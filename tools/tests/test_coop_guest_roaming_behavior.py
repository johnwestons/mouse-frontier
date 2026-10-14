"""Guest field input waits for a durable reply and matching host projection."""
import unittest
import test_coop_roaming_behavior as field


class GuestFieldTests(unittest.TestCase):
    setUp = field.RoamingCommandTests.setUp

    def guest_view(self):
        field.RoamingCommandTests.field(self)
        self.lua.execute('''
            GuestField=require('game.coop_guest_roaming'); source=data
            presentations=0; sent=0
            network={submitCommand=function(self,name,value,epoch,expected)
                sent=sent+1
                local request,reason=service:prepareRequest('companion',name,value)
                if not request then return nil,reason end
                request.expected=expected; request.sceneEpoch=epoch
                self.request=request; self.lastCommandResult=service:execute('companion',1,request)
                return request.requestId
            end}
            view={runtime={scene='expedition'},ui={},elapsed=10,epoch=source.coop.sceneEpoch,
                ready=true,focused=true,controller={network=network},inputAllowed=function() return true end,
                scene={presentFieldAttack=function() presentations=presentations+1 end}}
            function project() view.runtime.saveData=Players.forActor(assert(Schema.copy(source)),'companion') end
            project(); panel=GuestField.new(view,{catalog=Catalog}); panel:update()
        ''')

    def test_owned_swing_waits_for_matching_projection_and_blocks_repeat(self):
        self.guest_view()
        self.lua.execute('''
            assert(panel:attack(a.x,a.y)); assert(panel.pending and sent==1)
            assert(not panel:attack(a.x,a.y) and sent==1)
            panel:update(); assert(panel.pending and presentations==0)
            project(); panel:update(); assert(not panel.pending and presentations==1 and panel.lastOutcome.ok)
            assert(panel:presentation('companion').actionTimer>0 and panel:presentation('companion').actionHeldItem=='frontier-short-sword')
            panel:update(); assert(presentations==1 and not panel:attack(a.x,a.y))
            clock=clock+1; view.elapsed=view.elapsed+1
            assert(panel:attack(a.x,a.y)); project(); panel:update(); assert(presentations==2)
        ''')

    def test_save_error_keeps_pending_until_durable_receipt(self):
        self.guest_view()
        self.lua.execute('''
            failSave=true; assert(panel:attack(a.x,a.y)); project(); panel:update()
            assert(panel.pending and panel.notice=='Waiting for the host to finish saving...')
            local condition=guest.itemSlots.equipment[1].durability
            failSave=false; assert(service:retryCheckpoint())
            network.lastCommandResult=service:execute('companion',1,network.request)
            project(); panel:update(); assert(not panel.pending and panel.lastOutcome.durable)
            assert(guest.itemSlots.equipment[1].durability==condition and presentations==1)
        ''')

    def test_baseline_does_not_replay_old_swing_and_remote_new_swing_is_visual_only(self):
        self.guest_view()
        self.lua.execute('''
            assert(swing('host').ok); project()
            panel=GuestField.new(view,{catalog=Catalog}); panel:update(); assert(presentations==0)
            clock=clock+1; assert(swing('host').ok); project(); panel:update()
            assert(presentations==1 and panel:presentation('host').actionTimer>0)
            local hp=a.hp; panel:update(); assert(presentations==1 and a.hp==hp)
            view.elapsed=view.elapsed+1; assert(panel:presentation('host').actionTimer==0)
        ''')

    def test_wrong_scene_and_input_capture_do_not_send_and_missing_weapon_is_explained(self):
        self.guest_view()
        self.lua.execute('''
            view.runtime.scene='train'; assert(not panel:attack() and sent==0)
            view.runtime.scene='expedition'; view.inputAllowed=function() return false end
            assert(not panel:attack() and sent==0)
            view.inputAllowed=function() return true end
            view.runtime.saveData.itemSlots.equipment[1].durability=0
            assert(not panel:attack() and sent==0 and panel.notice=='Equip a working melee weapon in your pack.')
        ''')

    def test_command_rejection_clears_pending_without_local_costs(self):
        self.guest_view()
        self.lua.execute('''
            states.companion.activityBlocked=true
            network.submitCommand=function(self,name,args,epoch,expected)
                self.lastCommandResult={ok=false,requestId=1,reason='field_unavailable'}; return 1
            end
            assert(panel:attack()); panel:update(); assert(not panel.pending and not panel.lastOutcome.ok)
            assert(guest.itemSlots.equipment[1].durability==100 and presentations==0)
        ''')


if __name__ == '__main__':
    unittest.main()
