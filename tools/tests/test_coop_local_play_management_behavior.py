"""Companion administration through actual LocalPlay, admission, LAN and panel."""
from pathlib import Path
import unittest

import test_coop_local_play_behavior as lifecycle

ROOT = Path(__file__).resolve().parents[2]


class LocalPlayManagementTests(unittest.TestCase):
    def setUp(self):
        lifecycle.LocalPlayTests.setUp(self)
        self.lua.execute('''
            kicks={}
            function observeKicks()
                local original=host.network.kick
                host.network.kick=function(self,generation)
                    kicks[#kicks+1]=generation; return original(self,generation)
                end
            end
            function connected()
                ready(); observeKicks(); assert(host:canManageCompanion('kick'))
            end
            function disconnected()
                connected(); guest:stop(); step(8)
                assert(not host.network.link and not service.bindings.companion)
                assert(host:canManageCompanion('replace'))
            end
            function pendingKick()
                connected(); assert(host:selectCompanionDisconnect())
                generation=host.network.link.generation; failSave=true
                assert(host:disconnectCompanion())
                assert(host:managementStatus().phase=='saving' and service.pendingSave)
            end
            function retry()
                failSave=false; assert(service:retryCheckpoint())
                host:beginFrame(.016)
            end
            function makePanel(controller,runtime)
                texts={}
                love.graphics={newFont=function(size) return size end,getDimensions=function() return 960,720 end,
                    push=function() end,pop=function() end,origin=function() end,clear=function() end,
                    translate=function() end,scale=function() end,setFont=function() end,
                    setColor=function() end,rectangle=function() end,
                    printf=function(value) texts[#texts+1]=tostring(value) end}
                love.keyboard={setTextInput=function() end,isDown=function() return false end}
                panelContext={runtime=runtime,ui={},screenToGame=function(x,y) return x,y end}
                panel=require('game.local_play_panel').new(controller,panelContext)
                panel:draw()
            end
            function draw() panel:draw() end
            function click(id)
                local box=assert(panelContext.ui.localPlayControls[id],id)
                panel:click(box.x+box.w/2,box.y+box.h/2)
            end
            function keyActivate(id,key)
                local box=assert(panelContext.ui.localPlayControls[id],id)
                for index,control in ipairs(panel.controls) do if control==box then panel.selected=index end end
                panel:key(key or 'return')
            end
            function controlsFit()
                for i,a in ipairs(panel.controls) do
                    assert(a.x>=0 and a.y>=0 and a.x+a.w<=960 and a.y+a.h<=720)
                    for j,b in ipairs(panel.controls) do if i~=j then
                        assert(a.x+a.w<=b.x or b.x+b.w<=a.x or a.y+a.h<=b.y or b.y+b.h<=a.y)
                    end end
                end
            end
        ''')

    def tearDown(self):
        lifecycle.LocalPlayTests.tearDown(self)

    def test_failed_save_keeps_peer_then_external_retry_kicks_exactly_once(self):
        self.lua.execute('''
            pendingKick()
            local actor=assert(Schema.copy(data.players.companion)); local version=data.coop.network.bindingVersion
            local attempts=writes; step(20)
            assert(#kicks==0 and host.network.link.admitted and guest.phase=='connected')
            assert(writes==attempts and host:managementStatus().phase=='saving')
            assert(not host:cancelCompanionManagement())
            assert(not host:disconnectCompanion() and host.error=='management_busy')
            retry(); assert(#kicks==1 and kicks[1]==generation and not host:managementStatus())
            assert(saved.coop.network.bindingVersion==version and not service.bindings.companion)
            assert(data.players.companion.character==actor.character)
            assert(data.players.companion.stats.xp==actor.stats.xp)
            assert(data.players.companion.itemSlots.equipment[1].id==actor.itemSlots.equipment[1].id)
            step(20); assert(#kicks==1 and guest.phase=='idle' and guest.error=='host_kicked')
            assert(not guest:reconnectStatus() or not guest:reconnectStatus().active)
        ''')

    def test_old_confirmation_cannot_disconnect_actual_reconnected_generation(self):
        self.lua.execute('''
            connected(); assert(host:selectCompanionDisconnect()); local old=host.management.generation
            guest:stop(); step(6); assert(guest:join()); step(18)
            assert(guest.phase=='connected' and host.network.link.generation~=old)
            local newer=host.network.link.generation; local revision=data.coop.revision
            assert(not host:disconnectCompanion() and host.error=='stale_generation')
            assert(#kicks==0 and host.network.link.generation==newer and service.bindings.companion==newer)
            assert(data.coop.revision==revision and host:cancelCompanionManagement())
        ''')

    def test_delayed_durable_result_never_kicks_a_newer_link(self):
        self.lua.execute('''
            pendingKick(); local network=host.network; local old=network.link.generation
            -- Adversarial callback-boundary injection: a new admitted generation
            -- is present before finalization. Normal admission is save-barriered.
            network.link.generation=old+1
            service:disconnect('companion',old); assert(service:admit('companion',old+1))
            retry()
            assert(#kicks==0 and host.network.link.generation==old+1)
            assert(service.bindings.companion==old+1 and not host:managementStatus())
            host:beginFrame(.016); assert(#kicks==0)
        ''')

    def test_wrong_receipt_correlations_do_not_disconnect(self):
        self.lua.execute('''
            pendingKick(); failSave=false; assert(service:retryCheckpoint())
            local original=host.admission.managementResult
            local correct=assert(original(host.admission)); assert(correct.durable)
            for _,field in ipairs({'requestId','management','campaignId','companionId','bindingVersion','generation'}) do
                local wrong=assert(Schema.copy(correct))
                if field=='requestId' then wrong.requestId=wrong.requestId+1
                elseif field=='bindingVersion' or field=='generation' then wrong.result[field]=wrong.result[field]+1
                else wrong.result[field]='different' end
                host.admission.managementResult=function() return wrong end
                host:beginFrame(.016)
                assert(#kicks==0 and host.network.link and host:managementStatus())
                assert(host.error=='management_expired')
            end
            host.admission.managementResult=original
            host:beginFrame(.016); assert(#kicks==1 and not host.management)
        ''')

    def test_stop_and_campaign_slot_changes_invalidate_pending_management(self):
        self.lua.execute('''
            pendingKick(); local oldNetwork=host.network; local admission=host.admission
            host:stop(); assert(not host.management and not host.network and oldNetwork.closed)
            failSave=false; assert(service:retryCheckpoint()); host:beginFrame(.016)
            assert(#kicks==0 and not host.management)
        ''')
        # Separate real lifecycle instances make the slot/campaign boundary
        # assertions independent of the stop case and its pending checkpoint.
        for changed in ('slot', 'campaign'):
            with self.subTest(boundary=changed):
                self.tearDown()
                self.setUp()
                self.lua.globals().changed = changed
                self.lua.execute('''
                    pendingKick(); failSave=false; assert(service:retryCheckpoint())
                    if changed=='slot' then hostRuntime.selectedSlot=2
                    else hostRuntime.saveData=F.campaign(3,{scene='train'}) end
                    host:beginFrame(.016)
                    assert(host.phase=='idle' and not host.management and #kicks==0)
                ''')

    def test_replacement_requires_safe_disconnected_stopped_train(self):
        self.lua.execute('''
            connected()
            assert(not host:selectCompanionReplacement() and host.error=='companion_connected')
            guest:stop(); step(8); assert(host:canManageCompanion('replace'))
            local checks={
                {function() hostRuntime.scene='stop' end,function() hostRuntime.scene='train' end},
                {function() data.stopped=false end,function() data.stopped=true end},
                {function() hostRuntime.travelTransition={} end,function() hostRuntime.travelTransition=nil end},
                {function() hostRuntime.carTransition={} end,function() hostRuntime.carTransition=nil end},
                {function() hostRuntime.battle={} end,function() hostRuntime.battle=nil end},
                {function() hostRuntime.firstAid={} end,function() hostRuntime.firstAid=nil end},
                {function() hostRuntime.shootingRange={} end,function() hostRuntime.shootingRange=nil end},
                {function() hostRuntime.outfitCraftingOpen=true end,function() hostRuntime.outfitCraftingOpen=false end},
                {function() hostRuntime.exitPrompt={} end,function() hostRuntime.exitPrompt=nil end},
                {function() hostRuntime.travelConfirm=true end,function() hostRuntime.travelConfirm=false end},
                {function() hostContext.managementState=function() return {activityBlocked=true} end end,
                    function() hostContext.managementState=nil end},
                {function() service.activityState.resources.example={} end,function() service.activityState.resources.example=nil end},
                {function() data.tacticalBattle={} end,function() data.tacticalBattle=nil end},
                {function() data.events.current={} end,function() data.events.current=nil end},
            }
            for index,check in ipairs(checks) do
                check[1](); local ok,reason=host:canManageCompanion('replace')
                assert(not ok and reason=='replacement_unavailable','guard '..index..':'..tostring(reason))
                check[2](); assert(host:canManageCompanion('replace'),'restore '..index)
            end
            assert(guest:canManageCompanion('replace')==false)
            assert(not guest:selectCompanionDisconnect() and guest.error=='host_only')
            assert(not guest:selectCompanionReplacement() and guest.error=='host_only')
        ''')

    def test_actual_panel_mouse_keyboard_confirm_cancel_and_guest_controls(self):
        self.lua.execute('''
            connected(); host.menuOpen=true; makePanel(host,hostRuntime); controlsFit()
            assert(panelContext.ui.localPlayControls.disconnectCompanion.enabled)
            assert(not panelContext.ui.localPlayControls.changeCompanion.enabled)
            click('disconnectCompanion'); draw(); controlsFit()
            assert(host.management.phase=='confirm'); click('cancelManagement')
            assert(not host.management and #kicks==0)
            draw(); keyActivate('disconnectCompanion','space'); draw()
            panel:key('escape'); assert(not host.management and host.menuOpen and #kicks==0)
            draw(); click('disconnectCompanion'); draw(); failSave=true
            keyActivate('confirmDisconnect'); draw(); controlsFit()
            assert(host.management.phase=='saving' and not panelContext.ui.localPlayControls.confirmDisconnect)
            assert(not panelContext.ui.localPlayControls.cancelManagement and #kicks==0)
            panel:key('escape'); assert(host.management.phase=='saving')
            retry(); step(18); assert(#kicks==1)
            makePanel(guest,guestRuntime)
            assert(not panelContext.ui.localPlayControls.disconnectCompanion)
            assert(not panelContext.ui.localPlayControls.changeCompanion)
        ''')

    def test_actual_panel_replacement_preserves_items_progress_and_waits_for_save(self):
        self.lua.execute('''
            disconnected(); host.menuOpen=true; makePanel(host,hostRuntime); controlsFit()
            local actor=assert(Schema.copy(data.players.companion)); local old=data.coop.network.companionId
            click('changeCompanion'); draw(); controlsFit()
            assert(host.management.phase=='select' and not panelContext.ui.localPlayControls.confirmReplacement.enabled)
            click('confirmReplacement'); assert(data.players.companion.character==actor.character)
            keyActivate('nextReplacement'); draw()
            assert(host:replacementCharacter()~=actor.character and panelContext.ui.localPlayControls.confirmReplacement.enabled)
            local character=host:replacementCharacter()
            click('cancelManagement'); assert(not host.management and data.players.companion.character==actor.character)
            draw(); keyActivate('changeCompanion'); draw(); click('previousReplacement'); draw()
            assert(host:replacementCharacter()==character)
            failSave=true; keyActivate('confirmReplacement','space'); draw(); controlsFit()
            assert(host.management.phase=='saving' and not host:cancelCompanionManagement())
            assert(not panelContext.ui.localPlayControls.confirmReplacement and #kicks==0)
            local revision=data.coop.revision; step(12); assert(data.coop.revision==revision)
            retry(); assert(not host.management and #kicks==0)
            assert(saved.players.companion.character==character and saved.coop.network.companionId~=old)
            assert(saved.players.companion.itemSlots.equipment[1].id==actor.itemSlots.equipment[1].id)
            assert(saved.players.companion.stats.xp==actor.stats.xp and saved.players.companion.health<=actor.health)
            draw(); assert(panelContext.ui.localPlayControls.changeCompanion.enabled)
        ''')


if __name__ == '__main__':
    unittest.main()
