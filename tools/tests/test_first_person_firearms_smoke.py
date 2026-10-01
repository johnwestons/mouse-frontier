"""End-to-end first-person firearm smoke checks using the real Lua modules.

These fixtures run Shooting and ShootingRange without opening a game window or
reading/writing a save. Image loading and drawing are recorded LÖVE stubs; PNG
dimensions come from the checked-in production sprite sheets.
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


@unittest.skipIf(LuaRuntime is None, "lupa is required for behavioral Lua checks")
class FirstPersonFirearmsSmokeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().project_root = ROOT.as_posix()
        self.lua.execute(
            "package.path=project_root..'/?.lua;'..package.path; love={}; "
            "Manifest=require('game.first_person_weapon_manifest'); "
            "Actions=require('game.first_person_weapon_actions'); "
            "Shooting=require('game.first_person_shooting'); "
            "Range=require('game.shooting_range'); Catalog=require('game.catalog')"
        )

    def test_smg_reload_finishes_with_the_seated_magazine_sprite(self) -> None:
        self.lua.execute(
            "local weapon='frontier-9mm-smg'; "
            "local duration=Manifest.reloadProfileFor(weapon).duration; "
            "local state={weapon=weapon,weaponAction='reload',weaponActionElapsed=0}; "
            "assert(Actions.frameIndex(state)==4); "
            "state.weaponActionElapsed=duration*.4; assert(Actions.frameIndex(state)==5); "
            "state.weaponActionElapsed=duration*.85; assert(Actions.frameIndex(state)==1); "
            "state.weaponActionElapsed=duration; assert(Actions.frameIndex(state)==1)"
        )

    def test_every_firearm_draws_its_authored_ads_ready_flash_recoil_and_settle_frames(self) -> None:
        sizes = self.lua.table()
        sprite_root = ROOT / "assets" / "sprites" / "weapons" / "first-person"
        for path in sprite_root.rglob("*.png"):
            with Image.open(path) as image:
                sizes[path.relative_to(ROOT).as_posix()] = self.lua.table_from([image.width, image.height])
        self.lua.globals().spriteSizes = sizes
        self.lua.execute(
            r'''
            local function noop() end
            drawCalls={}
            love.filesystem={getInfo=function() return {} end}
            love.graphics={
                push=noop,pop=noop,setColor=noop,
                newImage=function(path)
                    local size=assert(spriteSizes[path], 'missing sprite dimensions: '..path)
                    return {path=path,getDimensions=function() return size[1],size[2] end,setFilter=noop}
                end,
                newQuad=function(x,y,w,h,sw,sh)
                    return {x=x,y=y,w=w,h=h,sourceWidth=sw,sourceHeight=sh}
                end,
                draw=function(image,quad,x,y,rotation,sx,sy)
                    drawCalls[#drawCalls+1]={path=image.path,quad=quad,x=x,y=y,
                        rotation=rotation,sx=sx,sy=sy}
                end,
            }
            for weapon,entry in pairs(Manifest.weapons) do
                if entry.kind=='firearm' then
                    local combat=assert(Catalog.weaponCombat[weapon],weapon..' catalog entry missing')
                    local state={weapon=weapon,ammoType=combat.ammo,magazine=3,fireMode='single',
                        cooldown=0,reloadTimer=0,ads=true,aimX=480,aimY=360}
                    local data={ammo={[combat.ammo]=3}}
                    local quest={}
                    local atlas='assets/sprites/weapons/first-person/actions/'..weapon..'-ads-fire.png'
                    local size=assert(spriteSizes[atlas],weapon..' ADS atlas dimensions missing')
                    local frameRects={{0,0},{size[1]/2,0},{0,size[2]/2},{size[1]/2,size[2]/2}}
                    local function assertFrame(index)
                        local call=assert(drawCalls[#drawCalls],'renderer made no draw call for '..weapon)
                        local rect=frameRects[index]
                        assert(call.path==atlas,weapon..' used the wrong ADS sprite atlas: '..tostring(call.path))
                        assert(call.quad.x==rect[1] and call.quad.y==rect[2],
                            weapon..' selected the wrong ADS frame '..index)
                        local size=assert(spriteSizes[atlas],weapon..' ADS atlas dimensions missing')
                        local anchor=Manifest.adsActionAnchorFor(weapon,index)
                        local sightX=call.x+(size[1]/2)*anchor.x*call.sx
                        local sightY=call.y+(size[2]/2)*anchor.y*call.sy
                        assert(math.abs(sightX-state.aimX)<.02 and math.abs(sightY-state.aimY)<.02,
                            weapon..' ADS sight moved off the reticle in frame '..index)
                    end
                    Shooting.draw(state,960,720); assertFrame(1)
                    assert(Shooting.fire(state,data,quest),'ADS shot failed for '..weapon)
                    Shooting.draw(state,960,720); assertFrame(2)
                    Shooting.update(state,.08,data,quest,960,720)
                    Shooting.draw(state,960,720); assertFrame(3)
                    Shooting.update(state,.08,data,quest,960,720)
                    Shooting.draw(state,960,720); assertFrame(4)
                end
            end
            '''
        )

    def test_every_firearm_plays_hip_action_frames_with_aim_on_its_barrel_line(self) -> None:
        sizes = self.lua.table()
        sprite_root = ROOT / "assets" / "sprites" / "weapons" / "first-person"
        for path in sprite_root.rglob("*.png"):
            with Image.open(path) as image:
                sizes[path.relative_to(ROOT).as_posix()] = self.lua.table_from([image.width, image.height])
        self.lua.globals().spriteSizes = sizes
        self.lua.execute(
            r'''
            local Aim=require('game.mobile_weapon_aim')
            local function noop() end
            drawCalls={}
            love.filesystem={getInfo=function() return {} end}
            love.graphics={
                push=noop,pop=noop,setColor=noop,
                newImage=function(path)
                    local size=assert(spriteSizes[path],'missing sprite dimensions: '..path)
                    return {path=path,getDimensions=function() return size[1],size[2] end,setFilter=noop}
                end,
                newQuad=function(x,y,w,h,sw,sh)
                    return {x=x,y=y,w=w,h=h,sourceWidth=sw,sourceHeight=sh}
                end,
                draw=function(image,quad,x,y,rotation,sx,sy)
                    drawCalls[#drawCalls+1]={path=image.path,quad=quad,x=x,y=y,
                        rotation=rotation,sx=sx,sy=sy}
                end,
            }
            local frameRects={{0,0},{512,0},{1024,0}}
            for weapon,entry in pairs(Manifest.weapons) do
                if entry.kind=='firearm' then
                    local combat=assert(Catalog.weaponCombat[weapon],weapon..' catalog entry missing')
                    local state={weapon=weapon,ammoType=combat.ammo,magazine=3,fireMode='single',
                        cooldown=0,reloadTimer=0,ads=false,aimX=480,aimY=360}
                    local data={ammo={[combat.ammo]=3}}
                    local quest={}
                    local atlas='assets/sprites/weapons/first-person/actions/'..weapon..'-actions.png'
                    local touchX,touchY=510,530
                    Shooting.setTouchAim(state,touchX,touchY,960,720)
                    local function assertFrame(index)
                        local call=assert(drawCalls[#drawCalls],'renderer made no draw call for '..weapon)
                        local rect=frameRects[index]
                        assert(call.path==atlas,weapon..' used the wrong hip action atlas: '..tostring(call.path))
                        assert(call.quad.x==rect[1] and call.quad.y==rect[2],
                            weapon..' selected the wrong hip frame '..index)
                        local anchor=assert(Actions.anchorsFor(weapon),weapon..' action anchors missing')
                        local gripX=call.x+anchor.grip.x*512*call.sx
                        local gripY=call.y+anchor.grip.y*512*call.sy
                        assert(math.abs(gripX-touchX)<.02 and math.abs(gripY-touchY)<.02,
                            weapon..' moved its grip away from touch in hip frame '..index)
                        local muzzleX=call.x+anchor.muzzle.x*512*call.sx
                        local muzzleY=call.y+anchor.muzzle.y*512*call.sy
                        local boreX=call.x+anchor.bore.x*512*call.sx
                        local boreY=call.y+anchor.bore.y*512*call.sy
                        local barrelX,barrelY=muzzleX-boreX,muzzleY-boreY
                        local reticleX,reticleY=state.aimX-muzzleX,state.aimY-muzzleY
                        assert(math.abs(barrelX*reticleY-barrelY*reticleX)<.02,
                            weapon..' hip reticle left the authored barrel line in frame '..index)
                        assert(barrelX*reticleX+barrelY*reticleY>0,
                            weapon..' hip reticle fell behind the muzzle in frame '..index)
                    end
                    Shooting.draw(state,960,720); assertFrame(1)
                    assert(Shooting.fire(state,data,quest),'hip shot failed for '..weapon)
                    Shooting.draw(state,960,720); assertFrame(2)
                    Shooting.update(state,.08,data,quest,960,720)
                    Shooting.draw(state,960,720); assertFrame(3)
                end
            end
            '''
        )

    def test_range_selector_safe_single_and_auto_paths_fire_as_selected(self) -> None:
        result = self.lua.execute(
            r'''
            local weapon='compact-carbine'
            local combat=Catalog.weaponCombat[weapon]
            local data={location=2,equipment={weapon},inventory={},ammo={[combat.ammo]=20}}
            local spot={preferences={},highScores={}}
            local session=assert(Range.new(data,spot,Catalog))
            assert(Range.keypressed(session,'return',data,Catalog)=='start')
            assert(session.fireMode=='single')

            -- The visible MODE control cycles through all three selector positions.
            assert(Range.mousepressed(session,600,675,data,Catalog,1)=='mode')
            assert(session.fireMode=='auto')
            assert(Range.mousepressed(session,600,675,data,Catalog,1)=='mode')
            assert(session.fireMode=='safe')
            local ammo=data.ammo[combat.ammo]
            assert(Range.mousepressed(session,480,330,data,Catalog,1)=='safe')
            assert(session.shots==0 and data.ammo[combat.ammo]==ammo,'SAFE consumed a round')

            assert(Range.keypressed(session,'v',data,Catalog)=='mode')
            assert(session.fireMode=='single')
            assert(Range.keypressed(session,'space',data,Catalog)=='shot')
            assert(session.shots==1 and data.ammo[combat.ammo]==ammo-1)
            Range.keyreleased(session,'space')
            for _=1,4 do Range.update(session,.08,data,Catalog) end

            assert(Range.mousepressed(session,600,675,data,Catalog,1)=='mode')
            assert(session.fireMode=='auto')
            assert(Range.keypressed(session,'space',data,Catalog)=='shot')
            local beforeAuto=session.shots
            for _=1,8 do Range.update(session,.08,data,Catalog) end
            assert(session.shots>=beforeAuto+3,'held AUTO did not continue firing')
            assert(Range.keyreleased(session,'space'))
            return session.shots
            '''
        )
        self.assertGreaterEqual(result, 4)

    def test_every_firearm_cycles_safe_single_and_only_supported_auto(self) -> None:
        self.lua.execute(
            r'''
            for weapon,entry in pairs(Manifest.weapons) do
                if entry.kind=='firearm' then
                    local modes=Manifest.fireModesFor(weapon)
                    assert(modes[1]=='safe' and modes[2]=='single' and #modes<=3,
                        weapon..' has invalid selector positions')
                    assert((#modes==3 and modes[3]=='auto') or #modes==2,
                        weapon..' has an unsupported automatic position')
                    local combat=assert(Catalog.weaponCombat[weapon],weapon..' catalog entry missing')
                    local data={location=2,equipment={weapon},inventory={},ammo={[combat.ammo]=80}}
                    local session=assert(Range.new(data,{preferences={},highScores={}},Catalog))
                    assert(Range.keypressed(session,'return',data,Catalog)=='start')
                    assert(session.fireMode=='single')
                    assert(Range.cycleFireMode(session,-1)=='safe',weapon..' could not select SAFE')
                    local rounds=data.ammo[combat.ammo]
                    assert(Range.keypressed(session,'space',data,Catalog)=='safe',
                        weapon..' fired with SAFE selected')
                    assert(session.shots==0 and data.ammo[combat.ammo]==rounds,
                        weapon..' consumed ammunition while SAFE')
                    Range.keyreleased(session,'space')
                    assert(Range.cycleFireMode(session,1)=='single',weapon..' could not select SINGLE')
                    assert(Range.keypressed(session,'space',data,Catalog)=='shot',
                        weapon..' did not fire in SINGLE')
                    assert(session.shots==1 and data.ammo[combat.ammo]==rounds-1,
                        weapon..' SINGLE did not consume exactly one shot')
                    Range.keyreleased(session,'space')
                    local nextMode=#modes==3 and 'auto' or 'safe'
                    assert(Range.cycleFireMode(session,1)==nextMode,
                        weapon..' cycled into the wrong next selector position')
                end
            end
            '''
        )

    def test_shotshell_patterns_change_between_shots_and_keep_ammo_and_scoring_correct(self) -> None:
        self.lua.execute(r'''
            math.randomseed(4371)
            for _,weapon in ipairs({'frontier-12g-pump-shotgun','sawed-off-shotgun'}) do
                local combat=Catalog.weaponCombat[weapon]
                assert(combat.ammo=='12-gauge',weapon..' must consume shotshell ammunition')
                local data={location=2,equipment={weapon},inventory={},ammo={[combat.ammo]=50}}
                local session=assert(Range.new(data,{preferences={},highScores={}},Catalog))
                assert(Range.keypressed(session,'return',data,Catalog)=='start')
                local previous
                for shot=1,8 do
                    session.loaded=session.capacity
                    session.cooldown=0
                    local target={x=session.aimX,y=session.aimY,baseX=session.aimX,scale=1,
                        sprite=1,radius=24,material='paper',points=100,age=0,life=math.huge,
                        velocity=0,hit=false,impacts={}}
                    session.targets={target}
                    local ammoBefore=data.ammo[combat.ammo]
                    local hitsBefore=session.hits
                    assert(Range.keypressed(session,'space',data,Catalog)=='shot')
                    Range.keyreleased(session,'space')
                    assert(#target.impacts==7,weapon..' did not produce seven pellet impacts')
                    assert(data.ammo[combat.ammo]==ammoBefore-1,'pellets consumed extra shells')
                    assert(session.hits==hitsBefore+1,'pellets inflated target-hit count')
                    local changed=false
                    for i,p in ipairs(target.impacts) do
                        assert(p.offsetX^2+p.offsetY^2<=18^2+.001,'pellet escaped scatter bounds')
                        if previous and (math.abs(p.offsetX-previous[i].offsetX)>.01
                            or math.abs(p.offsetY-previous[i].offsetY)>.01) then changed=true end
                        for j=1,i-1 do
                            local q=target.impacts[j]
                            assert((p.offsetX-q.offsetX)^2+(p.offsetY-q.offsetY)^2>.01,
                                'two pellet marks occupy exactly the same point')
                        end
                    end
                    if previous then assert(changed,'identical pellet stamp repeated on next shot') end
                    previous=target.impacts
                end
            end
        ''')

    def test_shotgun_spread_impacts_and_pump_reload_frames_run_in_range(self) -> None:
        result = self.lua.execute(
            r'''
            local weapon='frontier-12g-pump-shotgun'
            local combat=Catalog.weaponCombat[weapon]
            local data={location=2,equipment={weapon},inventory={},ammo={[combat.ammo]=10}}
            local session=assert(Range.new(data,{preferences={},highScores={}},Catalog))
            assert(Range.keypressed(session,'return',data,Catalog)=='start')
            local target={x=session.aimX,y=session.aimY,baseX=session.aimX,scale=1,sprite=1,
                radius=24,material='paper',points=100,age=0,life=math.huge,velocity=0,hit=false,impacts={}}
            session.targets={target}
            assert(Range.keypressed(session,'space',data,Catalog)=='shot')
            assert(session.shots==1 and session.hits==1 and #target.impacts==7,
                'one shotshell must leave seven pellet marks and count one target hit')
            for _,impact in ipairs(target.impacts) do
                assert(impact.offsetX^2+impact.offsetY^2<=14^2+.001,
                    'pellet impact exceeded its scatter radius')
            end
            Range.keyreleased(session,'space')

            local loaded=session.loaded
            assert(Range.mousepressed(session,70,675,data,Catalog,1)=='reload')
            assert(session.reloadTimer>0.9 and session.reloadTimer<1.0 and session.weaponAction=='reload',
                'pump reload did not initialize: timer='..tostring(session.reloadTimer)
                    ..' action='..tostring(session.weaponAction))
            assert(session.tubeReloadTotalRounds==1,'pump shotgun did not begin a single-shell reload')
            assert(Actions.frameIndex(session)==4,'pump reload did not start on its authored first frame')
            for _=1,4 do Range.update(session,.08,data,Catalog) end
            assert(Actions.frameIndex(session)==5,'pump reload did not enter its work frame')
            for _=1,5 do Range.update(session,.08,data,Catalog) end
            assert(Actions.frameIndex(session)==6 and session.loaded==loaded+1,
                'pump reload did not insert one shell and enter its finish frame')
            for _=1,4 do Range.update(session,.08,data,Catalog) end
            assert(session.reloadTimer==0 and Actions.frameIndex(session)==1)
            assert(session.loaded==loaded+1,'pump reload did not restore the spent shell')

            session.loaded=2
            assert(Range.reload(session,data,Catalog),'pump reload did not start a multi-shell top-off')
            local missing=session.capacity-session.loaded
            assert(session.tubeReloadTotalRounds==missing and session.loaded==2,
                'pump reload did not preserve loaded shells and stage each missing shell: total='
                    ..tostring(session.tubeReloadTotalRounds)..' loaded='..tostring(session.loaded)
                    ..' timer='..tostring(session.reloadTimer))
            for _=1,4 do Range.update(session,.08,data,Catalog) end
            assert(Actions.frameIndex(session)==5 and session.loaded==2,
                'pump reload skipped its shell-loading pose')
            for index=1,missing-1 do
                for _=1,6 do Range.update(session,.08,data,Catalog) end
                assert(session.loaded==2+index,
                    'pump reload did not insert missing shell '..index)
            end
            for _=1,4 do Range.update(session,.08,data,Catalog) end
            assert(Actions.frameIndex(session)==6 and session.loaded==2+missing,
                'pump reload did not finish after inserting every missing shell')
            for _=1,4 do Range.update(session,.08,data,Catalog) end
            assert(session.reloadTimer==0 and Actions.frameIndex(session)==1,
                'multi-shell pump reload did not return to ready')

            local largeTarget={x=session.aimX,y=session.aimY,baseX=session.aimX,scale=1,
                sprite=1,radius=24,material='paper',points=100,age=0,life=math.huge,
                velocity=0,hit=false,impacts={}}
            session.targets={largeTarget}
            local loadedAfterReload=session.loaded
            local hitsBefore=session.hits
            assert(Range.keypressed(session,'space',data,Catalog)=='shot',
                'loaded pump shotgun could not fire into a single target')
            assert(#largeTarget.impacts==7,
                'shotgun pellets did not leave seven distinct marks on one target: '
                    ..tostring(#largeTarget.impacts))
            assert(session.hits==hitsBefore+1,
                'multiple pellets on one target counted as multiple target hits')
            assert(session.loaded==loadedAfterReload-1,
                'shotgun consumed more than one shell for its pellet spread')
            Range.keyreleased(session,'space')
            return loadedAfterReload
            '''
        )
        self.assertEqual(6, result)

    def test_sks_last_round_open_carrier_and_stripper_clip_reload_complete(self) -> None:
        result = self.lua.execute(
            r'''
            local weapon='frontier-762-carbine'
            local combat=Catalog.weaponCombat[weapon]
            local data={equipment={weapon},inventory={},ammo={[combat.ammo]=2}}
            local quest={}
            local state=Shooting.new(data,Catalog,quest,960,720)
            state.magazine=1
            assert(Shooting.fire(state,data,quest))
            Shooting.update(state,.20,data,quest,960,720)
            assert(state.magazine==0 and Actions.frameIndex(state)==4,
                'empty SKS did not hold the carrier open')
            assert(Shooting.reload(state,data,quest))
            assert(Actions.frameIndex(state)==4)
            Shooting.update(state,.32,data,quest,960,720)
            assert(Actions.frameIndex(state)==5)
            Shooting.update(state,.72,data,quest,960,720)
            assert(Actions.frameIndex(state)==6)
            Shooting.update(state,.51,data,quest,960,720)
            assert(state.reloadTimer==0 and state.magazine==1 and Actions.frameIndex(state)==1,
                'SKS reload did not finish with the available cartridge')
            return state.magazine
            '''
        )
        self.assertEqual(1, result)

    def test_22_lever_reload_inserts_rounds_over_time_and_finishes(self) -> None:
        result = self.lua.execute(
            r'''
            local weapon='frontier-22-lever-rifle'
            local combat=Catalog.weaponCombat[weapon]
            local data={equipment={weapon},inventory={},ammo={[combat.ammo]=7}}
            local quest={}
            local state=Shooting.new(data,Catalog,quest,960,720)
            state.magazine=2
            assert(Shooting.reload(state,data,quest))
            assert(state.magazine==0 and state.tubeReloadTotalRounds==7,
                'tube reload setup mismatch: magazine='..tostring(state.magazine)..' rounds='
                    ..tostring(state.tubeReloadTotalRounds))
            assert(Actions.frameIndex(state)==4)
            Shooting.update(state,.35,data,quest,960,720)
            assert(Actions.frameIndex(state)==5 and state.magazine==0)
            Shooting.update(state,.38,data,quest,960,720)
            assert(state.magazine==1,'tube loader did not insert its first round at the round interval')
            for _=1,6 do Shooting.update(state,.38,data,quest,960,720) end
            assert(state.magazine==7,'tube loader did not insert all rounds: '..tostring(state.magazine))
            Shooting.update(state,.02,data,quest,960,720)
            assert(Actions.frameIndex(state)==6,'tube loader did not enter its finish pose: elapsed='
                ..tostring(state.weaponActionElapsed))
            Shooting.update(state,.32,data,quest,960,720)
            assert(state.reloadTimer==0 and state.weaponAction==nil and Actions.frameIndex(state)==1)
            return state.magazine
            '''
        )
        self.assertEqual(7, result)


if __name__ == "__main__":
    unittest.main()
