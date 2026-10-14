"""Accepted patient treatment is host-validated, actor-funded and resumable."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopFirstAidTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Fixtures=require('tools.tests.lua.coop_fixtures'); Catalog=require('game.catalog')
            Authority=require('game.coop_authority'); Model=require('game.first_aid')
            Schema=require('game.save_schema'); Players=require('game.coop_players')
            Help=require('game.stop_help_progression'); Quests=require('game.help_quest_session')
            Items=require('game.item_instances')
            data=Fixtures.campaign(); assert(Fixtures.enroll(data)); data.scene='stop'
            layout={}; data.stopLayouts['1']=layout; npc='medic.png'; data.currentNPC=npc
            request=Help.ensureRequest(layout,npc,'aid',1,data)
            request.accepted=true; Quests.accept(data,request.sessionId)
            for _,id in ipairs({'host','companion'}) do
                local actor=Players.forActor(data,id)
                for slot=1,actor.inventoryCapacity do Items.write(actor,nil,{kind='inventory',index=slot},nil) end
                Items.write(actor,nil,{kind='inventory',index=1},'field-bandage-roll')
            end
            now=0; states={}
            for _,id in ipairs({'host','companion'}) do
                states[id]={screen='game',scene='stop',x=140,y=100,npc={id=npc,x=100,y=100}}
            end
            service=Authority.new({campaign=data,sessionId='aid',clock=function() return now end})
            require('game.coop_activities').install(service,{catalog=Catalog,actorState=function(id) return states[id] end})
            service:admit('companion',1)
            function execute(actor,req) return service:execute(actor,actor=='host' and 0 or 1,req) end
            function run(actor,name,args)
                local req,reason=service:prepareRequest(actor,name,args)
                if not req then return {ok=false,reason=reason} end
                return execute(actor,req)
            end
            function acquire(actor)
                local source={kind='inventory',index=1}
                return run(actor,'firstAid.acquire',{targetId=layout.entityId,npc=npc,source=source,
                    selected=require('game.coop_item_contract').selection(Players.forActor(data,actor),nil,source)})
            end
            function step(actor,lease,action,args)
                args=args or {}; args.leaseId=lease; args.action=action
                return run(actor,'firstAid.step',args)
            end
            function treat(actor,lease,first)
                for phase=first or 1,6 do assert(step(actor,lease,'choose',{index=phase}).ok) end
            end
        ''')

    def test_guest_treats_accepted_patient_with_own_supply_and_one_shared_reward(self):
        self.lua.execute('''
            local lease=acquire('companion').result.leaseId
            assert(acquire('host').reason=='activity_busy')
            assert(run('companion','firstAid.complete',{leaseId=lease}).reason=='treatment_incomplete')
            treat('companion',lease)
            local req=assert(service:prepareRequest('companion','firstAid.complete',{leaseId=lease}))
            local reply=execute('companion',req)
            assert(reply.ok and reply.result.completed and reply.result.gained==3)
            assert(data.players.companion.inventory[1]==nil and data.inventory[1]=='field-bandage-roll')
            assert(data.goodwill==3 and #data.helpHistory==1 and request.complete)
            assert(execute('companion',req).result.completed and data.goodwill==3)
            assert(acquire('host').reason=='quest_unavailable')
            assert(data.scene=='stop' and data.location==1 and data.conversations.completed.example.answer==2)
            assert(Schema.migrate(data).helpQuestSessions[request.sessionId].rewardClaimed)
        ''')

    def test_guest_cannot_accept_an_offer_or_target_an_absent_distant_patient(self):
        self.lua.execute('''
            request.accepted=false
            assert(acquire('companion').reason=='quest_unavailable' and not request.accepted)
            request.accepted=true; Quests.get(data,request.sessionId).state='offered'
            assert(acquire('companion').reason=='quest_unavailable')
            Quests.accept(data,request.sessionId); states.companion.x=200
            assert(acquire('companion').reason=='patient_unavailable')
            states.companion.x=140; states.companion.npc.id='different.png'
            assert(acquire('companion').reason=='patient_unavailable')
            states.companion.npc.id=npc; states.companion.screen='battle'
            assert(acquire('companion').reason=='activity_unavailable')
            assert(data.goodwill==0 and data.players.companion.inventory[1]=='field-bandage-roll')
        ''')

    def test_partial_progress_survives_pause_disconnect_and_save_reload_without_a_lease(self):
        self.lua.execute('''
            local lease=acquire('companion').result.leaseId
            step('companion',lease,'choose',{index=1}); step('companion',lease,'choose',{index=2})
            step('companion',lease,'press',{x=410,y=370}); step('companion',lease,'move',{x=500,y=370})
            local quest=Quests.get(data,request.sessionId); assert(quest.progress.rubDistance==90)
            assert(step('companion',lease,'pause').ok and quest.paused)
            local host=acquire('host').result
            assert(host.session.phase==3 and host.session.progress.rubDistance==90 and not host.session.dragging)
            service:disconnect('companion',1)
            local saved=assert(Schema.migrate(data))
            assert(saved.helpQuestSessions[request.sessionId].progress.rubDistance==90 and not saved.activityState)
            treat('host',host.leaseId,3)
            assert(run('host','firstAid.complete',{leaseId=host.leaseId}).result.completed)
            assert(data.players.companion.inventory[1]=='field-bandage-roll' and data.inventory[1]==nil)
        ''')

    def test_host_clock_and_real_pointer_gestures_drive_treatment(self):
        self.lua.execute('''
            local lease=acquire('companion').result.leaseId
            step('companion',lease,'press',{x=512,y=420})
            now=.8; step('companion',lease,'move',{x=480,y=370})
            assert(Quests.get(data,request.sessionId).progress.phase==2)
            now=1.54; step('companion',lease,'tick')
            assert(Quests.get(data,request.sessionId).progress.phase==2)
            now=1.56; step('companion',lease,'tick')
            assert(Quests.get(data,request.sessionId).progress.phase==3)
            step('companion',lease,'press',{x=410,y=370})
            for _,x in ipairs({550,410,550,410}) do step('companion',lease,'move',{x=x,y=370}) end
            assert(Quests.get(data,request.sessionId).progress.phase==4)
            step('companion',lease,'press',{x=410,y=370})
            for i=1,12 do step('companion',lease,'move',{x=i%2==0 and 410 or 550,y=370}) end
            assert(Quests.get(data,request.sessionId).progress.phase==5)
            step('companion',lease,'press',{x=480,y=370}); step('companion',lease,'press',{x=398,y=370})
            for _,x in ipairs({562,398,562}) do step('companion',lease,'move',{x=x,y=370}) end
            assert(run('companion','firstAid.complete',{leaseId=lease}).result.completed)
        ''')

    def test_replay_wrong_phase_forged_time_progress_cost_and_lease_are_rejected(self):
        self.lua.execute('''
            local lease=acquire('companion').result.leaseId
            step('companion',lease,'choose',{index=6})
            assert(Quests.get(data,request.sessionId).progress.phase==1)
            local req=assert(service:prepareRequest('companion','firstAid.step',{leaseId=lease,action='choose',index=1}))
            assert(execute('companion',req).ok and execute('companion',req).ok)
            assert(Quests.get(data,request.sessionId).progress.phase==2)
            assert(step('host',lease,'choose',{index=2}).reason=='lease_owner')
            assert(step('companion',lease,'tick',{dt=100}).reason=='invalid_args')
            assert(step('companion',lease,'tick',{progress={phase=6}}).reason=='invalid_args')
            assert(step('companion',lease,'move',{x=0/0,y=370}).reason=='invalid_args')
            assert(run('companion','firstAid.complete',{leaseId=lease,itemSlot=1,cost=0}).reason=='invalid_args')
        ''')

    def test_missing_live_supply_and_forced_reward_failure_roll_back_completion(self):
        self.lua.execute('''
            local lease=acquire('companion').result.leaseId; treat('companion',lease)
            local actor=Players.forActor(data,'companion')
            Items.write(actor,nil,{kind='inventory',index=1},nil)
            assert(run('companion','firstAid.complete',{leaseId=lease}).reason=='medical_supply_changed')
            assert(not request.complete and data.goodwill==0)
            Items.write(actor,nil,{kind='inventory',index=3},'field-bandage-roll')
            assert(run('companion','firstAid.complete',{leaseId=lease}).reason=='medical_supply_changed')
            assert(step('companion',lease,'pause').ok)
            local source={kind='inventory',index=3}
            lease=run('companion','firstAid.acquire',{targetId=layout.entityId,npc=npc,source=source,
                selected=require('game.coop_item_contract').selection(actor,nil,source)}).result.leaseId
            local original=Help.add
            Help.add=function(...) original(...); error('injected reward failure') end
            assert(run('companion','firstAid.complete',{leaseId=lease}).reason=='handler_error')
            assert(actor.inventory[3]=='field-bandage-roll' and not request.complete and data.goodwill==0)
            Help.add=original
            assert(run('companion','firstAid.complete',{leaseId=lease}).result.completed)
            assert(actor.inventory[3]==nil and data.goodwill==3)
        ''')

    def test_expiry_scene_change_and_peer_rebind_reject_old_activity_but_keep_checkpoint(self):
        self.lua.execute('''
            local lease=acquire('companion').result.leaseId; step('companion',lease,'choose',{index=1})
            now=31; assert(step('companion',lease,'choose',{index=2}).reason=='lease_expired')
            assert(Quests.get(data,request.sessionId).progress.phase==2)
            lease=acquire('companion').result.leaseId
            data.coop.sceneEpoch=data.coop.sceneEpoch+1
            assert(not step('companion',lease,'choose',{index=2}).ok)
            lease=acquire('companion').result.leaseId
            service:disconnect('companion',1); service:admit('companion',2)
            local req=service:prepareRequest('companion','firstAid.step',{leaseId=lease,action='choose',index=2})
            assert(not req and data.goodwill==0)
            local host=acquire('host').result; assert(host.session.phase==2)
            treat('host',host.leaseId,2); assert(run('host','firstAid.complete',{leaseId=host.leaseId}).ok)
        ''')

    def test_real_ui_adapter_uses_authority_and_has_no_campaign_progress_alias(self):
        self.lua.execute('''
            local reply=acquire('host').result
            local ui=Model.bindCommands(reply.session,function(name,args) return run('host',name,args) end,reply.leaseId)
            local checkpoint=Quests.get(data,request.sessionId).progress
            assert(ui.progress~=checkpoint)
            assert(Model.keypressed(ui,'1')=='progress' and ui.phase==2 and checkpoint.phase==2)
            Model.mousemoved(ui,480,370); now=.8; Model.update(ui,.8)
            assert(ui.phase==3 and checkpoint.phase==3)
            Model.keypressed(ui,'3'); Model.keypressed(ui,'4'); Model.keypressed(ui,'5')
            assert(Model.keypressed(ui,'6')=='complete' and ui.command and ui.leaseId)
            assert(run('host','firstAid.complete',{leaseId=ui.leaseId}).result.completed)
        ''')

    def test_finished_unclaimed_treatment_can_be_resumed_after_reload(self):
        self.lua.execute('''
            local lease=acquire('companion').result.leaseId; treat('companion',lease)
            local checkpoint=Quests.get(data,request.sessionId)
            assert(checkpoint.progress.wrapPasses==3 and not checkpoint.rewardClaimed and not request.complete)
            data=assert(Schema.migrate(data)); layout=data.stopLayouts['1']; request=layout.helpRequests[npc]
            service=Authority.new({campaign=data,sessionId='aid-reloaded',clock=function() return now end})
            require('game.coop_activities').install(service,{catalog=Catalog,actorState=function(id) return states[id] end})
            assert(not next(service.activityState.resources))
            local resumed=acquire('host').result
            assert(resumed.session.ready)
            assert(run('host','firstAid.complete',{leaseId=resumed.leaseId}).result.completed)
            assert(data.goodwill==3 and data.inventory[1]==nil and data.players.companion.inventory[1]=='field-bandage-roll')
        ''')

    def test_dead_encounter_and_changed_supply_guards_still_allow_cleanup(self):
        self.lua.execute('''
            local actor=Players.forActor(data,'companion'); actor.health=0
            assert(acquire('companion').reason=='activity_unavailable'); actor.health=2
            states.companion.encounterActive=true; assert(acquire('companion').reason=='activity_unavailable')
            states.companion.encounterActive=false; local lease=acquire('companion').result.leaseId
            local revision=data.coop.revisions['player:companion']; data.coop.revisions['player:companion']=revision+1
            assert(step('companion',lease,'choose',{index=1}).reason=='medical_supply_changed')
            actor.health=0; states.companion.x=1000; states.companion.encounterActive=true
            assert(step('companion',lease,'pause').ok and not next(service.activityState.resources))
            assert(Quests.get(data,request.sessionId).paused and actor.inventory[1]=='field-bandage-roll' and data.goodwill==0)
        ''')

    def test_remote_acquisition_requires_the_selected_owned_supply_and_revision(self):
        self.lua.execute('''
            assert(run('companion','firstAid.acquire',{targetId=layout.entityId,npc=npc}).reason=='item_selection_required')
            local source={kind='inventory',index=1}; local actor=Players.forActor(data,'companion')
            local selected=require('game.coop_item_contract').selection(actor,nil,source)
            local req=assert(service:prepareRequest('companion','firstAid.acquire',{targetId=layout.entityId,npc=npc,source=source,selected=selected}))
            data.coop.revisions['player:companion']=(data.coop.revisions['player:companion'] or 0)+1
            assert(execute('companion',req).reason=='stale_revision' and not next(service.activityState.resources))
            assert(run('companion','firstAid.acquire',{targetId=layout.entityId,npc=npc,source={kind='equipment',index=1},selected=selected}).reason=='invalid_args')
            selected.name='healing-salve'
            assert(run('companion','firstAid.acquire',{targetId=layout.entityId,npc=npc,source=source,selected=selected}).reason=='medical_supply')
            assert(actor.inventory[1]=='field-bandage-roll' and not request.complete)
        ''')

    def test_public_results_fit_control_packets_without_raw_progress_or_sessions(self):
        self.lua.execute('''
            local result=acquire('companion'); local session=result.result.session
            session.progress.ointmentTrail={}; for i=1,80 do session.progress.ointmentTrail[i]={x=480,y=370} end
            local R=require('game.net.item_results'); local dto=assert(R.project('firstAid.acquire',result.result))
            assert(not dto.session and not dto.progress and not dto.message and not dto.itemSlot)
            local wire=assert(require('game.net.commands').outcome('aid',1,result,'firstAid.acquire'))
            assert(#assert(require('game.net.protocol').encode(wire,0))<=1200)
            dto.ready=true; assert(not R.valid('firstAid.acquire',dto)); dto.ready=false; dto.pointer.x=0/0
            assert(not R.valid('firstAid.acquire',dto))
        ''')


if __name__ == "__main__":
    unittest.main()
