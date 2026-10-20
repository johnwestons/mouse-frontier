"""Exact-generation host removal through real Session and ENet adapter APIs."""
import unittest
import test_coop_lan_session_behavior as sessions
import test_coop_local_play_behavior as localplay
from lupa.lua51 import LuaRuntime


class HostKickTests(unittest.TestCase):
    tearDown = sessions.LanSessionTests.tearDown

    def setUp(self):
        sessions.LanSessionTests.setUp(self)
        self.lua.execute('''
            host.transport,native=require('tools.tests.lua.coop_kick_transport_fixture').install(lab,host.transport)
        ''')

    def test_kick_delivers_reliable_reason_keeps_host_and_cleans_once(self):
        self.lua.execute('''
            ready();local generation=host.link.generation;local peer=host.link.peer;local id=host.link.connectionId
            assert(id and host:kick(generation));assert(not host.closed and not host.transport.closed and not host.link)
            assert(host:hasDeparting() and disconnected==1 and host.departing.connectionId==id)
            guest:update();assert(guest.closed and guest.reason=='host_kicked' and not guest.snapshot)
            host:service();assert(not host:hasDeparting() and disconnected==1)
            local graceful=false;for _,entry in ipairs(native.log)do if entry.method=='disconnect_later'then graceful=true end end
            assert(graceful and not native.closed)
            guest=join(stored);step(10);assert(guest.status=='ready' and host.link.generation>generation)
        ''')

    def test_stale_pending_and_closed_targets_never_disconnect_current_guest(self):
        self.lua.execute('''
            step(3);local generation=host:pending().generation;local count=#native.log
            local ok,why=host:kick(generation);assert(not ok and why=='not_admitted' and #native.log==count)
            assert(host:approve(generation));step(10);assert(guest.status=='ready')
            for _,value in ipairs({0,generation+1,'1',false})do
                ok,why=host:kick(value);assert(not ok and why=='stale_generation' and host.link.generation==generation)
            end
            assert(disconnected==0);host:close();ok,why=host:kick(generation);assert(not ok and why=='host_closed')
        ''')

    def test_drain_blocks_replacement_until_terminal_event_and_ignores_old_packets(self):
        self.lua.execute('''
            ready();local oldGeneration=host.link.generation;local oldPeer=host.link.peer;local oldId=host.link.connectionId
            assert(lab:delayNext('host_to_client',1,10));assert(host:kick(oldGeneration))
            extra=join(stored);for _=1,3 do host:service();extra:update();lab:advanceSteps(1)end
            assert(not host.link and host.generation==oldGeneration and host:hasDeparting() and admitted==1)
            extra:close();extra=nil
            lab:advanceSteps(10);guest:update();host:service();assert(guest.reason=='host_kicked' and not host:hasDeparting())
            guest=join(stored);step(10);local newLink=host.link;assert(newLink and newLink.generation>oldGeneration)
            -- Native identity can be reused; normalized old event IDs still
            -- cannot be attributed to the new admitted generation.
            local raw=lab.host
            raw.inbound[#raw.inbound+1]={type='receive',peer=oldPeer,channel=P.CONTROL,data='malformed old packet'}
            raw.inbound[#raw.inbound+1]={type='disconnect',peer=oldPeer,code=0}
            host:service();assert(host.link==newLink and disconnected==1 and guest.status=='ready')
            local transport=host.transport;local service=transport.service
            transport.service=function()return {
                {type='receive',peer=newLink.peer,connectionId=oldId,channel=P.CONTROL,payload='old corrupted packet'},
                {type='disconnect',peer=newLink.peer,connectionId=oldId,code=0},
                {type='disconnect',peer=newLink.peer,code=0}},nil end
            host:service();transport.service=service
            assert(host.link==newLink and disconnected==1)
            local ok,why=host:kick(oldGeneration);assert(not ok and why=='stale_generation' and host.link==newLink)
        ''')

    def test_grace_timeout_uses_native_kick_code_without_admitting_overcapacity(self):
        self.lua.execute('''
            ready();assert(lab:delayNext('host_to_client',1,1000));assert(host:kick(host.link.generation))
            assert(host:hasDeparting());clock=host.departing.deadline;host:service()
            assert(not host:hasDeparting() and not host.link and not host.closed and disconnected==1)
            guest:update();assert(guest.closed and guest.reason=='host_kicked')
            local forced=false;for _,entry in ipairs(native.log)do
                if entry.method=='disconnect_now' and entry.code==Session.KICK_DISCONNECT_CODE then forced=true end
            end;assert(forced)
        ''')

    def test_failed_reject_send_still_closes_as_host_kicked_from_native_event_code(self):
        self.lua.execute('''
            ready();native.failSend=true;assert(host:kick(host.link.generation));guest:update()
            assert(guest.closed and guest.reason=='host_kicked' and disconnected==1 and not host.closed)
        ''')

    def test_older_peer_without_deferred_api_uses_safe_native_kick_fallback(self):
        self.lua.execute('''
            ready();host.link.peer.disconnect_later=nil;assert(host:kick(host.link.generation))
            guest:update();assert(guest.reason=='host_kicked' and not host:hasDeparting() and not host.closed)
            assert(disconnected==1)
            local forced=false;for _,entry in ipairs(native.log)do forced=forced or entry.method=='disconnect_now' end
            assert(forced)
        ''')

    def test_older_transport_without_deferred_api_fails_closed_with_native_reason(self):
        self.lua.execute('''
            ready();host.transport.disconnectLater=false;assert(host:kick(host.link.generation))
            guest:update();assert(guest.reason=='host_kicked' and not host:hasDeparting() and not host.closed)
            assert(disconnected==1 and not host.link)
        ''')

    def test_ordinary_malformed_packet_drop_still_resets_native_queue_immediately(self):
        self.lua.execute('''
            ready();local peer=host.link.peer;local count=#native.log
            lab.host.inbound[#lab.host.inbound+1]={type='receive',peer=peer,channel=P.CONTROL,data='malformed'}
            host:service();assert(not host.link and not host:hasDeparting() and disconnected==1)
            local regular,graceful=false,false
            for index=count+1,#native.log do
                regular=regular or native.log[index].method=='disconnect'
                graceful=graceful or native.log[index].method=='disconnect_later'
            end;assert(regular and not graceful)
        ''')

    def test_admitted_peer_can_be_kicked_during_a_later_baseline_transfer(self):
        self.lua.execute('''
            ready();local generation=host.link.generation
            hostContext.update=function()return {revision=revision,sceneEpoch=epoch,kind='readonly-test',payload=string.rep('y',14336)}end
            clock=clock+.2;revision=revision+1;host:publish();assert(host.link.admitted and host.link.phase=='snapshot')
            assert(host:kick(generation));step(3)
            assert(guest.reason=='host_kicked' and not guest.snapshot and not guest.receiver and not guest.pendingSnapshot)
            assert(admitted==1 and disconnected==1 and not host.closed)
        ''')


