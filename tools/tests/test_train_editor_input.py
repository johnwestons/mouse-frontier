"""Train fitting must preserve object picking while leaving editor controls in UI space."""
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

HARNESS = r'''
local function noop() end
local function service(values) return setmetatable(values or {},{__index=function() return noop end}) end
love={keyboard={isDown=function() return false end}}
function fixture(scale,offsetX,offsetY)
    local calls={world=0,writes=0}
    local item={x=620,y=540,name='chair'}
    local runtime={state='game',scene='train',editMode=true,saveData={droppedItems={item},location=3}}
    local ui={playSfx=noop}
    local function screenToGame(x,y) return (x-120)/2,(y-30)/2 end
    local function worldCoordinates(x,y)
        calls.world=calls.world+1
        return (x-offsetX)/scale,(y-offsetY)/scale
    end
    local function uiToScreen(x,y) return x*2+120,y*2+30 end
    local function worldToScreen(x,y) return uiToScreen(x*scale+offsetX,y*scale+offsetY) end
    local trainCarRuntime=service({
        placeEditedItem=function(x,y) calls.placed={x=x,y=y}; item.x,item.y=x,y; return true end,
        moveEditedItem=function(dx,dy) calls.moved={x=dx,y=dy}; item.x,item.y=item.x+dx,item.y+dy; return true end,
    })
    local inventoryPresenter=service({
        handleClick=function(x,y) calls.inventory={x=x,y=y} end,
        handleRelease=function(x,y,button) calls.release={x=x,y=y,button=button} end,
    })
    local context={
        gameplayInputFactory=require('game.gameplay_input'),runtime=runtime,ui=ui,
        content={characters={},scenery={},isFurnitureItem=noop},maintenanceSession={},
        platform={persistenceRuntime=service({schedule=function() calls.writes=calls.writes+1 end}),
            presentationRuntime=service({screenToGame=screenToGame,worldCoordinates=worldCoordinates}),
            mobileRuntime=service(),trainCarRuntime=trainCarRuntime,audioRuntime=service()},
        adventure={inventoryActions=service(),journeyRules=service(),eventRuntime=service(),battleRuntime=service()},
        views={inventoryPresenter=inventoryPresenter,screenUI=service(),worldRenderer={
            trainItemAt=function(x,y)
                calls.picked={x=x,y=y}
                if math.abs(x-item.x-31)<=14 and math.abs(y-item.y-31)<=14 then return 1 end
            end,
        }},worldScene=service(),sessionBootstrap=service(),util=require('game.util'),
        resolveFirstAid=noop,chooseHelpDialogue=noop,
    }
    for _,name in ipairs({'inventory','catalog','npcRelationships','merchantTrade','engineUpgrades',
        'trainUpgradeBalance','maintenance','battleRules','stops','settlements','interiorDoors','intro',
        'interactions','firstAid','shootingRange','finaleProgression'}) do context[name]=service() end
    local input=require('game.input_composition').new(context).gameplayInput
    return {input=input,runtime=runtime,ui=ui,calls=calls,item=item,uiToScreen=uiToScreen,worldToScreen=worldToScreen}
end
function close(actual,expected)
    assert(math.abs(actual-expected)<.000001,tostring(actual)..' differs from '..tostring(expected))
end
'''


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class TrainEditorInputTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(HARNESS)

    def test_selection_and_drag_resolve_to_authored_item_positions(self) -> None:
        self.lua.execute(r'''
            for _,transform in ipairs({{1,0,0},{1.42,-290,-233},{.84,152,44},{1.7,-650,-440}}) do
                local f=fixture(unpack(transform))
                local x,y=f.worldToScreen(651,571)
                f.input.mousepressed(x,y,1)
                assert(f.runtime.editedItem==1 and f.runtime.editDragging)
                close(f.calls.picked.x,651); close(f.calls.picked.y,571)
                assert(f.calls.world==1,'selection converts exactly once')
                x,y=f.worldToScreen(675,555)
                f.input.mousemoved(x,y,48,-32)
                close(f.item.x,675); close(f.item.y,555)
                assert(f.calls.world==2,'drag converts exactly once')
                f.input.mousereleased(x,y,1)
                assert(not f.runtime.editDragging and f.calls.writes==1)
                assert(f.calls.world==2,'release must not transform stored coordinates again')
            end
        ''')

    def test_blank_space_does_not_select_scaled_item(self) -> None:
        self.lua.execute(r'''
            local f=fixture(1.4,-300,-220)
            local x,y=f.worldToScreen(730,600)
            f.input.mousepressed(x,y,1)
            assert(f.runtime.editedItem==nil and not f.runtime.editDragging)
            assert(f.calls.world==1)
        ''')

    def test_editor_done_button_stays_in_ui_space(self) -> None:
        self.lua.execute(r'''
            local f=fixture(1.4,-300,-220)
            f.ui.editDone={x=800,y=160,w=120,h=60}
            local x,y=f.uiToScreen(845,190)
            f.input.mousepressed(x,y,1)
            assert(not f.runtime.editMode and f.calls.writes==1)
            assert(f.calls.world==0 and f.calls.picked==nil)
        ''')

    def test_inventory_click_and_release_stay_in_ui_space(self) -> None:
        self.lua.execute(r'''
            local f=fixture(1.7,-540,-330)
            f.runtime.editMode=false; f.runtime.inventoryOpen=true
            local x,y=f.uiToScreen(360,240)
            f.input.mousepressed(x,y,1); f.input.mousereleased(x,y,1)
            close(f.calls.inventory.x,360); close(f.calls.inventory.y,240)
            close(f.calls.release.x,360); close(f.calls.release.y,240)
            assert(f.calls.world==0)
        ''')

    def test_editor_color_slider_drag_stays_in_ui_space(self) -> None:
        self.lua.execute(r'''
            local f=fixture(1.7,-540,-330)
            f.runtime.editedItem=1
            f.ui.editHue={x=700,y=180,w=180,h=40}
            f.ui.updateEditColorSlider=function(x) f.calls.slider=x end
            local x,y=f.uiToScreen(740,200)
            f.input.mousepressed(x,y,1)
            assert(f.ui.editSliderDrag=='hue'); close(f.calls.slider,740)
            x,y=f.uiToScreen(825,200)
            f.input.mousemoved(x,y,170,0)
            close(f.calls.slider,825)
            f.input.mousereleased(x,y,1)
            assert(f.ui.editSliderDrag==nil and f.calls.writes==1)
            assert(f.calls.world==0 and f.calls.placed==nil)
        ''')

    def test_arrow_keys_and_editor_nudge_buttons_keep_canonical_distance(self) -> None:
        self.lua.execute(r'''
            local f=fixture(1.7,-540,-330)
            f.runtime.editedItem=1
            f.input.keypressed('right')
            close(f.item.x,625); close(f.item.y,540)
            close(f.calls.moved.x,5); close(f.calls.moved.y,0)
            f.ui.editUp={x=800,y=160,w=100,h=60}
            local x,y=f.uiToScreen(850,190)
            f.input.mousepressed(x,y,1)
            close(f.item.x,625); close(f.item.y,535)
            close(f.calls.moved.x,0); close(f.calls.moved.y,-5)
            assert(f.calls.world==0,'nudge distances are already authored units')
        ''')


if __name__ == '__main__':
    unittest.main()
