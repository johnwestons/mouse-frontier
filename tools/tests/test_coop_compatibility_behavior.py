"""Exact Lua content compatibility is independent of directory enumeration."""
from pathlib import Path
import hashlib
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class CompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.globals().pythonHash = lambda value: hashlib.sha256(value.encode('utf-8')).hexdigest()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            C=require('game.net.compatibility')
            files={['game/main.lua']='return 1',['game/net/state.lua']='return 2',['game/notes.txt']='ignored'}
            directories={game={'net','notes.txt','main.lua'},['game/net']={'state.lua'}}
            fs={getDirectoryItems=function(path) return directories[path] end,
                getInfo=function(path)
                    if directories[path] then return {type='directory'} end
                    if files[path] then return {type='file',size=#files[path]} end
                end,
                read=function(path) return files[path] end}
            function hash(value) return pythonHash(value) end
            function compute() local value,reason=C.compute(fs,hash); assert(value,reason); return value end
        ''')

    def test_sorted_paths_give_same_identity_and_noncode_notes_do_not_change_it(self):
        self.lua.execute('''
            local first=compute(); assert(first.files==2 and first.bytes==16 and first.schema==require('game.save_schema').CURRENT_VERSION)
            directories.game={'main.lua','notes.txt','net'}; files['game/notes.txt']='updated notes'
            assert(compute().build==first.build)
        ''')

    def test_changed_code_content_path_or_file_set_changes_identity(self):
        self.lua.execute('''
            local first=compute().build; files['game/main.lua']='return 3'; assert(compute().build~=first)
            files['game/main.lua']='return 1'; files['game/other.lua']=files['game/main.lua']; files['game/main.lua']=nil
            directories.game={'other.lua','net','notes.txt'}; assert(compute().build~=first)
            files['game/main.lua']='return 1'; directories.game[#directories.game+1]='main.lua'; assert(compute().build~=first)
        ''')

    def test_read_failure_size_race_and_hash_failure_do_not_fall_back_to_a_shared_tag(self):
        self.lua.execute('''
            fs.read=function() return nil end; assert(not C.compute(fs,hash))
            fs.read=function() return 'short' end; assert(not C.compute(fs,hash))
            fs.read=function(path) return files[path] end
            assert(not C.compute(fs,function() return nil end))
            assert(not C.compute(fs,function() error('unavailable') end))
        ''')

    def test_oversized_files_and_unsafe_directory_entries_fail_closed(self):
        self.lua.execute('''
            local info=fs.getInfo
            fs.getInfo=function(path) if path=='game/main.lua' then return {type='file',size=C.MAX_FILE_BYTES+1} end; return info(path) end
            assert(not C.compute(fs,hash)); fs.getInfo=info
            for _,name in ipairs({'..','../other','net/other','net'..string.char(92)..'other'}) do
                directories.game={name}; assert(not C.compute(fs,hash))
            end
            directories.game={}; assert(not C.compute(fs,hash))
        ''')

if __name__ == '__main__':
    unittest.main()
