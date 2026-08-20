from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"C:\Users\johnw\.codex\generated_images\019fecb0-a456-7410-a95b-1e8ee57838ee")
OUTPUT = ROOT / "assets" / "sprites" / "battle-maps"
SHEETS = {
    "exec-ffd296d8-9a02-4fb8-bc66-2197339f7ac5.png": "wasteland-tiles-v3.png",
    "exec-1c2056da-8d21-4d2b-a5d6-4bd3f33530d5.png": "forest-tiles-v2.png",
    "exec-67a57e49-1715-4dd8-ad53-5c82f45e00f8.png": "town-ruins-tiles-v2.png",
    "exec-1d73d98a-17c0-4466-8f97-ebcc1cd96c47.png": "mountain-tiles-v2.png",
}


def clear_connected_black(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    width, height = image.size
    queue = deque()
    seen = set()

    def add(x: int, y: int) -> None:
        if (x, y) in seen:
            return
        r, g, b, _ = pixels[x, y]
        if max(r, g, b) <= 12:
            seen.add((x, y))
            queue.append((x, y))

    for x in range(width):
        add(x, 0)
        add(x, height - 1)
    for y in range(height):
        add(0, y)
        add(width - 1, y)
    while queue:
        x, y = queue.popleft()
        pixels[x, y] = (*pixels[x, y][:3], 0)
        if x:
            add(x - 1, y)
        if x + 1 < width:
            add(x + 1, y)
        if y:
            add(x, y - 1)
        if y + 1 < height:
            add(x, y + 1)
    return image


OUTPUT.mkdir(parents=True, exist_ok=True)
for source_name, output_name in SHEETS.items():
    source = SOURCE / source_name
    output = OUTPUT / output_name
    clear_connected_black(Image.open(source)).save(output, optimize=True)
    print(output.relative_to(ROOT))
