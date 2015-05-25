{-# LANGUAGE CPP #-}
module Network.Wai.Session.Map (mapStore, mapStore_) where

import Control.Monad
import Data.StateVar
import Data.ByteString (ByteString)
import Control.Monad.IO.Class (liftIO, MonadIO)
import Data.IORef
import Network.Wai.Session (Session, SessionStore, genSessionId)

import Data.Map (Map)
import qualified Data.Map as Map

-- | Simple session store based on threadsafe 'Data.IORef.IORef's and
-- 'Data.Map.Map'.  This only works if your application server remains
-- running (such as with warp).  All data is lost when the server
-- terminates (bad for CGI).
--
-- WARNING: This session is vulnerable to sidejacking,
-- use with TLS for security.
mapStore :: (Ord k, MonadIO m) =>
    IO ByteString
    -- ^ 'IO' action to generate unique session IDs
    -> IO (SessionStore m k v)
mapStore gen =
    liftM (mapStore' gen) (newThreadSafeStateVar Map.empty)
    where
    mapStore' _ ssv (Just k) = do
        m <- get ssv
        case Map.lookup k m of
            Just sv -> return (sessionFromMapStateVar sv, return k)
            -- Could not find key, so it's as if we were not sent one
            Nothing -> mapStore' (return k) ssv Nothing
    mapStore' genNewKey ssv Nothing = do
        newKey <- genNewKey
        sv <- newThreadSafeStateVar Map.empty
        ssv $~ Map.insert newKey sv
        return (sessionFromMapStateVar sv, return newKey)

-- | Store using simple session ID generator based on time and 'Data.Unique'
mapStore_ :: (Ord k, MonadIO m) => IO (SessionStore m k v)
mapStore_ = mapStore genSessionId

newThreadSafeStateVar :: a -> IO (StateVar a)
newThreadSafeStateVar a = do
    ref <- newIORef a
    return $ makeStateVar
        (atomicModifyIORef ref (\x -> (x,x)))
        (\x -> atomicModifyIORef ref (const (x,())))

#if MIN_VERSION_StateVar(1,1,0)
sessionFromMapStateVar :: (Ord k, MonadIO m) =>
    StateVar (Map k v) ->
#else
sessionFromMapStateVar :: (HasGetter sv, HasSetter sv, Ord k, MonadIO m) =>
    sv (Map k v) ->
#endif
    Session m k v
sessionFromMapStateVar sv = (
        (\k -> liftIO (Map.lookup k `liftM` get sv)),
        (\k v -> liftIO (sv $~ Map.insert k v))
    )
