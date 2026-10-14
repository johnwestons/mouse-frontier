"""Prediction remains disposable, bounded, collision-aware and host-corrected."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class PredictionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Prediction=require('game.coop_prediction'); Host=require('game.coop_movement')
            Step=require('game.coop_motion_step'); Wire=require('game.net.movement'); P=require('game.net.protocol')
            time=0; upper=1000
            record={character='legacy.png',activeCar=1,playerX=100,playerY=100,health=20}
            data={scene='house',coop={sceneEpoch=1},players={companion=record,host={character='host.png',activeCar=1,playerX=20,playerY=100}}}
            function move(_,_,ox,oy,x,y) return math.min(upper,math.max(0,x)),math.min(500,math.max(0,y)) end
            function pose(x,y) return {x=x or 100,y=y or 100,facing=1,activeCar=1,character=record.character,animationDistance=0} end
            predictor=Prediction.new({clock=function() return time end,data=function() return data end,move=move})
            predictor:reset(1,pose(),pose(20))
            function frame(serial,x,ack,age,active,hostX)
                local actor=pose(x); actor.velocityX=active and 185 or 0; actor.moving=active==true
                actor.intentX=active and 1 or 0
                return P.message('motion',{sessionId='prediction',motionId=1,sceneEpoch=1,serial=serial,tick=serial,ack=ack or 0,
                    ackAge=age or 0,inputActive=active==true,paused=false,ready=true,
                    host=Wire.packActor(pose(hostX or 20),data.players.host),companion=Wire.packActor(actor,record)})
            end
            assert(predictor:receive(frame(1,100),true)); assert(predictor:update({x=0,y=0,sprint=false},true))
            right={x=1,y=0,sprint=false}; left={x=-1,y=0,sprint=false}; zero={x=0,y=0,sprint=false}
        ''')

    def test_prediction_moves_before_reply_without_writing_replica_or_crossing_collision(self):
        self.lua.execute('''
            assert(predictor:sent(1,right)); upper=115
            for index=1,12 do time=index/60; assert(predictor:update(right,true)) end
            assert(predictor.actor.x==115 and predictor.display.x<=115 and record.playerX==100)
            assert(data.players.host.playerX==20 and predictor.authoritative.x==100)
            time=.4; predictor:update(right,true)
            assert(predictor:stale() and predictor.actor.x==100 and not predictor.actor.moving)
        ''')

    def test_held_sample_age_replays_elapsed_ticks_instead_of_packet_count(self):
        self.lua.execute('''
            assert(predictor:sent(1,right)); predictor:update(right,true)
            time=.25
            -- The same sample was already held for .15s at the host snapshot.
            -- Only .10s (three ticks), not .25s or one packet, remains to replay.
            assert(predictor:receive(frame(2,127.75,1,150,true),true))
            assert(math.abs(predictor.actor.x-146.25)<.0001)
            assert(record.playerX==100 and predictor.authoritative.x==127.75)
        ''')

    def test_reconciliation_replays_direction_changes_on_the_input_timeline(self):
        self.lua.execute('''
            predictor:sent(1,right); predictor:update(right,true)
            time=.05; predictor:sent(2,left); predictor:update(left,true)
            time=.10
            assert(predictor:receive(frame(2,100,1,0,true),true))
            -- The first replay tick is right, then two ticks are left.
            assert(math.abs(predictor.actor.x-(100-185/30))<.0001,predictor.actor.x)
        ''')

    def test_unknown_old_or_impossible_ack_cannot_create_unbounded_replay(self):
        self.lua.execute('''
            predictor:sent(1,right); predictor:update(right,true); time=1
            assert(predictor:receive(frame(2,120,1,0,true),true)); assert(predictor.actor.x==120)
            local ok,reason=predictor:receive(frame(3,130,2,0,true),true)
            assert(ok==nil and reason=='invalid_motion_ack')
            assert(predictor:receive(frame(1,2,0),true)==false and predictor.authoritative.x==120)
            local forged=frame(3,130,1,351,true); assert(not Wire.snapshot(forged))
        ''')

    def test_pause_scene_car_and_focus_boundaries_clear_old_prediction(self):
        self.lua.execute('''
            predictor:sent(1,right); time=.1; predictor:update(right,true); predictor:neutralize()
            assert(#predictor.history==0 and #predictor.sampleOrder==0 and not predictor.actor.moving)
            local paused=frame(2,112,1,0,true); paused.paused=true
            assert(predictor:receive(paused,true)); predictor:update(right,true)
            assert(predictor.actor.x==112 and not predictor.actor.moving)
            local changed=frame(3,180,1,0,true); changed.companion.car=2
            assert(predictor:receive(changed,true)); assert(predictor.actor.activeCar==2 and predictor.offsetX==0)
            predictor:reset(2,pose(500),pose(20)); assert(not predictor:receive(frame(4,10,1),true))
            time=.2; predictor:update(right,true); assert(predictor.actor.x==500 and #predictor.history==0)
        ''')

    def test_remote_motion_interpolates_without_extrapolation_and_teleports_snap(self):
        self.lua.execute('''
            assert(predictor:receive(frame(2,100,0,0,false,100),true))
            time=1/60; predictor:update(zero,true)
            assert(predictor.remote.x>20 and predictor.remote.x<100)
            for index=2,60 do time=index/60; predictor:update(zero,true); assert(predictor.remote.x<=100) end
            assert(predictor.remote.x==100 and not predictor.remote.moving)
            assert(predictor:receive(frame(3,600,0,0,false,500),true)); predictor:update(zero,true)
            assert(predictor.remote.x==500 and predictor.actor.x==600 and predictor.offsetX==0)
        ''')

    def test_sample_and_timeline_memory_stay_bounded(self):
        self.lua.execute('''
            for index=1,400 do
                time=index*.0001; local input=index%2==0 and right or left
                assert(predictor:sent(index,input)); predictor:update(input,true)
            end
            assert(#predictor.sampleOrder<=Prediction.MAX_SAMPLES and #predictor.history<=Prediction.MAX_HISTORY)
            local count=0; for _ in pairs(predictor.samples) do count=count+1 end
            assert(count<=Prediction.MAX_SAMPLES and record.playerX==100)
        ''')

    def test_actual_host_with_latency_loss_reordering_and_stopping_converges(self):
        self.lua.execute('''
            local campaign={coop={sceneEpoch=1},players={host={activeCar=1,playerX=20,playerY=100},
                companion={character=record.character,activeCar=1,playerX=100,playerY=100,health=20}}}
            local host=Host.host({campaign=campaign,clock=function() return time+100 end,move=move,
                hostActor=function() return pose(20) end,allowed=function() return true end})
            host:admit(7); assert(host:ready(7,1,host.motionId)); upper=260
            predictor:reset(1,pose(),pose(20)); assert(predictor:receive(host:snapshot('prediction'),true))
            local upstream,downstream={},{}; local sequence=0; local nextInput=0; local nextFrame=0
            local maxError=0; local predictedAhead=false
            for index=1,600 do
                time=index/120
                for i=#upstream,1,-1 do
                    if upstream[i].at<=time then host:receive(7,upstream[i].message); table.remove(upstream,i) end
                end
                assert(host:update())
                if time>=nextFrame then
                    nextFrame=nextFrame+1/12; local message=assert(host:snapshot('prediction'))
                    if message.serial%4~=0 then downstream[#downstream+1]={at=time+.06+(message.serial%3==0 and .1 or 0),message=message} end
                end
                if index%(renderEvery or 1)==0 then
                for i=#downstream,1,-1 do
                    if downstream[i].at<=time then
                        local ok,reason=predictor:receive(downstream[i].message,true); assert(ok~=nil,reason)
                        table.remove(downstream,i)
                    end
                end
                local input=time<1.3 and right or time<2 and left or zero
                if time>=nextInput then
                    nextInput=nextInput+.05; sequence=sequence+1; assert(predictor:sent(sequence,input))
                    if sequence%5~=0 then upstream[#upstream+1]={at=time+.06,message=P.message('movement',{
                        sessionId='prediction',motionId=1,sceneEpoch=1,sequence=sequence,x=input.x*1000,y=input.y*1000,sprint=false})} end
                end
                assert(predictor:update(input,true))
                assert(predictor.display.x>=0 and predictor.display.x<=upper and predictor.display.y==100)
                local error=math.abs(predictor.display.x-host.actor.x); maxError=math.max(maxError,error)
                if predictor.display.x-host.actor.x>3 then predictedAhead=true end
                end
            end
            assert(predictedAhead and maxError<80,maxError)
            assert(math.abs(predictor.display.x-host.actor.x)<.05,predictor.display.x..' vs '..host.actor.x)
            assert(not host.actor.moving and not predictor.actor.moving and record.playerX==100)
            assert(campaign.players.host.playerX==20 and host.sequence<=sequence)
        ''')

    def test_authored_gait_converges_at_thirty_and_sixty_fps(self):
        for every in (4, 2):
            with self.subTest(render_fps=120 // every):
                self.setUp()
                self.lua.execute("record.character='cook-mouse.png'; renderEvery=" + str(every))
                self.test_actual_host_with_latency_loss_reordering_and_stopping_converges()

    def test_host_echoes_age_at_last_simulated_step_and_clears_it_when_stale(self):
        self.lua.execute('''
            local host=Host.host({campaign=data,clock=function() return time end,move=move,
                hostActor=function() return pose(20) end,allowed=function() return true end})
            host:admit(7); assert(host:ready(7,1,host.motionId))
            time=.02; assert(host:receive(7,P.message('movement',{sessionId='prediction',motionId=1,sceneEpoch=1,
                sequence=1,x=1000,y=0,sprint=false})))
            time=.1; host:update(); local first=host:snapshot('prediction')
            assert(first.inputActive and first.ack==1 and first.ackAge==80 and first.tick==3)
            time=.105; assert(host:snapshot('prediction').ackAge==80) -- snapshot time is not simulation time
            time=.4; host:update(); local stopped=host:snapshot('prediction')
            assert(not stopped.inputActive and stopped.ackAge==0 and stopped.ack==1)
        ''')

    def test_expedition_prediction_reads_gates_and_flood_without_generation(self):
        self.lua.execute('''
            local Areas=require('game.expedition_areas'); local F=require('tools.tests.lua.coop_fixtures')
            local campaign=F.campaign(6); assert(F.enroll(campaign)); Areas.ensure(campaign)
            campaign.scene='expedition'; campaign.activeExpeditionArea=Areas.DUNGEON_ID
            local state=campaign.expeditions[Areas.DUNGEON_ID]
            for _,mob in pairs(state.mobs) do mob.dead=true end
            state.gates.bossGateOpen=false; state.completed=false
            Areas.ensure=function() error('predicted movement generated state') end
            Areas.state=function() error('predicted movement normalized state') end
            Areas.updateGates=function() error('predicted movement awarded progression') end
            local collision=require('game.coop_collision').new({car={},scenery={}})
            local x,y=collision(campaign,campaign.players.companion,966,490,1149,478)
            assert(x<1010 and not state.gates.bossGateOpen and not state.completed,x)
            state.gates.bossGateOpen=true
            x,y=collision(campaign,campaign.players.companion,966,490,1149,478)
            assert(math.abs(x-1149)<.01 and math.abs(y-478)<.01)
            local id=Areas.BADLANDS_BASIN_ID; local basin=campaign.expeditions[id]
            local definition=Areas.definition(id); basin.environmentPhase='dry'
            local point
            for _,p in ipairs(definition.environment.floodZone.points) do
                if Areas.isWalkable(campaign,id,p.x,p.y,true) then point=p; break end
            end
            assert(point); basin.environmentPhase='flooded'
            assert(not Areas.isWalkable(campaign,id,point.x,point.y,true))
            local missing={expeditions={}}; x,y=Areas.move(missing,id,100,100,120,100,true)
            assert(x==100 and y==100 and next(missing.expeditions)==nil)
        ''')

    def test_stop_correction_sweeps_thin_collision_obstacles(self):
        self.lua.execute('''
            local Settlements=require('game.settlements')
            Settlements.isWalkable=function(_,x,y) return x<49 or x>51 end
            local collision=require('game.coop_collision').new({car={},scenery={}})
            local x,y=collision({scene='stop',location=1},{},40,100,60,100)
            assert(x<49 and y==100)
        ''')

    def test_largest_valid_motion_frame_still_fits_the_realtime_packet_budget(self):
        self.lua.execute('''
            local value=frame(2147483647,100,2147483647,350,true)
            value.sessionId=string.rep('s',64); value.sceneEpoch=2147483647; value.tick=2147483647; value.motionId=2147483647
            for _,actor in ipairs({value.host,value.companion}) do
                actor.x=-100000000; actor.y=-100000000; actor.vx=-1000000; actor.vy=-1000000
                actor.ix=-1000; actor.iy=-1000; actor.d=9007199254740991; actor.p=9007199254740991
                actor.idle=3600000; actor.car=32; actor.f=-1; actor.moving=false
            end
            assert(Wire.snapshot(value))
            local bytes,reason=P.encode(value,P.REALTIME); assert(bytes,reason); assert(#bytes<=P.PACKET_BYTES)
            assert(Wire.snapshot(assert(P.decode(bytes,P.REALTIME))))
            value.inputActive=false; assert(not Wire.snapshot(value)) -- inactive frames cannot claim a held-input age
        ''')


if __name__ == '__main__':
    unittest.main()
