"""Advanced editor interaction regressions with real UI and layout modules."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
lua_path = os.environ.get("LUA_RUNTIME_PYTHONPATH")
if lua_path:
    sys.path.insert(0, lua_path)
elif (ROOT / ".stabilization" / "python-deps").is_dir():
    sys.path.insert(0, str(ROOT / ".stabilization" / "python-deps"))
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable")
class PlayerUIEditorBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(r'''
            local function noop() end
            keys={}
            love={graphics={getDimensions=function() return 960,720 end,
                push=noop,pop=noop,origin=noop,translate=noop,rotate=noop,scale=noop,
                setColor=noop,setLineWidth=noop,rectangle=noop,circle=noop,line=noop},
                keyboard={isDown=function(key) return keys[key] end,setTextInput=noop}}
            package.loaded['game.typography']={drawText=noop}
            package.loaded['game.player_tools_model']={build=function() return {} end,filter=function() return {} end}
            storage={}; writes=0; failWrites=false; screen='game_train'
            fs={read=function(path) return storage[path] end,
                write=function(path,value)
                    writes=writes+1
                    if failWrites then return false,'disk unavailable' end
                    storage[path]=value; return true
                end}
            UIStyle=require('game.ui_layout')
            manager=UIStyle.new({filesystem=fs,screen=function() return screen end})
            ui=require('game.player_tools_ui').new({filesystem=fs,ui={menuFrames={[1]={},[2]={}}},
                controls=function() end,data=function() end,save=function() return true end,
                cancelInput=noop,uiedit=manager})
            local button=ui.button
            function ui:button(label,...)
                local rect=button(self,label,...); rect.label=label; return rect
            end
            ui:show(); ui.tab='UI Editor'
            parts={{'journeyHud',{x=40,y=60,w=260,h=110}},
                {'resourceHud',{x=620,y=180,w=300,h=300}}}
            function render()
                manager:beginFrame()
                for _,part in ipairs(parts) do manager:scope(part[1],part[2],noop) end
                ui:draw()
            end
            function findButton(label)
                for _,rect in ipairs(ui.buttons) do if rect.label==label then return rect end end
                error('No button '..label)
            end
            function click(label)
                render(); local r=findButton(label)
                ui:press(r.x+r.w/2,r.y+r.h/2,1); ui:finishDrag()
            end
            function closeTo(actual,expected)
                assert(math.abs(actual-expected)<.000001,tostring(actual)..' ~= '..tostring(expected))
            end
            render()
        ''')

    def test_panel_moves_clamps_and_collapses_without_layout_writes(self) -> None:
        self.lua.execute(r'''
            local header=ui.uiPanelHeader
            ui:press(header.x+10,header.y+10,1)
            assert(ui.uiPanelDrag and not ui.uiDrag)
            ui:move(-100,-100); ui:finishDrag()
            local r=ui:editorRect(); assert(r.x==4 and r.y==4 and r.h==480)
            assert(writes==0 and #ui:editorHistory().undo==0)
            click('-'); assert(ui.uiPanel.collapsed)
            render(); header=ui.uiPanelHeader
            ui:press(header.x+10,header.y+10,1)
            ui:move(2000,2000); ui:finishDrag()
            r=ui:editorRect(); assert(r.x==652 and r.y==676 and r.h==40)
            click('+'); r=ui:editorRect()
            assert(not ui.uiPanel.collapsed and r.y==236 and r.h==480)
            assert(writes==0 and not manager.dirty)
        ''')

    def test_wide_mobile_canvas_uses_entire_screen_for_panel_and_grips(self) -> None:
        self.lua.execute(r'''
            love.graphics.getDimensions=function() return 1560,720 end
            ui.uiPanel.x=-500; ui.uiPanel.y=20
            assert(ui:editorRect().x==-296)
            ui.uiPanel.x=2000
            assert(ui:editorRect().x==952)
            parts={{'journeyHud',{x=-280,y=20,w=1440,h=60}}}
            render()
            assert(ui.uiHandleRect.x==1145,'grip follows wide mobile HUD instead of the old 960px boundary')
            assert(writes==0)
        ''')

    def test_font_can_return_to_inherited_style_without_resetting_layout(self) -> None:
        self.lua.execute(r'''
            ui.uiPanel.section='Art'
            ui:editUi({x=24})
            click('FONT: AUTO'); assert(manager:get(ui.uiElement).fontOverride)
            click('FONT: REGULAR'); assert(manager:get(ui.uiElement).font=='bold')
            click('FONT: BOLD'); assert(not manager:get(ui.uiElement).fontOverride)
            assert(manager:get(ui.uiElement).x==24)
        ''')

    def test_ui_can_move_across_screen_and_home_recovers_position(self) -> None:
        self.lua.execute(r'''
            ui.uiPanel.collapsed=true; render()
            ui:press(100,100,1); ui:move(800,550); ui:finishDrag()
            closeTo(manager:get('journeyHud').x,700)
            closeTo(manager:get('journeyHud').y,450)
            click('+'); click('HOME')
            closeTo(manager:get('journeyHud').x,0)
            closeTo(manager:get('journeyHud').y,0)
            ui:undoUi(false)
            closeTo(manager:get('journeyHud').x,700)
        ''')

    def test_rotated_empty_corners_do_not_select_or_start_a_drag(self) -> None:
        self.lua.execute(r'''
            parts={{'resourceHud',{x=200,y=200,w=100,h=100}}}
            manager:set('resourceHud',{rotation=45},false)
            render(); ui:selectUiPart('inventory'); render()
            local r=manager.liveRects[manager:elementKey('resourceHud')]
            ui:press(r.x+2,r.y+2,1)
            assert(ui.uiElement=='inventory' and not ui.uiDrag)
            ui:press(250,250,1)
            assert(ui.uiElement=='resourceHud' and ui.uiDrag)
            ui:finishDrag()
        ''')

    def test_panel_blocks_canvas_hits_but_relocated_panel_frees_right_side(self) -> None:
        self.lua.execute(r'''
            ui:press(646,250,1); ui:move(650,270); ui:finishDrag()
            assert(ui.uiElement=='journeyHud' and manager:get('resourceHud').x==0 and writes==0)
            local header=ui.uiPanelHeader
            ui:press(header.x+10,header.y+10,1); ui:move(30,30); ui:finishDrag(); render()
            ui:press(800,300,1)
            assert(ui.uiElement=='resourceHud' and ui.uiDrag and ui.uiDrag.mode=='move')
            ui:move(840,330); ui:finishDrag()
            closeTo(manager:get('resourceHud').x,40); closeTo(manager:get('resourceHud').y,30)
            assert(writes==1 and #ui:editorHistory().undo==1)
        ''')

    def test_slider_endpoints_and_one_undo_record_per_drag(self) -> None:
        self.lua.execute(r'''
            for _,section in ipairs({'Layout','Color','Art'}) do
                ui.uiPanel.section=section; render()
                for _,slider in ipairs(ui.uiSliderRects) do
                    local before=#ui:editorHistory().undo
                    local oldWrites=writes
                    ui:press(slider.trackX,slider.y+slider.h/2,1)
                    closeTo(manager:get(ui.uiElement)[slider.key],slider.low)
                    ui:move(slider.trackX+slider.trackW*.5,slider.y+slider.h/2)
                    ui:move(slider.trackX+slider.trackW,slider.y+slider.h/2)
                    closeTo(manager:get(ui.uiElement)[slider.key],slider.high)
                    assert(writes==oldWrites and #ui:editorHistory().undo==before)
                    ui:finishDrag()
                    assert(writes==oldWrites+1 and #ui:editorHistory().undo==before+1)
                end
            end
            assert(type(ui.uiSlider)=='function' and not ui.uiSliderDrag)
        ''')

    def test_history_is_independent_per_preset_and_restores_all_styles(self) -> None:
        self.lua.execute(r'''
            ui:editUi({x=20,hue=.2}); ui:editUi({textScale=1.5})
            assert(#ui:editorHistory().undo==2)
            click('P2'); ui:editUi({x=70,font='bold'})
            assert(manager.activeSlot==2 and #ui:editorHistory().undo==1)
            ui:undoUi(false); assert(manager:get(ui.uiElement).x==0)
            ui:undoUi(true); assert(manager:get(ui.uiElement).x==70)
            click('P1'); assert(manager:get(ui.uiElement).x==20 and #ui:editorHistory().undo==2)
            keys.lctrl=true; ui:key('z'); keys.lctrl=nil
            closeTo(manager:get(ui.uiElement).textScale,1)
            closeTo(manager:get(ui.uiElement).hue,.2)
            keys.lctrl=true; ui:key('y'); keys.lctrl=nil
            closeTo(manager:get(ui.uiElement).textScale,1.5)
            click('P2'); assert(manager:get(ui.uiElement).x==70 and manager:get(ui.uiElement).font=='bold')
        ''')

    def test_reset_requires_confirmation_can_cancel_and_can_undo(self) -> None:
        self.lua.execute(r'''
            ui:editUi({x=55,rotation=30,scale=1.3}); local oldWrites=writes
            click('RESET')
            assert(ui.uiResetConfirm and manager:get(ui.uiElement).x==55 and writes==oldWrites)
            ui:key('escape')
            assert(ui.open and not ui.uiResetConfirm and manager:get(ui.uiElement).x==55)
            click('RESET'); click('CONFIRM')
            assert(not ui.uiResetConfirm and manager:get(ui.uiElement).x==0)
            closeTo(manager:get(ui.uiElement).scale,1)
            ui:undoUi(false)
            closeTo(manager:get(ui.uiElement).x,55); closeTo(manager:get(ui.uiElement).scale,1.3)
            closeTo(manager:get(ui.uiElement).rotation,30)
        ''')

    def test_save_failure_keeps_edits_and_save_button_retries(self) -> None:
        self.lua.execute(r'''
            failWrites=true; ui:editUi({x=88,textScale=1.4})
            assert(manager.dirty and manager:get(ui.uiElement).x==88)
            assert(ui.message:find('Save failed',1,true) and #ui:editorHistory().undo==1)
            failWrites=false; click('SAVE')
            assert(not manager.dirty and not manager.lastSaveError and writes==2)
            local restored=UIStyle.new({filesystem=fs,screen=function() return screen end})
            closeTo(restored:get(ui.uiElement).x,88); closeTo(restored:get(ui.uiElement).textScale,1.4)
        ''')

    def test_visible_picker_and_screen_selection_exclude_hidden_parts(self) -> None:
        self.lua.execute(r'''
            local list=ui:editorParts(false)
            assert(#list==2 and list[1]=='journeyHud' and list[2]=='resourceHud')
            assert(#ui:editorParts(true)>#list)
            ui:cycleUiPart(1); assert(ui.uiElement=='resourceHud')
            ui:cycleUiPart(1); assert(ui.uiElement=='journeyHud')
            ui:selectUiPart('inventory'); render()
            assert(ui.uiElement=='inventory' and not ui.uiSelectedRect)
            screen='battle'; parts={{'battle',{x=20,y=20,w=900,h=600}}}; render()
            assert(ui.uiElement=='battle' and manager.selected=='battle')
            local visible=ui:editorParts(false); assert(#visible==1 and visible[1]=='battle')
        ''')


if __name__ == '__main__':
    unittest.main()
