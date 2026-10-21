"""Assist points follow visible scoring geometry without changing world state."""
import unittest
import test_mobile_weapon_aim_behavior as mobile


@unittest.skipIf(mobile.LuaRuntime is None, 'Lua 5.1 runtime unavailable')
class MobileAimTargetTests(unittest.TestCase):
    setUp = mobile.MobileWeaponAimBehaviorTests.setUp

    def test_production_window_and_vehicle_masks_accept_every_assist_point(self):
        cache = {}

        def image(path):
            if path not in cache:
                cache[path] = mobile.Image.open(mobile.ROOT / path).convert('RGBA')
            return cache[path]

        self.lua.globals().imageSize = lambda path: image(path).size
        self.lua.globals().imageAlpha = lambda path, x, y: image(path).getpixel((int(x), int(y)))[3] / 255
        self.lua.execute('''
            love.image={newImageData=function(path)
                local w,h=imageSize(path)
                return {getWidth=function() return w end,getHeight=function() return h end,
                    getPixel=function(_,x,y) return 1,1,1,imageAlpha(path,x,y) end}
            end}
            love.graphics={newImage=function(pixels)
                return {setFilter=function() end,getDimensions=function() return pixels:getWidth(),pixels:getHeight() end}
            end}
            local Targets=require('game.mobile_aim_targets')
            local Rules=require('game.train_ambush_rules')
            local Scene=require('game.train_ambush_scene')
            local state=Rules.start({location=6}); state.phase='combat'
            for _,vehicle in ipairs(state.vehicles) do
                vehicle.motion.phase='matched'
                for _,crew in ipairs(vehicle.crew) do crew.phase='aim' end
            end
            for _,far in ipairs({'wagon','cargo'}) do
                state.activeFar=far; Rules.vehicle(state,far).active=true
                local points=Targets.ambush(state,960,720); assert(#points>=2,'visible convoy must assist')
                for _,point in ipairs(points) do
                    local hit=Scene.target(state,960,720,point.x,point.y)
                    assert(hit and Scene.pointOpen(state,960,720,point.x,point.y),'assist entered frame/alpha hole')
                    local vehicle=Rules.vehicle(state,hit.vehicle)
                    assert(vehicle.hull>0 and (hit.kind=='hull' or Rules.exposed(vehicle.crew[hit.index])))
                end
            end
            local Window=require('game.window_scene')
            state={targets={}}
            for index in ipairs(Window.slots) do state.targets[index]={slot=index,status='exposed',health=3} end
            for _,window in ipairs({'wide','tall'}) do
                state.windowId=window
                local points=Targets.lastStand(state,960,720,true); assert(#points>0)
                for _,point in ipairs(points) do assert(Window.pointOpen(window,960,720,point.x,point.y)) end
            end
        ''')
        for pixels in cache.values():
            pixels.close()

    def test_range_filters_finished_targets_and_projects_zoom_and_world_view(self):
        self.lua.execute('''
            local Targets=require('game.mobile_aim_targets')
            local World=require('game.world_view')
            World.configure({toScreen=function(x,y) return x*1.2+10,y*1.2-30 end})
            local session={phase='play',hasMonocular=true,monocularActive=true,targets={
                {x=500,y=350,radius=20},{x=400,y=300,radius=20,hit=true},
                {x=400,y=300,radius=20,breaking=.1},{x=400,y=300,radius=20,clearing=true},
                {x=400,y=300,radius=20,life=0},{x=900,y=350,radius=20}}}
            local points=Targets.range(session,960,720)
            assert(#points==1); close(points[1].x,622); close(points[1].y,402); close(points[1].radius,36)
            session.canonicalView=true
            points=Targets.range(session,960,720)
            assert(#points==1); close(points[1].x,510); close(points[1].y,360); close(points[1].radius,30)
            session.targetPattern='pop-up'; session.targets[1].age=0
            assert(#Targets.range(session,960,720)==0)
            session.phase='result'; assert(#Targets.range(session,960,720)==0)
        ''')

    def test_section_centers_match_actual_scoring_and_ignore_broken_sections(self):
        self.lua.execute('''
            for index=1,13 do
                local h=newRangeHarness()
                local target={x=480,y=330,scale=1,radius=81,material='sectioned',points=100,sections={},impacts={}}
                h.session.targets={target}
                local points=Range.assistPoints(h.session); assert(#points==13)
                local point=points[index]
                local swayX,swayY=Range.sway(h.session,Catalog)
                assert(Range.serverFire(h.session,h.data,Catalog,point.x-swayX,point.y-swayY,math.random))
                assert(target.sections[index] and target.sections[index].hit,'wrong scoring section '..index)
                assert(#Range.assistPoints(h.session)==12)
                target.sections={}; target.sections[index]={broken=true}
                assert(#Range.assistPoints(h.session)==12)
            end
        ''')

    def test_last_stand_filters_dead_hidden_occluded_and_uses_local_window(self):
        self.lua.execute('''
            local Scene=require('game.window_scene')
            local Targets=require('game.mobile_aim_targets')
            local World=require('game.world_view')
            World.configure({toScreen=function(x,y) return x+30,y+50 end})
            Scene.layout=function(window,w,h) assert(window=='tall'); return {} end
            Scene.slotPosition=function(layout,index) return 100+index*50,200 end
            Scene.slotRect=function() return 0,0,40,60 end
            Scene.targetHit=function() return true end
            Scene.pointOpen=function(window,w,h,x,y) return x~=350 end
            local state={windowId='tall',targets={
                {slot=1,status='exposed',health=3},{slot=2,status='dying',health=0},
                {slot=3,status='hidden',health=3},{slot=4,status='hiding',health=3},
                {slot=5,status='firing',health=3},{slot=6,status='exposed',health=0},
                {slot=7,status='appearing',health=3}}}
            local points=Targets.lastStand(state,960,720)
            assert(#points==2); close(points[1].x,180); close(points[1].y,250)
            close(points[1].radius,18.4)
            points=Targets.lastStand(state,960,720,true)
            close(points[1].x,150); close(points[1].y,200)
            assert(state.targets[1].health==3 and state.targets[1].status=='exposed')
            state.ducking=true; assert(#Targets.lastStand(state,960,720)==0)
            state.ducking=false; state.coverProgress=.1; assert(#Targets.lastStand(state,960,720)==0)
            state.coverProgress=0; state.result='victory'; assert(#Targets.lastStand(state,960,720)==0)
        ''')

    def test_ambush_uses_visible_alpha_hit_and_skips_blocked_or_destroyed_vehicles(self):
        self.lua.execute('''
            local Scene=require('game.train_ambush_scene')
            local Rules=require('game.train_ambush_rules')
            local Targets=require('game.mobile_aim_targets')
            local entries={}
            local state={phase='combat',vehicles={}}
            for i,id in ipairs({'pickup','wagon','cargo'}) do
                entries[i]={id=id,x=(i-1)*200,y=100,sourceY=0,scale=1,cellW=100,height=100,
                    visual={clips={{x=30,y=30,w=40,h=40}}}}
                state.vehicles[i]={id=id,hull=i==3 and 0 or 20,crew={{hp=2,phase='aim'}}}
            end
            Scene.layout=function() return {vehicles=entries} end
            local probes=0
            Scene.target=function(s,w,h,x,y)
                probes=probes+1
                if x>200 then return {kind='hull',vehicle='pickup'} end -- Near hull occludes wagon.
                if x>35 and x<65 and y>135 and y<165 then return {kind='crew',vehicle='pickup',index=1} end
                return nil
            end
            local points=Targets.ambush(state,960,720)
            assert(probes>0 and #points==1); close(points[1].x,50); close(points[1].y,150)
            assert(state.vehicles[1].crew[1].hp==2 and state.vehicles[1].hull==20)
            state.vehicles[1].crew[1].phase='hidden'
            Scene.target=function(s,w,h,x,y) if x<200 then return {kind='hull',vehicle='pickup'} end end
            points=Targets.ambush(state,960,720); assert(#points==1)
            state.cover=true; assert(#Targets.ambush(state,960,720)==0)
            state.cover=false; state.phase='approach'; assert(#Targets.ambush(state,960,720)==0)
        ''')


if __name__ == '__main__':
    unittest.main()
