"""Independent guest expedition input waits for durable host state."""
import unittest
import test_coop_expedition_assistance_behavior as assistance


class GuestExpeditionTests(unittest.TestCase):
    setUp = assistance.ExpeditionAssistanceTests.setUp

    def view(self):
        assistance.ExpeditionAssistanceTests.expedition(self)
        self.lua.execute('''
            Guest=require('game.coop_guest_expedition'); source=data; sent=0; opened=0; neutral=0
            network={submitCommand=function(self,name,args,epoch,expected)
                sent=sent+1; local request=assert(service:prepareRequest('companion',name,args)); request.expected=expected; request.sceneEpoch=epoch
                self.request=request; self.lastCommandResult=service:execute('companion',1,request); return request.requestId
            end}
            local x,y=positionAt('north-cairn')
            view={elapsed=0,epoch=data.coop.sceneEpoch,runtime={scene='expedition',player={x=x,y=y}},controller={network=network},
                inputAllowed=function() return true end,actionsAllowed=function() return true end,neutralize=function() neutral=neutral+1 end,
                inventory={openContainer=function(self,id) opened=opened+1; openedId=id; return true end}}
            function project() view.runtime.saveData=Players.forActor(assert(Schema.copy(source)),'companion') end
            project(); panel=Guest.new(view)
        ''')

    def test_survey_waits_for_saved_projection_and_does_not_mutate_replica(self):
        self.view()
        self.lua.execute('''
            assert(panel:nearest().markerId=='north-cairn'); assert(panel:interact() and neutral==1)
            assert(panel.pending and not view.runtime.saveData.expeditions[data.activeExpeditionArea].markers['north-cairn'])
            assert(not panel:interact() and sent==1); panel:update(); assert(panel.pending)
            project(); panel:update(); assert(not panel.pending and panel.lastOutcome.durable and opened==0)
            assert(panel.notice=='Cairn marked. 1 of 3 charted.')
            panel:update(); assert(sent==1)
        ''')

    def test_empty_cache_panel_opens_once_after_save_retry_and_projection(self):
        self.view()
        self.lua.execute('''
            states.companion.x,states.companion.y=positionAt('western-stash'); view.runtime.player.x,view.runtime.player.y=positionAt('western-stash')
            local chest=area.chests['western-stash']; chest.storage={}; chest.storageInstances={}; project()
            failSave=true; assert(panel:interact()); panel:update(); assert(panel.pending and opened==0)
            project(); panel:update(); assert(panel.pending and opened==0)
            failSave=false; assert(service:retryCheckpoint()); network.lastCommandResult=service:execute('companion',1,network.request)
            panel:update(); assert(not panel.pending and opened==1 and openedId==chest.entityId)
            panel:update(); assert(opened==1)
        ''')

    def test_closed_scene_epoch_input_capture_and_rejection_keep_private_ui_closed(self):
        self.view()
        self.lua.execute('''
            view.runtime.scene='train'; assert(not panel:nearest() and not panel:interact())
            view.runtime.scene='expedition'; view.inputAllowed=function() return false end; assert(not panel:interact() and sent==0)
            view.inputAllowed=function() return true end; assert(panel:interact()); view.epoch=view.epoch+1; panel:update()
            assert(not panel.pending and not panel.notice and opened==0)
            network.submitCommand=function(self) self.lastCommandResult={ok=false,requestId=12,reason='cache_sealed'}; return 12 end
            assert(panel:interact()); panel:update(); assert(not panel.pending and panel.notice=='This cache is sealed.' and opened==0)
        ''')

    def test_cache_receipt_waits_through_delayed_motion_unpause_without_resending(self):
        self.view()
        self.lua.execute('''
            states.companion.x,states.companion.y=positionAt('western-stash'); view.runtime.player.x,view.runtime.player.y=positionAt('western-stash')
            assert(panel:interact()); project(); view.actionsAllowed=function() return false end
            panel:update(); panel:update(); assert(panel.pending and opened==0 and sent==1)
            view.actionsAllowed=function() return true end; panel:update()
            assert(not panel.pending and opened==1 and sent==1 and panel.lastOutcome.durable)
        ''')


if __name__ == '__main__':
    unittest.main()
