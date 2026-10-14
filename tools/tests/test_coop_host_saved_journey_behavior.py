"""Explicit saved-slot hosting starts before the first gameplay update."""
import unittest
import test_coop_local_play_behavior as local_play


class HostSavedJourneyTests(unittest.TestCase):
    setUp = local_play.LocalPlayTests.setUp
    tearDown = local_play.LocalPlayTests.tearDown

    def title(self):
        self.lua.execute('''
            hostRuntime.state='slots'; host:open()
            assert(host:canHostSavedJourney() and not host:canHost())
            function entry(slot)
                hostRuntime.state='game'; hostRuntime.selectedSlot=slot or 1; hostRuntime.saveData=data
            end
        ''')

    def test_saved_slot_selection_starts_real_host_synchronously_before_world_tick(self):
        self.title()
        self.lua.execute('''
            local campaignId=data.coop.network and data.coop.network.campaignId; local before=assert(Schema.copy(data))
            local writesBefore=writes; assert(host:hostSavedJourney())
            assert(host.hostingIntent=='selecting' and not host.menuOpen and not host:captures())
            assert(not host.network and hostSession.networkMode=='offline' and writes==writesBefore)
            entry(); assert(host:finishHostingEntry(),host.error)
            assert(host.network and host.phase=='hosting' and hostSession.networkMode=='host' and not host.hostingIntent)
            assert(host.campaign==data and data.coop.network.campaignId and data.location==before.location)
            if campaignId then assert(data.coop.network.campaignId==campaignId) end
            assert(hostRuntime.state=='game' and hostRuntime.selectedSlot==1)
        ''')

    def test_failed_bind_keeps_loaded_campaign_captured_until_explicit_retry(self):
        self.title()
        self.lua.execute('''
            assert(host:hostSavedJourney()); entry()
            local realHost=hostContext.network.host; local calls=0
            hostContext.network.host=function(options)
                calls=calls+1; if calls==1 then return nil,'bind_failed' end; return realHost(options)
            end
            assert(not host:finishHostingEntry() and host.error=='bind_failed')
            assert(host.hostingIntent=='failed' and host.menuOpen and host:captures() and not host.network)
            assert(hostSession.networkMode=='offline' and hostRuntime.saveData==data and hostRuntime.selectedSlot==1)
            host.menuOpen=false; assert(host:captures()) -- Closing a flag cannot unblock failed entry.
            assert(host:retryHostingEntry(),host.error)
            assert(calls==2 and host.network and hostSession.networkMode=='host' and not host.hostingIntent)
        ''')

    def test_thrown_host_transport_failure_is_recoverable_without_loading_again(self):
        self.title()
        self.lua.execute('''
            assert(host:hostSavedJourney()); entry()
            local realHost=hostContext.network.host
            hostContext.network.host=function() error('forced host initialization failure') end
            assert(not host:finishHostingEntry() and host.error=='operation_failed')
            assert(host.hostingIntent=='failed' and host:captures() and not host.network)
            hostContext.network.host=realHost; assert(host:retryHostingEntry())
            assert(host.campaign==data and hostRuntime.saveData==data and not host.hostingIntent)
        ''')

    def test_failed_preflight_preserves_save_retry_then_host_retry_order(self):
        self.title()
        self.lua.execute('''
            assert(host:hostSavedJourney()); entry(); failSave=true
            assert(not host:finishHostingEntry() and host.error=='save_not_ready')
            assert(service.pendingSave and host.hostingIntent=='failed' and host:captures() and not host.network)
            assert(not host:retryHostingEntry() and host.hostingIntent=='failed')
            failSave=false; assert(service:retryCheckpoint())
            assert(host:retryHostingEntry() and host.network and hostSession.networkMode=='host')
            assert(hostRuntime.saveData==data and saved.coop.network.campaignId==data.coop.network.campaignId)
        ''')

    def test_cancel_and_back_release_intent_without_deleting_or_replacing_save(self):
        self.title()
        self.lua.execute('''
            local original=data; local writesBefore=writes
            assert(host:hostSavedJourney()); assert(host:cancelHostingEntry())
            assert(not host.hostingIntent and not host:captures() and hostRuntime.saveData==original and writes==writesBefore)
            host:open(); assert(host:hostSavedJourney()); entry(); host.port='bad'
            assert(not host:finishHostingEntry() and host.hostingIntent=='failed')
            assert(host:closeMenu() and not host.hostingIntent and not host:captures())
            assert(hostSession.networkMode=='offline' and hostRuntime.saveData==original and hostRuntime.selectedSlot==1)
        ''')

    def test_invalid_slot_and_stale_authority_never_start_a_host(self):
        self.title()
        self.lua.execute('''
            for _,slot in ipairs({0,100,'1',1.5}) do
                hostRuntime.state='slots'; host:open(); assert(host:hostSavedJourney()); entry(slot)
                assert(not host:finishHostingEntry() and host.hostingIntent=='failed' and not host.network)
                assert(host:captures()); host:cancelHostingEntry()
            end
            hostRuntime.state='slots'; host:open(); assert(host:hostSavedJourney()); entry()
            hostRuntime.saveData=assert(Schema.copy(data))
            assert(not host:finishHostingEntry() and host.error=='campaign_changed' and not host.network)
            assert(host.hostingIntent=='failed' and host:captures())
        ''')

    def test_ordinary_continue_and_invalid_port_never_create_hosting_intent(self):
        self.title()
        self.lua.execute('''
            local writesBefore=writes; host.port='0'
            assert(not host:hostSavedJourney() and host.error=='invalid_port' and not host.hostingIntent)
            assert(host.menuOpen and not host.network and writes==writesBefore)
            host:closeMenu(); entry()
            local priorError=host.error; local ok,reason=host:finishHostingEntry()
            assert(not ok and reason=='hosting_not_requested' and host.error==priorError)
            assert(not host.network and hostSession.networkMode=='offline' and not host.hostingIntent)
        ''')

    def test_selecting_intent_blocks_join_and_auto_connect_without_consuming_slot(self):
        self.title()
        self.lua.execute('''
            assert(host:hostSavedJourney()); host:open(); assert(host:canHostSavedJourney())
            assert(not host:join() and host.error=='hosting_entry_pending' and not host.network)
            host.autoJoin=true; host.discovery.results=function() return {{address='192.168.1.9',port=22124,name='Friend'}} end
            clock=10; host:update(); clock=20; host:update()
            assert(not host.network and joins==0 and host.hostingIntent=='selecting')
            assert(host:hostSavedJourney() and not host.menuOpen and host.hostingIntent=='selecting')
        ''')

    def test_client_role_and_active_network_cannot_begin_saved_host_selection(self):
        self.title()
        self.lua.execute('''
            hostSession:setNetworkMode('client'); assert(not host:canHostSavedJourney())
            assert(not host:hostSavedJourney() and not host.hostingIntent); hostSession:setNetworkMode('offline')
            entry(); assert(host:host()); hostRuntime.state='slots'
            assert(not host:canHostSavedJourney() and not host:hostSavedJourney() and not host.hostingIntent)
        ''')


if __name__ == '__main__':
    unittest.main()
