"""Detached radio/editor previews, peer leases and host-projection barriers."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GuestObjectsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema'); Players=require('game.coop_players')
            Entities=require('game.coop_entities'); Items=require('game.item_instances'); Access=require('game.coop_object_access')
            data=F.campaign(); assert(F.enroll(data)); data.scene='train'
            data.droppedItems={{name='frontier-short-sword',scene='train',carIndex=1,x=300,y=400},
                {name='boombox-radio',scene='train',carIndex=1,x=320,y=400,permanent=true}}
            assert(Items.ensure(data)); assert(Entities.ensure(data)); copy=Schema.copy(data)
            runtime={saveData=Players.forActor(copy,'companion'),scene='train',state='game',player={x=300,y=400}}
            requests={}; audioCalls={}; allowed=true; network={}
            function network:submitCommand(name,args,epoch,expected)
                requests[#requests+1]={name=name,args=args,epoch=epoch,expected=expected}; return #requests
            end
            view={runtime=runtime,ui={},epoch=copy.coop.sceneEpoch,elapsed=0,focused=true,mobile={enabled=false},inventory={},trade={},train={},
                controller={network=network},actionsAllowed=function() return allowed end,neutralize=function() end,
                objectPoint=function(_,x,y) return x*2,y*2 end}
            panel=require('game.coop_guest_objects').new(view,{colors={},audio={toggleMute=function(r) audioCalls[#audioCalls+1]=r end}})
            object=copy.droppedItems[1]; radio=copy.droppedItems[2]
            function result(id,details,revision)
                network.lastCommandResult={requestId=id,ok=true,details=details,revision=revision or copy.coop.revision}
            end
            function acquire()
                assert(panel:openEditor() and panel:select(object.entityId)); result(1,{leaseId='l1',entityId=object.entityId}); panel:update()
                assert(panel.lease=='l1' and not panel.pending)
            end
            love={keyboard={isDown=function() return false end}}
        ''')

    def test_detached_draft_commits_exact_values_and_preserves_default_layer(self):
        self.lua.execute('''
            acquire(); local id=object.itemInstance.id
            assert(panel:change({x=500,scale=1.4,hue=.6,saturation=1.5,rotation=math.pi/4}))
            assert(object.x==300 and object.hue==nil and data.droppedItems[1].x==300)
            assert(panel:preview(object).x==500 and panel:apply()); local request=requests[2]
            assert(request.name=='decoration.place' and request.args.leaseId=='l1')
            assert(request.args.values.x==500 and request.args.values.layer==1 and request.args.values.saturation==1.5)
            assert(request.expected['entity:'..object.entityId]==0 and request.expected['activity:decoration:'..object.entityId]==0)
            assert(object.itemInstance.id==id and object.x==300)
            network.lastCommandResult={requestId=2,ok=true,savePending=true}; panel:update(); assert(panel.pending and panel.dirty)
            result(2,{entityId=object.entityId},2); panel:update(); assert(panel.pending)
            object.x=500; object.hue=.6; copy.coop.revision=2; panel:update()
            assert(not panel.pending and not panel.dirty and panel.draft.x==500 and panel.lease=='l1')
        ''')

    def test_focus_or_menu_close_after_inflight_acquisition_releases_without_committing(self):
        self.lua.execute('''
            assert(panel:openEditor() and panel:select(object.entityId)); panel:suspend()
            assert(not runtime.editMode and panel.wantRelease and #requests==1)
            view.focused=false; result(1,{leaseId='l1',entityId=object.entityId}); panel:update()
            assert(requests[2].name=='activity.release' and requests[2].args.leaseId=='l1')
            assert(requests[2].expected['activity:decoration:'..object.entityId]==0)
            result(2,{released=true,leaseId='l1'}); panel:update(); assert(not panel.lease and not panel.pending)
            assert(object.x==300 and #requests==2)
        ''')

    def test_renewal_preserves_preview_and_scene_car_changes_discard_it(self):
        self.lua.execute('''
            acquire(); assert(panel:change({x=800})); view.elapsed=11; panel:update()
            assert(requests[2].name=='decoration.place' and next(requests[2].args.values)==nil and panel.pending.renewal)
            result(2,{entityId=object.entityId}); panel:update(); assert(panel.dirty and panel.draft.x==800 and object.x==300)
            runtime.saveData.activeCar=2; panel:update(); assert(not runtime.editMode and not panel.lease and not panel.draft)
            runtime.saveData.activeCar=1; view.elapsed=12; assert(panel:openEditor() and panel:select(object.entityId))
            view.epoch=view.epoch+1; result(3,{leaseId='l2',entityId=object.entityId}); panel:update()
            assert(not panel.lease and not runtime.editMode and #requests==3)
        ''')

    def test_selection_switch_waits_for_release_and_failed_collect_keeps_lease(self):
        self.lua.execute('''
            acquire(); assert(panel:select(radio.entityId)); panel:update()
            assert(requests[2].name=='activity.release'); result(2,{released=true,leaseId='l1'}); panel:update()
            assert(requests[3].name=='decoration.acquire' and requests[3].args.entityId==radio.entityId)
            result(3,{leaseId='l2',entityId=radio.entityId}); panel:update(); assert(panel:collect())
            network.lastCommandResult={requestId=4,ok=false,reason='permanent'}; panel:update()
            assert(panel.lease=='l2' and panel:selected()==radio and #copy.droppedItems==2)
            panel:suspend(); panel:update(); assert(requests[5].name=='activity.release')
        ''')

    def test_radio_is_read_only_and_local_playback_never_emits_campaign_commands(self):
        self.lua.execute('''
            assert(panel:nearestRadio()==radio and panel:openRadio()); local original=copy.audio.station
            assert(panel:radio('vibes',false)); local req=requests[1]
            assert(req.name=='radio.station' and req.expected.radio==0 and req.expected['entity:'..radio.entityId]==0)
            assert(copy.audio.station==original and data.audio.station==original)
            panel:localAudio('toggleMute'); assert(audioCalls[1]==runtime and #requests==1)
            copy.audio.station='vibes'; copy.audio.rainEnabled=false; result(1,{station='vibes',rainEnabled=false}); panel:update()
            assert(not panel.pending and panel.notice=='Shared radio updated.')
            runtime.player.x=800; panel:update(); assert(not view.ui.radioOpen)
            runtime.player.x=300; runtime.saveData.health=0; assert(not panel:nearestRadio())
        ''')

    def test_drag_uses_world_transform_and_revert_discards_uncommitted_work(self):
        self.lua.execute('''
            acquire(); panel.controls={}; panel:press(165.5,215.5)
            assert(panel.drag and panel.drag.world); panel:move(700,-20); panel:releasePointer(700,-20)
            assert(panel.draft.x==960 and panel.draft.y==0 and not panel.drag and object.x==300)
            panel:revert(); assert(not panel.dirty and panel.draft.x==300 and #requests==1)
            view.controller.menuOpen=true; panel:update(); assert(not runtime.editMode and requests[2].name=='activity.release')
        ''')

    def test_public_results_are_bounded_and_strip_private_lease_and_item_state(self):
        self.lua.execute('''
            local R=require('game.net.item_results'); local W=require('game.net.commands')
            assert(R.valid('decoration.acquire',{leaseId='l12',entityId=object.entityId}))
            assert(not R.valid('decoration.acquire',{leaseId='arbitrary',entityId=object.entityId}))
            assert(not R.valid('radio.station',{station='vibes',rainEnabled=false,musicVolume=1}))
            assert(not R.valid('decoration.collect',{item='cowboy-hat',slot=0}))
            local projected=R.project('decoration.acquire',{leaseId='l1',entityId=object.entityId,payload={actorId='host'},expiresAt=30})
            assert(projected.leaseId=='l1' and not projected.payload and not projected.expiresAt)
            assert(W.outcome('s',1,{ok=true,revision=2,result={released=true,leaseId='l1'}},'activity.release'))
            assert(W.outcome('s',1,{ok=true,revision=2,result={station='chill',rainEnabled=true}},'radio.station'))
        ''')

    def test_all_panels_and_other_pending_commands_prevent_new_edit_sessions(self):
        self.lua.execute('''
            for _,name in ipairs({'inventoryOpen','tradeOpen','trainUpgradeOpen'}) do
                runtime[name]=true; assert(not panel:openEditor() and not panel:openRadio()); runtime[name]=false
            end
            view.inventory.pending={}; assert(not panel:openEditor()); view.inventory.pending=nil
            runtime.scene='stop'; runtime.saveData.scene='stop'; assert(not panel:openEditor())
            allowed=false; runtime.scene='train'; runtime.saveData.scene='train'; assert(not panel:openEditor())
        ''')

    def test_release_rate_limit_or_changed_revision_retries_with_current_scopes(self):
        self.lua.execute('''
            acquire(); panel:suspend(); panel:update(); assert(requests[2].name=='activity.release')
            network.lastCommandResult={requestId=2,ok=false,reason='rate_limited'}; panel:update()
            assert(panel.lease=='l1' and panel.wantRelease and not panel.pending and #requests==2)
            copy.coop.revisions['activity:decoration:'..object.entityId]=3; view.elapsed=.7; panel:update()
            assert(requests[3].expected['activity:decoration:'..object.entityId]==3)
            result(3,{released=true,leaseId='l1'}); panel:update(); assert(not panel.lease and not panel.wantRelease)
        ''')


if __name__ == '__main__':
    unittest.main()
