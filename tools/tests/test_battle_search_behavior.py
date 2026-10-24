"""Durable ruin exploration rewards, reach, actor ownership and save retry."""
import unittest
from tools.tests import test_coop_battles_behavior as fixtures


class RuinSearchTests(unittest.TestCase):
    def setUp(self):
        fixture = fixtures.TacticalCommandTests(); fixture.setUp(); self.lua = fixture.lua
        self.lua.execute('''
            Search=require('game.battle_search');Fog=require('game.battle_fog');Field=require('game.battle_field')
            function near(id,actorIndex)
                local b=ready(); b.active=actorIndex or 1; local p=Search.list(b)[id]
                local u=b.units[b.active];u.q,u.r=p.q,p.r
                b.phase='action';b.moveUsed=true;Fog.update(b)
                return b,u,p
            end
            function emptyPack(actor)
                for i=1,actor.inventoryCapacity do Items.write(actor,nil,{kind='inventory',index=i},nil)end
            end
        ''')

    def test_all_houses_have_reachable_interior_caches_without_changing_routes(self):
        self.lua.execute('''
            for seed=1,30 do
                local f,t,v,o=Field.generate(seed,1,'hard');local b={field=f}
                local sites=require('game.battle_sites').list(f);assert(#Search.list(b)==12)
                for _,p in ipairs(Search.list(b))do
                    local s=sites[p.id]
                    assert(p.q>s.q and p.q<s.q+s.w-1 and p.r>s.r and p.r<s.r+s.d-1)
                    assert(not o[p.q..':'..p.r]and Field.cellHeight(f,p.q,p.r)==.125)
                end
                assert(Field.connectedCount(f,o)>=2400)
            end
        ''')

    def test_search_after_moving_grants_personal_supplies_shared_scrap_and_ends_turn(self):
        self.lua.execute('''
            assert(begin().ok);emptyPack(host);local b,u=near(1);u.extraAttacks=2
            local scrap=data.scrap;local revision=data.tacticalBattle.revision
            local reply=action('host','battle.search',{cacheId=1});assert(reply.ok and reply.durable,reply.reason)
            local r=Search.receipt(data,b,1);assert(r and r.actorId=='host'and r.item and r.delivery=='inventory')
            assert(host.inventory[1]==r.item and Catalog.itemEffects[r.item].food)
            assert(data.scrap==scrap+r.scrap and b.active~=1 and data.tacticalBattle.revision==revision+1)
            assert(b.message:find('Ruin searched:',1,true)and Schema.validate(saved))
            assert(saved.encounters['2'].ruinCaches['1'].item==r.item)
        ''')

    def test_companion_ammo_is_owned_and_replication_includes_shared_claim(self):
        self.lua.execute('''
            assert(begin().ok);local b=near(4,2);local before=guest.ammo['22lr'];local h=host.ammo['22lr']
            local Net=require('game.net.game_state');local p=Net.producer();local r=Net.replica()
            assert(r:apply(assert(p:capture(data,true))))
            local reply=action('companion','battle.search',{cacheId=4});assert(reply.ok,reply.reason)
            local receipt=Search.receipt(data,b,4);assert(receipt.actorId=='companion'and receipt.ammo=='22lr')
            assert(guest.ammo['22lr']==before+receipt.amount and host.ammo['22lr']==h)
            assert(r:apply(assert(p:capture(data,false))))
            assert(Search.receipt(r.data,r.data.tacticalBattle.battle,4).actorId=='companion')
            assert(r.data.players.companion.ammo['22lr']==guest.ammo['22lr'])
        ''')

    def test_invalid_hidden_foreign_busy_and_wall_blocked_searches_have_no_cost(self):
        self.lua.execute('''
            assert(begin().ok);local b=ready();local revision=data.tacticalBattle.revision
            local rng=data.coop.randomState;local scrap=data.scrap;local w=writes
            assert(action('host','battle.search',{cacheId=1}).reason=='cache_out_of_reach')
            for _,id in ipairs({0,13,1.5,'1'})do assert(not action('host','battle.search',{cacheId=id}).ok)end
            assert(not action('host','battle.search',{}).ok)
            local _,u,p=near(1);assert(action('companion','battle.search',{cacheId=1}).reason=='not_your_turn')
            b.intro={};assert(action('host','battle.search',{cacheId=1}).reason=='battle_busy');b.intro=nil
            u.q=p.q-1;b.obstacles[p.q..':'..p.r]={q=p.q,r=p.r,kind='ruin-wall-x'}
            -- The target cover is discoverable; an intervening solid wall still blocks reach at distance two.
            u.q=p.q-2;assert(not action('host','battle.search',{cacheId=1}).ok)
            assert(data.scrap==scrap and data.coop.randomState==rng and writes==w and data.tacticalBattle.revision==revision)
            assert(not data.encounters['2'].ruinCaches)
        ''')

    def test_exact_replay_failed_save_and_reload_never_grant_twice(self):
        self.lua.execute('''
            assert(begin().ok);emptyPack(guest);local b=near(2,2)
            local request=assert(service:prepareRequest('companion','battle.search',args({cacheId=2})))
            failSave=true;local reply=service:execute('companion',1,request);assert(reply.ok and reply.savePending,reply.reason)
            local scrap=data.scrap;local rng=data.coop.randomState;local revision=data.tacticalBattle.revision
            assert(service:execute('companion',1,request).ok)
            assert(data.scrap==scrap and data.coop.randomState==rng and data.tacticalBattle.revision==revision)
            assert(action('host','battle.endTurn').reason=='save_pending')
            failSave=false;assert(service:retryCheckpoint());local loaded=assert(Schema.migrate(saved))
            local restored=assert(State.restore(loaded,Catalog));local u=restored.units[2]
            local r=Search.receipt(loaded,restored,2);assert(r and loaded.players.companion.inventory[1]==r.item)
            local ok,reason=Search.available(loaded,restored,u,2);assert(not ok and reason=='cache_collected')
            assert(loaded.scrap==scrap and loaded.coop.randomState==rng)
        ''')

    def test_retreat_reenter_and_older_schema_migration_preserve_claims(self):
        self.lua.execute('''
            assert(begin().ok);near(1);assert(action('host','battle.search',{cacheId=1}).ok)
            local b=ready();local s=data.tacticalBattle;local scrap=data.scrap
            assert(run('host','battle.retreat',{encounterId=s.encounterId,turnRevision=s.revision}).ok)
            assert(not data.tacticalBattle and Schema.validate(saved))
            data.version=49;local migrated=assert(Schema.migrate(data));assert(migrated.encounters['2'].ruinCaches['1']);data.version=Schema.CURRENT_VERSION
            assert(begin().ok);b=near(1)
            assert(action('host','battle.search',{cacheId=1}).reason=='cache_collected'and data.scrap==scrap)
            near(2);assert(action('host','battle.search',{cacheId=2}).ok)
        ''')

    def test_full_pack_uses_mailbox_then_pending_delivery_without_losing_loot(self):
        self.lua.execute('''
            assert(begin().ok)
            for i=1,guest.inventoryCapacity do Items.write(guest,nil,{kind='inventory',index=i},'cloth')end
            local mailbox;for _,v in ipairs(data.droppedItems)do if v.name=='mailbox-reward'and v.scene=='train'then mailbox=v end end
            if not mailbox then mailbox={name='mailbox-reward',scene='train',carIndex=1,x=100,y=100};table.insert(data.droppedItems,mailbox);assert(Entities.ensure(data))end
            mailbox.storage={};mailbox.storageInstances={}
            local b=near(1,2);assert(action('companion','battle.search',{cacheId=1}).ok)
            local r=Search.receipt(data,b,1);assert(r.delivery=='mailbox'and mailbox.storage[1]==r.item)
            for i=1,Catalog.storageCapacities['mailbox-reward']do Items.write(data,mailbox,{kind='chest',index=i},'cloth')end
            near(2,2);assert(action('companion','battle.search',{cacheId=2}).ok)
            r=Search.receipt(data,b,2);assert(r.delivery=='pending'and data.pendingRewards[#data.pendingRewards]==r.item)
            assert(Schema.validate(saved))
            data.tacticalBattle=nil;state.screen='game';state.scene='train';state.x,state.y=mailbox.x,mailbox.y
            guest.activeCar=1;Items.write(guest,nil,{kind='inventory',index=1},nil)
            require('game.coop_inventory').install(service,{catalog=Catalog,actorState=function()return state end})
            local reply=run('companion','storage.transfer',{containerId=mailbox.entityId,source={kind='chest',index=1},sourceItem={name='cloth',id=false}})
            assert(reply.ok,reply.reason);assert(mailbox.storage[1]==r.item and #data.pendingRewards==0)
            assert(Schema.validate(saved),'mailbox refill was not saved with the transfer')
        ''')

    def test_all_reward_categories_use_existing_catalog_and_gear_ledger(self):
        self.lua.execute('''
            for _,location in ipairs({1,20,50})do
                setup();data.location=location;data.encounters={[tostring(location)]=data.encounters['2']};assert(Entities.ensure(data));assert(begin().ok)
                local b=ready();emptyPack(host)
                for id=1,12 do
                    near(id);local r,text=Search.claim(data,b,b.units[1],id,Catalog,function()return .01 end)
                    assert(r and text and(r.item or r.ammo)and Search.validate(data))
                    if r.item then assert(Catalog.itemEffects[r.item]or Catalog.craftMaterials[r.item]or Catalog.weaponStats[r.item]or Catalog.itemRarity[r.item])end
                end
                assert(Schema.validate(data))
            end
        ''')

    def test_expedition_area_owns_receipts_across_different_enemy_encounters(self):
        self.lua.execute('''
            assert(begin().ok);local b=near(1);local area={mobs={}}
            data.expeditions.test=area;b.encounter={source='expedition',areaId='test'}
            local r=assert(Search.claim(data,b,b.units[1],1,Catalog,function()return .5 end))
            assert(area.ruinCaches['1']==r and not data.encounters['2'].ruinCaches)
            b.encounter={source='expedition',areaId='test',entityId='different-enemy'}
            assert(Search.receipt(data,b,1)==r and not Search.available(data,b,b.units[1],1))
        ''')

    def test_corrupt_receipts_are_rejected_even_without_an_active_battle(self):
        self.lua.execute('''
            assert(begin().ok);near(1);assert(action('host','battle.search',{cacheId=1}).ok)
            data.tacticalBattle=nil;assert(Schema.validate(data))
            local r=data.encounters['2'].ruinCaches['1']
            r.scrap=0/0;assert(not Schema.validate(data));r.scrap=3
            r.amount=9;assert(not Schema.validate(data));r.amount=nil
            r.actorId='enemy';assert(not Schema.validate(data));r.actorId='host'
            data.encounters['2'].ruinCaches['13']=r;assert(not Schema.validate(data))
        ''')


if __name__ == '__main__':
    unittest.main()
