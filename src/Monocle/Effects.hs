{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeFamilies #-}
-- for MTL Compat
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -fno-warn-unused-imports #-}

-- | This module demonstrates how the static reader based effect
-- provided by the effectful library can be used to replace the
-- current mtl style solution.
--
-- The goals are:
--
-- - Remove the `instance HasLogger Api` and `instance HasLogger Lentille` boilerplate.
--   The effects should be usable and general purpose.
-- - Enable using multiple reader so that effect can easily have an environment.
--   This removes the needs for `AppEnv.aEnv.glLogger` and `QueryEnv.tEnv.glLogger`
-- - Keep IO out of the main module, the signature should indicate precisely what are
--   the necessary effects. E.g. crawler shall not be able to access elastic.
--
-- Design:
--
-- The effect are implemented using the familiar `ReaderT env IO` but using a StaticRep and 'unsafeEff' to liftIO.
-- The downside is that dynamic implementation, e.g. for testing, is presently not possible.
--
-- If approved, then the inidivual effect should be sperated in multiple modules for
-- better re-usability.
--
-- Note: [Monocle Effects]
--
-- Monocle uses effectful to implement a simple effect system.
-- An effect is composed of an environment data type and associated
-- functions.
--
-- Effectful uses an extensible record indexed by types of kind Effect.
-- This list is represented as a type variable, usually named `es`
--
-- * Effect constraints
--
-- Effect can be added as a contraints using the `:>` operator:
--
--   `LoggerEffect :> es` meanst that the es list contains the Effect.
--
-- * Effect execution
--
-- Effect can be executed using a run* function to remove the effect from the list.
--
module Monocle.Effects where

import Control.Retry (RetryStatus (..))
import Control.Retry qualified as Retry

import Data.Aeson (Series, pairs)
import Data.Aeson.Encoding (encodingToLazyByteString)
import Monocle.Prelude hiding (Reader, ask, local)
import System.Log.FastLogger qualified as FastLogger

import Control.Exception (throwIO, try)
import Monocle.Client qualified
import Network.HTTP.Client (HttpException (..))
import Network.HTTP.Client qualified as HTTP

import Effectful
import Effectful.Dispatch.Static (SideEffects (..), StaticRep, evalStaticRep, getStaticRep, localStaticRep)
import Effectful.Dispatch.Static.Primitive qualified as EffStatic

import Monocle.Logging hiding (logInfo, withContext)

import Monocle.Config (ConfigStatus)
import Monocle.Config qualified

import Control.Exception (finally)
import GHC.IO.Handle (hClose)
import System.Directory
import System.Posix.Temp (mkstemp)
import Test.Tasty
import Test.Tasty.HUnit

import Network.Wai.Handler.Warp qualified as Warp
import Servant (Get, (:<|>))
import Servant qualified

import Data.Vector qualified as V
import Database.Bloodhound qualified as BH
import Database.Bloodhound.Raw qualified as BHR
import Json.Extras qualified as Json

-- for MonoQueryEffect
import Monocle.Env (AppEnv, QueryEnv (..))
import Monocle.Env qualified
import Monocle.Search.Query qualified as SearchQuery
import Monocle.Search.Syntax (Expr)

import Effectful qualified as E
import Effectful.Error.Static qualified as E
import Effectful.Fail qualified as E
import Effectful.Reader.Static qualified as E
import Effectful.Servant qualified as ES

-- the servant api
type ApiEffects es = [IOE, E.Reader AppEnv, E.Error Servant.ServerError, MonoConfigEffect, LoggerEffect, ElasticEffect, E.Fail] :>> es

type IndexEffects es = [ElasticEffect, LoggerEffect] :>> es

-- the query handler
type QEffects es = [ElasticEffect, LoggerEffect, MonoQueryEffect] :>> es

type TestEffects es = (E.Fail :> es, IOE :> es, QEffects es)

testTree :: TestTree
testTree =
  testGroup
    "Monocle.Effects"
    [ testCase "LoggerEffect" do
        runEff $ runLoggerEffect do
          logInfo "logInfo prints!" []
    , testCase "MonoConfig" do
        (path, fd) <- mkstemp "/tmp/monoconfig-test"
        hClose fd
        writeFile path "workspaces: []"
        setEnv "CRAWLERS_API_KEY" "42"
        runEff (runMonoConfig path $ testMonoConfig path) `finally` removeFile path
    ]
 where
  testEff a b = liftIO (a @?= b)
  testMonoConfig :: [MonoConfigEffect, IOE] :>> es => FilePath -> Eff es ()
  testMonoConfig fp = do
    -- Setup the test config
    let getNames c = Monocle.Config.getWorkspaceName <$> Monocle.Config.getWorkspaces (Monocle.Config.csConfig c)

    -- initial load
    do
      config <- getReloadConfig
      Monocle.Config.csReloaded config `testEff` False
      getNames config `testEff` []

    -- test reload works
    do
      liftIO do writeFile fp "workspaces:\n- name: test\n  crawlers: []"
      config <- getReloadConfig
      Monocle.Config.csReloaded config `testEff` True
      getNames config `testEff` ["test"]

    -- make sure reload is avoided when the file doesn't change
    do
      config <- getReloadConfig
      Monocle.Config.csReloaded config `testEff` False

-- | MTL Compat
instance IOE :> es => MonadMonitor (Eff es) where
  doIO = liftIO

------------------------------------------------------------------
--

-- | Config effect to load and reload the local config

------------------------------------------------------------------

-- | The effect environment
type MonoConfigEnv = IO ConfigStatus

-- | The effect definition using static rep.
data MonoConfigEffect :: Effect

type instance DispatchOf MonoConfigEffect = 'Static 'WithSideEffects
newtype instance StaticRep MonoConfigEffect = MonoConfigEffect MonoConfigEnv

-- | Run the effect (e.g. removes it from the list)
runMonoConfig :: IOE :> es => FilePath -> Eff (MonoConfigEffect : es) a -> Eff es a
runMonoConfig fp action = do
  (mkReload :: IO ConfigStatus) <- unsafeEff_ (Monocle.Config.reloadConfig fp)
  evalStaticRep (MonoConfigEffect mkReload) action

runMonoConfigFromEnv :: IOE :> es => IO ConfigStatus -> Eff (MonoConfigEffect : es) a -> Eff es a
runMonoConfigFromEnv reload action = evalStaticRep (MonoConfigEffect reload) action

-- | The lifted version of Monocle.Config.reloadConfig
getReloadConfig :: MonoConfigEffect :> es => Eff es ConfigStatus
getReloadConfig = do
  MonoConfigEffect reload <- getStaticRep
  unsafeEff_ reload

------------------------------------------------------------------
--

-- | Query effects

------------------------------------------------------------------
data MonoQueryEnv = MonoQueryEnv
  { queryTarget :: Monocle.Env.QueryTarget
  , searchQuery :: SearchQuery.Query
  }

data MonoQueryEffect :: Effect
type instance DispatchOf MonoQueryEffect = 'Static 'NoSideEffects
newtype instance StaticRep MonoQueryEffect = MonoQueryEffect MonoQueryEnv

runMonoQuery :: MonoQueryEnv -> Eff (MonoQueryEffect : es) a -> Eff es a
runMonoQuery env = evalStaticRep (MonoQueryEffect env)

runMonoQueryWorkSpace :: Monocle.Config.Index -> SearchQuery.Query -> Eff (MonoQueryEffect : es) a -> Eff es a
runMonoQueryWorkSpace ws query = evalStaticRep (MonoQueryEffect $ MonoQueryEnv target query)
 where
  target = Monocle.Env.QueryWorkspace ws

runEmptyMonoQuery :: Monocle.Config.Index -> Eff (MonoQueryEffect : es) a -> Eff es a
runEmptyMonoQuery ws = runMonoQueryWorkSpace ws query
 where
  query = Monocle.Env.mkQuery []

localSearchQuery :: MonoQueryEffect :> es => (SearchQuery.Query -> SearchQuery.Query) -> Eff es a -> Eff es a
localSearchQuery changeQuery = localStaticRep updateRep
 where
  updateRep (MonoQueryEffect env) = MonoQueryEffect (env {searchQuery = changeQuery (env.searchQuery)})

localQueryTarget :: MonoQueryEffect :> es => Monocle.Env.QueryTarget -> Eff es a -> Eff es a
localQueryTarget localTarget = localStaticRep updateRep
 where
  updateRep (MonoQueryEffect env) = MonoQueryEffect (env {queryTarget = localTarget})

withQuery :: MonoQueryEffect :> es => SearchQuery.Query -> Eff es a -> Eff es a
withQuery query = localSearchQuery (const query)

-- | 'withFlavor' change the query flavor
withFlavor :: MonoQueryEffect :> es => SearchQuery.QueryFlavor -> Eff es a -> Eff es a
withFlavor flavor = localSearchQuery setFlavor
 where
  -- the new flavor replaces the oldFlavor
  setFlavor query =
    let newQueryGet modifier oldFlavor = SearchQuery.queryGet query modifier (Just $ fromMaybe flavor oldFlavor)
     in query {SearchQuery.queryGet = newQueryGet}

-- | 'withFilter' run a queryM with extra queries.
-- Use it to mappend bloodhound expression to the final result
withFilter :: MonoQueryEffect :> es => [BH.Query] -> Eff es a -> Eff es a
withFilter = localSearchQuery . addFilter

-- | 'withFilterFlavor' run a queryM with extra queries provided based on the current query flavor.
-- This is used in monoHisto where the extra bounds need to take into account the query flavor,
-- e.g. firstComment metrics uses
withFilterFlavor :: MonoQueryEffect :> es => (Maybe SearchQuery.QueryFlavor -> [BH.Query]) -> Eff es a -> Eff es a
withFilterFlavor extraQueries = localSearchQuery addModifier
 where
  addModifier query =
    let newQueryGet modifier qf = extraQueries qf <> SearchQuery.queryGet query modifier qf
     in query {SearchQuery.queryGet = newQueryGet}

-- | 'withModified' run a queryM with a modified query
-- Use it to remove or change field from the initial expr, for example to drop dates.
withModified :: MonoQueryEffect :> es => (Maybe Expr -> Maybe Expr) -> Eff es a -> Eff es a
withModified modifier = localSearchQuery addModifier
 where
  -- The new modifier is composed with the previous one
  addModifier query =
    let newQueryGet oldModifier = SearchQuery.queryGet query (modifier . oldModifier)
     in query {SearchQuery.queryGet = newQueryGet}

-- | Add extra queires to a QueryEnv
-- Extra queries are added to the resulting [BH.Query]
addFilter :: [BH.Query] -> SearchQuery.Query -> SearchQuery.Query
addFilter extraQueries query =
  let newQueryGet modifier qf = extraQueries <> SearchQuery.queryGet query modifier qf
   in query {SearchQuery.queryGet = newQueryGet}

-- | 'dropQuery' remove the query from the context
dropQuery :: MonoQueryEffect :> es => Eff es a -> Eff es a
dropQuery = localSearchQuery dropQuery'
 where
  -- we still want to call the provided modifier, so
  -- the expr is removed by discarding the modifier parameter
  dropQuery' query =
    let newQueryGet modifier = SearchQuery.queryGet query (const $ modifier Nothing)
     in query {SearchQuery.queryGet = newQueryGet}

getQueryTarget :: MonoQueryEffect :> es => Eff es Monocle.Env.QueryTarget
getQueryTarget = do
  MonoQueryEffect env <- getStaticRep
  pure env.queryTarget

getIndexName' :: MonoQueryEffect :> es => Eff es BH.IndexName
getIndexName' = do
  MonoQueryEffect env <- getStaticRep
  pure $ Monocle.Env.envToIndexName (queryTarget env)

getIndexConfig' :: MonoQueryEffect :> es => Eff es Monocle.Config.Index
getIndexConfig' = do
  MonoQueryEffect env <- getStaticRep
  pure $ case queryTarget env of
    Monocle.Env.QueryWorkspace ws -> ws
    _ -> error "Config has no index config"

getQueryBH :: MonoQueryEffect :> es => Eff es (Maybe BH.Query)
getQueryBH = do
  MonoQueryEffect env <- getStaticRep
  pure $ Monocle.Env.mkFinalQuery' Nothing env.searchQuery

getQueryBound :: MonoQueryEffect :> es => Eff es (UTCTime, UTCTime)
getQueryBound = do
  MonoQueryEffect env <- getStaticRep
  pure $ SearchQuery.queryBounds env.searchQuery

------------------------------------------------------------------
--

-- | Elastic Effect to access elastic backend. TODO: make it use the HttpEffect retry capability.

------------------------------------------------------------------
type ElasticEnv = BH.BHEnv

data ElasticEffect :: Effect
type instance DispatchOf ElasticEffect = 'Static 'WithSideEffects
newtype instance StaticRep ElasticEffect = ElasticEffect ElasticEnv

runElasticEffect :: IOE :> es => BH.BHEnv -> Eff (ElasticEffect : es) a -> Eff es a
runElasticEffect bhEnv action = do
  -- bhEnv <- liftIO (BH.mkBHEnv <$> pure server <*> Monocle.Client.mkManager)
  evalStaticRep (ElasticEffect bhEnv) action

esSearch :: [ElasticEffect, LoggerEffect] :>> es => (ToJSON body, FromJSONField resp) => BH.IndexName -> body -> BHR.ScrollRequest -> Eff es (BH.SearchResult resp)
esSearch iname body scrollReq = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BHR.search iname body scrollReq

esAdvance :: [ElasticEffect, LoggerEffect] :>> es => FromJSON resp => BH.ScrollId -> Eff es (BH.SearchResult resp)
esAdvance scroll = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BHR.advance scroll

esGetDocument :: ElasticEffect :> es => BH.IndexName -> BH.DocId -> Eff es (HTTP.Response LByteString)
esGetDocument iname doc = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BH.getDocument iname doc

esCountByIndex :: ElasticEffect :> es => BH.IndexName -> BH.CountQuery -> Eff es (Either BH.EsError BH.CountResponse)
esCountByIndex iname q = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BH.countByIndex iname q

esSearchHit :: ElasticEffect :> es => ToJSON body => BH.IndexName -> body -> Eff es [Json.Value]
esSearchHit iname body = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BHR.searchHit iname body

esScanSearch :: ElasticEffect :> es => FromJSON body => BH.IndexName -> BH.Search -> Eff es [BH.Hit body]
esScanSearch iname search = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BH.scanSearch iname search


esDeleteByQuery :: ElasticEffect :> es => BH.IndexName -> BH.Query -> Eff es BH.Reply
esDeleteByQuery iname q = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BH.deleteByQuery iname q

esCreateIndex :: ElasticEffect :> es => BH.IndexSettings -> BH.IndexName -> Eff es ()
esCreateIndex is iname = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ void $ BH.runBH env $ BH.createIndex is iname

esIndexDocument :: ToJSON body => ElasticEffect :> es => BH.IndexName -> BH.IndexDocumentSettings -> body -> BH.DocId -> Eff es (HTTP.Response LByteString)
esIndexDocument indexName docSettings body docId = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BH.indexDocument indexName docSettings body docId

esPutMapping :: ElasticEffect :> es => ToJSON mapping => BH.IndexName -> mapping -> Eff es ()
esPutMapping iname mapping = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ void $ BH.runBH env $ BH.putMapping iname mapping

esIndexExists :: ElasticEffect :> es => BH.IndexName -> Eff es Bool
esIndexExists iname = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BH.indexExists iname

esDeleteIndex :: ElasticEffect :> es => BH.IndexName -> Eff es (HTTP.Response LByteString)
esDeleteIndex iname = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BH.deleteIndex iname

esSettings :: ElasticEffect :> es => ToJSON body => BH.IndexName -> body -> Eff es ()
esSettings iname body = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BHR.settings iname body

esRefreshIndex :: ElasticEffect :> es => BH.IndexName -> Eff es (HTTP.Response LByteString)
esRefreshIndex iname = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BH.refreshIndex iname

esDocumentExists :: ElasticEffect :> es => BH.IndexName -> BH.DocId -> Eff es Bool
esDocumentExists iname doc = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BH.documentExists iname doc

esBulk :: ElasticEffect :> es => V.Vector BulkOperation -> Eff es (BH.Reply)
esBulk ops = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BH.bulk ops

esUpdateDocument :: ElasticEffect :> es => ToJSON a => BH.IndexName -> BH.IndexDocumentSettings -> a -> DocId -> Eff es BH.Reply
esUpdateDocument iname ids body doc = do
  ElasticEffect env <- getStaticRep
  unsafeEff_ $ BH.runBH env $ BH.updateDocument iname ids body doc

-- Legacy wrappers
esSearchLegacy :: [LoggerEffect, ElasticEffect] :>> es => (FromJSON a) => BH.IndexName -> BH.Search -> Eff es (BH.SearchResult a)
esSearchLegacy indexName search = do
  ElasticEffect env <- getStaticRep
  (rawResp, resp) <- unsafeEff_ $ BH.runBH env do
    -- logText . decodeUtf8 . encode $ search
    rawResp <- BH.searchByIndex indexName search
    -- logText $ show rawResp
    (\resp -> (rawResp, resp)) <$> BH.parseEsResponse rawResp
  case resp of
    Left e -> handleError e rawResp
    Right x -> pure x
 where
  handleError resp rawResp = do
    logWarn' "Elastic response failed" ["status" .= BH.errorStatus resp, "message" .= BH.errorMessage resp]
    error $ "Elastic response failed: " <> show rawResp

------------------------------------------------------------------
--

-- | HTTP Effect that retries on exception

------------------------------------------------------------------
type HttpEnv = HTTP.Manager

data HttpEffect :: Effect
type instance DispatchOf HttpEffect = 'Static 'WithSideEffects
newtype instance StaticRep HttpEffect = HttpEffect HttpEnv

-- | 'runHttpEffect' simply add a Manager to the static rep env.
runHttpEffect :: IOE :> es => Eff (HttpEffect : es) a -> Eff es a
runHttpEffect action = do
  ctx <- liftIO Monocle.Client.mkManager
  evalStaticRep (HttpEffect ctx) action

-- | 'httpRequest' catches http exception and retries the requests.
httpRequest ::
  [LoggerEffect, HttpEffect] :>> es =>
  HTTP.Request ->
  Eff es (Either HTTP.HttpExceptionContent (HTTP.Response LByteString))
httpRequest req = do
  HttpEffect manager <- getStaticRep
  respE <- unsafeEff $ \env ->
    try $ Retry.recovering policy [httpHandler env] (const $ HTTP.httpLbs req manager)
  case respE of
    Right resp -> pure (Right resp)
    Left err -> case err of
      HttpExceptionRequest _ ctx -> pure (Left ctx)
      _ -> unsafeEff_ (throwIO err)
 where
  retryLimit = 2
  backoff = 500000 -- 500ms
  policy = Retry.exponentialBackoff backoff <> Retry.limitRetries retryLimit
  httpHandler :: LoggerEffect :> es => EffStatic.Env es -> RetryStatus -> Handler IO Bool
  httpHandler env (RetryStatus num _ _) = Handler $ \case
    HttpExceptionRequest _req ctx -> do
      let url = decodeUtf8 @Text $ HTTP.host req <> ":" <> show (HTTP.port req) <> HTTP.path req
          arg = decodeUtf8 $ HTTP.queryString req
          loc = if num == 0 then url <> arg else url
      flip unEff env $
        logInfo
          "network error"
          [ "count" .= num
          , "limit" .= retryLimit
          , "loc" .= loc
          , "error" .= show @Text ctx
          ]
      pure True
    InvalidUrlException _ _ -> pure False

------------------------------------------------------------------
--

-- | Logging effect based on the current Monocle.Logging.HasEffect

------------------------------------------------------------------

type LoggerEnv = Logger

data LoggerEffect :: Effect
type instance DispatchOf LoggerEffect = 'Static 'WithSideEffects
newtype instance StaticRep LoggerEffect = LoggerEffect LoggerEnv

runLoggerEffect :: IOE :> es => Eff (LoggerEffect : es) a -> Eff es a
runLoggerEffect action =
  -- `withEffToIO` and `unInIO` enables calling IO function like: `(Logger -> IO a) -> IO a`.
  withEffToIO $ \runInIO ->
    withLogger \logger ->
      runInIO $ evalStaticRep (LoggerEffect logger) action

withContext :: LoggerEffect :> es => Series -> Eff es a -> Eff es a
withContext ctx = localStaticRep $ \(LoggerEffect (Logger prevCtx logger)) -> LoggerEffect (Logger (ctx <> prevCtx) logger)

doLog :: LoggerEffect :> es => LogLevel -> ByteString -> Text -> [Series] -> Eff es ()
doLog lvl loc msg attrs = do
  LoggerEffect (Logger ctx logger) <- getStaticRep
  let body :: ByteString
      body = case from . encodingToLazyByteString . pairs . mappend ctx . mconcat $ attrs of
        "{}" -> mempty
        x -> " " <> x
  -- `unsafeEff_` is equivalent to `liftIO`
  unsafeEff_ $ logger (\time -> FastLogger.toLogStr $ time <> msgText <> body <> "\n")
 where
  msgText :: ByteString
  msgText = from lvl <> loc <> ": " <> encodeUtf8 msg

logInfo :: (HasCallStack, LoggerEffect :> es) => Text -> [Series] -> Eff es ()
logInfo = doLog LogInfo getLocName

logWarn' :: (HasCallStack, LoggerEffect :> es) => Text -> [Series] -> Eff es ()
logWarn' = doLog LogWarning getLocName

------------------------------------------------------------------
--

-- | Demonstrate Servant.Handler implemented with Eff

------------------------------------------------------------------

type TestApi =
  "route1" Servant.:> Get '[Servant.JSON] Natural
    :<|> "route2" Servant.:> Get '[Servant.JSON] Natural

type ApiEffects' es = [IOE, LoggerEffect] :>> es

-- | serverEff is the effectful implementation of the TestAPI
serverEff' :: forall es. ApiEffects' es => Servant.ServerT TestApi (Eff es)
serverEff' = route1Handler Servant.:<|> route1Handler
 where
  route1Handler :: Eff es Natural
  route1Handler = do
    logInfo "Handling route" []
    pure 42

-- | liftServer convert the effectful implementation to the Handler context.
-- It is necessary to pass each effect environment so that the effects can be interpret for each request.
liftServer :: forall es. ApiEffects' es => EffStatic.Env es -> Servant.ServerT TestApi Servant.Handler
liftServer es = Servant.hoistServer (Proxy @TestApi) interpretServer serverEff'
 where
  interpretServer :: Eff es a -> Servant.Handler a
  interpretServer action = do
    liftIO do
      es' <- EffStatic.cloneEnv es
      unEff action es'

demo, demoServant, demoTest, demoCrawler :: IO ()
demo = demoMultiEffects
demoTest = defaultMain testTree
demoServant =
  runEff $ runLoggerEffect do
    unsafeEff $ \es ->
      Warp.run 8080 $ Servant.serve (Proxy @TestApi) $ liftServer es
demoCrawler = runEff $ runLoggerEffect $ runHttpEffect $ crawlerDemo

type CrawlerEffect' es = [IOE, HttpEffect, LoggerEffect] :>> es

crawlerDemo :: CrawlerEffect' es => Eff es ()
crawlerDemo = withContext ("crawler" .= ("crawler-name" :: Text)) do
  logInfo "Starting crawler" []
  res <- httpRequest =<< HTTP.parseUrlThrow "http://localhost"
  logInfo ("Got: " <> show res) []

demoMultiEffects :: IO ()
demoMultiEffects = do
  runEff $ E.runFailIO $ runLoggerEffect do
    loggerDemo
    subDemo

loggerDemo :: LoggerEffect :> es => Eff es ()
loggerDemo = logInfo "Hello effectful" []

subDemo :: E.Fail :> es => Eff es ()
subDemo = fail "Toto"
