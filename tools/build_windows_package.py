"""Build a self-contained Windows portable game from the shared source."""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools.audit_coop_package import audit_love, binding_evidence, file_digest, pe_machine, source_files
from tools.build_mobile_package import runtime_asset, select_audio_sources

OUTPUT_ROOT = ROOT / "output" / "windows"
RUNTIME_FILES = ("love.dll", "lua51.dll", "mpg123.dll", "msvcp120.dll", "msvcr120.dll", "OpenAL32.dll", "SDL2.dll", "license.txt", "lovec.exe")


def resolve_output(path: Path | None) -> Path:
    result = (path or OUTPUT_ROOT).resolve()
    expected = OUTPUT_ROOT.resolve()
    if ROOT.resolve() not in expected.parents:
        raise ValueError("Windows output area resolves outside the project")
    if result != expected and expected not in result.parents:
        raise ValueError("Windows package output must stay inside output/windows")
    return result


def runtime_inventory(runtime: Path) -> dict:
    files = [runtime / "love.exe", *(runtime / name for name in RUNTIME_FILES)]
    for path in files:
        if not path.is_file():
            raise ValueError(f"Missing LÖVE portable runtime file: {path.name}")
        if path.suffix.lower() in (".exe", ".dll") and pe_machine(path.read_bytes()) != 0x8664:
            raise ValueError(f"Windows Local Play runtime must be x64: {path.name}")
    bindings = binding_evidence((runtime / "love.dll").read_bytes(), (runtime / "lua51.dll").read_bytes())
    return {"architecture": "x86_64", "nativeBindings": bindings,
            "files": {path.name: {"sha256": file_digest(path), "bytes": path.stat().st_size} for path in files}}


def inventory() -> dict[str, Path]:
    result = source_files(ROOT)
    for path in (ROOT / "assets").rglob("*"):
        if runtime_asset(path):
            if ROOT.resolve() not in path.resolve().parents:
                raise ValueError(f"External runtime asset: {path}")
            result[path.relative_to(ROOT).as_posix()] = path
    for path in select_audio_sources():
        result[path.relative_to(ROOT).as_posix()] = path
    return dict(sorted(result.items()))


def write_archive(path: Path, files: dict[str, Path]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, allowZip64=True) as archive:
            for name, source in sorted(files.items()):
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.external_attr = 0o644 << 16
                info.compress_type = zipfile.ZIP_STORED if source.suffix.lower() in {".png", ".jpg", ".jpeg", ".ogg", ".mp3"} else zipfile.ZIP_DEFLATED
                with source.open("rb") as reader, archive.open(info, "w", force_zip64=True) as writer:
                    shutil.copyfileobj(reader, writer, 1024 * 1024)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def fuse(engine: Path, game: Path, destination: Path) -> None:
    temporary = destination.with_suffix(".tmp")
    try:
        with temporary.open("wb") as writer:
            for source in (engine, game):
                with source.open("rb") as reader:
                    shutil.copyfileobj(reader, writer, 1024 * 1024)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def git_value(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def build(runtime: Path, requested_output: Path | None = None) -> dict:
    output = resolve_output(requested_output)
    native = runtime_inventory(runtime)
    output.mkdir(parents=True, exist_ok=True)
    game = output / "game.love"
    files = inventory()
    write_archive(game, files)
    audited = audit_love(game, ROOT)
    portable = output / "portable"
    # Only generated portable files are reset, after resolving the final path.
    if portable.resolve() != output / "portable" or portable.is_symlink():
        raise ValueError("Refusing to reset a portable directory outside the output area")
    if portable.exists():
        shutil.rmtree(portable)
    portable.mkdir()
    for name in RUNTIME_FILES:
        shutil.copy2(runtime / name, portable / name)
    executable = portable / "MouseFrontier.exe"
    fuse(runtime / "love.exe", game, executable)
    fused = audit_love(executable, ROOT)
    if fused["network"] != audited["network"]:
        raise ValueError("Fused executable contains a different shared game")
    report = {**audited, "platform": "Windows", "runtime": native, "sourceCommit": git_value("rev-parse", "HEAD"),
              "sourceDirty": bool(git_value("status", "--porcelain")), "gameArchive": str(game),
              "portableDirectory": str(portable), "fusedExecutableSha256": file_digest(executable),
              "runtimeFilesBundled": list(RUNTIME_FILES), "fusedEntryPointVerified": False,
              "packageNativeAcceptanceVerified": False, "physicalNetworkVerified": False,
              "runtimeAssets": len(files) - audited["luaFilesVerified"]}
    (portable / "package-audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (portable / "README.txt").write_text(
        "Mouse Frontier — Windows portable Local Play candidate\n\n"
        "Extract the entire ZIP, then open MouseFrontier.exe. Keep the included DLLs and license.txt beside it.\n"
        "Host a saved journey through Local Play (F8). One friend can join by automatic discovery or local IPv4 address and port.\n"
        "The host owns the save and story decisions; the companion can assist. Both copies must use the same gameplay build.\n"
        "ENet uses UDP 22124; local discovery uses UDP 22125. Permit this game on the private network when Windows asks.\n"
        "Internet play is deferred. Binary inspection is not a claim of physical-device or packaged-runtime acceptance.\n"
        "package-audit.json records the exact candidate. lovec.exe is the included engine for isolated validation harnesses.\n",
        encoding="utf-8")
    bundle = output / ("MouseFrontier-Windows-" + audited["network"]["build"][:12] + ".zip")
    write_archive(bundle, {path.relative_to(output).as_posix(): path for path in portable.rglob("*") if path.is_file()})
    report.update(portableZip=str(bundle), portableZipSha256=file_digest(bundle), portableZipBytes=bundle.stat().st_size)
    (output / "build-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--love-root", type=Path, default=Path("C:/Program Files/LOVE"))
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    print(json.dumps(build(args.love_root, args.output_dir), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
