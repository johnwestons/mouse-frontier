"""Host-clock movement, ownership, collision and bounded realtime messages."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class MovementTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Movement=require('game.coop_movement'); Wire=require('game.net.movement'); P=require('game.net.protocol')
            clock=0; blocked=false; hostActor={x=20,y=30,facing=1}
            data={coop={sceneEpoch=1},players={host={activeCar=1,playerX=20,playerY=30},
                companion={character='cook-mouse.png',health=20,activeCar=1,playerX=100,playerY=100,playerFacing=1}}}
            context={campaign=data,clock=function() return clock end,hostActor=function() return hostActor end,
                allowed=function() return not blocked end,
                move=function(campaign,record,ox,oy,x,y)
                    assert(campaign==data and record==data.players.companion)
                    return math.min(2000,math.max(0,x)),math.min(2000,math.max(0,y))
                end}
            sim=Movement.host(context); sim:admit(7)
            function input(sequence,x,y,sprint,epoch)
                return P.message('movement',{sessionId='host-session',motionId=sim.motionId,sceneEpoch=epoch or data.coop.sceneEpoch,
                    sequence=sequence,x=x or 1000,y=y or 0,sprint=sprint==true})
            end
            function step(seconds) clock=clock+(seconds or Wire.STEP); assert(sim:update()) end
            function run(count,sprint)
                assert(sim:ready(7,data.coop.sceneEpoch,sim.motionId))
                for i=1,count do assert(sim:receive(7,input(i,1000,0,sprint))); step() end
            end
        ''')

    def test_motion_uses_host_collision_and_never_changes_host_actor_or_inventory(self):
        self.lua.execute('''
            run(30); assert(data.players.companion.playerX>250 and data.players.companion.playerX<310)
            assert(hostActor.x==20 and hostActor.y==30 and data.players.host.playerX==20)
            assert(sim.actor.animationDistance>150 and sim.ack==30 and sim.tick==30)
            context.move=function(_,_,ox,oy,x,y) return math.min(x,300),y end
            for i=31,90 do assert(sim:receive(7,input(i))); step() end
            assert(data.players.companion.playerX==300 and not sim.actor.moving and sim.actor.velocityX==0)
        ''')

    def test_host_hazard_relocation_resets_prediction_generation_and_old_intents(self):
        self.lua.execute('''
            run(3); local old=sim.motionId; local stale=input(4)
            local epoch=data.coop.sceneEpoch; local hostX=hostActor.x
            assert(sim:relocate(690,515)); assert(sim.motionId==old+1 and sim.actor.x==690 and sim.actor.y==515)
            assert(not sim.input and not sim.simInput and not sim.readyEpoch and not sim.actor.moving)
            assert(data.coop.sceneEpoch==epoch and hostActor.x==hostX and data.players.companion.playerX==690)
            assert(not sim:receive(7,stale) and not sim:ready(7,epoch,old))
            local frame=assert(sim:snapshot('host-session')); assert(Wire.snapshot(frame) and frame.paused and not frame.ready)
            step(); assert(sim.actor.x==690)
            assert(sim:ready(7,epoch,sim.motionId)); assert(sim:receive(7,input(4))); step(); assert(sim.actor.x>690)
        ''')

    def test_invalid_or_unbound_relocation_never_changes_saved_position(self):
        self.lua.execute('''
            local id=sim.motionId
            for _,point in ipairs({{0/0,30},{30,math.huge},{'claimed',30},{100001,30}}) do
                assert(not sim:relocate(point[1],point[2])); assert(data.players.companion.playerX==100 and sim.motionId==id)
            end
            assert(not sim:relocate(nil,30))
            sim.motionId=2147483647; assert(not sim:relocate(400,300) and data.players.companion.playerX==100)
            sim:disconnect(7); assert(not sim:relocate(400,300) and data.players.companion.playerX==100)
        ''')

    def test_frame_rate_does_not_buy_extra_host_simulation_ticks(self):
        self.lua.execute('''
            assert(sim:ready(7,1,sim.motionId)); local sequence=0
            for i=1,120 do
                if i%6==1 then sequence=sequence+1; assert(sim:receive(7,input(sequence))) end
                step(1/120)
            end
            local x=data.players.companion.playerX; assert(sim.tick==30)
            clock=0; data.players.companion.playerX=100
            sim=Movement.host(context); sim:admit(7); assert(sim:ready(7,1,sim.motionId))
            for i=1,30 do assert(sim:receive(7,input(i))); step() end
            assert(math.abs(x-data.players.companion.playerX)<.000001 and sim.tick==30)
        ''')

    def test_stale_intent_stops_and_does_not_resume_on_later_updates(self):
        self.lua.execute('''
            assert(sim:ready(7,1,sim.motionId)); assert(sim:receive(7,input(1)))
            for _=1,9 do step() end
            step(.1); local x=sim.actor.x
            assert(not sim.actor.moving and sim.actor.velocityX==0 and not sim.input)
            step(.1); assert(sim.actor.x==x)
            assert(sim:receive(7,input(2))); step(); assert(sim.actor.x>x)
        ''')

    def test_scene_ack_epoch_and_peer_generation_are_required(self):
        self.lua.execute('''
            assert(not sim:receive(7,input(1))); assert(not sim:ready(6,1,sim.motionId)); assert(sim:ready(7,1,sim.motionId))
            assert(not sim:receive(8,input(1))); assert(sim:receive(7,input(2)))
            assert(not sim:receive(7,input(1))); step()
            data.coop.sceneEpoch=2; data.players.companion.playerX=450
            step(); assert(sim.actor.x==450 and not sim.input and not sim.readyEpoch)
            assert(not sim:ready(7,1,sim.motionId) and not sim:receive(7,input(3,1000,0,false,1)))
            assert(sim:ready(7,2,sim.motionId)); assert(sim:receive(7,input(3))); step(); assert(sim.actor.x>450)
            assert(sim:disconnect(7)); assert(not sim:ready(nil,2,sim.motionId) and not sim:receive(nil,input(4)))
            local x=sim.actor.x; step(); assert(sim.actor.x==x)
            sim:admit(8); assert(not sim:receive(7,input(4)) and not sim.readyEpoch)
        ''')

    def test_checkpoint_block_and_incapacitation_stop_without_mutating_saved_positions(self):
        self.lua.execute('''
            run(5); local x=sim.actor.x; blocked=true
            step(); assert(sim.actor.x==x and not sim.actor.moving and not sim.input)
            blocked=false; step(); assert(sim.actor.x==x)
            data.players.companion.health=0; assert(sim:receive(7,input(6))); step(); assert(sim.actor.x==x)
            local packet=assert(sim:snapshot('host-session')); assert(packet.paused)
        ''')

    def test_same_scene_car_change_rejects_old_ready_and_inputs_even_after_returning(self):
        self.lua.execute('''
            assert(sim:ready(7,1,sim.motionId)); local old=sim.motionId
            local delayed=input(100); assert(sim:receive(7,input(1))); step()
            data.players.companion.activeCar=2; data.players.companion.playerX=450
            step(); assert(sim.motionId==old+1 and sim.actor.x==450 and not sim.readyEpoch)
            assert(not sim:ready(7,1,old) and not sim:receive(7,delayed))
            assert(sim:ready(7,1,sim.motionId)); assert(sim:receive(7,input(2))); step()
            data.players.companion.activeCar=1; data.players.companion.playerX=100
            step(); assert(sim.motionId==old+2 and not sim:ready(7,1,old))
            assert(not sim:receive(7,delayed) and sim.actor.x==100)
        ''')

    def test_pause_catchup_is_bounded_and_new_input_cannot_retroactively_move(self):
        self.lua.execute('''
            assert(sim:ready(7,1,sim.motionId)); clock=20; assert(sim:receive(7,input(1)))
            assert(sim:update()); assert(sim.tick==4 and sim.actor.x<103)
            local x=sim.actor.x; clock=40; assert(sim:update())
            assert(sim.actor.x==x and sim.tick==8 and not sim.actor.moving)
            clock=39; local ok,reason=sim:update(); assert(not ok and reason=='invalid_clock')
        ''')

    def test_inputs_cannot_claim_actor_position_speed_or_story(self):
        self.lua.execute('''
            for _,field in ipairs({'actorId','playerX','speed','dt','command','scene','inventory'}) do
                local message=input(1); message[field]=1; assert(not Wire.input(message))
                assert(not sim:receive(7,message))
            end
            for _,value in ipairs({1001,-1001,math.huge,-math.huge,.5}) do
                local message=input(1); message.x=value; assert(not Wire.input(message))
            end
            local message=input(1); message.x=0/0; assert(not Wire.input(message))
            assert(data.players.companion.playerX==100)
        ''')

    def test_wire_roundtrip_is_small_owned_and_keeps_gait_state(self):
        self.lua.execute('''
            run(12,true); local message=assert(sim:snapshot('host-session'))
            local bytes=assert(P.encode(message,P.REALTIME)); assert(#bytes<=1200)
            local decoded=assert(P.decode(bytes,P.REALTIME)); assert(Wire.snapshot(decoded))
            local actor=Wire.unpackActor(decoded.companion)
            assert(math.abs(actor.x-sim.actor.x)<=.00051 and math.abs(actor.posePhase-sim.actor.posePhase)<=.00051)
            assert(actor.locomotionMode=='run' and actor.activeCar==1)
            actor.x=-99; decoded.companion.x=-99; assert(sim.actor.x>100 and data.players.companion.playerX>100)
            local prior=message.serial; blocked=true; step()
            local paused=assert(sim:snapshot('host-session')); assert(paused.serial>prior and paused.paused)
            message.host.extra=true; assert(not Wire.snapshot(message))
        ''')

    def test_legacy_characters_keep_normalized_motion_and_collision(self):
        self.lua.execute('''
            data.players.companion.character='legacy.png'; sim:admit(8); assert(sim:ready(8,1,sim.motionId))
            assert(sim:receive(8,input(1,100,100))); step()
            local delta=sim.actor.x-100; assert(math.abs(delta-185/30/math.sqrt(2))<.00001)
            assert(sim.actor.moving and sim.actor.animationDistance>0)
        ''')


if __name__ == '__main__':
    unittest.main()
