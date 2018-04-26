{-# LANGUAGE GADTs, OverloadedStrings, InstanceSigs, TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances, MultiParamTypeClasses #-}
{-# LANGUAGE DataKinds, ScopedTypeVariables, Rank2Types #-}
-- | Provide HTTP primitives
module Network.Discord.Rest.HTTP
  ( JsonRequest(..)
  , R.ReqBodyJson(..)
  , R.NoReqBody(..)
  , baseUrl
  , fetch
  , makeRequest
  , (//)
  , (R./:)
  ) where

    import Data.Semigroup ((<>))

    import Control.Monad (when)
    import Data.Aeson
    import Data.ByteString.Char8 (pack, ByteString)
    import Data.Hashable
    import Data.Maybe (fromMaybe)
    import qualified Data.Text as T (pack)
    import qualified Network.HTTP.Req as R

    import Network.Discord.Rest.Prelude
    import Network.Discord.Types

    -- | The base url (Req) for API requests
    baseUrl :: R.Url 'R.Https
    baseUrl = R.https "discordapp.com" R./: "api" R./: apiVersion
      where apiVersion = "v6"

    -- | Construct base options with auth from Discord state
    baseRequestOptions :: MonadIO m => m Option
    baseRequestOptions = do
      a <- auth
      v <- version
      return $ R.header "Authorization" (pack . show $ a)
            <> R.header "User-Agent" (pack $ "DiscordBot (https://github.com/jano017/Discord.hs,"
                                          ++ v ++ ")")
    infixl 5 //
    (//) :: Show a => R.Url scheme -> a -> R.Url scheme
    url // part = url R./: (T.pack $ show part)

    type Option = R.Option 'R.Https

    -- | Represents an HTTP request made to an API that supplies a Json response
    data JsonRequest r where
      Delete ::  FromJSON r                => R.Url 'R.Https      -> Option -> JsonRequest r
      Get    ::  FromJSON r                => R.Url 'R.Https      -> Option -> JsonRequest r
      Patch  :: (FromJSON r, R.HttpBody a) => R.Url 'R.Https -> a -> Option -> JsonRequest r
      Post   :: (FromJSON r, R.HttpBody a) => R.Url 'R.Https -> a -> Option -> JsonRequest r
      Put    :: (FromJSON r, R.HttpBody a) => R.Url 'R.Https -> a -> Option -> JsonRequest r

    fetch :: (FromJSON r, MonadIO m) => JsonRequest r -> m (R.JsonResponse r)
    fetch (Delete url      opts) = R.req R.DELETE url R.NoReqBody R.jsonResponse =<< (<> opts) <$> baseRequestOptions
    fetch (Get    url      opts) = R.req R.GET    url R.NoReqBody R.jsonResponse =<< (<> opts) <$> baseRequestOptions
    fetch (Patch  url body opts) = R.req R.PATCH  url body        R.jsonResponse =<< (<> opts) <$> baseRequestOptions
    fetch (Post   url body opts) = R.req R.POST   url body        R.jsonResponse =<< (<> opts) <$> baseRequestOptions
    fetch (Put    url body opts) = R.req R.PUT    url body        R.jsonResponse =<< (<> opts) <$> baseRequestOptions

    makeRequest :: (FromJSON r, MonadIO m, DoFetch f r) 
      => f r -> JsonRequest r -> m r
    makeRequest req action = do
      waitRateLimit req
      resp <- fetch action
      when (parseHeader resp "X-RateLimit-Remaining" 1 < 1) $
        setRateLimit req $ parseHeader resp "X-RateLimit-Reset" 0
      return $ R.responseBody resp
      where
        parseHeader :: R.HttpResponse resp => resp -> ByteString -> Int -> Int
        parseHeader resp header def = fromMaybe def $ decodeStrict =<< R.responseHeader resp header

    instance Hashable (JsonRequest r) where
      hashWithSalt s (Delete url _)   = hashWithSalt s $ show url
      hashWithSalt s (Get    url _)   = hashWithSalt s $ show url
      hashWithSalt s (Patch  url _ _) = hashWithSalt s $ show url
      hashWithSalt s (Post   url _ _) = hashWithSalt s $ show url
      hashWithSalt s (Put    url _ _) = hashWithSalt s $ show url
    
    -- | Base implementation of DoFetch, allows arbitrary HTTP requests to be performed
    instance (FromJSON r) => DoFetch JsonRequest r where
      doFetch req = R.responseBody <$> fetch req
