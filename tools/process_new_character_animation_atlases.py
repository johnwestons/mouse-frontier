from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"C:\Users\johnw\.codex\generated_images\019ff205-5bd9-7b10-ac24-1303d9d44234")
OUT = ROOT / "assets" / "sprites" / "character-animations" / "new-options"

NAMES = [
    "mail-mouse", "scavenger-mouse", "scholar-mouse", "cook-mouse",
    "trail-fox", "tinker-fox", "medic-fox", "guard-fox",
    "engineer-frog", "botanist-frog", "cook-frog", "scout-frog",
    "merchant-raccoon", "watch-raccoon", "river-raccoon", "mechanic-raccoon",
]
ACTION_FILES = [
    "exec-8879e019-c4f4-48ed-b06f-7534c081cb44.png", "exec-3b96aa1f-7d4c-49b8-8ef1-4948af174d37.png", "exec-25e8d4dd-3cb4-44f1-9342-d54e798a764c.png", "exec-269ff570-e393-40e2-a171-f41c08b9fb45.png",
    "exec-6e117de4-d885-4a05-9d18-465670cd4504.png", "exec-e8474a95-c650-4ba0-8d5c-966011cec06d.png", "exec-9ecdcdb6-e9f5-441a-9ff2-e6602faa7a12.png", "exec-ac61d2f8-8e42-4af7-aa8e-cef9120bb841.png",
    "exec-1a866409-b1e3-4510-b398-84832cc86b32.png", "exec-57bff562-d18c-46a3-92c9-bb0274e4b6c9.png", "exec-f0581b26-6daf-4c73-a169-7c670e42edc7.png", "exec-23982876-b8ff-40bc-a652-43a1f80cf81c.png",
    "exec-07589fc4-25c3-40f2-861b-eea81a8e4211.png", "exec-88441169-17d2-4697-bc4f-138acb794d09.png", "exec-60204c3c-aef1-4647-a1ac-f7a1db3c52fe.png", "exec-6ecd2ea7-9e10-46b8-be62-132cd1b9b559.png",
]
MOVEMENT_FILES = [
    "exec-42b8793a-d4b0-4d0d-95e6-5bfcbd3b688f.png", "exec-19712bbe-3b77-4136-8eef-2f6096d10603.png", "exec-c4b02e7d-a0c0-4c44-a4ff-0fb0522eded2.png", "exec-00e2fc83-9d0c-4efd-981b-6c9c6d99b2a7.png",
    "exec-e50b73d2-8409-47b5-8790-ce9876f21558.png", "exec-57efaec5-41a2-452a-80a8-16968699561c.png", "exec-d3386912-1a74-408c-bc29-02c70f7db62f.png", "exec-937d9da5-035b-4347-a491-68cae8da1020.png",
    "exec-5a9ce241-758f-4102-9e1b-499aa3025247.png", "exec-af8fd435-520f-4d22-867d-28c22b0f5c75.png", "exec-88b63fb0-e5be-4084-b8c5-52a84c0ff92c.png", "exec-295b6517-4090-4a17-bf87-f32cc4c30140.png",
    "exec-a4677b44-8ab5-4968-91e6-1e1e2482086c.png", "exec-51573bac-d26b-417f-bf09-bdcf0fa76b31.png", "exec-a3f1b84d-2051-4469-896f-623e32737cd1.png", "exec-03985094-4f83-4d5f-96a2-e97599c6ad06.png",
]


def key_green(image: Image.Image) -> Image.Image:
    from chroma import remove_green_background
    return remove_green_background(image)


def panel(image: Image.Image, col: int, row: int) -> Image.Image:
    from chroma import extract_panel
    cell_w, cell_h = image.width // 2, image.height // 4
    cell = image.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h)).convert("RGBA")
    # Clear only the atlas divider. It is not character artwork.
    px = cell.load()
    for y in range(cell.height):
        for x in range(cell.width):
            if x < 8 or y < 8 or x >= cell.width - 8 or y >= cell.height - 8:
                px[x, y] = (0, 0, 0, 0)
    cell = extract_panel(cell)
    bbox = cell.getchannel("A").getbbox()
    if bbox:
        cell = cell.crop(bbox)
    # Match the established Hedgehog Botanist footprint: roughly 413 visible
    # pixels on a 512px animation frame, centered with a safe foot baseline.
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
    save_strip([panel(movement, i % 2, i // 2) for i in (0, 1, 2, 3, 1, 0)], destination / "walk.png")
    save_strip([panel(movement, i % 2, i // 2) for i in (4, 5)], destination / "unconscious.png")
    print(destination.relative_to(ROOT))
