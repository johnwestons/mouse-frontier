"""Guest private journey lifecycle and actual read-only model/render paths."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/coop-python-deps')))
from lupa.lua51 import LuaRuntime


class JourneyTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            local F=require('tools.tests.lua.coop_fixtures')
            State=require('game.net.game_state');Entities=require('game.coop_entities')
            Codec=require('game.net.codec');Records=require('game.net.state_records')
            data=F.campaign(6,{scene='stop',visitedStops={[1]=true,[6]=true}});assert(F.enroll(data))
            assert(Entities.ensure(data));public=assert(State.project(data)).view
            function bytes(value)return assert(Codec.encode(assert(Records.encode(value,Records.budget())),
                {maxBytes=524288,maxDepth=32,maxEntries=200000,maxStringBytes=4096}))end
            local colors={cream={1,1,1},red={1,0,0},ink={0,0,0},brass={1,.8,.4},blue={0,0,1},green={0,1,0}}
            graphicsCalls=0;texts={}
            love.graphics=setmetatable({getColor=function()return 1,1,1,1 end,getShader=function()return nil end},
                {__index=function()return function()graphicsCalls=graphicsCalls+1 end end})
            require('game.typography').drawText=function(_,value)texts[#texts+1]=value end
            v={ready=true,focused=true,paused=false,epoch=public.coop.sceneEpoch,motionId=3,lastSerial=10,
                runtime={saveData=public,scene='stop',player={activeCar=1}},mobile={enabled=false},
                prediction={stale=function()return false end},neutralizations=0}
            v.controller={network={status='ready',sessionId='s1',campaignId='c1'},replica={data=public},
                motionFrame={ready=true,paused=false,sessionId='s1',sceneEpoch=v.epoch,motionId=3,serial=10}}
            function v:neutralize()self.neutralizations=self.neutralizations+1;self.held=nil end
            function v:objectsOpen()return self.runtime.editMode or self.uiRadioOpen end
            function v:activityBusy()return self.activityBlocked end
            v.inventory={frame=function()graphicsCalls=graphicsCalls+1 end,
                button=function(_,label,x,y,w,h,enabled)
                    texts[#texts+1]=label;return{x=x,y=y,w=w,h=h,enabled=enabled~=false}end}
            Journey=require('game.coop_guest_journey');j=Journey.new(v,{colors=colors})
        ''')

    def test_open_close_only_neutralizes_guest_and_keeps_campaign_network_menu_unchanged(self):
        self.lua.execute('''
            local before=bytes(public);v.held='right'
            assert(not j:open('other') and not j.opened)
            assert(j:open('map') and j.opened and j.kind=='map' and v.neutralizations==1 and not v.held)
            assert(not v.controller.menuOpen and not v.controller.network.pendingCommand)
            assert(j:draw() and #j.model.points==2 and graphicsCalls>100)
            v.held='up';assert(j:close() and not j.opened and not j.kind and not v.held)
            assert(v.neutralizations==2 and bytes(public)==before)
            j:close();assert(v.neutralizations==2)
        ''')

    def test_private_map_and_journal_mouse_touch_close_controls(self):
        self.lua.execute('''
            for _,mobile in ipairs({false,true})do
                v.mobile.enabled=mobile
                for _,kind in ipairs({'map','journal'})do
                    assert(j:open(kind));assert(j:draw())
                    local close=kind=='map' and j.controls.map or j.controls.journeyLogClose
                    assert(j:pointer(close.x+close.w/2,close.y+close.h/2) and not j.opened)
                end
            end
            assert(v.neutralizations==8)
        ''')

    def test_canonical_controller_keys_and_wheel_scroll_capture_actions(self):
        self.lua.execute('''
            public.visitedStops['50']=true
            assert(j:open('map'));j:draw();assert(j.scroll==0)
            assert(j:keypressed('down') and j.scroll==1)
            assert(j:keypressed('w') and j.scroll==0)
            j:wheelmoved(0,-3);assert(j.scroll==1)
            j:wheelmoved(0,1);assert(j.scroll==0)
            j:wheelmoved(0,0/0);assert(j.scroll==0)
            j:keypressed('g');assert(j.opened)
            assert(j:pointer(-100,-100) and j.opened)
            j:keypressed('m');assert(not j.opened and not j:keypressed('down') and not j:wheelmoved(0,-1))
            assert(j:open('journal'));j:keypressed('return');assert(not j.opened)
            assert(j:open('journal'));j:keypressed('j');assert(not j.opened)
            assert(j:open('map'));j:keypressed('acback');assert(not j.opened)
        ''')

    def test_persisted_rotated_scaled_shifted_ui_scopes_inverse_hit_testing(self):
        self.lua.execute('''
            local Style=require('game.ui_layout')
            local fs={read=function()return nil end,write=function()return true end}
            local manager=Style.new({filesystem=fs,screen=function()return 'game' end})
            for _,kind in ipairs({'map','journal'})do
                local element=kind=='map' and 'map' or 'journeyLog'
                manager:set(element,{x=27,y=-18,scale=.75,rotation=18},false)
                assert(j:open(kind));j:draw()
                local r=kind=='map' and j.controls.map or j.controls.journeyLogClose
                local bounds=kind=='map' and {x=70,y=75,w=820,h=570} or j.controls.journeyLogBounds
                local tiny={x=r.x+r.w/2,y=r.y+r.h/2,w=0,h=0}
                local transformed=Style.transformRectFor(element,bounds,tiny)
                assert(j:pointer(transformed.x,transformed.y) and not j.opened)
            end
        ''')

    def test_journal_draw_accepted_tasks_scroll_and_no_offers_rewards_or_letter_speech(self):
        self.lua.execute('''
            local Help=require('game.help_quest_session')
            local offered=Help.ensure(data,{source='maintenance',location=6,npc='mechanic.png',
                title='OFFER TO HIDE',objective='Unaccepted objective to hide.'})
            local accepted=Help.ensure(data,{source='first-aid',location=6,npc='medic.png',
                title='ACCEPTED TASK',objective='Continue the active task.'})
            assert(Help.accept(data,accepted.id))
            data.mailQuests={}
            for i=1,8 do data.mailQuests[i]={origin=1,destination=6+i,recipient='crow-merchant.png',
                complete=false,letter='PRIVATE LETTER SPEECH'}end
            assert(Entities.ensure(data));public=assert(State.project(data)).view;v.runtime.saveData=public;v.controller.replica.data=public
            local before=bytes(public)
            Help.summary=function()error('mutating summary')end
            require('game.expedition_areas').state=function()error('mutating expedition state')end
            assert(j:open('journal'));j:draw()
            assert(#j.model.rows==9 and j.controls.journeyLogPageSize==3 and j.controls.journeyLogMaxScroll==6)
            assert(j:keypressed('down') and j.scroll==1);j:draw()
            local down=j.controls.journeyLogDown;j:pointer(down.x+5,down.y+5);assert(j.scroll==2)
            j:wheelmoved(0,-1);assert(j.scroll==3);j:draw()
            local text=table.concat(texts,'|')
            assert(not text:find('OFFER TO HIDE',1,true) and not text:find('Unaccepted objective',1,true))
            assert(not text:find('PRIVATE LETTER SPEECH',1,true) and not text:find('reward',1,true))
            assert(bytes(public)==before and data.helpQuestSessions[offered.id].state=='offered')
        ''')

    def test_rejects_battle_special_activity_story_and_unfinished_transactions(self):
        self.lua.execute('''
            local mutations={
                function()public.tacticalBattle={battle={}}end,
                function()public.roamingEncounter={}end,
                function()public.trainAmbush={active=true}end,
                function()public.lastStand={lifecycle={mode='offer'}}end,
                function()public.events={current={id='event'}}end,
                function()v.controller.network.pendingCommand={}end,
                function()v.controller.motionFrame.paused=true end,
                function()v.runtime.saving=true end,
                function()v.runtime.inventoryOpen=true end,
                function()v.runtime.tradeOpen=true end,
                function()v.runtime.trainUpgradeOpen=true end,
                function()v.runtime.peopleOpen=true end,
                function()v.runtime.guestActivityOpen=true end,
                function()v.runtime.editMode=true end,
                function()v.activityBlocked=true end,
                function()v.inventory.pending={}end,
                function()v.range={available=function()return true end}end,
                function()v.poses={opened=true}end,
                function()v.controller.menuOpen=true end,
                function()v.carTransition={}end,
                function()v.carRequest={}end,
            }
            for _,mutate in ipairs(mutations)do
                mutate();assert(not j:open('map'))
                public.tacticalBattle=nil;public.roamingEncounter=nil;public.trainAmbush=nil
                public.lastStand=nil;public.events=nil;v.controller.network.pendingCommand=nil
                v.controller.motionFrame.paused=false;v.runtime.saving=nil
                v.runtime.inventoryOpen=nil;v.runtime.tradeOpen=nil;v.runtime.trainUpgradeOpen=nil
                v.runtime.peopleOpen=nil;v.runtime.guestActivityOpen=nil;v.runtime.editMode=nil
                v.activityBlocked=nil;v.inventory.pending=nil;v.range=nil;v.poses=nil
                v.controller.menuOpen=nil;v.carTransition=nil;v.carRequest=nil
            end
            assert(j:open('map'))
        ''')

    def test_identity_or_modal_change_clears_stale_overlay_before_draw_or_input(self):
        self.lua.execute('''
            local changes={function()v.motionId=v.motionId+1;v.controller.motionFrame.motionId=v.motionId end,
                function()v.epoch=v.epoch+1;public.coop.sceneEpoch=v.epoch;v.controller.motionFrame.sceneEpoch=v.epoch end,
                function()v.modalDomain='new';v.controller.motionFrame.domain='new'end,
                function()v.controller.network.sessionId='s2';v.controller.motionFrame.sessionId='s2'end,
                function()v.controller.network.campaignId='c2'end,
                function()v.runtime.player.activeCar=2 end,
                function()public.location=7 end,
                function()public.scene='house';v.runtime.scene='house'end}
            for _,change in ipairs(changes)do
                assert(j:open('journal'));j:draw();change();j:update()
                assert(not j.opened and not j.kind and not next(j.controls) and j.scroll==0)
            end
            assert(j:open('map'));public.events={current={id='event'}}
            assert(not j:pointer(0,0) and not j.opened)
            public.events=nil;assert(j:open('map'));v.controller.network.closed=true
            assert(not j:draw() and not j.opened)
        ''')

    def test_unready_or_stale_frames_and_focus_loss_close_without_campaign_writes(self):
        self.lua.execute('''
            local before=bytes(public)
            v.ready=false;assert(not j:open('map'));v.ready=true
            v.controller.motionFrame.serial=9;assert(not j:open('map'));v.controller.motionFrame.serial=10
            v.controller.motionFrame.sessionId='old';assert(not j:open('map'));v.controller.motionFrame.sessionId='s1'
            v.prediction.stale=function()return true end;assert(not j:open('map'))
            v.prediction.stale=function()return false end;assert(j:open('map'));j:focus(false)
            assert(not j.opened and bytes(public)==before)
            assert(j:open('journal'));j:release();assert(not j.opened and bytes(public)==before)
        ''')

    def test_projection_revision_refreshes_same_scene_without_erasing_private_scroll(self):
        self.lua.execute('''
            public.visitedStops['50']=true;assert(j:open('map'));j:draw();j:keypressed('down')
            local copy=require('game.save_schema').copy(public)
            copy.visitedStops['2']=true;v.runtime.saveData=copy;v.controller.replica.data=copy
            j:update();assert(j.opened);j:draw();assert(j.scroll==1 and #j.model.points==4)
            assert(copy.mapScroll==nil and copy.journeyLogScroll==nil)
        ''')

    def test_map_opens_at_current_visited_stop_and_private_accessibility_does_not_repair_projection(self):
        self.lua.execute('''
            public.location=50;public.visitedStops['50']=true
            local Preferences=require('game.local_preferences')
            local store=Preferences.new({read=function()return nil end,write=function()return true end})
            store.values.accessibility.textSize=3;store.values.accessibility.highContrast=true
            store:bind(public,function()return 'client'end)
            local before=bytes(public);local scales={}
            require('game.typography').drawText=function(_,value,x,y,w,h,options)
                texts[#texts+1]=value;scales[#scales+1]=options.scale end
            assert(j:open('map'));j:draw();assert(j.scroll==6 and j.model.current.stop==50)
            assert(scales[1]==1.25*1.30 and bytes(public)==before)
            assert(not public.accessibility and not public.mapScroll)
        ''')


if __name__ == '__main__':
    unittest.main()
