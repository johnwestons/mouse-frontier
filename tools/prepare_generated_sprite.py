"""Turn ImageGen's green-screen pixel art into a compact transparent PNG."""
from pathlib import Path
import sys
from PIL import Image


def prepare(source: Path, destination: Path) -> None:
    image = Image.open(source).convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, _ = pixels[x, y]
            green = g > 105 and g > r * 1.28 and g > b * 1.28
            pixels[x, y] = (r, g, b, 0 if green else 255)
    box = image.getbbox()
    if not box:
        raise ValueError(f"No sprite remained after removing green: {source}")
    image = image.crop(box)
    scale = min(1.0, 128 / max(image.size))
    image = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.Resampling.NEAREST)
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: prepare_generated_sprite.py SOURCE DESTINATION")
    prepare(Path(sys.argv[1]), Path(sys.argv[2]))
