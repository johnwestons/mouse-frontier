from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"C:\Users\johnw\.codex\generated_images\019ff205-5bd9-7b10-ac24-1303d9d44234")
OUT = ROOT / "assets" / "sprites" / "character-animations" / "new-options-3"
MAIN = ROOT / "assets" / "sprites" / "MainCharacters"

NAMES = [
    "gecko-ranger", "gecko-herbalist", "gecko-mechanic", "gecko-courier",
    "ferret-trapper", "ferret-medic", "ferret-engineer", "ferret-scout",
]

ACTION_FILES = [
    "exec-3f0b5cbd-917b-409b-8bb6-cc92371f7ba1.png", "exec-b31cce07-8c0d-408e-803b-72abd57137ea.png",
    "exec-6fc2ca94-3529-40d3-8d3b-d498315db656.png", "exec-9b34a92e-5789-4f44-82f2-64c3028163bb.png",
    "exec-9f256891-9124-435f-9fd4-b938c73408de.png", "exec-8c93e781-bbef-46be-9646-39659903a386.png",
    "exec-e2872efe-8b68-49e0-9fe4-198e84de80fa.png", "exec-887898ee-5d77-44b8-ba25-581181d5c195.png",
]

MOVEMENT_FILES = [
    "exec-b3d6ac18-bb39-4521-a7e2-14247070ae21.png", "exec-fa7c9b6e-f43d-4c3e-9c7a-e36a05e6335b.png",
    "exec-30d19b89-d456-4dcb-ba36-de7e36669a12.png", "exec-deb72ebe-af1a-4053-9e53-746dc51c10d4.png",
    "exec-ec725a54-6bdb-4fb3-8f1f-bcc5a3f60dc5.png", "exec-0027ecfa-7ef5-4301-8a9e-4439425ab42a.png",
    "exec-253c50ca-5d8c-48ac-ad0d-5427db9feeea.png", "exec-597a9db5-1916-43c6-aabd-ea25ddc37285.png",
]


def key_green(image: Image.Image) -> Image.Image:
    from chroma import remove_green_background
    return remove_green_background(image)


def panel(image: Image.Image, col: int, row: int) -> Image.Image:
    from chroma import extract_panel
    cell_w, cell_h = image.width // 2, image.height // 4
    cell = image.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h)).convert("RGBA")
    # Generated atlas dividers sit on the outer edge of each cell. Remove only
    # those edge pixels so white eyes/highlights inside the character remain.
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


for name, action_file, movement_file in zip(NAMES, ACTION_FILES, MOVEMENT_FILES):
    destination = OUT / name
    destination.mkdir(parents=True, exist_ok=True)
    action = key_green(Image.open(SOURCE / action_file))
    panels = [panel(action, index % 2, index // 2) for index in range(8)]
    panels[0].save(MAIN / f"{name}.png", optimize=True)
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
