from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"C:\Users\johnw\.codex\generated_images\019ff205-5bd9-7b10-ac24-1303d9d44234")
OUT = ROOT / "assets" / "sprites" / "character-animations" / "new-options-2"

NAMES = [
    "herbalist-hedgehog", "signal-hedgehog", "mechanic-hedgehog", "musician-hedgehog",
    "conductor-cat", "radio-cat", "homesteader-cat", "medic-cat",
    "scout-lizard", "courier-lizard", "prospector-lizard", "gardener-lizard",
]

# Generated in the same order as NAMES by the action-atlas batch.
ACTION_FILES = [
    "exec-a815d67e-fd06-49e3-8d07-81c40fe231c5.png", "exec-948b60d5-d1bc-48e4-b1f5-d6f9320dd4e5.png",
    "exec-e1b73514-ca0a-4331-9536-561b7b3f0782.png", "exec-93ca4750-ba9d-4eee-b33a-2a796222fef1.png",
    "exec-cd388530-8fff-4836-90f6-2a59beb6761b.png", "exec-6ca5e832-275d-4702-90d4-cace67122656.png",
    "exec-b9b61a4e-922e-428f-9fa4-4a2d0e71a8d1.png", "exec-20bb5b2a-8b77-4dcf-acbe-6b7e1ab28c67.png",
    "exec-98d7db39-42e8-4e26-b7c8-930b5865bb2f.png", "exec-d6bfe5ff-4694-4d12-866e-3f91189b8b76.png",
    "exec-d88bde59-ca0d-44e9-a582-64a97dc43e5c.png", "exec-46948277-fb6c-49c2-8f9d-30e7d82fa9ab.png",
]

# Generated in the same order as NAMES by the movement/unconscious batch.
MOVEMENT_FILES = [
    "exec-8ddd622c-727c-49fd-ac4a-4d7df68426b5.png", "exec-de45a461-3b3b-4b7e-8115-98b8f57681a6.png",
    "exec-f9b9c76a-9a7e-409c-a4a6-7758bb4fd46a.png", "exec-6ff30e03-193a-44e5-9c06-c61324e43f97.png",
    "exec-d10ff554-ac37-4db5-8a01-427ac6dbfc15.png", "exec-ee0b5efd-430f-45e9-98bd-254d16110254.png",
    "exec-ab2a8c3a-eefe-4dae-8c3f-a61f2a39104d.png", "exec-19156240-a6d1-478c-83b5-99afa5401de1.png",
    "exec-e283aa35-6a1a-44cf-821d-5879d4071439.png", "exec-eb0647a0-26c1-4f97-9e8c-3be2377e4fa7.png",
    "exec-a1fc95bd-09d6-4ff9-9b74-7f9542326114.png", "exec-2b00e747-a56b-4064-b609-0bfe55124a06.png",
]


def key_green(image: Image.Image) -> Image.Image:
    from chroma import remove_green_background
    return remove_green_background(image)


def panel(image: Image.Image, col: int, row: int) -> Image.Image:
    from chroma import extract_panel
    cell_w, cell_h = image.width // 2, image.height // 4
    cell = image.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h)).convert("RGBA")
    px = cell.load()
    for y in range(cell.height):
        for x in range(cell.width):
            if x < 8 or y < 8 or x >= cell.width - 8 or y >= cell.height - 8:
                px[x, y] = (0, 0, 0, 0)
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


for name, action_file, movement_file in zip(NAMES, ACTION_FILES, MOVEMENT_FILES):
    destination = OUT / name
    destination.mkdir(parents=True, exist_ok=True)
    action = key_green(Image.open(SOURCE / action_file))
    panels = [panel(action, index % 2, index // 2) for index in range(8)]
    save_strip(panels[0:2], destination / "idle.png")
    panels[1].save(destination / "idle-variant.png", optimize=True)
    save_strip([panels[2], panels[2]], destination / "sit.png")
    save_strip([panels[3], panels[3]], destination / "lay.png")
    for action_name, panel_index in (("melee", 4), ("ranged", 5), ("use", 6), ("hit", 7)):
        save_strip([panels[panel_index]] * 3, destination / f"{action_name}.png")
    movement = key_green(Image.open(SOURCE / movement_file))
    movement_panels = [panel(movement, i % 2, i // 2) for i in range(8)]
    save_strip([movement_panels[i] for i in (0, 1, 2, 3, 1, 0)], destination / "walk.png")
    save_strip([movement_panels[4], movement_panels[5]], destination / "unconscious.png")
    print(destination.relative_to(ROOT))
