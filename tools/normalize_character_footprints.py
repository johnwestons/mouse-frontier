"""Match every character portrait and animation to Hedgehog Botanist's footprint.

This pass never removes opaque pixels.  It crops only existing transparency,
rescales proportionally, centers horizontally, and uses the reference baseline.
"""
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1] / "assets" / "sprites"
PORTRAIT_DIRS = (ROOT / "MainCharacters", ROOT / "NPCS")
ANIMATION_ROOT = ROOT / "character-animations"
CANVAS = 512
# The Botanist proportions remain the guide, with a small extra safety margin
# so wide hats, ears, tails, and feet never appear clipped in the game view.
PORTRAIT_EXTENT = 380
ANIMATION_EXTENT = 385
BASELINE = 458

FRAME_COUNTS = {
    "idle.png": 2,
    "idle-variant.png": 1,
    "walk.png": 6,
    "sit.png": 2,
    "lay.png": 2,
    "melee.png": 3,
    "ranged.png": 3,
    "use.png": 3,
    "hit.png": 3,
    "unconscious.png": 2,
    "death.png": 3,
}


def safe_despill(image: Image.Image) -> Image.Image:
    """Remove exact chroma pixels and neutralize softer edge spill."""
    a = np.array(image.convert("RGBA"))
    alpha = a[:, :, 3]
    exact_key = (alpha > 0) & (a[:, :, 1] > 205) & (a[:, :, 0] < 80) & (a[:, :, 2] < 80)
    a[:, :, 3][exact_key] = 0
    alpha = a[:, :, 3]
    transparent = alpha == 0
    near = np.zeros_like(transparent)
    # Chroma halos can be two or three pixels thick after atlas resampling.
    # Recolor the halo, but never touch alpha or remove character pixels.
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            shifted = np.roll(np.roll(transparent, dy, axis=0), dx, axis=1)
            if dy < 0:
                shifted[dy:, :] = False
            elif dy > 0:
                shifted[:dy, :] = False
            if dx < 0:
                shifted[:, dx:] = False
            elif dx > 0:
                shifted[:, :dx] = False
            near |= shifted
    r = a[:, :, 0].astype(np.int16)
    g = a[:, :, 1].astype(np.int16)
    b = a[:, :, 2].astype(np.int16)
    spill = near & (alpha > 0) & (g > 95) & (g > r * 1.45) & (g > b * 1.45)
    a[:, :, 1][spill] = np.maximum(a[:, :, 0], a[:, :, 2])[spill]
    return Image.fromarray(a, "RGBA")


def normalize_frame(frame: Image.Image, extent: int) -> Image.Image:
    frame = safe_despill(frame)
    bbox = frame.getchannel("A").getbbox()
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    if not bbox:
        return canvas
    sprite = frame.crop(bbox)
    scale = min(extent / sprite.width, extent / sprite.height)
    size = (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale)))
    sprite = sprite.resize(size, Image.Resampling.LANCZOS)
    x = (CANVAS - sprite.width) // 2
    y = BASELINE - sprite.height
    canvas.alpha_composite(sprite, (x, y))
    # Resampling can blend a remaining chroma pixel back onto a transparent
    # edge, so de-spill once more on the finished frame. Alpha is preserved.
    return safe_despill(canvas)


def normalize_sheet(path: Path, frame_count: int) -> None:
    sheet = Image.open(path).convert("RGBA")
    if sheet.width % frame_count:
        raise ValueError(f"{path}: width {sheet.width} is not divisible by {frame_count}")
    frame_width = sheet.width // frame_count
    output = Image.new("RGBA", (CANVAS * frame_count, CANVAS), (0, 0, 0, 0))
    for index in range(frame_count):
        frame = sheet.crop((index * frame_width, 0, (index + 1) * frame_width, sheet.height))
        output.alpha_composite(normalize_frame(frame, ANIMATION_EXTENT), (index * CANVAS, 0))
    output.save(path, optimize=True)


portrait_count = 0
for directory in PORTRAIT_DIRS:
    for path in sorted(directory.glob("*.png")):
        normalize_frame(Image.open(path), PORTRAIT_EXTENT).save(path, optimize=True)
        portrait_count += 1

sheet_count = 0
for directory in sorted(ANIMATION_ROOT.iterdir()):
    if not directory.is_dir() or directory.name.startswith("new-options"):
        continue
    for filename, count in FRAME_COUNTS.items():
        path = directory / filename
        if path.exists():
            normalize_sheet(path, count)
            sheet_count += 1

print(f"normalized {portrait_count} portraits and {sheet_count} animation sheets")
