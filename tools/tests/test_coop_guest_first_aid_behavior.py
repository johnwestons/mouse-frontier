"""Guest treatment uses detached displays, bounded intents and durable receipts."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GuestFirstAidTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema'); Players=require('game.coop_players')
            Catalog=require('game.catalog'); Help=require('game.stop_help_progression'); Quests=require('game.help_quest_session')
            Items=require('game.item_instances'); Access=require('game.coop_aid_access'); Model=require('game.first_aid')
            data=F.campaign(); assert(F.enroll(data)); data.scene='stop'; data.currentNPC='medic.png'
            local layout={}; data.stopLayouts['1']=layout
            local request=Help.ensureRequest(layout,'medic.png','aid',1,data); request.accepted=true; Quests.accept(data,request.sessionId)
            assert(require('game.coop_entities').ensure(data)); targetId=layout.entityId; questId=request.sessionId
            local actor=Players.forActor(data,'companion')
            for i=1,actor.inventoryCapacity do Items.write(actor,nil,{kind='inventory',index=i},nil) end
            Items.write(actor,nil,{kind='inventory',index=1},'field-bandage-roll')
            copy=Schema.copy(data); copy.itemIdentity=nil
            runtime={saveData=Players.forActor(copy,'companion'),scene='stop',state='game',player={x=140,y=100},npcActor={x=100,y=100}}
            requests={}; allowed=true; network={}; reject=false
            function network:submitCommand(name,args,epoch,expected)
                if reject then return nil,'busy' end
                requests[#requests+1]={name=name,args=args,epoch=epoch,expected=expected}; self.lastCommandResult=nil; return #requests
            end
            view={runtime=runtime,ui={},epoch=copy.coop.sceneEpoch,elapsed=10,focused=true,controller={network=network},
                actionsAllowed=function() return allowed end,neutralize=function() end,
                inventory={frame=function() end,button=function() end},trade={textBox=function() end}}
            created=0; released=0
            art={new=function() created=created+1; return {owned=true} end,
                release=function(a) if a then assert(a.owned); released=released+1 end end}
            love={graphics={setColor=function() end}}
            require('game.ui_layout').scope=function(_,_,fn) fn() end
            require('game.ui_layout').inversePoint=function(x,y) return x,y end
            panel=require('game.coop_guest_first_aid').new(view,{catalog=Catalog,colors={cream={}},aidArt=art})
            function equal(a,b)
                if type(a)~='table' then return a==b end; if type(b)~='table' then return false end
                for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
                for k in pairs(b) do if a[k]==nil then return false end end; return true
            end
            function facts(phase,overrides)
                local d={leaseId='l1',questId=questId,itemName='field-bandage-roll',phase=phase or 1,
                    ready=false,dragging=false,pointer={x=480,y=370},expiresIn=30}
                for k,v in pairs(overrides or {}) do d[k]=v end; return d
            end
            function result(id,d,revision)
                network.lastCommandResult={requestId=id,ok=true,details=d,revision=revision or copy.coop.revision}
            end
            function acquire(phase)
                assert(panel:open()); panel:draw(); assert(panel:begin()); result(1,facts(phase)); panel:update()
            end
            function advance() view.elapsed=view.elapsed+.2; panel:update() end
        ''')

    def test_selection_binds_drawn_supply_revision_and_every_backpack_page(self):
        self.lua.execute('''
            runtime.saveData.inventoryCapacity=64
            for i=2,64 do runtime.saveData.inventory[i]='field-bandage-roll' end
            assert(panel:open()); panel.selected=64; panel:draw()
            local before=Schema.copy(copy); copy.coop.revisions['player:companion']=9
            assert(panel:begin()); local r=requests[1]
            assert(r.args.source.index==64 and r.args.selected.name=='field-bandage-roll')
            assert(r.expected['player:companion']==0 and r.expected['quest:'..questId]==0)
            assert(not r.expected['player:host'] and #panel.rows==4 and panel.drawn[64])
            copy.coop.revisions['player:companion']=before.coop.revisions['player:companion']; assert(equal(before,copy))
        ''')

    def test_draw_and_pointer_preview_never_run_model_rules_or_mutate_projection(self):
        self.lua.execute('''
            local q=copy.helpQuestSessions[questId]; q.progress.ointmentTrail={{x=430,y=370}}; q.progress.rubDistance=8
            local before=Schema.copy(copy); acquire(3)
            Model.new=function() error('replica normalizer') end; Model.update=function() error('replica clock') end
            Model.mousemoved=function() error('replica gesture') end; Model.choose=function() error('replica choice') end
            Model.draw=function(display)
                assert(display.progress~=q.progress and display.progress.ointmentTrail~=q.progress.ointmentTrail)
                display.progress.ointmentTrail[1].x=0; display.progress.rubDistance=999
            end
            panel:press(410,370); panel:move(500,370); panel:releasePointer(500,370); panel:draw()
            assert(equal(before,copy) and panel.session.progress.rubDistance==8 and #requests==1)
            assert(created==1); panel:suspend(); assert(released==1)
        ''')

    def test_early_release_is_queued_behind_press_ack_and_input_is_rate_bounded(self):
        self.lua.execute('''
            acquire(3); panel:press(410,370); advance()
            assert(requests[2].args.action=='press'); panel:move(500,370); panel:releasePointer(500,370)
            advance(); assert(#requests==2)
            result(2,facts(3,{dragging=true})); panel:update()
            assert(requests[3].args.action=='move' and not requests[3].args.elapsed)
            result(3,facts(3,{dragging=true})); panel:update(); assert(#requests==3)
            advance(); assert(requests[4].args.action=='release' and #panel.queue==0)
        ''')

    def test_queue_bounds_keep_release_and_phase_changes_discard_old_gestures(self):
        self.lua.execute('''
            acquire(3); panel:press(410,370)
            for i=1,100 do panel:move(i%2==0 and 410 or 550,370) end; panel:releasePointer(500,370)
            assert(#panel.queue==17 and panel.queue[17].action=='release')
            advance(); result(2,facts(4)); panel:update()
            assert(#panel.queue==1 and panel.queue[1].action=='release')
            advance(); assert(requests[3].args.action=='release')
        ''')

    def test_pour_uses_host_ticks_and_failed_submission_keeps_queued_intent(self):
        self.lua.execute('''
            acquire(2); advance(); assert(requests[2].args.action=='tick')
            result(2,facts(2)); panel:update(); panel:move(480,370)
            reject=true; advance(); assert(#panel.queue==1 and #requests==2)
            reject=false; advance(); assert(requests[3].args.action=='move' and #panel.queue==0)
            assert(copy.helpQuestSessions[questId].progress.pourTime==nil)
        ''')

    def test_fast_swipes_preserve_turns_endpoints_and_ointment_coverage_samples(self):
        self.lua.execute('''
            acquire(3); panel:press(410,370)
            for _,direction in ipairs({1,-1,1,-1}) do
                for i=1,70 do panel:move(direction==1 and 410+i*2 or 550-i*2,370) end
            end
            assert(#panel.queue==5 and panel.queue[2].x==550 and panel.queue[3].x==410
                and panel.queue[4].x==550 and panel.queue[5].x==410)
            panel.queue={}; panel.session.phase=4; panel:press(398,370)
            for i=1,82 do panel:move(398+i*2,370) end
            panel:move(550,370); panel:move(540,370); panel:releasePointer(540,370)
            assert(#panel.queue<=17 and #panel.queue>=14)
            assert(panel.queue[#panel.queue].action=='release' and panel.queue[#panel.queue-1].x==540)
            local count=0; for _,entry in ipairs(panel.queue) do if entry.action=='move' then count=count+1 end end
            assert(count>=12 and not copy.helpQuestSessions[questId].progress.ointmentDistance)
        ''')

    def test_late_acquisition_after_close_pauses_and_waits_for_durable_partial_save(self):
        self.lua.execute('''
            assert(panel:open()); panel:draw(); panel:begin(); panel:suspend(); advance()
            result(1,facts(3)); panel:update(); assert(requests[2].args.action=='pause' and not panel.opened and created==0)
            network.lastCommandResult={requestId=2,ok=false,savePending=true,reason='save_pending'}; advance()
            assert(panel.pending and panel.lease=='l1')
            result(2,facts(3,{outcome='cancelled',expiresIn=0}),4); panel:update(); assert(panel.pending)
            copy.coop.revision=4; panel:update(); assert(not panel:busy() and not runtime.guestActivityOpen)
        ''')

    def test_focus_loss_and_lost_patient_pause_even_when_gameplay_is_blocked(self):
        self.lua.execute('''
            acquire(3); view.focused=false; runtime.player.x=700; allowed=false; advance()
            assert(requests[2].args.action=='pause' and not panel.opened and released==1)
            result(2,facts(3,{outcome='cancelled',expiresIn=0})); panel:update(); assert(not panel:busy())
            allowed=true; view.focused=true; runtime.player.x=140; assert(panel:open())
            panel:draw(); panel:begin(); view.epoch=view.epoch+1; result(3,facts(3)); panel:update()
            assert(not panel.lease and not panel.opened and not panel.pending and created==1)
        ''')

    def test_failed_pause_falls_back_to_release_and_retries_without_story_or_payment(self):
        self.lua.execute('''
            acquire(3); panel:suspend(); advance()
            network.lastCommandResult={requestId=2,ok=false,reason='quest_unavailable'}; panel:update()
            view.elapsed=view.elapsed+1; panel:update(); assert(requests[3].name=='activity.release')
            network.lastCommandResult={requestId=3,ok=false,reason='rate_limited'}; panel:update()
            view.elapsed=view.elapsed+1; panel:update(); assert(requests[4].name=='activity.release')
            result(4,{released=true,leaseId='l1'}); panel:update(); assert(not panel:busy())
            assert(data.goodwill==0 and copy.scene=='stop' and runtime.saveData.inventory[1]=='field-bandage-roll')
        ''')

    def test_completion_survives_resolved_projection_and_save_barrier_without_repayment(self):
        self.lua.execute('''
            acquire(6); panel.session.ready=true; advance(); assert(requests[2].name=='firstAid.complete')
            copy.helpQuestSessions[questId].state='resolved'
            network.lastCommandResult={requestId=2,ok=true,savePending=true,revision=5}; advance()
            assert(panel.opened and panel.pending and not panel.completed)
            result(2,{completed=true,item='field-bandage-roll',gained=3,total=3},5); panel:update()
            assert(panel.pending and not panel.completed)
            copy.coop.revision=5; panel:update(); assert(panel.opened and panel.completed.gained==3 and not panel:busy())
            advance(); assert(#requests==2 and panel.notice:find('+3 goodwill',1,true))
            panel:keypressed('return'); assert(not panel.opened and released==1)
        ''')

    def test_incomplete_completion_refreshes_host_facts_without_a_retry_loop(self):
        self.lua.execute('''
            acquire(6); panel.session.ready=true; advance()
            network.lastCommandResult={requestId=2,ok=false,reason='treatment_incomplete'}; advance()
            assert(requests[3].name=='firstAid.step' and requests[3].args.action=='tick' and not panel.session.ready)
        ''')

    def test_art_is_owned_separately_and_releases_only_its_images(self):
        self.lua.execute('''
            local loads,releases={},{}; local shared={}
            love.filesystem={getInfo=function(path) return {type='file'} end}
            love.graphics.newImage=function(path)
                local image={path=path,release=function(self) releases[#releases+1]=self.path end}
                loads[#loads+1]=image; return image
            end
            local Art=require('game.coop_aid_art'); local a=Art.new('medic.png','field-bandage-roll')
            assert(#loads>=10 and a.npc~=shared and #a.bandageStrips==3)
            Art.release(a); assert(#releases==#loads)
            local n=#loads; local b=Art.new('../bad.png','../../bad'); assert(#loads==n+9)
            Art.release(b)
        ''')

    def test_failed_save_lease_recovery_rebinds_original_supply_without_replaying_gestures(self):
        self.lua.execute('''
            acquire(4); panel:press(410,370); advance()
            network.lastCommandResult={requestId=2,ok=false,reason='lease_expired'}; advance()
            assert(requests[3].name=='firstAid.acquire' and requests[3].args.source.index==1 and not requests[3].args.action)
            assert(#panel.queue==0 and panel.resumeAcquire and not panel.session.dragging)
            network.lastCommandResult={requestId=3,ok=false,reason='rate_limited'}; panel:update()
            view.elapsed=view.elapsed+1; panel:update(); assert(requests[4].name=='firstAid.acquire')
            result(4,facts(4,{leaseId='l2'})); panel:update()
            assert(panel.lease=='l2' and not panel.resumeAcquire and not panel.session.dragging and created==2 and released==1)
            assert(not requests[4].args.progress and runtime.saveData.inventory[1]=='field-bandage-roll' and data.goodwill==0)
        ''')

    def test_closing_or_changed_supply_stops_automatic_lease_recovery(self):
        self.lua.execute('''
            acquire(4); panel:press(410,370); advance()
            network.lastCommandResult={requestId=2,ok=false,reason='lease_expired'}; panel:update()
            panel:suspend(); view.elapsed=view.elapsed+1; panel:update(); assert(#requests==2 and not panel:busy())
            assert(panel:open()); panel:draw(); panel:begin(); result(3,facts(4)); panel:update()
            panel:press(410,370); advance()
            network.lastCommandResult={requestId=4,ok=false,reason='lease_expired'}; advance()
            assert(requests[5].name=='firstAid.acquire')
            network.lastCommandResult={requestId=5,ok=false,reason='medical_supply'}; panel:update()
            assert(not panel:busy() and not panel.session and not panel.resumeAcquire and panel.opened)
        ''')

    def test_treatment_rate_lane_does_not_spend_ordinary_inventory_budget(self):
        self.lua.execute('''
            local Rate=require('game.net.command_rate'); local link={}
            local work={command='firstAid.step',args={action='move'}}
            for i=1,4 do assert(Rate.allow(link,work,0)) end; assert(not Rate.allow(link,work,0))
            assert(Rate.allow(link,work,.18))
            for i=1,4 do assert(Rate.allow(link,{command='firstAid.complete'},0)) end
            assert(not Rate.allow(link,{command='inventory.consume'},0))
        ''')


if __name__ == '__main__':
    unittest.main()
