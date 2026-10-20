"""Thumb aiming stays precise, independent of firing, and local to its round."""
import unittest
import test_mobile_weapon_aim_behavior as mobile
import test_coop_guest_range_behavior as guest_range
import test_coop_guest_ambush_behavior as guest_ambush
import test_coop_guest_last_stand_shooter_behavior as guest_defense
import test_coop_last_stand_source_behavior as defense
import test_coop_ambush_lifecycle_behavior as ambush


class MobileShooterControlsTests(unittest.TestCase):
    setUp = mobile.MobileWeaponAimBehaviorTests.setUp

    def test_precision_fast_sweep_ads_and_frame_rate(self):
        self.lua.execute('''
            local Pad=require('game.mobile_shooter_controls')
            function sweep(amount,ads,fps,dx,dy)
                local p=Pad.new(); local l=Pad.layout(960,720)
                p:press('aim',l.x,l.y,960,720)
                p:move('aim',l.x+l.r*amount*(dx or 1),l.y+l.r*amount*(dy or 0),960,720)
                local gun={aimX=0,aimY=0,ads=ads}
                for i=1,fps/2 do
                    local x,y=p:step(1/fps,gun,960,720)
                    if x then gun.aimX,gun.aimY=x,y end
                end
                return math.sqrt(gun.aimX^2+gun.aimY^2)
            end
            close(sweep(.09,false,60),0,'resting thumb drift')
            local fine,fast=sweep(.25,false,60),sweep(1,false,60)
            assert(fine>5 and fine<20 and fast>400,'precision/fast travel bands')
            close(sweep(1,false,30),fast); close(sweep(1,false,120),fast)
            close(sweep(1,true,60),fast*.55,'ADS slowdown')
            close(sweep(1,false,60,1,1),fast,'diagonals must not be faster')
        ''')

    def test_range_aim_and_fire_are_separate_and_release_stops_immediately(self):
        self.lua.execute('''
            local h=newRangeHarness(2); local c=h.controls
            c:touchpressed('aim',224,1000)
            local x,y=h.session.aimX,h.session.aimY
            c:update(.016); close(h.session.aimX,x); close(h.session.aimY,y)
            c:touchmoved('aim',352,1000,128,0); c:update(.05)
            assert(h.session.aimX>x+40 and h.session.aimY==y and h.session.shots==0)
            x=h.session.aimX; h:targetAtAim()
            c:touchpressed('fire',1704,1000)
            assert(h.session.shots==1 and h.session.hits==1)
            close(h.session.aimX,x); close(h.session.aimY,y)
            c:touchmoved('fire',800,400,-904,-600)
            assert(c.rangePad.aimTouch=='aim')
            c:touchreleased('aim',352,1000); c:update(.05)
            close(h.session.aimX,x); assert(c.rangePad.fireTouch=='fire')
            c:touchreleased('fire',800,400)
            assert(c.rangePad.fireTouch==nil and h.released[#h.released]=='space')
        ''')

    def test_range_snapshot_refresh_preserves_stick_but_new_round_cancels_it(self):
        self.lua.execute('''
            local h=newRangeHarness(); local c=h.controls
            h.session.entityId='range:1'; h.session.roundRevision=3
            c:touchpressed('aim',176,500); c:update(.016)
            local replacement={}; for k,v in pairs(h.session) do replacement[k]=v end
            h.session=replacement; local x=h.session.aimX
            c:update(.016); assert(h.session.aimX>x and c.rangePad.aimTouch=='aim')
            local nextRound={}; for k,v in pairs(h.session) do nextRound[k]=v end
            nextRound.roundRevision=4; h.session=nextRound; x=h.session.aimX
            c:update(.016); close(h.session.aimX,x); assert(c.rangePad.aimTouch==nil)
            c:touchmoved('aim',176,520,0,20); c:update(.016); close(h.session.aimX,x)
            c:touchpressed('new',176,500); c:touchreleased('aim',176,520)
            assert(c.rangePad.aimTouch=='new')
            c:cancelAll(); c:update(.016); close(h.session.aimX,x)
        ''')

    def test_ownership_edges_and_pause_cancellation(self):
        self.lua.execute('''
            local Pad=require('game.mobile_shooter_controls'); local p=Pad.new()
            assert(p:press('first',112,500)=='aim')
            assert(p:press('second',112,500)=='blocked')
            p:move('second',176,500); assert(p.x==0)
            p:move('first',10000,-10000)
            local x,y=p:step(.05,{aimX=929,aimY=56},960,720,{left=30,top=55,right=930,bottom=625})
            assert(x==930 and y==55)
            p:release('second'); assert(p.aimTouch=='first')
            p:cancel(); assert(p:step(.05,{aimX=480,aimY=330},960,720)==nil)
            assert(not p:move('first',176,500))
            for _,size in ipairs({{960,720},{1280,720},{640,480},{720,960}}) do
                local l=Pad.layout(size[1],size[2])
                assert(l.x-l.r>=0 and l.fireX+l.fireR<=size[1] and l.y+l.r<size[2])
            end
        ''')

    def test_range_pause_releases_auto_fire_and_old_touch_cannot_restart_it(self):
        self.lua.execute('''
            local h=newRangeHarness(); local c=h.controls
            c.releaseKey=function(key) Range.keyreleased(h.session,key) end
            c:touchpressed('fire',852,500); assert(h.session.fireHeld)
            c.shootingRangeActive=function() return false end
            c:update(.02); assert(not h.session.fireHeld and not c.rangePad.fireTouch)
            c.shootingRangeActive=function() return h.session end
            c:update(.02); c:touchmoved('fire',852,500,0,0)
            assert(not h.session.fireHeld and not c.rangePad.fireTouch)
        ''')


