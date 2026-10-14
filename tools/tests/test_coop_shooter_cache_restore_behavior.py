"""Gun restoration after selection/loan loss must retain exact owned history."""
import unittest
import test_coop_shooter_sessions_behavior as sessions


class ShooterCacheRestoreTests(unittest.TestCase):
    setUp = sessions.ShooterSessionTests.setUp

    def test_both_actor_caches_restore_after_loan_reclaim_without_refill(self):
        self.lua.execute('''
            local hi,gi=hg.itemId,gg.itemId; hg.magazine=2; gg.magazine=3
            hg=Shooting.useLoan(hg,host,Catalog,quest); gg=Shooting.useLoan(gg,guest,Catalog,quest)
            local hc=quest.weaponSessions[hi]; local scope=quest.shooterSessions.companion; local gc=scope.weaponSessions[gi]
            hc.cooldown=.2; gc.reloadTimer=.7
            Sessions.reclaim(quest); assert(not quest.weaponSession and not scope.weaponSession)
            local h=Shooting.new(host,Catalog,quest,960,720); local g=Shooting.new(guest,Catalog,quest,960,720)
            assert(h.itemId==hi and g.itemId==gi and h.magazine==2 and g.magazine==3)
            assert(h.cooldown==.2 and g.reloadTimer==.7 and host.ammo['22lr']==20 and guest.ammo['22lr']==9)
            assert(quest.loanAmmo==0 and scope.loanAmmo==0 and not h.borrowed and not g.borrowed)
            assert(quest.weaponSession==hc and scope.weaponSession==gc and Schema.validate(data))
        ''')

    def test_missing_current_restores_exact_item_and_clears_held_device_controls(self):
        self.lua.execute('''
            local scope=quest.shooterSessions.companion; local id=gg.itemId
            gg.magazine=3; gg.cooldown=.3; gg.fireHeld=true; gg.fireHeldSources={mouse=true}; gg.ads=true; gg.touchAim={x=18,y=20}
            scope.weaponSessions={[id]=Sessions.record(gg)}; scope.weaponSession=nil
            local gun=Shooting.new(guest,Catalog,quest,960,720)
            assert(gun.itemId==id and gun.magazine==3 and gun.cooldown==.3)
            assert(not gun.fireHeld and next(gun.fireHeldSources)==nil and not gun.ads and not gun.touchAim)
            local copy,h,g,hgun,ggun=loaded()
            assert(ggun.itemId==id and ggun.magazine==3 and ggun.cooldown==.3 and g.ammo['22lr']==9)
            assert(Schema.validate(copy))
        ''')

    def test_inert_removed_current_falls_back_to_another_exact_cached_duplicate(self):
        self.lua.execute('''
            local original=gg.itemId; Items.write(guest,nil,{kind='inventory',index=1},'frontier-22-lever-rifle')
            local second=Items.get(guest,nil,{kind='inventory',index=1}).id
            local other=Shooting.chooseWeapon(gg,{name='frontier-22-lever-rifle',itemId=second,borrowed=false},guest,Catalog,quest)
            other.magazine=2; other.cooldown=.4
            local scope=quest.shooterSessions.companion
            gg=Shooting.chooseWeapon(other,{name='frontier-22-lever-rifle',itemId=original,borrowed=false},guest,Catalog,quest)
            Items.write(guest,nil,{kind='equipment',index=2},nil)
            local restored=Shooting.new(guest,Catalog,quest,960,720)
            assert(restored.itemId==second and restored.itemId~=original and restored.magazine==2 and restored.cooldown==.4)
            assert(guest.ammo['22lr']==9 and scope.weaponSessions[second].magazine==2 and Schema.validate(data))
        ''')

    def test_cache_owner_and_exact_item_mismatch_cannot_be_adopted(self):
        self.lua.execute('''
            local scope=quest.shooterSessions.companion; local id=gg.itemId
            local foreign=assert(Schema.copy(Sessions.record(hg))); foreign.magazine=2; foreign.cooldown=.5
            scope.weaponSession=nil; scope.weaponSessions={[id]=foreign}
            local fresh=Shooting.new(guest,Catalog,quest,960,720)
            assert(fresh.actorId=='companion' and fresh.itemId==id and fresh.magazine~=2 and fresh.cooldown==0)
            assert(foreign.actorId=='host' and foreign.magazine==2 and foreign.cooldown==.5)
            foreign.actorId='companion'; scope.weaponSession=nil
            fresh=Shooting.new(guest,Catalog,quest,960,720)
            assert(fresh.itemId==id and fresh.itemId~=foreign.itemId and fresh.magazine~=2)
            assert(host.ammo['22lr']==20 and guest.ammo['22lr']==9)
        ''')

    def test_broken_or_no_longer_owned_cache_is_not_restored(self):
        self.lua.execute('''
            local scope=quest.shooterSessions.companion; local id=gg.itemId
            gg.magazine=2; scope.weaponSessions={[id]=Sessions.record(gg)}; scope.weaponSession=nil
            assert(Items.setCondition(guest,id,0)); local fresh=Shooting.new(guest,Catalog,quest,960,720)
            assert(not fresh.weapon and scope.weaponSessions[id].magazine==2 and guest.ammo['22lr']==9)
            Items.write(guest,nil,{kind='equipment',index=2},nil); scope.weaponSession=nil
            fresh=Shooting.new(guest,Catalog,quest,960,720)
            assert(not fresh.weapon and fresh.actorId=='companion' and guest.ammo['22lr']==9 and host.ammo['22lr']==20)
            assert(Schema.validate(data))
        ''')

    def test_restored_magazine_obeys_actual_ammo_without_resetting_cooldown(self):
        self.lua.execute('''
            local scope=quest.shooterSessions.companion; local id=gg.itemId
            gg.magazine=7; gg.cooldown=.4; scope.weaponSessions={[id]=Sessions.record(gg)}; scope.weaponSession=nil
            guest.ammo['22lr']=2; local restored=Shooting.new(guest,Catalog,quest,960,720)
            assert(restored.magazine==2 and restored.cooldown==.4 and guest.ammo['22lr']==2)
            assert(scope.weaponSession.itemId==id and host.ammo['22lr']==20 and Schema.validate(data))
        ''')


if __name__ == '__main__':
    unittest.main()
