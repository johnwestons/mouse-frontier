"""A durable frozen return precedes local saving and admission of a new visitor."""
import unittest
import test_coop_gifts_behavior as gifts

class TravelerReturnTests(unittest.TestCase):
    def setUp(self):
        gifts.CoopGiftsTests.setUp(self)
        self.lua.execute('''
            Traveler=require('game.coop_traveler')
            authority=require('game.coop_authority').new({campaign=data,sessionId='return-test',checkpoint=function() return saveWorks~=false end})
            require('game.coop_traveler_return').install(authority)
            authority:admit('companion',1)
            data.players.companion.travelIdentity={version=1,profileId=string.rep('a',32),tripId=string.rep('b',32),serial=1,status='active'}
            args={tripId=string.rep('b',32),serial=1}
            function submit(name)
                local request,why=authority:prepareRequest('companion',name,args)
                if not request then return nil,why end
                return authority:execute('companion',1,request),request
            end
        ''')

    def test_freezes_final_character_rejects_actions_then_acknowledges_saved_return(self):
        self.lua.execute('''
            local reply=assert(submit('traveler.return')); assert(reply.ok and reply.durable,reply.reason)
            local actor=data.players.companion; local frozen=assert(Traveler.unpack(actor.travelReturn.profile))
            assert(actor.travelIdentity.status=='returned' and Schema.validate(data))
            local before=actor.travelReturn.revision
            actor.stats.xp=actor.stats.xp+10 -- later host simulation cannot alter the frozen return
            local retry=assert(submit('traveler.return')); assert(retry.ok and actor.travelReturn.revision==before)
            assert(Traveler.unpack(actor.travelReturn.profile).actor.stats.xp==frozen.actor.stats.xp)
            local request,why=authority:prepareRequest('companion','inventory.swap',{})
            assert(not request and why=='traveler_returned')
            assert(not require('game.coop_sharing').recipient(data,'host'))
            local ack=assert(submit('traveler.ack')); assert(ack.ok and ack.durable)
            assert(actor.travelIdentity.status=='closed' and data.travelerHistory[frozen.profileId].serial==1)
            assert(Schema.validate(data) and require('game.net.game_state').audit(data))
        ''')

    def test_failed_checkpoint_cannot_ack_or_run_twice_before_save_retry(self):
        self.lua.execute('''
            saveWorks=false
            local reply,request=submit('traveler.return'); assert(reply.ok and reply.savePending and not reply.durable)
            local frozenRevision=data.players.companion.travelReturn.revision
            local ack,why=submit('traveler.ack'); assert(not ack and why=='save_pending')
            saveWorks=true; assert(authority:retryCheckpoint())
            local retry=authority:execute('companion',1,request)
            assert(retry.ok and retry.durable and data.players.companion.travelReturn.revision==frozenRevision)
            assert(Schema.validate(data))
        ''')

    def test_wrong_visit_and_combat_cannot_finalize_character(self):
        self.lua.execute('''
            args.serial=2; local reply,why=submit('traveler.return')
            assert(not reply and why=='traveler_visit_mismatch')
            args.serial=1; data.trainAmbush={active=true}
            reply,why=submit('traveler.return'); assert(not reply and why=='traveler_combat_active')
            assert(not data.players.companion.travelReturn)
        ''')

if __name__=='__main__': unittest.main()
