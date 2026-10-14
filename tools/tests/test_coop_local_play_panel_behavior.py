"""Local Play controls preserve manual entry and expose LAN convenience safely."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class LocalPlayPanelTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            texts={}; events={}; keyboardOpen=false
            love={graphics={newFont=function(size) return size end,
                getDimensions=function() return 960,720 end,
                push=function() end,pop=function() end,origin=function() end,clear=function() end,
                translate=function() end,scale=function() end,setFont=function() end,
                setColor=function() end,rectangle=function() end,
                printf=function(value,x,y,w) texts[#texts+1]={value=value,x=x,y=y,w=w} end},
                keyboard={setTextInput=function(value) keyboardOpen=value end,isDown=function() return false end}}
            c={phase='idle',address='',name='Friend',port='22124',connectionMode='auto',autoJoin=false,
                interfaces={{address='192.168.1.4',prefixLength=24,isUsb=false},
                    {address='192.168.42.2',prefixLength=24,isUsb=true}},hosts={},canHostValue=false}
            function c:canHost() return self.canHostValue end
            function c:character() return 'scout-frog.png' end
            function c:cycleCharacter(direction) events.cycle=direction end
            function c:closeMenu() events.close=true end
            function c:setConnectionMode(value) self.connectionMode=value; events.mode=value end
            function c:setAutoJoin(value) self.autoJoin=value; events.auto=value end
            function c:refreshDiscovery() events.refresh=(events.refresh or 0)+1 end
            function c:localInterfaces() return self.interfaces end
            function c:discoveredHosts() return self.hosts end
            function c:discoveryStatus() return 'Searching local adapters, including USB Ethernet...' end
            function c:joinDiscovered(host) events.discovered=host end
            function c:reconnectStatus() return self.reconnect end
            function c:cancelReconnect() self.reconnect=nil; events.cancel=true end
            function c:host() events.host=true end
            function c:join() events.join=true end
            function c:stop() events.stop=true end
            function c:pending() return self.request end
            function c:approve() events.approve=true end
            function c:decline() events.decline=true end
            context={runtime={state='slots'},ui={},screenToGame=function(x,y) return x,y end}
            panel=require('game.local_play_panel').new(c,context)
            function draw() texts={}; panel:draw() end
            function click(id)
                local rect=assert(context.ui.localPlayControls[id],id)
                return panel:click(rect.x+rect.w/2,rect.y+rect.h/2)
            end
            function includes(value)
                for _,item in ipairs(texts) do if item.value:find(value,1,true) then return true end end
                return false
            end
            draw()
        ''')

    def test_saved_hosting_from_title_and_failed_retry_controls(self):
        self.lua.execute('''
            function c:canHostSavedJourney() return context.runtime.state=='slots' and self.hostingIntent~='failed' end
            function c:hostSavedJourney() events.savedHost=true; self.hostingIntent='selecting' end
            function c:retryHostingEntry() events.retryHosting=true end
            function c:cancelHostingEntry() events.cancelHosting=true; self.hostingIntent=nil end
            draw(); assert(includes('Host saved journey') and context.ui.localPlayControls.host.enabled)
            assert(context.ui.localPlayControls.port.enabled); click('port'); panel:textinput('22128'); panel:key('return')
            assert(c.port=='22128'); click('host'); assert(events.savedHost and not events.host and c.hostingIntent=='selecting')
            draw(); assert(context.ui.localPlayControls.join.enabled==false and includes('Cancel hosting'))
            c.hostingIntent='failed'; c.error='bind_failed'; context.runtime.state='game'; draw()
            assert(includes('Hosting has not started') and context.ui.localPlayControls.retryHosting and context.ui.localPlayControls.cancelHosting)
            assert(context.ui.localPlayControls.port.enabled); click('retryHosting'); assert(events.retryHosting)
            click('cancelHosting'); assert(events.cancelHosting and not c.hostingIntent)
        ''')

    def test_connection_modes_refresh_and_opt_in_auto_connect(self):
        self.lua.execute('''
            click('connection_usb'); assert(c.connectionMode=='usb' and not c.manualEntry)
            click('connection_wifi'); assert(events.mode=='wifi')
            click('connection_auto'); assert(events.mode=='auto')
            click('refresh'); assert(events.refresh==1)
            assert(not c.autoJoin); click('autoJoin'); assert(c.autoJoin)
            draw(); assert(includes('AUTO-CONNECT ONE FOUND JOURNEY: ON'))
            click('autoJoin'); assert(not c.autoJoin)
        ''')

    def test_manual_selection_opens_keyboard_and_blocks_auto_join_until_mode_selection(self):
        self.lua.execute('''
            click('manual'); assert(panel.field=='address' and keyboardOpen and c.manualEntry)
            panel:textinput('192.168.1.7:22124'); panel:key('return')
            assert(c.address=='192.168.1.7:22124' and not keyboardOpen and c.manualEntry)
            click('join'); assert(events.join and c.manualEntry)
            click('connection_wifi'); assert(not panel.manualSelected and not c.manualEntry)
        ''')

    def test_direct_address_focus_also_suppresses_automatic_join(self):
        self.lua.execute('''
            click('address'); assert(c.manualEntry and panel.manualSelected)
            panel:textinput('friend-pc:22124'); panel:key('return'); assert(c.manualEntry)
            panel:key('escape'); assert(events.close and not keyboardOpen)
        ''')

    def test_profile_editing_suppresses_auto_join_only_while_typing(self):
        self.lua.execute('''
            click('name'); assert(c.manualEntry)
            panel:textinput('Helper'); panel:key('return')
            assert(c.name=='Helper' and not c.manualEntry)
            c.canHostValue=true; draw(); click('port'); panel:textinput('22a!124')
            assert(c.port=='22124' and c.manualEntry); panel:key('return'); assert(not c.manualEntry)
        ''')

    def test_network_hints_discovered_rows_and_multiple_candidate_count(self):
        self.lua.execute('''
            assert(includes('USB ETHERNET: 192.168.42.2/24'))
            assert(includes('WI-FI / ETHERNET: 192.168.1.4/24'))
            assert(includes('Searching local adapters'))
            c.hosts={{name='Journey A',address='192.168.1.10',port=22124},
                {name='Journey B',address='192.168.1.11',port=22222},
                {name='Journey C',address='192.168.1.12',port=22333}}
            draw(); assert(includes('3 found') and context.ui.localPlayControls.discoveryNext)
            assert(includes('Journey A   192.168.1.10:22124'))
            assert(not context.ui.localPlayControls.discovered_3)
            click('discovered_2'); assert(events.discovered.address=='192.168.1.11' and events.discovered.port==22222)
        ''')

    def test_discovered_click_preserves_displayed_endpoint_if_results_change(self):
        self.lua.execute('''
            c.hosts={{name='Journey A',address='192.168.1.10',port=22124},
                {name='Journey B',address='192.168.1.11',port=22222}}
            draw()
            c.hosts={{name='Journey B',address='192.168.1.11',port=22222}}
            click('discovered_1')
            assert(events.discovered.address=='192.168.1.10' and events.discovered.port==22124)
            assert(events.discovered.name=='Journey A')
        ''')

    def test_discovery_paging_reaches_every_host_and_clamps_after_expiry(self):
        self.lua.execute('''
            c.hosts={}; for index=1,8 do c.hosts[index]={name='Journey '..index,address='192.168.1.'..(10+index),port=22124} end
            draw(); assert(not context.ui.localPlayControls.discoveryPrevious.enabled and context.ui.localPlayControls.discoveryNext.enabled)
            for page=1,4 do
                assert(includes('Journey '..(page*2)))
                click('discovered_2'); assert(events.discovered.address=='192.168.1.'..(10+page*2))
                if page<4 then click('discoveryNext'); draw() end
            end
            assert(not context.ui.localPlayControls.discoveryNext.enabled)
            local captured=events.discovered
            c.hosts={c.hosts[1],c.hosts[2],c.hosts[3]}; draw()
            assert(panel.discoveryPage==2 and includes('Journey 3') and not context.ui.localPlayControls.discovered_2)
            click('discovered_1'); assert(events.discovered.address=='192.168.1.13' and captured.address=='192.168.1.18')
            click('refresh'); draw(); assert(panel.discoveryPage==1)
            for i,a in ipairs(panel.controls) do for j,b in ipairs(panel.controls) do
                if i~=j then assert(a.x+a.w<=b.x or b.x+b.w<=a.x or a.y+a.h<=b.y or b.y+b.h<=a.y,'overlapping paged controls') end
            end end
        ''')

    def test_pager_keyboard_manual_and_reconnect_keep_discovered_rows_aligned(self):
        self.lua.execute('''
            c.hosts={}; for index=1,6 do c.hosts[index]={name='Journey '..index,address='192.168.1.'..(10+index),port=22124} end
            draw(); local rect=context.ui.localPlayControls.discoveryNext
            for index,control in ipairs(panel.controls) do if control==rect then panel.selected=index end end
            panel:key('return'); draw(); assert(panel.discoveryPage==2 and includes('Journey 3'))
            rect=context.ui.localPlayControls.discoveryPrevious
            for index,control in ipairs(panel.controls) do if control==rect then panel.selected=index end end
            panel:key('up'); panel:key('down'); panel:key('space'); draw()
            assert(panel.discoveryPage==1)
            click('discoveryNext'); draw(); local row=context.ui.localPlayControls.discovered_1
            assert(row.y==510 and row.h==42); click('manual'); draw()
            assert(panel.field=='address' and context.ui.localPlayControls.discovered_1.y==row.y)
            c.reconnect={active=true,state='waiting',attempt=1,maxAttempts=6,nextIn=2}; draw()
            assert(not context.ui.localPlayControls.discoveryNext and not context.ui.localPlayControls.discovered_1)
            click('cancelReconnect'); draw()
            assert(panel.discoveryPage==2 and context.ui.localPlayControls.discovered_1.y==row.y and includes('Journey 3'))
            click('connection_wifi'); draw(); assert(panel.discoveryPage==1)
            c.hosts={c.hosts[1]}; draw()
            assert(panel.discoveryPage==1 and not context.ui.localPlayControls.discoveryPrevious and not context.ui.localPlayControls.discoveryNext)
            assert(context.ui.localPlayControls.discovered_1.y==row.y)
        ''')

    def test_hosting_from_loaded_journey_and_joining_from_title_only(self):
        self.lua.execute('''
            click('host'); assert(not events.host)
            context.runtime.state='game'; c.canHostValue=true
            c.hosts={{name='Friend',address='192.168.1.10',port=22124}}
            draw(); click('join'); click('discovered_1'); assert(not events.join and not events.discovered)
            click('host'); assert(events.host)
        ''')

    def test_keyboard_and_controller_key_bridge_skips_disabled_controls(self):
        self.lua.execute('''
            local port=context.ui.localPlayControls.port
            for index,control in ipairs(panel.controls) do if control==port then panel.selected=index-1 end end
            panel:key('down'); assert(panel.controls[panel.selected]~=port)
            local rect=context.ui.localPlayControls.connection_usb
            for index,control in ipairs(panel.controls) do if control==rect then panel.selected=index end end
            panel:key('return'); assert(c.connectionMode=='usb')
            panel:key('up'); panel:key('space'); assert(c.connectionMode=='wifi')
        ''')

    def test_pointer_coordinates_are_transformed_once(self):
        self.lua.execute('''
            context.screenToGame=function(x,y) return (x-20)/2,(y-30)/2 end
            local r=context.ui.localPlayControls.refresh
            panel:click(20+2*(r.x+r.w/2),30+2*(r.y+r.h/2)); assert(events.refresh==1)
        ''')

    def test_reconnect_progress_and_cancellation(self):
        self.lua.execute('''
            c.reconnect={active=true,state='waiting',attempt=2,maxAttempts=6,nextIn=1.2}
            draw(); assert(includes('Reconnect attempt 2 of 6: retrying in 2 seconds...'))
            assert(not context.ui.localPlayControls.discovered_1)
            click('cancelReconnect'); assert(events.cancel and not c.reconnect)
            c.reconnect={active=true,state='connecting',attempt=3,maxAttempts=6}
            draw(); assert(includes('contacting the host...'))
        ''')

    def test_host_addresses_and_approval_controls_remain_available(self):
        self.lua.execute('''
            c.phase='hosting'; c.request={name='Helper',character='scout-frog.png'}
            c.campaign={players={}}; draw()
            assert(includes('Hosting this journey on port 22124') and includes('192.168.42.2/24'))
            click('approve'); click('decline'); assert(events.approve and events.decline)
            click('close'); assert(events.close)
            click('stop'); assert(events.stop and not c.menuOpen)
        ''')

    def test_pending_connection_has_cancel_and_reconnect_attempt_label(self):
        self.lua.execute('''
            c.phase='joining'; c.network={status='approval'}
            c.reconnect={active=true,state='connecting',attempt=3,maxAttempts=6}
            draw(); assert(includes('Waiting for the host to approve') and includes('Reconnect attempt 3 of 6'))
            assert(includes('Cancel connection')); click('leave'); assert(events.stop and not c.menuOpen)
        ''')

    def test_existing_field_ids_remain_present_and_all_controls_fit_viewport(self):
        self.lua.execute('''
            for _,id in ipairs({'address','name','port','previous','next','host','join','close'}) do
                assert(context.ui.localPlayControls[id],id)
            end
            for _,r in ipairs(panel.controls) do
                assert(r.x>=0 and r.y>=0 and r.x+r.w<=960 and r.y+r.h<=720)
            end
            for i,a in ipairs(panel.controls) do for j,b in ipairs(panel.controls) do
                if i~=j then assert(a.x+a.w<=b.x or b.x+b.w<=a.x or a.y+a.h<=b.y or b.y+b.h<=a.y,'overlapping controls') end
            end end
        ''')


if __name__ == '__main__':
    unittest.main()
