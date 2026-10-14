"""Real repair/combat sessions bind to owned item IDs, including duplicates."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class EquipmentSessionsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=function(a,b) return a or .5 end}}
            Catalog=require('game.catalog'); Items=require('game.item_instances')
            Inventory=require('game.inventory'); Loot=require('game.loot_progression')
            Players=require('game.coop_players'); Fixtures=require('tools.tests.lua.coop_fixtures')
            data=Fixtures.campaign(nil,{
                equipment={'frontier-short-sword','frontier-22-lever-rifle'},
                inventory={[1]='frontier-short-sword',[2]='frontier-22-lever-rifle'}})
            assert(Fixtures.enroll(data))
            data.ammo['22lr']=30; data.scrap=1000
            assert(Items.ensure(data))
            host=Players.forActor(data,'host'); guest=Players.forActor(data,'companion')
            function slot(kind,index) return {kind=kind,index=index} end
            function item(kind,index) return Items.get(host,nil,slot(kind,index)) end
        ''')

    def test_repair_one_copy_uses_its_condition_and_the_acting_players_parts(self):
        self.lua.execute('''
            local equipped=item('equipment',1); local spare=item('inventory',1)
            local friend=Items.get(guest,nil,slot('equipment',1))
            equipped.durability=71; spare.durability=9; friend.durability=12
            local part=Loot.repairPartFor(Catalog,spare.name)
            Inventory.setValue(host,nil,slot('inventory',3),part)
            local status=Loot.repairStatus(host,Catalog,spare.id)
            assert(status.major and status.hasPart and status.itemId==spare.id)
            local result=Loot.completeRepair(host,Catalog,spare.id,'perfect')
            assert(result.ok and spare.durability==100 and equipped.durability==71 and friend.durability==12)
            assert(host.inventory[3]==nil and data.scrap==1000-status.cost)
            assert(not Loot.completeRepair(host,Catalog,friend.id,'perfect').ok)
            assert(Items.validate(data))
        ''')

    def test_transferred_or_replaced_item_cannot_complete_old_repair_selection(self):
        self.lua.execute('''
            local selected=item('inventory',1); selected.durability=60
            local chest={name='supply-crate',storage={}}
            assert(Inventory.move(host,chest,slot('inventory',1),slot('chest',1),Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.wearableItems))
            assert(Inventory.move(guest,chest,slot('chest',1),slot('inventory',1),Catalog.weaponStats,Catalog.ammoPickupAmounts,Catalog.wearableItems))
            Inventory.setValue(host,nil,slot('inventory',1),selected.name)
            local result=Loot.completeRepair(host,Catalog,selected.id,'perfect')
            assert(not result.ok and result.reason=='ownership' and data.scrap==1000)
            assert(selected.durability==60 and item('inventory',1).id~=selected.id)
            assert(Loot.completeRepair(guest,Catalog,selected.id,'perfect').ok)
            assert(selected.durability==100 and Items.validate(data))
        ''')

    def test_first_person_sessions_distinguish_identical_guns_and_reject_stale_ownership(self):
        self.lua.execute('''
            local Shooting=require('game.first_person_shooting')
            local first=item('equipment',2); local second=item('inventory',2)
            local quest={}; local gun=Shooting.new(host,Catalog,quest,960,720)
            assert(gun.itemId==first.id)
            assert(Shooting.fire(gun,host,quest)); local firstMagazine=gun.magazine
            local options=Shooting.weaponOptions(host,Catalog); local other
            for _,option in ipairs(options) do if option.itemId==second.id then other=option end end
            assert(other); gun=Shooting.chooseWeapon(gun,other,host,Catalog,quest)
            assert(gun.itemId==second.id and quest.weaponSessions[first.id].magazine==firstMagazine)
            local reserve=host.ammo['22lr']; local loaded=gun.magazine
            Inventory.setValue(host,nil,slot('inventory',2),nil)
            Inventory.setValue(host,nil,slot('inventory',2),second.name)
            local fired,reason=Shooting.fire(gun,host,quest)
            assert(not fired and reason=='ownership' and gun.magazine==loaded and host.ammo['22lr']==reserve)
            assert(not Shooting.reload(gun,host,quest))
            local replacement=Shooting.new(host,Catalog,quest,960,720)
            assert(replacement.itemId~=second.id)
        ''')

    def test_broken_first_gun_does_not_hide_sound_duplicate_and_ammo_is_checked_live(self):
        self.lua.execute('''
            local Shooting=require('game.first_person_shooting')
            item('equipment',2).durability=0
            local second=item('inventory',2); second.durability=30
            local name,id=Shooting.playerWeapon(host,Catalog)
            assert(name==second.name and id==second.id)
            local quest={}; local gun=Shooting.new(host,Catalog,quest,960,720)
            local reserve=host.ammo['22lr']; second.durability=0
            local fired,reason=Shooting.fire(gun,host,quest)
            assert(not fired and reason=='broken' and host.ammo['22lr']==reserve)
            second.durability=30; host.ammo['22lr']=0
            fired,reason=Shooting.fire(gun,host,quest)
            assert(not fired and reason=='empty')
        ''')

    def test_range_rejects_replaced_weapon_after_course_has_started(self):
        self.lua.execute('''
            local Range=require('game.shooting_range')
            local spot={preferences={motion='stationary',material='paper'},highScores={}}
            local session=assert(Range.new(host,spot,Catalog))
            assert(#session.weapons==2 and session.itemId==item('equipment',2).id)
            assert(Range.keypressed(session,'return',host,Catalog)=='start')
            local selected=item('equipment',2); local reserve=host.ammo['22lr']
            Inventory.setValue(host,nil,slot('equipment',2),selected.name)
            assert(Range.keypressed(session,'space',host,Catalog)=='dry')
            assert(session.shots==0 and host.ammo['22lr']==reserve and not Range.reload(session,host,Catalog))
        ''')

    def test_tactical_player_and_passenger_wear_only_their_selected_instance(self):
        self.lua.execute('''
            local Battle=require('game.battle_controller')
            local Entities=require('game.coop_entities')
            data.passengers={{npc='medic-mouse.png',weapon='frontier-short-sword'}}
            assert(Entities.ensure(data)); assert(Items.ensure(data))
            local carried=data.passengers[1].weaponInstance; carried.durability=33
            local c={saveData=host,Catalog=Catalog,Util=require('game.util'),
                CombatBalance=require('game.combat_balance'),PlayerProgression=require('game.player_progression'),
                BattleRules=require('game.battle_rules'),TrainUpgradeBalance=require('game.train_upgrade_balance'),
                BattleGrid={generateObstacles=function() return {} end},BOARD_COLS=9,BOARD_ROWS=6,
                writeSave=function() end,playSfx=function() end,weaponSfx=function() return 'sword' end}
            local battle=Battle.begin(c,{mobFiles={'mouse-bandit.png'},maxHP=100})
            local player,passenger,enemy=battle.units[1],battle.units[2],battle.units[3]
            player.q,player.r=1,3; passenger.q,passenger.r=2,2; enemy.q,enemy.r=2,3
            local sword=item('equipment',1); local spare=item('inventory',1); local before=sword.durability
            local ok,why=Battle.resolve(c,player,enemy,sword.name,sword.id); assert(ok,tostring(why)..' '..tostring(battle.message))
            assert(sword.durability==before-1 and spare.durability==67 and carried.durability==33,
                'conditions '..sword.durability..' '..spare.durability..' '..carried.durability)
            ok,why=Battle.resolve(c,passenger,enemy,carried.name,carried.id); assert(ok,tostring(why)..' '..tostring(battle.message))
            assert(carried.durability==32 and sword.durability==before-1)
            local oldId=sword.id
            Inventory.setValue(host,nil,slot('equipment',1),sword.name)
            local valid,reason=Battle.resolve(c,player,enemy,sword.name,oldId)
            assert(not valid and reason=='ownership' and item('equipment',1).durability==100)
            assert(Items.validate(data))
        ''')

    def test_event_loss_and_reward_writers_retire_old_ids_and_create_fresh_gear(self):
        self.lua.execute('''
            local retired=item('inventory',1).id
            require('game.events').resolve(host,Catalog,{choices={{loseItem=true}}},1,
                require('game.combat_balance'),require('game.train_upgrade_balance'))
            assert(host.inventory[1]==nil and host.itemSlots.inventory[1]==nil)
            assert(require('game.quest_progression').storeRewardItem(host,Catalog,Inventory,'frontier-short-sword')=='backpack')
            local replacement=item('inventory',1)
            assert(replacement.id~=retired and replacement.durability==100)
            require('game.house').storeLoot(data,Catalog,'frontier-short-sword',1)
            local found
            for _,drop in ipairs(data.droppedItems) do
                if drop.scene=='house' and drop.storage then
                    for index,name in pairs(drop.storage) do if name=='frontier-short-sword' then
                        found=Items.get(host,drop,slot('chest',index)); break
                    end end
                end
            end
            assert(found and found.id~=replacement.id and found.id~=retired)
            assert(Items.validate(data))
        ''')

    def test_completed_crafting_allocates_one_new_wearable_for_the_acting_player(self):
        self.lua.execute('''
            local Crafting=require('game.outfit_crafting'); local Definitions=require('game.outfit_catalog')
            local recipe=Definitions.recipes[1]; local index=1
            for _,material in ipairs(recipe.materials) do
                for n=1,material.count do Inventory.setValue(guest,nil,slot('inventory',index),material.id); index=index+1 end
            end
            assert(Crafting.start(guest,recipe.id).ok)
            local guard=0
            while not Crafting.project(guest).complete do
                guard=guard+1; assert(guard<1000)
                local stage=Crafting.stage(guest)
                local action=stage.kind=='tension' and {kind='tension',value=(stage.targetRange.min+stage.targetRange.max)/2}
                    or {kind='point',x=stage.currentPoint.x,y=stage.currentPoint.y}
                assert(Crafting.act(guest,action).correct)
            end
            local result=Crafting.finish(guest); assert(result.ok)
            local output=Items.get(guest,nil,slot('inventory',result.slot))
            assert(output and output.name==result.outputId and output.durability==nil)
            local nextId=data.itemIdentity.nextId
            assert(not Crafting.finish(guest).ok and data.itemIdentity.nextId==nextId)
            assert(Items.validate(data) and host.inventory[1]=='frontier-short-sword')
        ''')

    def test_live_save_preparation_assigns_spawned_loot_once_and_rejects_corruption(self):
        self.lua.execute('''
            local chest={name='supply-crate',scene='train',storage={'frontier-short-sword'}}
            data.droppedItems[#data.droppedItems+1]=chest
            local session=require('game.game_session').new(); session.selectedSlot=1; session.saveData=data
            local scheduled=0; local copied
            local save={schedule=function(_,value) scheduled=scheduled+1; copied=assert(require('game.save_schema').copy(value)); return true end}
            assert(session:scheduleSave(save))
            local live=Items.get(host,chest,slot('chest',1))
            assert(live and Items.validate(data) and Items.validate(copied))
            local nextId=data.itemIdentity.nextId
            assert(session:scheduleSave(save) and data.itemIdentity.nextId==nextId)
            chest.storageInstances[1]=item('equipment',1)
            assert(not session:scheduleSave(save) and scheduled==2)
        ''')

    def test_default_migration_enrollment_and_corrupt_reload_preserve_ownership(self):
        self.lua.execute('''
            local Schema=require('game.save_schema')
            assert(data.itemIdentity and host.itemSlots and guest.itemSlots)
            local nextId=data.itemIdentity.nextId
            local saved=assert(Schema.migrate(data))
            assert(saved.itemIdentity.nextId==nextId)
            assert(saved.players.host.itemSlots.equipment[1].id==item('equipment',1).id)
            assert(saved.players.companion.itemSlots.equipment[1].id~=item('equipment',1).id)
            saved.players.host.itemSlots.equipment[1]=nil
            local loaded,reason=Schema.migrate(saved)
            assert(not loaded and reason=='missing item identity')
            assert(saved.itemIdentity.nextId==nextId and saved.players.host.itemSlots.equipment[1]==nil)
            local exhausted=Fixtures.campaign(); exhausted.itemIdentity.nextId=2147483647
            local enrolled,message=Fixtures.enroll(exhausted)
            assert(not enrolled and message=='item IDs exhausted' and not exhausted.players.companion)
            assert(exhausted.itemIdentity.nextId==2147483647 and Items.validate(exhausted))
        ''')

    def test_old_first_person_checkpoint_cannot_bind_a_same_named_replacement(self):
        self.lua.execute('''
            local Shooting=require('game.first_person_shooting')
            local first=item('equipment',2)
            local quest={}; local original=Shooting.new(host,Catalog,quest,960,720)
            original.magazine=1
            local valid=Shooting.new(host,Catalog,quest,960,720)
            assert(valid==original and valid.itemId==first.id and valid.magazine==1)
            original.itemId=nil -- a pre-ledger checkpoint is not proof of ownership
            local legacy=Shooting.new(host,Catalog,quest,960,720)
            assert(legacy~=original and legacy.itemId==first.id and legacy.magazine<=host.ammo['22lr'])
            Inventory.setValue(host,nil,slot('equipment',2),first.name)
            local current=Shooting.new(host,Catalog,quest,960,720)
            assert(current~=legacy and current.itemId~=first.id and host.ammo['22lr']==30)
        ''')

    def test_recruitment_moves_the_residents_weapon_instead_of_copying_it(self):
        self.lua.execute('''
            data.currentNPC='medic-mouse.png'
            local layout={npcWeapon='frontier-22-lever-rifle'}; data.stopLayouts['1']=layout
            assert(Items.ensure(data)); local resident=layout.npcWeaponInstance; resident.durability=23
            local runtime={saveData=data,scene='stop',state='game'}
            local context={runtime=runtime,car={x=100,y=100},inventory=Inventory,catalog=Catalog,
                lootProgression=Loot,questProgression=require('game.quest_progression'),
                npcRelationships=require('game.npc_relationships'),passengers=require('game.passengers'),util=require('game.util'),
                ensureStopLayout=function() return layout end,setupNPC=function() end,writeSave=function() end,
                beginEncounter=function() end,beginRequiredEvent=function() end,beginRandomEvent=function() end}
            for name in ('engineUpgrades progressionBalance combatBalance eventBalance trainUpgradeBalance stopHelpProgression '
                ..'helpQuestSession helpDialogueQuests firstAid battleRules maintenance house'):gmatch('%S+') do context[name]={} end
            require('game.journey_rules').new(context).acceptQuest('ride')
            assert(data.passengers[1].weaponInstance==resident and resident.durability==23)
            assert(layout.npcWeapon==nil and layout.npcWeaponInstance==nil)
            assert(Items.validate(data))
        ''')


if __name__ == '__main__':
    unittest.main()
