"""Range distance controls resize rendered targets and their playable hit areas."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class ShootingRangeDistanceTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=function() return .5 end}}
            Catalog=require('game.catalog'); Range=require('game.shooting_range')
            actor={location=2,equipment={'frontier-22-lever-rifle'},inventory={'monocular'},
                ammo={['22lr']=500},weaponDurability={['frontier-22-lever-rifle']=100}}
            function near(actual,expected,message)
                assert(math.abs(actual-expected)<1e-8,(message or 'unexpected geometry')..': '..actual..' / '..expected)
            end
            function rng(a,b) return a and a or .5 end
            function lobby(distance,material,canonical)
                spot={preferences={motion='stationary',material=material or 'paper',
                    targetPattern='stay-up',stageLength=30,distance=distance},highScores={}}
                return assert((canonical and Range.serverNew or Range.new)(actor,spot,Catalog))
            end
            function spawn(session,canonical)
                for i=1,3 do
                    if canonical then Range.serverUpdate(session,.08,actor,Catalog,rng)
                    else Range.update(session,.08,actor,Catalog) end
                end
                assert(#session.targets==1)
                return session.targets[1]
            end
            function start(session,canonical)
                if canonical then assert(Range.serverStart(session,actor,Catalog))
                else assert(Range.keypressed(session,'return',actor,Catalog)=='start') end
                return spawn(session,canonical)
            end
            function fresh(distance,material,canonical)
                local session=lobby(distance,material,canonical)
                return session,start(session,canonical)
            end
            function fire(session,canonical,x,y)
                if canonical then assert(Range.serverFire(session,actor,Catalog,x,y,rng))
                else assert(Range.mousepressed(session,x,y,actor,Catalog,1)=='shot') end
            end

            -- Capture the effective graphics transform, including the sectioned
            -- target's parent scale and the optional monocular camera.
            local g={};love.graphics=g
            for _,key in ipairs({'setColor','rectangle','circle','line','rotate','setLineWidth','print'}) do
                g[key]=function() end
            end
            g.getFont=function() return {getWidth=function() return 8 end,getHeight=function() return 14 end} end
            g.newQuad=function(x,y,w,h) return {w=w,h=h} end
            local matrix,stack
            g.push=function() stack[#stack+1]={sx=matrix.sx,sy=matrix.sy,x=matrix.x,y=matrix.y} end
            g.pop=function() matrix=assert(table.remove(stack)) end
            g.translate=function(x,y) matrix.x=matrix.x+x*matrix.sx;matrix.y=matrix.y+y*matrix.sy end
            g.scale=function(x,y) matrix.sx=matrix.sx*x;matrix.sy=matrix.sy*(y or x) end
            local function image(w,h)
                return {getDimensions=function() return w,h end,getWidth=function() return w end,getHeight=function() return h end}
            end
            assets={targets=image(1440,1080),sectionedTarget=image(528,712),
                sectionedFrame=image(128,174),impacts=image(400,200)}
            g.draw=function(img,a,b,c,d,e,f)
                local x,y,sx,sy
                if type(a)=='table' then x,y,sx,sy=b,c,e,f
                else x,y,sx,sy=a,b,d,e end
                draws[#draws+1]={image=img,x=matrix.x+x*matrix.sx,y=matrix.y+y*matrix.sy,
                    sx=matrix.sx*(sx or 1),sy=matrix.sy*(sy or sx or 1)}
            end
            require('game.typography').drawText=function() end
            function render(session,canonical,monocular)
                draws={};stack={};matrix={sx=1,sy=1,x=0,y=0}
                local model=canonical and Range.presentation(session,{hasMonocular=true,monocularActive=monocular}) or session
                if not canonical then model.monocularActive=monocular==true end
                Range.draw(model,actor,assets,{},Catalog,false)
                assert(#stack==0,'unbalanced draw transforms')
                return draws,model
            end
        ''')

    def test_all_distances_resize_actual_atlas_and_sectioned_draws(self):
        self.lua.execute('''
            for _,canonical in ipairs({false,true}) do
                for _,material in ipairs({'paper','steel','clay','sectioned'}) do
                    local previousScale
                    for _,distance in ipairs(Range.targetDistances) do
                        local s,t=fresh(distance,material,canonical)
                        local drawn=render(s,canonical)
                        assert(#drawn==(material=='sectioned' and 14 or 1))
                        local materialSize=material=='sectioned' and 1.4 or 1
                        local expected=.27*50/distance*materialSize
                        for _,draw in ipairs(drawn) do
                            near(draw.sx,expected,material..' rendered width at '..distance..' m')
                            near(draw.sy,expected,material..' rendered height at '..distance..' m')
                        end
                        near(t.radius,34*50/distance*materialSize,'hit radius must follow rendered size')
                        if previousScale then assert(drawn[1].sx<previousScale,'farther targets did not shrink') end
                        previousScale=drawn[1].sx
                    end
                end
            end
        ''')

    def test_targets_rise_toward_background_horizon_as_distance_increases(self):
        self.lua.execute('''
            for _,canonical in ipairs({false,true}) do
                for _,material in ipairs({'paper','steel','clay','sectioned'}) do
                    for lane=1,6 do
                        local previousY
                        for _,distance in ipairs(Range.targetDistances) do
                            local s=lobby(distance,material,canonical)
                            if canonical then assert(Range.serverStart(s,actor,Catalog))
                            else assert(Range.keypressed(s,'return',actor,Catalog)=='start') end
                            s.spawnIndex=lane-1
                            local t=spawn(s,canonical)
                            if material=='sectioned' then
                                near(t.x,480,'sectioned target must start in the center lane')
                                near(t.baseX,480,'sectioned target base position must be centered')
                            end
                            assert(t.y>225,'target rose above the ground horizon')
                            if previousY then assert(t.y<previousY,'farther target did not rise') end
                            if distance==25 then assert(t.y>420,'near target is too far up the background') end
                            if distance>=150 then assert(t.y<275,'distant target is too low on the background') end
                            previousY=t.y
                        end
                    end
                end
            end
        ''')

    def test_public_distance_controls_rebuild_targets_when_restarting(self):
        self.lua.execute('''
            for _,canonical in ipairs({false,true}) do
                local s=lobby(50,'paper',canonical)
                local function configure(direction,mouse)
                    if canonical then
                        local pose=Range.presentation(s,{menuRow=5})
                        local intent=mouse and Range.inputIntent(pose,'mousepressed',direction==1 and 700 or 250,405,1)
                            or Range.inputIntent(pose,'keypressed',direction==1 and 'right' or 'left')
                        assert(intent.action=='configure' and intent.kind=='distance')
                        assert(Range.serverConfigure(s,actor,Catalog,intent.kind,intent.direction))
                    elseif mouse then
                        assert(Range.mousepressed(s,direction==1 and 700 or 250,405,actor,Catalog,1)=='select')
                    else
                        assert(Range.keypressed(s,direction==1 and 'right' or 'left',actor,Catalog)=='select')
                    end
                end
                configure(1,true); assert(s.distance==75)
                configure(-1,false); assert(s.distance==50)
                configure(-1,false); assert(s.distance==25)
                local closeTarget=start(s,canonical)
                if canonical then assert(Range.serverSetup(s))
                else assert(Range.keypressed(s,'tab',actor,Catalog)=='setup') end
                configure(-1,true); assert(s.distance==300)
                local farTarget=start(s,canonical)
                assert(closeTarget~=farTarget,'restarting reused the previous target')
                near(closeTarget.scale/farTarget.scale,12,'25 m / 300 m visual size ratio')
                if not canonical then
                    assert(spot.preferences.distance==300)
                    local reopened=assert(Range.new(actor,spot,Catalog));assert(reopened.distance==300)
                end
            end
        ''')

    def test_hit_boundaries_follow_distance_for_all_target_types(self):
        self.lua.execute('''
            for _,canonical in ipairs({false,true}) do
                for _,material in ipairs({'paper','steel','clay','sectioned'}) do
                    for _,distance in ipairs({25,50,300}) do
                        for _,inside in ipairs({false,true}) do
                            local s,t=fresh(distance,material,canonical)
                            local offset=material=='sectioned' and (inside and 55 or 57)*t.scale
                                or t.radius*(inside and .99 or 1.01)
                            fire(s,canonical,t.x+offset,t.y)
                            assert(s.hits==(inside and 1 or 0),material..' hit boundary at '..distance..' m')
                        end
                    end
                end
            end
        ''')

    def test_monocular_magnifies_distance_scaled_targets_and_preserves_aim(self):
        self.lua.execute('''
            for _,canonical in ipairs({false,true}) do
                for _,distance in ipairs({25,50,300}) do
                    local s,t=fresh(distance,'paper',canonical)
                    local drawn,model=render(s,canonical,true)
                    near(drawn[1].sx,.27*50/distance*1.5,'monocular target scale')
                    local x,y=480+(t.x-480)*1.5,330+(t.y-330)*1.5
                    near(drawn[1].x,x,'monocular target center X')
                    near(drawn[1].y,y,'monocular target center Y')
                    if canonical then x,y=Range.canonicalAim(model,x,y) end
                    fire(s,canonical,x,y)
                    assert(s.hits==1,'monocular displayed target could not be hit')
                end
            end
        ''')

    def test_impact_marks_shrink_with_the_target(self):
        self.lua.execute('''
            for _,material in ipairs({'paper','steel'}) do
                for _,distance in ipairs({25,50,100,300}) do
                    local s,t=fresh(distance,material,true)
                    fire(s,true,t.x,t.y)
                    local drawn=render(s,true)
                    assert(#drawn==2 and drawn[2].image==assets.impacts)
                    near(drawn[2].sx*100,16*50/distance,'impact mark width')
                    near(drawn[2].sy*100,16*50/distance,'impact mark height')
                end
            end
        ''')


if __name__ == '__main__':
    unittest.main()
