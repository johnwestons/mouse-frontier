"""Exercise failed saves and serialization through the real Lua save modules."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipIf(LuaRuntime is None, "lupa is required for behavioral Lua checks")
class SaveReliabilityBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().project_root = ROOT.as_posix()
        self.lua.execute(r'''
            package.path=project_root..'/?.lua;'..package.path
            files={}; writes=0; failWrites=0
            love={filesystem={
                getInfo=function(path) return files[path] and {type='file'} end,
                createDirectory=function() return true end,
                write=function(path,contents)
                    writes=writes+1
                    if failWrites>0 then failWrites=failWrites-1; return false,'temporary I/O failure' end
                    files[path]=contents; return true
                end,
                read=function(path) return files[path] end,
                load=function(path) return loadstring(files[path] or '',path) end,
                remove=function(path) files[path]=nil; return true end,
            }}
            Save=require('game.save')
            Schema=require('game.save_schema')
            data=assert(Schema.migrate({character='scout-frog.png'}))
        ''')

    def test_debounced_write_retries_after_transient_failure(self) -> None:
        self.lua.execute(r'''
            failWrites=1
            assert(Save.schedule(1,data))
            Save.update(.3)
            assert(not files[Save.path(1)])
            data.scrap=17
            Save.update(.1)
            assert(writes==1,'retry respects debounce')
            Save.update(.2)
            assert(Save.read(1).scrap==17,'pending save survives failure with latest state')
            local completedWrites=writes
            Save.update(1)
            assert(writes==completedWrites,'successful save leaves no pending retry')
        ''')

    def test_failed_focus_flush_remains_available_for_later_flush(self) -> None:
        self.lua.execute(r'''
            Save.schedule(1,data); failWrites=1
            assert(Save.flush()==false)
            assert(Save.flush()==true)
            assert(Save.read(1).character=='scout-frog.png')
        ''')

    def test_nonfinite_nested_values_cannot_silently_disappear_from_save(self) -> None:
        self.lua.execute(r'''
            assert(Save.write(1,data))
            local original=files[Save.path(1)]
            for _,value in ipairs({math.huge,-math.huge,0/0}) do
                data.lastStand={pressure=value}
                assert(Save.write(1,data)==false)
                assert(files[Save.path(1)]==original,'invalid save must preserve primary')
                assert(not files[Save.path(1)..'.bak'],'invalid save must not replace backup')
            end
            data.lastStand={[math.huge]='invalid-key'}
            assert(Save.write(1,data)==false)
        ''')

    def test_valid_but_stale_primary_cannot_count_as_confirmed_write(self) -> None:
        self.lua.execute(r'''
            data.scrap=7; assert(Save.write(1,data))
            local old=files[Save.path(1)]; local write=love.filesystem.write
            love.filesystem.write=function(path,text)
                if path==Save.path(1) then return true end
                return write(path,text)
            end
            data.scrap=19; assert(not Save.write(1,data))
            assert(files[Save.path(1)]==old and Save.read(1).scrap==7)
            assert(files[Save.path(1)..'.tmp'])
            love.filesystem.write=write; assert(Save.write(1,data) and Save.read(1).scrap==19)
        ''')

    def test_valid_but_altered_temporary_file_is_rejected(self) -> None:
        self.lua.execute(r'''
            data.scrap=7; assert(Save.write(1,data))
            local old=files[Save.path(1)]; local write=love.filesystem.write
            love.filesystem.write=function(path,text)
                if path==Save.path(1)..'.tmp' then files[path]=old; return true end
                return write(path,text)
            end
            data.scrap=19; assert(not Save.write(1,data))
            assert(files[Save.path(1)]==old and not files[Save.path(1)..'.tmp'])
        ''')

    def test_filesystem_exception_keeps_pending_save_for_retry(self) -> None:
        self.lua.execute(r'''
            data.scrap=7; assert(Save.write(1,data)); data.scrap=19
            local write=love.filesystem.write
            love.filesystem.write=function(path,text)
                if path==Save.path(1) then error('I/O exception') end
                return write(path,text)
            end
            assert(Save.schedule(1,data) and not Save.flush(1))
            assert(Save.read(1).scrap==7)
            love.filesystem.write=write
            assert(Save.flush(1) and Save.read(1).scrap==19)
            love.filesystem.createDirectory=function() error('directory unavailable') end
            assert(not Save.write(1,data))
        ''')

    def test_failed_recovery_copy_cannot_replace_primary(self) -> None:
        self.lua.execute(r'''
            data.scrap=7; assert(Save.write(1,data)); local old=files[Save.path(1)]
            local write=love.filesystem.write
            love.filesystem.write=function(path,text)
                if path==Save.path(1)..'.bak' then return false end
                return write(path,text)
            end
            data.scrap=19; assert(not Save.write(1,data) and files[Save.path(1)]==old)
            love.filesystem.write=write; assert(Save.write(1,data) and Save.read(1).scrap==19)
        ''')

    def test_focus_and_shutdown_fail_when_live_campaign_cannot_be_queued(self) -> None:
        self.lua.execute(r'''
            local Session=require('game.game_session'); local session=Session.new()
            session:activate(data,{x=1,y=2}); session:selectSlot(1)
            local runtime={saveData=data,selectedSlot=1,syncForSave=function() end}
            local queued,flushed=false,0
            local persistence=require('game.persistence_runtime').new({runtime=runtime,ui={},session=session,
                save={schedule=function() return queued end,flush=function() flushed=flushed+1; return true end},
                maintenance={release=function() end},maintenanceSession={},focusMobile=function() end,
                focusAudio=function() end,shutdownAudio=function() end})
            assert(not persistence.checkpoint() and not persistence.focus(false) and not persistence.shutdown())
            assert(flushed==0,'an empty flush must not hide a scheduling failure')
            queued=true; assert(persistence.checkpoint() and flushed==1)
            session:setNetworkMode('client'); assert(not persistence.checkpoint() and flushed==1)
        ''')


if __name__ == "__main__":
    unittest.main()
