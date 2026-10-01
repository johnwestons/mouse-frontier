"""Editor drags belong to one pointer and never leak into gameplay."""
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
class PlayerToolsHostBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(r'''
            local function noop() end
            love={graphics={getDimensions=function() return 1600,720 end,
                push=noop,pop=noop,clear=noop,translate=noop,scale=noop}}
            records={}
            app={}
            for _,name in ipairs({'update','draw','mousepressed','mousemoved','mousereleased',
                'touchpressed','touchmoved','touchreleased','keypressed','keyreleased',
                'gamepadpressed','gamepadreleased','gamepadaxis','wheelmoved','focus','quit','textinput'}) do
                local event=name
                app[event]=function(...)
                    records[#records+1]={event=event,args={...}}
                    if event=='draw' and drawHook then drawHook() end
                    return event
                end
            end
            function count(name)
                local total=0
                for _,record in ipairs(records) do if record.event==name then total=total+1 end end
                return total
            end
            package.loaded['game.ui_layout']={new=function()
                manager={frames=0,beginFrame=function(self) self.frames=self.frames+1; self.liveRects={} end}
                return manager
            end}
            package.loaded['game.player_tools_ui']={new=function(context)
                menu={open=false,tab='UI Editor',presses=0,moves=0,finishes=0,keys={}}
                function menu:show() self.open=true end
                function menu:close() self:finishDrag(); self.open=false; context.cancelInput() end
                function menu:focus(field) self.field=field end
                function menu:press(x,y,button)
                    self.presses=self.presses+1; self.lastPress={x,y,button}
                    if self.closeOnPress then self:close() end
                end
                function menu:move(x,y) self.moves=self.moves+1; self.lastMove={x,y} end
                function menu:finishDrag() self.finishes=self.finishes+1 end
                function menu:key(key)
                    self.keys[#self.keys+1]=key
                    if key=='escape' or key=='acback' then
                        if self.field then self:focus(nil) else self:close() end
                    elseif key=='f2' then self:close() end
                    return true
                end
                function menu:textinput(value) self.text=value end
                function menu:wheel(value) self.scroll=value end
                function menu:draw() end
                function menu:button() end
                return menu
            end}
            local Viewport=require('game.viewport')
            context={runtime={state='game',scene='train'},ui={},filesystem={},
                mobile={get=function() return {cancelAll=noop} end},
                presentation={endPan=noop,screenToGame=function(x,y) return Viewport.toGame(x,y,960,720) end},
                persistence={update=noop,schedule=noop,flush=noop}}
            require('game.player_tools_host').wrap(app,context)
            function openEditor()
                app.keypressed('f2'); app.keyreleased('f2'); records={}
                menu.presses=0; menu.moves=0; menu.finishes=0
            end
        ''')

    def test_touch_owner_ignores_other_touches_and_mouse_events(self) -> None:
        self.lua.execute(r'''
            openEditor()
            app.touchpressed(1,420,100)
            app.touchpressed(2,700,200)
            app.touchmoved(2,800,300)
            app.mousepressed(420,100,1,true)
            app.mousemoved(900,400,10,10,true)
            app.mousemoved(950,450,10,10,false)
            app.mousereleased(900,400,1,true)
            app.mousereleased(900,400,2,false)
            app.touchreleased(2,800,300)
            assert(menu.presses==1 and menu.moves==0 and menu.finishes==0)
            app.touchmoved(1,460,150)
            assert(menu.moves==1 and menu.lastMove[1]==140 and menu.lastMove[2]==150)
            assert(menu.lastPress[1]==100 and menu.lastPress[2]==100)
            app.touchreleased(1,460,150)
            assert(menu.finishes==1 and #records==0)
        ''')

    def test_mouse_owner_ignores_second_button_and_touch(self) -> None:
        self.lua.execute(r'''
            openEditor()
            app.mousepressed(520,100,1,false)
            app.mousepressed(520,100,2,false)
            app.touchpressed(2,700,200)
            app.touchmoved(2,800,300)
            app.touchreleased(2,800,300)
            app.mousereleased(520,100,2,false)
            assert(menu.presses==1 and menu.moves==0 and menu.finishes==0)
            app.mousemoved(620,120,100,20,false)
            app.mousereleased(620,120,1,false)
            assert(menu.moves==1 and menu.finishes==1 and #records==0)
        ''')

    def test_close_consumes_remaining_touch_and_synthetic_mouse(self) -> None:
        self.lua.execute(r'''
            openEditor(); menu.closeOnPress=true
            app.touchpressed(1,420,100)
            assert(not menu.open)
            app.touchmoved(1,450,110)
            app.touchreleased(1,450,110)
            app.mousereleased(450,110,1,true)
            assert(count('touchmoved')==0 and count('touchreleased')==0 and count('mousereleased')==0)
        ''')

    def test_focus_loss_cancels_owner_and_consumes_late_releases(self) -> None:
        self.lua.execute(r'''
            openEditor(); menu.field='query'
            app.touchpressed(1,420,100)
            app.focus(false); app.focus(true)
            assert(menu.finishes==1 and menu.field==nil)
            menu:close(); records={}
            app.touchreleased(1,420,100)
            app.mousereleased(420,100,1,true)
            assert(#records==0)
            openEditor()
            app.mousepressed(500,200,1,false)
            app.mousereleased(500,200,1,false)
            assert(menu.presses==1 and menu.finishes==1)
        ''')

    def test_escape_respects_text_focus_and_does_not_reach_game(self) -> None:
        self.lua.execute(r'''
            openEditor(); menu.field='query'
            app.keypressed('escape')
            assert(menu.open and menu.field==nil)
            app.keypressed('escape','escape',true)
            assert(menu.open)
            app.keyreleased('escape')
            app.keypressed('escape')
            assert(not menu.open and count('keypressed')==0)
            app.keypressed('escape','escape',true)
            app.keyreleased('escape')
            assert(count('keypressed')==0)
            app.keypressed('escape')
            assert(count('keypressed')==1)
        ''')

    def test_host_preserves_game_callbacks_and_editor_keyboard(self) -> None:
        self.lua.execute(r'''
            assert(app.textinput('game')=='textinput')
            assert(app.mousemoved(1,2,3,4,false)=='mousemoved')
            assert(records[#records].args[4]==4 and records[#records].args[5]==false)
            openEditor()
            app.keypressed('left'); app.keypressed('left','left',true)
            app.keypressed('lctrl'); app.keypressed('z'); app.textinput('editor')
            assert(#menu.keys==4 and menu.keys[4]=='z' and menu.text=='editor')
            assert(count('keypressed')==0 and count('textinput')==0)
            app.draw(); assert(manager.frames==1)
        ''')

    def test_options_overlay_is_hidden_only_during_hud_preview(self) -> None:
        self.lua.execute(r'''
            openEditor(); context.ui.optionsOpen=true; menu.uiElement='journeyHud'
            drawHook=function()
                manager.liveRects[context.ui.optionsOpen and 'options' or 'journeyHud']={}
            end
            app.draw()
            assert(context.ui.optionsOpen==true)
            assert(manager.liveRects.journeyHud and not manager.liveRects.options)
            menu.uiElement='options'; app.draw()
            assert(context.ui.optionsOpen==true)
            assert(manager.liveRects.options and not manager.liveRects.journeyHud)
            menu.uiElement='journeyHud'; menu.tab='Controls'; app.draw()
            assert(manager.liveRects.options and context.ui.optionsOpen==true)
            menu:close(); app.draw()
            assert(manager.liveRects.options and context.ui.optionsOpen==true)
            menu:show(); menu.tab='UI Editor'; menu.uiElement='options'
            context.ui.optionsOpen=false; app.draw()
            assert(context.ui.optionsOpen==false and not manager.liveRects.options)
        ''')

    def test_options_overlay_state_is_restored_after_drawing_failure(self) -> None:
        self.lua.execute(r'''
            openEditor(); context.ui.optionsOpen=true; menu.uiElement='journeyHud'
            drawHook=function()
                assert(context.ui.optionsOpen==false)
                error('preview failure')
            end
            local ok,message=pcall(app.draw)
            assert(not ok and message:find('preview failure',1,true))
            assert(context.ui.optionsOpen==true)
        ''')


if __name__ == '__main__':
    unittest.main()
