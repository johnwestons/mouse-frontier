"""Native restart comparisons retain sparse real ownership maps exactly."""
import unittest
import test_coop_guns_behavior as guns
import test_coop_guest_ambush_behavior as guest


class AmbushCheckpointFixtureTests(unittest.TestCase):
    setUp = guns.AmbushCommandTests.setUp

    def test_actual_sparse_owned_slots_round_trip_and_detect_changed_item_durability(self):
        self.lua.execute('''
            setup(); Items.write(guest,nil,{kind='inventory',index=1},nil)
            Items.write(guest,nil,{kind='inventory',index=2},'frontier-22-lever-rifle')
            local Codec=require('game.net.codec')
            local Checkpoint=assert(loadfile('tools/guest-ambush-pressure-smoke/checkpoint.lua'))()
            local limits={maxBytes=65536,maxDepth=16,maxEntries=4096,maxStringBytes=256}
            local actor=data.players.companion
            local raw=Codec.encode({actor=actor},limits); assert(raw==nil,'fixture no longer exercises sparse ownership')
            local snapshot=Checkpoint.encode({actor=actor},limits); local restored=assert(Codec.decode(snapshot,limits))
            local slot=restored['string:actor']['string:itemSlots']['string:inventory']['number:2']
            assert(slot['string:id']==actor.itemSlots.inventory[2].id)
            assert(snapshot==Checkpoint.encode({actor=assert(Schema.copy(actor))},limits))
            actor.itemSlots.inventory[2].durability=actor.itemSlots.inventory[2].durability-1
            assert(snapshot~=Checkpoint.encode({actor=actor},limits))
        ''')


class AmbushReturnFixtureTests(unittest.TestCase):
    setUp = guest.GuestAmbushTests.setUp
    ambush = guest.GuestAmbushTests.ambush
    panel = guest.GuestAmbushTests.panel

    def test_real_continuation_clears_gun_but_allows_only_fresh_stop_motion(self):
        self.panel()
        self.lua.execute('''
            local Checkpoint=assert(loadfile('tools/guest-ambush-pressure-smoke/checkpoint.lua'))()
            require('game.coop_ambush_progression').install(service,ctx)
            local epoch=view.epoch
            assert(service:submitLocal('ambush.withdraw',{encounterId=convoy.entityId}).ok)
            Ambush.update(data,convoy,2.1,nil,{'host'})
            assert(service:submitLocal('ambush.continue',{encounterId=convoy.entityId}).ok)
            project(); view.runtime.scene=data.scene; view.epoch=data.coop.sceneEpoch; view.motionId=2
            panel:update(0); assert(not panel.gun and not panel:available())
            local View=require('game.coop_guest_view'); view.ambush=panel
            view.actionsAllowed=function() return true end
            view.activityBusy=function() return false end; view.objectsOpen=function() return false end
            view.inputAllowed=View.inputAllowed
            local frame={sceneEpoch=view.epoch,motionId=2,ready=false}
            assert(not Checkpoint.returnReady(view,frame,epoch))
            frame.ready=true; frame.sceneEpoch=epoch; assert(not Checkpoint.returnReady(view,frame,epoch))
            frame.sceneEpoch=view.epoch; frame.motionId=1; assert(not Checkpoint.returnReady(view,frame,epoch))
            frame.motionId=2; assert(Checkpoint.returnReady(view,frame,epoch))
            assert(not panel.gun and View.inputAllowed(view))
        ''')

    def test_numeric_and_string_keys_do_not_compare_as_the_same_saved_state(self):
        self.lua.execute('''
            local Checkpoint=assert(loadfile('tools/guest-ambush-pressure-smoke/checkpoint.lua'))()
            local limits={maxBytes=65536,maxDepth=16,maxEntries=4096,maxStringBytes=256}
            assert(Checkpoint.encode({[2]='owned'},limits)~=Checkpoint.encode({['2']='owned'},limits))
            assert(Checkpoint.encode({[2]='owned'},limits)~=Checkpoint.encode({[3]='owned'},limits))
        ''')

    def test_return_facts_allow_motion_but_detect_kit_health_magazine_and_shared_cost_changes(self):
        self.panel()
        self.lua.execute('''
            local Checkpoint=assert(loadfile('tools/guest-ambush-pressure-smoke/checkpoint.lua'))()
            local limits={maxBytes=65536,maxDepth=16,maxEntries=4096,maxStringBytes=256}
            local baseline=Checkpoint.returnFacts(data,limits)
            local copy=assert(Schema.copy(data)); copy.players.companion.playerX=(copy.players.companion.playerX or 0)+4
            assert(Checkpoint.returnFacts(copy,limits)==baseline)
            for _,edit in ipairs({function(d) d.players.host.health=d.players.host.health-1 end,
                function(d) d.players.companion.ammo['22lr']=d.players.companion.ammo['22lr']-1 end,
                function(d) d.players.companion.itemSlots.equipment[2].durability=d.players.companion.itemSlots.equipment[2].durability-1 end,
                function(d) d.trainAmbush.shooterSessions.companion.weaponSession.magazine=d.trainAmbush.shooterSessions.companion.weaponSession.magazine-1 end,
                function(d) d.resources.food=d.resources.food-1 end,
                function(d) d.scrap=d.scrap+5 end}) do
                local changed=assert(Schema.copy(data));edit(changed)
                assert(Checkpoint.returnFacts(changed,limits)~=baseline)
            end
        ''')


if __name__ == '__main__':
    unittest.main()
