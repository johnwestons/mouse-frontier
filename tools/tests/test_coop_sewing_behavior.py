"""Shared sewing uses host steps, conserved materials and a persistent owner."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopSewingTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Fixtures=require('tools.tests.lua.coop_fixtures'); Catalog=require('game.catalog')
            Players=require('game.coop_players'); Items=require('game.item_instances')
            Schema=require('game.save_schema'); Crafting=require('game.outfit_crafting')
            Definitions=require('game.outfit_catalog'); Authority=require('game.coop_authority')
            data=Fixtures.campaign(); assert(Fixtures.enroll(data)); data.stopped=true
            now=0
            states={host={screen='game',scene='train'},companion={screen='game',scene='train'}}
            actors={host=Players.forActor(data,'host'),companion=Players.forActor(data,'companion')}
            function install(campaign)
                local service=Authority.new({campaign=campaign,sessionId='sewing',clock=function() return now end})
                require('game.coop_activities').install(service,{catalog=Catalog,actorState=function(id) return states[id] end})
                service:admit('companion',1); return service
            end
            service=install(data)
            function request(actor,args) return assert(service:prepareRequest(actor,'outfit.craft',args)) end
            function execute(actor,req) return service:execute(actor,actor=='host' and 0 or 1,req) end
            function run(actor,action,lease,args)
                args=args or {}; args.action=action; args.leaseId=lease
                local req,reason=service:prepareRequest(actor,'outfit.craft',args)
                if not req then return {ok=false,reason=reason} end
                return execute(actor,req)
            end
            function acquire(actor) return assert(run(actor,'acquire').result).leaseId end
            function release(actor,lease)
                local req=assert(service:prepareRequest(actor,'activity.release',{leaseId=lease}))
                return execute(actor,req)
            end
            function materials(actor,recipe)
                local indexes={}; for index in pairs(actor.inventory) do indexes[#indexes+1]=index end
                for _,index in ipairs(indexes) do Items.write(actor,nil,{kind='inventory',index=index},nil) end
                local index=1
                for _,material in ipairs(recipe.materials) do for n=1,material.count do
                    Items.write(actor,nil,{kind='inventory',index=index},material.id); index=index+1
                end end
            end
            function finishWork(actor,lease)
                local count=0
                while not Crafting.project(data).complete do
                    count=count+1; assert(count<1000)
                    local stage=Crafting.stage(data); local result
                    if stage.kind=='point' then result=run(actor,'point',lease,{x=stage.currentPoint.x,y=stage.currentPoint.y})
                    else
                        assert(run(actor,'pullStart',lease).ok)
                        now=now+(stage.targetRange.min+stage.targetRange.max)/2/.24
                        result=run(actor,'pullRelease',lease)
                    end
                    assert(result.ok and result.result.correct)
                end
            end
        ''')

    def test_every_recipe_consumes_guest_materials_and_delivers_one_owned_item(self):
        self.lua.execute('''
            for _,recipe in ipairs(Definitions.recipes) do
                materials(actors.companion,recipe)
                local lease=acquire('companion')
                local started=run('companion','start',lease,{recipeId=recipe.id})
                assert(started.ok and started.result.ok and not next(actors.companion.inventory))
                assert(Crafting.project(data).ownerPlayerId=='companion' and actors.host.inventory[1]=='orange-rose-vase')
                finishWork('companion',lease)
                local req=request('companion',{action='collect',leaseId=lease})
                local done=execute('companion',req); assert(done.ok and done.result.ok and done.result.quality=='masterwork')
                local item=Items.get(actors.companion,nil,{kind='inventory',index=done.result.slot})
                assert(item.name==recipe.outputIds.masterwork and Items.validate(data))
                local nextId=data.itemIdentity.nextId
                assert(execute('companion',req).result.outputId==item.name and data.itemIdentity.nextId==nextId)
                assert(not run('companion','collect',lease).result.ok and data.itemIdentity.nextId==nextId)
                assert(release('companion',lease).ok)
            end
        ''')

    def test_host_can_finish_guest_work_after_disconnect_without_taking_the_reward(self):
        self.lua.execute('''
            local recipe=Definitions.recipes[1]; materials(actors.companion,recipe)
            local guest=acquire('companion'); assert(run('companion','start',guest,{recipeId=recipe.id}).result.ok)
            local stage=Crafting.stage(data)
            assert(run('companion','point',guest,{x=stage.currentPoint.x,y=stage.currentPoint.y}).result.correct)
            local progress=Crafting.project(data).correctActions
            service:disconnect('companion',1)
            local host=acquire('host'); assert(Crafting.project(data).correctActions==progress)
            finishWork('host',host)
            local done=run('host','collect',host)
            assert(done.result.ok and done.result.ownerPlayerId=='companion')
            assert(done.result.message:find("companion",1,true) and actors.host.inventory[1]=='orange-rose-vase')
            local saved=assert(Schema.migrate(data))
            assert(saved.players.companion.inventory[done.result.slot]==done.result.outputId)
            assert(saved.players.companion.itemSlots.inventory[done.result.slot].id==actors.companion.itemSlots.inventory[done.result.slot].id)
            assert(data.location==1 and data.scene=='train')
        ''')

    def test_legacy_project_belongs_to_host_and_paid_progress_survives_reload(self):
        self.lua.execute('''
            local recipe=Definitions.recipes[1]; materials(actors.host,recipe)
            assert(Crafting.start(actors.host,recipe.id).ok and not Crafting.project(data).ownerPlayerId)
            local lease=acquire('companion'); assert(Crafting.project(data).ownerPlayerId=='host')
            local saved=assert(Schema.migrate(data))
            local fresh=install(saved); assert(not next(fresh.activityState.resources))
            assert(saved.outfitCrafting.project.ownerPlayerId=='host' and not next(saved.inventory))
            finishWork('companion',lease)
            assert(run('companion','collect',lease).result.ownerPlayerId=='host')
            assert(next(actors.host.inventory) and not next(actors.companion.inventory))
        ''')

    def test_foreign_lease_contention_and_replayed_point_cannot_advance_twice(self):
        self.lua.execute('''
            local recipe=Definitions.recipes[1]; materials(actors.host,recipe)
            local lease=acquire('host'); assert(run('companion','acquire').reason=='activity_busy')
            assert(run('host','start',lease,{recipeId=recipe.id}).result.ok)
            local stage=Crafting.stage(data)
            assert(run('companion','point',lease,{x=stage.currentPoint.x,y=stage.currentPoint.y}).reason=='lease_owner')
            local req=request('host',{action='point',leaseId=lease,x=stage.currentPoint.x,y=stage.currentPoint.y})
            assert(execute('host',req).result.correct); local count=Crafting.project(data).correctActions
            assert(execute('host',req).result.correct and Crafting.project(data).correctActions==count)
            local changed=assert(Schema.copy(req)); changed.args.x=0
            assert(execute('host',changed).reason=='request_conflict' and Crafting.project(data).correctActions==count)
        ''')

    def test_forged_quality_owner_duration_and_output_are_rejected(self):
        self.lua.execute('''
            local lease=acquire('companion')
            for _,key in ipairs({'quality','score','ownerPlayerId','outputId','elapsed','value'}) do
                local args={}; args[key]=1
                assert(run('companion','collect',lease,args).reason=='invalid_args')
            end
            assert(not data.outfitCrafting.project)
            local recipe=Definitions.recipes[1]; materials(actors.companion,recipe)
            assert(run('companion','start',lease,{recipeId=recipe.id}).result.ok)
            assert(run('companion','pullRelease',lease).reason=='wrong_step')
            assert(run('companion','point',lease,{x=0/0,y=.5}).reason=='invalid_args')
            assert(Crafting.project(data).attempts==0)
        ''')

    def test_host_clock_scores_pulls_and_accessible_adjustments_are_bounded_steps(self):
        self.lua.execute('''
            local recipe=Definitions.recipes[1]; materials(actors.host,recipe)
            local lease=acquire('host'); assert(run('host','start',lease,{recipeId=recipe.id}).result.ok)
            while Crafting.stage(data).kind=='point' do
                local stage=Crafting.stage(data); assert(run('host','point',lease,{x=stage.currentPoint.x,y=stage.currentPoint.y}).result.correct)
            end
            assert(run('host','pullStart',lease).ok)
            assert(run('host','pullStart',lease).reason=='already_pulling')
            local early=run('host','pullRelease',lease)
            assert(early.ok and not early.result.correct and Crafting.project(data).mistakes==1)
            assert(run('host','adjust',lease,{direction=20}).reason=='invalid_args')
            assert(run('host','suspend',lease).ok)
            local target=Crafting.stage(data).targetRange
            local steps=math.floor(((target.min+target.max)/2)/.05+.5)
            for n=1,steps do assert(run('host','adjust',lease,{direction=1}).ok) end
            assert(run('host','pullRelease',lease).result.correct)
        ''')

    def test_full_owner_inventory_keeps_completed_project_and_never_uses_helpers_space(self):
        self.lua.execute('''
            local recipe=Definitions.recipes[1]; materials(actors.companion,recipe)
            local lease=acquire('host'); release('host',lease)
            lease=acquire('companion'); assert(run('companion','start',lease,{recipeId=recipe.id}).result.ok)
            finishWork('companion',lease); release('companion',lease); lease=acquire('host')
            for index=1,actors.companion.inventoryCapacity do Items.write(actors.companion,nil,{kind='inventory',index=index},'food-ration') end
            local nextId=data.itemIdentity.nextId
            local result=run('host','collect',lease)
            assert(result.ok and not result.result.ok and result.result.inventoryFull)
            assert(Crafting.project(data).complete and data.itemIdentity.nextId==nextId)
            Items.write(actors.companion,nil,{kind='inventory',index=3},nil)
            assert(run('host','collect',lease).result.slot==3 and actors.host.inventory[1]=='orange-rose-vase')
        ''')

    def test_rejected_or_interrupted_start_keeps_materials_and_missing_owner_blocks(self):
        self.lua.execute('''
            local recipe=Definitions.recipes[1]; local lease=acquire('host')
            assert(not run('host','start',lease,{recipeId=recipe.id}).result.ok)
            assert(not Crafting.project(data) and actors.host.inventory[1]=='orange-rose-vase')
            materials(actors.host,recipe)
            local original=Crafting.start
            Crafting.start=function(...) original(...); error('forced post-payment failure') end
            assert(run('host','start',lease,{recipeId=recipe.id}).reason=='handler_error')
            assert(not Crafting.project(data) and next(actors.host.inventory))
            Crafting.start=original; assert(run('host','start',lease,{recipeId=recipe.id}).result.ok)
            Crafting.project(data).ownerPlayerId='unknown'
            assert(run('host','collect',lease).reason=='project_unavailable')
        ''')

    def test_expired_or_scene_changed_session_preserves_paid_checkpoint(self):
        self.lua.execute('''
            local recipe=Definitions.recipes[1]; materials(actors.host,recipe)
            local lease=acquire('host'); assert(run('host','start',lease,{recipeId=recipe.id}).result.ok)
            now=31; assert(run('host','renew',lease).reason=='lease_expired')
            assert(Crafting.project(data).ownerPlayerId=='host' and not next(actors.host.inventory))
            lease=acquire('companion'); now=50; assert(run('companion','renew',lease).ok)
            now=65; assert(run('companion','renew',lease).ok)
            data.coop.sceneEpoch=data.coop.sceneEpoch+1
            assert(run('companion','renew',lease).reason=='lease_expired')
            assert(Crafting.project(data).recipeId==recipe.id)
        ''')


if __name__ == '__main__':
    unittest.main()
