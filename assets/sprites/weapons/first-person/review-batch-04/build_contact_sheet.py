from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "review-batch-04-contact-sheet.png"

ROWS = [
    (
        "WRIST-BRACED SLINGSHOT",
        [
            ("LOW READY", "wrist-braced-slingshot-low-ready-v1.png"),
            ("LOADED", "wrist-braced-slingshot-loaded-v1.png"),
            ("FULL DRAW / AIM", "wrist-braced-slingshot-full-draw-aim-v1.png"),
            ("RELEASE / RETURN", "wrist-braced-slingshot-release-band-return-v1.png"),
        ],
    ),
    (
        "METAL SCRAP SLINGSHOT",
        [
            ("LOW READY", "metal-scrap-slingshot-low-ready-v1.png"),
            ("LOADED", "metal-scrap-slingshot-loaded-v1.png"),
            ("FULL DRAW / AIM", "metal-scrap-slingshot-full-draw-aim-v1.png"),
            ("RELEASE / RETURN", "metal-scrap-slingshot-release-band-return-v1.png"),
        ],
    ),
    (
        "LONG HUNTING SLINGSHOT",
        [
            ("LOW READY", "long-hunting-slingshot-low-ready-v1.png"),
            ("LOADED", "long-hunting-slingshot-loaded-v1.png"),
            ("FULL DRAW / AIM", "long-hunting-slingshot-full-draw-aim-v1.png"),
            ("RELEASE / RETURN", "long-hunting-slingshot-release-band-return-v1.png"),
        ],
    ),
    (
        "SCRAP BOOMERANG",
        [
            ("READY / THROW", "scrap-boomerang-ready-throw-v1.png"),
            ("FLIGHT SPIN", "scrap-boomerang-flight-spin-v1.png"),
            ("RETURN / APPROACH", "scrap-boomerang-return-approach-v1.png"),
        ],
    ),
]

CANVAS_W = 2100
MARGIN = 28
GAP = 14
TITLE_H = 42
CELL_W = (CANVAS_W - (MARGIN * 2) - (GAP * 3)) // 4
CELL_H = 520
ROW_LABEL_H = 48
CANVAS_H = MARGIN + sum(ROW_LABEL_H + CELL_H + 30 for _ in ROWS)


def font(path: str, size: int):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


heading = font("C:/Windows/Fonts/arialbd.ttf", 28)
label = font("C:/Windows/Fonts/arialbd.ttf", 18)
meta = font("C:/Windows/Fonts/arial.ttf", 14)

sheet = Image.new("RGB", (CANVAS_W, CANVAS_H), "#151b22")
draw = ImageDraw.Draw(sheet)

y = MARGIN
for row_name, states in ROWS:
    draw.text((MARGIN, y), row_name, fill="#f2f5f8", font=heading)
    y += ROW_LABEL_H
    for column, (state_name, filename) in enumerate(states):
        x = MARGIN + column * (CELL_W + GAP)
        draw.rounded_rectangle(
            (x, y, x + CELL_W, y + CELL_H),
            radius=7,
            fill="#252e39",
            outline="#566475",
            width=2,
        )

        image = Image.open(ROOT / filename)
        alpha_status = "RGBA ALPHA" if "A" in image.getbands() else "RAW RGB CHECKERBOARD"
        draw.text((x + 16, y + 13), state_name, fill="#f3f6f9", font=label)
        draw.text((x + 16, y + 38), alpha_status, fill="#ffbc6e" if "RAW" in alpha_status else "#8de2aa", font=meta)

        rgba = image.convert("RGBA")
        max_w, max_h = CELL_W - 28, CELL_H - 82
        scale = min(max_w / rgba.width, max_h / rgba.height)
        thumb = rgba.resize(
            (max(1, round(rgba.width * scale)), max(1, round(rgba.height * scale))),
            Image.Resampling.NEAREST,
        )
        px = x + (CELL_W - thumb.width) // 2
        py = y + 69 + (max_h - thumb.height) // 2
        sheet.paste(thumb, (px, py), thumb if "A" in image.getbands() else None)

    y += CELL_H + 30

sheet.save(OUT)
print(OUT)
