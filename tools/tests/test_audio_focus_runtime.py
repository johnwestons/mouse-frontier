"""Audio focus changes preserve screen-recording sound on Android."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable")
class AudioFocusRuntimeTests(unittest.TestCase):
    def test_android_keeps_audio_playing_while_other_platforms_suspend_it(self) -> None:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().project_root = ROOT.as_posix()
        lua.execute(r'''
            package.path=project_root..'/?.lua;'..package.path
            local AudioRuntime=require("game.audio_runtime")

            local function checkPlatform(osName,shouldKeepAudio)
                love={system={getOS=function() return osName end}}
                local engine={suspended=false,playCount=0,updateCount=0,recoveryCount=0,interruptionCount=0}
                function engine:installGunPools() end
                function engine:shutdown() end
                function engine:suspend() self.suspended=true; return true end
                function engine:resume() self.suspended=false; return true end
                function engine:markAndroidOutputInterrupted() self.interruptionCount=self.interruptionCount+1; return true end
                function engine:recoverAndroidOutput() self.recoveryCount=self.recoveryCount+1; return true end
                function engine:update() if not self.suspended then self.updateCount=self.updateCount+1 end end
                function engine:playSfx() if not self.suspended then self.playCount=self.playCount+1 end end
                local Audio={new=function() return engine end}
                local runtime={state="game",scene="train",saveData={audio={
                    station="chill",musicVolume=.1,sfxVolume=.55,rainVolume=.2,
                    rainEnabled=true,musicPaused=false,musicMuted=false,
                }}}
                local ui={}
                local audioRuntime=AudioRuntime.new({runtime=runtime,ui=ui,catalog={},audio=Audio,audioCatalog={}})
                audioRuntime.initialize()
                audioRuntime.focus(false)
                assert(engine.suspended~=shouldKeepAudio,"unexpected focus-loss audio policy on "..osName)
                assert(engine.interruptionCount==(shouldKeepAudio and 1 or 0),"unexpected interruption tracking on "..osName)
                audioRuntime.update()
                audioRuntime.playSfx("menu")
                local expected=shouldKeepAudio and 1 or 0
                assert(engine.updateCount==expected and engine.playCount==expected,"unexpected playback on "..osName)
                audioRuntime.focus(true)
                assert(not engine.suspended,"focus gain left audio suspended on "..osName)
                assert(engine.recoveryCount==(shouldKeepAudio and 1 or 0),"unexpected output recovery on "..osName)
                audioRuntime.shutdown()
            end

            checkPlatform("Android",true)
            checkPlatform("Windows",false)
        ''')


if __name__ == "__main__":
    unittest.main()
