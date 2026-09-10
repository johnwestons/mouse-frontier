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


if __name__ == "__main__":
    unittest.main()
