-- disable redundant constraint warning for fake effect
{-# OPTIONS_GHC -fno-warn-redundant-constraints #-}

-- | Monocle simple effect system based on mtl and PandocMonad
module Monocle.Class where

import Control.Concurrent (threadDelay)
import Control.Retry (RetryPolicyM, RetryStatus (..))
import Control.Retry qualified as Retry
import Data.Time.Clock qualified (getCurrentTime)
import Monocle.Prelude
import Network.HTTP.Client (HttpException (..))
import Network.HTTP.Client qualified as HTTP

import Effectful (Dispatch (Static), DispatchOf)
import Effectful.Dispatch.Static (SideEffects (..), StaticRep, evalStaticRep)

import Effectful.Prometheus

runMonitoring :: IOE :> es => Eff (LoggerEffect : PrometheusEffect : TimeEffect : RetryEffect : es) a -> Eff es a
runMonitoring = runRetry . runTime . runPrometheus . runLoggerEffect

-------------------------------------------------------------------------------
-- A time system

data TimeEffect :: Effect
type instance DispatchOf TimeEffect = 'Static 'WithSideEffects
data instance StaticRep TimeEffect = TimeEffect
runTime :: IOE :> es => Eff (TimeEffect : es) a -> Eff es a
runTime = evalStaticRep TimeEffect

mGetCurrentTime :: TimeEffect :> es => Eff es UTCTime
mGetCurrentTime = unsafeEff_ Data.Time.Clock.getCurrentTime

mThreadDelay :: TimeEffect :> es => Int -> Eff es ()
mThreadDelay = unsafeEff_ . threadDelay

holdOnUntil :: TimeEffect :> es => UTCTime -> Eff es ()
holdOnUntil resetTime = do
  currentTime <- mGetCurrentTime
  let delaySec = diffTimeSec resetTime currentTime + 1
  mThreadDelay $ delaySec * 1_000_000

-------------------------------------------------------------------------------
-- A network retry system

data RetryEffect :: Effect

type instance DispatchOf RetryEffect = 'Static 'WithSideEffects
data instance StaticRep RetryEffect = RetryEffect

runRetry :: IOE :> es => Eff (RetryEffect : es) a -> Eff es a
runRetry = evalStaticRep RetryEffect

retry ::
  forall es a.
  (RetryEffect :> es) =>
  "policy" ::: RetryPolicyM (Eff es) ->
  "handler" ::: (RetryStatus -> Handler (Eff es) Bool) ->
  "action" ::: (Int -> Eff es a) ->
  Eff es a
retry (Retry.RetryPolicyM policy) handler action =
  unsafeEff $ \env ->
    let actionIO :: RetryStatus -> IO a
        actionIO (RetryStatus num _ _) = unEff (action num) env
        policyIO :: RetryPolicyM IO
        policyIO = Retry.RetryPolicyM $ \s -> unEff (policy s) env
        convertHandler :: Handler (Eff es) Bool -> Handler IO Bool
        convertHandler (Handler handlerEff) =
          Handler $ \e -> unEff (handlerEff e) env
        handlerIO :: RetryStatus -> Handler IO Bool
        handlerIO s = convertHandler (handler s)
     in Retry.recovering policyIO [handlerIO] actionIO

retryLimit :: Int
retryLimit = 7

counterT :: Int -> Int -> Text
counterT count max' = show count <> "/" <> show max'

-- | Retry HTTP network action, doubling backoff each time
httpRetry :: (HasCallStack, [PrometheusEffect, RetryEffect, LoggerEffect] :>> es) => Text -> Eff es a -> Eff es a
httpRetry urlLabel baseAction = retry policy httpHandler (const action)
 where
  modName = case getCallStack callStack of
    ((_, srcLoc) : _) -> from (srcLocModule srcLoc)
    _ -> "N/C"
  label = (modName, urlLabel)

  backoff = 500000 -- 500ms
  policy = Retry.exponentialBackoff backoff <> Retry.limitRetries retryLimit
  action = do
    res <- baseAction
    promIncrCounter httpRequestCounter label
    pure res
  httpHandler (RetryStatus num _ _) = Handler $ \case
    HttpExceptionRequest req ctx -> do
      let url = decodeUtf8 @Text $ HTTP.host req <> ":" <> show (HTTP.port req) <> HTTP.path req
          arg = decodeUtf8 $ HTTP.queryString req
          loc = if num == 0 then url <> arg else url
      logWarn "network error" ["count" .= num, "limit" .= retryLimit, "loc" .= loc, "failed" .= show @Text ctx]
      promIncrCounter httpFailureCounter label
      pure True
    InvalidUrlException _ _ -> pure False

-- | A retry helper with a constant policy. This helper is in charge of low level logging
-- and TODO: incrementCounter for graphql request and errors
constantRetry :: [LoggerEffect, RetryEffect] :>> es => Text -> Handler (Eff es) Bool -> (Int -> Eff es a) -> Eff es a
constantRetry msg handler baseAction = retry policy (const handler) action
 where
  delay = 1_100_000 -- 1.1 seconds
  policy = Retry.constantDelay delay <> Retry.limitRetries retryLimit
  action num = do
    when (num > 0) $
      logWarn "Retry failed" ["num" .= num, "max" .= retryLimit, "msg" .= msg]
    baseAction num
