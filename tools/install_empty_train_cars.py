from pathlib import Path
import shutil

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
GENERATED = Path(r"C:\Users\johnw\.codex\generated_images\019fecb0-a456-7410-a95b-1e8ee57838ee")
OUTPUT = ROOT / "assets" / "sprites" / "train" / "cars"
SOURCES = {
    "coal-hauler": "exec-11597840-649b-4fd0-bf1e-910ab5fa7854.png",
    "greenhouse": "exec-3517a141-dd00-46a8-94ae-746716da67cd.png",
    "sleeper": "exec-6eb2081b-f7d9-4275-be1b-650c06015f7c.png",
    "storage": "exec-78369bc7-884a-46aa-844b-3f0f2995d975.png",
    "medical": "exec-25f38338-c4a8-4f42-a925-678005204d8d.png",
    "navigator": "exec-7c103711-b880-48f1-b73e-4a487d2eef5f.png",
}


def remove_magenta(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, _ = pixels[x, y]
            if r > 195 and b > 180 and g < 80:
                pixels[x, y] = (r, g, b, 0)
            else:
                if r > g * 2.1 and b > g * 1.9:
                    r = b = max(g, 10)
                pixels[x, y] = (r, g, b, 255)
    return image


for car_id, source_name in SOURCES.items():
    destination = OUTPUT / f"{car_id}.png"
    backup = OUTPUT / f"{car_id}-furnished-v1.png"
    if destination.exists() and not backup.exists():
        shutil.copy2(destination, backup)

    image = remove_magenta(Image.open(GENERATED / source_name))
    bounds = image.getchannel("A").getbbox()
    subject = image.crop(bounds)
    scale = min(620 / subject.width, 344 / subject.height)
    subject = subject.resize((round(subject.width * scale), round(subject.height * scale)), Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (640, 360), (0, 0, 0, 0))
    canvas.alpha_composite(subject, ((640 - subject.width) // 2, 356 - subject.height))
    canvas.save(destination, optimize=True)
    print(destination.relative_to(ROOT), subject.size)
