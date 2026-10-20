"""Exercise the range HUD with production asset loaders, without save files."""
from collections import Counter
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.tests.test_lazy_scene_asset_loading import AllocationProbe


class ShootingRangeRenderPerformanceTests(unittest.TestCase):
    def setUp(self):
        self.probe = AllocationProbe()
        self.lua = self.probe.lua
        self.lua.execute('''
            local noop=function()end
            Range=require('game.shooting_range');Catalog=require('game.catalog')
            data.location=2;data.equipment={'frontier-9mm-smg'}
            data.inventory={};data.ammo={['9mm']=200}
            data.weaponDurability={['frontier-9mm-smg']=100}
            local spot={preferences={stageLength=90}}
            runtime.scene='stop';runtime.shootingRange=assert(Range.new(data,spot,Catalog))
            mobile=false;worldDraws=0;rangeDraws=0
            local function hiddenWorld()
                worldDraws=worldDraws+1
                error('range requested its hidden world or HUD')
            end
            local context={runtime=runtime,width=960,height=720,ui=targets.ui,
                colors={cream={1,1,1}},holdPickupSeconds=1,scenery=scenery,catalog=Catalog,
                shootingRange={draw=function(...)
                    rangeDraws=rangeDraws+1;return Range.draw(...)
                end},mobileEnabled=function()return mobile end}
            for _,name in ipairs({'maintenanceSession','engineUpgrades','trainUpgradeBalance',
                'clouds','maintenance','firstAid','lastStand','npcImages','util','train','controlBindings'})do
                context[name]={}
            end
            for _,name in ipairs({'getCloudLayer','button','drawMenuFrame','drawTrade','isFurnitureItem',
                'containerValue','travelStatus','questSummary','screenToGame','getTrainView',
                'pointerPosition','getAudioStatus','drawLandscape','drawTracks','drawTrainView',
                'drawHouse','drawStop','drawExpedition','expeditionObjective','drawExpeditionLocalMap',
                'drawCaravan'})do context[name]=hiddenWorld end
            hud=require('game.gameplay_hud').new(context)
            function frame()
                Assets.releaseIntroImages(scenery,runtime)
                Assets.releaseDormantSceneArt(scenery,runtime)
                streamer:update(runtime.state,runtime.scene,data)
                Range.update(runtime.shootingRange,1/60,data,Catalog)
                hud.draw()
            end
        ''')

    def test_lobby_play_and_results_bypass_hidden_world_on_desktop_and_mobile(self):
        self.lua.execute('''
            for _,touch in ipairs({false,true})do
                mobile=touch
                local session=runtime.shootingRange
                session.phase='lobby';hud.draw()
                assert(Range.keypressed(session,'return',data,Catalog)=='start')
                hud.draw()
                session.phase='results'
                session.result={score=0,accuracy=0,highScore=0,gained=0,rewardTier=0,earnedRewardTier=0}
                hud.draw()
            end
            assert(rangeDraws==6 and worldDraws==0)
        ''')

    def test_warm_range_has_no_repeated_texture_uploads_or_decodes(self):
        self.lua.execute('''
            assert(Range.keypressed(runtime.shootingRange,'return',data,Catalog)=='start')
            frame()
        ''')
        self.probe.events.clear()
        self.lua.execute('for index=1,180 do frame()end;assert(worldDraws==0 and rangeDraws==181)')
        allocations = Counter(path for kind, path in self.probe.events if kind in ('texture', 'pixels'))
        self.assertEqual(allocations, {}, 'an active range must retain its warmed artwork')

    def test_leaving_range_resumes_world_rendering(self):
        self.lua.execute('''
            hud.draw();runtime.shootingRange=nil
            local ok,message=pcall(hud.draw)
            assert(not ok and message:find('range requested its hidden world or HUD',1,true))
            assert(worldDraws==1 and rangeDraws==1)
        ''')

    def test_range_cursor_hides_only_while_the_sight_sprite_is_drawn(self):
        self.lua.execute('''
            local Cursor=require('game.aim_cursor')
            visible=true
            love.mouse=love.mouse or {}
            love.mouse.isVisible=function() return visible end
            love.mouse.setVisible=function(value) visible=value end
            assert(Range.keypressed(runtime.shootingRange,'return',data,Catalog)=='start')
            Range.setAim(runtime.shootingRange,true)
            Cursor.beginFrame();hud.draw();Cursor.endFrame(false);assert(not visible)
            Range.setAim(runtime.shootingRange,false)
            Cursor.beginFrame();hud.draw();Cursor.endFrame(false);assert(visible)
            Range.setAim(runtime.shootingRange,true)
            Cursor.beginFrame();hud.draw();Cursor.endFrame(false);assert(not visible)
            runtime.shootingRange.phase='lobby'
            Cursor.beginFrame();hud.draw();Cursor.endFrame(false);assert(visible)
        ''')


if __name__ == '__main__':
    unittest.main()
