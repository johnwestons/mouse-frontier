from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
PLANTS = ROOT / "assets" / "sprites" / "plants"
SIZE = 256
OFFSETS = (0, -1, -2, -1)


def planter_top(image: Image.Image) -> int:
    """Find the first dense horizontal band of brown planter/soil pixels."""
    pixels = image.load()
    alpha_box = image.getchannel("A").getbbox()
    if not alpha_box:
        return 160
    _, top, _, bottom = alpha_box
    qualifying = []
    for y in range(top, bottom):
        brown = 0
        for x in range(SIZE):
            r, g, b, a = pixels[x, y]
            if a and r > 42 and r > g * 1.18 and g > b * 1.08:
                brown += 1
        if brown >= 28:
            qualifying.append(y)
    runs = []
    for y in qualifying:
        if not runs or y - runs[-1][-1] > 4:
            runs.append([y])
        else:
            runs[-1].append(y)
    # The planter is the final substantial brown band near the sprite's feet;
    # earlier bands can be tomatoes, corn tassels, or brown stems.
    substantial = [run for run in runs if len(run) >= 4]
    if substantial:
        return substantial[-1][0]
    return top + round((bottom - top) * 0.62)


def bob_frame(base: Image.Image, seam: int, offset: int) -> Image.Image:
    if offset == 0:
        return base.copy()
    frame = base.copy()
    # Clear the living portion only; the planter and stem base remain anchored.
    frame.paste((0, 0, 0, 0), (0, 0, SIZE, seam))
    plant = base.crop((0, 0, SIZE, seam + 3))
    frame.alpha_composite(plant, (0, offset))
    return frame


for source in sorted(PLANTS.glob("*.png")):
    if "atlas" in source.stem or source.stem.endswith("-idle"):
        continue
    base = Image.open(source).convert("RGBA")
    seam = planter_top(base)
    frames = [bob_frame(base, seam, offset) for offset in OFFSETS]
    sheet = Image.new("RGBA", (SIZE * len(frames), SIZE), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (index * SIZE, 0))
    destination = source.with_name(source.stem + "-idle.png")
    sheet.save(destination, optimize=True)
    print(destination.relative_to(ROOT), "planter line", seam)
