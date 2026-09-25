"""Guard the scene-art memory lifecycle used on low-memory Android devices."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable")
class SceneAssetStreamingTests(unittest.TestCase):
    def test_inactive_battle_and_event_art_is_released(self) -> None:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + lua.globals().package.path
        lua.execute(r'''
            local Assets=require('game.assets')
            local EventUI=require('game.event_ui')
            local stream
            for index=1,100 do
                local name,value=debug.getupvalue(Assets.load,index)
                if not name then break end
                if name=='streamBattleAtlases' then stream=value; break end
            end
            assert(stream,'battle atlas streamer unavailable')
            local created={}
            local atlases=stream({{'WASTELAND'},{'FOREST'}},function(entry)
                local image={released=0,release=function(self) self.released=self.released+1 end}
                created[#created+1]=image
                return {image=image,name=entry[1]}
            end)
            assert(#created==0)
            assert(atlases[1].name=='WASTELAND' and atlases[1].name=='WASTELAND')
            assert(#created==1 and created[1].released==0)
            assert(atlases[2].name=='FOREST' and created[1].released==1)
            assert(rawget(atlases,1)==nil and rawget(atlases,2)~=nil)
            assert(atlases[1].name=='WASTELAND' and created[2].released==1)

            local eventCreated={}
            local art=EventUI.load(function(path)
                local image={path=path,released=0,release=function(self) self.released=self.released+1 end}
                eventCreated[#eventCreated+1]=image
                return image
            end)
            assert(#eventCreated==0 and art['unknown']==nil)
            assert(art['story-a']==art['story-a'] and #eventCreated==1)
            assert(art['battle-a'] and eventCreated[1].released==1)
            assert(rawget(art,'story-a')==nil and rawget(art,'battle-a')~=nil)

            local prepare,register
            for index=1,100 do
                local name,value=debug.getupvalue(Assets.load,index)
                if not name then break end
                if name=='prepareLazyImages' then prepare=value end
                if name=='registerLazyImage' then register=value end
            end
            assert(prepare and register)
            local activeTrain={released=0,release=function(self) self.released=self.released+1 end}
            local intro={released=0,release=function(self) self.released=self.released+1 end}
            local scenery={worldTrain=activeTrain}
            prepare(scenery)
            register(scenery,'introBackground','intro.png','UI')
            rawset(scenery,'introBackground',intro)
            Assets.releaseIntroImages(scenery)
            assert(intro.released==1 and rawget(scenery,'introBackground')==nil)
            assert(activeTrain.released==0 and scenery.worldTrain==activeTrain)
        ''')


if __name__ == "__main__":
    unittest.main()
