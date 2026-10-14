"""Bounded transfers and durable connection identity; no real save paths."""
from pathlib import Path
import hashlib
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class LanFoundationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.globals().pythonHash = lambda value: hashlib.sha256(value.encode('utf-8')).hexdigest()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            P=require('game.net.protocol'); B=require('game.net.baseline')
            Codec=require('game.net.codec'); Identity=require('game.net.identity')
            function hash(value) return pythonHash(value) end
            function valid(value) return value.kind=='test' end
            function snapshot(size) return {kind='test',revision=7,sceneEpoch=2,body=string.rep('x',size or 19000)} end
            function transfer(value) return assert(B.pack(value or snapshot(),1,hash)) end
        ''')

    def test_chunks_are_bounded_and_only_complete_valid_snapshot_is_published(self):
        self.lua.execute('''
            local sender=transfer(); local r=assert(B.receiver(sender.header,10,valid,hash))
            local first=sender:next(); local second=sender:next(); local third=sender:next()
            assert(first and second and third and not sender:next())
            for _,part in ipairs({third,first,second}) do
                local wire=assert(P.encode(part,P.STATE)); assert(#wire<=P.CHUNK_BYTES)
                assert(P.decode(wire,P.STATE).index==part.index)
            end
            assert(r:push(third,11)==false and r:push(third,12)==false and r.count==1)
            assert(r:push(first,13)==false)
            local result=assert(r:push(second,14))
            assert(result.body==snapshot().body and result.revision==7 and next(r.parts)==nil)
            local value,reason=r:push(second,14); assert(not value and reason=='transfer_closed')
        ''')

    def test_bad_chunk_conflicts_abort_and_free_memory(self):
        self.lua.execute('''
            local sender=transfer(); local r=assert(B.receiver(sender.header,0,valid,hash))
            local first=sender:next(); assert(r:push(first,1)==false)
            first.data=string.rep('00',P.PART_BYTES)
            local result,reason=r:push(first,2)
            assert(not result and reason=='conflicting_part' and r.closed and not next(r.parts))
            sender=transfer(); r=assert(B.receiver(sender.header,0,valid,hash))
            first=sender:next(); first.data='not hex'
            assert(not r:push(first,1) and r.closed and not next(r.parts))
        ''')

    def test_timeout_and_invalid_clocks_cannot_keep_a_transfer_alive(self):
        self.lua.execute('''
            local sender=transfer(); local r=assert(B.receiver(sender.header,0,valid,hash))
            assert(r:push(sender:next(),1)==false)
            local result,reason=r:push(sender:next(),30)
            assert(not result and reason=='baseline_timeout' and not next(r.parts))
            assert(not B.receiver(sender.header,0/0,valid,hash))
            assert(not B.receiver(sender.header,0,nil,hash))
            r=assert(B.receiver(sender.header,0,valid,hash))
            assert(not r:push(transfer():next(),math.huge))
        ''')

    def test_header_integrity_checksums_shape_and_validator_exceptions(self):
        self.lua.execute('''
            local sender=transfer(snapshot(1)); local header=sender.header
            local r=assert(B.receiver(header,0,valid,hash)); header.hash=string.rep('0',64)
            assert(r:push(sender:next(),1)) -- receiver owns a detached header
            sender=transfer(snapshot(1)); sender.header.hash=string.rep('0',64)
            r=assert(B.receiver(sender.header,0,valid,hash))
            local result,reason=r:push(sender:next(),1); assert(not result and reason=='baseline_checksum')
            sender=transfer(snapshot(1)); sender.header.parts=2; assert(not B.receiver(sender.header,0,valid,hash))
            for _,validator in ipairs({function() error('bad content') end,function() return 'truthy' end}) do
                sender=transfer(snapshot(1)); r=assert(B.receiver(sender.header,0,validator,hash))
                assert(not r:push(sender:next(),1))
            end
            assert(not B.pack('not a DTO',1,hash))
            assert(not B.pack({revision=1,sceneEpoch=0},1,hash))
            assert(not B.pack(snapshot(),1,function() error('hash failure') end))
            local bytes=assert(Codec.encode(42)); local text=(bytes:gsub('.',function(c) return string.format('%02x',c:byte()) end))
            r=assert(B.receiver(P.message('baseline',{id=1,bytes=#bytes,parts=1,revision=7,sceneEpoch=2,hash=hash(bytes)}),0,valid,hash))
            assert(not r:push(P.message('part',{id=1,index=1,data=text}),1))
        ''')

    def test_wire_decode_limits_and_invalid_channels(self):
        self.lua.execute('''
            assert(not P.encode({},99) and not P.decode('a',99))
            assert(not P.decode(string.rep('x',1201),0))
            assert(not P.decode(string.rep('x',16385),2))
            assert(not P.encode({payload=string.rep('x',257)},0))
            assert(not P.decode('return os.execute("no")',0))
            assert(not P.integer(0/0,0,100) and not P.integer(math.huge,0,100))
        ''')

    def test_manual_addresses_retain_picture_shop_validation(self):
        self.lua.execute('''
            local A=require('game.net.address')
            assert(A.parse('127.0.0.1').endpoint=='127.0.0.1:22124')
            assert(A.parse('192.168.1.8:22129').endpoint=='192.168.1.8:22129')
            assert(A.parse('friend-pc').endpoint=='friend-pc:22124')
            for _,bad in ipairs({'http://host','255.255.255.255','224.1.2.3','192.168.1.999','host:0','host:65536','a'..string.char(10)..'b'}) do
                assert(not A.parse(bad),bad)
            end
        ''')

    def test_identity_rejects_credential_leaks_and_only_exact_token_matches(self):
        self.lua.execute('''
            local c={campaignId=string.rep('a',32),companionId=string.rep('b',32),token=string.rep('c',64)}
            local n={version=1,campaignId=c.campaignId,companionId=c.companionId,credentialHash=hash(c.token),bindingVersion=1}
            local data={coop={network=n},players={companion={}}}
            assert(Identity.validate(data) and Identity.matches(n,c,hash))
            c.token=string.rep('d',64); assert(not Identity.matches(n,c,hash))
            assert(not Identity.matches(n,c,function() error('unavailable') end))
            n.token=c.token; assert(not Identity.validate(data)); n.token=nil
            n.companionId=nil; assert(not Identity.validate(data))
        ''')


class ConnectionCommandTests(unittest.TestCase):
    def setUp(self):
        LanFoundationTests.setUp(self)
        self.lua.execute('''
            love={math={random=math.random}}
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            Authority=require('game.coop_authority'); Connections=require('game.coop_connections')
            data=F.campaign(2,{scene='train'}); writes=0; failSave=false
            service=Authority.new({campaign=data,sessionId='identity-test',checkpoint=function(value)
                writes=writes+1; if failSave then return false end
                saved=assert(Schema.copy(value)); return true
            end})
            Connections.install(service,{catalog={characterTrait=function() return {name='cook',maxHealth=2} end},
                allowedCharacters={['cook-mouse.png']=true},placeCompanion=function(campaign)
                    if failSpawn then return false,'bad_spawn' end
                    campaign.players.companion.playerX=240; campaign.players.companion.playerY=250; return true
                end})
            cid=string.rep('a',32); pid=string.rep('b',32); secret=string.rep('c',64)
            function run(name,args) local reply=service:submitLocal(name,args or {}); assert(reply.ok,reply.reason); return reply end
            function host() return run('session.host',{campaignId=cid}) end
            function enroll() return run('session.enroll',{companionId=pid,credentialHash=hash(secret),character='cook-mouse.png'}) end
        ''')

    def test_host_enrollment_is_durable_and_rebind_retains_existing_character(self):
        self.lua.execute('''
            assert(host().durable and enroll().durable)
            assert(saved.players.companion.character=='cook-mouse.png' and saved.players.companion.playerX==240)
            local old=assert(Schema.copy(data.players.companion))
            assert(not service:submitLocal('session.enroll',{companionId=pid,credentialHash=hash(string.rep('d',64)),character='cook-mouse.png'}).ok)
            run('session.rebind',{companionId=pid,credentialHash=hash(string.rep('d',64))})
            assert(data.coop.network.bindingVersion==2 and data.players.companion.health==old.health)
            assert(data.players.companion.equipment[1]==old.equipment[1])
            assert(data.coop.network.token==nil and assert(Schema.validate(saved)))
            local fs,files=F.filesystem(); love.filesystem=fs
            local Save=require('game.save'); assert(Save.write(1,saved))
            local encoded=assert(files[Save.path(1)])
            assert(not encoded:find(secret,1,true))
            local loaded=assert(Save.read(1)); assert(loaded.coop.network.bindingVersion==2)
        ''')

    def test_enrollment_save_failure_is_pending_and_cannot_be_published(self):
        self.lua.execute('''
            host(); failSave=true; local reply=enroll()
            assert(reply.ok and not reply.durable and reply.savePending and service.pendingSave)
            assert(not saved.players.companion)
            local second=service:submitLocal('session.rebind',{companionId=pid,credentialHash=hash(string.rep('d',64))})
            assert(not second.ok and second.reason=='save_pending')
            failSave=false; assert(service:retryCheckpoint()); assert(saved.players.companion)
            assert(data.coop.network.bindingVersion==1)
        ''')

    def test_guest_and_connected_rebinding_are_denied(self):
        self.lua.execute('''
            host(); enroll(); service:admit('companion',1)
            for id,name in ipairs({'session.host','session.enroll','session.rebind'}) do
                local r=service:execute('companion',1,{sessionId=service.sessionId,requestId=id,sceneEpoch=data.coop.sceneEpoch,
                    command=name,args={},expected={}})
                assert(not r.ok and r.reason=='host_only')
            end
            local r=service:submitLocal('session.rebind',{companionId=pid,credentialHash=hash(string.rep('d',64))})
            assert(not r.ok and r.reason=='companion_connected')
        ''')

    def test_failed_spawn_rolls_back_kit_and_identity_together(self):
        self.lua.execute('''
            host(); local revision=data.coop.revision; failSpawn=true
            local r=service:submitLocal('session.enroll',{companionId=pid,credentialHash=hash(secret),character='cook-mouse.png'})
            assert(not r.ok and r.reason=='bad_spawn' and not data.players.companion)
            assert(data.coop.revision==revision and data.coop.network.bindingVersion==0)
            failSpawn=false; assert(enroll().durable)
        ''')

    def admission(self):
        self.lua.execute('''
            local sequence=0
            tokenProvider=function(bytes) sequence=sequence+1; return string.format('%0'..(bytes*2)..'x',sequence) end
            Admission=require('game.coop_admission')
            adapter=assert(Admission.new(service,{token=tokenProvider,hash=hash}))
            request={generation=1,name='Friend',character='cook-mouse.png'}
        ''')

    def test_admission_only_publishes_credential_after_pending_checkpoint_is_retried(self):
        self.admission()
        self.lua.execute('''
            failSave=true
            local credential,reason=adapter:issue(request)
            assert(not credential and reason=='save_not_ready' and not adapter:preflight())
            local retained=adapter.pending.credential; local item=data.players.companion.itemSlots.equipment[1].id
            assert(not adapter:authenticate(retained) and not Admission.new(service,{}))
            failSave=false; assert(service:retryCheckpoint())
            assert(adapter:issue(request).token==retained.token and adapter:authenticate(retained))
            assert(data.coop.network.bindingVersion==1 and data.players.companion.itemSlots.equipment[1].id==item)
            local count=writes; assert(adapter:issue(request).token==retained.token and writes==count)
        ''')

    def test_explicit_rebind_rotates_credential_without_replacing_companion(self):
        self.admission()
        self.lua.execute('''
            local first=assert(adapter:issue(request)); local item=data.players.companion.itemSlots.equipment[1].id
            data.players.companion.health=6
            adapter:forgetPending(1); request.generation=2; request.character='unavailable-other-character.png'
            local second=assert(adapter:issue(request))
            assert(second.companionId==first.companionId and second.token~=first.token)
            assert(not adapter:authenticate(first) and adapter:authenticate(second))
            assert(data.players.companion.health==6 and data.players.companion.itemSlots.equipment[1].id==item)
            assert(data.players.companion.character=='cook-mouse.png' and saved.coop.network.bindingVersion==2)
            adapter:forgetPending(1); assert(adapter.pending)
            adapter:forgetPending(2); assert(not adapter.pending)
        ''')

    def test_unavailable_entropy_or_hash_never_creates_an_insecure_binding(self):
        self.admission()
        self.lua.execute('''
            local count=writes; local provider=adapter.token
            adapter.token=function() return nil end
            local credential,reason=adapter:issue(request)
            assert(not credential and reason=='entropy_unavailable' and not data.players.companion and writes==count)
            adapter.token=provider; adapter.hash=function() error('missing native provider') end
            credential,reason=adapter:issue(request)
            assert(not credential and reason=='hash_unavailable' and writes==count)
        ''')

    def test_legacy_companion_receives_identity_without_a_second_starter_kit(self):
        self.lua.execute('''
            assert(F.enroll(data)); legacyItem=data.players.companion.itemSlots.equipment[1].id
            data.players.companion.health=3
        ''')
        self.admission()
        self.lua.execute('''
            local credential=assert(adapter:issue(request))
            assert(adapter:authenticate(credential) and data.players.companion.health==3)
            assert(data.players.companion.itemSlots.equipment[1].id==legacyItem)
        ''')

    def test_stale_authority_cannot_authenticate_after_another_save_session_takes_over(self):
        self.admission()
        self.lua.execute('''
            local credential=assert(adapter:issue(request))
            local replacement=Authority.new({campaign=data,sessionId='replacement',checkpoint=function() return true end})
            assert(not adapter:preflight() and not adapter:authenticate(credential))
            assert(not adapter:issue(request))
        ''')


if __name__ == '__main__':
    unittest.main()
