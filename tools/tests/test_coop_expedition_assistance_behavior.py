"""Host-known survey/cache assistance, persistence, ownership and story boundaries."""
import unittest
import test_coop_battles_behavior as tactical


class ExpeditionAssistanceTests(unittest.TestCase):
    setUp = tactical.TacticalCommandTests.setUp

    def expedition(self):
        self.lua.execute('''
            setup(); Areas=require('game.expedition_areas'); Assist=require('game.coop_expedition_assistance')
            data.location=5; data.scene='expedition'; data.activeExpeditionArea=Areas.BADLANDS_BASIN_ID
            Areas.ensure(data); assert(Entities.ensure(data)); area=data.expeditions[data.activeExpeditionArea]
            function positionAt(interactionId)
                for _,interaction in ipairs(Areas.definition(data.activeExpeditionArea).interactions) do
                    if interaction.id==interactionId then return interaction.x,interaction.y end
                end
                error('missing fixture interaction '..interactionId)
            end
            local x,y=positionAt('north-cairn')
            states={host={screen='game',scene='expedition',x=x,y=y},companion={screen='game',scene='expedition',x=x,y=y}}
            service=Authority.new({campaign=data,sessionId='assist',checkpoint=function(value)
                writes=writes+1; if failSave then return false end; saved=assert(Schema.copy(value)); return true end})
            Assist.install(service,{catalog=Catalog,actorState=function(id) return states[id] end})
            require('game.coop_inventory').install(service,{catalog=Catalog,actorState=function(id) return states[id] end})
            service:admit('companion',1); writes=0
            function survey(id,marker) return run(id,'expedition.survey',{areaId=data.activeExpeditionArea,markerId=marker}) end
            function cache(id,chest) return run(id,'expedition.cache',{areaId=data.activeExpeditionArea,containerId=chest.entityId}) end
        ''')

    def test_guest_surveys_all_markers_without_scene_xp_or_story_change(self):
        self.expedition()
        self.lua.execute('''
            local epoch=data.coop.sceneEpoch; local xp=guest.stats.xp
            for i,markerId in ipairs({'north-cairn','wash-cairn','arch-cairn'}) do
                states.companion.x,states.companion.y=positionAt(markerId)
                local reply=survey('companion',markerId); assert(reply.ok and reply.durable,reply.reason)
                assert(reply.result.marked==i and reply.result.total==3 and reply.result.complete==(i==3))
            end
            assert(area.completed and area.gates.routeSurveyed and writes==3)
            assert(data.scene=='expedition' and data.activeExpeditionArea==Areas.BADLANDS_BASIN_ID and data.coop.sceneEpoch==epoch)
            assert(guest.stats.xp==xp and not data.tacticalBattle and Schema.validate(saved))
            local repeatResult=survey('companion','arch-cairn'); assert(repeatResult.ok and repeatResult.result.already)
        ''')

    def test_host_and_guest_share_scopes_and_reject_stale_concurrent_survey(self):
        self.expedition()
        self.lua.execute('''
            local request=assert(service:prepareRequest('companion','expedition.survey',{areaId=data.activeExpeditionArea,markerId='north-cairn'}))
            assert(survey('host','north-cairn').ok)
            assert(service:execute('companion',1,request).reason=='stale_revision' and writes==1)
            assert(survey('companion','north-cairn').result.already and area.markers['north-cairn'])
        ''')

    def test_invalid_claims_range_cover_activity_health_and_story_actions_are_denied(self):
        self.expedition()
        self.lua.execute('''
            assert(survey('companion','invented').reason=='invalid_marker')
            assert(run('companion','expedition.survey',{areaId=data.activeExpeditionArea,markerId='north-cairn',x=750}).reason=='invalid_args')
            assert(run('companion','expedition.survey',{areaId='wrong',markerId='north-cairn'}).reason=='assistance_unavailable')
            states.companion.x,states.companion.y=positionAt('western-stash'); assert(survey('companion','north-cairn').reason=='out_of_reach')
            states.companion.x,states.companion.y=positionAt('north-cairn')
            local reach=Areas.canReach; Areas.canReach=function() return false end
            assert(survey('companion','north-cairn').reason=='out_of_reach'); Areas.canReach=reach
            for _,key in ipairs({'traveling','changingCar','encounterActive','activityBlocked'}) do
                states.companion[key]=true; assert(survey('companion','north-cairn').reason=='assistance_unavailable'); states.companion[key]=nil
            end
            states.companion.movementReady=false; assert(survey('companion','north-cairn').reason=='assistance_unavailable'); states.companion.movementReady=nil
            guest.health=0; assert(survey('companion','north-cairn').reason=='assistance_unavailable'); guest.health=20
            states.companion.x=0/0; assert(survey('companion','north-cairn').reason=='assistance_unavailable')
            assert(run('companion','scene.expedition',{}).reason=='host_only')
            assert(run('companion','battle.begin',{}).reason=='host_only' and writes==0 and not area.markers['north-cairn'])
        ''')

    def test_cache_open_is_durable_even_when_empty_and_transfer_keeps_owned_instance(self):
        self.expedition()
        self.lua.execute('''
            states.companion.x,states.companion.y=positionAt('western-stash')
            local chest=area.chests['western-stash']; Items.write(host,chest,{kind='chest',index=1},'frontier-short-sword')
            local first=chest.storageInstances[1]; local hostItem=host.itemSlots.equipment[1].id
            assert(not chest.opened); local r=cache('companion',chest); assert(r.ok and r.durable,r.reason)
            assert(saved.expeditions[data.activeExpeditionArea].chests['western-stash'].opened and #chest.storage>0)
            local moved=run('companion','storage.transfer',{containerId=chest.entityId,source={kind='chest',index=1},sourceItem={name=first.name,id=first.id}})
            assert(moved.ok,moved.reason)
            local found=false; for _,item in pairs(guest.itemSlots.inventory) do if item.id==first.id then found=true end end
            assert(found and host.itemSlots.equipment[1].id==hostItem)
            chest.storage={}; chest.storageInstances={}; chest.opened=false
            assert(cache('companion',chest).ok and saved.expeditions[data.activeExpeditionArea].chests['western-stash'].opened)
            assert(cache('companion',area.chests['fossil-cache']).reason=='out_of_reach')
            assert(run('companion','expedition.cache',{areaId=data.activeExpeditionArea,containerId=area.entityId}).reason=='invalid_cache')
            data.location=6; data.activeExpeditionArea=Areas.DUNGEON_ID; Areas.ensure(data); assert(Entities.ensure(data))
            states.companion.x,states.companion.y=positionAt('boss-vault')
            local vault=data.expeditions[data.activeExpeditionArea].chests['boss-vault']
            assert(not cache('companion',vault).ok and not vault.opened)
            local walk,reach=Areas.isWalkable,Areas.canReach
            Areas.isWalkable=function() return true end; Areas.canReach=function() return true end
            assert(cache('companion',vault).reason=='cache_sealed' and not vault.opened)
            Areas.isWalkable,Areas.canReach=walk,reach
            data.expeditions[data.activeExpeditionArea].gates.bossDefeated=true
            assert(cache('companion',vault).ok and vault.opened)
        ''')

    def test_save_failure_replay_reconnect_and_restore_do_not_repeat_surveys(self):
        self.expedition()
        self.lua.execute('''
            local request=assert(service:prepareRequest('companion','expedition.survey',{areaId=data.activeExpeditionArea,markerId='north-cairn'}))
            failSave=true; local reply=service:execute('companion',1,request); assert(reply.ok and reply.savePending)
            local revision=data.coop.revision; assert(service:execute('companion',1,request).savePending and data.coop.revision==revision)
            failSave=false; assert(service:retryCheckpoint()); assert(service:execute('companion',1,request).durable)
            service:disconnect('companion',1); service:admit('companion',2)
            assert(area.markers['north-cairn'] and data.coop.revision==revision)
            local restored=assert(Schema.migrate(saved)); assert(restored.expeditions[data.activeExpeditionArea].markers['north-cairn'])
        ''')

    def test_nearest_and_public_results_are_read_only_and_bounded(self):
        self.expedition()
        self.lua.execute('''
            local copy=assert(Schema.copy(data)); local before=assert(require('game.net.codec').encode(copy.expeditions,{maxBytes=10000000,maxDepth=30,maxEntries=100000,maxStringBytes=100000}))
            local ensure,state=Areas.ensure,Areas.state
            Areas.ensure=function() error('read-only assistance normalized world') end
            Areas.state=function() error('read-only assistance lazily accessed state') end
            local spot=Assist.nearest(copy,states.companion); assert(spot.markerId=='north-cairn')
            local after=assert(require('game.net.codec').encode(copy.expeditions,{maxBytes=10000000,maxDepth=30,maxEntries=100000,maxStringBytes=100000})); assert(before==after)
            Areas.ensure,Areas.state=ensure,state
        ''')

    def test_production_host_adapter_presents_only_after_durable_retry_once(self):
        self.expedition()
        self.lua.execute('''
            local session=require('game.game_session').new(); session.saveData=data; session.scene='expedition'; session.screen='game'
            data.coop.randomState=728431
            local x,y=positionAt('western-stash')
            local runtime={saveData=data,state='game',scene='expedition',animationClock=0,player={x=x,y=y}}
            local presented=0; local adapter=require('game.coop_inventory_runtime').new({runtime=runtime,session=session,catalog=Catalog,
                checkpoint=function(value) if failSave then return false end; saved=assert(Schema.copy(value)); return true end,
                applyExpedition=function(result)
                    assert(result.containerId==area.chests['western-stash'].entityId)
                    assert(saved.expeditions[data.activeExpeditionArea].chests['western-stash'].opened)
                    presented=presented+1
                end})
            assert(adapter.authority()); failSave=true
            local r=adapter.submit('expedition.cache',{areaId=data.activeExpeditionArea,containerId=area.chests['western-stash'].entityId})
            assert(r.ok and r.savePending and presented==0,tostring(r.reason)..' presented='..presented..' pending='..tostring(r.savePending))
            assert(not adapter.retryCheckpoint() and presented==0)
            failSave=false; assert(adapter.retryCheckpoint() and presented==1)
            assert(adapter.retryCheckpoint() and presented==1)
        ''')
        self.expedition()
        self.lua.execute('''
            local r=survey('companion','north-cairn'); local Public=require('game.net.item_results'); local result=assert(Public.project('expedition.survey',r.result))
            assert(Public.valid('expedition.survey',result)); result.total=65; assert(not Public.valid('expedition.survey',result))
            result.total=3; result.complete=true; assert(not Public.valid('expedition.survey',result))
        ''')


if __name__ == '__main__':
    unittest.main()
