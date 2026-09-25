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
            local stream,backgroundStream
            for index=1,100 do
                local name,value=debug.getupvalue(Assets.load,index)
                if not name then break end
                if name=='streamBattleAtlases' then stream=value end
                if name=='streamWorldBackgrounds' then backgroundStream=value end
            end
            assert(stream and backgroundStream,'scene art streamers unavailable')
            local backgroundCreated={}
            local backgrounds=backgroundStream({count=2},{'stop1.png','stop2.png'},function(path)
                local image={path=path,released=0,release=function(self) self.released=self.released+1 end}
                backgroundCreated[#backgroundCreated+1]=image
                return image
            end)
            assert(backgrounds[1]==backgrounds[1] and #backgroundCreated==1)
            backgrounds:release()
            assert(backgroundCreated[1].released==1 and rawget(backgrounds,1)==nil)
            assert(backgrounds[1].path=='stop1.png' and #backgroundCreated==2)
            assert(backgrounds[2].path=='stop2.png' and backgroundCreated[2].released==1)
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

            local function image()
                return {released=0,release=function(self) self.released=self.released+1 end}
            end
            local aid={bandageStrips={}}
            prepare(aid); prepare(aid.bandageStrips)
            register(aid,'wound','wound.png'); register(aid.bandageStrips,1,'strip.png')
            local wound,strip=image(),image()
            rawset(aid,'wound',wound); rawset(aid.bandageStrips,1,strip)
            local weaponViews={released=0,release=function(self) self.released=self.released+1 end}
            local range={weaponViews=weaponViews}; prepare(range)
            register(range,'background','range.png'); register(range,'entrance','flag.png')
            local rangeBackground,flag=image(),image()
            rawset(range,'background',rangeBackground); rawset(range,'entrance',flag)
            local caravan={released=0,release=function(self) self.released=self.released+1 end}
            scenery.battleAtlases=atlases; scenery.eventArt=art
            scenery.firstAidAssets=aid; scenery.shootingRangeAssets=range
            scenery.crowCaravanAssets=caravan
            local activeAtlas=atlases[1]
            local activeArt=art['story-a']
            Assets.releaseDormantSceneArt(scenery,{state='battle',scene='caravan',firstAid=true,shootingRange=true})
            assert(rawget(atlases,1)==activeAtlas and wound.released==0 and flag.released==0)
            assert(activeArt.released==1 and caravan.released==1)
            Assets.releaseDormantSceneArt(scenery,{state='game',scene='stop'})
            assert(activeAtlas.image.released==1 and rawget(atlases,1)==nil)
            assert(wound.released==1 and strip.released==1)
            assert(rangeBackground.released==1 and flag.released==0 and weaponViews.released==1)
            Assets.releaseDormantSceneArt(scenery,{state='game',scene='train'})
            assert(flag.released==1 and rawget(range,'entrance')==nil)
        ''')

    def test_full_screen_quest_releases_hidden_settlement_and_keeps_escort_motion(self) -> None:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + lua.globals().package.path
        lua.execute(r'''
            local Assets=require('game.assets')
            local Settlements=require('game.settlements')
            local CharacterAnimation=require('game.character_animation')
            local AssetStreamer=require('game.asset_streamer')
            local settlement={released=0,release=function(self) self.released=self.released+1 end}
            local resident={wide={[10]=settlement},active=10}
            local streamer=AssetStreamer.new({settlements=resident,characterAnimations={},
                legacyAnimationTables={},interiorFiles={}})
            streamer.lastSettlement=10
            local originalRetain=CharacterAnimation.retain
            local originalLegacyRetain=Assets.retainAnimationImages
            local retained,legacy
            CharacterAnimation.retain=function(_,keep) retained=keep end
            Assets.retainAnimationImages=function(_,keep) legacy=keep end
            streamer:update('game','lastStand',{location=10,character='conductor-cat.png',
                stopLayouts={}},nil,nil)
            CharacterAnimation.retain=originalRetain
            Assets.retainAnimationImages=originalLegacyRetain
            assert(settlement.released==1 and resident.wide[10]==nil and resident.active==nil)
            assert(retained['conductor-cat.png'] and retained['otter-scout.png'])
            assert(legacy['conductor-cat.png'] and legacy['otter-scout.png'])
        ''')


if __name__ == "__main__":
    unittest.main()
