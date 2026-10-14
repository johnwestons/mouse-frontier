"""Accepted task views never roll rewards or consume the guest projection."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GuestQuestTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema'); Players=require('game.coop_players')
            Items=require('game.item_instances'); Catalog=require('game.catalog'); Entities=require('game.coop_entities')
            Help=require('game.stop_help_progression'); Quests=require('game.help_quest_session'); Progress=require('game.quest_progression')
            Access=require('game.coop_quest_access')
            data=F.campaign(4); assert(F.enroll(data)); data.scene='stop'; data.currentNPC='recipient.png'
            layout={}; data.stopLayouts['4']=layout
            request=Help.ensureRequest(layout,'recipient.png','item',4,data); request.accepted=true; Quests.accept(data,request.sessionId)
            actor=Players.forActor(data,'companion')
            for i=1,actor.inventoryCapacity do Items.write(actor,nil,{kind='inventory',index=i},nil) end
            Items.write(actor,nil,{kind='inventory',index=1},request.item); Items.write(actor,nil,{kind='inventory',index=3},request.item)
            data.mailQuests={{origin=1,destination=4,recipient='recipient.png',complete=false}}
            data.supplyQuests={{origin=1,destination=4,cargoKind='medicine',complete=false}}
            assert(Entities.ensure(data)); copy=Schema.copy(data); copy.itemIdentity=nil
            runtime={saveData=Players.forActor(copy,'companion'),scene='stop',state='game',player={x=140,y=100},npcActor={x=100,y=100}}
            allowed=true; requests={}; network={}
            function network:submitCommand(name,args,epoch,expected)
                requests[#requests+1]={name=name,args=args,epoch=epoch,expected=expected}; return #requests
            end
            view={runtime=runtime,ui={},epoch=copy.coop.sceneEpoch,focused=true,inventory={frame=function() end,button=function(_,_,x,y,w,h) return {x=x,y=y,w=w,h=h} end},
                trade={textBox=function() end},train={},objects={},controller={network=network},
                actionsAllowed=function() return allowed end,neutralize=function() end}
            people=require('game.coop_guest_people').new(view,{catalog=Catalog,colors={cream={}}}); panel=people.quests
            love={keyboard={isDown=function() return false end},graphics={setColor=function() end,rectangle=function() end}}
            require('game.ui_layout').scope=function(_,_,fn) return fn() end
            function equal(a,b)
                if type(a)~='table' then return a==b end; if type(b)~='table' then return false end
                for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
                for k in pairs(b) do if a[k]==nil then return false end end; return true
            end
            function open() assert(people:open()); assert(panel:open()); panel:draw() end
            function result(id,d,revision) network.lastCommandResult={requestId=id,ok=true,durable=true,details=d,revision=revision or copy.coop.revision} end
        ''')

    def test_read_only_offers_and_cargo_plans_do_not_normalize_consume_or_roll_rewards(self):
        self.lua.execute('''
            local before=Schema.copy(copy); local host=Schema.copy(data)
            Progress.rollReward=function() error('guest roll') end; Progress.consumeCargo=function() error('guest consumption') end
            Quests.get=function() error('guest normalizer') end; Help.completeItem=function() error('guest hand-in') end
            open(); assert(#panel.drawn==4 and panel.drawn[1].slot==1 and panel.drawn[2].slot==3)
            assert(panel.drawn[3].kind=='mail' and panel.drawn[3].available and not panel.drawn[4].available)
            assert(equal(before,copy) and equal(host,data) and #requests==0)
        ''')

    def test_exact_drawn_item_and_revision_survive_inventory_changes_until_host_validation(self):
        self.lua.execute('''
            open(); assert(panel:choose(2)); local quote=panel.quote
            runtime.saveData.inventory[3]='field-bandage-roll'; copy.coop.revisions['player:companion']=8
            assert(panel:confirm()); local r=requests[1]
            assert(r.args.source.index==3 and r.args.selected.name==quote.item and r.expected['player:companion']==0)
            assert(not r.expected['player:host'] and people.pending.quest and #requests==1)
            assert(not panel:confirm())
            network.lastCommandResult={requestId=1,ok=false,reason='stale_revision'}; people:update()
            assert(not people.pending and not panel.quote and panel.notice:find('Review',1,true))
            assert(not copy.stopLayouts['4'].helpRequests['recipient.png'].complete)
        ''')

    def test_delivery_scopes_do_not_depend_on_reward_roll_or_unprojected_cursor(self):
        self.lua.execute('''
            local own=runtime.saveData; for i=1,own.inventoryCapacity do own.inventory[i]='cowboy-hat' end
            copy.droppedItems={{name='supply-crate',scene='house',location=4,storage={},entityId='e50'},
                {name='supply-crate',scene='house',location=4,storage={},entityId='e51'}}
            copy.lootContainerCursor={['4']=1}
            local q=copy.mailQuests[1]; local expected=Access.expected(own,'companion','quest.deliver',q,copy.stopLayouts['4'].entityId,Catalog)
            assert(expected['entity:e51']==0 and expected['entity:e50']==nil and expected['player:host']==0 and expected['player:companion']==0)
            assert(expected.rng==0 and expected['world:rewardDelivery']==0 and not copy.coop.randomState)
        ''')

    def test_accepted_only_story_rejection_and_shortage_disable_controls_without_commands(self):
        self.lua.execute('''
            copy.stopLayouts['4'].helpRequests['recipient.png'].accepted=false; copy.mailQuests[1].storyHandIn=true
            open(); assert(#panel.drawn==1 and panel.drawn[1].kind=='medicine' and not panel.drawn[1].available)
            assert(not panel:choose(1) and #requests==0)
            runtime.saveData.health=0; assert(not panel:recipient()); runtime.saveData.health=25
            runtime.player.x=400; assert(not panel:recipient()); people:update(); assert(not panel.opened and not runtime.peopleOpen)
        ''')

    def test_completion_waits_for_save_and_projection_then_reports_only_actual_shared_rewards(self):
        self.lua.execute('''
            open(); assert(panel:choose(3) and panel:confirm())
            assert(not panel.notice:find('XP',1,true) and not panel.notice:find('scrap',1,true))
            network.lastCommandResult={requestId=1,ok=true,savePending=true,revision=5}; people:update()
            assert(people.pending and not panel.receipt)
            local d={completed=true,item='field-bandage-roll',delivery='backpack',coal=1,scrap=4,xp=6,levels=0,gained=1,total=1,recipients={host=6,companion=6}}
            copy.mailQuests[1].complete=true; result(1,d,5); people:update(); assert(people.pending)
            copy.coop.revision=5; people:update(); assert(not people.pending and not panel.quote and panel.receipt==d)
            assert(panel.notice:find('host +6 XP',1,true) and panel.notice:find('companion +6 XP',1,true) and #requests==1)
        ''')

    def test_close_focus_and_scene_change_clear_presentation_without_replaying_hand_in(self):
        self.lua.execute('''
            open(); panel:choose(1); panel:confirm(); view.focused=false; people:update()
            assert(not runtime.peopleOpen and not panel.opened and people.pending)
            result(1,{completed=true,item=request.item,gained=2,total=2}); people:update()
            assert(not people.pending and not panel.receipt and #requests==1)
            view.focused=true; open(); panel:choose(3); panel:confirm(); view.epoch=view.epoch+1; people:update()
            result(2,{completed=true,item='food-ration',delivery='backpack',coal=1,scrap=4,xp=6,levels=0,gained=1,total=1,recipients={host=6,companion=6}})
            people:update(); assert(not people.pending and not panel.opened and not panel.receipt and #requests==2)
        ''')

    def test_all_task_pages_and_confirmation_controls_retain_captured_cargo_names(self):
        self.lua.execute('''
            runtime.saveData.inventory[1]='field-bandage-roll'; runtime.saveData.inventory[2]='healing-salve'
            for i=2,9 do copy.mailQuests[i]={origin=1,destination=4,recipient='recipient.png',complete=false,entityId='e'..(100+i)} end
            open(); panel.page=2; panel:draw(); assert(panel.ui.quests_task1 and panel.drawn[9])
            panel.page=0; panel:draw(); local index
            for i,q in ipairs(panel.drawn) do if q.kind=='medicine' then index=i end end
            assert(panel:choose(index)); local name=panel.quote.cargo.items[1].name
            runtime.saveData.inventory[1]='cowboy-hat'; panel:draw()
            assert(panel.quote.cargo.items[1].name==name and #panel.quote.cargo.items==2 and not panel.notice)
        ''')

    def test_public_delivery_metadata_is_bounded_and_excludes_raw_reward_quest_and_random_state(self):
        self.lua.execute('''
            local R=require('game.net.item_results'); local Wire=require('game.net.commands'); local P=require('game.net.protocol')
            local value={completed=true,reward={item='field-bandage-roll',delivery='backpack',coalAdded=1,scrapAdded=4,xp=6,levels=0,minimumRarity='secret'},
                gained=1,total=1,recipients={host=6,companion=6},quest={secret=true},randomState=99,session={private=true}}
            local d=assert(R.project('quest.deliver',value)); assert(R.valid('quest.deliver',d) and not d.reward and not d.quest and not d.randomState)
            local msg=assert(Wire.outcome('quests',1,{ok=true,revision=2,durable=true,result=value},'quest.deliver'))
            assert(#assert(P.encode(msg,P.CONTROL))<=1200)
            d.recipients.stranger=6; assert(not R.valid('quest.deliver',d)); d.recipients.stranger=nil
            d.recipients.host=7; assert(not R.valid('quest.deliver',d)); d.recipients.host=6
            d.delivery='ammunition'; assert(not R.valid('quest.deliver',d)); d.amount=8; assert(R.valid('quest.deliver',d))
            assert(not R.valid('quest.help',{completed=true,item='food-ration',gained=2,total=2,session={}}))
        ''')


if __name__ == '__main__':
    unittest.main()
