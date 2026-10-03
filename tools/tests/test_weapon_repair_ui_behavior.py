"""Repair workbench input, layout, and cancellation without reading or writing saves."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable")
class WeaponRepairUIBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            noop=function() end
            textDraws={}; rectangles={}; color={}; mobile=false
            local font={}
            function font:getWidth(text) return #text*12 end
            function font:getHeight() return 22 end
            function font:getLineHeight() return 1.08 end
            function font:getWrap(text,width)
                local lines,longest={},0
                for paragraph in (text..'\n'):gmatch('(.-)\n') do
                    local line=''
                    for word in paragraph:gmatch('%S+') do
                        local nextLine=line=='' and word or line..' '..word
                        if line~='' and self:getWidth(nextLine)>width then
                            lines[#lines+1]=line; longest=math.max(longest,self:getWidth(line)); line=word
                        else line=nextLine end
                    end
                    lines[#lines+1]=line; longest=math.max(longest,self:getWidth(line))
                end
                return longest,lines
            end
            local gfx=setmetatable({getFont=function() return font end,getDimensions=function() return 960,720 end,
                setColor=function(r,g,b,a) color=type(r)=='table' and r or {r,g,b,a} end,
                rectangle=function(mode,x,y,w,h) rectangles[#rectangles+1]={mode=mode,x=x,y=y,w=w,h=h,color=color} end},
                {__index=function() return noop end})
            love={graphics=gfx,keyboard={isDown=function() return false end},timer={getTime=function() return 0 end}}
            Catalog=require('game.catalog'); Loot=require('game.loot_progression'); Util=require('game.util')
            Inventory=require('game.inventory'); Style=require('game.ui_layout')
            local Typography=require('game.typography'); local drawText=Typography.drawText
            Typography.drawText=function(graphics,text,x,y,w,h,options)
                local scale,height,lines,fits=drawText(graphics,text,x,y,w,h,options)
                textDraws[#textDraws+1]={text=text,x=x,y=y,w=w,h=h,height=height,scale=scale,lines=lines,fits=fits}
                return scale,height,lines,fits
            end
            weapon='frontier-short-sword'
            data={inventory={},inventoryCapacity=16,equipment={weapon},scrap=1000,weaponDurability={[weapon]=50}}
            runtime={state='game',scene='train',saveData=data,animationClock=10,trainUpgradeOpen=true,
                weaponRepairOpen=true,weaponRepairSelected=weapon,weaponRepairScroll=1}
            saves=0; repairs={}; cameraMoves=0; cameraZooms=0; pointerX,pointerY=220,250
            ui={playSfx=noop,drawItem=noop,handleRadioMousePressed=function() return false end,
                handlePoseClick=function() return false end}
            controls=require('game.control_bindings').new({getInfo=function() return nil end})
            local actions=require('game.inventory_actions').new({runtime=runtime,inventory=Inventory,catalog=Catalog,util=Util,
                trainUpgradeBalance=require('game.train_upgrade_balance'),lootProgression=Loot,
                writeSave=function() saves=saves+1 end,useBattleHealingItem=function() return false end,useBattlePotion=function() return false end})
            local context={runtime=runtime,ui=ui,characters={},maintenanceSession={},scenery={},inventory=Inventory,catalog=Catalog,
                controlBindings=controls,mobileEnabled=function() return mobile end,npcRelationships={},merchantTrade={},util=Util,
                engineUpgrades={},trainUpgradeBalance={},maintenance={},battleRules={},stops={},settlements={},interiorDoors={},firstAid={},shootingRange={},
                screenToGame=function(x,y) return x,y end,pointerPosition=function() return pointerX,pointerY end,
                cameraPanning=function() return false end,beginCameraPan=function() cameraMoves=cameraMoves+1 end,
                zoomCamera=function() cameraZooms=cameraZooms+1 end,
                repairWeapon=function(name,quality) repairs[#repairs+1]={name=name,quality=quality}; return actions.repairWeapon(name,quality) end}
            setmetatable(context,{__index=function() return noop end})
            input=require('game.gameplay_input').new(context)
            colors={panel={.1,.1,.1},cream={1,.9,.8},brass={.8,.6,.2},green={.1,.7,.3},red={.8,.2,.2}}
            local screenContext={runtime=runtime,ui=ui,width=960,height=720,colors=colors,scenery={},characters={},characterImages={},npcImages={},
                util=Util,catalog=Catalog,inventory=Inventory,eventUI={},engineUpgrades=require('game.engine_upgrades'),
                trainUpgradeBalance=require('game.train_upgrade_balance'),playerProgression={},stopHelpProgression={},npcRelationships={},
                merchantTrade={},finaleProgression={},maintenance=require('game.maintenance'),mobileEnabled=function() return mobile end,
                repairStatus=function(name) return Loot.repairStatus(data,Catalog,name) end}
            setmetatable(screenContext,{__index=function() return noop end})
            require('game.screen_ui').new(screenContext)
            function drawRepair() textDraws={}; rectangles={}; ui.drawTrainUpgrades() end
            function click(rect)
                local x,y=rect.x+rect.w/2,rect.y+rect.h/2
                input.mousepressed(x,y,1); input.mousereleased(x,y,1)
            end
            function populate(count)
                data.equipment={}; data.inventory={}; data.inventoryCapacity=math.max(16,count)
                for index=1,count do
                    local name=Catalog.weaponProgression[index]
                    data.inventory[index]=name; data.weaponDurability[name]=50
                end
                runtime.weaponRepairSelected=data.inventory[1]
                drawRepair()
            end
            function transformedRow(row)
                return Style.transformRectFor('trainUpgrades',{x=150,y=70,w=660,h=580},ui.repairRows[row].rect)
            end
            function styleWorkbench()
                local manager=Style.new({filesystem={getInfo=function() return nil end,read=function() return nil end},screen=function() return 'game' end})
                manager:set('trainUpgrades',{x=75,y=-22,scale=.8,rotation=8},false)
                return manager
            end
            drawRepair()
        ''')

    def test_mouse_started_repair_accepts_space_even_when_row_has_focus(self) -> None:
        self.lua.execute(r'''
            click(ui.repairStart)
            assert(runtime.weaponRepairStartedAt==10 and runtime.weaponRepairActiveWeapon==weapon)
            ui.keyboardFocusId='weapon-repair.select.'..weapon
            runtime.animationClock=10+.655/.86
            input.keypressed('space')
            assert(#repairs==1 and repairs[1].quality=='perfect')
            assert(data.weaponDurability[weapon]==100 and saves==1 and not runtime.weaponRepairStartedAt)
        ''')

    def test_controller_confirm_and_cancel_use_same_repair_flow(self) -> None:
        self.lua.execute(r'''
            local confirm=controls:translateButton('a','menu')
            local cancel=controls:translateButton('b','menu')
            assert(confirm=='return' and cancel=='escape')
            ui.keyboardFocusScreen='weapon-repair'; ui.keyboardFocusId='weapon-repair.start'
            input.keypressed(confirm)
            runtime.animationClock=10+.655/.86
            input.keypressed(confirm)
            assert(data.weaponDurability[weapon]==100 and saves==1)
            input.keypressed(cancel)
            assert(not runtime.weaponRepairOpen and runtime.trainUpgradeOpen)
            input.keypressed(cancel)
            assert(not runtime.trainUpgradeOpen)
        ''')

    def test_held_confirm_key_does_not_stop_or_restart_repair(self) -> None:
        self.lua.execute(r'''
            ui.keyboardFocusScreen='weapon-repair'; ui.keyboardFocusId='weapon-repair.start'
            input.keypressed('return',nil,false)
            runtime.animationClock=10+.655/.86
            input.keypressed('return',nil,true)
            assert(runtime.weaponRepairStartedAt and #repairs==0)
            input.keypressed('return',nil,false)
            assert(#repairs==1 and saves==1)
            input.keypressed('return',nil,true)
            assert(not runtime.weaponRepairStartedAt and #repairs==1)
        ''')

    def test_workshop_access_reopens_fresh_and_preserves_resources(self) -> None:
        self.lua.execute(r'''
            runtime.weaponRepairOpen=false
            runtime.weaponRepairStartedAt=1; runtime.weaponRepairActiveWeapon=weapon; runtime.weaponRepairDrag={}
            ui.weaponRepair={x=185,y=594,w=185,h=38,enabled=true}
            click(ui.weaponRepair)
            assert(runtime.weaponRepairOpen and not runtime.weaponRepairStartedAt and not runtime.weaponRepairActiveWeapon and not runtime.weaponRepairDrag)
            assert(runtime.weaponRepairSelected==weapon and data.scrap==1000 and saves==0)
        ''')

    def test_mouse_hit_regions_follow_custom_workbench_layout(self) -> None:
        self.lua.execute(r'''
            styleWorkbench(); drawRepair()
            click(ui.repairStart)
            assert(runtime.weaponRepairStartedAt,'transformed start button must activate exactly once')
            runtime.animationClock=10+.655/.86
            click(ui.repairStart)
            assert(saves==1)
            click(ui.repairBack)
            assert(not runtime.weaponRepairOpen and runtime.trainUpgradeOpen)
        ''')

    def test_keyboard_focus_uses_button_transform_once(self) -> None:
        self.lua.execute(r'''
            styleWorkbench(); drawRepair()
            ui.keyboardFocusScreen='weapon-repair'; ui.keyboardFocusId='weapon-repair.start'; ui.keyboardFocusVisible=true
            ui.drawKeyboardFocus()
            local ring=rectangles[#rectangles]
            assert(math.abs(ring.x-(ui.repairStart.x-2))<.001 and math.abs(ring.y-(ui.repairStart.y-2))<.001)
            input.keypressed('return')
            assert(runtime.weaponRepairStartedAt)
        ''')

    def test_drag_scroll_does_not_select_or_cancel_running_repair(self) -> None:
        self.lua.execute(r'''
            populate(12)
            local original=runtime.weaponRepairSelected
            click(ui.repairStart)
            input.mousepressed(210,410,1); input.mousemoved(210,210,0,-200); input.mousereleased(210,210,1)
            assert(runtime.weaponRepairScroll==5 and runtime.weaponRepairSelected==original)
            assert(runtime.weaponRepairStartedAt and #repairs==0 and saves==0)
            drawRepair()
            local nextName=ui.repairRows[2].name
            click(transformedRow(2))
            assert(runtime.weaponRepairSelected==nextName and not runtime.weaponRepairStartedAt and not runtime.weaponRepairActiveWeapon)
        ''')

    def test_transformed_row_selection_and_wheel_scroll(self) -> None:
        self.lua.execute(r'''
            populate(12); styleWorkbench(); drawRepair()
            local name=ui.repairRows[3].name
            click(transformedRow(3)); assert(runtime.weaponRepairSelected==name)
            local rect=transformedRow(2); pointerX,pointerY=rect.x+rect.w/2,rect.y+rect.h/2
            input.wheelmoved(0,-1); assert(runtime.weaponRepairScroll==2)
            for _=1,20 do input.wheelmoved(0,-1) end
            assert(runtime.weaponRepairScroll==7 and cameraZooms==0)
            pointerX,pointerY=900,680; input.wheelmoved(0,1)
            assert(runtime.weaponRepairScroll==7 and cameraZooms==0)
        ''')

    def test_mobile_drag_and_tap_reach_workbench(self) -> None:
        self.lua.execute(r'''
            mobile=true; populate(12)
            local touch=require('game.mobile_controls').new({enabled=true,toGame=function(x,y) return x,y end,
                pressKey=input.keypressed,releaseKey=input.keyreleased,pressPointer=input.mousepressed,
                movePointer=input.mousemoved,releasePointer=input.mousereleased,cameraGesturesActive=function() return false end})
            local original=runtime.weaponRepairSelected
            touch:touchpressed('finger',210,410)
            touch:touchmoved('finger',210,210,0,-200)
            touch:touchreleased('finger',210,210)
            assert(runtime.weaponRepairScroll==5 and runtime.weaponRepairSelected==original)
            drawRepair()
            local expected=ui.repairRows[2].name
            touch:touchpressed('finger',210,250); touch:touchreleased('finger',210,250)
            assert(runtime.weaponRepairSelected==expected)
            touch:touchpressed('finger',580,549); touch:touchreleased('finger',580,549)
            assert(runtime.weaponRepairStartedAt)
            runtime.animationClock=10+.655/.86
            touch:touchpressed('finger',580,549); touch:touchreleased('finger',580,549)
            assert(saves==1 and repairs[1].name==expected)
        ''')

    def test_cancel_and_world_shortcuts_do_not_spend_or_escape_modal(self) -> None:
        self.lua.execute(r'''
            click(ui.repairStart)
            for _,key in ipairs({'i','m','j','e','f','p','=','0'}) do input.keypressed(key) end
            input.mousepressed(20,20,3)
            assert(not runtime.inventoryOpen and not runtime.mapOpen and not runtime.journeyLogOpen)
            assert(cameraMoves==0 and cameraZooms==0 and runtime.weaponRepairStartedAt)
            input.keypressed('escape')
            assert(not runtime.weaponRepairOpen and not runtime.weaponRepairStartedAt and not runtime.weaponRepairActiveWeapon)
            assert(saves==0 and data.scrap==1000 and data.weaponDurability[weapon]==50)
        ''')

    def test_disabled_controls_and_page_navigation_are_bounded(self) -> None:
        self.lua.execute(r'''
            assert(ui.repairListUp.enabled==false and ui.repairListDown.enabled==false)
            data.weaponDurability[weapon]=100; drawRepair()
            assert(ui.repairStart.enabled==false)
            ui.keyboardFocusScreen='weapon-repair'; ui.keyboardFocusId='weapon-repair.start'
            input.keypressed('return'); assert(not runtime.weaponRepairStartedAt)
            populate(12)
            input.keypressed('pagedown'); assert(runtime.weaponRepairScroll==7)
            input.keypressed('pagedown'); assert(runtime.weaponRepairScroll==7)
            input.keypressed('pageup'); assert(runtime.weaponRepairScroll==1)
            input.keypressed('pageup'); assert(runtime.weaponRepairScroll==1)
        ''')

    def test_empty_inventory_clears_stale_selection_and_timing(self) -> None:
        self.lua.execute(r'''
            click(ui.repairStart)
            data.equipment={}; drawRepair()
            assert(not runtime.weaponRepairSelected and not runtime.weaponRepairStartedAt and not runtime.weaponRepairActiveWeapon)
            assert(not ui.repairRail and ui.repairStart.enabled==false and #ui.repairRows==0)
            click(ui.repairStart); assert(saves==0 and #repairs==0)
        ''')

    def test_selection_removed_during_timing_cannot_repair_replacement(self) -> None:
        self.lua.execute(r'''
            populate(2); click(ui.repairStart)
            local replacement=data.inventory[2]
            data.inventory[1]=nil; drawRepair()
            assert(runtime.weaponRepairSelected==replacement and not runtime.weaponRepairStartedAt)
            runtime.animationClock=10+.655/.86
            click(ui.repairStart)
            assert(runtime.weaponRepairStartedAt and #repairs==0 and saves==0)
        ''')

    def test_automatic_selection_change_clears_previous_result_message(self) -> None:
        self.lua.execute(r'''
            populate(2)
            runtime.weaponRepairMessage='Repair complete: 100% condition.'
            data.inventory[1]=nil; drawRepair()
            assert(not runtime.weaponRepairMessage)
        ''')

    def test_missing_part_instruction_and_component_names_fit_for_every_weapon(self) -> None:
        self.lua.execute(r'''
            for _,mode in ipairs({false,true}) do
                mobile=mode
                for name,partId in pairs(Catalog.weaponRepairParts) do
                    data.equipment={name}; data.weaponDurability[name]=25; runtime.weaponRepairSelected=name
                    drawRepair()
                    assert(ui.repairStart.enabled==false,name)
                    local found=false
                    for _,text in ipairs(textDraws) do
                        if text.text:find('Find this part',1,true) then
                            found=true; assert(text.text:find('chests',1,true) and text.text:find('backpack',1,true))
                            assert(text.fits,'missing-part guidance clips for '..name)
                        end
                        if text.x==494 and text.y==318 then assert(text.fits,'component label clips for '..name..': '..text.text) end
                    end
                    assert(found,name)
                end
            end
        ''')

    def test_visual_good_zone_matches_scored_zone_and_miss_is_free(self) -> None:
        self.lua.execute(r'''
            local good
            for _,rect in ipairs(rectangles) do if rect.y==444 and rect.color==colors.green then good=rect end end
            assert(good and math.abs((good.x-ui.repairRail.x)/ui.repairRail.w-.53)<.0001)
            assert(math.abs((good.x+good.w-ui.repairRail.x)/ui.repairRail.w-.78)<.0001)
            for _,case in ipairs({{.52,'miss'},{.531,'good'},{.655,'perfect'},{.779,'good'},{.781,'miss'}}) do
                data.weaponDurability[weapon]=50; data.scrap=1000; runtime.animationClock=10; drawRepair()
                local before=saves
                click(ui.repairStart); runtime.animationClock=10+case[1]/.86; click(ui.repairStart)
                assert(repairs[#repairs].quality==case[2])
                if case[2]=='miss' then assert(saves==before and data.scrap==1000) end
            end
        ''')

    def test_close_clears_drag_and_reentry_state(self) -> None:
        self.lua.execute(r'''
            click(ui.repairStart)
            input.mousepressed(210,210,1)
            assert(runtime.weaponRepairDrag)
            click(ui.repairClose)
            assert(not runtime.trainUpgradeOpen and not runtime.weaponRepairOpen and not runtime.weaponRepairDrag)
            assert(not runtime.weaponRepairStartedAt and not runtime.weaponRepairActiveWeapon and saves==0)
            runtime.weaponRepairOpen=true
            input.wheelmoved(0,-1)
            assert(cameraZooms==1,'a stale hidden repair flag must not swallow scrolling')
        ''')

    def test_runtime_entry_reset_clears_repair_transients(self) -> None:
        self.lua.execute(r'''
            local Runtime=require('game.runtime_state')
            local state=Runtime.new({session={},transition=noop})
            state.weaponRepairOpen=true; state.weaponRepairStartedAt=10
            state.weaponRepairActiveWeapon=weapon; state.weaponRepairDrag={startY=3}
            state:resetForGameEntry()
            assert(not state.weaponRepairOpen and not state.weaponRepairStartedAt and not state.weaponRepairActiveWeapon and not state.weaponRepairDrag)
        ''')


if __name__ == '__main__':
    unittest.main()
