"""Large battlefield connectivity, stable geometry, and camera/picking contracts."""
from pathlib import Path
import os
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,os.environ.get('LUA_RUNTIME_PYTHONPATH',str(ROOT/'.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime

class BattleFieldTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path=ROOT.as_posix()+'/?.lua;'+self.lua.globals().package.path
        self.lua.execute("F=require('game.battle_field'); C=require('game.battle_camera')")

    def test_multiple_routes_and_fourfold_area_across_seeds(self):
        self.lua.execute('''
            local directions={{1,0},{-1,0},{0,1},{0,-1}}
            local Grid=require('game.battle_grid')
            for seed=1,100 do
                local f,tiles,variants,obstacles=F.generate(seed*1729,seed%4+1,seed%3==0 and 'hard' or 'easy')
                assert(F.validate(f));assert(f.columns==72 and f.rows==40)
                assert(F.playableCount(f,obstacles)>=2400)
                local function route(startRow,minimumRow,maximumRow)
                    local queue,seen={{q=0,r=startRow}},{['0:'..startRow]=true};local head=1
                    while queue[head]do
                        local p=queue[head];head=head+1;if F.isExit(f,p.q,p.r)then return true end
                        for _,v in ipairs(directions)do
                            local q,r=p.q+v[1],p.r+v[2];local k=q..':'..r
                            if q>=0 and q<f.columns and r>=minimumRow and r<=maximumRow and not seen[k]
                                and not obstacles[k] and F.traversalCost(f,p.q,p.r,q,r)then
                                seen[k]=true;queue[#queue+1]={q=q,r=r}
                            end
                        end
                    end
                    return false
                end
                assert(route(3,2,4),'north flank disconnected: '..seed)
                assert(route(f.rows-2,f.rows-3,f.rows-1),'south flank disconnected: '..seed)
                assert(route(f.rows/2,f.rows/2-4,f.rows/2+4),'central route disconnected: '..seed)
                for _,o in pairs(obstacles)do assert(not F.isCorridor(f,o.q+.5,o.r-.5))end
                local unit={q=0,r=3,hp=20};local count=0
                for _ in pairs(Grid.reachable({field=f,tiles=tiles,obstacles=obstacles,units={unit}},unit,5760))do count=count+1 end
                assert(count>=2400,'fewer than 2400 reachable spaces: '..seed..' / '..count)
            end
        ''')

    def test_deterministic_canonical_data_and_validation(self):
        self.lua.execute('''
            local f,a,b,c=F.generate(1847,2,'hard');local g,d,e,h=F.generate(1847,2,'hard')
            assert(f.elevationData==g.elevationData)
            for q=0,f.columns-1 do for r=1,f.rows do
                local k=q..':'..r;assert(a[q][r]==d[q][r] and b[q][r]==e[q][r])
                assert((c[k]and c[k].kind)==(h[k]and h[k].kind))
            end end
            local other=F.generate(1848,2,'hard');assert(f.elevationData~=other.elevationData)
            g.elevationData=g.elevationData:sub(2);assert(not F.validate(g))
            g=F.generate(1847,2,'hard');g.columns=35;assert(not F.validate(g))
            g=F.generate(1847,2,'hard');g.unknown=true;assert(not F.validate(g))
        ''')

    def test_generation_has_a_bounded_valid_fallback(self):
        self.lua.execute('''
            local original=F.connectedCount;F.connectedCount=function()return 0 end
            local field,tiles,variants,obstacles=F.generate(77,1,'hard');F.connectedCount=original
            assert(next(obstacles)==nil and F.validate(field))
            assert(original(field,obstacles)==2880 and F.playableCount(field,obstacles)==2880)
        ''')

    def test_projection_and_terrain_picking_across_azimuth_tilt_zoom_pan(self):
        self.lua.execute('''
            local f=F.generate(73091,1,'medium');local camera=C.new()
            camera:configure({x=17,y=53,w=1211,h=647})
            for yaw=0,345,15 do for _,tilt in ipairs({20,55,85})do for _,zoom in ipairs({.12,1,3.5})do
                camera.yaw=yaw;camera.tilt=tilt;camera:setZoom(zoom)
                local q,r=17,10;local x,z=q+.5,r-.5;local y=F.cellHeight(f,q,r)
                camera:focus(q,r,y);camera:pan(37,-29)
                local sx,sy=camera:project(x,y,z);local origin,direction=camera:ray(sx,sy)
                local a,b,hit=F.raycast(f,origin,direction)
                -- At grazing angles another foreground hill may legitimately be picked.
                assert(a~=nil and b~=nil and hit)
                local hx,hy=camera:project(hit[1],hit[2],hit[3])
                assert(math.abs(hx-sx)<.00001 and math.abs(hy-sy)<.00001)
                if tilt>=55 then assert(a==q and b==r,'project/pick mismatch')end
            end end end
            camera:pan(100000,-100000);assert(math.abs(camera.targetX)>100)
            camera:orbit(720,100);assert(camera.yaw<360 and camera.tilt==85)
        ''')

    def test_triangle_height_matches_vertical_raycast(self):
        self.lua.execute('''
            local f=F.generate(62381,4,'hard')
            for q=0,f.columns-1,3 do for r=1,f.rows,3 do for _,uv in ipairs({{.2,.3},{.8,.7},{.5,.5}})do
                local x,z=q+uv[1],r-1+uv[2];local y=F.heightAt(f,x,z)
                local a,b,hit=F.raycast(f,{x,40,z},{0,-1,0})
                assert(a==q and b==r and math.abs(hit[2]-y)<1e-8)
            end end end
        ''')

    def test_large_grid_uses_slope_costs_and_returns_a_legal_route(self):
        self.lua.execute('''
            local Grid=require('game.battle_grid')
            local f,tiles,variants,obstacles=F.generate(1847,1,'hard')
            local unit={q=0,r=3,hp=20};local battle={field=f,tiles=tiles,obstacles=obstacles,units={unit}}
            local cols,rows=Grid.dimensions(battle);assert(cols==71 and rows==40)
            local reachable=Grid.reachable(battle,unit,8)
            local path=assert(Grid.path(battle,unit,6,3,8,reachable))
            assert(path[1].q==0 and path[#path].q==6)
            for i=2,#path do local a,b=path[i-1],path[i]
                assert(math.abs(a.q-b.q)+math.abs(a.r-b.r)==1 and not obstacles[b.q..':'..b.r])
                assert(F.traversalCost(f,a.q,a.r,b.q,b.r))
            end
            local found=false
            for q=0,f.columns-2 do for r=1,f.rows do
                if F.traversalCost(f,q,r,q+1,r)==2 and not obstacles[q..':'..r] and not obstacles[(q+1)..':'..r]then
                    unit.q,unit.r=q,r;assert(not Grid.canMove(battle,unit,q+1,r,1));found=true
                end
            end end
            assert(found,'fixture contains no uphill costs');assert(Grid.audit().ready,'legacy battle regression')
        ''')

    def test_terrain_occludes_attacks_even_without_an_obstacle_sprite(self):
        self.lua.execute('''
            local Grid=require('game.battle_grid');local f,tiles=F.generate(91,4,'hard');local bytes={}
            for x=0,f.columns do for z=0,f.rows do bytes[#bytes+1]=string.format('%02x',x>=15 and x<=18 and 24 or 0)end end
            f.elevationData=table.concat(bytes)
            local battle={field=f,tiles=tiles,obstacles={}}
            local clear,obstacle=Grid.lineOfSight(battle,{q=10,r=10},{q=23,r=10})
            assert(not clear and obstacle.kind=='terrain-rise')
            assert(Grid.lineOfSight(battle,{q=2,r=10},{q=12,r=10}))
        ''')

if __name__=='__main__':unittest.main()
