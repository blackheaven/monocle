{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE NoImplicitPrelude #-}

-- | The Monocle API HTTP type and servant
module Monocle.Api.HTTP (MonocleAPI, server) where

import Data.Aeson (ToJSON)
import qualified Database.Bloodhound as BH
import qualified Monocle.Api.Config as Config
import Monocle.Api.PBJSON (PBJSON)
import Monocle.Api.Server (searchChangeQuery, searchFields)
import Monocle.Search (ChangesQueryRequest, ChangesQueryResponse, FieldsRequest, FieldsResponse)
import Relude
import Servant

type MonocleAPI =
  "indices" :> Get '[JSON] [Text]
    :<|> "infos" :> Get '[JSON] Info
    :<|> "api" :> "2" :> "search" :> "changes" :> ReqBody '[JSON] ChangesQueryRequest :> Post '[PBJSON, JSON] ChangesQueryResponse
    :<|> "api" :> "2" :> "search_fields" :> ReqBody '[JSON] FieldsRequest :> Post '[PBJSON, JSON] FieldsResponse

newtype Info = Info
  { version :: String
  }
  deriving (Eq, Show, Generic)

instance ToJSON Info

info :: Info
info = Info "1.0.0"

server :: [Config.Tenant] -> BH.BHEnv -> Server MonocleAPI
server tenants bhEnv =
  return (map Config.unTenant tenants)
    :<|> return info
    :<|> (searchChangeQuery bhEnv)
    :<|> (searchFields)