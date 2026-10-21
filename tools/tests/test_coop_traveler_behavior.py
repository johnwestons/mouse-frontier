"""Portable character checkout/checkpoints preserve each local world's state."""
import unittest
import test_coop_gifts_behavior as gifts

class TravelerTests(unittest.TestCase):
    def setUp(self):
        gifts.CoopGiftsTests.setUp(self)
        self.lua.execute('''
            Traveler=require('game.coop_traveler')
            remoteWorld=string.rep('a',32); profileId=string.rep('b',32); tripId=string.rep('c',32)
            localSave=Fixtures.campaign(9); localSave.scene='house'; localSave.activeHouseDoor=2
            original=assert(Schema.copy(localSave))
            away,profile=Traveler.checkout(localSave,remoteWorld,'192.168.1.2:22124',profileId,tripId)
            assert(away and profile, tostring(profile))
            function receipt(revision,returned) return {campaignId=remoteWorld,revision=revision,returned=returned==true} end
        ''')

    def test_checkout_reserves_slot_and_reconnect_reuses_visit(self):
        self.lua.execute('''
            assert(not Traveler.isAway(localSave) and Traveler.isAway(away))
            assert(profile.actor.character==localSave.character and profile.actor.stats.level==2)
            assert(not profile.actor.scene and not profile.actor.playerX and not profile.actor.activeCar)
            local retry,envelope=Traveler.checkout(away,remoteWorld,'192.168.1.2:22124',string.rep('d',32),string.rep('e',32))
            assert(envelope.tripId==tripId and envelope.profileId==profileId and envelope.serial==1)
            local denied,reason=Traveler.checkout(away,string.rep('f',32),'another-host',profileId,string.rep('e',32))
            assert(not denied and reason=='traveler_away')
            assert(Schema.validate(retry) and require('game.net.game_state').audit(retry))
        ''')

    def test_import_keeps_foreign_gear_distinct_and_preserves_condition_and_upgrades(self):
        self.lua.execute('''
            local hostItem=data.itemSlots.equipment[1].id; local sourceId=profile.actor.itemSlots.equipment[1].id
            local oldScene,oldLocation,oldHostXP=data.scene,data.location,data.stats.xp
            profile.actor.stats.level=5; profile.actor.stats.xp=13; profile.actor.ammo['22lr']=38
            profile.actor.maxHealth=31; profile.actor.health=27
            local imported=assert(Traveler.replaceActor(data,'companion',profile.actor))
            assert(imported.stats.level==5 and imported.ammo['22lr']==38 and imported.maxHealth==31)
            assert(imported.itemSlots.equipment[1].id~=sourceId and imported.itemSlots.equipment[1].id~=hostItem)
            assert(imported.itemSlots.equipment[1].durability==67)
            assert(data.scene==oldScene and data.location==oldLocation and data.stats.xp==oldHostXP)
            assert(Schema.validate(data) and Items.validate(data))
        ''')

    def test_return_updates_only_the_character_and_repeated_receipts_do_not_duplicate(self):
        self.lua.execute('''
            profile.actor.inventory[1]=nil
            profile.actor.stats.level=4; profile.actor.stats.xp=19; profile.actor.ammo['22lr']=51
            local checkpoint=assert(Traveler.applyCheckpoint(away,profile,receipt(5)))
            assert(Traveler.isAway(checkpoint) and checkpoint.stats.level==4 and checkpoint.ammo['22lr']==51)
            assert(checkpoint.inventory[1]==nil and localSave.inventory[1]=='orange-rose-vase')
            assert(checkpoint.location==9 and checkpoint.scene=='house' and checkpoint.activeHouseDoor==2)
            assert(checkpoint.playerX==original.playerX and checkpoint.resources.coal==original.resources.coal)
            assert(checkpoint.conversations.completed.example.answer==2 and checkpoint.scrap==original.scrap)
            local counter=checkpoint.itemIdentity.nextId
            local returned=assert(Traveler.applyCheckpoint(checkpoint,profile,receipt(5,true)))
            assert(not Traveler.isAway(returned) and returned.itemIdentity.nextId==counter)
            local again,why=Traveler.applyCheckpoint(returned,profile,receipt(5,true))
            assert(again and why=='already_returned' and again.itemIdentity.nextId==counter and again.stats.xp==19)
            local nextTrip,nextProfile=Traveler.checkout(returned,remoteWorld,'192.168.1.2',profileId,string.rep('d',32))
            assert(nextTrip and nextProfile.serial==2 and nextProfile.actor.ammo['22lr']==51)
        ''')

    def test_stale_foreign_and_malformed_checkpoints_do_not_touch_slot(self):
        self.lua.execute('''
            local checkpoint=assert(Traveler.applyCheckpoint(away,profile,receipt(8)))
            local bad,reason=Traveler.applyCheckpoint(checkpoint,profile,receipt(7))
            assert(not bad and reason=='stale_traveler_checkpoint')
            local forged=receipt(9); forged.campaignId=string.rep('f',32)
            bad,reason=Traveler.applyCheckpoint(checkpoint,profile,forged)
            assert(not bad and reason=='traveler_visit_mismatch')
            profile.actor.scene='train'; assert(not Traveler.validEnvelope(profile)); profile.actor.scene=nil
            profile.actor.itemSlots.equipment[2].id=profile.actor.itemSlots.equipment[1].id
            assert(not Traveler.validEnvelope(profile))
            assert(checkpoint.stats.xp==4 and checkpoint.localTraveler.trip.appliedRevision==8)
        ''')

    def test_bounded_wire_records_preserve_sparse_inventory_and_reject_extra_fields(self):
        self.lua.execute('''
            local wire=assert(Traveler.pack(profile))
            local Codec=require('game.net.codec'); local bytes=assert(Codec.encode(wire,{maxBytes=65536,maxDepth=12,maxEntries=4096,maxStringBytes=256}))
            local decoded=assert(Traveler.unpack(assert(Codec.decode(bytes,{maxBytes=65536,maxDepth=12,maxEntries=4096,maxStringBytes=256}))))
            assert(decoded.actor.inventory[4]=='cowboy-hat' and not decoded.actor.inventory[2])
            assert(decoded.actor.itemSlots.equipment[1].durability==67)
            wire.world={location=50}; assert(not Traveler.unpack(wire)); wire.world=nil
            wire.actor.nodes[1][1].ref=1; assert(not Traveler.unpack(wire))
        ''')

    def test_prepared_potions_round_trip_as_flags_and_reject_malformed_values(self):
        self.lua.execute('''
            profile.actor.nextBattlePotions['red-potion-vial']=true
            local received=assert(Traveler.unpack(assert(Traveler.pack(profile))))
            assert(received.actor.nextBattlePotions['red-potion-vial']==true)
            assert(Traveler.replaceActor(data,'companion',received.actor))
            assert(data.players.companion.nextBattlePotions['red-potion-vial']==true)
            local returned=assert(Traveler.applyCheckpoint(away,received,receipt(1,true)))
            assert(returned.nextBattlePotions['red-potion-vial']==true)
            for _,value in ipairs({false,1,'true',{}}) do
                profile.actor.nextBattlePotions['red-potion-vial']=value
                assert(not Traveler.validEnvelope(profile))
            end
        ''')
