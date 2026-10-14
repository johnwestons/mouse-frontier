"""Read-only sewing presentation, asynchronous host work and input cleanup."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GuestSewingTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema'); Players=require('game.coop_players')
            Items=require('game.item_instances'); Definitions=require('game.outfit_catalog'); Model=require('game.outfit_crafting')
            data=F.campaign(); assert(F.enroll(data)); data.scene='train'; data.stopped=true
            copy=Schema.copy(data); copy.itemIdentity=nil
            runtime={saveData=Players.forActor(copy,'companion'),scene='train',state='game'}
            requests={}; allowed=true; network={}
            function network:submitCommand(name,args,epoch,expected)
                requests[#requests+1]={name=name,args=args,epoch=epoch,expected=expected}; return #requests
            end
            view={runtime=runtime,ui={},epoch=copy.coop.sceneEpoch,elapsed=10,focused=true,
                controller={network=network},actionsAllowed=function() return allowed end,neutralize=function() end}
            panel=require('game.coop_guest_sewing').new(view,{})
            love={keyboard={isDown=function() return false end}}
            function equal(a,b)
                if type(a)~='table' then return a==b end; if type(b)~='table' then return false end
                for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
                for k in pairs(b) do if a[k]==nil then return false end end; return true
            end
            function details(action,overrides)
                local d={action=action,success=true,leaseId='l1',ownerPlayerId='companion',tension=0,pulling=false,expiresIn=30}
                for k,v in pairs(overrides or {}) do d[k]=v end; return d
            end
            function result(id,d,revision)
                network.lastCommandResult={requestId=id,ok=true,details=d,revision=revision or copy.coop.revision}
            end
            function redraw()
                panel.bench.draw=function(b)
                    local read=b.context.model; read.ensure(runtime.saveData); read.project(runtime.saveData)
                    read.status(runtime.saveData,Definitions.recipes[1].id); read.stage(runtime.saveData); read.quality(runtime.saveData)
                end
                panel:draw()
            end
            function acquire()
                assert(panel:open()); result(#requests,details('acquire')); panel:update(); redraw()
            end
            function project(stage,owner)
                local recipe=Definitions.recipes[1]
                copy.outfitCrafting={version=1,project={recipeId=recipe.id,ownerPlayerId=owner or 'companion',stageIndex=stage or 1,
                    pointIndex=1,correctActions=0,completedPoints=0,mistakes=0,attempts=0,complete=false}}
            end
            function tensionStage()
                for i,s in ipairs(Definitions.recipes[1].stages) do if s.kind=='tension' then project(i); return s end end
            end
        ''')

    def test_view_helpers_and_guest_input_never_normalize_or_consume_projection(self):
        self.lua.execute('''
            copy.outfitCrafting=nil; local before=Schema.copy(copy); local original=Schema.copy(data)
            acquire(); panel.bench:start()
            assert(requests[2].name=='outfit.craft' and requests[2].args.action=='start')
            assert(requests[2].args.recipeId==Definitions.recipes[1].id and not requests[2].args.ownerPlayerId)
            assert(requests[2].expected['player:companion']==0 and requests[2].expected.outfit==0)
            assert(not requests[2].expected['player:host'] and equal(copy,before) and equal(data,original))
            panel.bench:start(); assert(#requests==2)
        ''')

    def test_work_uses_the_drawn_revisions_and_host_point_outcome(self):
        self.lua.execute('''
            project(); acquire(); local before=Schema.copy(copy); copy.coop.revisions.outfit=8
            panel.bench:nextPoint(); local args=requests[2].args
            local stage=Model.view.stage(runtime.saveData)
            assert(args.x==stage.currentPoint.x and args.y==stage.currentPoint.y and not args.pointIndex)
            assert(requests[2].expected.outfit==0 and copy.outfitCrafting.project.attempts==0)
            network.lastCommandResult={requestId=2,ok=false,reason='stale_revision'}; panel:update()
            assert(not panel.pending and panel.lease=='l1' and not panel.bench.holding)
            assert(copy.outfitCrafting.project.attempts==0 and data.outfitCrafting.project==nil)
            assert(equal(copy.outfitCrafting,before.outfitCrafting))
        ''')

    def test_early_key_release_waits_for_pull_start_then_sends_no_client_timing(self):
        self.lua.execute('''
            tensionStage(); acquire(); assert(panel.bench:beginPull('space')); panel:keyreleased('space')
            assert(panel.releaseWanted and not panel.bench.holding and #requests==2)
            view.elapsed=10.2; result(2,details('pullStart',{pulling=true})); panel:update()
            assert(requests[3].args.action=='pullRelease' and requests[3].args.leaseId=='l1')
            assert(not requests[3].args.tension and not requests[3].args.elapsed and not requests[3].args.startedAt)
            assert(copy.outfitCrafting.project.attempts==0)
            result(3,details('pullRelease',{correct=false,changed=true,complete=false,stageComplete=false,tension=.01})); panel:update()
            assert(not panel.releaseWanted and panel.bench.tension==.01 and not panel.bench.holding)
        ''')

    def test_renewal_and_release_queue_preserve_host_tension(self):
        self.lua.execute('''
            tensionStage(); acquire(); panel.bench:beginPull('space'); result(2,details('pullStart',{pulling=true,tension=.2})); panel:update()
            view.elapsed=11; panel:update(); assert(panel.bench.tension>.43 and panel.bench.tension<.45)
            view.elapsed=21; panel:update(); assert(requests[3].args.action=='renew')
            panel:keyreleased('space'); assert(panel.releaseWanted and #requests==3)
            result(3,details('renew',{pulling=true,tension=.72})); panel:update()
            assert(requests[4].args.action=='pullRelease')
            assert(copy.outfitCrafting.project.mistakes==0)
        ''')

    def test_late_acquisition_cleanup_rate_retry_and_no_story_action(self):
        self.lua.execute('''
            assert(panel:open()); panel:suspend(); result(1,details('acquire')); panel:update()
            assert(requests[2].name=='activity.release' and not runtime.guestActivityOpen and not panel.opened)
            network.lastCommandResult={requestId=2,ok=false,reason='rate_limited'}; panel:update()
            view.elapsed=11; panel:update(); assert(requests[3].name=='activity.release')
            result(3,{released=true,leaseId='l1'}); panel:update(); assert(not panel:busy())
            assert(copy.scene=='train' and copy.coop.sceneEpoch==view.epoch and data.location==copy.location)
        ''')

    def test_collection_waits_for_save_and_projection_before_showing_receipt(self):
        self.lua.execute('''
            project(nil,'host'); acquire(); panel.bench:collect()
            assert(requests[2].expected['player:host']==0 and not requests[2].expected['player:companion'])
            network.lastCommandResult={requestId=2,ok=false,reason='save_pending',savePending=true}; panel:update()
            assert(panel.pending and not panel.bench.receipt and Model.view.project(runtime.saveData))
            result(2,details('collect',{changed=true,complete=true,quality='masterwork',score=100,
                outputId=Definitions.recipes[1].outputIds.masterwork,ownerPlayerId='host'}),3)
            panel:update(); assert(panel.pending and not panel.bench.receipt)
            copy.coop.revision=3; copy.outfitCrafting.project=nil; panel:update()
            assert(panel.bench.receipt and panel.pending.action=='renew')
            assert(panel.bench.context.subtitle()=='Completed upgrade / for the host' and panel.notice:find("host's",1,true))
            assert(not runtime.saveData.inventory[2])
        ''')

    def test_owner_backpack_full_keeps_project_and_lease(self):
        self.lua.execute('''
            project(nil,'host'); acquire(); panel.bench:collect()
            result(2,details('collect',{success=false,reason='inventory_full',inventoryFull=true,complete=true,changed=false,ownerPlayerId='host'})); panel:update()
            assert(Model.view.project(runtime.saveData) and not panel.bench.receipt and panel.lease=='l1')
            assert(panel.notice:find('remains on the bench',1,true))
        ''')

    def test_failed_save_barrier_reacquires_only_the_lease_without_replaying_payment(self):
        self.lua.execute('''
            acquire(); panel.bench:start()
            network.lastCommandResult={requestId=2,ok=true,savePending=true,details=details('start',{changed=true}),revision=1}; panel:update()
            project(); copy.coop.revision=1; result(2,details('start',{changed=true}),1); panel:update()
            assert(requests[3].args.action=='renew')
            network.lastCommandResult={requestId=3,ok=false,reason='lease_expired'}; panel:update()
            assert(requests[4].args.action=='acquire' and not requests[4].args.recipeId)
            result(4,details('acquire',{leaseId='l2'}),1); panel:update(); redraw()
            assert(panel.lease=='l2' and panel:ready() and Model.view.project(runtime.saveData).recipeId==Definitions.recipes[1].id)
            local starts=0; for _,r in ipairs(requests) do if r.args.action=='start' then starts=starts+1 end end
            assert(starts==1)
        ''')

    def test_focus_and_scene_cleanup_never_apply_an_old_project_reply(self):
        self.lua.execute('''
            tensionStage(); acquire(); panel.bench:beginPull('space'); view.focused=false; panel:update()
            result(2,details('pullStart',{pulling=true})); panel:update()
            assert(requests[3].name=='activity.release' and not panel.opened and not panel.bench.holding)
            result(3,{released=true,leaseId='l1'}); panel:update(); view.focused=true
            assert(panel:open()); view.epoch=view.epoch+1; result(#requests,details('acquire')); panel:update()
            assert(not panel.lease and not panel.opened and not panel.pending and not panel.bench.receipt)
        ''')

    def test_public_dto_excludes_project_private_clock_and_raw_messages(self):
        self.lua.execute('''
            local R=require('game.net.item_results')
            local value={ok=true,action='acquire',leaseId='l2',ownerPlayerId='host',tension=0,pulling=false,expiresIn=30,
                expiresAt=999999,project={private=true},message='private',startedAt=8}
            local dto=assert(R.project('outfit.craft',value)); assert(R.valid('outfit.craft',dto))
            assert(not dto.project and not dto.message and not dto.expiresAt and not dto.startedAt)
            dto.tension=0/0; assert(not R.valid('outfit.craft',dto)); dto.tension=2; assert(not R.valid('outfit.craft',dto))
            dto.tension=0; dto.ownerPlayerId='stranger'; assert(not R.valid('outfit.craft',dto))
        ''')

    def test_host_visual_tension_uses_the_authority_clock_when_updates_pause(self):
        self.lua.execute('''
            project(); tensionStage(); local now=100
            local b=require('game.outfit_crafting_ui').new({data=function() return runtime.saveData end,
                clock=function() return now end,command=function(action) return {ok=true,tension=.1} end})
            b.visible=true; b:beginPull('space'); now=102; b:update(0)
            assert(math.abs(b.tension-.58)<.000001); b:suspend(); assert(not b.holding and not b.pullAnchor)
        ''')

    def test_tool_rate_is_bounded_and_material_actions_keep_the_ordinary_budget(self):
        self.lua.execute('''
            local Rate=require('game.net.command_rate'); local link={}
            local work={command='outfit.craft',args={action='point'}}
            local start={command='outfit.craft',args={action='start'}}
            for _=1,4 do assert(Rate.allow(link,work,0) and Rate.allow(link,start,0)) end
            for _=1,100 do assert(not Rate.allow(link,work,0) and not Rate.allow(link,start,0)) end
            assert(Rate.allow(link,work,1/6) and not Rate.allow(link,start,1/6))
            assert(not Rate.allow(link,{command='outfit.craft',args={action='collect'}},1/6))
            assert(not Rate.allow(link,{command='train.depart',args={action='point'}},1/6))
            assert(Rate.allow(link,start,.5))
            assert(Rate.allow({},work,0)) -- a fresh connection gets only its own bounded burst
        ''')


if __name__ == '__main__':
    unittest.main()
