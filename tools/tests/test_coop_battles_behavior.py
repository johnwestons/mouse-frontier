"""Saved two-player tactical authority, resources, RNG and settlement."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class TacticalCommandTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=function() error('global battle RNG used') end}}
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema'); Entities=require('game.coop_entities')
            Authority=require('game.coop_authority'); Commands=require('game.coop_battles'); State=require('game.tactical_battle_state')
            Catalog=require('game.catalog'); Players=require('game.coop_players'); Items=require('game.item_instances')
            Actors=require('game.battle_actors'); Controller=require('game.battle_controller'); Rules=require('game.battle_rules')
            function setup(admit)
                data=F.campaign(2); assert(F.enroll(data)); data.scene='train'
                host=Players.forActor(data,'host'); guest=Players.forActor(data,'companion')
                Items.write(host,nil,{kind='equipment',index=2},'frontier-22-lever-rifle')
                Items.write(guest,nil,{kind='equipment',index=2},'frontier-22-lever-rifle')
                host.ammo['22lr']=20; guest.ammo['22lr']=9
                data.encounters['2']={rolled=true,hasMob=true,resolved=false,tier='easy',maxHP=100,mobFiles={Catalog.mobTiers.easy[1]}}
                assert(Entities.ensure(data)); state={screen='game',scene='train'}; writes=0; failSave=false
                service=Authority.new({campaign=data,sessionId='tactical',randomSeed=728431,
                    checkpoint=function(value) writes=writes+1; if failSave then return false end; saved=assert(Schema.copy(value)); return true end})
                Commands.install(service,{catalog=Catalog,actorState=function() return state end})
                if admit~=false then service:admit('companion',1) end
                writes=0
            end
            function run(id,name,args)
                local request,reason=service:prepareRequest(id,name,args or {})
                if not request then return {ok=false,reason=reason} end
                local reply=service:execute(id,id=='host' and 0 or 1,request)
                if reply.ok and reply.result.partyTransition then state.screen=reply.result.screen end
                return reply
            end
            function begin()
                return run('host','battle.begin',{encounterId=data.encounters[tostring(data.location)].entityId})
            end
            function ready()
                local b=data.tacticalBattle.battle; b.intro=nil; b.attackTimer=0; b.enemyDelay=0; b.projectile=nil
                for _,u in ipairs(b.units) do u.actionTimer=0; u.hitTimer=0; u.moveAnim=nil end
                return b
            end
            function args(extra)
                local s=data.tacticalBattle; local b=s.battle
                local a={encounterId=s.encounterId,turnRevision=s.revision,unitId=b.units[b.active].id}
                for key,value in pairs(extra or {}) do a[key]=value end
                return a
            end
            function action(id,name,extra) return run(id,name,args(extra)) end
            function atExit(b)
                for i,u in ipairs(Actors.units(b))do u.q,u.r=b.field.exitColumn,2+i*2 end
            end
            setup()
        ''')

    def test_begin_builds_two_owned_units_and_durable_reproducible_board(self):
        self.lua.execute('''
            local reply=begin(); assert(reply.ok and reply.durable,reply.reason)
            local b=assert(State.pending(data)); assert(#b.units==3 and b.units[1].actorId=='host' and b.units[2].actorId=='companion')
            assert(b.units[1].hp==host.health and b.units[2].hp==guest.health and b.units[2].file==guest.character)
            assert(saved.tacticalBattle.encounterId==data.encounters['2'].entityId and writes==1 and data.coop.randomState)
            local loaded=assert(Schema.migrate(saved)); local restored=assert(State.restore(loaded,Catalog))
            assert(restored.tiles[4][3]==b.tiles[4][3] and restored.encounter==loaded.encounters['2'])
            assert(restored.units[2].actorId=='companion' and loaded.coop.randomState==data.coop.randomState)
        ''')

    def test_offline_roster_has_one_player_and_guest_cannot_start(self):
        self.lua.execute('''
            assert(run('companion','battle.begin',{encounterId=data.encounters['2'].entityId}).reason=='host_only')
            setup(false); assert(begin().ok); assert(#data.tacticalBattle.battle.units==2)
            assert(data.tacticalBattle.battle.units[2].team=='enemy')
        ''')

    def test_guest_fire_wears_and_charges_only_guest_weapon_and_ammo(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready(); b.active=2; local u,e=b.units[2],b.units[3]
            e.q,e.r=2,5; b.tiles[2][5]=1; b.obstacles={}
            local weapon=guest.itemSlots.equipment[2]; local hostWeapon=host.itemSlots.equipment[2]
            local hp=host.health; local use=host.weaponProficiency.firearms; local guestUse=guest.weaponProficiency.firearms or 0
            local reply=action('companion','battle.attack',{weapon=weapon.id,targetId=e.id}); assert(reply.ok,reply.reason)
            assert(guest.ammo['22lr']==8 and host.ammo['22lr']==20 and weapon.durability==99 and hostWeapon.durability==100)
            assert(host.health==hp and host.weaponProficiency.firearms==use and guest.weaponProficiency.firearms==guestUse+1)
            assert(saved.players.companion.ammo['22lr']==8 and State.validate(saved))
        ''')

    def test_foreign_units_items_and_stale_turns_fail_without_costs(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready()
            assert(action('companion','battle.guard').reason=='not_your_turn')
            b.active=2; local a=args({weapon=host.itemSlots.equipment[2].id}); assert(run('companion','battle.attack',a).reason=='ownership')
            a=args(); a.unitId=b.units[1].id; assert(run('companion','battle.guard',a).reason=='not_your_turn')
            a=args(); a.turnRevision=99; assert(run('companion','battle.guard',a).reason=='stale_turn')
            assert(action('host','battle.guard').reason=='not_your_turn')
            assert(guest.ammo['22lr']==9 and host.ammo['22lr']==20 and data.tacticalBattle.revision==0 and writes==1)
        ''')

    def test_healing_consumes_own_pack_and_updates_own_health(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready(); b.active=2; b.units[2].hp=5; guest.health=5
            local medical; for name,e in pairs(Catalog.itemEffects) do if e.health and not e.potion and not Items.isGear(name) then medical=name; break end end
            assert(medical); guest.inventory[1]=medical; host.inventory[3]=medical
            local hostHealth=host.health
            local reply=action('companion','battle.item',{name=medical}); assert(reply.ok,reply.reason)
            assert(guest.inventory[1]==nil and host.inventory[3]==medical and guest.health>5 and host.health==hostHealth)
            assert(saved.players.companion.inventory[1]==nil)
        ''')

    def test_owned_potion_and_extra_actions_do_not_use_host_pending_potions(self):
        self.lua.execute('''
            local potion; for name,e in pairs(Catalog.itemEffects) do if e.potion and e.extraAttacks then potion=name; break end end
            assert(potion); guest.nextBattlePotions[potion]=true
            assert(begin().ok); local b=ready(); assert(b.units[2].extraAttacks and not b.units[1].extraAttacks)
            assert(next(guest.nextBattlePotions)==nil and next(host.nextBattlePotions)==nil)
            local original=guest.health; local u=b.units[2]; u.maxHP=guest.maxHealth+10; u.hp=guest.maxHealth+8
            Actors.syncHealth(data,u); assert(guest.health==guest.maxHealth and Schema.validate(data))
        ''')

    def test_exact_attack_replay_and_save_retry_never_charge_again(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready(); b.active=2; b.units[3].q,b.units[3].r=2,5; b.obstacles={}
            local request=assert(service:prepareRequest('companion','battle.attack',args({weapon=guest.itemSlots.equipment[2].id,targetId=b.units[3].id})))
            failSave=true; local reply=service:execute('companion',1,request); assert(reply.ok and reply.savePending,reply.reason)
            local hp=b.units[3].hp; local rng=data.coop.randomState; local revision=data.tacticalBattle.revision
            assert(service:execute('companion',1,request).ok and guest.ammo['22lr']==8 and b.units[3].hp==hp and data.tacticalBattle.revision==revision)
            assert(action('companion','battle.guard').reason=='save_pending')
            failSave=false; assert(service:retryCheckpoint()); assert(saved.players.companion.ammo['22lr']==8 and saved.coop.randomState==rng)
        ''')

    def test_target_selection_survives_reload_with_owned_instance(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready(); b.active=2
            local request=assert(service:prepareRequest('companion','battle.guard',args()))
            local id=guest.itemSlots.equipment[2].id; assert(action('companion','battle.attack',{weapon=id}).ok)
            local loaded=assert(Schema.migrate(saved)); b=assert(State.restore(loaded,Catalog))
            assert(b.phase=='target' and b.chosenItemId==id and b.chosenWeapon=='frontier-22-lever-rifle')
            assert(loaded.players.companion.ammo['22lr']==9)
        ''')

    def test_enemy_action_updates_target_owner_and_uses_host_rng(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready(); b.active=3
            b.units[3].q,b.units[3].r=2,5; b.units[3].aim=100; b.obstacles={}; b.units[2].armor=0
            local hostHP=host.health; local guestHP=guest.health; local rng=data.coop.randomState
            assert(action('companion','battle.enemyTurn').reason=='host_only')
            assert(action('host','battle.enemyTurn').ok)
            assert(host.health==hostHP and guest.health<guestHP and data.coop.randomState~=rng)
            assert(saved.players.companion.health==guest.health)
        ''')

    def test_victory_awards_both_players_once_and_guest_cannot_continue(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready(); b.units[3].hp=0;atExit(b)
            local hostXP=host.stats.xp; local guestXP=guest.stats.xp
            local request=assert(service:prepareRequest('host','battle.endTurn',args()))
            assert(service:execute('host',0,request).ok); local scrap=data.scrap; local rng=data.coop.randomState
            assert(b.finished=='win' and data.encounters['2'].resolved and host.stats.xp>hostXP and guest.stats.xp>guestXP)
            assert(service:execute('host',0,request).ok and data.scrap==scrap and data.coop.randomState==rng)
            local a={encounterId=data.tacticalBattle.encounterId,turnRevision=data.tacticalBattle.revision}
            assert(run('companion','battle.continue',a).reason=='host_only')
            assert(run('host','battle.continue',a).ok and not data.tacticalBattle and state.screen=='game')
            assert(saved.encounters['2'].resolved and not saved.tacticalBattle)
        ''')

    def test_party_loss_recovers_both_records_and_waits_for_host(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready(); for _,u in ipairs(b.units) do if u.team=='ally' then u.hp=0 end end
            local c={battle=b,saveData=data,BattleRules=Rules,writeSave=function() end}
            Controller.advance(c); assert(b.finished=='loss' and host.health==math.floor(host.maxHealth/2) and guest.health==math.floor(guest.maxHealth/2))
            assert(data.tacticalBattle and State.validate(data))
        ''')

    def test_disconnect_fallback_controls_only_the_saved_companion_turn(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready(); b.active=2
            local request=assert(service:prepareRequest('companion','battle.guard',args()))
            assert(action('host','battle.guard').reason=='not_your_turn'); service:disconnect('companion',1)
            assert(action('host','battle.guard').ok and b.units[2].guarding)
            assert(service:execute('companion',1,request).reason=='unbound_peer')
        ''')

    def test_owned_backpack_swap_is_durable_and_keeps_weapon_identity(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready(); b.active=2
            local Contract=require('game.coop_item_contract'); local weapon=guest.itemSlots.equipment[2]
            local a={source={kind='equipment',index=2},target={kind='inventory',index=4}}
            a.sourceItem=Contract.selection(guest,nil,a.source); a.targetItem=false
            assert(action('companion','battle.swap',a).ok)
            assert(not guest.equipment[2] and guest.itemSlots.inventory[4].id==weapon.id and host.equipment[2])
            assert(saved.players.companion.itemSlots.inventory[4].id==weapon.id and b.phase=='select')
            assert(action('companion','battle.attack',{weapon=weapon.id}).reason=='ownership')
            a.source,a.target=a.target,a.source; a.sourceItem={name=weapon.name,id=weapon.id}; a.targetItem=false
            assert(action('companion','battle.swap',a).ok and guest.itemSlots.equipment[2].id==weapon.id)
        ''')

    def test_battle_swap_rejects_shared_or_wearable_slots_foreign_and_stale_quotes(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready(); b.active=2
            local a={source={kind='equipment',index=2},target={kind='inventory',index=4},
                sourceItem={name=guest.equipment[2],id=host.itemSlots.equipment[2].id},targetItem=false}
            assert(action('companion','battle.swap',a).reason=='stale_item')
            a.sourceItem.id=guest.itemSlots.equipment[2].id; a.target={kind='wearable',slot='backpack'}
            assert(action('companion','battle.swap',a).reason=='invalid_slot')
            a.target={kind='chest',index=1}; assert(action('companion','battle.swap',a).reason=='invalid_slot')
            a.target={kind='inventory',index=4}; a.targetItem=nil
            assert(action('companion','battle.swap',a).reason=='invalid_slot')
            assert(guest.equipment[2] and not guest.inventory[4] and writes==1)
        ''')

    def test_entry_and_continue_save_failures_hold_the_same_board_and_result(self):
        self.lua.execute('''
            failSave=true; local start=begin(); assert(start.ok and start.savePending and data.tacticalBattle)
            local rng=data.coop.randomState; local b=ready()
            assert(begin().reason=='save_pending' and data.tacticalBattle.battle==b)
            failSave=false; assert(service:retryCheckpoint() and saved.coop.randomState==rng)
            b.units[3].hp=0;atExit(b);assert(action('host','battle.endTurn').ok and b.finished=='win')
            local xp=host.stats.xp; local a={encounterId=data.tacticalBattle.encounterId,turnRevision=data.tacticalBattle.revision}
            failSave=true; local r=run('host','battle.continue',a); assert(r.ok and r.savePending and not data.tacticalBattle)
            failSave=false; assert(service:retryCheckpoint() and not saved.tacticalBattle and host.stats.xp==xp)
            assert(saved.encounters['2'].resolved)
        ''')

    def test_boss_boards_restore_two_owners_and_passenger_weapon_instances(self):
        self.lua.execute('''
            for _,stop in ipairs({15,35,47}) do
                setup(); data.location=stop
                local tier=require('game.combat_balance').tierFor(stop)
                data.encounters[tostring(stop)]={rolled=true,hasMob=true,resolved=false,tier=tier,boss=true,mobFiles={Catalog.mobTiers[tier][1]}}
                data.passengers={{npc='guard-fox.png',weapon='frontier-short-sword'}}
                assert(Entities.ensure(data)); assert(Items.ensure(data)); assert(begin().ok)
                local loaded=assert(Schema.migrate(saved)); local b=assert(State.restore(loaded,Catalog))
                assert(#b.units==4 and b.units[1].actorId=='host' and b.units[2].actorId=='companion' and b.units[4].boss)
                assert(b.units[3].weaponOwnerId==loaded.passengers[1].entityId and b.units[3].weaponItemId==loaded.passengers[1].weaponInstance.id)
                assert(loaded.players.companion.ammo['22lr']==9 and loaded.ammo['22lr']==20)
            end
        ''')

    def test_companion_loot_potion_helps_one_shared_roll_then_clears_both_flags(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready(); b.units[3].hp=0;atExit(b)
            host.battlePotionLootChance=.15; guest.battlePotionLootChance=.9
            local Events=require('game.events'); local original=Events.grantBattleLoot; local chance; local calls=0
            Events.grantBattleLoot=function(d,...) chance=d.battlePotionLootChance; calls=calls+1; return original(d,...) end
            local request=assert(service:prepareRequest('host','battle.endTurn',args()))
            assert(service:execute('host',0,request).ok and chance==.9 and calls==1)
            assert(not host.battlePotionLootChance and not guest.battlePotionLootChance)
            assert(service:execute('host',0,request).ok and calls==1)
        ''')

    def test_long_battle_feed_remains_saveable_without_losing_the_latest_message(self):
        self.lua.execute('''
            assert(begin().ok); local b=ready()
            for i=1,5000 do Controller.message({battle=b},'Battle report '..i) end
            assert(#b.log==512 and b.log[512]=='Battle report 5000' and b.message==b.log[512])
            assert(Schema.validate(data) and Schema.migrate(assert(Schema.copy(data))))
        ''')

    def test_saved_model_rejects_dangling_duplicate_foreign_and_invalid_board_values(self):
        self.lua.execute('''
            assert(begin().ok)
            for _,edit in ipairs({
                function(d) d.tacticalBattle.encounterId='e999' end,
                function(d) d.tacticalBattle.battle.units[1].actorId='forged' end,
                function(d) d.tacticalBattle.battle.units[2].actorId='host' end,
                function(d) d.tacticalBattle.battle.units[3].actorId='companion' end,
                function(d) d.tacticalBattle.battle.units[2].hp=999 end,
                function(d) d.tacticalBattle.battle.tiles[4][3]=99 end,
                function(d) d.tacticalBattle.battle.active=99 end,
                function(d) d.tacticalBattle.revision=-1 end,
                function(d) d.tacticalBattle.battle.units[2].q=1; d.tacticalBattle.battle.units[2].r=3 end,
                function(d) d.tacticalBattle.battle.obstacles['2:3']={q=2,r=3,kind='forged'} end}) do
                local copy=assert(Schema.copy(data)); edit(copy); local ok,result=pcall(Schema.validate,copy); assert(ok and not result)
            end
        ''')


if __name__ == '__main__':
    unittest.main()