class GuestRangeJoystickTests(unittest.TestCase):
    setUp = guest_range.GuestRangeTests.setUp
    range = guest_range.GuestRangeTests.range

    def test_stick_keeps_aiming_during_fire_receipt_and_pause_clears_it(self):
        self.range()
        self.lua.execute('''
            playing(); panel:touchpressed('aim',176,500)
            local x=panel.pose.aimX; panel:update(.02); assert(panel.pose.aimX>x)
            panel:touchpressed('fire',852,500); assert(panel.pending.name=='range.fire')
            x=panel.pose.aimX; panel:update(.02); assert(panel.pose.aimX>x)
            panel:touchreleased('aim'); x=panel.pose.aimX
            panel:touchpressed('aim2',112,500); assert(panel.pose.aimX==x)
            panel:touchmoved('aim2',176,500); panel:update(.02); assert(panel.pose.aimX>x)
            panel:touchreleased('fire'); assert(not panel.held.pad)
            panel:keypressed('p'); x=panel.pose.aimX; panel:update(.02)
            assert(panel.pose.aimX==x and not panel.aimPad.aimTouch)
        ''')


class GuestAmbushJoystickTests(unittest.TestCase):
    setUp = guest_ambush.GuestAmbushTests.setUp
    ambush = guest_ambush.GuestAmbushTests.ambush
    panel = guest_ambush.GuestAmbushTests.panel

    def test_aim_and_fire_use_private_gun_and_keep_moving_during_receipt(self):
        self.panel()
        self.lua.execute('''
            panel:touchpressed('aim',176,500); local x=panel.gun.aimX
            panel:update(.02); assert(panel.gun.aimX>x)
            panel:touchpressed('fire',852,500); assert(panel.pending.name=='gun.fire')
            x=panel.gun.aimX; panel:update(.02); assert(panel.gun.aimX>x)
            panel:touchreleased('aim'); x=panel.gun.aimX
            panel:touchpressed('aim2',112,500); assert(panel.gun.aimX==x)
            panel:touchmoved('aim2',176,500); panel:update(.02); assert(panel.gun.aimX>x)
            panel:touchreleased('fire'); assert(not panel.held.pad)
            panel:suspend(); x=panel.gun.aimX; panel:update(.02); assert(panel.gun.aimX==x)
        ''')


class GuestDefenseJoystickTests(unittest.TestCase):
    setUp = guest_defense.GuestLastStandShooterTests.setUp
    farm = guest_defense.GuestLastStandShooterTests.farm
    shooter = guest_defense.GuestLastStandShooterTests.shooter

    def test_two_thumb_controls_route_through_real_guest_view(self):
        self.shooter()
        self.lua.execute('''
            positioned(); view:touchpressed('aim',176,500)
            local x=panel.gun.aimX; panel:update(.02); assert(panel.gun.aimX>x)
            view:touchpressed('fire',852,500); assert(panel.pending.name=='gun.fire')
            x=panel.gun.aimX; panel:update(.02); assert(panel.gun.aimX>x)
            view:touchreleased('aim',176,500); view:touchreleased('fire',852,500)
            assert(not panel.held.pad and not panel.aimTouch)
            x=panel.gun.aimX; panel:update(.02); assert(panel.gun.aimX==x)
        ''')


class HostDefenseJoystickTests(unittest.TestCase):
    setUp = defense.LastStandSourceTests.setUp

    def test_stick_bypasses_zoom_and_pause_drops_held_input(self):
        self.lua.execute('''
            assert(Source:zoomField(112,500)==nil and Source:zoomField(852,500)==nil)
            Source:touchpressed('aim',176,500); local x=battle.gun.aimX
            sourceTick(.02); assert(battle.gun.aimX>x)
            Source:touchpressed('fire',852,500); assert(battle.fireHeldSources.pad)
            Source:touchreleased('aim',176,500); assert(battle.fireHeldSources.pad)
            Source:touchreleased('fire',852,500); assert(not battle.fireHeldSources.pad)
            Source:touchpressed('aim2',176,500); privatePaused=true
            x=battle.gun.aimX; sourceTick(.02)
            assert(battle.gun.aimX==x and not runtime.lastStand.aimPad.aimTouch)
        ''')


class HostAmbushJoystickTests(unittest.TestCase):
    setUp = ambush.AmbushReadinessTests.setUp
    source = ambush.AmbushReadinessTests.source

    def test_stick_changes_the_drawn_gun_without_firing_and_stops_on_focus_loss(self):
        self.source()
        self.lua.execute('''
            local latest; local original=Shooting.setAim
            Shooting.setAim=function(gun,x,y) latest=gun; original(gun,x,y) end
            input:touchpressed('aim',176,500); input:update(.02)
            assert(latest and latest.aimX>250 and convoy.shots==0)
            local x=latest.aimX; input:focus(false); input:update(.02)
            assert(latest.aimX==x)
            input:keypressed('p'); input:update(.02); assert(latest.aimX==x)
        ''')


if __name__ == '__main__':
    unittest.main()
