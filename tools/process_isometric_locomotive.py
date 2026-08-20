from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"C:\Users\johnw\.codex\generated_images\019fecb0-a456-7410-a95b-1e8ee57838ee\exec-4c6bd992-971a-4794-a058-e8cbdbb6b2c4.png")
OUTPUT = ROOT / "assets" / "sprites" / "train"
ANIMATIONS = OUTPUT / "animations"

sheet = Image.open(SOURCE).convert("RGBA")
cell_width = sheet.width // 4
cells = [sheet.crop((i * cell_width, 0, (i + 1) * cell_width, sheet.height)) for i in range(4)]

processed = []
boxes = []
for cell in cells:
    pixels = cell.load()
    for y in range(cell.height):
        for x in range(cell.width):
            r, g, b, _ = pixels[x, y]
            # The generated key varies slightly around #00ff00.
            is_key = g > 175 and g > r * 2.4 and g > b * 2.4
            if is_key:
                pixels[x, y] = (r, g, b, 0)
            else:
                # Remove green spill from the hard pixel edge without blurring it.
                if g > max(r, b) * 1.22:
                    g = max(r, b)
                pixels[x, y] = (r, g, b, 255)
    box = cell.getchannel("A").getbbox()
    boxes.append(box)
    processed.append(cell)

left = min(box[0] for box in boxes)
top = min(box[1] for box in boxes)
right = max(box[2] for box in boxes)
bottom = max(box[3] for box in boxes)
padding = 10
crop = (max(0, left - padding), max(0, top - padding), min(cell_width, right + padding), min(sheet.height, bottom + padding))
processed = [cell.crop(crop) for cell in processed]

OUTPUT.mkdir(parents=True, exist_ok=True)
ANIMATIONS.mkdir(parents=True, exist_ok=True)
destinations = [
    OUTPUT / "locomotive-red-isometric.png",
    ANIMATIONS / "locomotive-red-isometric-run-1.png",
    ANIMATIONS / "locomotive-red-isometric-run-2.png",
    ANIMATIONS / "locomotive-red-isometric-run-3.png",
]
for image, destination in zip(processed, destinations):
    image.save(destination, optimize=True)
    print(destination.relative_to(ROOT), image.size)
