"""Owned first-person gun records, private controls, saves and projection."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class ShooterSessionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=function() return .5 end}}
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            Catalog=require('game.catalog'); Items=require('game.item_instances'); Players=require('game.coop_players')
            Shooting=require('game.first_person_shooting'); Sessions=require('game.coop_shooter_sessions')
            data=F.campaign(6); assert(F.enroll(data))
            host=Players.forActor(data,'host'); guest=Players.forActor(data,'companion')
            Items.write(host,nil,{kind='equipment',index=2},'frontier-22-lever-rifle')
            Items.write(guest,nil,{kind='equipment',index=2},'frontier-22-lever-rifle')
            host.ammo['22lr']=20; guest.ammo['22lr']=9
            data.trainAmbush={active=true,phase='combat',location=6}; quest=data.trainAmbush
            hg=Shooting.new(host,Catalog,quest,960,720); gg=Shooting.new(guest,Catalog,quest,960,720)
            function loaded()
                local copy=assert(Schema.migrate(data))
                local h=Players.forActor(copy,'host'); local g=Players.forActor(copy,'companion')
                return copy,h,g,Shooting.new(h,Catalog,copy.trainAmbush,960,720),Shooting.new(g,Catalog,copy.trainAmbush,960,720)
            end
        ''')

    def test_two_actors_use_own_identical_weapon_instances_and_ammunition(self):
        self.lua.execute('''
            assert(Players.actorId(host)=='host' and Players.actorId(guest)=='companion' and Players.actorId(data)=='host')
            assert(hg.actorId=='host' and gg.actorId=='companion' and hg.itemId~=gg.itemId)
            local hmag=hg.magazine; assert(Shooting.fire(gg,guest,quest))
            assert(guest.ammo['22lr']==8 and host.ammo['22lr']==20 and hg.magazine==hmag)
            assert(quest.weaponSession==Sessions.record(hg) and quest.shooterSessions.companion.weaponSession==Sessions.record(gg))
            assert(Schema.validate(data))
            local d,h,g,hgun,ggun=loaded()
            assert(hgun.itemId==hg.itemId and ggun.itemId==gg.itemId and ggun.magazine==gg.magazine)
            assert(ggun.cooldown==gg.cooldown and h.ammo['22lr']==20 and g.ammo['22lr']==8)
        ''')

    def test_action_serial_survives_save_cache_and_legacy_missing_serial(self):
        self.lua.execute('''
            assert(gg.weaponActionSerial==nil and Schema.validate(data))
            assert(Shooting.fire(gg,guest,quest)); local serial=gg.weaponActionSerial
            assert(serial==1 and Schema.validate(data))
            local d,h,g,hgun,ggun=loaded(); assert(ggun.weaponActionSerial==serial)
            Shooting.update(ggun,1,g,d.trainAmbush,960,720)
            ggun.magazine=1
            assert(Shooting.reload(ggun,g,d.trainAmbush) and ggun.weaponActionSerial==serial+1)
            Shooting.useLoan(ggun,g,Catalog,d.trainAmbush)
            assert(d.trainAmbush.shooterSessions.companion.weaponSessions[gg.itemId].weaponActionSerial==serial+1)
            assert(Schema.validate(d))
            for _,bad in ipairs({0,-1,1.5,1000000001,'1',math.huge}) do
                local copy=assert(Schema.copy(d))
                copy.trainAmbush.shooterSessions.companion.weaponSession.weaponActionSerial=bad
                assert(not Schema.validate(copy))
            end
        ''')

    def test_private_reload_frames_advance_without_loading_or_spending_and_reset_on_new_action(self):
        self.lua.execute('''
            local A=require('game.first_person_weapon_actions')
            gg.magazine=1; assert(Shooting.reload(gg,guest,quest))
            local source=assert(Schema.copy(Sessions.record(gg)))
            local private=assert(Schema.copy(source)); local profile=require('game.first_person_weapon_manifest').reloadProfileFor(gg.weapon)
            A.update(private,profile.startSeconds+profile.roundSeconds+.03)
            local nextFrame=assert(Schema.copy(source)); A.preservePresentation(nextFrame,private)
            assert(nextFrame.weaponActionElapsed==private.weaponActionElapsed)
            assert(nextFrame.tubeReloadRemaining==private.tubeReloadRemaining and nextFrame.tubeReloadRoundTimer==private.tubeReloadRoundTimer)
            assert(nextFrame.magazine==source.magazine and nextFrame.reloadTimer==source.reloadTimer and guest.ammo['22lr']==9)
            assert(gg.weaponActionElapsed==0 and gg.tubeReloadRemaining==source.tubeReloadRemaining)
            A.finish(nextFrame); A.preservePresentation(nextFrame,private); assert(nextFrame.weaponAction==nil)
            for _,reset in ipairs({
                function(s) A.beginReload(s,2) end,
                function(s) s.itemId='i9999' end,
                function(s) s.weaponActionSerial=nil end}) do
                local nextFrame=assert(Schema.copy(source)); reset(nextFrame); A.preservePresentation(nextFrame,private)
                assert(nextFrame.weaponActionElapsed==0)
            end
            gg.weaponActionSerial=1000000000; A.beginFire(gg); assert(gg.weaponActionSerial==1)
        ''')

    def test_aim_ads_touch_held_fire_and_device_geometry_are_private(self):
        self.lua.execute('''
            Shooting.setAim(hg,220,170); Shooting.setADS(hg,true); hg.fireHeld=true; hg.fireHeldSources={mouse=true}
            gg.aimX=800; gg.aimY=250; gg.ads=false; gg.touchAim={x=800,y=250}; gg.weaponX=910
            local copy=assert(Schema.copy(data))
            for _,gun in ipairs({copy.trainAmbush.weaponSession,copy.trainAmbush.shooterSessions.companion.weaponSession}) do
                for _,key in ipairs({'aimX','aimY','ads','touchAim','weaponX','weaponY','fireHeld','fireHeldSources'}) do assert(gun[key]==nil,key) end
            end
            assert(hg.aimX==220 and hg.ads and gg.aimX==800 and not gg.ads)
            local d,h,g,hgun,ggun=loaded()
            assert(hgun.aimX==480 and ggun.aimX==480 and not hgun.ads and not ggun.ads)
            assert(not hgun.fireHeld and not ggun.touchAim and hgun.weaponX==960*.68)
        ''')

    def test_foreign_owned_and_borrowed_guns_cannot_spend_or_advance_another_actor(self):
        self.lua.execute('''
            assert(not Shooting.fire(hg,guest,quest) and not Shooting.reload(hg,guest,quest))
            hg.cooldown=.7; assert(not Shooting.update(hg,1,guest,quest) and hg.cooldown==.7)
            local other=Shooting.weaponOptions(guest,Catalog)[1]
            assert(Shooting.chooseWeapon(hg,other,guest,Catalog,quest)==hg and hg.itemId~=gg.itemId)
            hg.cooldown=0; hg=Shooting.useLoan(hg,host,Catalog,quest); gg=Shooting.useLoan(gg,guest,Catalog,quest)
            assert(hg.borrowed and gg.borrowed and quest.loanAmmo==48 and quest.shooterSessions.companion.loanAmmo==48)
            local hmag=hg.magazine
            assert(not Shooting.fire(hg,guest,quest) and not Shooting.reload(hg,guest,quest))
            assert(Shooting.rounds(hg,guest,quest)==0 and Shooting.needsSupply(hg,guest,quest))
            assert(hg.magazine==hmag and quest.loanAmmo==48 and quest.shooterSessions.companion.loanAmmo==48)
        ''')

    def test_independent_loan_ammo_and_resupply_survive_restore(self):
        self.lua.execute('''
            hg=Shooting.useLoan(hg,host,Catalog,quest); gg=Shooting.useLoan(gg,guest,Catalog,quest)
            assert(Shooting.fire(gg,guest,quest))
            assert(quest.loanAmmo==48 and quest.shooterSessions.companion.loanAmmo==47 and host.ammo['22lr']==20 and guest.ammo['22lr']==9)
            local d,h,g,hgun,ggun=loaded()
            assert(hgun.borrowed and ggun.borrowed and ggun.magazine==gg.magazine)
            assert(d.trainAmbush.loanAmmo==48 and d.trainAmbush.shooterSessions.companion.loanAmmo==47)
            d.trainAmbush.shooterSessions.companion.loanAmmo=0; ggun.magazine=0; ggun.cooldown=0
            assert(Shooting.useLoan(ggun,g,Catalog,d.trainAmbush)==ggun)
            assert(d.trainAmbush.shooterSessions.companion.loanAmmo==12 and d.trainAmbush.loanAmmo==48)
        ''')

    def test_partial_authored_tube_reload_preserves_inserted_rounds_and_remaining_stage(self):
        self.lua.execute('''
            gg.magazine=1; assert(Shooting.reload(gg,guest,quest))
            local profile=require('game.first_person_weapon_manifest').reloadProfileFor(gg.weapon)
            Shooting.update(gg,profile.startSeconds+profile.roundSeconds+.01,guest,quest,960,720)
            local mag,timer,remaining,elapsed=gg.magazine,gg.reloadTimer,gg.tubeReloadRemaining,gg.weaponActionElapsed
            assert(mag>0 and timer>0 and remaining>0 and gg.weaponAction=='reload')
            local d,h,g,hgun,ggun=loaded()
            assert(ggun.magazine==mag and ggun.reloadTimer==timer and ggun.tubeReloadRemaining==remaining and ggun.weaponActionElapsed==elapsed)
            Shooting.update(ggun,.02,g,d.trainAmbush,960,720)
            assert(ggun.reloadTimer<timer and g.ammo['22lr']==9 and h.ammo['22lr']==20)
            assert(Schema.validate(d))
        ''')

    def test_switching_duplicate_guns_retains_exact_partial_magazine_and_cooldown(self):
        self.lua.execute('''
            Items.write(guest,nil,{kind='inventory',index=3},'frontier-22-lever-rifle')
            local first=gg.itemId; assert(Shooting.fire(gg,guest,quest)); local mag,delay=gg.magazine,gg.cooldown
            local alternate,original
            for _,option in ipairs(Shooting.weaponOptions(guest,Catalog)) do
                if option.itemId==first then original=option elseif not option.borrowed then alternate=option end
            end
            gg=Shooting.chooseWeapon(gg,alternate,guest,Catalog,quest)
            assert(gg.itemId~=first and quest.shooterSessions.companion.weaponSessions[first].magazine==mag)
            gg=Shooting.chooseWeapon(gg,original,guest,Catalog,quest)
            assert(gg.itemId==first and gg.magazine==mag and gg.cooldown==delay)
            local d,h,g,hgun,ggun=loaded(); assert(ggun.itemId==first and ggun.magazine==mag and ggun.cooldown==delay)
            assert(hgun.itemId==hg.itemId and hgun.magazine==hg.magazine)
        ''')

    def test_legacy_host_session_migration_removes_device_controls_without_refilling(self):
        self.lua.execute('''
            local raw=assert(Schema.copy(data)); raw.trainAmbush.shooterSessions=nil; raw.trainAmbush.shooterVersion=nil
            local gun=raw.trainAmbush.weaponSession; gun.actorId=nil; gun.itemId=nil; gun.magazine=2; gun.cooldown=.4
            gun.aimX=17; gun.ads=true; gun.touchAim={x=18}; gun.fireHeld=true
            raw.trainAmbush.weaponSessions={[gun.weapon]=assert(Schema.copy(gun))}
            local migrated=assert(Schema.migrate(raw)); gun=migrated.trainAmbush.weaponSession
            assert(gun.actorId=='host' and gun.itemId==hg.itemId and gun.magazine==2 and gun.cooldown==.4)
            assert(not gun.ads and not gun.aimX and migrated.trainAmbush.weaponSessions[hg.itemId].magazine==2)
            assert(not migrated.trainAmbush.weaponSessions[gun.weapon])
            local guestGun=Shooting.new(Players.forActor(migrated,'companion'),Catalog,migrated.trainAmbush,960,720)
            assert(guestGun.itemId==gg.itemId and guestGun.actorId=='companion' and guestGun.magazine~=2)
        ''')

    def test_malformed_saved_owner_frames_counts_and_foreign_record_are_rejected(self):
        self.lua.execute('''
            for _,edit in ipairs({
                function(d) d.trainAmbush.shooterSessions.evil={} end,
                function(d) d.trainAmbush.shooterSessions.companion.weaponSession.actorId='host' end,
                function(d) d.trainAmbush.shooterSessions.companion.weaponSession.magazine=999 end,
                function(d) d.trainAmbush.shooterSessions.companion.weaponSession.reloadTimer=-1 end,
                function(d) d.trainAmbush.shooterSessions.companion.weaponSession.fireMode='invented' end,
                function(d) d.trainAmbush.shooterSessions.companion.weaponSession.ads=true end,
                function(d) d.trainAmbush.shooterSessions.companion.storyChoice=true end,
                function(d) d.trainAmbush.shooterSessions.companion.loanAmmo=-2 end}) do
                local copy=assert(Schema.copy(data)); edit(copy); assert(not Schema.validate(copy))
            end
        ''')

    def test_unavailable_name_only_legacy_gun_does_not_block_the_campaign_or_create_ammo(self):
        self.lua.execute('''
            local raw=assert(Schema.copy(data)); raw.trainAmbush.shooterSessions=nil; raw.trainAmbush.shooterVersion=nil
            local gun=raw.trainAmbush.weaponSession; gun.actorId=nil; gun.itemId=nil; gun.magazine=2
            raw.trainAmbush.weaponSessions={[gun.weapon]=assert(Schema.copy(gun))}
            Items.write(Players.forActor(raw,'host'),nil,{kind='equipment',index=2},nil)
            local migrated=assert(Schema.migrate(raw))
            assert(not migrated.trainAmbush.weaponSession and next(migrated.trainAmbush.weaponSessions)==nil)
            assert(migrated.players.host.ammo['22lr']==20 and migrated.players.companion.ammo['22lr']==9)
            assert(migrated.trainAmbush.active and migrated.trainAmbush.phase=='combat' and migrated.location==6)
            assert(migrated.players.companion.itemSlots.equipment[2].id==gg.itemId)
            local current=Shooting.new(migrated,Catalog,migrated.trainAmbush,960,720)
            assert(not current.weapon and current.actorId=='host' and Schema.validate(migrated))
        ''')

    def test_public_projection_preserves_both_guns_without_device_input(self):
        self.lua.execute('''
            gg.aimX=240; gg.ads=true; gg.touchAim={x=240}; assert(Shooting.fire(gg,guest,quest))
            local GameState=require('game.net.game_state'); local producer=GameState.producer()
            local baseline,reason=producer:capture(data,true); assert(baseline,reason)
            local replica=GameState.replica(); assert(replica:apply(baseline))
            local q=replica.data.trainAmbush; assert(q.weaponSession.itemId==hg.itemId and q.shooterSessions.companion.weaponSession.itemId==gg.itemId)
            assert(q.shooterSessions.companion.weaponSession.magazine==gg.magazine and q.shooterSessions.companion.weaponSession.actorId=='companion')
            assert(not q.weaponSession.aimX and not q.shooterSessions.companion.weaponSession.ads)
            assert(not Schema.validate(replica.data))
        ''')
