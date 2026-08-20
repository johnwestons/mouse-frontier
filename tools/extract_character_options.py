from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"C:\Users\johnw\.codex\generated_images\019ff205-5bd9-7b10-ac24-1303d9d44234")
OUT = ROOT / "assets" / "sprites" / "characters" / "new-options"
SHEETS = {
    "exec-452743c1-5e0a-4fb6-a387-a3ac984e14a3.png": ("mouse", ["mail-mouse", "scavenger-mouse", "scholar-mouse", "cook-mouse"]),
    "exec-90c7e06f-fd0e-4803-8f44-8f3fb5241f11.png": ("fox", ["trail-fox", "tinker-fox", "medic-fox", "guard-fox"]),
    "exec-e626dd4a-bbff-4096-9e14-e5b1dd793efb.png": ("frog", ["engineer-frog", "botanist-frog", "cook-frog", "scout-frog"]),
    "exec-03245ed7-974a-4b55-b787-3dbaab5e9d3a.png": ("raccoon", ["merchant-raccoon", "watch-raccoon", "river-raccoon", "mechanic-raccoon"]),
}


def remove_green(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if g > 150 and g > r * 1.25 and g > b * 1.25:
                pixels[x, y] = (r, g, b, 0)
    return image


OUT.mkdir(parents=True, exist_ok=True)
for filename, (species, names) in SHEETS.items():
    sheet = remove_green(Image.open(SOURCE / filename))
    cell_w, cell_h = sheet.width // 2, sheet.height // 2
    for index, name in enumerate(names):
        col, row = index % 2, index // 2
        cell = sheet.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h))
        bbox = cell.getchannel("A").getbbox()
        if not bbox:
            continue
        subject = cell.crop(bbox)
        scale = min(512 / subject.width, 512 / subject.height)
        subject = subject.resize((round(subject.width * scale), round(subject.height * scale)), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
        canvas.alpha_composite(subject, ((512 - subject.width) // 2, 512 - subject.height - 12))
        path = OUT / f"{name}.png"
        canvas.save(path, optimize=True)
        print(path.relative_to(ROOT))
