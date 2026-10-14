"""Guest native texture ownership stays bounded without losing active art."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/coop-python-deps')))
from lupa.lua51 import LuaRuntime


class GuestAssetRetentionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            Assets=require('game.assets');Retention=require('game.coop_guest_asset_retention')
            local prepare,register
            for i=1,100 do local name,value=debug.getupvalue(Assets.load,i)
                if name=='prepareLazyImages' then prepare=value end
                if name=='registerLazyImage' then register=value end
            end
            assert(prepare and register)
            function image(name)
                return {name=name,releases=0,release=function(self)self.releases=self.releases+1 end}
            end
            function lazy(name,key)
                local t={};prepare(t);register(t,key,name..'.png');local i=image(name);rawset(t,key,i);return t,i
            end
            scenery,intro=lazy('intro','introBackground')
            scenery.eventArt=image('event');scenery.battleAtlases=image('battle');scenery.battleVariations=image('variation')
            scenery.battleAccents=image('accent');scenery.crowCaravanAssets=image('caravan')
            scenery.firstAidAssets,wound=lazy('wound','wound');scenery.firstAidAssets.bandageStrips,strip=lazy('strip',1)
            scenery.shootingRangeAssets,range=lazy('range','background')
            scenery.shootingRangeAssets.weaponViews=image('weapon')
            local bg=image('landscape');content={scenery=scenery,backgroundImages=bg}
            view={runtime={state='game',scene='train',saveData={scene='train',events={}}},
                range={available=function()return rangeOpen==true end},ambush={available=function()return ambushOpen==true end},
                activities={firstAid={opened=false}},lastStand={aid={opened=false},shooter={available=function()return shooterOpen==true end}}}
            keeper=Retention.new(content)
        ''')

    def test_guest_join_releases_title_intro_but_keeps_live_train_landscape_and_caches_signature(self):
        self.lua.execute('''
            keeper:update(view)
            assert(intro.releases==1 and content.backgroundImages.releases==0)
            local released=scenery.eventArt.releases;keeper:update(view)
            assert(scenery.eventArt.releases==released)
        ''')

    def test_intro_ownership_is_not_discarded(self):
        self.lua.execute('''
            view.runtime.state='intro';keeper:update(view);assert(intro.releases==0)
            view.runtime.state='game';keeper:update(view);assert(intro.releases==1)
        ''')

    def test_actual_passive_cold_night_event_keeps_art_until_continue_town_then_releases_event_only(self):
        self.lua.execute('''
            local F=require('tools.tests.lua.coop_fixtures');local State=require('game.net.game_state')
            local data=F.campaign(1,{scene='train'});assert(F.enroll(data))
            data.events['1']=nil;data.events.current={id='cold-shelter',location=1,scene='train',sceneEpoch=data.coop.sceneEpoch,phase='prompt'}
            assert(require('game.coop_events').readAlong(data))
            local projected=assert(State.project(data)).view
            local before=require('game.save_schema').copy(projected)
            view.runtime.saveData=projected;keeper:update(view)
            assert(scenery.eventArt.releases==0 and content.backgroundImages.releases==0)
            local function unchanged(left,right)
                assert(type(left)==type(right),'cleanup changed field type')
                if type(left)~='table' then assert(left==right,'cleanup changed public campaign value');return end
                for key,value in pairs(left)do unchanged(value,right[key])end
                for key in pairs(right)do assert(left[key]~=nil,'cleanup added public campaign field')end
            end
            unchanged(before,projected)
            data.events.current=nil;data.scene='stop'
            view.runtime.saveData=assert(State.project(data)).view;view.runtime.scene='stop'
            keeper:update(view)
            assert(scenery.eventArt.releases==1 and content.backgroundImages.releases==0)
        ''')

    def test_private_range_aid_and_shooter_keep_all_live_assets_without_faking_saved_modes(self):
        self.lua.execute('''
            view.runtime.scene='stop';view.activities.firstAid.opened=true;rangeOpen=true
            keeper:update(view)
            assert(wound.releases==0 and strip.releases==0 and range.releases==0 and scenery.shootingRangeAssets.weaponViews.releases==0)
            assert(view.runtime.firstAid==nil and view.runtime.shootingRange==nil and view.runtime.saveData.events.current==nil)
            rangeOpen=false;view.activities.firstAid.opened=false;view.lastStand.aid.opened=true;shooterOpen=true
            keeper:update(view);assert(wound.releases==0 and range.releases==0)
            shooterOpen=false;view.lastStand.aid.opened=false;keeper:update(view)
            assert(wound.releases==1 and strip.releases==1 and range.releases==1)
        ''')

    def test_live_ambush_and_battle_art_are_retained_while_hidden_landscape_is_released(self):
        self.lua.execute('''
            ambushOpen=true;view.runtime.battle={};keeper:update(view)
            assert(scenery.battleAtlases.releases==0 and scenery.battleAccents.releases==0)
            assert(scenery.shootingRangeAssets.weaponViews.releases==0 and content.backgroundImages.releases==1)
            ambushOpen=false;view.runtime.battle=nil;keeper:update(view)
            assert(scenery.battleAtlases.releases==1 and scenery.shootingRangeAssets.weaponViews.releases==1)
        ''')

    def test_live_caravan_ownership_remains_and_offline_default_release_semantics_are_unchanged(self):
        self.lua.execute('''
            view.runtime.scene='caravan';keeper:update(view);assert(scenery.crowCaravanAssets.releases==0)
            Assets.releaseDormantSceneArt(scenery,{state='game',scene='train'})
            assert(scenery.crowCaravanAssets.releases==1)
        ''')

    def test_actual_last_stand_record_hides_train_landscape_and_preserves_live_shootout(self):
        self.lua.execute('''
            view.runtime.saveData.lastStand={lifecycle={mode='shootout'}}
            view.lastStand.shooter.available=function()
                local active=require('game.coop_last_stand_lifecycle').active(view.runtime.saveData)
                return active and active.mode=='shootout' or false
            end
            keeper:update(view)
            assert(content.backgroundImages.releases==1 and range.releases==0)
            assert(scenery.shootingRangeAssets.weaponViews.releases==0)
            view.runtime.saveData.lastStand.lifecycle.mode='backyard';keeper:update(view)
            assert(range.releases==1 and scenery.shootingRangeAssets.weaponViews.releases==1)
            view.runtime.saveData.lastStand.lifecycle.mode='complete';keeper:update(view)
            local keep,hidden=Retention.plan(view);assert(not hidden and not keep.shootingRange)
        ''')

    def test_actual_lazy_event_art_survives_every_passive_prompt_frame_and_reloads_after_release(self):
        self.lua.execute('''
            local F=require('tools.tests.lua.coop_fixtures')
            local data=F.campaign(1,{scene='train'});assert(F.enroll(data))
            data.events['1']=nil;data.events.current={id='cold-shelter',location=1,scene='train',sceneEpoch=data.coop.sceneEpoch,phase='prompt'}
            view.runtime.saveData=data
            eventLoads=0;scenery.eventArt=require('game.event_ui').load(function(path)
                eventLoads=eventLoads+1;return image(path)
            end)
            local name=require('game.events').findById('cold-shelter').artSheet
            local live=scenery.eventArt[name];assert(live and eventLoads==1)
            keeper:update(view);keeper:update(view);assert(live.releases==0)
            data.events.current=nil;keeper:update(view);assert(live.releases==1)
            assert(rawget(scenery.eventArt,name)==nil)
            local replacement=scenery.eventArt[name]
            assert(eventLoads==2 and replacement~=live and replacement.releases==0)
        ''')

    def test_actual_ordinary_world_and_battle_ui_keep_same_landscape_until_private_range(self):
        self.lua.execute('''
            local noop=function()end
            local backgroundStream
            for i=1,100 do local name,value=debug.getupvalue(Assets.load,i)
                if name=='streamWorldBackgrounds'then backgroundStream=value end
            end
            assert(backgroundStream)
            local loads,draws=0,0;local original
            content.backgroundImages=backgroundStream({count=1},{'live-landscape.png'},function(path)
                loads=loads+1;local i=image(path)
                i.getWidth=function()return 960 end;i.getHeight=function()return 720 end
                i.getDimensions=function()return 960,720 end;i.setWrap=noop
                if not original then original=i end;return i
            end)
            love.graphics={setColor=noop,rectangle=noop,clear=noop,getDimensions=function()return 960,720 end,
                newQuad=function()return {setViewport=noop,release=noop}end,
                draw=function(i)
                    assert(i.releases==0,'renderer used released live landscape')
                    assert(i==content.backgroundImages[1]);draws=draws+1
                end}
            scenery.settlements={}
            local r=view.runtime;r.landscapeOffset=0;r.animationClock=0;r.player={}
            r.saveData.location=1;r.saveData.droppedItems={}
            local context={runtime=r,width=960,height=720,backgroundImages=content.backgroundImages,scenery=scenery,
                getCharacterAnimations=function()return {}end,ensureStopLayout=function()return {}end,
                settlements={draw=function()return true end,trainPoint=function()return 0,0 end}}
            for _,name in ipairs({'car','colors','landscape','characterImages','characterWalkImages','characterActionImages',
                'itemIdleImages','npcImages','npcWalkImages','familyImages','mobImages','mobIdleImages','mobWalkImages',
                'mobHitImages','mobDeathImages','train','characterAnimation','catalog','family','stops','util','ui'})do
                context[name]={}
            end
            for _,name in ipairs({'drawStopSludges','drawShootingRangeSpot','drawWildlife','drawExpedition',
                'drawExpeditionTrailhead','drawCaravanRuntime','drawCaravanGate','itemIsHere','pendingMailHere'})do context[name]=noop end
            local renderer=require('game.world_renderer').new(context)
            for _,entry in ipairs({{'train','drawLandscape'},{'stop','drawStop'},{'house','drawHouse'},
                {'expedition','drawExpedition'},{'caravan','drawCaravan'}})do
                r.scene=entry[1];keeper:update(view)
                local _,hidden=Retention.plan(view);assert(not hidden,'ordinary renderer incorrectly hides landscape')
                renderer[entry[2]]()
                assert(loads==1 and original.releases==0,'ordinary scene change discarded or reloaded live landscape')
            end
            assert(draws==5)
            r.battle={};keeper:update(view)
            assert(original.releases==0,'tactical BattleUI still draws the global landscape')
            local v={runtime=r,ui={},scene={battleImages={}},renderer=renderer,mobile={enabled=false},
                camera={apply=noop,toWorld=noop,zoom=1,panX=0,panY=0},inventory={}}
            love.graphics.push=noop
            renderer.drawGround=function()error('STOP_AFTER_LIVE_LANDSCAPE')end
            local ctx=require('game.coop_guest_battles').new(v,{content=content,colors={}}):context()
            local ok,why=pcall(require('game.battle_ui').draw,ctx)
            assert(not ok and tostring(why):find('STOP_AFTER_LIVE_LANDSCAPE',1,true))
            assert(loads==1 and draws==6 and original.releases==0,'actual BattleUI discarded or reloaded landscape')
            rangeOpen=true;keeper:update(view)
            assert(original.releases==1 and rawget(content.backgroundImages,1)==nil)
            rangeOpen=false;r.battle=nil;r.scene='train';keeper:update(view);renderer.drawLandscape()
            assert(loads==2 and draws==7 and content.backgroundImages[1]~=original)
            renderer.release()
        ''')


class CharacterRetainPeakTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={filesystem={getInfo=function()return nil end},graphics={newQuad=function()return {}end}}
            Animation=require('game.character_animation')
            function image(name)return {name=name,releases=0,release=function(self)self.releases=self.releases+1 end,
                getDimensions=function()return 512,256 end}end
            hostImage=image('host');guestImage=image('guest');oldImage=image('old')
            manager={root='test',known={['host.png']='host',['guest.png']='guest',['old.png']='old',['new.png']='new'},
                sets={['host.png']={idle={image=hostImage}},['guest.png']={idle={image=guestImage}},
                    ['old.png']={idle={image=oldImage},hit={image=oldImage}}},retainSignature=''}
            loaded=0;manager.loadImage=function(path)
                assert(oldImage.releases==1,'new sheet decoded before dormant old set released')
                assert(hostImage.releases==0 and guestImage.releases==0,'live actor art discarded')
                loaded=loaded+1;return image(path)
            end
        ''')

    def test_releases_old_before_new_load_and_retains_both_live_actors_and_exact_actions(self):
        self.lua.execute('''
            Animation.retain(manager,{['host.png']=true,['guest.png']=true,['new.png']=true})
            assert(oldImage.releases==1 and not manager.sets['old.png'] and loaded>0)
            assert(manager.sets['host.png'].idle.image==hostImage and manager.sets['guest.png'].idle.image==guestImage)
            for action in pairs(Animation.actions)do assert(manager.sets['new.png'][action])end
            local count=loaded;Animation.retain(manager,{['host.png']=true,['guest.png']=true,['new.png']=true})
            assert(loaded==count and hostImage.releases==0 and guestImage.releases==0)
        ''')

    def test_alias_shared_image_owned_by_kept_actor_is_not_released_by_dormant_set(self):
        self.lua.execute('''
            manager.sets['old.png'].shared={image=hostImage}
            manager.sets['also-old.png']={idle={image=oldImage}}
            Animation.retain(manager,{['host.png']=true,['guest.png']=true})
            assert(oldImage.releases==1 and hostImage.releases==0 and guestImage.releases==0)
            assert(not manager.sets['old.png'] and not manager.sets['also-old.png'])
            assert(manager.sets['host.png'].idle.image==hostImage)
        ''')

    def test_actual_streamer_keeps_exact_host_guest_and_current_npc_then_battle_units(self):
        self.lua.execute('''
            local Settlements=require('game.settlements')
            Settlements.activate=function()end;Settlements.release=function()end
            local streamer=require('game.asset_streamer').new({settlements={},characterAnimations=manager,
                legacyAnimationTables={},interiorFiles={}})
            local data={character='guest.png',currentNPC='new.png',location=2}
            streamer:update('game','stop',data,nil,nil,nil,'host.png')
            assert(oldImage.releases==1 and hostImage.releases==0 and guestImage.releases==0)
            assert(manager.sets['host.png'] and manager.sets['guest.png'] and manager.sets['new.png'])
            local npc=manager.sets['new.png'];local actions={}
            for action,entry in pairs(npc)do if type(entry)=='table' and entry.image then actions[action]=entry.image end end
            streamer:update('battle','stop',data,{units={{file='new.png'},{file='host.png'},{file='guest.png'}}},nil,nil,'host.png')
            assert(manager.sets['new.png']==npc)
            for action,i in pairs(actions)do assert(npc[action].image==i and i.releases==0)end
            streamer:update('game','train',{character='guest.png',passengers={}},nil,nil,nil,'host.png')
            assert(not manager.sets['new.png'] and manager.sets['host.png'] and manager.sets['guest.png'])
            for _,i in pairs(actions)do assert(i.releases==1)end
            assert(hostImage.releases==0 and guestImage.releases==0)
        ''')


class GuestViewRetentionOrderingTests(unittest.TestCase):
    def test_actual_view_releases_dormant_scene_art_before_streamer_character_and_scene_preparation(self):
        import test_coop_guest_view_behavior as guest_harness
        harness = guest_harness.GuestViewTests()
        harness.setUp()
        harness.lua.execute('''
            local Assets=require('game.assets');local prepare,register
            for i=1,100 do local name,value=debug.getupvalue(Assets.load,i)
                if name=='prepareLazyImages'then prepare=value end
                if name=='registerLazyImage'then register=value end
            end
            local intro={released=0,release=function(self)self.released=self.released+1 end}
            local landscape={released=0,release=function(self)self.released=self.released+1 end}
            local scenery={};prepare(scenery);register(scenery,'introBackground','intro.png');rawset(scenery,'introBackground',intro)
            context.content.scenery=scenery;context.content.backgroundImages=landscape
            local order={}
            view.ui.assetStreamer={update=function()
                assert(intro.released==1,'guest join allocates actor/scene art before releasing intro')
                assert(landscape.released==0,'ordinary scene still draws the landscape')
                order[#order+1]='stream'
            end}
            context.prepareCharacters=function(players)
                assert(order[#order]=='stream' and players.host and players.companion)
                order[#order+1]='characters'
            end
            view.scene.prepare=function()
                assert(order[#order]=='characters' or view.motionId,'scene prepared before character art ready')
                order[#order+1]='scene';return true
            end
            assert(view:update(.05));assert(intro.released==1 and landscape.released==0)
            local nextData=Schema.copy(data);nextData.scene='house';nextData.coop.sceneEpoch=nextData.coop.sceneEpoch+1
            controller.replica={data=nextData,revision=2}
            assert(view:update(.05));assert(landscape.released==0)
            assert(order[1]=='stream' and order[2]=='characters' and order[3]=='scene')
            assert(order[4]=='stream' and order[5]=='characters' and order[6]=='scene')
            assert(data.scene=='train' and data.coop.sceneEpoch~=nextData.coop.sceneEpoch)
        ''')


if __name__ == '__main__':
    unittest.main()
