"""Each player's resident access uses shared presence and its own position."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopResidentAccessTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=root..'/?.lua;'..package.path
            Fixtures=require('tools.tests.lua.coop_fixtures'); Catalog=require('game.catalog')
            Schema=require('game.save_schema'); Players=require('game.coop_players')
            Entities=require('game.coop_entities'); Items=require('game.item_instances')
            SceneNPCs=require('game.scene_npcs'); Recipients=require('game.coop_recipient_access')
            Merchants=require('game.coop_merchant_access'); Quests=require('game.coop_quest_access')
            Aid=require('game.coop_aid_access'); Trade=require('game.merchant_trade')
            data=Fixtures.campaign(4); assert(Fixtures.enroll(data)); data.scene='stop'; data.scrap=1000
            hostNpc='crow-merchant.png'; guestNpc='recipient.png'; patientNpc='medic-mouse.png'
            data.currentNPC=hostNpc; data.activeHouseDoor=1
            hostKey='resident:4:'..hostNpc; guestKey='resident:4:'..guestNpc; patientKey='resident:4:'..patientNpc
            layout={residentVersion=1,residentKeys={hostKey,guestKey,patientKey},
                npcOffers={[hostNpc]='trade',[guestNpc]='trade'},
                tradeStock={{item='coal-chunk',quantity=2,basePrice=3}},tradeBudget=40}
            data.stopLayouts['4']=layout
            data.npcStates[hostKey]={file=hostNpc,scene='stop',homeDoor=1,x=200,y=250}
            data.npcStates[guestKey]={file=guestNpc,scene='stop',homeDoor=2,x=600,y=250}
            data.npcStates[patientKey]={file=patientNpc,scene='house',homeDoor=2,x=650,y=300}
            states={host={screen='game',scene='stop',x=200,y=250,npc={id=guestNpc,x=200,y=250}},
                companion={screen='game',scene='stop',x=600,y=250,npc={id=hostNpc,x=600,y=250}}}
            for _,id in ipairs({'host','companion'}) do
                local actor=Players.forActor(data,id)
                for index=1,actor.inventoryCapacity do Items.write(actor,nil,{kind='inventory',index=index},nil) end
            end
            assert(Entities.ensure(data))
            service=require('game.coop_authority').new({campaign=data,sessionId='resident-access',randomSeed=4891})
            require('game.coop_trade').install(service,{catalog=Catalog,actorState=function(id) return states[id] end})
            require('game.coop_quests').install(service,{catalog=Catalog,actorState=function(id) return states[id] end})
            service:admit('companion',1)
            function run(id,name,args)
                local request,reason=service:prepareRequest(id,name,args)
                if not request then return {ok=false,reason=reason} end
                return service:execute(id,id=='host' and 0 or 1,request)
            end
        ''')

    def test_host_and_guest_find_nearby_residents_without_changing_shared_selection(self):
        self.lua.execute(r'''
            local Codec=require('game.net.codec')
            local before=assert(Codec.encode({layout=layout,states=data.npcStates}))
            SceneNPCs.prepare=function() error('access attempted scene preparation') end
            require('game.stops').ensure=function() error('access generated residents') end
            for id,npc in pairs({host=hostNpc,companion=guestNpc}) do
                local actor=Players.forActor(data,id)
                local recipient=assert(Recipients.nearest(actor,states[id]))
                assert(recipient.npc==npc and recipient.targetId==layout.entityId)
                assert(Quests.nearest(actor,states[id]).npc==npc)
                assert(Merchants.nearest(actor,states[id],Catalog).merchantId==npc)
                assert(Recipients.find(actor,layout.entityId,npc,states[id]))
            end
            assert(data.currentNPC==hostNpc and before==Codec.encode({layout=layout,states=data.npcStates}))
        ''')

    def test_authoritative_positions_and_roster_membership_reject_stale_pose_claims(self):
        self.lua.execute(r'''
            local state=states.companion
            state.npc={id=guestNpc,x=state.x,y=state.y}
            data.npcStates[guestKey].x=1000
            assert(not Recipients.find(data,layout.entityId,guestNpc,state))
            assert(not Merchants.find(data,layout.entityId,guestNpc,state,Catalog))
            data.npcStates[guestKey].x=600; data.npcStates[guestKey].scene='house'
            assert(not Recipients.find(data,layout.entityId,guestNpc,state))
            assert(not Merchants.find(data,layout.entityId,guestNpc,state,Catalog))
            data.npcStates[guestKey].scene='stop'; table.remove(layout.residentKeys,2)
            data.currentNPC=guestNpc
            assert(not Recipients.find(data,layout.entityId,guestNpc,state),'removed resident cannot use legacy selected-NPC fallback')
            assert(not Merchants.find(data,layout.entityId,guestNpc,state,Catalog))
        ''')

    def test_house_access_uses_the_current_door_and_rejects_stale_door_state(self):
        self.lua.execute(r'''
            data.scene='house'; local state=states.companion; state.scene='house'; state.x=650; state.y=300
            assert(not Recipients.find(data,layout.entityId,patientNpc,state),'another home must not expose its resident')
            data.activeHouseDoor=2
            assert(Recipients.find(data,layout.entityId,patientNpc,state))
            state.houseDoor=1
            assert(not Recipients.find(data,layout.entityId,patientNpc,state),'a stale actor door must be denied')
            state.houseDoor=2; state.x=900
            assert(not Recipients.find(data,layout.entityId,patientNpc,state),'door membership does not bypass distance')
        ''')

    def test_both_players_buy_from_their_present_merchant_and_guest_delivers_to_its_recipient(self):
        self.lua.execute(r'''
            local before=data.scrap
            for id,npc in pairs({host=hostNpc,companion=guestNpc}) do
                local result=run(id,'merchant.buy',{targetId=layout.entityId,merchantId=npc,index=1})
                assert(result.ok,result.reason)
                assert(Players.forActor(data,id).inventory[1]=='coal-chunk')
            end
            assert(layout.tradeStock[1].quantity==0 and data.scrap<before and data.currentNPC==hostNpc)
            local quest={origin=1,destination=4,recipient=guestNpc,complete=false}
            data.mailQuests[#data.mailQuests+1]=quest; assert(Entities.ensure(data))
            local result=run('companion','quest.deliver',{targetId=layout.entityId,npc=guestNpc,questId=quest.entityId})
            assert(result.ok and quest.complete and quest.completedBy=='companion',result.reason)
            assert(data.currentNPC==hostNpc,'guest assistance must not overwrite the host selection')
        ''')

    def test_patient_lookup_uses_present_resident_and_preserves_cleanup_after_departure(self):
        self.lua.execute(r'''
            data.scene='house'; data.activeHouseDoor=2
            local state=states.companion; state.scene='house'; state.x=650; state.y=300
            layout.helpRequests={[patientNpc]={kind='aid',accepted=true,sessionId='resident-aid'}}
            data.helpQuestSessions['resident-aid']={id='resident-aid',source='first-aid',state='accepted',npc=patientNpc,location=4}
            local actor=Players.forActor(data,'companion')
            assert(Aid.nearest(actor,state).npc==patientNpc)
            assert(Aid.patient(actor,state,layout.entityId,patientNpc))
            data.npcStates[patientKey].scene='stop'
            assert(not Aid.patient(actor,state,layout.entityId,patientNpc))
            assert(Aid.patient(actor,state,layout.entityId,patientNpc,true),'lease cleanup must still release an absent patient')
        ''')

    def test_guest_delivers_in_own_house_while_host_visits_another_house(self):
        self.lua.execute(r'''
            data.scene='house'; data.activeHouseDoor=1
            require('game.coop_presence').ensure(data)
            local guest=Players.forActor(data,'companion'); guest.activeHouseDoor=2
            states.host.scene='house'; states.host.houseDoor=1
            states.companion.scene='house'; states.companion.houseDoor=2
            states.companion.x=650; states.companion.y=300
            local quest={origin=1,destination=4,recipient=patientNpc,complete=false}
            data.mailQuests[#data.mailQuests+1]=quest; assert(Entities.ensure(data))
            assert(Recipients.nearest(guest,states.companion).npc==patientNpc)
            local args={targetId=layout.entityId,npc=patientNpc,questId=quest.entityId}
            assert(not run('host','quest.deliver',args).ok)
            local result=run('companion','quest.deliver',args)
            assert(result.ok and quest.complete and quest.completedBy=='companion',result.reason)
            assert(data.activeHouseDoor==1 and data.currentNPC==hostNpc and guest.activeHouseDoor==2)
        ''')


if __name__ == '__main__':
    unittest.main()
