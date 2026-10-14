"""LAN discovery uses address hints only; automatic joins retain real admission."""
import unittest
import test_coop_local_play_behavior as lifecycle

FAKE_NETWORK = r"""
local function fakeNetwork(options)
    options = options or {}
    local network = {
        sockets = {}, nextPort = 30000, nextIp = 10,
        blockBroadcast = options.blockBroadcast == true,
    }
    local socketModule = {}

    function socketModule.udp()
        local udp = {
            ip = "192.168.50." .. tostring(network.nextIp),
            port = nil,
            queue = {},
            closed = false,
            sent = {},
        }
        network.nextIp = network.nextIp + 10
        network.sockets[#network.sockets + 1] = udp
        function udp:setoption() return true end
        function udp:settimeout() return true end
        function udp:setsockname(address, port)
            if port == 0 then
                network.nextPort = network.nextPort + 1
                port = network.nextPort
            end
            self.bindAddress = address
            self.port = port
            return true
        end
        function udp:sendto(packet, address, port)
            self.sent[#self.sent + 1] = { packet = packet, address = address, port = port }
            for _, target in ipairs(network.sockets) do
                local broadcast = address == "255.255.255.255"
                    or address:match("%.255$") ~= nil
                if not target.closed and target ~= self and target.port == port
                    and (not broadcast or not network.blockBroadcast)
                    and (broadcast or target.ip == address)
                then
                    target.queue[#target.queue + 1] = {
                        packet = packet, address = self.ip, port = self.port,
                    }
                end
            end
            return #packet
        end
        function udp:receivefrom()
            local item = table.remove(self.queue, 1)
            if not item then return nil, "timeout" end
            return item.packet, item.address, item.port
        end
        function udp:close() self.closed = true; return true end
        return udp
    end
    return network, socketModule
end

"""

