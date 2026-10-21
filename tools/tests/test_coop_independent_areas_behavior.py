"""Areas occupied only by a companion retain host-owned AI and hazards."""
import unittest
import test_coop_gifts_behavior as gifts

class IndependentAreaTests(unittest.TestCase):
    def setUp(self):
        gifts.CoopGiftsTests.setUp(self)
        self.lua.execute('''
            Areas=require('game.expedition_areas'); Presence=require('game.coop_presence')
            data.location=5; data.scene='train'; Presence.ensure(data)
            own=Players.forActor(data,'companion'); own.scene='expedition'; own.activeExpeditionArea=Areas.BADLANDS_SURFACE_ID
            Areas.ensure(own); remote={x=700,y=500}
            runtime={state='game',scene='train',saveData=data,player={x=200,y=250},animationClock=0,
                session={networkMode='host'},expeditionGraceTimer=999}
            ui={expeditionActors=function(view)
                assert(view.activeExpeditionArea==own.activeExpeditionArea)
                return {{id='companion',x=remote.x,y=remote.y}}
            end,relocateExpeditionCompanion=function(x,y) remote.x,remote.y=x,y; relocated=(relocated or 0)+1; return true end,
            roamingPressure=function(definition,target,areaId)
                contact={id=target.id,areaId=areaId,mob=definition.id}; return true
            end}
            exp=require('game.expedition_runtime').new({runtime=runtime,ui=ui,catalog=Catalog,areas=Areas,
                roamingMobs=require('game.roaming_mobs'),getIsWeapon=function() return function() return true end end,
                getBeginEncounter=function() return function() error('remote area started a host-local battle') end end,
                writeSave=function() savedCount=(savedCount or 0)+1 end,clampToStop=function(x,y) return x,y end,
                mobImages={},mobIdleImages={},mobWalkImages={},mobAttackImages={},mobHitImages={},mobDeathImages={},
                mobRangedImages={},width=960,height=720})
        ''')

    def test_remote_enemies_chase_and_contact_guest_without_host_in_area(self):
        self.lua.execute('''
            local mob=data.expeditions[own.activeExpeditionArea].mobs['surface-dust-beetle']
            remote.x,remote.y=mob.x,mob.y
            for i=1,40 do runtime.animationClock=i*.1; exp.updateRemote(.1,own,remote); if contact then break end end
            assert(contact and contact.id=='companion' and contact.areaId==own.activeExpeditionArea)
            assert(data.scene=='train' and runtime.scene=='train' and runtime.player.x==200 and runtime.player.y==250)
            local frame=exp.fieldState().transient[own.activeExpeditionArea]['surface-dust-beetle']
            assert(frame.targetId=='companion' and frame.state=='windup')
        ''')

    def test_flood_updates_guest_area_and_relocates_only_guest_to_safe_bank(self):
        self.lua.execute('''
            own.activeExpeditionArea=Areas.BADLANDS_BASIN_ID; own.players.companion.presence.revision=1; Areas.ensure(own)
            local environment=Areas.definition(own.activeExpeditionArea).environment
            local state=data.expeditions[own.activeExpeditionArea]; state.environmentClock=environment.floodAt-.01; state.environmentPhase='warning'
            local point=environment.floodZone.points[1]; remote.x,remote.y=point.x,point.y
            state.environmentPhase='flooded'; assert(Areas.isInFlood(own,own.activeExpeditionArea,remote.x,remote.y))
            state.environmentPhase='warning'; exp.updateRemote(.05,own,remote)
            assert(relocated==1 and state.environmentPhase=='flooded')
            assert(not Areas.isInFlood(own,own.activeExpeditionArea,remote.x,remote.y))
            assert(Areas.isWalkable(own,own.activeExpeditionArea,remote.x,remote.y))
            assert(runtime.player.x==200 and runtime.player.y==250 and data.scene=='train' and savedCount==1)
        ''')

    def test_same_area_is_not_simulated_twice_and_shared_pause_stops_remote_area(self):
        self.lua.execute('''
            own.activeExpeditionArea=Areas.BADLANDS_BASIN_ID; Areas.ensure(own)
            local state=data.expeditions[own.activeExpeditionArea]; state.environmentClock=0; local clock=state.environmentClock
            runtime.scene='expedition'; data.activeExpeditionArea=own.activeExpeditionArea
            exp.updateRemote(.5,own,remote); assert(state.environmentClock==clock)
            runtime.scene='train'; runtime.session.checkpointPending=true
            exp.updateRemote(.5,own,remote); assert(state.environmentClock==clock)
            runtime.session.checkpointPending=false; exp.updateRemote(.5,own,remote)
            assert(state.environmentClock>clock)
        ''')

    def test_client_interaction_queries_use_replica_without_initializing_host_state(self):
        self.lua.execute('''
            own.activeExpeditionArea=Areas.BADLANDS_BASIN_ID; Areas.ensure(own)
            local GameState=require('game.net.game_state'); local replica=GameState.replica()
            assert(replica:apply(assert(GameState.producer():capture(data,true))))
            local view=replica:actor('companion'); local area=Areas.current(view)
            local function snapshot()
                return assert(require('game.net.codec').encode(assert(require('game.net.state_records').encode(replica.data)),
                    {maxBytes=1048576,maxDepth=32,maxEntries=100000,maxStringBytes=4096}))
            end
            local before=snapshot()
            Areas.ensure=function() error('read-only query tried to initialize a replica') end
            Areas.state=function() error('read-only query tried to access mutable area state') end
            local point=area.interactions[1]
            assert(Areas.interaction(view,'expedition',{x=point.x,y=point.y},true))
            Areas.isInFlood(view,area.id,point.x,point.y,true)
            assert(snapshot()==before)
            view.expeditions[area.id]=nil
            assert(not Areas.interaction(view,'expedition',{x=point.x,y=point.y},true))
        ''')

if __name__=='__main__': unittest.main()
