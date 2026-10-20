"""Real range update/audio, sight-to-impact transforms, and cursor ownership."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GunADSAndAudioTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random},mouse={}}
            Range=require('game.shooting_range'); Catalog=require('game.catalog')
            Manifest=require('game.first_person_weapon_manifest')
            Cursor=require('game.aim_cursor')
            function newRange(weapon)
                local combat=Catalog.weaponCombat[weapon]
                data={location=2,equipment={weapon},inventory={'monocular'},ammo={[combat.ammo]=200}}
                session=assert(Range.new(data,{preferences={},highScores={}},Catalog))
                assert(Range.keypressed(session,'return',data,Catalog)=='start')
                session.fireMode='auto'
            end
        ''')

    def updateHarness(self):
        self.lua.execute('''
            local noop=function() end
            package.loaded['game.assets']={releaseIntroImages=noop,releaseDormantSceneArt=noop}
            runtime={state='game',scene='stop',session={networkMode='offline'},
                animationClock=0,walkingSoundTimer=0,actionTimer=0,saveData=data,shootingRange=session}
            reports=0;handled=0
            ui={playSfxPath=function(path,profile)
                reports=reports+1
                assert(path==Range.soundProfile(session,Catalog).path and profile.pitch>0)
            end}
            local context={runtime=runtime,width=960,holdPickupSeconds=1,ui=ui,
                catalog=Catalog,shootingRange=Range,
                clouds={update=noop},screens={is=function() return false end,update=function() return false end},
                handleShootingRange=function(outcome) assert(outcome=='shot');handled=handled+1 end}
            for _,name in ipairs({'car','landscape','scenery','cloudLayer','maintenanceSession','interactionRouter',
                'inventoryActions','journeyRules','settlements','interiorDoors','interactions','engineUpgrades',
                'trainUpgradeBalance','maintenance','family','util','passengers','firstAid','controlBindings'}) do
                context[name]={}
            end
            for _,name in ipairs({'mobileEnabled','mobileMovement','mobileHeld','mobileSprinting',
                'updatePersistence','screenToGame','updateAudio','ensureStopLayout','updateWorldScene',
                'currentShootingRange','clampToTrainFloor','itemIsHere','setupNPC','moveExpedition',
                'currentExpeditionInteraction','moveCaravan','currentCaravanInteraction','trainFloorBounds',
                'updateCarTransition','writeSave'}) do context[name]=noop end
            updater=require('game.gameplay_update').new(context)
        ''')

    def test_every_automatic_range_weapon_reports_each_update_shot(self):
        weapons = self.lua.execute('''
            local names={}
            for weapon,entry in pairs(Manifest.weapons) do
                if entry.kind=='firearm' and Manifest.fireModeValid(weapon,'auto') then names[#names+1]=weapon end
            end
            return names
        ''')
        for weapon in weapons.values():
            with self.subTest(weapon=weapon):
                self.lua.globals().weapon = weapon
                self.lua.execute("newRange(weapon); assert(Range.keypressed(session,'space',data,Catalog)=='shot')")
                self.updateHarness()
                self.lua.execute('''
                    local initial=session.shots
                    for frame=1,90 do updater.update(1/60) end
                    assert(session.shots>initial+4,'held automatic fire did not continue')
                    assert(reports==session.shots-initial and reports==handled,
                        'every subsequent automatic round must have exactly one report')
                    Range.keyreleased(session,'space')
                    local before=reports;for frame=1,30 do updater.update(1/60) end
                    assert(reports==before,'released trigger still sounded')
                    session.fireHeld=true;session.fireMode='safe';session.cooldown=0
                    updater.update(.1);assert(reports==before,'safe selector played gunfire')
                    session.fireMode='auto';session.loaded=0
                    updater.update(.1);assert(reports==before,'dry fire played a shot report')
                    assert(Range.reload(session,data,Catalog));updater.update(.1)
                    assert(reports==before,'reload played a shot report')
                ''')

    def test_range_impacts_match_sight_tip_through_camera_and_monocular(self):
        self.lua.execute('''
            local View=require('game.world_view')
            for _,zoom in ipairs({1,1.6}) do
                View.configure({toWorld=function(x,y) return (x-120)/zoom,(y-70)/zoom end})
                for weapon,entry in pairs(Manifest.weapons) do if entry.kind=='firearm' then
                    for _,mono in ipairs({false,true}) do
                        newRange(weapon);session.fireMode='single';Range.setAim(session,true)
                        session.hasMonocular=true;session.monocularActive=mono
                        Range.mousemoved(session,542,357)
                        local sx,sy=Range.sway(session,Catalog)
                        local x,y=View.toWorld(session.aimX+sx,session.aimY+sy)
                        local mag=Range.magnification(session)
                        x=480+(x-480)/mag;y=330+(y-330)/mag
                        local target={x=x,y=y,radius=40,material='paper',points=100,impacts={}}
                        session.targets={target}
                        assert(Range.keypressed(session,'space',data,Catalog)=='shot')
                        assert(target.hit and #target.impacts>0,weapon..' sight missed its target')
                        if Catalog.weaponCombat[weapon].ammo~='12-gauge' then
                            local hit=target.impacts[1]
                            assert(math.abs(hit.offsetX)<.001 and math.abs(hit.offsetY)<.001,
                                weapon..' bullet impact differs from sight aim')
                        end
                    end
                end end
            end
            View.configure()
        ''')

    def test_cursor_owns_only_its_ads_visibility_and_restores_on_menus_and_focus(self):
        self.lua.execute('''
            visible=true;visibilityChanges=0
            love.mouse.isVisible=function() return visible end
            love.mouse.setVisible=function(value) visible=value;visibilityChanges=visibilityChanges+1 end
            local function frame(ads,menu)
                Cursor.beginFrame();Cursor.sights(ads);Cursor.endFrame(menu)
            end
            frame(true,false);assert(not visible and visibilityChanges==1)
            frame(true,false);assert(visibilityChanges==1)
            frame(true,true);assert(visible)
            frame(true,false);assert(not visible)
            frame(false,false);assert(visible)
            -- A maintenance view already owns a hidden OS cursor.
            visible=false;frame(false,false);assert(not visible)
            frame(true,false);frame(false,false);assert(not visible)
            visible=true;frame(true,false);Cursor.restore();assert(visible)

            package.loaded['game.local_play_panel']={new=function() return {
                draw=function() end,stopTextInput=function() end} end}
            local controller={captures=function(self) return self.captured end,
                isClient=function() return false end,stop=function() end}
            local context={controller=controller,ui={},runtime={state='game'},
                commands={checkpointStatus=function() return {} end},screenToGame=function(x,y) return x,y end}
            local app=require('game.local_play_host').wrap({
                draw=function() Cursor.sights(true) end,focus=function() end,quit=function() end},context)
            app.draw();assert(not visible)
            controller.captured=true;app.draw();assert(visible)
            controller.captured=false;app.draw();assert(not visible)
            app.focus(false);assert(visible);app.draw();assert(visible)
            app.focus(true);app.draw();assert(not visible)
            context.runtime.pendingConfirmation={};app.draw();assert(visible)
            context.runtime.pendingConfirmation=nil;app.draw();assert(not visible)
            app.quit();assert(visible)
        ''')


if __name__ == '__main__':
    unittest.main()
