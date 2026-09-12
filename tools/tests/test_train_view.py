"""Uniform consist fitting and pointer conversion share the same real presentation chain."""
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
View=require('game.train_view')
Train=require('game.train')
car=require('game.config').trainCar
sizes={{960,720},{1280,720},{1920,1080},{2340,1080},{2400,1080},
    {2560,1440},{3440,1440},{1024,768},{1281,721},{720,1280}}
function close(actual,expected,label)
    assert(math.abs(actual-expected)<.000001,(label or 'coordinate')..': '..actual..' differs from '..expected)
end
local function noop() end
local function copy(value)
    if type(value)~='table' then return value end
    local result={}; for k,v in pairs(value) do result[k]=copy(v) end; return result
end
function same(a,b)
    assert(type(a)==type(b),'value type changed')
    if type(a)~='table' then assert(a==b,'value changed'); return end
    for k,v in pairs(a) do same(v,b[k]) end
    for k,v in pairs(b) do same(v,a[k]) end
end
function fixture(windowWidth,windowHeight,mobile,count)
    local graphics={}
    local matrix={sx=1,sy=1,x=0,y=0}
    local stack={}
    function graphics.getDimensions() return windowWidth,windowHeight end
    function graphics.push() stack[#stack+1]=copy(matrix) end
    function graphics.pop() matrix=table.remove(stack) end
    function graphics.translate(x,y)
        matrix.x,matrix.y=matrix.x+matrix.sx*x,matrix.y+matrix.sy*y
    end
    function graphics.scale(x,y) matrix.sx,matrix.sy=matrix.sx*x,matrix.sy*(y or x) end
    graphics.clear=noop; graphics.setColor=noop; graphics.rectangle=noop
    love={graphics=graphics}
    local runtime={state='game',scene='train',player={x=680,y=552},
        saveData={location=3,activeCar=1,trainCars={},droppedItems={
            {x=618,y=545,scale=1.3,rotation=.4,name='chair',car=1},
            {x=855,y=547,name='mailbox',car=2}},resources={food=17,water=19}}}
    for i=1,count or 1 do runtime.saveData.trainCars[i]={id='car-'..i} end
    local before=copy(runtime)
    local carBefore=copy(car)
    local ui={}
    local camera=assert(loadfile(root..'/game/camera.lua'))()
    local viewport=require('game.viewport')
    local offset={x=0,y=0}
    local f={runtime=runtime,ui=ui,camera=camera,viewport=viewport,offset=offset,
        before=before,carBefore=carBefore,points={{x=-115,y=670},{x=429,y=648},{x=680,y=552},{x=1049,y=670}}}
    local screens={is=function(_,state) return runtime.state==state end}
    function screens:draw()
        f.uiMatrix=copy(matrix)
        graphics.push()
        local layout=f.presentation.getTrainView()
        if layout then View.apply(layout) else graphics.translate(-offset.x,-offset.y) end
        f.worldMatrix=copy(matrix); f.rendered={}
        for i,p in ipairs(f.points) do
            f.rendered[i]={x=matrix.x+p.x*matrix.sx,y=matrix.y+p.y*matrix.sy}
        end
        graphics.pop()
    end
    f.presentation=require('game.presentation_runtime').new({runtime=runtime,ui=ui,screens=screens,
        maintenanceSession={},viewport=viewport,camera=camera,engineUpgrades={},maintenance={},
        width=960,height=720,car=car,mobileEnabled=function() return mobile end,
        drawExitPrompt=noop,drawMobileControls=noop,getWorldOffset=function() return offset.x,offset.y end})
    function f.checkRoundtrip()
        f.presentation.draw()
        for i,p in ipairs(f.points) do
            local x,y=f.presentation.screenToWorld(f.rendered[i].x,f.rendered[i].y)
            close(x,p.x,'world x'); close(y,p.y,'world y')
        end
    end
    return f
end
'''


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class TrainViewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(HARNESS)

    def test_largest_uniform_fit_respects_side_margins_and_header_at_all_shapes(self) -> None:
        self.lua.execute(r'''
            for _,size in ipairs(sizes) do
                for _,mobile in ipairs({false,true}) do
                    for _,count in ipairs({1,2,7}) do
                        local v=View.layout(car,960,720,size[1],size[2],{mobile=mobile,carCount=count})
                        assert(v.scale>0)
                        assert(v.left>=v.visibleLeft+20-.000001)
                        assert(v.right<=v.visibleRight-20+.000001)
                        assert(v.top>=v.headerBottom-.000001)
                        assert(v.bottom<720)
                        close(v.rail,670,'rail baseline')
                        close(v.left+v.right,960,'centered consist')
                        -- A larger uniform scale must exceed at least one of
                        -- the real constraints, rather than leave usable space.
                        local larger=v.scale*1.0001
                        local fitsWidth=(v.bounds.right-v.bounds.left)*larger<=v.visibleRight-v.visibleLeft-40
                        local fitsHeight=(v.bounds.rail-v.bounds.top)*larger<=v.rail-v.headerBottom
                        assert(not (fitsWidth and fitsHeight),'train is smaller than its available area')
                        local header=mobile and (count>1 and 324 or 214) or 238
                        assert(v.headerBottom>=header,'train intrudes into HUD or car tabs')
                    end
                end
            end
        ''')

    def test_car_count_reserves_tabs_without_shrinking_individual_authored_parts(self) -> None:
        self.lua.execute(r'''
            local one=View.layout(car,960,720,3440,1440,{mobile=true,carCount=1})
            local two=View.layout(car,960,720,3440,1440,{mobile=true,carCount=2})
            local seven=View.layout(car,960,720,3440,1440,{mobile=true,carCount=7})
            assert(two.headerBottom>one.headerBottom and two.scale<=one.scale)
            same(two,seven)
        ''')

    def test_wheels_coupling_character_and_contents_keep_shared_affine_anchors(self) -> None:
        self.lua.execute(r'''
            local engine=Train.locomotiveLayout(car)
            close(engine.overlap,2,'authored coupler overlap')
            for _,size in ipairs(sizes) do
                local v=View.layout(car,960,720,size[1],size[2],{mobile=true,carCount=1})
                for _,wheel in ipairs(engine.driverCenters) do
                    local _,contact=View.toView(v,wheel.x,wheel.y+engine.driverRadius)
                    close(contact,v.rail,'driver contact')
                end
                for _,name in ipairs({'pilot','tender'}) do
                    -- Small source wheels meet the rail within their authored
                    -- one-pixel overlap; that overlap must scale with the body.
                    for _,wheel in ipairs(engine[name..'Centers']) do
                        local _,contact=View.toView(v,wheel.x,wheel.y+engine[name..'Radius'])
                        close(contact-v.rail,(wheel.y+engine[name..'Radius']-Train.railY)*v.scale)
                    end
                end
                local enginePin=View.toView(v,engine.coupler,648)
                local carPin=View.toView(v,car.x,648)
                close(enginePin-carPin,2*v.scale,'coupler overlap scales together')
                for _,pair in ipairs({{{620,540},{680,552}},{{680,552},{855,547}},
                    {{429,670},{1049,670}},{{429,620},{429,670}}}) do
                    local ax,ay=View.toView(v,unpack(pair[1]))
                    local bx,by=View.toView(v,unpack(pair[2]))
                    close(bx-ax,(pair[2][1]-pair[1][1])*v.scale)
                    close(by-ay,(pair[2][2]-pair[1][2])*v.scale)
                    local x,y=View.toWorld(v,ax,ay)
                    close(x,pair[1][1]); close(y,pair[1][2])
                end
            end
        ''')

    def test_transition_distance_moves_entire_car_outside_both_viewport_edges(self) -> None:
        self.lua.execute(r'''
            for _,size in ipairs(sizes) do
                for _,count in ipairs({1,2,7}) do
                    local v=View.layout(car,960,720,size[1],size[2],{mobile=true,carCount=count})
                    local left=View.toView(v,v.bounds.left+v.transitionDistance,Train.railY)
                    local right=View.toView(v,v.bounds.right-v.transitionDistance,Train.railY)
                    assert(left>v.visibleRight and right<v.visibleLeft,'departing sprite remains onscreen')
                end
            end
        ''')

    def test_actual_viewport_camera_and_train_transform_roundtrip(self) -> None:
        self.lua.execute(r'''
            for _,size in ipairs(sizes) do
                for _,mobile in ipairs({false,true}) do
                    local f=fixture(size[1],size[2],mobile,3)
                    for _,zoom in ipairs({1,1.4,2.25}) do
                        f.presentation.setZoom(zoom)
                        f.presentation.panCamera(63,-41)
                        f.checkRoundtrip()
                        close(f.worldMatrix.sx,f.worldMatrix.sy,'all layers scale uniformly')
                    end
                end
            end
        ''')

    def test_default_hud_conversion_stays_in_ui_coordinates(self) -> None:
        self.lua.execute(r'''
            for _,size in ipairs(sizes) do
                local f=fixture(size[1],size[2],true,1)
                local ox,oy,sx,sy=f.viewport.transform(960,720)
                for _,p in ipairs({{25,18},{600,150},{-120,34},{920,280}}) do
                    local x,y=f.presentation.screenToGame(ox+p[1]*sx,oy+p[2]*sy)
                    close(x,p[1]); close(y,p[2])
                end
                f.presentation.draw()
                close(f.uiMatrix.sx,sx); close(f.uiMatrix.sy,sy)
                close(f.uiMatrix.x,ox); close(f.uiMatrix.y,oy)
            end
        ''')

    def test_zoom_focus_follows_fitted_player_position(self) -> None:
        self.lua.execute(r'''
            local f=fixture(2340,1080,true,1)
            f.points={f.runtime.player}
            f.presentation.setZoom(1.8); f.presentation.panCamera(57,-26)
            f.presentation.draw()
            local ox,oy,sx,sy=f.viewport.transform(960,720)
            local px,py=View.toView(f.presentation.getTrainView(),f.runtime.player.x,f.runtime.player.y)
            close(f.rendered[1].x,ox+(px+57)*sx)
            close(f.rendered[1].y,oy+(py-26)*sy)
            f.checkRoundtrip()
        ''')

    def test_editor_scope_uses_train_inverse_and_preserves_its_camera_state(self) -> None:
        self.lua.execute(r'''
            local f=fixture(2340,1080,true,2)
            f.presentation.setZoom(1.8); f.presentation.panCamera(37,-23)
            f.runtime.editMode=true
            assert(f.presentation.getSurface()=='game:editor')
            close(f.presentation.getZoom(),1)
            f.checkRoundtrip()
            f.presentation.setZoom(1.5); f.presentation.panCamera(-31,19)
            f.checkRoundtrip()
            f.runtime.editMode=false
            assert(f.presentation.getSurface()=='game:train')
            close(f.presentation.getZoom(),1.8)
            f.checkRoundtrip()
            f.runtime.editMode=true
            close(f.presentation.getZoom(),1.5)
            f.checkRoundtrip()
        ''')

    def test_pointer_anchored_zoom_and_physical_drag_pan_keep_world_alignment(self) -> None:
        self.lua.execute(r'''
            for _,size in ipairs({{1280,720},{2340,1080}}) do
                local f=fixture(size[1],size[2],true,1)
                f.points={f.runtime.player}
                f.presentation.draw()
                local anchor={x=f.rendered[1].x+40,y=f.rendered[1].y-20}
                local beforeX,beforeY=f.presentation.screenToWorld(anchor.x,anchor.y)
                f.presentation.setZoom(1.8,anchor.x,anchor.y)
                local afterX,afterY=f.presentation.screenToWorld(anchor.x,anchor.y)
                close(afterX,beforeX); close(afterY,beforeY)
                f.presentation.draw()
                local rendered=f.rendered[1]
                f.presentation.beginPan(100,100)
                assert(f.presentation.isPanning())
                f.presentation.movePan(220,55)
                f.presentation.endPan()
                assert(not f.presentation.isPanning())
                f.presentation.draw()
                close(f.rendered[1].x-rendered.x,120,'physical pan x')
                close(f.rendered[1].y-rendered.y,-45,'physical pan y')
                f.checkRoundtrip()
            end
        ''')

    def test_stop_house_expedition_caravan_and_non_game_scenes_are_unaffected(self) -> None:
        self.lua.execute(r'''
            local f=fixture(1920,1080,false,3)
            for _,scene in ipairs({'stop','house','expedition','caravan'}) do
                f.runtime.scene=scene; f.offset.x=245; f.offset.y=78
                assert(f.presentation.getTrainView()==nil)
                local x,y=f.presentation.worldCoordinates(100,210)
                close(x,345); close(y,288)
                f.presentation.setZoom(1.6); f.presentation.panCamera(32,-18)
                f.checkRoundtrip()
            end
            f.runtime.scene='train'; f.offset.x=0; f.offset.y=0
            for _,state in ipairs({'slots','characters','battle','event','ending'}) do
                f.runtime.state=state
                assert(f.presentation.getTrainView()==nil)
                f.checkRoundtrip()
            end
        ''')

    def test_fit_zoom_and_pointer_reads_do_not_rewrite_saves_or_canonical_geometry(self) -> None:
        self.lua.execute(r'''
            local f=fixture(2340,1080,true,3)
            for _,size in ipairs(sizes) do
                View.layout(car,960,720,size[1],size[2],{mobile=true,carCount=3})
                f.presentation.setZoom(1.6); f.presentation.panCamera(43,-19)
                f.presentation.getTrainView(); f.checkRoundtrip()
                f.presentation.resetCamera(true)
            end
            same(f.before,f.runtime); same(f.carBefore,car)
        ''')


if __name__ == '__main__':
    unittest.main()
