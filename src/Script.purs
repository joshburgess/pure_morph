module Script where

import Prelude
import Data.Array (index, length, elemIndex, foldM, updateAt) as A
import Data.Complex
import Data.Either (Either(..))
import Data.Foldable (or)
import Data.Maybe
import Data.StrMap (StrMap, keys, lookup, insert, fromFoldable, union, member, delete)
import Data.String (trim)
import Data.Tuple (Tuple(..))
import Data.Traversable (traverse)
import Control.Monad (unless)
import Control.Monad.ST
import Control.Monad.Error.Class (throwError)
import Control.Monad.Except.Trans (lift)

import Config
import System (loadLib)
import Util (lg, tLg, numFromStringE, intFromStringE, gmod, rndstr)
import Pattern (purgeScript, replaceModule, importScript, flagFamily, findParent)

-- PUBLIC

-- execute all scripts & script pool
runScripts :: forall eff h. STRef h (SystemST h) -> EpiS eff h Boolean
runScripts ssRef = do
  systemST <- lift $ readSTRef ssRef
  res <- traverse (handle ssRef) (keys systemST.scriptRefPool)
  return $ or res
  where
    handle :: forall eff h. STRef h (SystemST h) -> String -> EpiS eff h Boolean
    handle ssRef n = do
      systemST <- lift $ readSTRef ssRef
      case (member n systemST.scriptRefPool) of
        true -> do
          sRef <- loadLib n systemST.scriptRefPool "runScripts"
          scr <- lift $ readSTRef sRef
          fn <- lookupScriptFN scr.fn
          let t' = systemST.t - scr.tPhase
          case scr.mid of
            Nothing -> throwError $ "No module when running script: " ++ scr.fn
            Just mid -> fn ssRef n t' mid sRef
        false -> do
          let g = lg "script removed" -- ghetto
          return false

-- SCRIPT FUNCTIONS

-- dont do anything.  is this necessary?
nullS :: forall eff h. ScriptFn eff h
nullS ssRef self t mid sRef = do
  return false


