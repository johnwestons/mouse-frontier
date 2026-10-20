"""Explicit durable host administration; detached saves and real domain rules."""
from pathlib import Path
import hashlib
import os
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,os.environ.get('LUA_RUNTIME_PYTHONPATH',str(ROOT/'.stabilization/coop-python-deps')))
from lupa.lua51 import LuaRuntime


class CompanionManagementTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root=ROOT.as_posix()
        self.lua.globals().pythonHash=lambda value:hashlib.sha256(value.encode()).hexdigest()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            F=require('tools.tests.lua.coop_fixtures');Schema=require('game.save_schema')
            Authority=require('game.coop_authority');Connections=require('game.coop_connections')
            Admission=require('game.coop_admission');Identity=require('game.net.identity');Codec=require('game.net.codec')
            Players=require('game.coop_players');Items=require('game.item_instances')
            data=F.campaign(2,{scene='train',stopped=true});writes=0;failSave=false;clock=1;entropy=20
            function hash(value)return pythonHash(value)end
            function encoded(value)
                if type(value)=='string'then return string.format('%q',value)end
                if type(value)~='table'then return type(value)..':'..tostring(value)end
                local keys={};for key in pairs(value)do keys[#keys+1]=key end
                table.sort(keys,function(a,b)return type(a)..tostring(a)<type(b)..tostring(b)end)
                local out={'{'};for _,key in ipairs(keys)do out[#out+1]=encoded(key)..'='..encoded(value[key])..';'end
                out[#out+1]='}';return table.concat(out)
            end
            function same(a,b)return encoded(a)==encoded(b)end
            service=Authority.new({campaign=data,sessionId='management-test',clock=function()return clock end,
                checkpoint=function(value)writes=writes+1;if failSave then return false end;saved=assert(Schema.copy(value));return true end})
            trusted={screen='game',scene='train',saving=false,pendingAdmission=false,traveling=false,
                encounterActive=false,activityBlocked=false,changingCar=false}
            ctx={catalog={characterTrait=function(name)return {name=name,maxHealth=name=='cook-mouse.png' and 2 or name=='scout-frog.png' and 4 or 0}end},
                allowedCharacters={['cook-mouse.png']=true,['scout-frog.png']=true,['plain-mouse.png']=true},
                managementState=function()return trusted end,
                placeCompanion=function(campaign)campaign.players.companion.playerX=240;campaign.players.companion.playerY=250;return true end}
            Connections.install(service,ctx)
            cid=string.rep('a',32);pid=string.rep('b',32);secret=string.rep('c',64)
            function run(name,args)local r=service:submitLocal(name,args or {});assert(r.ok,r.reason);return r end
            run('session.host',{campaignId=cid})
            run('session.enroll',{companionId=pid,credentialHash=hash(secret),character='cook-mouse.png'})
            oldCredential={campaignId=cid,companionId=pid,token=secret}
            own=data.players.companion;own.health=6
            own.ammo['22lr']=37;own.weaponProficiency.firearms=4;own.nextBattlePotions={'iron-potion'}
            Items.write(Players.forActor(data,'companion'),nil,{kind='inventory',index=1},'frontier-22-lever-rifle')
            own.itemSlots.inventory[1].durability=61
            adapter=assert(Admission.new(service,{token=function(bytes)entropy=entropy+1;return string.format('%0'..(bytes*2)..'x',entropy)end,hash=hash}))
            writes=0
            function replacementArgs(extra)
                local result={character='scout-frog.png',previousCompanionId=data.coop.network.companionId,
                    companionId=string.rep('e',32),credentialHash=hash(string.rep('f',64))}
                for key,value in pairs(extra or {})do result[key]=value end;return result
            end
            function kickArgs(extra)
                local result={generation=7,companionId=data.coop.network.companionId,credentialHash=hash(string.rep('f',64))}
                for key,value in pairs(extra or {})do result[key]=value end;return result
            end
        ''')

    def test_explicit_replacement_changes_only_traveler_trait_health_identity_and_admin_receipt(self):
        self.lua.execute('''
            local old=assert(Schema.copy(own));local host=assert(Schema.copy(data.players.host))
            local resources=encoded(data.resources);local itemCounter=data.itemIdentity.nextId
            local entityCounter=data.coop.nextEntityId;local epoch=data.coop.sceneEpoch;local revision=data.coop.revision
            local receipts=#data.coop.checkpoints.receipts;local randomState=data.coop.randomState;local seed=service.randomSeed
            local r=assert(adapter:replace('scout-frog.png'));assert(r.ok and r.durable and writes==1)
            assert(r.result.management=='replace' and r.result.character=='scout-frog.png')
            assert(data.players.companion==own and own.character=='scout-frog.png' and own.maxHealth==old.maxHealth+2 and own.health==6)
            old.character=own.character;old.trait=own.trait;old.maxHealth=own.maxHealth
            assert(same(own,old) and same(data.players.host,host) and encoded(data.resources)==resources)
            assert(data.itemIdentity.nextId==itemCounter and data.coop.nextEntityId==entityCounter)
            assert(data.coop.sceneEpoch==epoch and data.coop.revision==revision+1 and #data.coop.checkpoints.receipts==receipts+1)
            assert(data.coop.randomState==randomState and service.randomSeed==seed)
            assert(data.coop.network.companionId~=pid and data.coop.network.campaignId==cid and data.coop.network.bindingVersion==2)
            assert(not adapter:authenticate(oldCredential) and Schema.validate(saved))
            local copy=assert(Schema.migrate(saved));assert(copy.players.companion.itemSlots.inventory[1].id==own.itemSlots.inventory[1].id)
        ''')

    def test_trait_decrease_clamps_current_health_without_healing_or_resetting_levels(self):
        self.lua.execute('''
            own.health=own.maxHealth;local oldMax=own.maxHealth;local stats=encoded(own.stats)
            local r=assert(adapter:replace('plain-mouse.png'));assert(r.ok and r.durable)
            assert(own.maxHealth==oldMax-2 and own.health==oldMax-2 and encoded(own.stats)==stats)
        ''')

    def test_unapplied_legacy_trait_uses_existing_bootstrap_baseline_rule_without_healing(self):
        self.lua.execute('''
            own.traitBaselineApplied=false;own.maxHealth=23;own.health=6
            local r=assert(adapter:replace('scout-frog.png'));assert(r.ok and r.durable)
            assert(own.maxHealth==27 and own.health==6 and own.traitBaselineApplied==true)
        ''')

    def test_ordinary_approval_after_replacement_preserves_host_selected_character_and_exact_kit(self):
        self.lua.execute('''
            local r=assert(adapter:replace('scout-frog.png'));assert(r.durable);adapter:clearManagement()
            local item=own.itemSlots.inventory[1].id;local id=data.coop.network.companionId;local hp=own.health
            local credential=assert(adapter:issue({generation=8,name='Friend',character='cook-mouse.png'}))
            assert(credential.companionId==id and own.character=='scout-frog.png' and own.health==hp)
            assert(own.itemSlots.inventory[1].id==item and own.itemSlots.inventory[1].durability==61 and own.ammo['22lr']==37)
            assert(adapter:authenticate(credential) and not adapter:authenticate(oldCredential))
        ''')

    def test_failed_replacement_save_retries_exact_envelope_once_without_new_entropy_or_health_rebase(self):
        self.lua.execute('''
            failSave=true;local oldMax=own.maxHealth;local r=assert(adapter:replace('scout-frog.png'))
            assert(r.ok and r.savePending and not r.durable and service.pendingSave)
            local id=r.requestId;local entropyAfter=entropy;local revision=data.coop.revision
            local rebound=data.coop.network.companionId;assert(own.maxHealth==oldMax+2)
            local duplicate=assert(adapter:replace('scout-frog.png'))
            assert(duplicate.requestId==id and not duplicate.durable and entropy==entropyAfter and data.coop.revision==revision)
            assert(not adapter:replace('plain-mouse.png'))
            failSave=false;assert(service:retryCheckpoint());local durable=assert(adapter:managementResult())
            assert(durable.durable and durable.requestId==id and own.maxHealth==oldMax+2 and data.coop.network.companionId==rebound)
            assert(saved.players.companion.itemSlots.inventory[1].id==own.itemSlots.inventory[1].id)
            local count=writes;assert(adapter:managementResult().durable and writes==count and entropy==entropyAfter)
        ''')

    def test_replacement_rejects_unknown_same_character_stale_identity_and_forged_extra_fields(self):
        self.lua.execute('''
            local before=encoded(data)
            for _,extra in ipairs({{character='unloaded.png'},{character='cook-mouse.png'},
                {previousCompanionId=string.rep('9',32)},{companionId=pid},{credentialHash=hash(secret)},
                {token=secret},{resetKit=true},{character='scout-frog.png',actorId='host'}})do
                local r=service:submitLocal('session.replace',replacementArgs(extra));assert(not r.ok)
                assert(encoded(data)==before and writes==0)
            end
            service:admit('companion',7)
            assert(service:submitLocal('session.replace',replacementArgs()).reason=='companion_connected')
        ''')

    def test_missing_or_unsafe_trusted_context_and_activity_locks_fail_closed(self):
        self.lua.execute('''
            local before=encoded(data)
            local provider=ctx.managementState;ctx.managementState=nil
            assert(service:submitLocal('session.replace',replacementArgs()).reason=='management_unavailable');ctx.managementState=provider
            for _,key in ipairs({'saving','pendingAdmission','traveling','encounterActive','activityBlocked','changingCar'})do
                trusted[key]=true;assert(not service:submitLocal('session.replace',replacementArgs()).ok);trusted[key]=false
                assert(encoded(data)==before and writes==0)
            end
            trusted.scene='stop';assert(not service:submitLocal('session.replace',replacementArgs()).ok);trusted.scene='train'
            data.stopped=false;assert(not service:submitLocal('session.replace',replacementArgs()).ok);data.stopped=true
            service.activityState.resources.busy={actorId='host',generation=0,sceneEpoch=data.coop.sceneEpoch,expiresAt=10,payload={kind='sewing'}}
            assert(service:submitLocal('session.replace',replacementArgs()).reason=='replacement_unavailable')
            service.activityState.resources={};assert(encoded(data)==before and writes==0)
        ''')

    def test_connected_guest_can_never_kick_or_replace_anyone(self):
        self.lua.execute('''
            service:admit('companion',7);local before=encoded(data)
            for index,name in ipairs({'session.kick','session.replace'})do
                local reply=service:execute('companion',7,{sessionId=service.sessionId,requestId=index,
                    sceneEpoch=data.coop.sceneEpoch,command=name,args={},expected={}})
                assert(not reply.ok and reply.reason=='host_only')
            end
            assert(encoded(data)==before and writes==0 and service.bindings.companion==7)
        ''')

    def test_kick_revokes_credentials_but_keeps_exact_kit_world_and_live_binding_until_durable_drop(self):
        self.lua.execute('''
            service:admit('companion',7);local kit=encoded(own);local host=encoded(data.players.host)
            local resources=encoded(data.resources);local epoch=data.coop.sceneEpoch;local ledger=encoded(data.itemIdentity)
            service.activityState.travelRequests={pending={serial=8}}
            local r=assert(adapter:kick(7));assert(r.ok and r.durable and r.result.management=='kick' and r.result.generation==7)
            assert(service.bindings.companion==7 and encoded(own)==kit and encoded(data.players.host)==host)
            assert(data.coop.network.companionId==pid and not adapter:authenticate(oldCredential))
            assert(encoded(data.resources)==resources and encoded(data.itemIdentity)==ledger and data.coop.sceneEpoch==epoch)
            assert(not service.activityState.travelRequests and writes==1 and Schema.validate(saved))
            service:disconnect('companion',7);adapter:clearManagement()
            local credential=assert(adapter:issue({generation=8,name='Friend',character='scout-frog.png'}))
            assert(own.character=='cook-mouse.png' and encoded(own)==kit and credential.companionId==pid)
        ''')

    def test_kick_failed_save_replay_preserves_binding_and_does_not_revoke_twice(self):
        self.lua.execute('''
            service:admit('companion',7);failSave=true
            local r=assert(adapter:kick(7));assert(r.ok and r.savePending and not r.durable)
            local version=data.coop.network.bindingVersion;local rev=data.coop.revision;local entropyAfter=entropy
            assert(service.bindings.companion==7 and not adapter:authenticate(oldCredential))
            local duplicate=assert(adapter:kick(7));assert(duplicate.requestId==r.requestId and not duplicate.durable)
            assert(data.coop.network.bindingVersion==version and data.coop.revision==rev and entropy==entropyAfter)
            failSave=false;assert(service:retryCheckpoint());assert(adapter:managementResult().durable)
            assert(saved.coop.network.bindingVersion==version and service.bindings.companion==7)
        ''')

    def test_kick_rejects_stale_generation_missing_context_save_barrier_and_identity_claims(self):
        self.lua.execute('''
            service:admit('companion',7);local before=encoded(data)
            for _,extra in ipairs({{generation=6},{generation=0},{companionId=string.rep('9',32)},
                {credentialHash=hash(secret)},{token=secret},{resetKit=true}})do
                assert(not service:submitLocal('session.kick',kickArgs(extra)).ok);assert(encoded(data)==before and writes==0)
            end
            ctx.managementState=nil;assert(service:submitLocal('session.kick',kickArgs()).reason=='management_unavailable')
            ctx.managementState=function()return trusted end
            trusted.saving=true;assert(not adapter:kick(7));trusted.saving=false
            service.pendingSave={session=true};assert(not adapter:kick(7));service.pendingSave=nil
            assert(encoded(data)==before and writes==0)
        ''')

    def test_entropy_failure_never_changes_identity_or_allocates_a_management_request(self):
        self.lua.execute('''
            local before=encoded(data);local provider=adapter.token;adapter.token=function()return nil end
            local r,why=adapter:replace('scout-frog.png');assert(not r and why=='entropy_unavailable')
            adapter.token=provider;adapter.hash=function()error('missing provider')end
            r,why=adapter:replace('scout-frog.png');assert(not r and why=='hash_unavailable')
            assert(encoded(data)==before and writes==0 and not adapter.management)
        ''')

    def test_identity_exhaustion_and_journey_block_management_without_reallocating_saved_ledgers(self):
        self.lua.execute('''
            data.coop.network.bindingVersion=2147483647;local before=encoded(data)
            assert(service:submitLocal('session.replace',replacementArgs()).reason=='binding_exhausted')
            service:admit('companion',7)
            assert(service:submitLocal('session.kick',kickArgs()).reason=='binding_exhausted')
            assert(encoded(data)==before and writes==0)
            service:disconnect('companion',7);data.coop.network.bindingVersion=1
            data.coop.journey={from=data.location,to=data.location+1,phase='departed',epoch=data.coop.sceneEpoch,maintenanceCondition=100}
            before=encoded(data);assert(service:submitLocal('session.replace',replacementArgs()).reason=='replacement_unavailable')
            assert(encoded(data)==before and writes==0)
        ''')

    def test_cached_kick_result_always_names_original_generation_after_another_binding(self):
        self.lua.execute('''
            service:admit('companion',7);local first=assert(adapter:kick(7));assert(first.durable)
            service:disconnect('companion',7);service:admit('companion',8)
            local count=writes;local version=data.coop.network.bindingVersion
            local cached=assert(adapter:managementResult())
            assert(cached.durable and cached.result.generation==7 and service.bindings.companion==8)
            assert(writes==count and data.coop.network.bindingVersion==version)
            assert(not adapter:kick(8))
        ''')

    def test_management_tokens_are_never_published_or_written_as_raw_credentials(self):
        self.lua.execute('''
            local issued={};adapter.token=function(bytes)
                entropy=entropy+1;local value=string.format('%0'..(bytes*2)..'x',entropy)
                if bytes==32 then issued[#issued+1]=value end;return value
            end
            local r=assert(adapter:replace('scout-frog.png'));assert(r.durable and not r.result.token)
            local fs,files=F.filesystem();love.filesystem=fs;local Save=require('game.save');assert(Save.write(1,saved))
            local bytes=assert(files[Save.path(1)]);local pending=encoded(adapter.management)
            for _,token in ipairs(issued)do assert(not bytes:find(token,1,true) and not pending:find(token,1,true))end
            assert(not adapter:issue({generation=8,name='Friend',character='cook-mouse.png'}))
        ''')


class CompanionManagementModeTests(unittest.TestCase):
    def setUp(self):
        import test_coop_battles_behavior as tactical
        tactical.TacticalCommandTests.setUp(self)

    def install(self):
        self.lua.execute('''
            local Connections=require('game.coop_connections')
            data.coop.network={version=1,campaignId=string.rep('a',32),companionId=string.rep('b',32),
                credentialHash=string.rep('c',64),bindingVersion=1}
            local function encode(value)
                if type(value)=='string'then return string.format('%q',value)end
                if type(value)~='table'then return type(value)..':'..tostring(value)end
                local keys={};for key in pairs(value)do keys[#keys+1]=key end
                table.sort(keys,function(a,b)return type(a)..tostring(a)<type(b)..tostring(b)end)
                local out={'{'};for _,key in ipairs(keys)do out[#out+1]=encode(key)..'='..encode(value[key])..';'end
                out[#out+1]='}';return table.concat(out)
            end
            function gameplay()
                local value=assert(Schema.copy(data))
                value.coop.network=nil;value.coop.revision=nil;value.coop.revisions.session=nil
                value.coop.checkpoints.receipts=nil
                return encode(value)
            end
            Connections.install(service,{catalog=Catalog,allowedCharacters={['cook-mouse.png']=true,['scout-frog.png']=true},
                placeCompanion=function()return true end,
                managementState=function()return {screen=managementScreen or 'game',scene=data.scene,saving=false,pendingAdmission=false,
                    traveling=false,encounterActive=false,activityBlocked=false,changingCar=false}end})
            function kick()
                local before=gameplay();local leaseCount=0
                for _ in pairs(service.activityState.resources)do leaseCount=leaseCount+1 end
                local r=service:submitLocal('session.kick',{generation=1,companionId=data.coop.network.companionId,
                    credentialHash=string.rep('d',64)})
                assert(r.ok and r.durable,r.reason)
                assert(gameplay()==before and Schema.validate(saved))
                assert(service.bindings.companion==1)
                local count=0;for _ in pairs(service.activityState.resources)do count=count+1 end;assert(count==leaseCount)
                service:disconnect('companion',1)
                for _,lease in pairs(service.activityState.resources)do assert(lease.actorId~='companion')end
                assert(gameplay()==before)
            end
            function blockedReplacement()
                service:disconnect('companion',1)
                local before=gameplay();local r=service:submitLocal('session.replace',{character='scout-frog.png',
                    previousCompanionId=data.coop.network.companionId,companionId=string.rep('e',32),credentialHash=string.rep('d',64)})
                assert(not r.ok and gameplay()==before)
            end
        ''')

    def test_active_tactical_kick_preserves_exact_saved_board_actor_hp_items_turns_and_rng(self):
        self.lua.execute('assert(begin().ok);ready()')
        self.install()
        self.lua.execute('kick();assert(data.tacticalBattle and data.tacticalBattle.battle.units[2].actorId=="companion")')

    def test_actual_tactical_battle_screen_allows_kick_and_preserves_saved_combat(self):
        self.lua.execute('assert(begin().ok);ready();managementScreen="battle"')
        self.install()
        self.lua.execute('kick();assert(data.tacticalBattle and data.tacticalBattle.battle.units[2].actorId=="companion")')

    def test_active_ambush_kick_preserves_exact_magazines_reload_cover_targets_and_owned_ammo(self):
        import test_coop_guns_behavior as guns
        guns.AmbushCommandTests.ambush(self)
        self.lua.execute('ggun.magazine=3;ggun.cooldown=.2;ggun.reloadTimer=.3;convoy.defenders.companion.cover=true')
        self.install()
        self.lua.execute('kick();assert(data.trainAmbush.shooterSessions.companion.weaponSession.magazine==3)')

    def test_active_range_kick_preserves_practice_guns_round_state_and_releases_only_live_guest_lease(self):
        import test_coop_range_behavior as ranges
        ranges.RangeCommandTests.range(self)
        self.lua.execute('assert(config("companion","start").ok);advance(.2)')
        self.install()
        self.lua.execute('kick();assert(data.rangeSessions.companion.phase=="play")')

    def test_active_last_stand_kick_preserves_defender_positions_loans_magazines_and_combat(self):
        import test_coop_last_stand_progression_behavior as stand
        stand.LastStandProgressionTests.stand(self)
        self.lua.execute('start()')
        self.install()
        self.lua.execute('kick();assert(data.lastStand.lifecycle.mode=="shootout")')

    def test_active_tactical_replacement_is_rejected_without_kit_or_combat_mutation(self):
        self.lua.execute('assert(begin().ok);ready()')
        self.install();self.lua.execute('blockedReplacement()')

    def test_active_ambush_replacement_is_rejected_without_kit_or_gun_mutation(self):
        import test_coop_guns_behavior as guns
        guns.AmbushCommandTests.ambush(self)
        self.install();self.lua.execute('blockedReplacement()')

    def test_active_range_replacement_is_rejected_without_kit_or_lane_mutation(self):
        import test_coop_range_behavior as ranges
        ranges.RangeCommandTests.range(self)
        self.lua.execute('assert(config("companion","start").ok)')
        self.install();self.lua.execute('blockedReplacement()')

    def test_saved_unfinished_range_blocks_replacement_even_after_return_to_ordinary_train(self):
        import test_coop_range_behavior as ranges
        ranges.RangeCommandTests.range(self)
        self.lua.execute('assert(config("companion","start").ok);data.scene="train";data.stopped=true')
        self.install();self.lua.execute('blockedReplacement()')

    def test_active_last_stand_replacement_is_rejected_without_positions_or_kit_mutation(self):
        import test_coop_last_stand_progression_behavior as stand
        stand.LastStandProgressionTests.stand(self)
        self.lua.execute('start()')
        self.install();self.lua.execute('blockedReplacement()')


if __name__=='__main__':unittest.main()
