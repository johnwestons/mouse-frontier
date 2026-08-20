from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"C:\Users\johnw\.codex\generated_images\019ff205-5bd9-7b10-ac24-1303d9d44234")
ANIM = ROOT / "assets" / "sprites" / "character-animations"

MOVEMENT_FILES = {
    "cowboy-mouse-no-skull": "exec-4e8c428e-9066-4c95-9b18-bc3c7593a479.png",
    "cowboy-mouse-on-skull": "exec-679cedaa-5dff-4049-a747-e683e801545c.png",
    "crow-merchant": "exec-1ed56275-6238-43b6-abc6-74d2ac888b71.png",
    "hedgehog-botanist": "exec-3bae66b8-a596-4663-86a0-4940bcfd44a3.png",
    "jackrabbit-courier": "exec-7d6de8e7-2ef0-4c32-b31c-8a283dea02f8.png",
    "lizard-cook": "exec-453512c4-50a1-44a5-8c70-975db14c159e.png",
    "mole-prospector": "exec-5ca90b0e-cfeb-40fa-8630-b4ebe753f3a7.png",
    "mouse-engineer": "exec-7164bc6a-3f1f-4a02-9209-ef66918648d9.png",
    "opossum-medic": "exec-54a56dfe-0aab-4ce7-9c57-5442540e00a4.png",
    "otter-scout": "exec-368d3ef0-d4e2-46ac-a0f8-bd9801e8aa2b.png",
    "prairie-dog-mechanic": "exec-62f84963-8c81-4310-b722-de47377095b5.png",
    "raccoon-cape": "exec-08d7c00a-fa84-46b1-aed7-730831d6b1e6.png",
    "raccoon-heart": "exec-4e2a2139-0309-4b88-bdef-44836bd04065.png",
    "red-hood-mouse": "exec-1061d41c-5e3a-4c61-8c0e-a367ac3edf86.png",
    "shield-mouse": "exec-46f00bca-94ea-4f83-9a4e-f124ca4b3686.png",
    "tortoise-conductor": "exec-870b1c48-03a7-4500-b82b-088a7a9e4ce9.png",
    "vampire-mouse": "exec-854099c3-b347-4578-a352-9ee6d4b91a2b.png",
    "raccoon-witch": "exec-29d6a8d9-ada7-4405-bd13-39af91367f5e.png",
}
ACTION_FILE = "exec-6b4b0736-ed47-415f-8493-93ebe0753c93.png"


def key_green(image: Image.Image) -> Image.Image:
    from chroma import remove_green_background
    return remove_green_background(image)


def panel(image: Image.Image, col: int, row: int) -> Image.Image:
    from chroma import extract_panel
    cell_w, cell_h = image.width // 2, image.height // 4
    cell = image.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h)).convert("RGBA")
    edge = 8
    pixels = cell.load()
    for y in range(cell.height):
        for x in range(cell.width):
            if x < edge or y < edge or x >= cell.width - edge or y >= cell.height - edge:
                pixels[x, y] = (0, 0, 0, 0)
    cell = extract_panel(cell)
    bbox = cell.getchannel("A").getbbox()
    if bbox:
        cell = cell.crop(bbox)
    scale = min(413 / cell.width, 413 / cell.height)
    cell = cell.resize((round(cell.width * scale), round(cell.height * scale)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    canvas.alpha_composite(cell, ((512 - cell.width) // 2, 458 - cell.height))
    return canvas


def save_strip(frames, destination):
    strip = Image.new("RGBA", (512 * len(frames), 512), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * 512, 0))
    strip.save(destination, optimize=True)


for name, filename in MOVEMENT_FILES.items():
    destination = ANIM / name
    destination.mkdir(parents=True, exist_ok=True)
    movement = key_green(Image.open(SOURCE / filename))
    movement_panels = [panel(movement, i % 2, i // 2) for i in range(8)]
    save_strip([movement_panels[i] for i in (0, 1, 2, 3, 1, 0)], destination / "walk.png")
    save_strip([movement_panels[4], movement_panels[5]], destination / "unconscious.png")

    if name == "raccoon-witch":
        action = key_green(Image.open(SOURCE / ACTION_FILE))
        panels = [panel(action, i % 2, i // 2) for i in range(8)]
        save_strip(panels[0:2], destination / "idle.png")
        panels[1].save(destination / "idle-variant.png", optimize=True)
        save_strip([panels[2], panels[2]], destination / "sit.png")
        save_strip([panels[3], panels[3]], destination / "lay.png")
        for action_name, panel_index in (("melee", 4), ("ranged", 5), ("use", 6), ("hit", 7)):
            save_strip([panels[panel_index]] * 3, destination / f"{action_name}.png")
    print(name)
