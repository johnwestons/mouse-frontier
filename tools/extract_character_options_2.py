from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"C:\Users\johnw\.codex\generated_images\019ff205-5bd9-7b10-ac24-1303d9d44234")
OUT = ROOT / "assets" / "sprites" / "characters" / "new-options-2"
SHEETS = {
    "exec-cafd5723-e5e0-4418-805f-569dcf8fa36a.png": ["herbalist-hedgehog", "signal-hedgehog", "mechanic-hedgehog", "musician-hedgehog"],
    "exec-13a0a034-f377-49a8-b1e5-cc18ae331341.png": ["conductor-cat", "radio-cat", "homesteader-cat", "medic-cat"],
    "exec-6b3c70ce-0542-4ea5-b52a-066937222bff.png": ["scout-lizard", "courier-lizard", "prospector-lizard", "gardener-lizard"],
}


def remove_green(image):
    image = image.convert("RGBA")
    px = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, _ = px[x, y]
            if g > 150 and g > r * 1.25 and g > b * 1.25:
                px[x, y] = (r, g, b, 0)
    return image


OUT.mkdir(parents=True, exist_ok=True)
for filename, names in SHEETS.items():
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
