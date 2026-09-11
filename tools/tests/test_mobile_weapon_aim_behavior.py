"""Mobile shooters keep the weapon grip under one finger and fire independently."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

from PIL import Image

if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class MobileWeaponAimBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(r'''
            love={}
            Aim=require('game.mobile_weapon_aim')
            Grips=require('game.first_person_weapon_grips')
            Manifest=require('game.first_person_weapon_manifest')
            Shooting=require('game.first_person_shooting')
            Range=require('game.shooting_range')
            Catalog=require('game.catalog')
            Controls=require('game.mobile_controls')
            function close(actual,expected,label)
                assert(math.abs(actual-expected)<.00001,
                    (label or 'coordinate')..': '..tostring(actual)..' ~= '..tostring(expected))
            end
            function newRangeHarness(scale)
                scale=scale or 1
                local h={keys={},released={},moves=0,scale=scale}
                h.data={location=2,equipment={'frontier-sr22-pistol'},inventory={},ammo={['22lr']=100}}
                h.spot={preferences={},highScores={}}
                function h:replaceSession()
                    self.session=assert(Range.new(self.data,self.spot,Catalog))
                    assert(Range.keypressed(self.session,'return',self.data,Catalog)=='start')
                end
                h:replaceSession()
                h.controls=Controls.new({enabled=true,toGame=function(x,y) return x/scale,y/scale end,
                    shootingRangeActive=function() return h.session.phase=='play' and h.session or false end,
                    pressKey=function(key)
                        h.keys[#h.keys+1]=key
                        return Range.keypressed(h.session,key,h.data,Catalog)
                    end,
                    releaseKey=function(key) h.released[#h.released+1]=key end,
                    pressPointer=function(x,y,button)
                        return Range.mousepressed(h.session,x/scale,y/scale,h.data,Catalog,button)
                    end,
                    movePointer=function(x,y,dx,dy,touch)
                        h.moves=h.moves+1
                        Range.mousemoved(h.session,x/scale,y/scale,touch)
                    end,
                    releasePointer=function() end,
                })
                function h:targetAtAim()
                    local sx,sy=Range.sway(self.session,Catalog)
                    self.session.targets={{x=self.session.aimX+sx,y=self.session.aimY+sy,
                        radius=8,material='paper',points=100,impacts={}}}
                end
                return h
            end
        ''')

    def test_every_runtime_view_has_a_grip_on_art_and_matching_aspect(self) -> None:
        manifest = self.lua.globals().Manifest.weapons
        grips = self.lua.globals().Grips
        self.assertEqual(set(manifest), set(grips))
        checked: set[str] = set()
        for weapon, entry in manifest.items():
            self.assertEqual(set(entry.views), set(grips[weapon]))
            for view, filename in entry.views.items():
                with self.subTest(weapon=weapon, view=view):
                    grip = grips[weapon][view]
                    self.assertTrue(0 < grip.x < 1 and 0 < grip.y < 1)
                    with Image.open(ROOT / filename) as image:
                        self.assertAlmostEqual(image.width / image.height, grip.aspect, places=7)
                        self.assertGreater(image.getpixel((round(grip.x * image.width), round(grip.y * image.height)))[3], 20)
                    checked.add(filename)
        self.assertEqual(103, len(checked))

    def test_all_weapons_keep_grip_at_touch_and_calibrated_sight_at_reticle(self) -> None:
        self.lua.execute(r'''
            for weapon,entry in pairs(Manifest.weapons) do
                for _,size in ipairs({{960,720},{1280,720},{640,480},{720,960}}) do
                    local width,height=size[1],size[2]
                    for _,mode in ipairs({'hip','sights'}) do
                        local state={}
                        local tx,ty=width*.54,height*.72
                        Aim.set(state,tx,ty,weapon,mode,width,height)
                        assert(ty-state.aimY>math.min(width,height)*.10,weapon..' reticle hidden by aiming hand')
                        local place=Aim.placement(weapon,mode,mode,state.aimX,state.aimY,width,height)
                        local grip=Grips[weapon][mode]
                        close(place.x+place.width*grip.x,tx,weapon..' grip X')
                        close(place.y+place.height*grip.y,ty,weapon..' grip Y')
                        assert(place.width<=width*.65+.00001 and place.height<=height*.66+.00001)
                        local sight,calibrated=Manifest.anchorFor(weapon)
                        if mode=='sights' and calibrated then
                            close(place.x+place.width*sight.x,state.aimX,weapon..' sight X')
                            close(place.y+place.height*sight.y,state.aimY,weapon..' sight Y')
                        end
                    end
                end
            end
        ''')

    def test_special_animation_views_keep_the_same_held_point(self) -> None:
        self.lua.execute(r'''
            for weapon,entry in pairs(Manifest.weapons) do
                if entry.kind=='special' then
                    for _,mode in ipairs({'hip','sights'}) do
                        for view in pairs(entry.views) do
                            local grip=Grips[weapon][view]
                            local place=Aim.placement(weapon,view,mode,480,300,960,720)
                            local hx,hy=Aim.gripForAim(weapon,mode,480,300,960,720)
                            close(place.x+place.width*grip.x,hx,weapon..' '..view)
                            close(place.y+place.height*grip.y,hy,weapon..' '..view)
                        end
                    end
                end
            end
        ''')

    def test_range_touch_clamps_targets_and_mouse_remains_absolute(self) -> None:
        self.lua.execute(r'''
            local h=newRangeHarness()
            Range.mousemoved(h.session,-100,-100,true)
            close(h.session.aimX,30); close(h.session.aimY,55)
            Range.mousemoved(h.session,2000,2000,true)
            close(h.session.aimX,930); close(h.session.aimY,625)
            Range.mousemoved(h.session,480,340,false)
            close(h.session.aimX,480); close(h.session.aimY,340)
            assert(h.session.touchAim==nil)
            local state={weapon='frontier-sr22-pistol'}
            Shooting.setTouchAim(state,510,540,960,720)
            Shooting.setAim(state,200,300)
            assert(state.touchAim==nil)
            close(state.aimX,200); close(state.aimY,300)
        ''')

    def test_ads_toggle_and_weapon_change_preserve_the_held_touch(self) -> None:
        self.lua.execute(r'''
            local data={equipment={'frontier-sr22-pistol','frontier-22-lever-rifle'},ammo={['22lr']=100}}
            local quest={}
            local state=Shooting.new(data,Catalog,quest,960,720)
            Shooting.setTouchAim(state,520,550,960,720)
            for _,ads in ipairs({true,false,true}) do
                Shooting.setADS(state,ads)
                local mode=ads and 'sights' or 'hip'
                local x,y=Aim.gripForAim(state.weapon,mode,state.aimX,state.aimY,960,720)
                close(x,520); close(y,550)
            end
            state=Shooting.chooseWeapon(state,{name='frontier-sr22-pistol',borrowed=false},data,Catalog,quest)
            local x,y=Aim.gripForAim(state.weapon,'sights',state.aimX,state.aimY,960,720)
            close(x,520); close(y,550)
            local reopened=Shooting.new(data,Catalog,quest,960,720)
            assert(reopened.touchAim==nil and reopened.ads==false)
        ''')

    def test_first_person_renderer_draws_actual_grip_under_the_touch(self) -> None:
        sizes = self.lua.table()
        for path in (ROOT / "assets/sprites/weapons/first-person").glob("*.png"):
            with Image.open(path) as image:
                sizes[path.relative_to(ROOT).as_posix()] = self.lua.table_from([image.width, image.height])
        self.lua.globals().spriteSizes = sizes
        self.lua.execute(r'''
            local function noop() end
            love.filesystem={getInfo=function() return {} end}
            love.graphics={push=noop,pop=noop,setColor=noop,
                newImage=function(path)
                    local size=assert(spriteSizes[path])
                    return {getDimensions=function() return size[1],size[2] end,setFilter=noop}
                end,
                draw=function(image,x,y,rotation,sx,sy)
                    local iw,ih=image:getDimensions()
                    drawn={x=x,y=y,width=iw*sx,height=ih*sy}
                end}
            for weapon,entry in pairs(Manifest.weapons) do
                if entry.kind=='firearm' then
                    for _,ads in ipairs({false,true}) do
                        local state={weapon=weapon,ads=ads,recoil=0}
                        Shooting.setTouchAim(state,520,550,960,720)
                        Shooting.draw(state,960,720)
                        local grip=Grips[weapon][ads and 'sights' or 'hip']
                        close(drawn.x+drawn.width*grip.x,520,weapon)
                        close(drawn.y+drawn.height*grip.y,550,weapon)
                    end
                end
            end
        ''')

    def test_second_field_touch_fires_at_first_finger_aim_without_taking_ownership(self) -> None:
        self.lua.execute(r'''
            local h=newRangeHarness(2)
            local c=h.controls
            assert(c:touchpressed('aim',1000,1000))
            assert(c.rangeAimTouch=='aim' and h.session.shots==0)
            close(h.session.aimX,500); close(h.session.aimY,356)
            h:targetAtAim()
            c:touchpressed('fire',300,400)
            assert(h.session.shots==1 and h.session.hits==1)
            assert(c.rangeAimTouch=='aim')
            close(h.session.aimX,500); close(h.session.aimY,356)
            c:touchmoved('fire',700,650,400,250)
            assert(h.moves==0)
            close(h.session.aimX,500); close(h.session.aimY,356)
            c:touchreleased('fire',700,650)
            assert(c.rangeAimTouch=='aim')
            c:touchmoved('aim',1100,1040,100,40)
            assert(h.moves==1)
            close(h.session.aimX,550); close(h.session.aimY,376)
        ''')

    def test_fire_button_uses_existing_aim_and_releases_cleanly(self) -> None:
        self.lua.execute(r'''
            local h=newRangeHarness()
            local c=h.controls
            c:touchpressed('aim',500,500)
            h:targetAtAim()
            c:touchpressed('fire',480,675)
            assert(h.session.shots==1 and h.session.hits==1)
            assert(c.rangeAimTouch=='aim' and c.touches.fire.kind=='rangeControl')
            c:touchmoved('fire',400,350,-100,-100)
            close(h.session.aimX,500); close(h.session.aimY,356)
            c:touchreleased('fire',400,350)
            assert(c.touches.fire==nil and c.rangeAimTouch=='aim' and #h.keys==0)
        ''')

    def test_footer_fire_without_a_held_grip_preserves_current_aim(self) -> None:
        self.lua.execute(r'''
            local h=newRangeHarness()
            local x,y=h.session.aimX,h.session.aimY
            h:targetAtAim()
            h.controls:touchpressed('fire',480,675)
            assert(h.session.shots==1 and h.session.hits==1 and h.controls.rangeAimTouch==nil)
            close(h.session.aimX,x); close(h.session.aimY,y)
            h.controls:touchmoved('fire',600,500,120,-175)
            assert(h.moves==0)
        ''')

    def test_tablet_grip_over_old_fire_position_acquires_aim_without_shooting(self) -> None:
        self.lua.execute(r'''
            love.graphics={getDimensions=function() return 960,720 end}
            local h=newRangeHarness()
            local tx,ty=Aim.gripForAim(h.session.weapon,'hip',800,382,960,720)
            h.controls:touchpressed('aim',tx,ty)
            assert(h.session.shots==0 and h.controls.rangeAimTouch=='aim')
            close(h.session.aimX,800); close(h.session.aimY,382)
            h:targetAtAim()
            h.controls:touchpressed('fire',480,675)
            assert(h.session.shots==1 and h.session.hits==1)
        ''')

    def test_releasing_aim_does_not_promote_a_held_fire_finger(self) -> None:
        self.lua.execute(r'''
            local h=newRangeHarness()
            local c=h.controls
            c:touchpressed('aim',500,500)
            c:touchpressed('fire',300,300)
            c:touchreleased('aim',500,500)
            assert(c.rangeAimTouch==nil)
            c:touchmoved('fire',450,450,150,150)
            close(h.session.aimX,500); close(h.session.aimY,356)
            c:touchpressed('new-aim',550,520)
            assert(c.rangeAimTouch=='new-aim' and h.session.shots==1)
            close(h.session.aimX,550); close(h.session.aimY,376)
            c:touchreleased('fire',450,450)
            assert(c.rangeAimTouch=='new-aim')
        ''')

    def test_footer_actions_do_not_fire_or_claim_aim_touch(self) -> None:
        self.lua.execute(r'''
            local h=newRangeHarness()
            local c=h.controls
            c:touchpressed('reload',70,675)
            assert(c.rangeAimTouch==nil and h.session.shots==0)
            c:touchreleased('reload',70,675)
            c:touchpressed('aim',500,500)
            c:touchpressed('ads',200,675)
            assert(h.session.aimMode=='sights' and c.rangeAimTouch=='aim' and h.session.shots==0)
            local x,y=Aim.gripForAim(h.session.weapon,'sights',h.session.aimX,h.session.aimY,960,720)
            close(x,500); close(y,500)
            c:touchmoved('ads',600,400,400,-275)
            assert(h.moves==0)
            c:touchreleased('ads',600,400)
            assert(c.rangeAimTouch=='aim')
            c:touchpressed('setup',730,675)
            assert(h.session.phase=='lobby' and h.session.shots==0)
        ''')

    def test_old_session_fingers_cannot_move_or_release_new_session_owner(self) -> None:
        self.lua.execute(r'''
            local h=newRangeHarness()
            local c=h.controls
            c:touchpressed('old',500,500)
            h:replaceSession()
            c:touchmoved('old',600,500,100,0)
            close(h.session.aimX,480); close(h.session.aimY,330)
            assert(h.moves==0)
            c:touchpressed('new',550,520)
            assert(c.rangeAimTouch=='new' and h.session.shots==0)
            c:touchreleased('old',600,500)
            assert(c.rangeAimTouch=='new')
            c:touchmoved('new',570,540,20,20)
            close(h.session.aimX,570); close(h.session.aimY,396)
        ''')

    def test_setup_restart_does_not_reuse_an_old_finger_on_the_same_session(self) -> None:
        self.lua.execute(r'''
            local h=newRangeHarness()
            local c=h.controls
            c:touchpressed('old',500,500)
            c:touchpressed('setup',730,675)
            c:touchreleased('setup',730,675)
            assert(h.session.phase=='lobby')
            c:touchpressed('start',630,570)
            c:touchreleased('start',630,570)
            assert(h.session.phase=='play' and h.session.shots==0)
            local x,y=h.session.aimX,h.session.aimY
            c:touchmoved('old',600,550,100,50)
            close(h.session.aimX,x); close(h.session.aimY,y)
            assert(h.moves==0)
            c:touchpressed('new',550,520)
            assert(c.rangeAimTouch=='new' and h.session.shots==0)
        ''')

    def test_cancel_all_discards_aim_and_fire_pointer_events(self) -> None:
        self.lua.execute(r'''
            local h=newRangeHarness()
            local c=h.controls
            c:touchpressed('aim',500,500)
            c:touchpressed('fire',480,675)
            c:cancelAll()
            assert(c.rangeAimTouch==nil and c.rangeSession==nil and next(c.touches)==nil)
            assert(not c:isHeld('space') and #h.keys==0)
            assert(not c:touchmoved('aim',600,550,100,50))
            assert(not c:touchreleased('fire',480,675))
            c:touchpressed('fresh',550,520)
            assert(c.rangeAimTouch=='fresh' and h.session.shots==1)
            close(h.session.aimX,550); close(h.session.aimY,376)
        ''')


if __name__ == "__main__":
    unittest.main()
