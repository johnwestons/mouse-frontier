"""Render an explicit physical-leg guide for the shared eight-pose gait."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output" / "character-motion" / "shared" / "gait-pose-guide.png"
PHASE_OUTPUT = ROOT / "output" / "character-motion" / "shared" / "gait-pose-guides"
PHASES = (
    "1  LEFT CONTACT",
    "2  LEFT WEIGHT-DOWN",
    "3  RIGHT PASSING",
    "4  RIGHT KNEE-UP",
    "5  RIGHT CONTACT",
    "6  RIGHT WEIGHT-DOWN",
    "7  LEFT PASSING",
    "8  LEFT KNEE-UP",
)


def font(size: int) -> ImageFont.ImageFont:
    for name in ("C:/Windows/Fonts/arialbd.ttf", "C:/Windows/Fonts/arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def limb(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], color: str, width: int) -> None:
    draw.line(points, fill=color, width=width, joint="curve")
    radius = width // 2
    for x, y in points:
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)


def render() -> None:
    cell_w, cell_h = 400, 360
    canvas = Image.new("RGB", (cell_w * 4, cell_h * 2 + 90), "#f5f1e8")
    draw = ImageDraw.Draw(canvas)
    title_font, phase_font, key_font = font(28), font(19), font(22)
    draw.text((24, 16), "PHYSICAL-LEG GAIT GUIDE — FACING SCREEN-RIGHT", fill="#151515", font=title_font)
    draw.text((860, 20), "LEFT / near", fill="#009ec4", font=key_font)
    draw.text((1090, 20), "RIGHT / far", fill="#7044b8", font=key_font)
    draw.text((1340, 20), "arrow = travel", fill="#333333", font=key_font)
    draw.line((1510, 34, 1570, 34), fill="#333333", width=5)
    draw.polygon(((1570, 34), (1552, 23), (1552, 45)), fill="#333333")

    # Hip, knee, and foot points for physical-left and physical-right legs.
    poses = (
        (((198, 190), (236, 248), (300, 300)), ((184, 190), (164, 248), (112, 300))),
        (((198, 205), (224, 260), (270, 306)), ((184, 205), (164, 258), (125, 302))),
        (((198, 190), (228, 246), (274, 300)), ((184, 190), (205, 248), (200, 284))),
        (((198, 190), (170, 248), (128, 300)), ((184, 190), (236, 220), (280, 252))),
        (((198, 190), (164, 248), (112, 300)), ((184, 190), (236, 248), (300, 300))),
        (((198, 205), (164, 258), (125, 302)), ((184, 205), (224, 260), (270, 306))),
        (((198, 190), (205, 248), (200, 284)), ((184, 190), (228, 246), (274, 300))),
        (((198, 190), (236, 220), (280, 252)), ((184, 190), (170, 248), (128, 300))),
    )

    for index, (left_leg, right_leg) in enumerate(poses):
        column, row = index % 4, index // 4
        ox, oy = column * cell_w, 90 + row * cell_h
        draw.rectangle((ox + 2, oy + 2, ox + cell_w - 2, oy + cell_h - 2), outline="#b6afa2", width=3)
        draw.text((ox + 16, oy + 14), PHASES[index], fill="#151515", font=phase_font)
        # Far physical-right leg is drawn first and narrower.
        limb(draw, [(ox + x, oy + y) for x, y in right_leg], "#7044b8", 18)
        limb(draw, [(ox + x, oy + y) for x, y in left_leg], "#009ec4", 24)
        draw.ellipse((ox + 132, oy + 78, ox + 252, oy + 212), fill="#68635c", outline="#151515", width=5)
        draw.ellipse((ox + 146, oy + 55, ox + 238, oy + 140), fill="#8b857d", outline="#151515", width=5)
        draw.ellipse((ox + 176, oy + 174, ox + 204, oy + 202), fill="#151515")
        draw.text((ox + 30, oy + 322), "cyan = physical LEFT", fill="#007d9b", font=phase_font)
        draw.text((ox + 215, oy + 322), "violet = physical RIGHT", fill="#573493", font=phase_font)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUTPUT)
    PHASE_OUTPUT.mkdir(parents=True, exist_ok=True)
    for index, phase in enumerate(PHASES):
        column, row = index % 4, index // 4
        cell = canvas.crop(
            (
                column * cell_w,
                90 + row * cell_h,
                (column + 1) * cell_w,
                90 + (row + 1) * cell_h,
            )
        )
        slug = phase.split("  ", 1)[1].lower().replace("-", "_")
        cell.save(PHASE_OUTPUT / f"{index + 1}-{slug}.png")
    print(OUTPUT)


if __name__ == "__main__":
    render()
