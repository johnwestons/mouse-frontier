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

    def test_corner_near_miss_is_owned_and_never_becomes_direct_aim(self):
        self.lua.execute('''
            local Pad=require('game.mobile_shooter_controls')
            local h=newRangeHarness(2); local c=h.controls; local p=Pad.layout(960,720)
            local x,y=h.session.aimX,h.session.aimY
            -- Deliberately outside the visible circle, near the bottom corner.
            local tx,ty=5,p.guardBottom-2
            assert((tx-p.x)^2+(ty-p.y)^2>p.r^2)
            c:touchpressed('corner',tx*2,ty*2)
            assert(c.rangePad.aimTouch=='corner' and c.touches.corner.kind=='rangePad')
            close(h.session.aimX,x); close(h.session.aimY,y)
            c:touchpressed('second',tx*2,ty*2)
            assert(c.touches.second.action=='blocked' and h.session.shots==0)
            c:touchmoved('corner',1200,200,0,0)
            assert(h.moves==0 and c.rangePad.aimTouch=='corner')
            c:touchreleased('second',tx*2,ty*2)
            assert(c.rangePad.aimTouch=='corner')
            c:touchreleased('corner',1200,200)
            assert(not c.rangePad.aimTouch)
            for _,size in ipairs({{960,720},{1440,720},{640,480},{720,960}}) do
                local w,h=size[1],size[2]; local l=Pad.layout(w,h); local scale=math.min(w/960,h/720)
                assert(l.guardBottom<h-104*scale,'capture region blocks the footer')
                assert(Pad.hit(5*scale,l.guardBottom-2*scale,w,h)=='aim')
                assert(Pad.hit(w-5*scale,l.guardBottom-2*scale,w,h)=='fire')
                assert(Pad.hit(l.x,h-80*scale,w,h)==nil)
                assert(l.x+l.r<145*scale and l.y>540*scale)
            end
        ''')

    def test_assist_strength_distance_manual_override_and_no_idle_drift(self):
        self.lua.execute('''
            local Pad=require('game.mobile_shooter_controls'); local p=Pad.new()
            local l=Pad.layout(960,720); p:press('aim',l.x,l.y,960,720)
            local gun={aimX=400,aimY=300}; local targets={{x=440,y=320,radius=16}}
            assert(p:step(.016,gun,960,720,nil,{aimAssist=1},targets)==nil)
            p:move('aim',l.x+l.r*.25,l.y,960,720)
            local function step(strength,list,speed)
                return p:step(.016,gun,960,720,nil,{aimAssist=strength,aimSensitivity=speed or 1},list or targets)
            end
            local offX,offY=step(0); close(offY,300)
            local weakX,weakY=step(.25); local strongX,strongY=step(1)
            assert(strongX>weakX and weakX>offX and strongY>weakY and weakY>offY)
            assert(strongX<440 and strongY<320,'assist snapped or overshot target')
            local x,y=step(1,{{x=800,y=300}}); close(x,offX); close(y,offY)
            x,y=step(1,{{x=380,y=300}}); close(x,offX); close(y,offY)
            local slow=step(0,nil,.5); local fast=step(0,nil,2)
            close(fast-400,(slow-400)*4,'saved sensitivity range')
            p:move('aim',l.x+l.r,l.y,960,720)
            offX,offY=step(0); x,y=step(1); close(x,offX); close(y,offY)
            p:release('aim')
            assert(p:step(.016,gun,960,720,nil,{aimAssist=1},targets)==nil)
        ''')

    def test_assist_selects_nearest_valid_target_and_never_leaves_aim_bounds(self):
        self.lua.execute('''
            local Pad=require('game.mobile_shooter_controls'); local p=Pad.new()
            local l=Pad.layout(960,720); p:press('aim',l.x+l.r*.2,l.y,960,720)
            local gun={aimX=900,aimY=300}
            local bounds={left=30,top=55,right=930,bottom=625}
            local function step(targets)
                return p:step(.016,gun,960,720,bounds,{aimAssist=1},targets)
            end
            local near={x=920,y=310}; local far={x=925,y=320}
            local x,y=step({near})
            local ax,ay=step({far,{x=940,y=300},near})
            close(ax,x); close(ay,y)
            gun.aimX=930; gun.aimY=625
            ax,ay=step({{x=950,y=640}}); close(ax,930); close(ay,625)
        ''')

    def test_precision_fast_sweep_ads_and_frame_rate(self):
        self.lua.execute('''
            local pad=require('game.mobile_shooter_controls').layout(960,720)
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
            close(sweep(.05,false,60),0,'resting thumb drift')
            local fine,fast=sweep(.25,false,60),sweep(1,false,60)
            assert(fine>60 and fine<100 and fast>650,'precision/fast travel bands')
            close(sweep(1,false,30),fast); close(sweep(1,false,120),fast)
            close(sweep(1,true,60),fast*.8,'ADS slowdown')
            close(sweep(1,false,60,1,1),fast,'diagonals must not be faster')
        ''')

    def test_range_aim_and_fire_are_separate_and_release_stops_immediately(self):
        self.lua.execute('''
            local pad=require('game.mobile_shooter_controls').layout(960,720)
            local h=newRangeHarness(2); local c=h.controls
            c:touchpressed('aim',pad.x*2,pad.y*2)
            local x,y=h.session.aimX,h.session.aimY
            c:update(.016); close(h.session.aimX,x); close(h.session.aimY,y)
            c:touchmoved('aim',(pad.x+pad.r)*2,pad.y*2,128,0); c:update(.05)
            assert(h.session.aimX>x+40 and h.session.aimY==y and h.session.shots==0)
            x=h.session.aimX; h:targetAtAim()
            c:touchpressed('fire',pad.fireX*2,pad.fireY*2)
            assert(h.session.shots==1 and h.session.hits==1)
            close(h.session.aimX,x); close(h.session.aimY,y)
            c:touchmoved('fire',800,400,-904,-600)
            assert(c.rangePad.aimTouch=='aim')
            c:touchreleased('aim',(pad.x+pad.r)*2,pad.y*2); c:update(.05)
            close(h.session.aimX,x); assert(c.rangePad.fireTouch=='fire')
            c:touchreleased('fire',800,400)
            assert(c.rangePad.fireTouch==nil and h.released[#h.released]=='space')
        ''')

    def test_range_snapshot_refresh_preserves_stick_but_new_round_cancels_it(self):
        self.lua.execute('''
            local pad=require('game.mobile_shooter_controls').layout(960,720)
            local h=newRangeHarness(); local c=h.controls
            h.session.entityId='range:1'; h.session.roundRevision=3
            c:touchpressed('aim',pad.x+pad.r,pad.y); c:update(.016)
            local replacement={}; for k,v in pairs(h.session) do replacement[k]=v end
            h.session=replacement; local x=h.session.aimX
            c:update(.016); assert(h.session.aimX>x and c.rangePad.aimTouch=='aim')
            local nextRound={}; for k,v in pairs(h.session) do nextRound[k]=v end
            nextRound.roundRevision=4; h.session=nextRound; x=h.session.aimX
            c:update(.016); close(h.session.aimX,x); assert(c.rangePad.aimTouch==nil)
            c:touchmoved('aim',pad.x+pad.r,pad.y+20,0,20); c:update(.016); close(h.session.aimX,x)
            c:touchpressed('new',pad.x+pad.r,pad.y); c:touchreleased('aim',pad.x+pad.r,pad.y+20)
            assert(c.rangePad.aimTouch=='new')
            c:cancelAll(); c:update(.016); close(h.session.aimX,x)
        ''')

    def test_ownership_edges_and_pause_cancellation(self):
        self.lua.execute('''
            local pad=require('game.mobile_shooter_controls').layout(960,720)
            local Pad=require('game.mobile_shooter_controls'); local p=Pad.new()
            assert(p:press('first',pad.x,pad.y)=='aim')
            assert(p:press('second',pad.x,pad.y)=='blocked')
            p:move('second',pad.x+pad.r,pad.y); assert(p.x==0)
            p:move('first',10000,-10000)
            local x,y=p:step(.05,{aimX=929,aimY=56},960,720,{left=30,top=55,right=930,bottom=625})
            assert(x==930 and y==55)
            p:release('second'); assert(p.aimTouch=='first')
            p:cancel(); assert(p:step(.05,{aimX=480,aimY=330},960,720)==nil)
            assert(not p:move('first',pad.x+pad.r,pad.y))
            for _,size in ipairs({{960,720},{1280,720},{640,480},{720,960}}) do
                local l=Pad.layout(size[1],size[2])
                assert(l.x-l.r>=0 and l.fireX+l.fireR<=size[1] and l.y+l.r<size[2])
            end
        ''')

    def test_range_pause_releases_auto_fire_and_old_touch_cannot_restart_it(self):
        self.lua.execute('''
            local pad=require('game.mobile_shooter_controls').layout(960,720)
            local h=newRangeHarness(); local c=h.controls
            c.releaseKey=function(key) Range.keyreleased(h.session,key) end
            c:touchpressed('fire',pad.fireX,pad.fireY); assert(h.session.fireHeld)
            c.shootingRangeActive=function() return false end
            c:update(.02); assert(not h.session.fireHeld and not c.rangePad.fireTouch)
            c.shootingRangeActive=function() return h.session end
            c:update(.02); c:touchmoved('fire',pad.fireX,pad.fireY,0,0)
            assert(not h.session.fireHeld and not c.rangePad.fireTouch)
        ''')


