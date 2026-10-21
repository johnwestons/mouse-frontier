"""Bounded personal-profile uploads finish before host approval or authentication."""
import unittest
import test_coop_local_play_behavior as lifecycle

class TravelerTransferTests(unittest.TestCase):
    def setUp(self):
        lifecycle.LocalPlayTests.setUp(self)
        self.lua.execute('''
            Traveler=require('game.coop_traveler'); Transfer=require('game.net.traveler_transfer')
            source=F.campaign(9,{character='cook-mouse.png'}); source.ammo['22lr']=44
            checked,profile=Traveler.checkout(source,string.rep('a',32),'friend-pc',string.rep('b',32),string.rep('c',32))
            assert(profile and checked)
        ''')

    def tearDown(self):
        lifecycle.LocalPlayTests.tearDown(self)

    def test_checksums_bounds_and_sparse_items_across_multiple_parts(self):
        self.lua.execute('''
            for i=1,240 do profile.actor.inventory[i]='food-ration' end
            profile.actor.inventory[4]='cowboy-hat'; profile.actor.inventoryCapacity=240
            local transfer=assert(Transfer.pack(profile,hash)); assert(transfer.header.parts>1)
            local receiver=assert(Transfer.receiver(transfer.header,0,{['cook-mouse.png']=true},hash))
            local decoded,parts
            parts={}
            while true do local part=transfer:next(); if not part then break end
                parts[#parts+1]=part; decoded=receiver:push(part,1)
            end
            assert(decoded.actor.ammo['22lr']==44 and decoded.actor.inventory[120]=='food-ration')
            assert(decoded.actor.itemSlots.equipment[1].durability==67)
            local bad={}; for key,value in pairs(transfer.header) do bad[key]=value end
            bad.bytes=65537; assert(not Transfer.receiver(bad,0,nil,hash))
            local corrupted=assert(Transfer.receiver(transfer.header,0,nil,hash)); local outcome
            parts[1].data='00'..parts[1].data:sub(3)
            for _,part in ipairs(parts) do outcome=corrupted:push(part,1) end
            assert(outcome==nil)
        ''')

    def test_host_receives_profile_before_approval_and_client_cannot_replace_world(self):
        self.lua.execute('''
            local hostNetwork=hostContext.network.host; local guestNetwork=guestContext.network.join
            hostContext.network.host=function(options)
                options.requiresTraveler=true; options.allowedCharacters={['cook-mouse.png']=true}
                options.validateTraveler=function(candidate) reviewed=candidate; return true end
                local issue=options.issue
                options.issue=function(request)
                    assert(request.profile and request.profile==reviewed)
                    received=request.profile; return issue(request)
                end
                return hostNetwork(options)
            end
            guestContext.network.join=function(address,options)
                options.traveler=function(campaignId) requestedCampaign=campaignId; return profile end
                return guestNetwork(address,options)
            end
            assert(host:host() and guest:join()); step(12)
            assert(host:pending() and reviewed and reviewed.actor.ammo['22lr']==44)
            assert(not data.players.companion and data.location~=source.location)
            assert(host:approve()); step(20)
            assert(guest.phase=='connected',guest.error or guest.phase)
            assert(received.tripId==profile.tripId and requestedCampaign==data.coop.network.campaignId)
            assert(data.scene=='train' and data.location~=source.location)
            assert(data.players.companion.ammo['22lr']==44)
            data.players.companion.ammo['22lr']=19
            assert(host.authority:checkpointNow())
            guest:stop(); step(6); assert(guest:join()); step(30)
            assert(guest.phase=='connected',guest.error or guest.phase)
            assert(data.players.companion.ammo['22lr']==19, 'reconnect imported stale character')
        ''')

    def test_required_profile_and_host_validation_reject_before_enrollment(self):
        self.lua.execute('''
            local hostNetwork=hostContext.network.host
            hostContext.network.host=function(options)
                options.requiresTraveler=true
                options.validateTraveler=function() return false,'traveler_away' end
                return hostNetwork(options)
            end
            assert(host:host() and guest:join()); step(10)
            assert(guest.phase=='idle' and host.network.reason=='traveler_required' and not data.players.companion)
            local guestNetwork=guestContext.network.join
            guestContext.network.join=function(address,options)
                options.traveler=function() return profile end; return guestNetwork(address,options)
            end
            assert(guest:join()); step(16)
            assert(guest.phase=='idle' and host.network.reason=='traveler_away' and not data.players.companion and not host:pending())
        ''')
