"""Read-only workshop, immutable upgrade quotes and selected personal fuel."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GuestTrainTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema'); Players=require('game.coop_players')
            data=F.campaign(50); assert(F.enroll(data)); data.scrap=200; data.scene='train'
            data.players.companion.inventory[2]='coal-bucket'; data.players.companion.inventory[4]='coal-chunk'
            copy=Schema.copy(data); runtime={saveData=Players.forActor(copy,'companion'),scene='train',state='game',player={x=594,y=520}}
            allowed=true; requests={}; neutral=0; network={}
            function network:submitCommand(name,args,epoch,expected)
                requests[#requests+1]={name=name,args=args,epoch=epoch,expected=expected}; return #requests
            end
            view={runtime=runtime,ui={},epoch=data.coop.sceneEpoch,mobile={enabled=false},inventory={},trade={},
                controller={network=network},actionsAllowed=function() return allowed end,neutralize=function() neutral=neutral+1 end}
            panel=require('game.coop_guest_train').new(view,{catalog=require('game.catalog'),colors={}})
            love={keyboard={isDown=function() return false end}}
            function result(id,details,revision)
                network.lastCommandResult={requestId=id,ok=true,durable=true,revision=revision or copy.coop.revision,details=details}
            end
        ''')

    def test_workshop_confirmation_retains_price_tier_and_revision_without_writes(self):
        self.lua.execute('''
            assert(panel:open() and panel:choose('engine')); local q=panel.quote
            assert(q.args.quotedPrice==15 and q.args.quotedLevel==1 and #requests==0 and copy.scrap==200)
            copy.engineLevel=1; copy.scrap=180; copy.coop.revisions.train=1; panel:update()
            assert(panel.quote==q and panel:confirm()); local r=requests[1]
            assert(r.name=='train.engineUpgrade' and r.args.quotedLevel==1 and r.args.quotedPrice==15 and r.expected.train==0)
            assert(panel.pending and copy.engineLevel==1 and data.engineLevel==0 and data.scrap==200)
            network.lastCommandResult={requestId=1,ok=false,reason='quote_changed'}; panel:update()
            assert(not panel.pending and panel.notice:find('upgrade changed',1,true))
        ''')

    def test_fueling_selects_only_own_coal_and_declares_shared_capacity_scopes(self):
        self.lua.execute('''
            assert(panel:nearFire() and panel:fuel()); local r=requests[1]
            assert(r.name=='train.fuel' and r.args.source.index==2 and r.args.sourceItem.name=='coal-bucket')
            assert(r.expected['player:companion']==0 and r.expected.resources==0 and r.expected.train==0)
            assert(runtime.saveData.inventory[2]=='coal-bucket' and copy.resources.coal==10 and data.resources.coal==10)
            result(1,{item='coal-bucket',gained=2}); panel:update()
            assert(not panel.pending and panel.notice=='Coal +2. Used Coal Bucket.')
        ''')

    def test_fueling_is_not_available_in_another_car_scene_or_modal(self):
        self.lua.execute('''
            runtime.saveData.activeCar=2; assert(not panel:fuel()); runtime.saveData.activeCar=1
            runtime.scene='stop'; assert(not panel:fuel()); runtime.scene='train'
            runtime.player.x=900; assert(not panel:fuel()); runtime.player.x=594
            runtime.tradeOpen=true; assert(not panel:fuel() and not panel:open()); runtime.tradeOpen=false
            allowed=false; assert(not panel:fuel() and not panel:open()); assert(#requests==0)
        ''')

    def test_owned_locked_and_insufficient_scrap_quotes_are_not_offered(self):
        self.lua.execute('''
            assert(panel:open()); copy.location=1; assert(not panel:choose('coal-hauler') and not panel:choose('engine'))
            copy.location=50; copy.scrap=0; assert(not panel:choose('coal-hauler'))
            copy.scrap=200; copy.trainCars[2]='coal-hauler'; assert(not panel:choose('coal-hauler'))
            assert(panel:choose('storage')); assert(panel.quote.args.carId=='storage' and #requests==0)
            panel:keypressed('escape'); assert(not panel.quote and runtime.trainUpgradeOpen)
            panel:keypressed('escape'); assert(not runtime.trainUpgradeOpen and copy.scrap==200)
        ''')

    def test_pending_save_projection_and_scene_change_do_not_repeat_the_purchase(self):
        self.lua.execute('''
            assert(panel:open() and panel:choose('storage') and panel:confirm())
            network.lastCommandResult={requestId=1,ok=true,savePending=true,revision=copy.coop.revision}; panel:update()
            assert(panel.pending and not panel:choose('engine') and #requests==1)
            view.epoch=view.epoch+1; panel:update(); assert(not runtime.trainUpgradeOpen and panel.pending)
            result(1,{carId='storage',price=22},copy.coop.revision+1); panel:update(); assert(panel.pending)
            copy.coop.revision=copy.coop.revision+1; panel:update()
            assert(not panel.pending and panel.notice=='Storage added for 22 scrap.' and #requests==1)
        ''')

    def test_public_results_strip_domain_entry_and_status(self):
        self.lua.execute('''
            local R=require('game.net.item_results'); local W=require('game.net.commands')
            local r=assert(R.project('train.upgrade',{ok=true,carId='storage',price=22,entry={description='private'},status={owned=true}}))
            assert(not r.entry and not r.status and not r.ok and r.carId=='storage')
            assert(not R.valid('train.fuel',{item='coal-bucket',gained=4}))
            assert(not R.valid('train.fuel',{item='food-ration',gained=1}))
            assert(not R.valid('train.engineUpgrade',{level=1.5,price=15}))
            assert(W.outcome('train',1,{ok=true,durable=true,revision=2,result={item='coal-chunk',gained=1}},'train.fuel'))
        ''')


if __name__ == '__main__':
    unittest.main()