-- move par[par] around on a path
ppath :: forall eff h. ScriptFn eff h
ppath ssRef self t mid sRef = do
  systemST <- lift $ readSTRef ssRef
  scr <- lift $ readSTRef sRef
  let dt = scr.dt

  -- get data
  spd <- (loadLib "spd" dt "ppath spd") >>= numFromStringE
  par <-  loadLib "par" dt "ppath par"
  pathN <- loadLib "path" dt "ppath path"
  mRef <- loadLib mid systemST.moduleRefPool "ppath module"
  m <- lift $ readSTRef mRef

  -- lookup path function
  fn <- case pathN of
    "linear" -> return $ \t -> t
    _ -> throwError $ "Unknown par path : " ++ pathN

  -- execute
  let val = fn (t * spd)

  -- modify data
  let par' = insert par val m.par
  lift $ modifySTRef mRef (\m -> m {par = par'})

  return false


-- move zn[idx] around on a path
zpath :: forall eff h. ScriptFn eff h
zpath ssRef self t mid sRef = do
  systemST <- lift $ readSTRef ssRef
  scr <- lift $ readSTRef sRef
  let dt = scr.dt

  -- get data
  spd <- (loadLib "spd" dt "zpath spd") >>= numFromStringE
  idx <- (loadLib "idx" dt "zpath idx") >>= intFromStringE
  pathN <- loadLib "path" dt "zpath path"
  mRef <- loadLib mid systemST.moduleRefPool "zpath module"
  m <- lift $ readSTRef mRef

  -- lookup path function
  fn <- case pathN of
    "rlin" -> return $ \t ->
      outCartesian $ Cartesian t 0.0
    "circle" -> return $ \t ->
      outPolar $ Polar t 1.0
    _ -> throwError $ "Unknown z path : " ++ pathN

  -- execute
  let z' = fn (t * spd)

  -- modify data
  case (A.updateAt idx z' m.zn) of
    (Just zn') -> lift $ modifySTRef mRef (\m -> m {zn = zn'})
    _ -> throwError $ "zn idx out of bound : " ++ (show idx) ++ " : in zpath"

  return false


-- increment a substitution by looking through the index
incStd :: forall eff h. ScriptFn eff h
incStd ssRef self t mid sRef = do
  systemST <- lift $ readSTRef ssRef
  scr <- lift $ readSTRef sRef
  let dt = scr.dt

  -- get data
  idx   <- (loadLib "idx" dt "incStd idx") >>= intFromStringE
  spd   <- (loadLib "spd" dt "incStd spd") >>= numFromStringE
  subN  <- loadLib "sub" dt "incStd sub"
  dim   <- loadLib "dim" dt "incStd dim"
  lib   <- loadLib "lib" dt "incStd lib"

  -- index & next data
  let index = flagFamily systemST.moduleLib $ fromFoldable [(Tuple "family" subN), (Tuple lib "true")]

  let nxtPos = idx `gmod` (A.length index)

  m1 <- case (A.index index nxtPos) of
    Nothing -> throwError $ "your index doesnt exist"
    Just v -> return v

  switchModules ssRef mid subN m1 dim spd t

  -- remove self
  purgeScript ssRef self

  return true


switchModules :: forall eff h. STRef h (SystemST h) -> String -> String -> String -> String -> Number -> Number -> EpiS eff h Unit
switchModules ssRef mid subN m1 dim spd t = do
  systemST <- lift $ readSTRef ssRef
  mRef  <- loadLib mid systemST.moduleRefPool "incStd module"
  m     <- lift $ readSTRef mRef
  m0    <- loadLib subN m.modules "incStd find sub"
  m0Ref <- loadLib m0 systemST.moduleRefPool "incStd m0"
  m0M   <- lift $ readSTRef m0Ref

  let x = lg m0

  -- create switch module
  switch <- loadLib "smooth_switch" systemST.moduleLib "switchModules"
  let modules = fromFoldable [(Tuple "m0" m0), (Tuple "m1" m1)]
  let sub'    = union (fromFoldable [(Tuple "dim" dim), (Tuple "var" m0M.var)]) switch.sub
  let switch' = switch {sub = sub', modules = modules, var = m0M.var}

  swid <- replaceModule ssRef mid subN m0 (Left switch')

  -- create & import blending script
  createScript ssRef swid "default" "finishSwitch" $ fromFoldable [(Tuple "spd" (show spd))]
  createScript ssRef swid "default" "ppath" $ fromFoldable [(Tuple "par" "intrp"), (Tuple "path" "linear"), (Tuple "spd" (show spd))]

  return unit


finishSwitch :: forall eff h. ScriptFn eff h
finishSwitch ssRef self t mid sRef = do
  systemST <- lift $ readSTRef ssRef
  scr <- lift $ readSTRef sRef
  let dt = scr.dt

  -- get data
  spd  <- (loadLib "spd" dt "finishSwitch spd") >>= numFromStringE

  case t * spd of
    -- we're done
    x | x >= 1.0 -> do
      let a = lg "DONE SWITCHING"

      -- find parent & m1
      (Tuple parent subN) <- findParent systemST.moduleRefPool mid
      mRef   <- loadLib mid systemST.moduleRefPool "finishSwitch module"
      m      <- lift $ readSTRef mRef
      m1     <- loadLib "m1" m.modules "finishSwitch module"

      -- replace.  this removes all scripts wrt this as well
      replaceModule ssRef parent subN mid (Right m1)

      return true
    _ -> do
      return false


-- PRIVATE

-- find script fuction given name
lookupScriptFN :: forall eff h. String -> EpiS eff h (ScriptFn eff h)
lookupScriptFN n = case n of
  "null"   -> return nullS
  "ppath"  -> return ppath
  "zpath"  -> return zpath
  "incStd" -> return incStd
  "finishSwitch" -> return finishSwitch
  _       -> throwError $ "script function not found: " ++ n


-- create a script dynamically & import it
createScript :: forall eff h. STRef h (SystemST h) -> String -> String -> String -> StrMap String -> EpiS eff h String
createScript ssRef mid parent fn dt = do
  systemST <- lift $ readSTRef ssRef
  scr      <- loadLib parent systemST.scriptLib "create script"

  let scr' = scr {fn = fn, dt = union dt scr.dt}
  importScript ssRef (Left scr') mid
