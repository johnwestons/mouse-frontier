"""Local Play owns both save-slot selectors and launches hosting directly."""
import unittest
import test_coop_local_play_behavior as local_play

class LocalSlotsTests(unittest.TestCase):
    def setUp(self):
        local_play.LocalPlayTests.setUp(self)
        self.lua.execute('''
            slots={
                [1]={character='cook-mouse.png',stats={level=3},location=7},
                [3]={character='medic-mouse.png',stats={level=5},location=18},
            }
            guest.context.readSlot=function(slot) return slots[slot] end
            host.context.readSlot=guest.context.readSlot
        ''')

    def test_join_requires_a_real_selected_local_save_and_uses_its_character(self):
        self.lua.execute('''
            assert(not guest:canJoin())
            local ok,reason=guest:join(); assert(not ok and reason=='select_local_slot' and guest.slotPicker)
            assert(not guest:selectSaveSlot(2))
            assert(guest:selectSaveSlot(3) and not guest.slotPicker)
            assert(guest:canJoin() and guest:character()=='medic-mouse.png')
            assert(guest.localSlots[3].level==5 and guest.localSlots[3].location==18)
            assert(guestRuntime.saveData==guestData)
        ''')

    def test_host_loads_selection_and_starts_without_leaving_for_title_slot_controls(self):
        self.lua.execute('''
            hostRuntime.state='slots'
            host.context.enterSavedJourney=function(data)
                assert(data==slots[3] and hostRuntime.selectedSlot==3)
                hostRuntime.saveData=data; hostRuntime.state='game'; return true
            end
            local count=0
            host.host=function(self)
                assert(hostRuntime.saveData==slots[3] and hostRuntime.selectedSlot==3)
                count=count+1; self.phase='hosting'; return true
            end
            assert(host:chooseSaveSlot() and host:selectSaveSlot(3))
            assert(host:hostSavedJourney() and count==1 and not host.hostingIntent and not host.menuOpen)
        ''')

    def test_deleted_selection_is_cleared_and_cancel_stays_in_local_play(self):
        self.lua.execute('''
            assert(guest:chooseSaveSlot() and guest:selectSaveSlot(1))
            slots[1]=nil; guest:refreshSaveSlots()
            assert(not guest.selectedLocalSlot and not guest:canJoin())
            guest.menuOpen=true; assert(guest:chooseSaveSlot()); assert(guest:closeMenu())
            assert(guest.menuOpen and not guest.slotPicker)
        ''')
