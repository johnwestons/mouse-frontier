"""Advanced UI layout persistence, nested selection and rendering boundaries."""
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
class UILayoutEditorBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            local noop=function() end
            local shader,stack=nil,{}
            graphics={origin=noop,scale=noop,translate=noop,rotate=noop,setColor=noop}
            graphics.push=function() stack[#stack+1]={shader=shader} end
            graphics.pop=function() shader=stack[#stack].shader; stack[#stack]=nil end
            graphics.getShader=function() return shader end
            graphics.setShader=function(value) shader=value end
            graphics.newShader=function(source)
                local result={source=source,uniforms={}}
                function result:send(key,...) self.uniforms[key]={...} end
                return result
            end
            love={graphics=graphics}
            stored={}; failWrite=false; currentScreen='game_train'
            filesystem={read=function(path) return stored[path] end,
                write=function(path,value)
                    if failWrite then return false,'disk unavailable' end
                    stored[path]=value; return true
                end}
            UIStyle=require('game.ui_layout')
            function newManager()
                return UIStyle.new({filesystem=filesystem,screen=function() return currentScreen end})
            end
            manager=newManager()
            function near(actual,expected)
                assert(math.abs(actual-expected)<.00001,tostring(actual)..' ~= '..tostring(expected))
            end
        ''')

    def test_presets_remember_screen_and_snapshot_is_independent(self) -> None:
        self.lua.execute(r'''
            manager:set('inventory',{x=37,rotation=15})
            currentScreen='battle'
            manager:set('inventory',{scale=1.8})
            local snapshot=manager:snapshotSlot()
            manager:useSlot(2)
            manager:set('inventory',{x=-90})
            manager:useSlot(1)
            manager:resetScreen('battle',false)
            near(manager:get('inventory').scale,1)
            near(manager:get('inventory','game_train').x,37)
            manager:restoreSlot(snapshot,false)
            snapshot['battle.inventory'].scale=2.4
            near(manager:get('inventory').scale,1.8)
            assert(manager:save())
            manager=newManager()
            near(manager:get('inventory').scale,1.8)
            manager:useSlot(2)
            near(manager:get('inventory').x,-90)
            near(manager:get('inventory','game_train').x,0)
        ''')

    def test_failed_save_keeps_edit_and_allows_retry(self) -> None:
        self.lua.execute(r'''
            failWrite=true
            local ok,message=manager:set('inventory',{x=22})
            assert(not ok and message=='disk unavailable' and manager.dirty)
            near(manager:get('inventory').x,22)
            failWrite=false
            assert(manager:save() and not manager.dirty and manager.lastSaveError==nil)
            filesystem.write=function() error('permission denied') end
            assert(not manager:set('inventory',{x=31}) and manager.dirty)
            near(manager:get('inventory').x,31)
        ''')

    def test_nested_rotation_bounds_do_not_expand_between_transforms(self) -> None:
        self.lua.execute(r'''
            local bounds={x=100,y=100,w=200,h=100}
            manager:set('parent',{rotation=45},false)
            manager:set('child',{rotation=-45},false)
            manager:scope('parent',bounds,function()
                manager:scope('child',bounds,function()
                    local hit=UIStyle.transformRect({x=100,y=100,w=200,h=100,enabled=true})
                    near(hit.x,100); near(hit.y,100); near(hit.w,200); near(hit.h,100)
                    assert(hit.enabled)
                end)
            end)
            local live=manager.liveRects[manager:elementKey('child')]
            near(live.x,100); near(live.y,100); near(live.w,200); near(live.h,100)
            assert(manager:hitElement('child',200,150))
            assert(not manager:hitElement('child',90,150))
            manager:beginFrame()
            assert(next(manager.liveRects)==nil and next(manager.liveRegions)==nil)
        ''')

    def test_rotated_selection_ignores_empty_corners_and_nested_move_follows_pointer(self) -> None:
        self.lua.execute(r'''
            local bounds={x=100,y=100,w=200,h=100}
            manager:set('child',{rotation=45},false)
            manager:scope('child',bounds,function() end)
            local live=manager.liveRects[manager:elementKey('child')]
            assert(not manager:hitElement('child',live.x+1,live.y+1))
            assert(manager:hitElement('child',200,150))
            manager:beginFrame()
            manager:set('parent',{rotation=90,scale=2},false)
            manager:scope('parent',bounds,function()
                manager:scope('child',bounds,function() end)
            end)
            local dx,dy=manager:moveDelta('child',20,0)
            near(dx,0); near(dy,-10)
        ''')

    def test_nested_color_shader_restores_parent_and_graphics_after_error(self) -> None:
        self.lua.execute(r'''
            manager:set('parent',{hue=.2,saturation=.7},false)
            manager:set('child',{hue=-.1,colorTint=.5},false)
            local bounds={x=0,y=0,w=200,h=100}
            local origin,scale,setColor=graphics.origin,graphics.scale,graphics.setColor
            manager:scope('parent',bounds,function()
                local parentShader=graphics.getShader()
                assert(parentShader and parentShader.uniforms.uiColorCount[1]==1)
                assert(parentShader.source:find('Texel(texture, textureCoords) * color',1,true))
                manager:scope('child',bounds,function()
                    assert(graphics.getShader()==parentShader)
                    assert(parentShader.uniforms.uiColorCount[1]==2)
                    near(parentShader.uniforms.uiColorSteps[1][1],-.1)
                    near(parentShader.uniforms.uiColorSteps[2][1],.2)
                end)
                assert(parentShader.uniforms.uiColorCount[1]==1)
                near(parentShader.uniforms.uiColorSteps[1][1],.2)
            end)
            assert(graphics.getShader()==nil)
            local ok=pcall(function()
                manager:scope('parent',bounds,function() error('draw failed') end)
            end)
            assert(not ok and graphics.getShader()==nil)
            assert(graphics.origin==origin and graphics.scale==scale and graphics.setColor==setColor)
            near(UIStyle.currentTextStyle(),1)
        ''')

    def test_existing_scene_shader_is_preserved(self) -> None:
        self.lua.execute(r'''
            local sceneShader={}
            graphics.setShader(sceneShader)
            manager:set('inventory',{hue=.2},false)
            manager:scope('inventory',{x=0,y=0,w=200,h=100},function()
                assert(graphics.getShader()==sceneShader)
            end)
            assert(graphics.getShader()==sceneShader)
        ''')

    def test_child_inherits_font_until_player_explicitly_changes_it(self) -> None:
        self.lua.execute(r'''
            local bounds={x=0,y=0,w=200,h=100}
            manager:scope('untouched',bounds,function()
                local _,font=UIStyle.currentTextStyle()
                assert(font==nil,'untouched UI retains authored font')
            end)
            manager:set('parent',{font='bold'},false)
            manager:set('child',{x=12},false)
            manager:scope('parent',bounds,function()
                manager:scope('child',bounds,function()
                    local _,font=UIStyle.currentTextStyle()
                    assert(font=='bold','position-only edits should not cancel parent font')
                end)
            end)
            manager:set('child',{font='regular'},false)
            assert(manager:save())
            manager=newManager()
            manager:scope('parent',bounds,function()
                manager:scope('child',bounds,function()
                    local _,font=UIStyle.currentTextStyle()
                    assert(font=='regular','explicit child font should survive a restart')
                end)
            end)
        ''')

    def test_shader_compile_failure_is_reported_and_tint_fallback_stays_usable(self) -> None:
        self.lua.execute(r'''
            graphics.newShader=function() error('shader not supported') end
            local resultingColor
            graphics.setColor=function(r,g,b) resultingColor={r,g,b} end
            manager:set('inventory',{hue=1/3},false)
            manager:scope('inventory',{x=0,y=0,w=200,h=100},function()
                graphics.setColor(1,0,0,1)
            end)
            assert(manager.lastColorError:find('shader not supported',1,true))
            near(resultingColor[1],0); near(resultingColor[2],1); near(resultingColor[3],0)
            assert(graphics.getShader()==nil)
        ''')


if __name__ == '__main__':
    unittest.main()
