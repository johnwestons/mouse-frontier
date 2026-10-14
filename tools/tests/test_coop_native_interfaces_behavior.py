"""Real LuaJIT declarations survive Refresh and module reloads."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.luajit21 import LuaRuntime


class NativeInterfaceTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute("package.path=root..'/?.lua;'..package.path; ffi=require('ffi'); M=require('game.net.interface_addresses')")

    def test_windows_c_types_are_reused_across_refresh_and_module_reload(self):
        self.lua.execute("""
            local cdef,load=ffi.cdef,ffi.load; local declarations,loads=0,0
            ffi.cdef=function(value) declarations=declarations+1; return cdef(value) end
            -- Keep actual LuaJIT ctypes and allocations. Only the unavailable
            -- OS library boundary is isolated for this deterministic test.
            ffi.load=function(name)
                assert(name=='iphlpapi'); loads=loads+1
                return {GetAdaptersAddresses=function() return 1 end}
            end
            assert(M.enumerate({os='Windows'})==nil)
            assert(M.enumerate({os='Windows'})==nil)
            package.loaded['game.net.interface_addresses']=nil
            M=require('game.net.interface_addresses'); assert(M.enumerate({os='Windows'})==nil)
            assert(declarations==1 and loads==3)
            assert(ffi.sizeof('mf_win_adapter')>0 and ffi.sizeof('mf_win_unicast')>0)
            ffi.cdef=cdef; ffi.load=load
        """)

    def test_posix_c_types_are_reused_across_refresh_and_module_reload(self):
        self.lua.execute("""
            local cdef,library=ffi.cdef,ffi.C; local declarations,calls=0,0
            ffi.cdef=function(value) declarations=declarations+1; return cdef(value) end
            ffi.C={getifaddrs=function(head) calls=calls+1; return -1 end,freeifaddrs=function() error('unexpected free') end}
            assert(M.enumerate({os='Linux'})==nil)
            assert(M.enumerate({os='Linux'})==nil)
            package.loaded['game.net.interface_addresses']=nil
            M=require('game.net.interface_addresses'); assert(M.enumerate({os='Linux'})==nil)
            assert(declarations==1 and calls==3)
            assert(ffi.sizeof('struct mf_ifaddrs')>0 and ffi.sizeof('struct mf_sockaddr_in')==16)
            ffi.cdef=cdef; ffi.C=library
        """)

    def test_actual_windows_refresh_and_reload_return_native_adapter_tables(self):
        if self.lua.eval('jit.os') != 'Windows':
            self.skipTest('actual Windows adapter enumeration needs Windows')
        count = self.lua.execute("a=M.enumerate({os='Windows'}); return a and #a or -1")
        if count == 0:
            self.skipTest('no active native IPv4 adapters on this machine')
        self.assertGreater(count, 0, 'native Windows adapter enumeration unavailable')
        self.lua.execute("""
            for index=1,4 do
                local current=M.enumerate({os='Windows'})
                assert(type(current)=='table' and #current>0, 'Refresh lost native adapters')
                assert(current~=a and current[1]~=a[1], 'Refresh reused mutable adapter entries')
            end
            package.loaded['game.net.interface_addresses']=nil
            M=require('game.net.interface_addresses')
            local current=M.enumerate({os='Windows'}); assert(type(current)=='table' and #current>0)
            local Address=require('game.net.address')
            local first=Address.detectLanInterfaces({native=true}); local second=Address.detectLanInterfaces({native=true})
            assert(type(first)=='table' and #first>0 and type(second)=='table' and #second>0,
                'address helper lost native adapters after Refresh')
            for _,entry in ipairs(current) do
                assert(Address.isIPv4(entry.address) and type(entry.interfaceName)=='string' and type(entry.isUsb)=='boolean')
            end
        """)

    def test_unsupported_platform_does_not_register_native_structs(self):
        self.lua.execute("""
            local cdef=ffi.cdef; ffi.cdef=function() error('unsupported platform declared native types') end
            local value,reason=M.enumerate({os='Unsupported'}); assert(value==nil and reason=='platform_unavailable')
            ffi.cdef=cdef
        """)


if __name__ == '__main__':
    unittest.main()
