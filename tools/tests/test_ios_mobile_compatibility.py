"""iOS joins the existing shared mobile runtime without changing desktop defaults."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class IOSMobileCompatibilityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.globals().conf_path = (ROOT / "conf.lua").as_posix()
        self.lua.execute(r'''
            platform="Windows"
            mobilePreview=false
            smokeMode=false
            originalGetenv=os.getenv
            love={
                system={getOS=function() return platform end},
                filesystem=nil,
                graphics={getDimensions=function() return 960,720 end},
                timer={getTime=function() return 0 end},
            }
            os.getenv=function(name)
                if name=="MOUSE_FRONTIER_MOBILE" then return mobilePreview and "1" or nil end
                if name=="MOUSE_FRONTIER_SMOKE" then return smokeMode and "1" or nil end
                return originalGetenv(name)
            end
            Controls=require("game.mobile_controls")
            function controlsEnabled(osName,preview)
                platform=osName; mobilePreview=preview or false
                local controls=Controls.new({toGame=function(x,y) return x,y end,
                    pressKey=function() end,releaseKey=function() end,
                    pressPointer=function() end,movePointer=function() end,releasePointer=function() end})
                return controls:isEnabled()
            end
            function configured(osName,smoke)
                love._os=osName
                smokeMode=smoke or false
                local t={window={resizable=true,fullscreen=false,fullscreentype="desktop"}}
                love.conf(t)
                return t
            end
        ''')

    def test_platform_defaults_keep_android_windows_and_preview_behavior(self) -> None:
        self.lua.execute("dofile(conf_path)")
        self.assertTrue(self.lua.eval("controlsEnabled('Android')"))
        self.assertTrue(self.lua.eval("controlsEnabled('iOS')"))
        self.assertFalse(self.lua.eval("controlsEnabled('Windows')"))
        self.assertTrue(self.lua.eval("controlsEnabled('Windows',true)"))

        android = self.lua.globals().configured("Android")
        self.assertFalse(android.window.resizable)
        self.assertTrue(android.window.fullscreen)
        self.assertEqual("desktop", android.window.fullscreentype)

        windows = self.lua.globals().configured("Windows")
        self.assertTrue(windows.window.resizable)
        self.assertFalse(windows.window.fullscreen)
        ios = self.lua.globals().configured("iOS")
        self.assertTrue(ios.window.resizable)
        self.assertFalse(ios.window.fullscreen)
        self.assertEqual("mouse-frontier", windows.identity)
        smoke = self.lua.globals().configured("Windows", True)
        self.assertEqual("mouse-frontier-smoke", smoke.identity)

    def test_maintenance_uses_mobile_instruction_on_ios(self) -> None:
        self.lua.execute(r'''
            local Maintenance=require("game.maintenance")
            local Typography=require("game.typography")
            local drawn={}
            local originalDrawText=Typography.drawText
            Typography.drawText=function(_,text) drawn[#drawn+1]=text end
            local graphics={}
            for _,name in ipairs({"setColor","rectangle","circle","setLineWidth","printf","push","pop",
                    "translate","scale","draw","rotate","setStencilTest","setScissor"}) do
                graphics[name]=function() end
            end
            love.graphics=graphics
            platform="iOS"; mobilePreview=false
            local session={open=true,testMotion=0,assets={},targetDoses={0,0,0},targetMotion={},lampPulse={},
                particles={},spriteDrops={},serviceBursts={},conditionMotion=0,conditionFrom=70,conditionTo=70,
                donePress=0,message="",mouseX=-1000,mouseY=-1000}
            Maintenance.draw(session,{location=1,resources={oil=10},trainCars={"living-car"},maintenance={condition=70}})
            IOS_MAINTENANCE_TEXT=table.concat(drawn,"\n")
            Typography.drawText=originalDrawText
        ''')
        self.assertIn("Oil three hubs. Tap DONE when all five lamps are lit.", self.lua.globals().IOS_MAINTENANCE_TEXT)

    def test_touch_ids_synthetic_mouse_filter_and_focus_cancellation(self) -> None:
        self.lua.execute(r'''
            platform="iOS"; mobilePreview=false
            local MobileRuntime=require("game.mobile_runtime")
            local keysPressed,keysReleased={},{}
            local pointerEvents=0
            local mappedControlTouches=0
            local function viewportToGame(x,y)
                if x==252 and y==542 then mappedControlTouches=mappedControlTouches+1 end
                return x,y
            end
            local input={
                keypressed=function(key) keysPressed[#keysPressed+1]=key end,
                keyreleased=function(key) keysReleased[#keysReleased+1]=key end,
                mousepressed=function() pointerEvents=pointerEvents+1 end,
                mousemoved=function() pointerEvents=pointerEvents+1 end,
                mousereleased=function() pointerEvents=pointerEvents+1 end,
                beginTouchPickup=function() return false end,
            }
            local runtime={state="game",saveData={}}
            local app=MobileRuntime.new({runtime=runtime,ui={},maintenanceSession={},mobileControls=Controls,
                width=960,height=720,viewportToGame=viewportToGame,getCameraZoom=function() return 1 end,
                setCameraZoom=function() end,beginCameraPan=function() end,moveCameraPan=function() end,
                endCameraPan=function() end,getGameplayInput=function() return input end})
            app.initialize()
            local controls=app.get()
            app.touchpressed("opaque-touch-id",252,542)
            assert(controls.touches["opaque-touch-id"].kind=="joystick")
            assert(mappedControlTouches==1,"control touch must pass through viewport mapping once")
            local axisX=app.movement()
            assert(axisX>0,"iOS touch activates mobile movement")
            app.mousepressed(300,300,1,true)
            assert(pointerEvents==0,"synthetic touch mouse event is filtered")
            app.mousepressed(300,300,1,false)
            assert(pointerEvents==1,"real mouse event still reaches desktop input")
            app.touchpressed("action-id",controls.primary.x,controls.primary.y)
            assert(#keysPressed==1 and keysPressed[1]=="e","context action is held through the existing adapter")
            app.focus(false)
            axisX=app.movement()
            assert(axisX==0 and next(controls.touches)==nil,"focus loss clears held touch and movement state")
            assert(#keysReleased==1 and keysReleased[1]=="e","focus loss releases held action")
        ''')

    def test_focus_loss_keeps_the_existing_pending_save_flush(self) -> None:
        self.lua.execute(r'''
            local PersistenceRuntime=require("game.persistence_runtime")
            local runtime={state="game",selectedSlot=2,saveData={}}
            function runtime:syncForSave() self.syncCount=(self.syncCount or 0)+1 end
            local counts={mobile=0,audio=0,scheduled=0,flushed=0}
            local session={scheduleSave=function() counts.scheduled=counts.scheduled+1; return true end}
            local save={update=function() end,read=function() end,remove=function() end,
                flush=function() counts.flushed=counts.flushed+1; return true end}
            local persistence=PersistenceRuntime.new({runtime=runtime,ui={},session=session,save=save,
                maintenance={release=function() end},maintenanceSession={},
                focusMobile=function(focused) if not focused then counts.mobile=counts.mobile+1 end end,
                focusAudio=function(focused) if not focused then counts.audio=counts.audio+1 end end,
                shutdownAudio=function() end})
            assert(persistence.focus(false))
            assert(counts.mobile==1 and counts.audio==1,"focus loss reaches mobile and audio adapters")
            assert(counts.scheduled==1 and counts.flushed==1,"focus loss schedules and flushes pending progress")
            assert(runtime.syncCount==1,"save state is synchronized before flushing")
        ''')

    def test_save_identity_and_schema_version_are_unchanged(self) -> None:
        self.lua.execute("Config=require('game.config'); Schema=require('game.save_schema')")
        self.assertEqual("mouse-frontier", self.lua.globals().Config.identity)
        self.assertEqual(35, self.lua.globals().Schema.CURRENT_VERSION)
