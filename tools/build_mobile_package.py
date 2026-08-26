"""Build the shared Mouse Frontier source into a phone-sized .love package."""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError as exc:
    raise SystemExit("Pillow is required. Install it with: python -m pip install Pillow") from exc


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "mobile" / "config.json"
OUTPUT_ROOT = ROOT / "output" / "mobile"
STAGE_ROOT = OUTPUT_ROOT / "stage"
CACHE_ROOT = OUTPUT_ROOT / "cache"
FFMPEG_URL = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
FFMPEG_SHA_URL = FFMPEG_URL + ".sha256"
ACTIONS = {"idle", "sit", "lay", "walk", "melee", "ranged", "use", "hit", "death", "unconscious"}
AUDIO_EXTENSIONS = {".wav", ".mp3", ".ogg", ".flac"}
EXCLUDED_RUNTIME_AUDIO_PREFIXES = (
    "sounds/soundeffects/hurtmale/",
    "sounds/soundeffects/hurtmob/",
    "sounds/soundeffects/nature/",
    "sounds/soundeffects/train/traintraveling/",
)
EXCLUDED_RUNTIME_AUDIO_FILES = {
    "sounds/soundeffects/rain/rainlit shelter.mp3",  # Music duplicated into the old ambience pool.
    "sounds/soundeffects/rain/865261__robo9418__rain-hitting-window.wav",  # Outside the curated rain level range.
}


def safe_clean(path: Path) -> None:
    resolved = path.resolve()
    output = OUTPUT_ROOT.resolve()
    if resolved == output or output not in resolved.parents:
        raise RuntimeError(f"Refusing to clean path outside the mobile output area: {resolved}")
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def cache_key(source: Path, operation: str) -> str:
    stat = source.stat()
    payload = f"{source.resolve()}|{stat.st_size}|{stat.st_mtime_ns}|{operation}".encode()
    return hashlib.sha256(payload).hexdigest()


def link_or_copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(source, destination)
    except OSError:
        shutil.copy2(source, destination)


def runtime_asset(source: Path) -> bool:
    relative = source.relative_to(ROOT).as_posix()
    if relative.startswith("assets/source/"):
        return False
    if relative.startswith("assets/sprites/character-animations/"):
        if source.name == "base.png" or "source" in source.stem or source.stem.startswith("complete"):
            return False
        if source.suffix.lower() == ".png" and source.stem not in ACTIONS:
            return False
    return source.is_file()


def image_bounds(relative: str, config: dict) -> tuple[int, int]:
    fullscreen = relative.startswith((
        "assets/backgrounds/",
        "assets/sprites/interiors/",
        "assets/sprites/stops/",
    ))
    if fullscreen:
        return config["fullscreenImageWidth"], config["fullscreenImageHeight"]
    return config["generalImageWidth"], config["generalImageHeight"]


def optimize_image(source: Path, destination: Path, relative: str, config: dict) -> tuple[int, int]:
    if source.name.startswith("walkmask-"):
        link_or_copy(source, destination)
        return source.stat().st_size, destination.stat().st_size
    max_width, max_height = image_bounds(relative, config)
    operation = f"png-v3-{max_width}x{max_height}-p{config['imagePaletteColors']}"
    cached = CACHE_ROOT / "images" / (cache_key(source, operation) + ".png")
    if not cached.exists():
        cached.parent.mkdir(parents=True, exist_ok=True)
        temporary = cached.with_suffix(".tmp.png")
        with Image.open(source) as opened:
            image = opened.convert("RGBA")
            image.thumbnail((max_width, max_height), Image.Resampling.LANCZOS)
            image = image.quantize(
                colors=config["imagePaletteColors"],
                method=Image.Quantize.FASTOCTREE,
                dither=Image.Dither.NONE,
            )
            image.save(temporary, "PNG", optimize=True, compress_level=9)
        temporary.replace(cached)
    link_or_copy(cached, destination)
    return source.stat().st_size, destination.stat().st_size


def normalized_music_stem(stem: str) -> str:
    normalized = stem.casefold()
    while True:
        updated = re.sub(r"\s*\(1\)$", "", normalized)
        updated = re.sub(r"[12]$", "", updated)
        if updated == normalized:
            return normalized
        normalized = updated


