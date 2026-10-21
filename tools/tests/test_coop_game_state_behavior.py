"""Production projection, sparse state, atomic deltas and save separation."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GameStateTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            State=require('game.net.game_state'); R=require('game.net.state_records'); Codec=require('game.net.codec')
            Players=require('game.coop_players'); Entities=require('game.coop_entities'); Items=require('game.item_instances')
            data=F.campaign(2,{scene='train'}); assert(F.enroll(data))
            data.players.companion.playerX=240; data.players.companion.playerY=250
            producer=State.producer(); replica=State.replica()
            function capture(full) local message,reason=producer:capture(data,full); assert(message,reason); return message end
            function apply(message) local ok,reason=replica:apply(message); assert(ok,reason) end
        ''')

    def test_sparse_slots_numeric_keys_and_both_actor_views_roundtrip(self):
        self.lua.execute('''
            data.visitedStops[50]=true
            data.events.example={[0]='zero',[3]='third',named={[-1]=false}}
            local message=capture(); apply(message)
            assert(replica.data.players.host.inventory[1]=='orange-rose-vase' and replica.data.players.host.inventory[2]==nil)
            assert(replica.data.players.host.inventory[4]=='cowboy-hat' and replica.data.visitedStops[50])
            assert(replica.data.events.example[0]=='zero' and replica.data.events.example[3]=='third')
            assert(replica.data.events.example.named[-1]==false)
            assert(replica:actor().character=='cook-mouse.png' and replica:actor('host').character=='scout-frog.png')
            assert(replica.data.players.companion.itemSlots.equipment[1].id==data.players.companion.itemSlots.equipment[1].id)
            assert(not getmetatable(replica.data))
        ''')

    def test_staged_snapshot_validates_once_and_commits_only_detached_data(self):
        self.lua.execute('''
            local calls=0; local prepare=replica.prepare
            replica.prepare=function(self,message) calls=calls+1; return prepare(self,message) end
            local message=capture(); local commit=assert(replica:stage(message))
            assert(calls==1 and replica.data==nil and replica.revision==0)
            message.domains={}; message.sceneEpoch=999
            assert(commit() and calls==1 and replica.sceneEpoch==data.coop.sceneEpoch)
            assert(replica:actor().character=='cook-mouse.png')
            assert(not commit())
        ''')

    def test_staged_delta_cannot_overwrite_a_newer_replica(self):
        self.lua.execute('''
            apply(capture()); data.scrap=data.scrap+1
            local delta=capture(); local commit=assert(replica:stage(delta))
            apply(delta); local current=replica.data; local revision=replica.revision
            local ok,reason=commit()
            assert(not ok and reason=='stale_staged_replica' and replica.data==current and replica.revision==revision)
            local corrupt=capture(true); corrupt.domains={}
            assert(not replica:stage(corrupt) and replica.data==current)
        ''')

    def test_secrets_receipts_device_preferences_and_allocation_counters_are_absent(self):
        self.lua.execute('''
            data.coop.network={version=1,campaignId=string.rep('a',32),companionId=string.rep('b',32),
                credentialHash=string.rep('c',64),bindingVersion=1}
            data.coop.randomState=9834567
            data.audio.musicVolume=.923; data.audio.station='8bit'; data.audio.rainEnabled=true
            data.accessibility.textSize=1.4
            local message=capture(); apply(message)
            local bytes=assert(Codec.encode(message,{maxBytes=8388608,maxEntries=200000,maxStringBytes=8192,maxDepth=16}))
            for _,secret in ipairs({'credentialHash','network','musicVolume','accessibility','randomState','itemIdentity',string.rep('c',64)}) do
                assert(not bytes:find(secret,1,true),secret)
            end
            assert(replica.data.audio.station=='8bit' and replica.data.audio.rainEnabled)
            assert(not replica.data.coop.network and not replica.data.coop.checkpoints and not replica.data.itemIdentity)
        ''')

    def test_receiver_cannot_save_a_replica_or_its_local_actor_view(self):
        self.lua.execute('''
            apply(capture()); local fs,files=F.filesystem(); love.filesystem=fs
            local Save=require('game.save')
            local ok,reason=Save.write(1,replica.data); assert(not ok and not next(files))
            assert(not Schema.migrate(replica.data))
            assert(not Save.write(1,replica:actor()) and not next(files))
            assert(not State.project(replica.data))
        ''')

    def test_real_inventory_command_sends_only_changed_domains_and_noop_sends_nothing(self):
        self.lua.execute('''
            local Authority=require('game.coop_authority')
            local service=Authority.new({campaign=data,sessionId='replica-test'})
            require('game.coop_inventory').install(service,{catalog=require('game.catalog'),car={x=0,y=0},
                actorState=function() return {screen='game',scene='train',x=200,y=250} end})
            apply(capture()); assert(producer:capture(data)==nil)
            local response=service:submitLocal('inventory.swap',{source={kind='inventory',index=1},target={kind='inventory',index=2}})
            assert(response.ok,response.reason)
            local delta=capture(); assert(delta.mode=='delta' and #delta.domains==2)
            local changed={}; for _,domain in ipairs(delta.domains) do changed[domain.id]=true end
            assert(changed['actor:host'] and changed.authority and not changed.world)
            apply(delta)
            assert(replica.data.players.host.inventory[1]==nil and replica.data.players.host.inventory[2]=='orange-rose-vase')
            assert(replica.data.coop.revision==data.coop.revision and producer:capture(data)==nil)
        ''')

    def test_gaps_stale_epochs_and_partial_baselines_do_not_mutate_current_state(self):
        self.lua.execute('''
            local initial=capture(); apply(initial)
            data.scrap=data.scrap+1; local second=capture()
            data.scrap=data.scrap+1; local third=capture()
            assert(not replica:apply(third) and replica.revision==1)
            apply(second); apply(third); assert(replica.data.scrap==data.scrap)
            assert(not replica:apply(second) and not replica:apply(initial) and replica.revision==3)
            data.coop.sceneEpoch=2; local scene=capture()
            assert(scene.mode=='baseline' and #scene.domains==11)
            table.remove(scene.domains); assert(not replica:apply(scene) and replica.sceneEpoch==1)
            apply(assert(producer:baseline())); assert(replica.sceneEpoch==2)
        ''')

    def test_invalid_item_identity_rejects_whole_update_without_losing_prior_state(self):
        self.lua.execute('''
            apply(capture()); local old=replica.data
            data.scrap=400; local delta=capture()
            local train
            for _,domain in ipairs(delta.domains) do if domain.id=='train' then train=domain end end
            local value=assert(R.decode(train.record)); value.resources.food=-1; train.record=assert(R.encode(value))
            assert(not replica:apply(delta) and replica.data==old and replica.data.scrap==40)
            local recovery=assert(producer:baseline()); apply(recovery)
            local actor=data.players.companion
            actor.itemSlots.equipment[1].id=data.players.host.itemSlots.equipment[1].id
            assert(not producer:capture(data) and producer.revision==2)
        ''')

    def test_projection_fails_closed_for_unclassified_fields_or_nested_secrets(self):
        self.lua.execute('''
            data.unclassifiedFeature={count=1}
            local packet,reason=producer:capture(data)
            assert(not packet and reason=='unclassified_campaign_field:unclassifiedFeature' and producer.revision==0)
            data.unclassifiedFeature=nil; data.players.host.newField=5
            assert(not producer:capture(data)); data.players.host.newField=nil
            data.events.example={credentialHash=string.rep('a',64)}
            assert(not producer:capture(data) and producer.revision==0)
            for field in pairs(Players.personalFields) do assert(State.manifest.actorAllowed[field],field) end
        ''')

    def test_mutating_ui_view_does_not_change_the_cached_authoritative_records(self):
        self.lua.execute('''
            apply(capture()); replica.data.resources.food=999; replica.data.players.companion.health=0
            replica.data.coop.revision=999999; replica.data.coop.revisions.injected=999999
            data.scrap=81; apply(capture())
            assert(replica.data.resources.food==data.resources.food and replica.data.players.companion.health==data.players.companion.health)
            assert(data.scrap==replica.data.scrap)
        ''')

    def test_authority_and_scope_revisions_cannot_move_backwards_in_a_new_baseline(self):
        self.lua.execute('''
            data.coop.revision=5; data.coop.revisions.party=5; apply(capture())
            local message=capture(true)
            for _,domain in ipairs(message.domains) do
                if domain.id=='authority' then
                    local value=assert(R.decode(domain.record)); value.sourceRevision=4; domain.record=assert(R.encode(value))
                end
            end
            local ok,reason=replica:apply(message); assert(not ok and reason=='authority_regressed' and replica.revision==1)
            message=assert(producer:baseline())
            for _,domain in ipairs(message.domains) do
                if domain.id=='authority' then
                    local value=assert(R.decode(domain.record)); value.scopes.party=4; domain.record=assert(R.encode(value))
                end
            end
            ok,reason=replica:apply(message); assert(not ok and reason=='scope_regressed' and replica.revision==1)
        ''')

    def test_generated_fifty_stop_world_fits_bounded_wire_and_preserves_last_stop(self):
        self.lua.execute('''
            local Stops=require('game.stops'); local Catalog=require('game.catalog')
            data.npcRoster={'cook-mouse.png','scout-frog.png'}
            for stop=1,50 do data.location=stop; Stops.ensure(data,Catalog,'stop') end
            data.location=50; assert(Entities.ensure(data)); assert(Items.ensure(data))
            local message=capture(); local bytes=assert(Codec.encode(message,{maxBytes=8388608,maxEntries=200000,maxStringBytes=8192,maxDepth=16}))
            assert(#bytes>16384 and #bytes<8388608); apply(message)
            assert(replica.data.location==50 and replica.data.stopLayouts['50'].entityId==data.stopLayouts['50'].entityId)
            assert(replica.data.conversations.assignments['50']==nil or replica.data.conversations.assignments['50'].id==data.conversations.assignments['50'].id)
            wireSize=#bytes
        ''')


class RecordTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute("package.path=root..'/?.lua;'..package.path; R=require('game.net.state_records')")

    def test_cycles_aliases_sparse_shapes_and_budget_exhaustion(self):
        self.lua.execute('''
            local shared={x=1}; local input={[0]='zero',[9]=false,a=shared,b=shared}
            local decoded=assert(R.decode(assert(R.encode(input))))
            assert(decoded[0]=='zero' and decoded[9]==false and decoded.a~=decoded.b)
            input.cycle=input; assert(not R.encode(input)); input.cycle=nil
            assert(not R.encode(input,{nodes=R.MAX_NODES,entries=0}))
            assert(not R.encode(input,{nodes=0,entries=R.MAX_ENTRIES}))
            assert(not R.encode({value=string.rep('x',R.MAX_STRING+1)}))
            assert(not R.encode({fn=function() end}))
        ''')

    def test_receiver_rejects_duplicate_keys_forward_aliases_cycles_and_orphans(self):
        self.lua.execute('''
            for _,record in ipairs({
                {nodes={{{key='a',value=1},{key='a',value=2}}}},
                {nodes={{{key='a',ref=2},{key='b',ref=2}}, {}}},
                {nodes={{{key='a',ref=1}}}},
                {nodes={{},{}}},
                {nodes={{{key='x',ref=2,value=1}}, {}}},
                {nodes={{{key='x',ref=2}},{{key='y',ref=1}}}},
                {nodes={{{key='token',value='secret'}}}},
            }) do assert(not R.decode(record)) end
            local nested={}; local cursor=nested
            for _=1,R.MAX_DEPTH do cursor.child={}; cursor=cursor.child end
            assert(not R.encode(nested))
        ''')

if __name__ == '__main__':
    unittest.main()
