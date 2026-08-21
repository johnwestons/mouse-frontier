from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GEN = Path(r"C:\Users\johnw\.codex\generated_images\019ff205-5bd9-7b10-ac24-1303d9d44234")
SOURCES = {
    "ferret-scout": "exec-f3c9d895-5949-43d2-8c7f-4edf30e4725e.png",
    "gecko-herbalist": "exec-1ddd064e-86ad-45d7-9b15-d8b078694d51.png",
    "mechanic-raccoon": "exec-40869ec7-1423-4b2d-b7eb-725e4d96207c.png",
    "watch-raccoon": "exec-e818e6ae-fc4e-4227-8512-9fd6a601cd49.png",
    "medic-fox": "exec-f510c3ee-7f09-4ca5-9ea5-1411f85ebd4a.png",
}

CELL = 512

def fit_pose(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if not bbox:
        raise ValueError(f"generated pose has no visible pixels: {path}")
    image = image.crop(bbox)
    # Keep the defeat pose on the same baseline and scale as the authored sheets.
    max_w, max_h = 420, 365
    scale = min(max_w / image.width, max_h / image.height, 1.0)
    image = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.Resampling.NEAREST)
    frame = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    frame.alpha_composite(image, ((CELL - image.width) // 2, CELL - image.height - 46))
    return frame

for name, filename in SOURCES.items():
    frame = fit_pose(GEN / filename)
    frames = []
    for dx, dy in ((-3, 2), (0, 0), (2, 1)):
        f = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        f.alpha_composite(frame, (dx, dy))
        frames.append(f)
    sheet = Image.new("RGBA", (CELL * len(frames), CELL), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.alpha_composite(f, (i * CELL, 0))
    out = ROOT / "assets" / "sprites" / "character-animations" / name / "death.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"wrote {out}")
