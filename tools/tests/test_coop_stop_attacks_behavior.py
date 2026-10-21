"""Stop swings use the same damage rules for host and guest, with saved receipts."""
import unittest
import test_coop_roaming_behavior as field
import test_coop_guest_roaming_behavior as guest_field


class StopAttackTests(unittest.TestCase):
    setUp = field.RoamingCommandTests.setUp

    def stop(self):
        field.RoamingCommandTests.field(self)
        self.lua.execute('''
            data.scene='stop'; data.activeExpeditionArea=nil
            Sludges=require('game.stop_sludges')
            data.stopSludges={['6']={{x=700,y=600,hp=100,maxHp=100,dead=false}}}
            a=data.stopSludges['6'][1]
            for _,actor in pairs(states) do actor.scene='stop'; actor.x=700; actor.y=620 end
            function fieldArgs(id,extra)
                local value={areaId=Field.areaId(data),weaponId=Field.weapon(data,id,Catalog)}
                for key,v in pairs(extra or {}) do value[key]=v end
                return value
            end
        ''')

    def test_both_players_swing_and_damage_without_changing_stop_weapon_rules(self):
        self.stop()
        self.lua.execute('''
            for _,id in ipairs({'host','companion'}) do
                local hp=a.hp; local weapon=Players.get(data,id).itemSlots.equipment[1]
                local r=swing(id); assert(r.ok,r.reason)
                assert(a.hp==hp-r.result.damage and weapon.durability==100)
                assert(r.result.hitId=='sludge:6:1' and r.result.duration==.42)
                assert(swing(id).reason=='attack_cooldown')
            end
            assert(writes==2 and Schema.validate(saved) and Cue.validate(data))
            assert(require('game.net.game_state').project(data))
            local Public=require('game.net.item_results')
            assert(Public.valid('roaming.attack',assert(Public.project('roaming.attack',data.roamingCombat.actors.companion))))
        ''')

    def test_cursor_cannot_extend_reach_and_free_swing_uses_facing(self):
        self.stop()
        self.lua.execute('''
            a.x=300; a.y=480; states.companion.facing=-1
            local hp=a.hp; local r=swing('companion',{targetX=a.x,targetY=a.y})
            assert(r.ok and r.result.damage==0 and a.hp==hp and r.result.facing==-1)
            clock=clock+1; r=swing('companion')
            assert(r.ok and r.result.damage==0 and r.result.facing==-1 and Cue.validate(data))
        ''')

    def test_own_weapon_only_and_closed_scenes_block_attack(self):
        self.stop()
        self.lua.execute('''
            assert(swing('companion',{weaponId=host.itemSlots.equipment[1].id}).reason=='ownership')
            assert(swing('companion',{weaponId='scratch'}).reason=='ownership')
            guest.itemSlots.equipment[1].durability=0
            assert(swing('companion',{weaponId=guest.itemSlots.equipment[1].id}).reason=='weapon_broken')
            assert(swing('companion').ok and data.roamingCombat.actors.companion.weapon=='scratch')
            clock=clock+1
            for _,scene in ipairs({'house','train','caravan'}) do
                states.companion.scene=scene
                assert(swing('companion').reason=='field_unavailable')
            end
            states.companion.scene='stop'; states.companion.x=-10
            assert(swing('companion').reason=='field_unavailable')
        ''')

    def test_retried_kill_and_save_failure_apply_damage_and_drop_once(self):
        self.stop()
        self.lua.execute('''
            a.hp=1; failSave=true
            local request=assert(service:prepareRequest('companion','roaming.attack',fieldArgs('companion')))
            local r=service:execute('companion',1,request)
            assert(r.ok and r.savePending and a.dead and not a.dropDone)
            local serial=data.roamingCombat.serial; local rng=data.coop.randomState
            assert(service:execute('companion',1,request).ok)
            assert(data.roamingCombat.serial==serial and data.coop.randomState==rng)
            failSave=false; assert(service:retryCheckpoint())
            assert(service:execute('companion',1,request).durable)
            local drops=0; local sys=Sludges.new()
            local ctx={data=data,location=6,player=states.host,dropCoal=function() drops=drops+1 end}
            Sludges.update(sys,ctx,2); Sludges.update(sys,ctx,2)
            assert(drops==1 and a.dropDone and Schema.validate(saved))
        ''')

    def test_corrupt_saved_hit_references_are_rejected(self):
        self.stop()
        self.lua.execute('''
            assert(swing('companion').ok)
            for _,key in ipairs({'hitId','mobId','areaId'}) do
                local copy=assert(Schema.copy(data)); copy.roamingCombat.actors.companion[key]='unknown'
                assert(not Cue.validate(copy),key)
            end
            local copy=assert(Schema.copy(data)); copy.roamingCombat.actors.companion.alerts={'1'}
            assert(not Cue.validate(copy))
        ''')


class GuestStopAttackTests(unittest.TestCase):
    setUp = field.RoamingCommandTests.setUp

    def test_stop_touch_button_sends_owned_swing_and_animates_saved_result(self):
        guest_field.GuestFieldTests.guest_view(self)
        self.lua.execute('''
            source.scene='stop'; view.runtime.scene='stop'
            for _,actor in pairs(states) do actor.scene='stop' end
            source.stopSludges={['6']={{x=700,y=600,hp=100,maxHp=100,dead=false}}}
            project(); assert(panel:available())
            view.ui.guestFieldAttack={x=764,y=510,w=180,h=56}
            assert(panel:pointer(800,540)); assert(sent==1 and panel.pending)
            assert(network.request.args.areaId=='stop:6')
            project(); panel:update()
            assert(presentations==1 and panel:presentation('companion').actionTimer>0)
            assert(source.stopSludges['6'][1].hp<100)
            view.runtime.scene='house'; assert(not panel:available())
        ''')


if __name__ == '__main__':
    unittest.main()