def runtime_audio(relative: str) -> bool:
    folded = relative.casefold()
    return folded not in EXCLUDED_RUNTIME_AUDIO_FILES and not folded.startswith(EXCLUDED_RUNTIME_AUDIO_PREFIXES)


def select_audio_sources() -> list[Path]:
    sources = [path for path in (ROOT / "sounds").rglob("*") if path.suffix.lower() in AUDIO_EXTENSIONS]
    selected: list[Path] = []
    music_groups: dict[tuple[str, str], list[Path]] = {}
    for source in sources:
        relative = source.relative_to(ROOT).as_posix()
        if not runtime_audio(relative):
            continue
        if relative.startswith("sounds/music/"):
            key = (source.parent.as_posix(), normalized_music_stem(source.stem))
            music_groups.setdefault(key, []).append(source)
        else:
            selected.append(source)
    for candidates in music_groups.values():
        candidates.sort(key=lambda path: (
            normalized_music_stem(path.stem) != path.stem.casefold(),
            len(path.stem),
            path.name.casefold(),
        ))
        selected.append(candidates[0])
    return sorted(selected)


def find_or_download_ffmpeg(explicit: str | None) -> Path:
    if explicit:
        candidate = Path(explicit).resolve()
        if candidate.is_file():
            return candidate
        raise FileNotFoundError(candidate)
    found = shutil.which("ffmpeg")
    if found:
        return Path(found)
    tool_root = OUTPUT_ROOT / "tooling" / "ffmpeg"
    existing = next(tool_root.rglob("ffmpeg.exe"), None) if tool_root.exists() else None
    if existing:
        return existing
    archive = OUTPUT_ROOT / "tooling" / "ffmpeg-release-essentials.zip"
    archive.parent.mkdir(parents=True, exist_ok=True)
    print("Downloading the FFmpeg audio converter (one-time mobile build dependency)...", flush=True)
    urllib.request.urlretrieve(FFMPEG_URL, archive)
    expected_text = urllib.request.urlopen(FFMPEG_SHA_URL, timeout=60).read().decode().strip()
    expected = re.search(r"[0-9a-fA-F]{64}", expected_text)
    if not expected:
        raise RuntimeError("Could not read the published FFmpeg SHA-256")
    actual = hashlib.sha256(archive.read_bytes()).hexdigest()
    if actual.casefold() != expected.group(0).casefold():
        archive.unlink(missing_ok=True)
        raise RuntimeError("Downloaded FFmpeg archive failed its published SHA-256 check")
    with zipfile.ZipFile(archive) as bundle:
        bundle.extractall(tool_root)
    executable = next(tool_root.rglob("ffmpeg.exe"), None)
    if not executable:
        raise RuntimeError("The FFmpeg archive did not contain ffmpeg.exe")
    return executable


def transcode_audio(source: Path, destination: Path, relative: str, ffmpeg: Path, config: dict) -> tuple[int, int]:
    quality = config["musicVorbisQuality"] if relative.startswith("sounds/music/") else config["soundEffectVorbisQuality"]
    operation = f"vorbis-v2-q{quality}"
    cached = CACHE_ROOT / "audio" / (cache_key(source, operation) + ".ogg")
    if not cached.exists():
        cached.parent.mkdir(parents=True, exist_ok=True)
        temporary = cached.with_suffix(".tmp.ogg")
        command = [str(ffmpeg), "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", str(source), "-vn", "-c:a", "libvorbis", "-q:a", str(quality), str(temporary)]
        subprocess.run(command, check=True)
        temporary.replace(cached)
    link_or_copy(cached, destination)
    return source.stat().st_size, destination.stat().st_size