class LocalPlayKickTests(unittest.TestCase):
    setUp = localplay.LocalPlayTests.setUp
    tearDown = localplay.LocalPlayTests.tearDown

    def test_transport_kick_preserves_hosting_discovery_and_disarms_guest_reconnect(self):
        localplay.LocalPlayTests.enable_cars(self)
        self.lua.execute('''
            guestContext.autoReconnect=true;ready();motionReady();assert(guest.reconnectArmed and host.motion.generation)
            local network=host.network;local discovery=host.discovery;local generation=host.generation
            network.transport,native=require('tools.tests.lua.coop_kick_transport_fixture').install(lab,network.transport)
            -- The existing admitted lab peer was seen before adapter install.
            local peer=network.link.peer;lab.host.inbound[#lab.host.inbound+1]={type='connect',peer=peer}
            native:service() -- initialize native peer methods, without a second Session admission
            assert(network:kick(generation));step(4)
            assert(host.phase=='hosting' and host.network==network and host.discovery==discovery and not network.closed)
            assert(not service.bindings.companion and guest.phase=='idle' and guest.error=='host_kicked')
            assert(not host.motion.generation and not host.motion.readyEpoch)
            assert(not guest.reconnect:isActive() and not guest.reconnectArmed)
            local count=joins;for _=1,100 do clock=clock+.2;host:update();guest:update();lab:advanceSteps(1)end
            assert(joins==count and hostRuntime.saveData==data and hostSession.networkMode=='host')
        ''')


class ClientDisconnectIdentityTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = sessions.ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Session=require('game.net.session');P=require('game.net.protocol');Transport=require('game.net.transport_enet')
            local noop=function()end
            peer={nativeId=91,connect_id=function(self)return self.nativeId end,index=function()return 1 end,
                state=function()return 'connected'end,send=function()return true end,disconnect=noop,disconnect_now=noop}
            native={events={},connect=function()return peer end,service=function(self)return table.remove(self.events,1)end,
                flush=noop,destroy=noop}
            transport=assert(Transport.createClient('friend-pc',{enet={host_create=function()return native end}}))
            client=assert(Session.join('friend-pc',{transport=transport,build=string.rep('a',64),schema=44,
                name='Friend',character='cook-mouse.png',clock=function()return 0 end,validate=function()return true end,store=function()return true end}))
            native.events={{type='connect',peer=peer,data=0}};client:update()
            assert(client.connectionId==91 and transport._connectionIds[peer]==91)
            client.status='ready';client.snapshot={revision=1};client.lastReceive=0
        ''')

    def test_native_kick_terminal_event_retains_connect_id_after_peer_reset(self):
        self.lua.execute('''
            peer.nativeId=0
            native.events={{type='disconnect',peer=peer,data=Session.KICK_DISCONNECT_CODE}}
            client:update();assert(client.closed and client.reason=='host_kicked' and not client.snapshot)
            assert(transport.closed and next(transport._connectionIds)==nil)
        ''')

    def test_old_or_missing_connection_id_disconnect_cannot_close_current_client(self):
        self.lua.execute('''
            local service=transport.service
            transport.service=function()return {
                {type='disconnect',peer=peer,connectionId=90,code=Session.KICK_DISCONNECT_CODE},
                {type='disconnect',peer=peer,code=Session.KICK_DISCONNECT_CODE},
                {type='receive',peer=peer,connectionId=90,channel=P.CONTROL,payload='malformed old message'}},nil end
            client:update();assert(not client.closed and client.status=='ready' and client.snapshot)
            transport.service=service;peer.nativeId=0;native.events={{type='disconnect',peer=peer,data=0}}
            client:update();assert(client.closed and client.reason=='host_disconnected')
        ''')

    def test_native_disconnect_code_is_never_taken_from_a_receive_payload(self):
        self.lua.execute('''
            local payload=assert(P.encode(P.message('ping',{code=Session.KICK_DISCONNECT_CODE}),P.CONTROL))
            native.events={{type='receive',peer=peer,channel=P.CONTROL,data=payload}}
            local event=assert(transport:poll());assert(event.payload==payload and event.code==nil and event.connectionId==91)
            transport.service=function()return {event},nil end
            client:update();assert(client.closed and client.reason=='unexpected_message')
        ''')
