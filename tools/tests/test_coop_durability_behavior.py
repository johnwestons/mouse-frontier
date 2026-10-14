"""Critical receipts survive checked saves; uncertain requests never run twice."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopDurabilityTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            Authority=require('game.coop_authority'); Receipts=require('game.coop_receipts')
            Codec=require('game.net.codec'); Players=require('game.coop_players')
            fs,files=F.filesystem(); love={filesystem=fs}; Save=require('game.save')
            data=F.campaign(); assert(F.enroll(data)); writes=0; applies=0; allowed=true
            function create(campaign)
                local service=Authority.new({campaign=campaign,sessionId='durable',checkpoint=function(value)
                    assert(value==campaign); writes=writes+1
                    return allowed and Save.write(1,value)
                end})
                service:admit('companion',1)
                service:register('quest.help',function(draft,actorId,args)
                    return {scopes={'resources','player:'..actorId},apply=function()
                        applies=applies+1; draft.scrap=draft.scrap-3
                        Players.get(draft,actorId).health=10
                        if args.raise then error('reward failure') end
                        return {completed=true,reward=args.reward or 'food-ration'}
                    end}
                end)
                service:register('radio.station',function(draft,actorId,args)
                    return {scopes={'radio'},apply=function() draft.audio.station='chill'; return {ok=true} end}
                end)
                return service
            end
            service=create(data)
            function request(actor,args) return assert(service:prepareRequest(actor or 'companion','quest.help',args or {})) end
            function execute(req,actor) return service:execute(actor or 'companion',actor=='host' and 0 or 1,req) end
            function fingerprint(req) return assert(Codec.encode(req,{maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128})) end
        ''')

    def test_cost_both_actors_and_receipt_are_in_one_verified_checkpoint(self):
        self.lua.execute('''
            data.players.host.health=6
            local req=request(); local reply=execute(req)
            assert(reply.ok and reply.durable and not reply.savePending and applies==1)
            local saved=assert(Save.read(1)); local receipt=Receipts.find(saved,'companion',service.sessionId,req.requestId)
            assert(saved.scrap==37 and saved.players.companion.health==10 and saved.players.host.health==6)
            assert(receipt.response.revision==reply.revision and receipt.response.durable)
            assert(receipt.response.result.completed and #saved.coop.checkpoints.receipts==1)
            assert(writes==2 and Schema.validate(saved))
        ''')

    def test_failed_checkpoint_accepts_once_blocks_mutations_and_retries_only_io(self):
        self.lua.execute('''
            local req=request(); allowed=false
            local reply=execute(req)
            assert(reply.ok and not reply.durable and reply.savePending and data.scrap==37 and applies==1)
            assert(Save.read(1).scrap==40 and service:checkpointStatus().pending)
            local again=execute(req); assert(again.ok and not again.durable and applies==1)
            local blocked=assert(Schema.copy(req)); blocked.requestId=2
            assert(execute(blocked).reason=='save_pending' and applies==1)
            assert(not service:prepareRequest('host','radio.station',{}))
            assert(not service:retryCheckpoint() and applies==1)
            allowed=true; assert(service:retryCheckpoint() and not service:checkpointStatus().pending)
            assert(execute(req).durable and applies==1 and Save.read(1).scrap==37)
        ''')

    def test_conflicting_replay_and_unbound_queries_cannot_claim_other_actor_receipts(self):
        self.lua.execute('''
            local req=request(); assert(execute(req).durable)
            local fp=fingerprint(req); local conflict=assert(Schema.copy(req)); conflict.args.reward='coal'
            assert(execute(conflict).reason=='request_conflict' and applies==1)
            assert(service:receipt('host',0,req.sessionId,req.requestId,fp).reason=='receipt_unavailable')
            assert(service:receipt('companion',2,req.sessionId,req.requestId,fp).reason=='unbound_peer')
            assert(service:receipt('companion',1,req.sessionId,req.requestId,'wrong').reason=='request_conflict')
            service:disconnect('companion',1)
            assert(service:receipt('companion',1,req.sessionId,req.requestId,fp).reason=='unbound_peer')
            service:admit('companion',2)
            assert(service:receipt('companion',2,req.sessionId,req.requestId,fp).durable)
        ''')

    def test_restart_uses_new_session_and_reads_receipt_without_reexecuting(self):
        self.lua.execute('''
            local req=request(); assert(execute(req).durable)
            data=assert(Save.read(1)); service=create(data)
            assert(service.sessionId~=req.sessionId and data.coop.checkpoints.sessionSerial==2)
            assert(execute(req).reason=='wrong_session' and applies==1)
            local receipt=service:receipt('companion',1,req.sessionId,req.requestId,fingerprint(req))
            assert(receipt.durable and receipt.result.completed and data.scrap==37)
        ''')

    def test_initial_write_failure_blocks_session_until_preflight_is_confirmed(self):
        self.lua.execute('''
            allowed=false; service=create(data)
            assert(service:checkpointStatus().pending and not service:prepareRequest('companion','quest.help',{}))
            allowed=true; assert(service:retryCheckpoint())
            assert(Save.read(1).coop.checkpoints.sessionSerial==2)
            assert(execute(request()).durable and applies==1)
        ''')

    def test_old_authority_cannot_write_after_a_new_session_owns_the_same_campaign(self):
        self.lua.execute('''
            local old=service; local req=request(); allowed=false
            assert(execute(req).savePending)
            allowed=true; service=create(data)
            local before=writes
            assert(not old:retryCheckpoint() and writes==before)
            assert(old:execute('companion',1,req).reason=='stale_authority')
            assert(not old:prepareRequest('host','radio.station',{}))
            assert(old:receipt('companion',1,req.sessionId,req.requestId,fingerprint(req)).reason=='stale_authority')
            assert(service:receipt('companion',1,req.sessionId,req.requestId,fingerprint(req)).durable)
        ''')

    def test_failed_new_session_preflight_cannot_certify_an_old_unsaved_receipt(self):
        self.lua.execute('''
            local req=request(); allowed=false
            assert(execute(req).savePending and Save.read(1).scrap==40)
            service=create(data)
            local receipt=service:receipt('companion',1,req.sessionId,req.requestId,fingerprint(req))
            assert(receipt.ok and receipt.savePending and not receipt.durable and applies==1)
            allowed=true; assert(service:retryCheckpoint() and Save.read(1).scrap==37)
            assert(service:receipt('companion',1,req.sessionId,req.requestId,fingerprint(req)).durable and applies==1)
            local nextReq=request(); allowed=false; assert(execute(nextReq).savePending)
            assert(service:receipt('companion',1,req.sessionId,req.requestId,fingerprint(req)).durable)
        ''')

    def test_throwing_checkpoint_never_rolls_back_an_already_applied_receipt(self):
        self.lua.execute('''
            local req=request(); local writer=service.checkpoint
            service.checkpoint=function() error('injected I/O exception') end
            local reply=execute(req)
            assert(reply.ok and reply.savePending and not reply.durable and data.scrap==37)
            assert(execute(req).savePending and applies==1)
            service.checkpoint=writer; assert(service:retryCheckpoint() and execute(req).durable and applies==1)
        ''')

    def test_exhausted_session_counter_and_oversized_prefix_reject_before_mutation(self):
        self.lua.execute('''
            local before=data.coop.checkpoints.sessionSerial
            local ok=pcall(Authority.new,{campaign=data,sessionId=string.rep('s',54),checkpoint=function() return true end})
            assert(not ok and data.coop.checkpoints.sessionSerial==before)
            data.coop.checkpoints.sessionSerial=Receipts.MAX_SEQUENCE
            assert(not pcall(create,data) and data.coop.checkpoints.sessionSerial==Receipts.MAX_SEQUENCE)
        ''')

    def test_schema_and_receipt_rejection_roll_back_before_payment(self):
        self.lua.execute('''
            local before=files[Save.path(1)]
            assert(execute(request(nil,{raise=true})).reason=='handler_error')
            assert(data.scrap==40 and #data.coop.checkpoints.receipts==0 and files[Save.path(1)]==before)
            assert(execute(request(nil,{reward=string.rep('x',100)})).ok)
            local previous=data.scrap
            service:register('quest.deliver',function(draft)
                return {scopes={'resources'},apply=function() draft.scrap=0; return {text=string.rep('x',2000)} end}
            end)
            local req=assert(service:prepareRequest('host','quest.deliver',{}))
            assert(execute(req,'host').reason=='invalid_receipt' and data.scrap==previous)
        ''')

    def test_journal_is_bounded_and_evicted_old_requests_still_cannot_execute(self):
        self.lua.execute('''
            data.scrap=1000
            local first
            for index=1,70 do local req=request(); first=first or req; assert(execute(req).durable) end
            assert(#data.coop.checkpoints.receipts==Receipts.MAX_COUNT and Schema.validate(data))
            assert(service:receipt('companion',1,first.sessionId,first.requestId,fingerprint(first)).reason=='receipt_unavailable')
            assert(execute(first).reason=='expired_request' and applies==70)
            local restored=assert(Save.read(1)); service=create(restored)
            assert(execute(first).reason=='wrong_session' and applies==70)
        ''')

    def test_radio_and_committed_placement_are_durable_but_lease_renewal_is_not(self):
        self.lua.execute('''
            local req=assert(service:prepareRequest('host','radio.station',{}))
            local reply=execute(req,'host')
            assert(reply.ok and reply.durable and not reply.savePending and writes==2)
            assert(#data.coop.checkpoints.receipts==1)
            assert(not Receipts.required('decoration.acquire',{},{}))
            assert(not Receipts.required('decoration.place',{values={}},{}))
            assert(Receipts.required('decoration.place',{values={x=20}},{}))
            assert(not Receipts.required('activity.release',{},{}))
            assert(Receipts.required('outfit.craft',{action='start'},{}))
            assert(Receipts.required('outfit.craft',{action='collect'},{}))
            assert(not Receipts.required('outfit.craft',{action='point'},{}))
            assert(Receipts.required('event.choose',{},{}))
        ''')

    def test_corrupt_receipts_are_rejected_without_silent_repair(self):
        self.lua.execute('''
            assert(execute(request()).durable)
            for _,mutate in ipairs({
                function(d) d.coop.checkpoints.receipts[1].actorId='stranger' end,
                function(d) d.coop.checkpoints.receipts[1].response.durable=false end,
                function(d) d.coop.checkpoints.receipts[1].response.revision=100 end,
                function(d) d.coop.checkpoints.receipts[1].fingerprint='code()' end,
                function(d) d.coop.checkpoints.sessionSerial=0 end,
                function(d) d.coop.checkpoints.receipts[3]=d.coop.checkpoints.receipts[1] end,
                function(d) d.coop.checkpoints.receipts[1].response.forged=true end,
            }) do local value=assert(Schema.copy(data)); mutate(value); assert(not Schema.validate(value) and not Schema.migrate(value)) end
        ''')

    def test_ambiguous_primary_failure_recovers_cost_and_receipt_together(self):
        self.lua.execute('''
            local req=request(); local write=fs.write
            fs.write=function(path,text)
                if path==Save.path(1) then files[path]='broken'; return false end
                return write(path,text)
            end
            local reply=execute(req); assert(reply.ok and not reply.durable and applies==1)
            fs.write=write
            data=assert(Save.read(1)); assert(data.scrap==37 and #data.coop.checkpoints.receipts==1)
            service=create(data)
            assert(service:receipt('companion',1,req.sessionId,req.requestId,fingerprint(req)).durable)
            assert(execute(req).reason=='wrong_session' and applies==1)
        ''')

    def test_stale_but_valid_primary_cannot_produce_a_durable_response(self):
        self.lua.execute('''
            local req=request(); local write=fs.write
            fs.write=function(path,text) if path==Save.path(1) then return true end; return write(path,text) end
            local reply=execute(req); assert(reply.ok and reply.savePending and not reply.durable)
            assert(service:receipt('companion',1,req.sessionId,req.requestId,fingerprint(req)).durable==false)
            fs.write=write; assert(service:retryCheckpoint() and execute(req).durable and applies==1)
        ''')


if __name__ == '__main__':
    unittest.main()