def git_value(*arguments: str) -> str | None:
    try:
        return subprocess.check_output(["git", *arguments], cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def generate_android_icons() -> None:
    source = ROOT / "assets" / "sprites" / "MainCharacters" / "mouse-engineer.png"
    icon_root = OUTPUT_ROOT / "android-res"
    with Image.open(source) as opened:
        character = opened.convert("RGBA")
        character.thumbnail((390, 390), Image.Resampling.NEAREST)
    master = Image.new("RGBA", (512, 512), "#1b110b")
    draw = ImageDraw.Draw(master)
    draw.rounded_rectangle((20, 20, 492, 492), radius=104, fill="#382015", outline="#e19b32", width=20)
    draw.ellipse((76, 76, 436, 436), fill="#24150e", outline="#8d4f21", width=12)
    master.alpha_composite(character, ((512-character.width)//2, 92+(390-character.height)//2))
    for density, size in {"mdpi":48,"hdpi":72,"xhdpi":96,"xxhdpi":144,"xxxhdpi":192}.items():
        destination = icon_root / f"drawable-{density}" / "love.png"
        destination.parent.mkdir(parents=True, exist_ok=True)
        master.resize((size,size),Image.Resampling.LANCZOS).save(destination,"PNG",optimize=True)


def build(args: argparse.Namespace) -> Path:
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    CACHE_ROOT.mkdir(parents=True, exist_ok=True)
    safe_clean(STAGE_ROOT)

    for source in [ROOT / "main.lua", ROOT / "conf.lua", *(ROOT / "game").rglob("*.lua")]:
        destination = STAGE_ROOT / source.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)

    images = [path for path in (ROOT / "assets").rglob("*") if runtime_asset(path)]
    image_sources = [path for path in images if path.suffix.lower() == ".png"]
    other_assets = [path for path in images if path.suffix.lower() != ".png"]
    totals = {"sourceBytes": 0, "stagedBytes": 0, "images": len(image_sources), "audio": 0, "other": len(other_assets)}

    def image_job(source: Path) -> tuple[int, int]:
        relative = source.relative_to(ROOT).as_posix()
        return optimize_image(source, STAGE_ROOT / Path(relative), relative, config)

    print(f"Optimizing {len(image_sources)} runtime images...", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(2, min(8, os.cpu_count() or 2))) as executor:
        for original, staged in executor.map(image_job, image_sources):
            totals["sourceBytes"] += original
            totals["stagedBytes"] += staged

    for source in other_assets:
        destination = STAGE_ROOT / source.relative_to(ROOT)
        link_or_copy(source, destination)
        totals["sourceBytes"] += source.stat().st_size
        totals["stagedBytes"] += destination.stat().st_size

    audio_sources = select_audio_sources()
    totals["audio"] = len(audio_sources)
    ffmpeg = find_or_download_ffmpeg(args.ffmpeg)

    def audio_job(source: Path) -> tuple[int, int]:
        relative_path = source.relative_to(ROOT)
        relative = relative_path.as_posix()
        destination = STAGE_ROOT / relative_path.with_suffix(".ogg")
        return transcode_audio(source, destination, relative, ffmpeg, config)

    print(f"Transcoding {len(audio_sources)} runtime audio files...", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, min(4, (os.cpu_count() or 2) // 2))) as executor:
        for original, staged in executor.map(audio_job, audio_sources):
            totals["sourceBytes"] += original
            totals["stagedBytes"] += staged

    manifest = {
        "applicationId": config["applicationId"],
        "applicationName": config["applicationName"],
        "versionName": config["versionName"],
        "versionCode": config["versionCode"],
        "loveVersion": config["loveVersion"],
        "sourceCommit": git_value("rev-parse", "HEAD"),
        "sourceDirty": bool(git_value("status", "--porcelain")),
        "assetCounts": {key: totals[key] for key in ("images", "audio", "other")},
        "sourceBytes": totals["sourceBytes"],
        "stagedBytes": totals["stagedBytes"],
    }
    (STAGE_ROOT / "mobile-build.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    package = OUTPUT_ROOT / f"mouse-frontier-{config['versionName']}.love"
    temporary_package = package.with_suffix(".tmp.love")
    temporary_package.unlink(missing_ok=True)
    print("Creating the shared Android game package...", flush=True)
    with zipfile.ZipFile(temporary_package, "w", allowZip64=True) as archive:
        for source in sorted(path for path in STAGE_ROOT.rglob("*") if path.is_file()):
            relative = source.relative_to(STAGE_ROOT).as_posix()
            compressed = source.suffix.lower() not in {".png", ".ogg", ".jpg", ".jpeg"}
            archive.write(source, relative, zipfile.ZIP_DEFLATED if compressed else zipfile.ZIP_STORED)
    temporary_package.replace(package)
    manifest["package"] = str(package)
    manifest["packageBytes"] = package.stat().st_size
    report = OUTPUT_ROOT / "build-report.json"
    report.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    generate_android_icons()
    print(json.dumps(manifest, indent=2), flush=True)
    return package


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", help="Path to ffmpeg; downloaded and verified when omitted")
    args = parser.parse_args()
    package = build(args)
    print(f"Mobile package ready: {package}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