class LanDiscoveryTests(unittest.TestCase):
    def setUp(self):
        lifecycle.LocalPlayTests.setUp(self)
        self.lua.execute(FAKE_NETWORK + r"""
            fakeNetworkFactory=fakeNetwork
            Discovery=require('game.net.lan_discovery'); Address=require('game.net.address')
            function discoveryPair(blocked)
                udpLab,sockets=fakeNetwork({blockBroadcast=blocked})
                advertised=Discovery.new({socket=sockets,clock=function() return clock end})
                searching=Discovery.new({socket=sockets,clock=function() return clock end,
                    nonceFactory=function() return '0123456789abcdef' end})
                assert(advertised:startHost({gamePort=22124,name='Journey | Host\n'}))
                assert(searching:startSearch({localInterfaces={{address='192.168.50.20',prefixLength=24}},detectInterfaces=false}))
            end
            function discover(count)
                for _=1,count or 1 do clock=clock+.05; searching:update(); advertised:update(); searching:update() end
            end
            function inject(packet,ip) udpLab.sockets[2].queue[#udpLab.sockets[2].queue+1]={packet=packet,address=ip or '192.168.50.99',port=22125} end
            function hint(ip,nonce,version,port)
                inject('MFLAN1|H|'..(nonce or '0123456789abcdef')..'|'..(version or require('game.net.protocol').VERSION)..'|'..(port or 22124)..'|Friend',ip)
            end
            function convenience()
                stub={mode='idle',list={},closed=0,searches=0,advertised=0}
                function stub:stop() self.mode='idle'; self.closed=self.closed+1 end
                function stub:startSearch(options) self.mode='search'; self.searches=self.searches+1; self.options=options; return true end
                function stub:startHost(options) self.mode='host'; self.advertised=self.advertised+1; self.options=options; return true end
                function stub:status() return self.mode,'Discovery status' end
                function stub:results() return self.list end
                function stub:update() end
                guest.discovery=stub
                guestContext.addressDetector=function() return {
                    {address='192.168.50.20',prefixLength=24,isUsb=false,interfaceName='Wi-Fi'},
                    {address='192.168.42.2',prefixLength=24,isUsb=true,interfaceName='USB Ethernet'}} end
                guest:open()
            end
        """)

    def tearDown(self):
        self.lua.execute("if advertised then advertised:stop() end; if searching then searching:stop() end")
        lifecycle.LocalPlayTests.tearDown(self)

    def test_udp_discovers_detached_sanitized_hint_then_expires(self):
        self.lua.execute(r"""
            discoveryPair(false); discover()
            assert(udpLab.sockets[1].bindAddress=='0.0.0.0' and udpLab.sockets[2].bindAddress=='0.0.0.0')
            local result=searching:results(); assert(#result==1 and result[1].address=='192.168.50.10')
            assert(result[1].port==22124 and result[1].name=='Journey ? Host?' and not result[1].campaignId)
            result[1].name='changed'; assert(searching:results()[1].name=='Journey ? Host?')
            clock=clock+6; searching:update(); assert(#searching:results()==0)
        """)

    def test_wrong_game_nonce_protocol_port_sender_and_size_ignored(self):
        self.lua.execute(r"""
            discoveryPair(false)
            hint('192.168.50.1','ffffffffffffffff'); hint('192.168.50.2',nil,999)
            hint('192.168.50.3',nil,nil,0); hint('255.255.255.255'); hint('not-ip')
            inject('TPSLAN1|H|0123456789abcdef|24|22124|Picture Shop')
            inject(string.rep('x',Discovery.MAX_PACKET_BYTES+1))
            searching:update(); assert(#searching:results()==0)
        """)

    def test_all_storage_is_bounded_even_unlisted_reply_flood(self):
        self.lua.execute(r"""
            discoveryPair(false)
            for index=1,24 do hint('192.168.50.'..index) end
            searching:update(); assert(#searching:results()==8)
            local count=0; for _ in pairs(searching.resultsByAddress) do count=count+1 end
            assert(count==8)
        """)

    def test_filtered_broadcast_finds_host_by_bounded_unicast(self):
        self.lua.execute(r"""
            discoveryPair(true); discover(90)
            assert(#searching:results()==1 and #searching.unicastScanTargets==253)
            local max=0
            for _,send in ipairs(udpLab.sockets[2].sent) do
                if send.address=='192.168.50.10' then max=max+1 end
            end
            assert(max>0 and #searching.unicastScanTargets<=Discovery.MAX_UNICAST_SCAN_TARGETS)
        """)

    def test_missing_sockets_bind_failure_and_bad_nonce_keep_manual_fallback(self):
        self.lua.execute(r"""
            local missing=Discovery.new({socket=false}); local ok,reason=missing:startSearch(); assert(not ok and reason:find('manually'))
            local closed=false
            local broken=Discovery.new({socket={udp=function() return {setoption=function() return true end,settimeout=function() return true end,
                setsockname=function() return nil,'denied' end,close=function() closed=true end} end}})
            assert(not broken:startHost({gamePort=22124}) and closed)
            local net,mod=fakeNetworkFactory(); local bad=Discovery.new({socket=mod,nonceFactory=function() return 'bad' end})
            assert(not bad:startSearch() and net.sockets[1].closed)
        """)

    def test_explicit_loopback_probe_and_interface_snapshot_are_detached(self):
        self.lua.execute(r"""
            local net,mod=fakeNetworkFactory()
            local search=Discovery.new({socket=mod,queryTargets={'127.0.0.1','invalid'},nonceFactory=function() return '0123456789abcdef' end})
            assert(search:startSearch({localInterfaces={{address='192.168.42.2',prefixLength=24,isUsb=true}},detectInterfaces=false}))
            search:update(); local explicit=false
            for _,send in ipairs(net.sockets[1].sent) do if send.address=='127.0.0.1' then explicit=true end end
            assert(explicit); local interfaces=search:interfaces(); interfaces[1].address='changed'
            assert(search:interfaces()[1].address=='192.168.42.2' and search:interfaces()[1].isUsb); search:stop()
        """)

    def test_interface_candidate_metadata_and_host_selection(self):
        self.lua.execute(r"""
            local interfaces=Address.detectLanInterfaces({candidates={
                {address='192.168.42.2',prefixLength=24,isUsb=true,interfaceName='RNDIS'},
                {address='192.168.50.2',prefixLength=23,interfaceName='Wi-Fi'}}})
            assert(#interfaces==2 and interfaces[1].isUsb and interfaces[1].prefixLength==24)
            assert(interfaces[2].prefixLength==23 and interfaces[2].broadcast=='192.168.51.255')
            assert(Address.chooseLanAddress(interfaces)=='192.168.50.2')
        """)

    def test_modes_filter_results_and_setters_persist_only_device_preferences(self):
        self.lua.execute(r"""
            convenience(); local preferences
            guestContext.saveLocalPlayPreferences=function(value) preferences=value; return true end
            stub.list={{address='192.168.50.10',port=22124,name='Wi-Fi host'},{address='192.168.42.1',port=22124,name='USB host'}}
            assert(#guest:discoveredHosts()==2); assert(guest:setConnectionMode('usb'))
            assert(#guest:discoveredHosts()==1 and guest:discoveredHosts()[1].name=='USB host')
            assert(stub.options.detectInterfaces==false and #stub.options.localInterfaces==1 and stub.options.localInterfaces[1].isUsb)
            assert(guest:setAutoJoin(true) and preferences.connectionMode=='usb' and preferences.autoJoin)
            assert(guest:setConnectionMode('wifi') and guest:discoveredHosts()[1].name=='Wi-Fi host')
            assert(not guest:setConnectionMode('internet'))
            local interfaces=guest:localInterfaces(); interfaces[1].address='changed'; assert(guest:localInterfaces()[1].address=='192.168.50.20')
            assert(not guestData.localPlay and not data.localPlay)
        """)

    def test_one_stable_host_autojoin_still_requires_host_approval(self):
        self.lua.execute(r"""
            assert(host:host()); convenience(); stub.list={{address='192.168.50.10',port=22124,name='Host'}}
            guest:setAutoJoin(true); step(20); assert(joins==0)
            step(17); assert(joins==1 and host:pending() and not service.bindings.companion)
            assert(host:approve()); step(15); assert(guest.phase=='connected' and service.bindings.companion==1)
            assert(stub.mode=='idle' and guestFiles['coop-credentials.txt']==nil)
        """)

    def test_autojoin_waits_for_disambiguation_profile_and_manual_intent(self):
        self.lua.execute(r"""
            assert(host:host()); convenience(); guest:setAutoJoin(true)
            stub.list={{address='192.168.50.10',port=22124,name='A'},{address='192.168.50.11',port=22124,name='B'}}
            step(45); assert(joins==0); stub.list[2]=nil; guest.manualEntry=true; step(45); assert(joins==0)
            guest.manualEntry=false; guest.name=''; step(45); assert(joins==0)
            guest.name='Friend'; step(20); assert(joins==0); step(16); assert(joins==1)
        """)

    def test_host_advertises_custom_port_and_menu_stop_closes_discovery(self):
        self.lua.execute(r"""
            convenience(); host.discovery=stub; host.port='23111'; assert(host:host())
            assert(stub.mode=='host' and stub.options.gamePort==23111 and stub.options.name=='Journey - Slot 1')
            host:open(); assert(stub.mode=='host'); host:stop(); assert(stub.mode=='idle')
            guest:open(); assert(stub.mode=='search'); guest:closeMenu(); assert(stub.mode=='idle')
        """)

    def test_transient_disconnect_rejoins_same_actor_credential_without_new_approval(self):
        self.lua.execute(r"""
            guestContext.autoReconnect=true; ready(); local item=data.players.companion.itemSlots.equipment[1].id
            host.network:_drop('host_timeout'); step(30)
            assert(guest.phase=='connected',guest.error or guest.phase)
            assert(service.bindings.companion==2 and data.players.companion.itemSlots.equipment[1].id==item)
            assert(not host:pending() and not guest:reconnectStatus().active)
        """)

    def test_reconnect_cancel_fatal_rejection_and_initial_failure_do_not_loop(self):
        self.lua.execute(r"""
            guestContext.autoReconnect=true; ready(); guest:_connectionFailed('host_timeout')
            assert(guest:reconnectStatus().active); guest:cancelReconnect(); step(30); assert(joins==1)
            assert(guest:join()); step(20); assert(guest.phase=='connected')
            guest:_connectionFailed('incompatible_build'); assert(not guest:reconnectStatus().active)
            assert(guest:join()); guest:_connectionFailed('join_timeout'); assert(not guest:reconnectStatus().active)
        """)

    def test_reconnect_attempts_back_off_and_exhaust_when_host_is_absent(self):
        self.lua.execute(r"""
            guestContext.autoReconnect=true; ready(); host:stop('host_timeout'); step(700)
            assert(guest.phase=='idle' and not guest:reconnectStatus().active)
            assert(guest:reconnectStatus().state=='exhausted' and joins==7)
            assert(guestRuntime.saveData==guestData and guestSession.networkMode=='offline' and guest.autoJoinBlocked)
        """)

    def test_discovered_row_snapshot_never_joins_a_shifted_or_expired_host(self):
        self.lua.execute(r"""
            assert(host:host()); convenience()
            stub.list={{address='192.168.50.10',port=22124,name='A'},{address='192.168.50.11',port=22124,name='B'}}
            local clicked=guest:discoveredHosts()[1]; table.remove(stub.list,1)
            assert(not guest:joinDiscovered(clicked) and guest.error=='discovered_host_expired' and joins==0)
            clicked=guest:discoveredHosts()[1]; assert(guest:joinDiscovered(clicked) and joins==1)
        """)

    def test_cancel_reconnect_does_not_autojoin_the_same_scan_again(self):
        self.lua.execute(r"""
            assert(host:host()); convenience(); guest:setAutoJoin(true)
            stub.list={{address='192.168.50.10',port=22124,name='Host'}}
            guest:cancelReconnect(); step(50); assert(joins==0 and guest.autoJoinBlocked)
            guest:refreshDiscovery(); step(40); assert(joins==1)
        """)

    def test_reconnect_remembers_long_valid_hostname_and_never_retains_old_invalid_target(self):
        self.lua.execute(r"""
            local reconnect=require('game.net.lan_reconnect').new()
            assert(reconnect:remember('old-pc:22124','Friend'))
            local name=string.rep('a',63)..'.'..string.rep('b',63)..'.'..string.rep('c',63)..'.'..string.rep('d',61)..':22124'
            assert(#name==259 and reconnect:remember(name,'Friend') and reconnect:snapshot().target.address==name)
            assert(not reconnect:remember('not/a/host','Friend') and not reconnect:snapshot().target)
        """)

    def test_wifi_and_usb_host_modes_keep_wildcard_listener_and_explicit_bind_override(self):
        self.lua.execute(r"""
            convenience(); hostContext.addressDetector=guestContext.addressDetector
            local original=hostContext.network.host; local binding
            hostContext.network.host=function(options) binding=options.bind or 'wildcard'; return original(options) end
            host:setConnectionMode('usb'); assert(host:host())
            assert(host.localAddress=='192.168.42.2' and binding=='wildcard'); host:stop()
            host:setConnectionMode('wifi'); assert(host:host())
            assert(host.localAddress=='192.168.50.20' and binding=='wildcard'); host:stop()
            hostContext.bind='127.0.0.1'; assert(host:host()); assert(binding=='127.0.0.1')
        """)
