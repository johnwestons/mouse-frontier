"""Inspect actual release archives without launching a game or touching saves."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import struct
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ABIS = {"arm64-v8a": (2, 183), "armeabi-v7a": (1, 40), "x86_64": (2, 62)}
ENET_MARKERS = (b"enet_host\0", b"enet_peer\0", b"enet: failed to create host (already listening?)\0")
REQUIRED_MODULES = ("game/net/session.lua", "game/net/lan_discovery.lua", "game/net/interface_addresses.lua",
                    "game/net/crypto.lua", "game/coop_local_play.lua", "game/local_play_panel.lua")


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def file_digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def source_files(root: Path = ROOT) -> dict[str, Path]:
    files = [root / "main.lua", root / "conf.lua", *(root / "game").rglob("*.lua")]
    result = {}
    for path in files:
        if not path.is_file() or root.resolve() not in path.resolve().parents:
            raise ValueError(f"Missing or external shared source: {path}")
        result[path.relative_to(root).as_posix()] = path
    return result


def contract(lua: dict[str, bytes]) -> dict:
    for path in REQUIRED_MODULES:
        if path not in lua:
            raise ValueError(f"Missing Local Play module: {path}")
    schema = re.search(rb"CURRENT_VERSION\s*=\s*(\d+)", lua["game/save_schema.lua"])
    protocol = re.search(rb"\bVERSION\s*=\s*(\d+)", lua["game/net/protocol.lua"])
    if not schema or not protocol:
        raise ValueError("Cannot read packaged schema/protocol versions")
    schema_version, protocol_version = int(schema[1]), int(protocol[1])
    parts = ["mouse-frontier-code-v1", str(schema_version), str(protocol_version)]
    game = {name: value for name, value in lua.items() if name.startswith("game/")}
    for name, value in sorted(game.items()):
        parts.append(f"{len(name.encode('utf-8'))}:{name}:{len(value)}:{digest(value)}")
    return {"game": "mouse-frontier", "schema": schema_version, "protocol": protocol_version,
            "build": digest("\n".join(parts).encode("utf-8")), "files": len(game),
            "bytes": sum(map(len, game.values())), "requiredRuntimeModules": ["enet", "socket", "ffi"],
            "gamePort": 22124, "discoveryPort": 22125, "scope": "host plus one companion on LAN"}


def audit_love(package: Path | bytes, root: Path = ROOT) -> dict:
    source = source_files(root)
    raw = io.BytesIO(package) if isinstance(package, bytes) else package
    with zipfile.ZipFile(raw) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Game archive contains duplicate entries")
        for name in names:
            if name.startswith(("/", "\\")) or "\\" in name or ".." in name.split("/"):
                raise ValueError(f"Unsafe archive path: {name}")
            if name.split("/")[0] in {"saves", "output", ".stabilization", "backups", ".git"}:
                raise ValueError(f"Non-runtime data in game archive: {name}")
        lua_names = {name for name in names if name in {"main.lua", "conf.lua"} or name.startswith("game/") and name.endswith(".lua")}
        if lua_names != set(source):
            raise ValueError("Game archive has a stale shared Lua inventory")
        lua = {name: archive.read(name) for name in sorted(lua_names)}
        for name, value in lua.items():
            if value != source[name].read_bytes():
                raise ValueError(f"Game archive has stale shared source: {name}")
    return {"packageSha256": digest(package) if isinstance(package, bytes) else file_digest(package),
            "packageBytes": len(package) if isinstance(package, bytes) else package.stat().st_size, "luaFilesVerified": len(lua),
            "sharedSourceVerified": True, "network": contract(lua)}


def pe_machine(binary: bytes) -> int:
    if len(binary) < 64 or binary[:2] != b"MZ":
        raise ValueError("Not a Windows PE binary")
    offset = struct.unpack_from("<I", binary, 0x3C)[0]
    if offset + 6 > len(binary) or binary[offset:offset + 4] != b"PE\0\0":
        raise ValueError("Invalid Windows PE header")
    return struct.unpack_from("<H", binary, offset + 4)[0]


def elf_machine(binary: bytes) -> tuple[int, int]:
    if len(binary) < 20 or binary[:4] != b"\x7fELF" or binary[4] not in (1, 2) or binary[5] != 1:
        raise ValueError("Not a supported ELF binary")
    return binary[4], struct.unpack_from("<H" if binary[5] == 1 else ">H", binary, 18)[0]


def binding_evidence(engine: bytes, jit: bytes | None = None) -> dict:
    jit = engine if jit is None else jit
    evidence = {"enetBindingMarkers": all(marker in engine for marker in ENET_MARKERS),
                "luaSocketEntryPointName": b"luaopen_socket_core\0" in engine,
                "luaJitEntryPointName": b"luaJIT_setmode\0" in jit,
                "ffiEntryPointName": b"luaopen_ffi\0" in jit}
    if not all(evidence.values()):
        raise ValueError("Native binary lacks required networking/FFI evidence: " + ", ".join(name for name, present in evidence.items() if not present))
    return {**evidence, "method": "actual binary entry-point names and ENet binding markers",
            "inference": "compiled binding presence; not proof of module loading or socket access",
            "runtimeModuleLoadVerified": False, "physicalNetworkVerified": False}


def internet_permission(permission_dump: str) -> bool:
    return re.search(r"(?m)^uses-permission: name='android\.permission\.INTERNET'\s*$", permission_dump) is not None


def audit_apk(apk: Path, package: Path, root: Path = ROOT, permission_dump: str | None = None) -> dict:
    if permission_dump is None or not internet_permission(permission_dump):
        raise ValueError("Final APK permission dump lacks unconditional INTERNET permission")
    game = audit_love(package, root)
    libraries = {}
    with zipfile.ZipFile(apk) as archive:
        embedded_hash = hashlib.sha256()
        with archive.open("assets/game.love") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                embedded_hash.update(chunk)
        if embedded_hash.hexdigest() != game["packageSha256"]:
            raise ValueError("APK contains a different embedded game archive")
        for abi, expected in ABIS.items():
            name = f"lib/{abi}/liblove.so"
            binary = archive.read(name)
            if elf_machine(binary) != expected:
                raise ValueError(f"APK engine architecture differs from {abi}")
            libraries[abi] = {"sha256": digest(binary), "bytes": len(binary), **binding_evidence(binary)}
    return {**game, "apkSha256": file_digest(apk), "nativeBindings": libraries,
            "mergedInternetPermissionVerified": True, "permissionDumpSha256": digest(permission_dump.encode("utf-8"))}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--permissions-file", type=Path, help="Actual aapt dump permissions output for the final APK")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.apk and not args.permissions_file:
        parser.error("--apk requires --permissions-file from the actual built APK")
    report = audit_apk(args.apk, args.package, permission_dump=args.permissions_file.read_text(encoding="utf-8")) if args.apk else audit_love(args.package)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
