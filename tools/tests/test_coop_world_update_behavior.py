"""Exercise the production update path with separate local/shared pauses."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class SharedWorldUpdateTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            counts={world=0,npc=0,persist=0,cloud=0,audio=0,aid=0,maintenance=0,interaction=0,range=0}
            function count(key) counts[key]=counts[key]+1 end
            function point(x,y) return x,y end
            function move(_,_,x,y) return x,y end
            love={keyboard={isDown=function(key) return key=='d' end},math={random=math.random},
                mouse={getPosition=function() return 100,200 end}}
            package.loaded['game.assets']={releaseIntroImages=function() end,releaseDormantSceneArt=function() end}
            package.loaded['game.character_motion']={profileFor=function() end}
            package.loaded['game.accessibility']={motionSpeed=function() return 1 end}
            -- Isolate routine movement while exercising the production
            -- SceneNPCs dispatcher and its actor-specific hold callback.
            package.loaded['game.family']={update=function() count('npc') end}
            package.loaded['game.npc_routines']={update=function(_,actor,dt,options)
                if options.held then
                    actor.targetX=nil; actor.moving=false; actor.velocityX=0
                else
                    actor.targetX=700; actor.x=actor.x+32*dt; actor.moving=true
                end
            end}
            runtime={state='game',scene='train',session={networkMode='host'},animationClock=0,
                walkingSoundTimer=0,actionTimer=0,sceneryOffset=0,landscapeOffset=0,
                player={x=100,y=200,speed=60,moving=true,velocityX=9,velocityY=2},
                npcActor={x=600,y=430,homeX=600,homeY=430,targetX=700,targetY=430,wait=100},
                saveData={location=20,character='mouse.png',currentNPC='medic.png',trainCars={'living-car'},
                    passengers={{x=200,y=420,wait=100,targetX=400,targetY=420,npc='friend.png',carIndex=1}}}}
            runtime.npcActor.file='medic.png'; runtime.npcActor.scene='house'; runtime.npcActor.homeDoor=1
            resident=runtime.npcActor
            runtime.saveData.stopLayouts={['20']={residentVersion=1,residentKeys={'resident:20:medic.png'}}}
            runtime.saveData.npcStates={['resident:20:medic.png']=runtime.npcActor}
            ui={playSfx=function() end,remoteWorldActor=function()
                return {scene='house',activeHouseDoor=1},{x=200,y=250}
            end}; maintenance={open=false}
            update=require('game.gameplay_update').new({runtime=runtime,width=960,holdPickupSeconds=1,
                ui=ui,car={x=0,y=0,w=960},landscape={},scenery={},cloudLayer={},maintenanceSession=maintenance,
                mobileEnabled=function() return false end,mobileMovement=function() return 0,0 end,
                mobileHeld=function() return false end,mobileSprinting=function() return false end,
                interactionRouter={select=function() count('interaction'); return {} end,flags=function() return {} end},
                inventoryActions={},journeyRules={},catalog={},settlements={move=function(_,_,_,x,y) return x,y end,clamp=point},
                interiorDoors={},interactions={},updatePersistence=function() count('persist') end,
                clouds={update=function() count('cloud') end},screens={is=function() return false end,update=function() return false end},
                engineUpgrades={},trainUpgradeBalance={},maintenance={update=function() count('maintenance') end},
                family={update=function() count('npc') end},util={clampHouseFloor=point},passengers={},
                screenToGame=point,updateAudio=function() count('audio') end,ensureStopLayout=function() return {} end,
                updateWorldScene=function() count('world'); if barrier then runtime.session.checkpointPending=true end
                    if encounter then runtime.state='battle' end end,
                currentShootingRange=function() end,handleShootingRange=function() end,clampToTrainFloor=point,
                itemIsHere=function() return true end,setupNPC=function() end,moveExpedition=move,
                currentExpeditionInteraction=function() end,moveCaravan=move,currentCaravanInteraction=function() end,
                trainFloorBounds=function() return 0,960,200,500 end,updateCarTransition=function() return carBusy end,
                writeSave=function() error('unexpected save') end,firstAid={update=function() count('aid') end},
                shootingRange={update=function() count('range') end},rangeUpdate=function() if runtime.session.networkMode=='host' then count('range') end end,
                controlBindings={movement=function() return 0,0 end,actionDown=function() return false end}})
            Pause=require('game.world_pause')
            function sharedTick()
                update.update(.1)
                assert(counts.persist==1 and counts.world==1 and counts.cloud==1 and counts.audio==1)
                assert(runtime.player.x==100 and not runtime.player.moving and runtime.player.velocityX==0)
                assert(math.abs(runtime.npcActor.x-603.2)<1e-6 and counts.npc==1)
                assert(math.abs(runtime.saveData.passengers[1].x-203.8)<1e-6)
            end
        ''')

    def test_host_backpack_stops_only_local_input_and_shared_actors_tick_once(self):
        self.lua.execute("runtime.inventoryOpen=true; sharedTick(); assert(counts.interaction==0)")

    def test_unoccupied_stop_residents_do_not_tick_from_a_train_only_scene(self):
        self.lua.execute('''
            ui.remoteWorldActor=nil; runtime.inventoryOpen=true; update.update(.1)
            assert(counts.world==1 and counts.npc==0 and runtime.npcActor.x==600)
            assert(math.abs(runtime.saveData.passengers[1].x-203.8)<1e-6)
        ''')

    def test_each_host_overlay_preserves_shared_simulation(self):
        for setup in ["ui.escMenuOpen=true", "ui.optionsOpen=true", "runtime.exitPrompt={}",
                      "ui.localPlay={menuOpen=true}", "ui.localPlay={focused=false}", "ui.playerToolsOpen=true",
                      "maintenance.open=true", "runtime.travelConfirm=true"]:
            with self.subTest(setup=setup):
                self.setUp()
                self.lua.execute(setup + '; sharedTick()')

    def test_help_dialogue_holds_its_resident_while_other_shared_actors_continue(self):
        self.lua.execute('''
            runtime.helpDialogue={}; update.update(.1)
            assert(counts.world==1 and counts.npc==0 and resident.x==600)
            assert(runtime.saveData.passengers[1].x>200)
        ''')

    def test_offline_menus_retain_existing_world_pause(self):
        self.lua.execute('''
            runtime.session.networkMode='offline'; runtime.inventoryOpen=true; update.update(.1)
            assert(counts.world==0 and counts.npc==0 and runtime.player.x==100)
            assert(runtime.saveData.passengers[1].x==200)
            ui.escMenuOpen=true; update.update(.1); assert(counts.cloud==1 and counts.persist==2)
        ''')

    def test_offline_focus_cleanup_does_not_leave_a_network_modal_pause(self):
        self.lua.execute('''
            runtime.session.networkMode='offline'; ui.localPlay={focused=false,menuOpen=false}
            assert(not Pause.isPaused(runtime,ui,maintenance)); update.update(.1)
            assert(runtime.player.x==106 and counts.world==1 and counts.npc==1)
        ''')

    def test_unpaused_host_moves_and_shared_actors_update_once(self):
        self.lua.execute('''
            update.update(.1)
            assert(runtime.player.x==106 and counts.world==1 and counts.npc==1)
            assert(math.abs(resident.x-603.2)<1e-6 and counts.interaction==1)
            assert(math.abs(runtime.saveData.passengers[1].x-203.8)<1e-6)
        ''')

    def test_checkpoint_and_new_mid_frame_checkpoint_stop_all_world_writers(self):
        self.lua.execute('''
            runtime.session.checkpointPending=true; update.update(.1)
            assert(counts.world==0 and counts.npc==0 and runtime.player.x==100)
            assert(runtime.saveData.passengers[1].x==200)
            runtime.session.checkpointPending=false; barrier=true; update.update(.1)
            assert(counts.world==1 and counts.npc==0 and runtime.player.x==100)
            assert(runtime.saveData.passengers[1].x==200)
        ''')

    def test_encounter_started_during_world_update_ends_ordinary_simulation(self):
        self.lua.execute('''
            encounter=true; update.update(.1)
            assert(runtime.state=='battle' and counts.world==1 and counts.npc==0)
            assert(runtime.player.x==100 and runtime.saveData.passengers[1].x==200)
        ''')

    def test_host_first_aid_holds_patient_but_keeps_passengers_and_world_live(self):
        self.lua.execute('''
            runtime.firstAid={}; update.update(.1)
            assert(counts.aid==1 and counts.world==1 and counts.npc==0 and runtime.npcActor.x==600)
            assert(runtime.player.x==100 and math.abs(runtime.saveData.passengers[1].x-203.8)<1e-6)
            ui.escMenuOpen=true; update.update(.1); assert(counts.aid==1 and counts.world==2)
            assert(runtime.npcActor.wait==100)
            runtime.firstAid=nil; ui.escMenuOpen=false; runtime.inventoryOpen=true; update.update(.1)
            assert(counts.npc==1 and runtime.npcActor.x>600)
        ''')

    def test_guest_patient_hold_does_not_freeze_the_world_and_release_resumes_wandering(self):
        self.lua.execute('''
            held=true; ui.coopPatientBusy=function() return held end; runtime.inventoryOpen=true; update.update(.1)
            assert(counts.world==1 and counts.npc==0 and runtime.npcActor.x==600 and runtime.npcActor.wait==100)
            assert(not runtime.npcActor.targetX and not runtime.npcActor.moving and runtime.npcActor.velocityX==0)
            assert(runtime.saveData.passengers[1].x>200)
            held=false; update.update(.1); assert(counts.world==2 and counts.npc==1 and runtime.npcActor.x>600 and runtime.npcActor.targetX==700)
        ''')

    def test_personal_car_transition_keeps_shared_actors_live(self):
        self.lua.execute('''
            runtime.carTransition={}; carBusy=true; update.update(.1)
            assert(counts.world==1 and counts.npc==1 and runtime.player.x==100)
            assert(math.abs(runtime.saveData.passengers[1].x-203.8)<1e-6)
        ''')

    def test_host_scene_and_encounter_barriers_remain_shared(self):
        self.lua.execute('''
            local fields={travelTransition={},battle={},lastStand={capture=true},trainAmbush={phase='active'}}
            for key,value in pairs(fields) do
                runtime[key]=value; assert(Pause.isSimulationPaused(runtime,ui,maintenance)); runtime[key]=nil
            end
            for _,state in ipairs({'event','battle','ending','slots'}) do
                runtime.state=state; assert(Pause.isSimulationPaused(runtime,ui,maintenance))
            end
            runtime.state='game'; assert(not Pause.isSimulationPaused(runtime,ui,maintenance))
        ''')

    def test_host_private_range_uses_adapter_once_and_keeps_shared_world_live(self):
        self.lua.execute('''
            runtime.shootingRange={}; sharedTick()
            assert(counts.range==1 and Pause.isPaused(runtime,ui,maintenance))
            assert(not Pause.isSimulationPaused(runtime,ui,maintenance))
        ''')

    def test_offline_range_retains_original_simulation_and_modal_world_pause(self):
        self.lua.execute('''
            runtime.session.networkMode='offline'; runtime.shootingRange={}; update.update(.1)
            assert(counts.range==1 and counts.world==0 and counts.npc==0 and runtime.player.x==100)
            assert(Pause.isSimulationPaused(runtime,ui,maintenance))
        ''')


class SharedSewingWrapperTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            runtime={state='game',scene='train',session={networkMode='host'},saveData={stopped=true},animationClock=0}
            ui={}; counts={world=0,bench=0,persist=0,audio=0}; clock=0
            package.loaded['game.outfit_crafting_ui']={new=function(ctx)
                bench={open=false,isOpen=function(self) return self.open end,show=function(self) self.open=true end,
                    update=function() counts.bench=counts.bench+1 end,
                    close=function(self) self.open=false; ctx.onClose() end,suspend=function() end}
                return bench
            end}
            local function persist() counts.persist=counts.persist+1 end
            app={keyreleased=function() end,update=function(dt)
                counts.world=counts.world+1; runtime.animationClock=runtime.animationClock+dt
                assert(require('game.world_pause').isPaused(runtime,ui)); persist()
            end}
            require('game.outfit_workbench_host').wrap(app,{runtime=runtime,ui=ui,maintenanceSession={},
                commands={clock=function() return clock end,submit=function(name,args)
                    if failRenew and args.action=='renew' then return {ok=false,reason='lease_expired'} end
                    return {ok=true,result={ok=true,leaseId='l1'}} end},
                mobile={get=function() end,isEnabled=function() return false end},presentation={endPan=function() end},
                persistence={update=persist},audio={update=function() counts.audio=counts.audio+1 end}})
            assert(ui.openOutfitWorkbench() and runtime.outfitCraftingOpen)
        ''')

    def test_host_sewing_runs_world_and_clock_once(self):
        self.lua.execute('''
            app.update(.2)
            assert(counts.bench==1 and counts.world==1 and counts.persist==1 and counts.audio==0)
            assert(runtime.animationClock==.2)
        ''')

    def test_offline_sewing_retains_bounded_local_clock_and_modal_world_pause(self):
        self.lua.execute('''
            runtime.session.networkMode='offline'; app.update(.2)
            assert(counts.bench==1 and counts.world==0 and counts.persist==1 and counts.audio==1)
            assert(runtime.animationClock==.1)
        ''')

    def test_expired_host_sewing_lease_still_updates_shared_world(self):
        self.lua.execute('''
            clock=11; failRenew=true; app.update(.1)
            assert(not bench.open and not runtime.outfitCraftingOpen and runtime.inventoryOpen)
            assert(counts.bench==0 and counts.world==1 and counts.persist==1)
        ''')


if __name__ == '__main__':
    unittest.main()
