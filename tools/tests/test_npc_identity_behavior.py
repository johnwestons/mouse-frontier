"""Individual identities, named reservations, passenger continuity and replicas."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class NpcIdentityTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            Identity=require('game.npc_identity'); Targets=require('game.npc_targets')
            Schema=require('game.save_schema'); F=require('tools.tests.lua.coop_fixtures')
            Catalog=require('game.catalog'); Entities=require('game.coop_entities')
            Relationships=require('game.npc_relationships'); NPCs=require('game.scene_npcs')
            data=F.campaign(4,{scene='stop',npcRoster={'mail-mouse.png','tinker-fox.png','scout-frog.png'}})
            function person(file,stop,door) return Identity.ensure(data,file,stop or data.location,door or 1) end
            function reserve(kind,stop,preferred)
                local q={sender='mail-mouse.png',origin=4,destination=stop,cargoKind=kind,complete=false}
                if preferred then q.recipient=preferred end
                Targets.bind(data,q,function(a,b) return b and a or 1 end)
                local list=kind=='mail' and data.mailQuests or data.supplyQuests
                list[#list+1]=q; assert(Entities.ensure(data)); return q
            end
        ''')

    def test_reused_art_has_different_people_names_and_relationships(self):
        self.lua.execute('''
            local a=person('tinker-fox.png',4); local b=person('tinker-fox.png',8)
            assert(a.id~=b.id and a.name~=b.name and a.file==b.file)
            Relationships.recordHelp(data,a.id,3,'medicine',4)
            Relationships.recordGift(data,a.id,'water-bottle','water')
            assert(Relationships.status(data,a.id).points>0)
            assert(Relationships.status(data,b.id).points==0)
            data.location=8; Relationships.npcDialogue(data,'tinker-fox.png',Catalog.dialogueLines)
            assert(data.relationships[b.id].talks==1 and data.relationships[a.id].talks==0)
        ''')

    def test_full_journey_roster_has_unique_stable_names(self):
        self.lua.execute('''
            local seen={}
            for stop=1,50 do for index=1,6 do
                local p=person('resident-'..index..'.png',stop,(index-1)%5+1)
                assert(not seen[p.name:lower()]); seen[p.name:lower()]=true
                assert(person(p.file,stop).name==p.name)
            end end
            assert(Identity.validate(data))
            local loaded=assert(Schema.migrate(data))
            for id,p in pairs(data.npcIdentities) do assert(loaded.npcIdentities[id].name==p.name) end
        ''')

    def test_home_cast_names_are_fixed_and_dialogue_is_unchanged(self):
        self.lua.execute('''
            local Home=require('game.home_stop'); data.location=1; data.homeStop=Home.newState()
            Home.layout(data); local fox=require('game.home_stop_fox').ensure(data)
            assert(Identity.name(data,Home.CONDUCTOR)=='Silas Reed')
            assert(Identity.name(data,fox)=='Tobin Flint')
            local loaded=assert(Schema.migrate(data))
            assert(Identity.title(loaded,Home.CONDUCTOR)=='Silas Reed • Conductor')
            assert(#require('game.home_stop_dialogue')==6)
        ''')

    def test_future_mail_and_supply_targets_are_reserved_before_arrival(self):
        self.lua.execute('''
            local mail=reserve('mail',8,'tinker-fox.png'); local supplies=reserve('food',8)
            local name=Identity.name(data,mail.recipientId)
            assert(mail.senderId and mail.recipientId and supplies.recipientId==mail.recipientId)
            assert(data.stopLayouts['8'].npcOutside=='tinker-fox.png')
            local loaded=assert(Schema.migrate(data)); assert(Identity.name(loaded,mail.recipientId)==name)
            loaded.location=8; NPCs.prepare(loaded,Catalog,math.random)
            local actor=assert(NPCs.find(loaded,'tinker-fox.png','stop'))
            assert(actor.characterId==mail.recipientId and Identity.name(loaded,actor)==name)
            assert(Targets.matches(loaded,mail,actor) and Targets.matches(loaded,supplies,actor))
            assert(not Targets.matches(loaded,mail,'scout-frog.png'))
        ''')

    def test_different_recipients_at_one_destination_do_not_share_tasks(self):
        self.lua.execute('''
            local a=reserve('mail',8,'tinker-fox.png'); local b=reserve('food',8,'scout-frog.png')
            data.location=8; NPCs.prepare(data,Catalog,math.random)
            local fox=assert(NPCs.find(data,'tinker-fox.png','stop'))
            local frog
            for _,actor in pairs(data.npcStates) do if actor.characterId==b.recipientId then frog=actor end end
            assert(frog and frog.homeDoor==1)
            assert(a.recipientId~=b.recipientId)
            assert(Targets.matches(data,a,fox) and not Targets.matches(data,a,frog))
            assert(Targets.matches(data,b,frog) and not Targets.matches(data,b,fox))
        ''')

    def test_target_directions_follow_indoor_outdoor_occupancy_and_home_door(self):
        self.lua.execute('''
            local q=reserve('mail',8,'tinker-fox.png'); data.location=8
            NPCs.prepare(data,Catalog,math.random)
            local actor=assert(NPCs.find(data,'tinker-fox.png','stop'))
            actor.scene='house'; actor.homeDoor=2
            assert(Targets.directions(data,q)=='Inside home 2')
            assert(Targets.doorMarkers(data)[1]==2)
            actor.scene='stop'
            assert(Targets.directions(data,q)=='Outside by the station')
            assert(#Targets.doorMarkers(data)==0)
        ''')

    def test_legacy_missing_recipient_joins_existing_roster_without_resetting_residents(self):
        self.lua.execute('''
            NPCs.prepare(data,Catalog,math.random)
            local old=NPCs.list(data,'stop')[1]; local x,y=old.x,old.y
            old.routineClock=7.25
            local q=reserve('mail',4,'guard-fox.png')
            assert(data.stopLayouts['4'].residentVersion==nil)
            NPCs.prepare(data,Catalog,math.random)
            local added=assert(NPCs.find(data,'guard-fox.png','stop'))
            assert(added.characterId==q.recipientId and Targets.matches(data,q,added))
            assert(old.x==x and old.y==y and old.routineClock==7.25)
        ''')

    def test_journal_and_map_names_are_read_only_and_distinguish_same_stop_jobs(self):
        self.lua.execute('''
            local a=reserve('mail',8,'tinker-fox.png'); local b=reserve('water',8,'scout-frog.png')
            local before=assert(Schema.copy(data))
            local Panels=require('game.coop_guest_journey_panels')
            local rows=Panels.journal(data,'stop',nil,0).rows
            assert(#rows==2 and rows[1].objective~=rows[2].objective)
            for _,row in ipairs(rows) do
                assert(row.portrait and row.detail:find('FROM '))
                assert(row.objective:find(' at Stop 8.',1,true))
            end
            assert(rows[1].objective:find(Identity.name(data,a.recipientId),1,true))
            assert(rows[2].objective:find(Identity.name(data,b.recipientId),1,true))
            local UI=require('game.npc_identity_ui')
            data.location=8; assert(UI.model(data).delivery)
            assert(Panels.trail(data,0).questLine:find(Identity.name(data,a.recipientId),1,true))
            assert(require('game.net.codec').encode(before.npcIdentities)==require('game.net.codec').encode(data.npcIdentities))
        ''')

    def test_passengers_keep_origin_identity_and_separate_same_sprite_histories(self):
        self.lua.execute('''
            local a=person('tinker-fox.png',4); local b=person('tinker-fox.png',6)
            local one={npc=a.file,characterId=a.id,origin=4,destination=9}
            local two={npc=b.file,characterId=b.id,origin=6,destination=10}
            data.passengers={one,two}; data.scene='train'; Identity.board(data,one); Identity.board(data,two)
            Relationships.passengerDialogue(data,one,Catalog.dialogueLines)
            Relationships.recordGift(data,two,'water-bottle','water')
            assert(data.relationships[a.id].talks==1 and data.relationships[a.id].gifts==0)
            assert(data.relationships[b.id].gifts==1 and data.relationships[b.id].talks==0)
            assert(Identity.get(data,'tinker-fox.png')==nil,'ambiguous train sprite resolved to a random person')
            data.location=9; Identity.arrive(data,one); table.remove(data.passengers,1)
            local loaded=assert(Schema.migrate(data))
            assert(Identity.name(loaded,a.id)==a.name and loaded.npcIdentities[a.id].lastStop==9)
            assert(loaded.npcIdentities[a.id].status=='arrived' and loaded.passengers[1].characterId==b.id)
        ''')

    def test_legacy_migration_binds_accepted_tasks_without_repeating_rewards(self):
        self.lua.execute('''
            data.version=45; data.npcIdentities=nil
            data.stopLayouts['4']={npc='mail-mouse.png'}
            data.mailQuests={{sender='mail-mouse.png',recipient='tinker-fox.png',origin=4,destination=8,complete=false}}
            data.supplyQuests={{origin=4,destination=9,cargoKind='medicine',complete=false},
                {origin=2,destination=4,complete=true,rewardItem='water-bottle'}}
            local loaded=assert(Schema.migrate(data))
            assert(loaded.mailQuests[1].recipientId and loaded.mailQuests[1].senderId)
            assert(loaded.supplyQuests[1].recipientId and loaded.supplyQuests[2].complete)
            assert(loaded.supplyQuests[2].rewardItem=='water-bottle' and loaded.scrap==data.scrap)
            local again=assert(Schema.migrate(loaded))
            assert(again.mailQuests[1].recipientId==loaded.mailQuests[1].recipientId)
        ''')

    def test_actual_arrival_rewards_and_notices_belong_to_the_departing_person(self):
        self.lua.execute('''
            local a=person('tinker-fox.png',4); local b=person('tinker-fox.png',6)
            data.scene='train';data.location=8
            data.passengers={{npc=a.file,characterId=a.id,origin=4,destination=8},
                {npc=b.file,characterId=b.id,origin=6,destination=10}}
            assert(Entities.ensure(data))
            require('game.journey_arrivals').apply(data,Catalog,math.random,{'host'})
            assert(#data.passengers==1 and data.passengers[1].characterId==b.id)
            assert(data.npcIdentities[a.id].status=='arrived' and data.npcIdentities[a.id].lastStop==8)
            assert(data.arrivalNotice:find(a.name..' reached their stop:',1,true))
            assert(data.relationships[a.id].helpCount==1 and not data.relationships[b.id])
            local loaded=assert(Schema.migrate(data));assert(Identity.name(loaded,a.id)==a.name)
        ''')

    def test_legacy_friendship_is_never_cloned_to_every_reused_sprite(self):
        self.lua.execute('''
            data.version=45; data.npcIdentities=nil
            data.stopLayouts['4']={npc='tinker-fox.png'}; data.stopLayouts['8']={npc='tinker-fox.png'}
            data.relationships['tinker-fox.png']={gifts=3,goodwillEarned=4,lastHelpStop=4}
            local loaded=assert(Schema.migrate(data)); local id=Identity.residentId(4,'tinker-fox.png')
            assert(loaded.relationships[id].gifts==3)
            assert(Relationships.status(loaded,Identity.residentId(8,'tinker-fox.png')).points==0)
            local again=assert(Schema.migrate(loaded)); assert(again.relationships[id].gifts==3)
        ''')

    def test_invalid_duplicate_names_and_dangling_targets_fail_validation(self):
        self.lua.execute('''
            local a=person('tinker-fox.png',4); local b=person('scout-frog.png',4)
            b.name=a.name; assert(not Schema.validate(data)); b.name='Unique Critter'
            local q=reserve('mail',8); q.recipientId='missing'
            assert(not Schema.validate(data)); q.recipientId=Identity.residentId(8,q.recipient)
            assert(Schema.validate(data)); q.senderId='missing'; assert(not Schema.validate(data))
        ''')

    def test_replica_contains_identical_names_and_target_ids_without_allocation(self):
        self.lua.execute('''
            local q=reserve('mail',8,'tinker-fox.png'); assert(F.enroll(data))
            local State=require('game.net.game_state'); local producer=State.producer(); local replica=State.replica()
            local message,reason=producer:capture(data); assert(message,reason); assert(replica:apply(message))
            assert(Identity.name(replica.data,q.recipientId)==Identity.name(data,q.recipientId))
            assert(replica.data.mailQuests[1].recipientId==q.recipientId)
            local bytes=require('game.net.codec').encode(replica.data.npcIdentities)
            require('game.coop_guest_journey_panels').journal(replica.data,'stop',nil,0)
            assert(bytes==require('game.net.codec').encode(replica.data.npcIdentities))
        ''')

    def test_identity_card_render_does_not_add_preferences_to_a_replica(self):
        self.lua.execute('''
            local q=reserve('mail',8,'tinker-fox.png'); assert(F.enroll(data)); data.location=8
            local State=require('game.net.game_state');local replica=State.replica()
            assert(replica:apply(assert(State.producer():capture(data))))
            local d=replica.data;assert(d.accessibility==nil)
            local Codec=require('game.net.codec');local before=Codec.encode(d)
            local noop=function()end
            local font={getHeight=function()return 20 end,getLineHeight=function()return 1.08 end,
                getWidth=function(_,s)return #s*10 end,getWrap=function(_,s)return #s*10,{s}end}
            love.graphics={getDimensions=function()return 1280,720 end,getFont=function()return font end,
                setColor=noop,rectangle=noop,printf=noop,print=noop,setFont=noop}
            local card=assert(require('game.npc_identity_ui').draw({data=d,key='E'}))
            assert(card.id==q.recipientId and card.x>=960)
            assert(Codec.encode(d)==before,'identity card mutated the public replica')
        ''')


if __name__ == '__main__':
    unittest.main()