class GuestRangeJoystickTests(unittest.TestCase):
    setUp = guest_range.GuestRangeTests.setUp
    range = guest_range.GuestRangeTests.range

    def test_stick_keeps_aiming_during_fire_receipt_and_pause_clears_it(self):
        self.range()
        self.lua.execute('''
            local pad=require('game.mobile_shooter_controls').layout(960,720)
            playing(); panel:touchpressed('aim',pad.x+pad.r,pad.y)
            local x=panel.pose.aimX; panel:update(.02); assert(panel.pose.aimX>x)
            panel:touchpressed('fire',pad.fireX,pad.fireY); assert(panel.pending.name=='range.fire')
            x=panel.pose.aimX; panel:update(.02); assert(panel.pose.aimX>x)
            panel:touchreleased('aim'); x=panel.pose.aimX
            panel:touchpressed('aim2',pad.x,pad.y); assert(panel.pose.aimX==x)
            panel:touchmoved('aim2',pad.x+pad.r,pad.y); panel:update(.02); assert(panel.pose.aimX>x)
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
            local pad=require('game.mobile_shooter_controls').layout(960,720)
            require('game.train_ambush_scene').target=ctx.ambushTarget
            panel:touchpressed('aim',pad.x+pad.r,pad.y); local x=panel.gun.aimX
            panel:update(.02); assert(panel.gun.aimX>x)
            panel:touchpressed('fire',pad.fireX,pad.fireY); assert(panel.pending.name=='gun.fire')
            x=panel.gun.aimX; panel:update(.02); assert(panel.gun.aimX>x)
            panel:touchreleased('aim'); x=panel.gun.aimX
            panel:touchpressed('aim2',pad.x,pad.y); assert(panel.gun.aimX==x)
            panel:touchmoved('aim2',pad.x+pad.r,pad.y); panel:update(.02); assert(panel.gun.aimX>x)
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
            local pad=require('game.mobile_shooter_controls').layout(960,720)
            positioned(); view:touchpressed('aim',pad.x+pad.r,pad.y)
            local x=panel.gun.aimX; panel:update(.02); assert(panel.gun.aimX>x)
            view:touchpressed('fire',pad.fireX,pad.fireY); assert(panel.pending.name=='gun.fire')
            x=panel.gun.aimX; panel:update(.02); assert(panel.gun.aimX>x)
            view:touchreleased('aim',pad.x+pad.r,pad.y); view:touchreleased('fire',pad.fireX,pad.fireY)
            assert(not panel.held.pad and not panel.aimTouch)
            x=panel.gun.aimX; panel:update(.02); assert(panel.gun.aimX==x)
        ''')


