module KeyHandlers where

import Prelude
import Config (UIST, UIConf)
import Control.Monad.Eff (Eff)
import Control.Monad.ST (ST, STRef, readSTRef, modifySTRef)
import DOM (DOM)
import Data.Maybe.Unsafe (fromJust)
import Data.StrMap (insert, member, lookup)
import Graphics.Canvas (Canvas)

-- converts key codes into command sequences
type KeyHandler = forall eff h. STRef h UIConf -> STRef h UIST -> String -> Eff (canvas :: Canvas, dom :: DOM, st :: ST h | eff) String

keyHandler :: KeyHandler
keyHandler ucRef usRef char = do
  uiConf <- readSTRef ucRef

  --let x = lg char
  case uiConf.keySet of
    "dev"  -> devKeyHandler ucRef usRef char
    "prod" -> prodKeyHandler ucRef usRef char
    _      -> commonKeyHandler ucRef usRef char


devKeyHandler :: KeyHandler
devKeyHandler ucRef usRef char = do
  uiConf <- readSTRef ucRef
  uiST   <- readSTRef usRef

  case char of
    "1" -> do
      inc uiConf uiST "Sub" "main.main_body.t" "t_inner" "t_inner" "vec2" 1
    "Q" -> do
      inc uiConf uiST "Sub" "main.main_body.t" "t_inner" "t_inner" "vec2" (-1)
    "2" -> do
      inc uiConf uiST "Mod" "disp" "post" "post_hlim" "vec4" 1
    "W" -> do
      inc uiConf uiST "Mod" "disp" "post" "post_hlim" "vec4" (-1)
    "3" -> do
      inc uiConf uiST "Image" "main.main_body.seed" "0" "basic_images" "vec4" 1
    "E" -> do
      inc uiConf uiST "Image" "main.main_body.seed" "0" "basic_images" "vec4" (-1)
    _   -> commonKeyHandler ucRef usRef char
  where
    inc uiConf uiST typ addr sub lib dim ofs = do
      let idn' = addr ++ sub
      let idx = if (member idn' uiST.incIdx) then ((fromJust $ lookup idn' uiST.incIdx) + ofs) else 0
      let dt = insert idn' idx uiST.incIdx
      modifySTRef usRef (\s -> s {incIdx = dt})
      let spd = show uiConf.keyboardSwitchSpd
      return $ "scr inc" ++ typ ++ " " ++  addr ++ " sub:" ++ sub ++ " lib:" ++ lib ++ " dim:" ++ dim ++ " idx:" ++ (show idx) ++ " spd:" ++ spd

prodKeyHandler :: KeyHandler
prodKeyHandler ucRef usRef char = do
  uiConf <- readSTRef ucRef
  uiST   <- readSTRef usRef

  case char of
    _ -> commonKeyHandler ucRef usRef char

commonKeyHandler :: KeyHandler
commonKeyHandler ucRef usRef char = do
  uiConf <- readSTRef ucRef
  uiST   <- readSTRef usRef

  case char of
    "~"  -> return "dev"
    "|"  -> return "showFps"
    "\\" -> return "clear"
    " "  -> return "save"
    _    -> return "null"