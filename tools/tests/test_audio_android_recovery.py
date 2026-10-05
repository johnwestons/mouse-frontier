"""Android audio recovery recreates streams after recorder focus changes."""
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
class AndroidAudioRecoveryTests(unittest.TestCase):
    def test_native_disconnect_recovery_is_wired_into_android_build(self) -> None:
        patch = (ROOT / "mobile" / "android" / "openal-oboe-recovery.patch").read_text(encoding="utf-8")
        builder = (ROOT / "tools" / "build_android_apk.ps1").read_text(encoding="utf-8")
        self.assertIn("MOUSE_FRONTIER_OBOE_DISCONNECT_RECOVERY", patch)
        self.assertIn("onErrorAfterClose", patch)
        self.assertIn("ErrorDisconnected", patch)
        self.assertIn("Recovered Oboe output stream after disconnect", patch)
        self.assertIn("apply --check --ignore-whitespace", builder)

    def test_android_manifest_allows_screen_recorder_audio_capture(self) -> None:
        manifest = (ROOT / "mobile" / "android" / "AndroidManifest.xml").read_text(encoding="utf-8")
        self.assertIn('android:allowAudioPlaybackCapture="true"', manifest)

    def test_rebuilds_music_and_rain_streams_at_their_playback_positions(self) -> None:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().project_root = ROOT.as_posix()
        lua.execute(r'''
            package.path=project_root..'/?.lua;'..package.path
            local Audio=require("game.audio")
            local catalog={
                musicCategories={},sfxCategories={},
                canonicalMusicFiles=function(files) return files end,
                includeRain=function() return false end,
                shouldLoopMusic=function() return true end,
            }
            local filesystem={
                getInfo=function() return nil end,
                getDirectoryItems=function() return {} end,
            }
            local created={}
            local backend={}
            function backend.newSource(path,kind)
                local source={path=path,kind=kind,position=0,playing=false,released=false}
                function source:setVolume(value) self.volume=value end
                function source:setLooping(value) self.looping=value end
                function source:play() self.playing=true end
                function source:pause() self.playing=false end
                function source:stop() self.playing=false end
                function source:release() self.released=true end
                function source:isPlaying() return self.playing end
                function source:tell() return self.position end
                function source:seek(value) self.position=value end
                created[#created+1]=source
                return source
            end

            local audio=Audio.new({filesystem=filesystem,audio=backend,catalog=catalog})
            local oldMusic=backend.newSource("sounds/music/chill/track.ogg","stream")
            oldMusic.position=38.25; oldMusic.playing=true
            local oldRain=backend.newSource("sounds/soundEffects/rain/storm.ogg","stream")
            oldRain.position=12.5; oldRain.playing=true
            audio.music=oldMusic; audio.category="chill"; audio.nowPlaying=oldMusic.path
            audio.rain=oldRain; audio.rainPath=oldRain.path
            local settings={musicVolume=.3,musicMuted=false,musicPaused=false,rainVolume=.4,rainEnabled=true}

            audio:markAndroidOutputInterrupted()
            assert(oldMusic.playing and oldRain.playing,"recording interruption paused live playback")
            assert(audio:recoverAndroidOutput(settings),"Android output recovery failed")
            assert(audio.music~=oldMusic and audio.rain~=oldRain,"recovery reused stale source objects")
            assert(oldMusic.released and oldRain.released,"recovery did not release stale sources")
            assert(audio.music.path==oldMusic.path and audio.rain.path==oldRain.path,"recovery changed tracks")
            assert(audio.music.position==38.25 and audio.rain.position==12.5,"recovery lost playback positions")
            assert(audio.music.playing and audio.rain.playing,"recovered streams did not resume")
            assert(audio.music.volume==.3 and audio.rain.volume==.4,"recovered streams lost volume settings")
            assert(audio.music.looping and audio.rain.looping,"recovered streams lost looping settings")

            audio:shutdown()
        ''')


if __name__ == "__main__":
    unittest.main()
