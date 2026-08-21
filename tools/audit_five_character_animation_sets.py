from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
NAMES = ["ferret-scout", "gecko-herbalist", "mechanic-raccoon", "watch-raccoon", "medic-fox"]
ACTIONS = ["idle", "sit", "lay", "walk", "melee", "ranged", "use", "hit", "unconscious", "death"]

for name in NAMES:
    directory = ROOT / "assets" / "sprites" / "character-animations" / name
    missing = []
    bad = []
    sizes = set()
    for action in ACTIONS:
        path = directory / f"{action}.png"
        if not path.exists():
            missing.append(action)
            continue
        image = Image.open(path).convert("RGBA")
        sizes.add(image.size)
        alpha = image.getchannel("A")
        if image.width % 512 or image.height != 512 or not alpha.getbbox():
            bad.append(action)
    base = ROOT / "assets" / "sprites" / "MainCharacters" / f"{name}.png"
    npc = ROOT / "assets" / "sprites" / "NPCS" / f"{name}.png"
    print(f"{name}: base={base.exists()} npc={npc.exists()} missing={missing or 'none'} bad={bad or 'none'} sizes={sorted(sizes)}")
