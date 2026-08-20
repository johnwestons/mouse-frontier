from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
GENERATED = Path(r"C:\Users\johnw\.codex\generated_images\019fecb0-a456-7410-a95b-1e8ee57838ee")

SHEETS = {
    "cowboy-mouse-no-skull": "exec-8cbc9815-173a-4b97-af06-b503fd1ad4c3.png",
    "cowboy-mouse-on-skull": "exec-d85d3316-3854-45d5-b44f-7eb58e815937.png",
    "crow-merchant": "exec-ffe87561-3431-4950-8137-83e57b6293de.png",
    "dog-red-scarf": "exec-30019be7-7181-45a8-bc96-d35e077b2eed.png",
    "dog-yellow-scarf": "exec-799ef36a-70e0-4d39-9d1b-e95727ef2716.png",
    "hedgehog-botanist": "exec-29bc3b14-cb9a-4acf-82a8-9455f5ac6171.png",
    "jackrabbit-courier": "exec-42999ce3-a4af-4811-8082-9bf7edae418a.png",
    "lizard-cook": "exec-d1bb4582-bf79-42a3-b482-e6cf2004fad5.png",
    "mole-prospector": "exec-a12ef37d-b3a0-4a62-86a0-0178f831d746.png",
    "mouse-engineer": "exec-e338a376-c82d-4370-97ef-8729964851b3.png",
    "musician-frog": "exec-871d0556-54db-4513-9d4a-a4222ffedfd2.png",
    "opossum-medic": "exec-e2e261fa-0d62-43ac-8426-6702847c752e.png",
    "otter-scout": "exec-a8dee07e-fb9a-4327-acfe-9d734c054170.png",
    "pipe-frog": "exec-910d0a9f-f597-4651-857d-6c1e004c9ff2.png",
    "prairie-dog-mechanic": "exec-f07cf69a-1ca5-40be-bc76-a3a371a47cc4.png",
    "raccoon-cape": "exec-adeef69e-8a61-44ce-b284-9ce3af4e6e3a.png",
    "raccoon-heart": "exec-4c4a1479-57c5-49fb-ab30-498fb8bc44ce.png",
    "raccoon-witch": "exec-79455c3a-f07d-4b4d-ba97-8939d1b9d5bf.png",
    "red-hood-mouse": "exec-55caa2d1-def6-41fd-ac4c-1a9285c0ca02.png",
    "skateboard-mouse": "exec-7420c875-3f71-454a-9e8e-9f3bbbea4884.png",
    "tortoise-conductor": "exec-9c3fe28e-3416-4b34-b827-ec68560867b1.png",
    "vampire-mouse": "exec-6e4a722f-6334-436e-9920-bf8d2217d268.png",
}

CELL = 160
MARGIN = 8


def remove_green(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pixels = []
    for r, g, b, a in image.getdata():
        # Generated sheets use a saturated green screen. Preserve green costume
        # details by requiring green to dominate both other channels strongly.
        if g > 150 and g > r * 1.65 and g > b * 1.65:
            pixels.append((r, g, b, 0))
        else:
            pixels.append((r, g, b, a))
    image.putdata(pixels)
    return image


def normalized_frame(frame: Image.Image) -> Image.Image:
    alpha = frame.getchannel("A")
    bbox = alpha.getbbox()
    if not bbox:
        raise ValueError("Generated frame became empty after chroma removal")
    sprite = frame.crop(bbox)
    max_size = CELL - MARGIN * 2
    scale = min(max_size / sprite.width, max_size / sprite.height)
    new_size = (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale)))
    sprite = sprite.resize(new_size, Image.Resampling.NEAREST)
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    x = (CELL - sprite.width) // 2
    y = CELL - MARGIN - sprite.height
    cell.alpha_composite(sprite, (x, y))
    return cell


for name, filename in SHEETS.items():
    source = GENERATED / filename
    image = remove_green(Image.open(source))
    midpoint = image.width // 2
    frames = [
        normalized_frame(image.crop((0, 0, midpoint, image.height))),
        normalized_frame(image.crop((midpoint, 0, image.width, image.height))),
    ]
    sheet = Image.new("RGBA", (CELL * 2, CELL), (0, 0, 0, 0))
    sheet.alpha_composite(frames[0], (0, 0))
    sheet.alpha_composite(frames[1], (CELL, 0))
    output_dir = ROOT / "assets" / "sprites" / "character-animations" / name
    output_dir.mkdir(parents=True, exist_ok=True)
    sheet.save(output_dir / "idle.png")
    # Keep the full generated source with the project for future animation edits.
    image.save(output_dir / "idle-generated-source.png")
    print(f"{name}: idle.png {sheet.size}")

# Shield Mouse deliberately preserves the original head and face pixel-for-pixel.
# Only the body below the neck settles two pixels for the breathing frame.
shield_source = Image.open(ROOT / "assets" / "sprites" / "NPCS" / "shield-mouse.png").convert("RGBA")
shield_frame = normalized_frame(shield_source)
shield_idle = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
neck_y = 69
body = shield_frame.crop((0, neck_y - 8, CELL, CELL))
shield_idle.alpha_composite(body, (0, neck_y - 6))
head = shield_frame.crop((0, 0, CELL, neck_y))
shield_idle.alpha_composite(head, (0, 0))
shield_sheet = Image.new("RGBA", (CELL * 2, CELL), (0, 0, 0, 0))
shield_sheet.alpha_composite(shield_frame, (0, 0))
shield_sheet.alpha_composite(shield_idle, (CELL, 0))
shield_dir = ROOT / "assets" / "sprites" / "character-animations" / "shield-mouse"
shield_dir.mkdir(parents=True, exist_ok=True)
shield_sheet.save(shield_dir / "idle.png")
shield_source.save(shield_dir / "idle-generated-source.png")
print(f"shield-mouse: original-art idle.png {shield_sheet.size}")
