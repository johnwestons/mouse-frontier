"""Checked companion-contact prompts, owner decisions and saved/replicated waits."""
import unittest
import test_coop_battles_behavior as tactical


class RoamingEncounterTests(unittest.TestCase):
    setUp = tactical.TacticalCommandTests.setUp

    def pressure(self):
        self.lua.execute('''
            setup(); Areas=require('game.expedition_areas'); Pressure=require('game.coop_roaming_encounters')
            Pending=require('game.roaming_encounter_state'); Roaming=require('game.roaming_mobs')
            data.location=5; data.scene='expedition'; data.activeExpeditionArea=Areas.BADLANDS_SURFACE_ID; Areas.ensure(data)
            area=data.expeditions[data.activeExpeditionArea]; a=area.mobs['surface-dust-beetle']; z=area.mobs['surface-cactus-rat']
            for _,interaction in ipairs(Areas.current(data).interactions) do
                if interaction.id=='surface-cache' then hostSpot={x=interaction.x,y=interaction.y} end
            end
            assert(hostSpot); contactSpot={x=a.x,y=a.y}
            states={host={screen='game',scene='expedition',x=hostSpot.x,y=hostSpot.y},
                companion={screen='game',scene='expedition',x=contactSpot.x,y=contactSpot.y,movementReady=true}}
            host.playerX,host.playerY=states.host.x,states.host.y; guest.playerX,guest.playerY=states.companion.x,states.companion.y
            visual=Roaming.new(); visual.transient[data.activeExpeditionArea]={['surface-dust-beetle']={state='windup',timer=0,targetId='companion'}}
            local domain={catalog=Catalog,actorState=function(id) return states[id] end,fieldState=function() return visual end,
                trainSpawn=function() return 400,420 end,trainClamp=function(_,_,x,y) return x,y end}
            service=Authority.new({campaign=data,sessionId='pressure',randomSeed=728431,
                checkpoint=function(value) writes=writes+1; if failSave then return false end; saved=assert(Schema.copy(value)); return true end})
            Pressure.install(service,domain); Commands.install(service,domain); require('game.coop_scenes').install(service,domain)
            service:admit('companion',1); writes=0
            function raise(extra)
                local args={areaId=data.activeExpeditionArea,leadId=a.entityId}; for key,value in pairs(extra or {}) do args[key]=value end
                return run('host','roaming.pressure',args)
            end
            function entry() return {encounterId=a.entityId,enemyIds={a.entityId}} end
        ''')

    def test_contact_checkpoints_a_shared_wait_without_damage_rewards_or_scene_progress(self):
        self.pressure()
        self.lua.execute('''
            local epoch=data.coop.sceneEpoch; local hp=guest.health; local scrap=data.scrap
            local reply=raise(); assert(reply.ok and reply.durable,reply.reason)
            assert(data.roamingEncounter.actorId=='companion' and data.roamingEncounter.x==contactSpot.x
                and data.roamingEncounter.y==contactSpot.y and #data.roamingEncounter.enemyIds==1)
            assert(data.scene=='expedition' and data.coop.sceneEpoch==epoch and guest.health==hp and data.scrap==scrap and not data.tacticalBattle)
            assert(Pending.validate(saved) and Schema.validate(saved) and writes==1)
            local producer=require('game.net.game_state').producer(); local packet=assert(producer:capture(data,true))
            local replica=require('game.net.game_state').replica(); assert(replica:apply(packet))
            assert(replica.data.roamingEncounter.id==data.roamingEncounter.id)
            local paused=require('game.world_pause'); assert(paused.isSimulationPaused({state='game',saveData=data,session={networkMode='host'}},{}))
        ''')

    def test_host_engages_guest_roster_while_retaining_actual_distant_host_return_point(self):
        self.pressure()
        self.lua.execute('''
            assert((a.x-states.host.x)^2+(a.y-states.host.y)^2>330^2)
            assert(run('host','battle.begin',entry()).reason=='enemy_unavailable')
            assert(raise().ok); local reply=run('host','battle.begin',entry()); assert(reply.ok and reply.durable,reply.reason)
            local b=data.tacticalBattle.battle
            assert(not data.roamingEncounter and b.encounter.returnContext.x==hostSpot.x and b.encounter.returnContext.y==hostSpot.y)
            assert(b.units[1].actorId=='host' and b.units[2].actorId=='companion' and b.units[3].hp==a.hp)
            assert(saved.tacticalBattle and State.validate(saved) and Schema.validate(saved))
        ''')

    def test_guests_cannot_raise_engage_or_withdraw_and_actions_cannot_change_pending_world(self):
        self.pressure()
        self.lua.execute('''
            assert(run('companion','roaming.pressure',{areaId=data.activeExpeditionArea,leadId=a.entityId}).reason=='host_only')
            assert(raise().ok)
            assert(run('companion','battle.begin',entry()).reason=='host_only')
            assert(run('companion','scene.returnTrain',{}).reason=='host_only')
            assert(run('companion','inventory.swap',{}).reason=='encounter_pending')
            assert(run('host','roaming.attack',{}).reason=='encounter_pending')
            assert(run('host','scene.expedition',{}).reason=='encounter_pending')
            assert(data.roamingEncounter and not data.tacticalBattle and writes==1)
        ''')

    def test_invalid_target_timer_distance_line_of_sight_or_claims_never_create_prompt(self):
        self.pressure()
        self.lua.execute('''
            assert(raise({x=914}).reason=='invalid_args')
            local t=visual.transient[data.activeExpeditionArea]['surface-dust-beetle']
            t.targetId='host'; assert(raise().reason=='pressure_unavailable'); t.targetId='companion'
            t.timer=.1; assert(raise().reason=='pressure_unavailable'); t.timer=0
            states.companion.x,states.companion.y=hostSpot.x,hostSpot.y; assert(raise().reason=='pressure_unavailable')
            states.companion.x,states.companion.y=contactSpot.x,contactSpot.y; states.companion.movementReady=false
            assert(raise().reason=='pressure_unavailable'); states.companion.movementReady=true
            service:disconnect('companion',1); assert(raise().reason=='pressure_unavailable')
            assert(not data.roamingEncounter and writes==0)
        ''')

    def test_failed_checkpoint_blocks_choices_and_retry_preserves_one_prompt(self):
        self.pressure()
        self.lua.execute('''
            failSave=true; local request=assert(service:prepareRequest('host','roaming.pressure',{areaId=data.activeExpeditionArea,leadId=a.entityId}))
            local reply=service:execute('host',0,request); assert(reply.ok and reply.savePending and not reply.durable and service.pendingSave)
            local id=data.roamingEncounter.id; assert(run('host','battle.begin',entry()).reason=='save_pending')
            assert(service:execute('host',0,request).result.pressureId==id and writes==1)
            failSave=false; assert(service:retryCheckpoint()); assert(saved.roamingEncounter.id==id and writes==2)
            assert(run('host','battle.begin',entry()).ok and not data.roamingEncounter and writes==3)
        ''')

    def test_saved_wait_survives_disconnect_and_new_authority_then_host_can_withdraw(self):
        self.pressure()
        self.lua.execute('''
            assert(raise().ok); service:disconnect('companion',1)
            local loaded=assert(Schema.migrate(saved)); assert(Pending.validate(loaded))
            data=loaded; service=Authority.new({campaign=data,sessionId='resume',checkpoint=function(value) saved=Schema.copy(value); return true end})
            require('game.coop_scenes').install(service,{catalog=Catalog,actorState=function() return states.host end,
                trainSpawn=function() return 400,420 end,trainClamp=function(_,_,x,y) return x,y end})
            local epoch=data.coop.sceneEpoch; local hp=data.players.companion.health
            local reply=run('host','scene.returnTrain',{}); assert(reply.ok and reply.durable,reply.reason)
            assert(data.scene=='train' and not data.roamingEncounter and data.coop.sceneEpoch==epoch+1 and data.players.companion.health==hp)
            assert(saved.scene=='train' and Schema.validate(saved))
        ''')

    def test_malformed_checkpoint_and_changed_roster_cannot_restore_or_start(self):
        self.pressure()
        self.lua.execute('''
            assert(raise().ok); local invalid=assert(Schema.copy(saved)); invalid.roamingEncounter.actorId='host'
            assert(not Schema.validate(invalid))
            invalid=assert(Schema.copy(saved)); invalid.roamingEncounter.enemyIds={a.entityId,a.entityId}; assert(not Schema.validate(invalid))
            invalid=assert(Schema.copy(saved)); invalid.roamingEncounter.epoch=99; assert(not Schema.validate(invalid))
            invalid=assert(Schema.copy(saved)); invalid.roamingEncounter.x=0/0; assert(not Schema.validate(invalid))
            invalid=assert(Schema.copy(saved)); invalid.expeditions[data.activeExpeditionArea].mobs['surface-dust-beetle'].x='claimed'
            assert(not Schema.validate(invalid))
            invalid=assert(Schema.copy(saved)); invalid.expeditions[data.activeExpeditionArea].mobs['surface-dust-beetle'].hp='claimed'
            assert(not Schema.validate(invalid))
            local args=entry(); args.enemyIds={a.entityId,z.entityId}; assert(run('host','battle.begin',args).reason=='pressure_unavailable')
            assert(data.roamingEncounter and not data.tacticalBattle)
        ''')

    def test_saved_wait_can_be_engaged_offline_without_reviving_a_disconnected_companion_unit(self):
        self.pressure()
        self.lua.execute('''
            assert(raise().ok); data=assert(Schema.migrate(saved))
            service=Authority.new({campaign=data,sessionId='offline-resume',checkpoint=function(value) saved=Schema.copy(value); return true end})
            Commands.install(service,{catalog=Catalog,actorState=function() return states.host end})
            local reply=run('host','battle.begin',entry()); assert(reply.ok and reply.durable,reply.reason)
            assert(not data.roamingEncounter and #data.tacticalBattle.battle.units==2)
            assert(data.tacticalBattle.battle.units[1].actorId=='host' and data.tacticalBattle.battle.encounter.returnContext.x==hostSpot.x)
        ''')


if __name__ == '__main__':
    unittest.main()
