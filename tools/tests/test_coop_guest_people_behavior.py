"""Read-only recipients, immutable gift selection and approved regular speech."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GuestPeopleTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema'); Catalog=require('game.catalog')
            Players=require('game.coop_players'); Entities=require('game.coop_entities'); Items=require('game.item_instances')
            Contract=require('game.coop_item_contract'); Access=require('game.coop_recipient_access')
            data=F.campaign(); assert(F.enroll(data)); data.scene='train'
            data.passengers={{npc='cook-mouse.png',carIndex=1,x=300,y=400,weapon='trail-slingshot'}}
            data.droppedItems={{name='mailbox-reward',mailbox=true,mailUnread=true,scene='train',carIndex=1,x=310,y=400,storage={'field-bandage-roll','frontier-short-sword'}}}
            data.players.companion.inventory[1]='food-ration'; assert(Entities.ensure(data)); assert(Items.ensure(data))
            copy=Schema.copy(data); recipient=copy.passengers[1]; chest=copy.droppedItems[1]
            runtime={saveData=Players.forActor(copy,'companion'),scene='train',state='game',player={x=300,y=400}}
            allowed=true; requests={}; network={}
            function network:submitCommand(name,args,epoch,expected)
                requests[#requests+1]={name=name,args=args,epoch=epoch,expected=expected}; return #requests
            end
            view={runtime=runtime,ui={},epoch=copy.coop.sceneEpoch,focused=true,inventory={},trade={},train={},objects={},
                controller={network=network},actionsAllowed=function() return allowed end,neutralize=function() end}
            panel=require('game.coop_guest_people').new(view,{catalog=Catalog,colors={}})
            love={keyboard={isDown=function() return false end}}
            function result(id,details,revision)
                network.lastCommandResult={requestId=id,ok=true,durable=true,details=details,revision=revision or copy.coop.revision}
            end
        ''')

    def test_home_fox_opens_talk_only_with_no_guest_story_or_history_writes(self):
        self.lua.execute('''
            local Home=require('game.home_stop'); local Fox=require('game.home_stop_fox')
            copy.scene='stop'; copy.location=1; copy.homeStop=Home.newState(); Home.layout(copy)
            local fox=Fox.ensure(copy); assert(Entities.ensure(copy))
            runtime.scene='stop'; runtime.player.x=fox.x; runtime.player.y=fox.y+30
            assert(panel:nearest().npc==Home.FOX and panel:open())
            assert(panel.homeFox and #requests==1 and requests[1].name=='npc.chatter')
            assert(#panel:offers()==0 and not copy.relationships[Home.FOX])
            result(1,{npc=Home.FOX,lineIndex=7,tier='New Face'}); panel:update()
            assert(panel.speech.text==Catalog.dialogueLines[7])
            assert(copy.homeStop.stage=='briefing' and not copy.homeStop.dialogueLine and not copy.relationships[Home.FOX])
            panel:keypressed('e'); assert(not runtime.peopleOpen)
            copy.homeStop.inOffice=true; assert(not panel:nearest() and not panel:open())
        ''')

    def test_confirmation_retains_exact_personal_gear_and_scopes_without_writes(self):
        self.lua.execute('''
            assert(panel:open() and panel:setMode('equip')); panel.drawn=panel:offers()
            local id=runtime.saveData.itemSlots.equipment[1].id; assert(panel:choose(1)); local q=panel.quote
            runtime.saveData.itemSlots.equipment[1].id='changed-test-instance'; copy.coop.revisions['player:companion']=9
            assert(panel.quote==q and #requests==0 and panel:confirm()); local req=requests[1]
            assert(req.name=='passenger.equip' and req.args.source.kind=='equipment' and req.args.sourceItem.id==id)
            assert(req.expected['player:companion']==0 and req.expected.relationships==0 and req.expected['entity:'..recipient.entityId]==0)
            assert(data.players.companion.itemSlots.equipment[1].id==id and recipient.weapon=='trail-slingshot')
            network.lastCommandResult={requestId=1,ok=false,reason='stale_item'}; panel:update()
            assert(not panel.pending and panel.notice:find('selected item changed',1,true))
        ''')

    def test_nearby_mailbox_choices_are_read_only_and_include_exact_container_item(self):
        self.lua.execute('''
            assert(panel:open()); local offers=panel:offers(); local found
            for _,offer in ipairs(offers) do if offer.args.containerId==chest.entityId and offer.args.source.index==2 then found=offer end end
            assert(found and found.args.sourceItem.id==Items.get(runtime.saveData,chest,{kind='chest',index=2}).id)
            assert(found.expected['entity:'..chest.entityId]==0 and found.expected['entity:'..recipient.entityId]==0)
            assert(chest.mailUnread and chest.storage[2]=='frontier-short-sword' and data.droppedItems[1].mailUnread)
            runtime.player.x=800; assert(#panel:offers()==0 and not panel:recipient())
            assert(chest.mailUnread and #requests==0)
        ''')

    def test_chatter_uses_exact_approved_line_and_changes_no_client_history(self):
        self.lua.execute('''
            assert(panel:open() and panel:talk()); local req=requests[1]
            assert(req.name=='passenger.chatter' and req.args.npc==recipient.npc and not req.args.line)
            assert(not req.expected['player:companion'] and req.expected.relationships==0)
            result(1,{npc=recipient.npc,lineIndex=13,tier='New Face'}); panel:update()
            assert(panel.speech.text==Catalog.dialogueLines[13] and panel.speech.npc==recipient.npc)
            assert(not copy.relationships[recipient.npc] and not recipient.relationshipTalks and not data.relationships[recipient.npc])
            panel:close(); assert(not runtime.peopleOpen and not panel.speech)
        ''')

    def test_pending_save_projection_and_scene_close_never_repeat_gift_or_show_obsolete_speech(self):
        self.lua.execute('''
            assert(panel:open() and panel:choose(1) and panel:confirm())
            network.lastCommandResult={requestId=1,ok=true,savePending=true}; panel:update(); assert(panel.pending)
            result(1,{item='food-ration',npc=recipient.npc,equipped=false,tier='Friend'},2); panel:update(); assert(panel.pending)
            copy.coop.revision=2; panel:update(); assert(not panel.pending and #requests==1 and runtime.saveData.inventory[1]=='food-ration')
            assert(panel:talk()); view.epoch=view.epoch+1; panel:update(); assert(not runtime.peopleOpen and panel.pending)
            result(2,{npc=recipient.npc,lineIndex=1,tier='Friend'}); panel:update(); assert(not panel.pending and not panel.speech and #requests==2)
        ''')

    def test_recipient_health_current_car_and_other_panels_guard_access(self):
        self.lua.execute('''
            for _,name in ipairs({'inventoryOpen','tradeOpen','trainUpgradeOpen','editMode'}) do
                runtime[name]=true; assert(not panel:open()); runtime[name]=false
            end
            view.ui.radioOpen=true; assert(not panel:open()); view.ui.radioOpen=false
            view.objects.pending={}; assert(not panel:open()); view.objects.pending=nil
            runtime.saveData.health=0; assert(not panel:nearest()); runtime.saveData.health=20
            runtime.saveData.activeCar=2; assert(not panel:nearest()); runtime.saveData.activeCar=1
            assert(panel:open()); view.controller.menuOpen=true; panel:update(); assert(not runtime.peopleOpen)
            view.controller.menuOpen=false; assert(panel:open()); view.focused=false; panel:update(); assert(not runtime.peopleOpen)
        ''')

    def test_resident_source_uses_host_selected_npc_and_cannot_equip_passenger_branch(self):
        self.lua.execute('''
            runtime.scene='house'; runtime.saveData.scene='house'; runtime.saveData.currentNPC='crow-merchant.png'
            runtime.saveData.stopLayouts['1']={}; assert(Entities.ensure(copy)); runtime.npcActor={x=300,y=400}
            assert(panel:open() and panel:recipient().kind=='resident' and not panel:setMode('equip') and panel:talk())
            assert(requests[1].name=='npc.chatter' and requests[1].args.targetId==copy.stopLayouts['1'].entityId)
            runtime.saveData.currentNPC='cook-mouse.png'; panel:update(); assert(not runtime.peopleOpen)
        ''')

    def test_public_gift_and_chatter_outcomes_strip_dialogue_and_owned_instances(self):
        self.lua.execute('''
            local R=require('game.net.item_results')
            local gift=R.project('npc.gift',{item='frontier-short-sword',npc=recipient.npc,equipped=true,status={name='Friend'},
                line='unapproved-result-text',itemId='g1',retiredItemId='g2',weaponInstance={id='g1'}})
            assert(gift.tier=='Friend' and gift.equipped and not gift.line and not gift.itemId and not gift.weaponInstance)
            assert(R.valid('npc.chatter',{npc=recipient.npc,lineIndex=1,tier='New Face'}))
            assert(not R.valid('npc.chatter',{npc=recipient.npc,lineIndex=129,tier='New Face'}))
            assert(not R.valid('passenger.equip',{item='food-ration',npc=recipient.npc,equipped=false,tier='Friend'}))
            assert(not R.valid('npc.chatter',{npc=recipient.npc,lineIndex=1,tier='New Face',line='text'}))
        ''')


if __name__ == '__main__':
    unittest.main()
