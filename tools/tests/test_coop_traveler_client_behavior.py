"""Selected-slot characters round trip through the real two-peer lifecycle."""
import unittest
import test_coop_local_play_behavior as lifecycle

class TravelerClientTests(unittest.TestCase):
    def setUp(self):
        lifecycle.LocalPlayTests.setUp(self)
        lifecycle.LocalPlayTests.enable_cars(self)
        self.lua.execute('''
            Traveler=require('game.coop_traveler'); localWrites=0
            guestData.ammo['22lr']=47; guestData.stats.level=5; guestData.stats.xp=13
            source=assert(Schema.copy(guestData)); slots={[2]=assert(Schema.copy(guestData))}
            guestContext.readSlot=function(slot) return slots[slot] and assert(Schema.copy(slots[slot])) end
            guestContext.writeSlot=function(slot,value)
                if failLocalSave then return false end
                localWrites=localWrites+1; slots[slot]=assert(Schema.copy(value)); return true
            end
            hostContext.writeSlot=function() return true end
            assert(guest:chooseSaveSlot() and guest:selectSaveSlot(2))
            function readyPortable()
                assert(host:host() and guest:join()); step(20)
                assert(host:pending(),guest.error or 'no approval'); assert(host:approve()); step(30)
                assert(guest.phase=='connected',guest.error or guest.phase)
            end
        ''')

    def tearDown(self):
        lifecycle.LocalPlayTests.tearDown(self)

    def test_import_and_return_preserve_source_world_and_exact_progress(self):
        self.lua.execute('''
            readyPortable()
            local actor=data.players.companion
            assert(actor.stats.level==5 and actor.ammo['22lr']==47 and Traveler.isAway(slots[2]))
            actor.stats.xp=23; actor.ammo['22lr']=29
            assert(service:checkpointNow()); step(60)
            assert(slots[2].stats.xp==23 and slots[2].ammo['22lr']==29)
            assert(Traveler.isAway(slots[2]) and slots[2].location==source.location)
            assert(slots[2].resources.coal==source.resources.coal and slots[2].playerX==source.playerX)
            guest:returnToSave(); step(55)
            assert(guest.phase=='idle',guest.error or guest.phase)
            assert(not Traveler.isAway(slots[2]) and not slots[2].localTraveler.lastReturn.pending)
            assert(slots[2].stats.xp==23 and slots[2].ammo['22lr']==29 and slots[2].scene==source.scene)
            assert(data.players.companion.travelIdentity.status=='closed')
            assert(Schema.validate(slots[2]) and Schema.validate(data))
            local count=slots[2].itemIdentity.nextId; step(25); assert(slots[2].itemIdentity.nextId==count)
        ''')

    def test_disconnect_reconnect_uses_host_latest_without_reimport(self):
        self.lua.execute('''
            readyPortable(); data.players.companion.ammo['22lr']=7; assert(service:checkpointNow())
            guest:stop(); step(5)
            assert(Traveler.isAway(slots[2])); local serial=slots[2].localTraveler.serial
            assert(guest:join()); step(45)
            assert(guest.phase=='connected',guest.error or guest.phase)
            assert(not host:pending() and data.players.companion.ammo['22lr']==7)
            assert(slots[2].localTraveler.serial==serial)
            guest:returnToSave(); step(55); assert(slots[2].ammo['22lr']==7 and not Traveler.isAway(slots[2]))
        ''')

    def test_portable_join_during_battle_consumes_prepared_potion_once(self):
        self.lua.execute('''
            local Catalog=require('game.catalog'); local Players=require('game.coop_players')
            slots[2].nextBattlePotions['red-potion-vial']=true
            data.encounters['2']={rolled=true,hasMob=true,resolved=false,tier='easy',maxHP=100,mobFiles={Catalog.mobTiers.easy[1]}}
            require('game.coop_entities').ensure(data)
            assert(commands.submit('battle.begin',{encounterId=data.encounters['2'].entityId}).ok)
            local battle=data.tacticalBattle.battle; hostRuntime.battle=battle; battle.intro=nil
            local enemyId=battle.units[2].id
            readyPortable()
            assert(#battle.units==2 and battle.pendingActorId=='companion')
            assert(data.players.companion.nextBattlePotions['red-potion-vial']==true)
            local state=data.tacticalBattle
            assert(commands.submit('battle.endTurn',{encounterId=state.encounterId,turnRevision=state.revision,unitId=battle.units[1].id}).ok)
            battle=data.tacticalBattle.battle; hostRuntime.battle=battle
            local actor=data.players.companion; local unit=battle.units[2]
            local wear=Catalog.wearableBonuses(actor.wearables)
            local baseAim=2+(actor.trait and actor.trait.combat or 0)+(wear.aim or 0)
            assert(unit.actorId=='companion' and unit.file==slots[2].character)
            assert(unit.aim==baseAim+Catalog.itemEffects['red-potion-vial'].attack)
            assert(next(actor.nextBattlePotions)==nil and #battle.units==3 and battle.units[3].id==enemyId)
            local aim=unit.aim; guest:stop(); step(6); assert(guest:join()); step(45)
            assert(guest.phase=='connected',guest.error or guest.phase)
            assert(#battle.units==3 and battle.units[2].aim==aim and not battle.pendingActorId)
            assert(next(actor.nextBattlePotions)==nil and next(slots[2].nextBattlePotions)==nil)
            local identity=actor.travelIdentity
            local denied=commands.submit('session.returnTraveler',{tripId=identity.tripId,serial=identity.serial})
            assert(not denied.ok and denied.reason=='traveler_combat_active' and identity.status=='active')
            state=data.tacticalBattle
            assert(commands.submit('battle.retreat',{encounterId=state.encounterId,turnRevision=state.revision}).ok)
            hostRuntime.battle=nil; step(20); guest:returnToSave(); step(55)
            assert(guest.phase=='idle' and not Traveler.isAway(slots[2]))
            assert(next(slots[2].nextBattlePotions)==nil and slots[2].stats.level==5)
        ''')

    def test_failed_local_return_save_holds_host_final_data_until_retry(self):
        self.lua.execute('''
            readyPortable(); failLocalSave=true; guest:returnToSave(); step(30)
            assert(guest.traveler and guest.traveler.error=='traveler_save_failed')
            assert(Traveler.isAway(slots[2]) and data.players.companion.travelIdentity.status=='returned')
            failLocalSave=false; step(65)
            assert(guest.phase=='idle' and not Traveler.isAway(slots[2]))
            assert(data.players.companion.travelIdentity.status=='closed')
        ''')

    def test_failed_checkout_never_uploads_character_or_reserves_slot(self):
        self.lua.execute('''
            failLocalSave=true; assert(host:host() and guest:join()); step(30)
            assert(not host:pending() and not data.players.companion)
            assert(not Traveler.isAway(slots[2]) and localWrites==0)
        ''')

    def test_lost_final_ack_recovers_without_reimporting_or_reverting_solo_progress(self):
        self.lua.execute('''
            readyPortable()
            local write=guestContext.writeSlot
            guest.traveler.c.write=function(slot,value)
                if value.localTraveler.lastReturn and not value.localTraveler.lastReturn.pending then return false end
                return write(slot,value)
            end
            guest:returnToSave(); step(60)
            assert(data.players.companion.travelIdentity.status=='closed' and slots[2].localTraveler.lastReturn.pending)
            assert(not Traveler.isAway(slots[2])); guest:stop(); step(6)
            slots[2].stats.xp=31 -- the returned character can be used in solo play
            assert(guest:join()); step(60)
            assert(guest.phase=='idle',guest.error or guest.phase)
            assert(slots[2].stats.xp==31 and not slots[2].localTraveler.lastReturn.pending)
            assert(data.players.companion.stats.xp==13, 'old return was imported again')
        ''')

    def test_second_visit_imports_updated_character_once(self):
        self.lua.execute('''
            readyPortable(); guest:returnToSave(); step(55)
            local first=data.players.companion.travelIdentity.tripId
            slots[2].ammo['22lr']=61; slots[2].stats.xp=22
            assert(guest:join()); step(25); assert(host:pending() and host:approve()); step(30)
            assert(guest.phase=='connected',guest.error or guest.phase)
            local actor=data.players.companion
            assert(actor.travelIdentity.serial==2 and actor.travelIdentity.tripId~=first)
            assert(actor.ammo['22lr']==61 and actor.stats.xp==22)
            guest:returnToSave(); step(55); assert(not Traveler.isAway(slots[2]) and slots[2].ammo['22lr']==61)
        ''')

    def test_declining_first_visit_releases_slot_but_declining_rejoin_keeps_it_reserved(self):
        self.lua.execute('''
            assert(host:host() and guest:join()); step(25); assert(host:pending() and host:decline()); step(20)
            assert(guest.phase=='idle' and not Traveler.isAway(slots[2]))
            assert(guest:join()); step(25); assert(host:approve()); step(25)
            guest:stop(); step(6)
            guestContext.filesystem.remove('local-play-credentials.lua')
            local network=guestContext.network.join
            guestContext.network.join=function(address,options)
                options.credentialFor=function() return nil end; return network(address,options)
            end
            assert(guest:join()); step(25); assert(host:pending() and host:decline()); step(20)
            assert(guest.phase=='idle' and Traveler.isAway(slots[2]))
            assert(data.players.companion.travelIdentity.status=='active')
        ''')

    def test_host_end_waits_for_client_save_and_final_acknowledgement(self):
        self.lua.execute('''
            readyPortable(); data.players.companion.ammo['22lr']=16; assert(service:checkpointNow())
            assert(host:endLocalPlay() and host.ending); step(80)
            assert(host.phase=='idle' and guest.phase=='idle')
            assert(slots[2].ammo['22lr']==16 and not Traveler.isAway(slots[2]))
            assert(not slots[2].localTraveler.lastReturn.pending and data.players.companion.travelIdentity.status=='closed')
        ''')

    def test_returned_character_can_visit_another_world_with_its_new_items_and_xp(self):
        self.lua.execute('''
            readyPortable(); data.players.companion.ammo['22lr']=26; data.players.companion.stats.xp=24
            assert(service:checkpointNow()); guest:returnToSave(); step(55)
            firstWorld=data.coop.network.campaignId; host:stop(); step(5)
            data=F.campaign(4,{scene='train'}); hostRuntime.saveData=data; hostRuntime.state='game'
        ''')
        lifecycle.LocalPlayTests.enable_cars(self)
        self.lua.execute('''
            assert(host:host() and guest:join()); step(25); assert(host:pending() and host:approve()); step(35)
            assert(data.coop.network.campaignId~=firstWorld and data.location==4)
            assert(data.players.companion.ammo['22lr']==26 and data.players.companion.stats.xp==24)
            assert(slots[2].localTraveler.serial==2 and slots[2].location==9)
            guest:returnToSave(); step(55)
            assert(slots[2].location==9 and slots[2].ammo['22lr']==26 and slots[2].stats.xp==24)
            assert(not Traveler.isAway(slots[2]))
        ''')

    def test_host_restart_restores_saved_visitor_and_reconnects_without_importing_old_ammo(self):
        self.lua.execute('''
            readyPortable(); data.players.companion.ammo['22lr']=12; data.players.companion.stats.xp=25
            assert(service:checkpointNow()); firstTrip=data.players.companion.travelIdentity.tripId
            host:stop('host_restart'); step(25)
            assert(guest.phase=='idle' and Traveler.isAway(slots[2]))
            data=assert(Schema.copy(saved)); hostRuntime.saveData=data; hostRuntime.state='game'
        ''')
        lifecycle.LocalPlayTests.enable_cars(self)
        self.lua.execute('''
            assert(host:host() and guest:join()); step(55)
            assert(guest.phase=='connected' and not host:pending(),guest.error or guest.phase)
            assert(data.players.companion.travelIdentity.tripId==firstTrip)
            assert(data.players.companion.ammo['22lr']==12 and data.players.companion.stats.xp==25)
            guest:returnToSave(); step(55)
            assert(not Traveler.isAway(slots[2]) and slots[2].ammo['22lr']==12 and slots[2].stats.xp==25)
        ''')

if __name__=='__main__': unittest.main()
