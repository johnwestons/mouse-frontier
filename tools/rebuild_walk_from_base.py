"""Rebuild the shared walk/idle strips from each character's own base sprite.

This is intentionally conservative: it guarantees identity/equipment stays with
the character while adding a small, slow body bob. It also removes only the
neon-green chroma pixels, leaving real green clothing/scales intact.
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path('assets/sprites')
ANIM = ROOT / 'character-animations'
SOURCES = [ROOT/'MainCharacters', ROOT/'Mobs', ROOT/'NPCS']

def clean(im):
    a = np.array(im.convert('RGBA'))
    r, g, b, alpha = [a[:, :, i] for i in range(4)]
    neon = (alpha > 0) & (g > 190) & (r < 105) & (b < 105) & (g > r * 1.55) & (g > b * 1.55)
    a[neon, 3] = 0
    # Remove the remaining anti-aliased green key fringe only at the
    # silhouette edge; green scales/clothing in the interior are preserved.
    transparent = a[:, :, 3] == 0
    near = transparent.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            near |= np.roll(np.roll(transparent, dy, axis=0), dx, axis=1)
    r, g, b, alpha = [a[:, :, i] for i in range(4)]
    fringe = near & (alpha > 0) & (g > 28) & (g.astype(np.int16) > r.astype(np.int16) * 1.12) & (g.astype(np.int16) > b.astype(np.int16) * 1.12)
    a[fringe, 3] = 0
    return Image.fromarray(a, 'RGBA')

def shifted(base, dx, dy):
    out = Image.new('RGBA', base.size, (0, 0, 0, 0))
    out.alpha_composite(base, (dx, dy))
    return out

for folder in sorted(ANIM.iterdir()):
    if not folder.is_dir():
        continue
    source = next((d/(folder.name+'.png') for d in SOURCES if (d/(folder.name+'.png')).exists()), None)
    if source is None:
        continue
    base = clean(Image.open(source))
    if base.size != (512, 512):
        base = base.resize((512, 512), Image.Resampling.LANCZOS)
    # Gentle six-frame walk cycle; the body remains the same size and anchor.
    walk = Image.new('RGBA', (512*6, 512), (0, 0, 0, 0))
    for i, (dx, dy) in enumerate(((0, 0), (1, -2), (0, 0), (-1, 2), (0, 0), (1, -1))):
        walk.alpha_composite(shifted(base, dx, dy), (i*512, 0))
    walk.save(folder/'walk.png', optimize=True)
    idle = Image.new('RGBA', (1024, 512), (0, 0, 0, 0))
    idle.alpha_composite(base, (0, 0))
    idle.alpha_composite(shifted(base, 0, 1), (512, 0))
    idle.save(folder/'idle.png', optimize=True)
    print(folder.name)