class HostDefenseJoystickTests(unittest.TestCase):
    setUp = defense.LastStandSourceTests.setUp

    def test_stick_bypasses_zoom_and_pause_drops_held_input(self):
        self.lua.execute('''
            local pad=require('game.mobile_shooter_controls').layout(960,720)
            assert(Source:zoomField(pad.x,pad.y)==nil and Source:zoomField(pad.fireX,pad.fireY)==nil)
            Source:touchpressed('aim',pad.x+pad.r,pad.y); local x=battle.gun.aimX
            sourceTick(.02); assert(battle.gun.aimX>x)
            Source:touchpressed('fire',pad.fireX,pad.fireY); assert(battle.fireHeldSources.pad)
            Source:touchreleased('aim',pad.x+pad.r,pad.y); assert(battle.fireHeldSources.pad)
            Source:touchreleased('fire',pad.fireX,pad.fireY); assert(not battle.fireHeldSources.pad)
            Source:touchpressed('aim2',pad.x+pad.r,pad.y); privatePaused=true
            x=battle.gun.aimX; sourceTick(.02)
            assert(battle.gun.aimX==x and not runtime.lastStand.aimPad.aimTouch)
        ''')


class HostAmbushJoystickTests(unittest.TestCase):
    setUp = ambush.AmbushReadinessTests.setUp
    source = ambush.AmbushReadinessTests.source

    def test_stick_changes_the_drawn_gun_without_firing_and_stops_on_focus_loss(self):
        self.source()
        self.lua.execute('''
            local pad=require('game.mobile_shooter_controls').layout(960,720)
            local latest; local original=Shooting.setAim
            Shooting.setAim=function(gun,x,y) latest=gun; original(gun,x,y) end
            input:touchpressed('aim',pad.x+pad.r,pad.y); input:update(.02)
            assert(latest and latest.aimX>250 and convoy.shots==0)
            local x=latest.aimX; input:focus(false); input:update(.02)
            assert(latest.aimX==x)
            input:keypressed('p'); input:update(.02); assert(latest.aimX==x)
        ''')


if __name__ == '__main__':
    unittest.main()
