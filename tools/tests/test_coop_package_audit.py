"""Archive and native evidence audits use synthetic files, never a game/device."""
from pathlib import Path
import hashlib
import json
import os
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime
from tools import audit_coop_package as audit
from tools import build_windows_package as windows
from tools import build_mobile_package as mobile


class CoopPackageAuditTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / 'project'
        self.root.mkdir()
        self.files = {'main.lua': b'require("game.net.session")', 'conf.lua': b'function love.conf(t) end',
                      'game/save_schema.lua': b'local SaveSchema={CURRENT_VERSION=44};return SaveSchema',
                      'game/net/protocol.lua': b'local P={VERSION=28};return P'}
        self.files.update({name: b'return {}' for name in audit.REQUIRED_MODULES})
        for name, value in self.files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value)
        self.game = self.root / 'game.love'
        self.archive(self.game, self.files)

    @staticmethod
    def archive(path, files):
        with zipfile.ZipFile(path, 'w') as archive:
            for name, value in files.items():
                archive.writestr(name, value)

    @staticmethod
    def native(abi, bindings=True):
        bit, machine = audit.ABIS[abi]
        value = bytearray(64)
        value[:6] = b'\x7fELF' + bytes((bit, 1))
        struct.pack_into('<H', value, 18, machine)
        return bytes(value) + (b''.join(audit.ENET_MARKERS) if bindings else b'') + b'luaopen_socket_core\0luaopen_ffi\0luaJIT_setmode\0'

    @staticmethod
    def pe(machine=0x8664, suffix=b''):
        value = bytearray(128)
        value[:2] = b'MZ'
        struct.pack_into('<I', value, 0x3C, 64)
        value[64:68] = b'PE\0\0'
        struct.pack_into('<H', value, 68, machine)
        return bytes(value) + suffix

    def apk(self, abi_missing=None, embedded=None, binding_missing=None, wrong_abi=None):
        path = self.root / 'game.apk'
        files = {'assets/game.love': embedded if embedded is not None else self.game.read_bytes()}
        for abi in audit.ABIS:
            if abi != abi_missing:
                files[f'lib/{abi}/liblove.so'] = self.native(wrong_abi or abi, abi != binding_missing)
        self.archive(path, files)
        return path

    def test_actual_archive_requires_exact_current_shared_lua_inventory_and_bytes(self):
        value = audit.audit_love(self.game, self.root)
        self.assertEqual(value['network']['schema'], 44)
        self.assertEqual(value['network']['protocol'], 28)
        self.assertEqual(value['luaFilesVerified'], len(self.files))
        (self.root / 'game/new.lua').write_text('return {}')
        with self.assertRaisesRegex(ValueError, 'stale shared Lua inventory'):
            audit.audit_love(self.game, self.root)
        (self.root / 'game/new.lua').unlink()
        (self.root / 'game/net/session.lua').write_text('return {changed=true}')
        with self.assertRaisesRegex(ValueError, 'stale shared source'):
            audit.audit_love(self.game, self.root)

    def test_source_compatibility_hash_matches_production_lua_algorithm(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().root = ROOT.as_posix()
        lua.execute("package.path=root..'/?.lua;'..package.path")
        # Use actual project source, schema and protocol; no gameplay is run.
        files = {name: path.read_bytes() for name, path in audit.source_files(ROOT).items()}
        filesystem = lua.table()
        def listing(directory):
            prefix = directory + '/'
            return lua.table_from(sorted({name[len(prefix):].split('/')[0] for name in files if name.startswith(prefix)}))
        def info(name):
            if name in files:
                return lua.table_from({'type': 'file', 'size': len(files[name])})
            return lua.table_from({'type': 'directory'})
        filesystem.getDirectoryItems = listing
        filesystem.getInfo = info
        filesystem.read = lambda name: files[name].decode('utf-8')
        lua.globals().filesystem = filesystem
        lua.globals().hashBytes = lambda value: hashlib.sha256(value.encode('utf-8')).hexdigest()
        actual = lua.eval("require('game.net.compatibility').compute")(filesystem, lua.globals().hashBytes)
        if isinstance(actual, tuple):
            actual = actual[0]
        expected = audit.contract(files)
        for key in ('build', 'schema', 'protocol', 'files', 'bytes'):
            self.assertEqual(expected[key], actual[key])

    def test_actual_apk_requires_embedded_hash_all_abis_and_binary_binding_evidence(self):
        permission = "package: com.mousefrontier.game\nuses-permission: name='android.permission.INTERNET'\n"
        report = audit.audit_apk(self.apk(), self.game, self.root, permission)
        self.assertTrue(report['mergedInternetPermissionVerified'])
        self.assertEqual(set(report['nativeBindings']), set(audit.ABIS))
        for value in report['nativeBindings'].values():
            self.assertFalse(value['runtimeModuleLoadVerified'])
            self.assertFalse(value['physicalNetworkVerified'])
        for kwargs in ({'embedded': b'stale game'}, {'abi_missing': 'x86_64'},
                       {'binding_missing': 'arm64-v8a'}, {'wrong_abi': 'x86_64'}):
            with self.subTest(kwargs=kwargs), self.assertRaises((ValueError, KeyError)):
                audit.audit_apk(self.apk(**kwargs), self.game, self.root, permission)

    def test_permission_source_overlay_is_not_a_substitute_for_final_apk_dump(self):
        apk = self.apk()
        for dump in (None, '', "uses-permission: name='android.permission.VIBRATE'",
                     "uses-permission-sdk-23: name='android.permission.INTERNET'",
                     "uses-permission: name='android.permission.INTERNET' maxSdkVersion='24'"):
            with self.subTest(dump=dump), self.assertRaisesRegex(ValueError, 'INTERNET'):
                audit.audit_apk(apk, self.game, self.root, dump)

    def test_game_archive_rejects_save_data_unsafe_paths_and_duplicate_entries(self):
        for name in ('saves/save1.json', '../game.lua', '/outside.lua', 'game\\outside.lua'):
            with self.subTest(name=name):
                self.archive(self.game, {**self.files, name: b'private'})
                with self.assertRaises(ValueError):
                    audit.audit_love(self.game, self.root)

    def test_native_metadata_rejects_wrong_or_truncated_platform_binaries(self):
        self.assertEqual(audit.pe_machine(self.pe()), 0x8664)
        self.assertEqual(audit.elf_machine(self.native('arm64-v8a')), (2, 183))
        for value in (b'', b'MZ', b'\x7fELF'):
            with self.assertRaises(ValueError):
                audit.pe_machine(value)
            with self.assertRaises(ValueError):
                audit.elf_machine(value)
        with self.assertRaises(ValueError):
            audit.binding_evidence(self.pe(), self.pe())

    def test_portable_builder_bundles_runtime_license_and_fuses_exact_game_without_source_outputs(self):
        runtime = self.root / 'engine'
        runtime.mkdir()
        for name in ('love.exe', *windows.RUNTIME_FILES):
            (runtime / name).write_bytes(b'license' if name.endswith('.txt') else self.pe())
        (runtime / 'love.dll').write_bytes(self.pe(suffix=b''.join(audit.ENET_MARKERS) + b'luaopen_socket_core\0'))
        (runtime / 'lua51.dll').write_bytes(self.pe(suffix=b'luaopen_ffi\0luaJIT_setmode\0'))
        assets = self.root / 'assets'; assets.mkdir(); (assets / 'font.ttf').write_bytes(b'font')
        (self.root / 'sounds').mkdir()
        output = self.root / 'output/windows'
        with patch.object(windows, 'ROOT', self.root), patch.object(windows, 'OUTPUT_ROOT', output), \
             patch.object(mobile, 'ROOT', self.root), patch.object(windows, 'git_value', side_effect=lambda *args: '' if args[0] == 'status' else 'test-head'):
            report = windows.build(runtime)
            portable = Path(report['portableDirectory'])
            self.assertTrue((portable / 'license.txt').is_file())
            self.assertTrue((portable / 'lovec.exe').is_file())
            self.assertFalse(report['fusedEntryPointVerified'])
            fused = audit.audit_love(portable / 'MouseFrontier.exe', self.root)
            self.assertEqual(fused['network'], report['network'])
            with zipfile.ZipFile(report['gameArchive']) as archive:
                self.assertIn('assets/font.ttf', archive.namelist())
                self.assertFalse(any(name.startswith(('output/', 'engine/', 'saves/')) for name in archive.namelist()))
            with self.assertRaises(ValueError):
                windows.resolve_output(self.root.parent / 'outside')
        (runtime / 'lua51.dll').write_bytes(self.pe(machine=0x14C))
        with self.assertRaisesRegex(ValueError, 'x64'):
            windows.runtime_inventory(runtime)


if __name__ == '__main__':
    unittest.main()
