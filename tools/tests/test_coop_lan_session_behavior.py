"""Admission sequencing over the independently impaired transport fixture."""
from pathlib import Path
import hashlib
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class LanSessionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.globals().pythonHash = lambda value: hashlib.sha256(value.encode('utf-8')).hexdigest()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Session=require('game.net.session'); P=require('game.net.protocol'); Identity=require('game.net.identity')
            Lab=require('tools.tests.lua.coop_network_harness'); Store=require('game.net.credential_store')
            lab=assert(Lab.new({maxClients=2})); clock=0; revision=7; epoch=2; saved=true; saveCredential=true
            applied=0; admitted=0; issued=0; disconnected=0
            credential={campaignId=string.rep('a',32),companionId=string.rep('b',32),token=string.rep('c',64)}
            function hash(value) return pythonHash(value) end
            hostContext={transport=assert(lab.factory.createHost({})),build=string.rep('d',64),schema=38,sessionId='test-session',campaignId=credential.campaignId,
                clock=function() return clock end,hash=hash,preflight=function() return saved end,
                authenticate=function(value)
                    if knownCredential and value.token==knownCredential.token then
                        return {campaignId=value.campaignId,companionId=value.companionId}
                    end
                end,
                issue=function() issued=issued+1; knownCredential=credential; return credential end,
                snapshot=function() return {revision=revision,sceneEpoch=epoch,kind='readonly-test',payload=string.rep('x',14336)} end,
                revision=function() return revision,epoch end,
                ready=function(generation) admitted=admitted+1; admittedGeneration=generation; return true end,
                disconnected=function() disconnected=disconnected+1 end}
            host=assert(Session.host(hostContext))
            function join(value,options)
                local context={transport=assert(lab.factory.createClient('test-host',{})),build=hostContext.build,schema=38,
                    name='Friend',character='cook-mouse.png',clock=hostContext.clock,credential=value,hash=hash,
                    validate=function(s) return s.kind=='readonly-test' and type(s.payload)=='string' end,
                    store=function(c) if not saveCredential then return false end; stored=c; return true end,
                    apply=function(s) applied=applied+1; return s.kind=='readonly-test' end}
                for key,item in pairs(options or {}) do context[key]=item end
                return assert(Session.join('test-host',context))
            end
            guest=join()
            function step(count)
                for _=1,count or 1 do clock=clock+.01; host:update(); guest:update(); lab:advanceSteps(1) end
            end
            function approve()
                step(3); local pending=assert(host:pending()); assert(host:approve(pending.generation)); return pending.generation
            end
            function ready()
                approve(); step(8); assert(guest.status=='ready',guest.reason or guest.status)
                assert(host.link.phase=='ready' and admitted==1 and applied==1)
            end
        ''')

    def tearDown(self):
        self.lua.execute('''
            if guest then guest:close() end
            if extra then extra:close() end
            if host then host:close() end
            assert(lab:dispose() and lab:isQuiescent())
        ''')

    def test_approval_credential_write_baseline_and_ready_are_ordered(self):
        self.lua.execute('''
            step(3); assert(guest.status=='approval' and not guest.snapshot and admitted==0 and applied==0)
            local pending=assert(host:pending()); assert(not pending.token and not pending.credential)
            assert(host:approve(pending.generation)); guest:update()
            assert(stored and guest.status=='snapshot' and not guest.snapshot and applied==0)
            host:update(); guest:update()
            assert(not guest.snapshot and applied==0)
            step(8); assert(guest.status=='ready' and host.link.phase=='ready' and applied==1 and admitted==1)
            assert(guest.snapshot.revision==7 and #guest.snapshot.payload==14336)
        ''')

    def test_service_does_not_capture_world_state_before_explicit_publication(self):
        self.lua.execute('''
            ready(); local captures=0
            hostContext.update=function()
                captures=captures+1
                return {revision=revision,sceneEpoch=epoch,kind='readonly-test',payload='after-world'}
            end
            clock=clock+.2; host:service(); assert(captures==0)
            revision=8; host:publish(); assert(captures==1)
            assert(host.link.transfer.header.revision==8)
            for _=1,8 do host:service(); host:publish(); guest:update(); lab:advanceSteps(1) end
            assert(guest.snapshot.revision==8 and guest.snapshot.payload=='after-world' and applied==2)
        ''')

    def test_service_keeps_peer_timeout_active_without_world_publication(self):
        self.lua.execute('''
            ready(); clock=clock+16; host:service()
            assert(not host.link and disconnected==1)
        ''')

    def test_rejoin_uses_saved_identity_without_issuing_another_kit(self):
        self.lua.execute('''
            ready(); local first=admittedGeneration; guest:close(); host:update()
            guest=join(stored); step(12)
            assert(guest.status=='ready',guest.reason or guest.status)
            assert(not host:pending() and issued==1 and admitted==2 and admittedGeneration>first)
            assert(disconnected==1)
        ''')

    def test_wrong_build_and_executable_or_oversized_packets_never_admit(self):
        self.lua.execute('''
            guest:close(); host:update(); guest=join(nil,{build=string.rep('0',64)})
            step(5); assert(guest.closed and issued==0 and admitted==0 and applied==0)
            guest=join(); guest:update(); host:update()
            assert(guest.transport:sendToServer(string.rep('x',1201),0,true))
            host:update(); assert(not host.link and admitted==0 and issued==0)
        ''')

    def test_second_peer_cannot_replace_a_pending_or_ready_companion(self):
        self.lua.execute('''
            step(3); local generation=host:pending().generation
            extra=join(); extra:update(); host:update(); extra:update()
            assert(extra.closed and host:pending().generation==generation and issued==0)
            assert(host:approve(generation)); step(10); assert(guest.status=='ready')
            extra=join(); extra:update(); host:update(); extra:update()
            assert(extra.closed and host.link.generation==generation and admitted==1)
        ''')

    def test_save_barrier_and_guest_credential_write_failure_prevent_ready(self):
        self.lua.execute('''
            step(3); saved=false
            local result,reason=host:approve(host:pending().generation)
            assert(not result and reason=='save_not_ready' and issued==0)
            saved=true; saveCredential=false; assert(host:approve(host:pending().generation)); step(5)
            assert(guest.closed and guest.reason=='credential_not_saved' and admitted==0 and applied==0)
        ''')

    def test_changed_world_is_resnapshotted_before_guest_becomes_ready(self):
        self.lua.execute('''
            approve()
            for _=1,10 do
                host:update(); guest:update()
                if guest.status=='acknowledging' then break end
            end
            assert(guest.status=='acknowledging' and applied==0)
            revision=8; epoch=3; step(10)
            assert(guest.status=='ready' and guest.snapshot.revision==8 and guest.snapshot.sceneEpoch==3)
            assert(admitted==1 and applied==1 and host.snapshotId==2)
        ''')

    def test_delayed_welcome_cannot_publish_or_deliver_chunks_early(self):
        self.lua.execute('''
            step(3); lab:delayNext('host_to_client',1,4)
            assert(host:approve(host:pending().generation)); step(3)
            assert(guest.status=='approval' and host.link.phase=='credentials' and applied==0)
            step(12); assert(guest.status=='ready' and applied==1)
        ''')

    def test_forged_ack_wrong_channel_and_story_request_are_denied(self):
        self.lua.execute('''
            step(3)
            local wire=assert(P.encode(P.message('baseline_ack',{id=1,revision=7,sceneEpoch=2,hash=string.rep('f',64)}),0))
            assert(guest.transport:sendToServer(wire,0,true)); host:update()
            assert(not host.link and admitted==0)
            guest:close(); guest=join(); ready()
            assert(guest.transport:sendToServer(assert(P.encode(P.message('scene.leaveTrain'),1)),1,true))
            host:update(); assert(not host.link and disconnected==2)
        ''')

    def test_host_silence_and_abandoned_approvals_expire(self):
        self.lua.execute('''
            step(3); local generation=host:pending().generation; clock=61
            assert(not host:approve(generation)); guest:update(); assert(guest.closed and admitted==0)
            guest=join(); ready(); clock=clock+16; guest:update()
            assert(guest.closed and guest.reason=='host_timeout' and not guest.snapshot)
        ''')

    def test_heartbeats_keep_ready_connection_alive_and_disconnect_cleans_up(self):
        self.lua.execute('''
            ready()
            for _=1,20 do clock=clock+4; host:update(); guest:update(); host:update() end
            assert(not guest.closed and host.link.phase=='ready')
            host:close(); guest:update(); assert(guest.closed and not guest.snapshot and disconnected==1)
        ''')

    def test_greeting_chooses_credentials_by_campaign_and_lookup_failure_stops_join(self):
        self.lua.execute('''
            ready(); guest:close(); host:update()
            local found
            guest=join(nil,{credentialFor=function(id) found=id; return stored end})
            step(12); assert(found==credential.campaignId and guest.status=='ready' and issued==1)
            guest:close(); host:update()
            guest=join(nil,{credentialFor=function() return nil,'unreadable_store' end})
            step(4); assert(guest.closed and guest.reason=='credential_lookup_failed' and issued==1)
        ''')

    def test_invalid_snapshot_and_transport_fault_never_publish_a_partial_replica(self):
        self.lua.execute('''
            guest.context.validate=function() error('bad DTO') end
            approve(); step(10)
            assert(guest.closed and not guest.snapshot and admitted==0 and applied==0)
            guest=join(); guest.transport.serviceError='test error'; guest:update()
            assert(guest.closed and guest.reason=='transport_failed')
        ''')

    def test_live_update_keeps_old_snapshot_until_commit_and_tolerates_heartbeat_overtaking(self):
        self.lua.execute('''
            ready(); local original=guest.snapshot
            local sent=false
            hostContext.update=function()
                if sent then return nil end; sent=true; revision=8; return hostContext.snapshot()
            end
            clock=clock+5; lab:delayNext('host_to_client',1,3)
            host:update(); guest:update()
            assert(guest.status=='snapshot' and guest.snapshot==original and applied==1)
            step(12)
            assert(guest.status=='ready' and guest.snapshot.revision==8 and admitted==1 and applied==2)
            assert(not guest.closed and host.link.admitted)
        ''')

    def test_live_ack_waits_through_long_checkpoint_barrier_and_resnapshots_saved_scene(self):
        self.lua.execute('''
            ready(); local original=guest.snapshot; local sent=false; local pending=false
            hostContext.checkpointPending=function() return pending end
            hostContext.update=function()
                if sent then return nil end; sent=true; revision=8; epoch=3; return hostContext.snapshot()
            end
            clock=clock+.2
            for _=1,12 do
                host:update(); guest:update(); lab:advanceSteps(1)
                if guest.status=='acknowledging' then break end
            end
            assert(guest.status=='acknowledging' and guest.snapshot==original)
            pending=true; saved=false; revision=9; epoch=4; host:update(); guest:update()
            assert(host.link.ackDeferred and host.link.admitted and not guest.closed)
            for _=1,12 do clock=clock+4; host:update(); guest:update(); host:update() end
            assert(not guest.closed and host.link.ackDeferred and guest.snapshot==original and applied==1 and admitted==1)
            saved=true; pending=false; step(12)
            assert(host.link.phase=='ready' and not host.link.ackDeferred and not guest.closed)
            assert(guest.snapshot.revision==9 and guest.snapshot.sceneEpoch==4 and applied==2 and admitted==1 and issued==1)
        ''')

    def test_checkpoint_barrier_retains_peer_timeout_and_cannot_approve_a_new_guest(self):
        self.lua.execute('''
            ready(); hostContext.checkpointPending=function() return true end; saved=false
            clock=clock+16; host:service(); assert(not host.link and disconnected==1)
            guest:close(); saved=true; guest=join(); step(3)
            saved=false
            local ok,reason=host:approve(host:pending().generation)
            assert(not ok and reason=='save_not_ready' and issued==1 and admitted==1)
        ''')

    def test_command_opening_save_barrier_defers_ack_in_same_transport_batch(self):
        self.lua.execute('''
            local pending=false; local sent=false; local commands=0
            hostContext.checkpointPending=function() return pending end
            hostContext.commandSequence=function() return 1 end
            hostContext.command=function(generation,request)
                assert(generation==admittedGeneration and request.command=='test.critical')
                commands=commands+1; pending=true; saved=false; revision=9; epoch=4
                return {ok=true,revision=revision,savePending=true}
            end
            ready(); local original=guest.snapshot
            hostContext.update=function()
                if sent then return nil end; sent=true; revision=8; epoch=3; return hostContext.snapshot()
            end
            clock=clock+.2; host:publish()
            -- Queue the command first, then finish the live snapshot without
            -- servicing host transport. The acknowledgement joins that batch.
            assert(guest:submitCommand('test.critical',{},original.sceneEpoch,{}))
            for _=1,6 do host:publish(); guest:update(); if guest.status=='acknowledging' then break end end
            assert(guest.status=='acknowledging' and commands==0)
            host:service(); guest:update()
            assert(host.link and host.link.ackDeferred and not guest.closed,'same-batch checkpoint dropped the admitted peer')
            assert(commands==1 and guest.lastCommandResult.savePending and guest.snapshot==original)
            saved=true; pending=false; step(12)
            assert(not guest.closed and host.link.phase=='ready' and guest.snapshot.revision==9 and guest.snapshot.sceneEpoch==4)
            assert(admitted==1 and issued==1 and applied==2)
        ''')

    def test_inflight_live_update_restarts_if_scene_changes_without_readmitting_actor(self):
        self.lua.execute('''
            ready(); local sent=false
            hostContext.update=function()
                if sent then return nil end; sent=true; revision=8; return hostContext.snapshot()
            end
            clock=clock+.2; host:update(); guest:update()
            for _=1,10 do host:update(); guest:update(); if guest.status=='acknowledging' then break end end
            assert(guest.status=='acknowledging' and applied==1)
            revision=9; epoch=3; step(12)
            assert(guest.status=='ready' and guest.snapshot.revision==9 and guest.snapshot.sceneEpoch==3)
            assert(admitted==1 and applied==2)
        ''')

    def test_save_barrier_defers_updates_but_services_heartbeat(self):
        self.lua.execute('''
            ready(); local updates=0; hostContext.update=function() updates=updates+1 end
            saved=false
            for _=1,4 do clock=clock+5; host:update(); guest:update(); host:update() end
            assert(updates==0 and not guest.closed and host.link.phase=='ready')
            saved=true; clock=clock+.2; host:update(); assert(updates==1)
        ''')

    def test_host_restart_can_continue_authority_generation_sequence(self):
        self.lua.execute('''
            ready(); host:close(); guest:update()
            hostContext.transport=assert(lab.factory.createHost({})); hostContext.generationBase=8
            host=assert(Session.host(hostContext)); guest=join(); step(3)
            assert(host:pending().generation==9)
            assert(not host:approve(1) and host:approve(9)); step(10)
            assert(guest.status=='ready' and admittedGeneration==9)
        ''')

    def enable_motion(self):
        self.lua.execute('''
            Wire=require('game.net.movement'); movementCalls=0; motionFrames=0; sceneAcks=0
            hostContext.movement=function(generation,message)
                assert(generation==admittedGeneration and message.sessionId=='test-session')
                movementCalls=movementCalls+1; lastSequence=message.sequence; return true
            end
            hostContext.sceneReady=function(generation,value)
                assert(generation==admittedGeneration); sceneAcks=sceneAcks+1; return value==epoch
            end
            guest.context.motion=function(message) motionFrames=motionFrames+1; lastMotion=message; return true end
            function frame(serial)
                local actor={x=100,y=200,facing=1}; local record={activeCar=1}
                return P.message('motion',{sessionId='test-session',motionId=1,sceneEpoch=epoch,serial=serial or 1,tick=1,ack=1,
                    host=Wire.packActor(actor,record),companion=Wire.packActor(actor,record),paused=false,ready=true,ackAge=0,inputActive=true})
            end
        ''')

    def test_movement_is_unreliable_and_scene_readiness_is_reliable(self):
        self.enable_motion()
        self.lua.execute('''
            assert(not guest:sendMovement(1,epoch,1000,0,false,1)); ready()
            assert(guest:sceneReady(epoch,1)); host:update(); assert(sceneAcks==1)
            assert(lab.log[#lab.log].reliable and lab.log[#lab.log].channel==P.CONTROL)
            lab:dropNext('client_to_host',1); assert(guest:sendMovement(1,epoch,1000,0,false,1))
            host:update(); assert(movementCalls==0 and not lab.log[#lab.log].reliable)
            assert(guest:sendMovement(2,epoch,1000,0,true,1)); host:update()
            assert(movementCalls==1 and lastSequence==2)
            lab:dropNext('host_to_client',1); assert(host:sendMotion(frame())); guest:update(); assert(motionFrames==0)
            assert(host:sendMotion(frame(2))); guest:update(); assert(motionFrames==1 and lastMotion.serial==2)
            assert(not lab.log[#lab.log].reliable and lab.log[#lab.log].channel==P.REALTIME)
        ''')

    def test_motion_crosses_live_campaign_transfer_without_readmitting(self):
        self.enable_motion()
        self.lua.execute('''
            ready(); local sent=false
            hostContext.update=function() if sent then return end; sent=true; revision=8; return hostContext.snapshot() end
            clock=clock+.2; host:update(); guest:update(); assert(guest.status=='snapshot')
            assert(guest:sendMovement(1,epoch,0,1000,false,1)); host:update()
            assert(movementCalls==1 and host.link.admitted)
            assert(host:sendMotion(frame())); guest:update(); assert(motionFrames==1)
            step(12); assert(guest.status=='ready' and admitted==1 and applied==2 and not guest.closed)
        ''')

    def test_movement_flood_is_bounded_and_wrong_session_is_rejected(self):
        self.enable_motion()
        self.lua.execute('''
            ready()
            for i=1,60 do assert(guest:sendMovement(i,epoch,1000,0,false,1)) end
            host:update(); assert(movementCalls==8 and host.link)
            clock=clock+.1; assert(guest:sendMovement(61,epoch,0,0,false,1)); host:update(); assert(movementCalls==9)
            local forged=P.message('movement',{sessionId='other-session',motionId=1,sceneEpoch=epoch,sequence=62,x=0,y=0,sprint=false})
            lab:injectToHost(1,assert(P.encode(forged,P.REALTIME)),P.REALTIME)
            host:update(); assert(not host.link and movementCalls==9 and disconnected==1)
        ''')

    def test_motion_overtaking_initial_ready_is_discarded_until_baseline_commits(self):
        self.enable_motion()
        self.lua.execute('''
            approve()
            for _=1,10 do host:update(); guest:update(); if guest.status=='acknowledging' then break end end
            assert(guest.status=='acknowledging' and not guest.snapshot)
            lab:delayNext('host_to_client',1,3); host:update(); assert(host.link.admitted)
            assert(host:sendMotion(frame())); guest:update(); assert(not guest.closed and motionFrames==0)
            step(5); assert(guest.snapshot)
            assert(host:sendMotion(frame(2))); guest:update(); assert(motionFrames==1)
        ''')


    def enable_roaming(self):
        self.enable_motion()
        self.lua.execute('''
            Roaming=require('game.net.roaming'); roamingCalls=0
            guest.context.roaming=function(value) roamingCalls=roamingCalls+1; lastRoaming=value; return true end
            function roamingFrame(serial)
                return P.message('roaming_motion',{sessionId='test-session',sceneEpoch=epoch,sourceRevision=revision,
                    serial=serial or 1,areaId='test-area',paused=false,mobs={{id='mob-a',e='entity-a',x=100,y=200,
                    f=1,s=4,t=460,d=200000,h=0,v=3000,z=0,q=1,a=true}}})
            end
        ''')

    def test_enemy_motion_is_unreliable_and_independent_of_actor_packets(self):
        self.enable_roaming()
        self.lua.execute('''
            ready(); lab:dropNext('host_to_client',1); assert(host:sendRoaming(roamingFrame())); guest:update()
            assert(roamingCalls==0)
            assert(host:sendRoaming(roamingFrame(2))); assert(host:sendMotion(frame())); guest:update()
            assert(roamingCalls==1 and lastRoaming.serial==2 and motionFrames==1 and not guest.closed)
            assert(not lab.log[#lab.log].reliable and lab.log[#lab.log].channel==P.REALTIME)
            local wrong=roamingFrame(3); wrong.sessionId='other-session'; assert(not host:sendRoaming(wrong))
            lab:injectToClient(1,assert(P.encode(wrong,P.REALTIME)),P.REALTIME)
            guest:update(); assert(guest.closed and guest.reason=='invalid_roaming' and roamingCalls==1)
        ''')

    def test_guest_cannot_send_host_enemy_motion_and_initial_packet_cannot_overtake_admission(self):
        self.enable_roaming()
        self.lua.execute('''
            approve()
            for _=1,10 do host:update(); guest:update(); if guest.status=='acknowledging' then break end end
            assert(guest.status=='acknowledging' and not guest.snapshot)
            lab:delayNext('host_to_client',1,3); host:update(); assert(host.link.admitted)
            assert(host:sendRoaming(roamingFrame())); guest:update(); assert(roamingCalls==0 and not guest.closed)
            step(5); assert(host:sendRoaming(roamingFrame(2))); guest:update(); assert(roamingCalls==1)
            lab:injectToHost(1,assert(P.encode(roamingFrame(3),P.REALTIME)),P.REALTIME)
            host:update(); assert(not host.link and disconnected==1 and movementCalls==0)
        ''')


class CredentialStoreTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Store=require('game.net.credential_store')
            fs,files=F.filesystem(); credential={campaignId=string.rep('a',32),companionId=string.rep('b',32),token=string.rep('c',64)}
        ''')

    def test_checked_roundtrip_updates_in_place_and_contains_no_campaign(self):
        self.lua.execute('''
            assert(Store.save(credential,fs)); assert(not files[Store.PATH..'.tmp'])
            local loaded=assert(Store.load(fs)); assert(#loaded.entries==1)
            local found=assert(Store.find(loaded,credential.campaignId)); assert(found.token==credential.token)
            found.token='changed'; assert(Store.find(loaded,credential.campaignId).token==credential.token)
            credential.token=string.rep('d',64); assert(Store.save(credential,fs))
            assert(#Store.load(fs).entries==1 and not next(files,Store.PATH))
        ''')

    def test_truncated_write_cannot_acknowledge_credentials_and_temp_is_recoverable(self):
        self.lua.execute('''
            local write=fs.write
            fs.write=function(path,bytes) if path==Store.PATH then files[path]='broken'; return true end; return write(path,bytes) end
            local result,reason=Store.save(credential,fs)
            assert(not result and reason=='connection_store_write_failed')
            assert(Store.find(assert(Store.load(fs)),credential.campaignId).token==credential.token)
            fs.write=write; assert(Store.save(credential,fs))
            assert(not files[Store.PATH..'.tmp'])
        ''')

    def test_corrupt_existing_store_is_not_silently_overwritten(self):
        self.lua.execute('''
            files[Store.PATH]='return os.execute("no")'
            assert(not Store.save(credential,fs) and files[Store.PATH]=='return os.execute("no")')
            files[Store.PATH]=nil; credential.inventory={}; assert(not Store.save(credential,fs) and not next(files))
        ''')

    def test_store_capacity_is_bounded_without_silently_forgetting_existing_friends(self):
        self.lua.execute('''
            for index=1,Store.MAX do
                credential.campaignId=string.format('%032x',index); assert(Store.save(credential,fs))
            end
            credential.campaignId=string.rep('f',32)
            local result,reason=Store.save(credential,fs)
            assert(not result and reason=='connection_store_full' and #Store.load(fs).entries==Store.MAX)
            credential.campaignId=string.format('%032x',1); credential.token=string.rep('e',64)
            assert(Store.save(credential,fs) and #Store.load(fs).entries==Store.MAX)
        ''')

if __name__ == '__main__':
    unittest.main()
