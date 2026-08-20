from collections import deque
from pathlib import Path
import shutil
import tempfile

import numpy as np
from PIL import Image

ROOT = Path('assets/sprites/character-animations')

# These groups were generated together. Their atlases were assigned to folders
# out of order, so the complete animation sets need to follow the matching base
# character rather than only replacing the walk strip.
CYCLES = [
    (['botanist-frog', 'cook-frog', 'engineer-frog'], -1),
    (['medic-fox', 'tinker-fox', 'trail-fox'], 1),
    (['river-raccoon', 'watch-raccoon'], 1),
]

def swap_cycle(names, direction):
    with tempfile.TemporaryDirectory(prefix='anim-swap-', dir=str(ROOT.parent)) as tmp:
        tmp = Path(tmp)
        saved = {}
        for name in names:
            src = ROOT / name
            dst = tmp / name
            shutil.copytree(src, dst)
            saved[name] = dst
        # The observed order is one position ahead for the three-way cycles;
        # the two-way pair is simply exchanged.
        for i, name in enumerate(names):
            source = saved[names[(i + direction) % len(names)]]
            for p in (ROOT / name).glob('*.png'):
                p.unlink()
            for p in source.glob('*.png'):
                shutil.copy2(p, ROOT / name / p.name)

def _bg_mask(a):
    r, g, b, alpha = [a[:, :, i] for i in range(4)]
    opaque = alpha > 0
    green = (g.astype(np.int16) >= r.astype(np.int16) * 1.05) & (g.astype(np.int16) >= b.astype(np.int16) * 1.05) & ((g.astype(np.int16) - np.minimum(r, b)) >= 2)
    near_white = (r > 215) & (g > 215) & (b > 215)
    dark = (r < 38) & (g < 48) & (b < 38)
    return opaque & (green | near_white | dark)

def clean_frame(im):
    a = np.array(im.convert('RGBA'))
    h, w = a.shape[:2]
    bg = _bg_mask(a)
    seen = np.zeros((h, w), dtype=bool)
    q = deque()
    for x in range(w):
        if bg[0, x]: q.append((0, x)); seen[0, x] = True
        if bg[h-1, x] and not seen[h-1, x]: q.append((h-1, x)); seen[h-1, x] = True
    for y in range(h):
        if bg[y, 0] and not seen[y, 0]: q.append((y, 0)); seen[y, 0] = True
        if bg[y, w-1] and not seen[y, w-1]: q.append((y, w-1)); seen[y, w-1] = True
    while q:
        y, x = q.popleft()
        for ny, nx in ((y-1,x),(y+1,x),(y,x-1),(y,x+1)):
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx] and bg[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    a[seen, 3] = 0

    # Remove anti-aliased green key spill only where it borders transparency;
    # green clothing inside a silhouette is left intact.
    r, g, b, alpha = [a[:, :, i] for i in range(4)]
    transparent = alpha == 0
    near_transparent = transparent.copy()
    for dy in (-2, -1, 0, 1, 2):
        for dx in (-2, -1, 0, 1, 2):
            if dx == 0 and dy == 0: continue
            near_transparent |= np.roll(np.roll(transparent, dy, axis=0), dx, axis=1)
    spill = (g.astype(np.int16) > r.astype(np.int16) * 1.12) & (g.astype(np.int16) > b.astype(np.int16) * 1.12) & near_transparent
    a[spill, 3] = 0
    return Image.fromarray(a, 'RGBA')

def clean_strip(path):
    im = Image.open(path).convert('RGBA')
    if im.width >= im.height and im.width % im.height == 0:
        count = im.width // im.height
    else:
        count = 1
    fw = im.width // count
    out = Image.new('RGBA', im.size, (0, 0, 0, 0))
    for i in range(count):
        out.alpha_composite(clean_frame(im.crop((i*fw, 0, (i+1)*fw, im.height))), (i*fw, 0))
    out.save(path, optimize=True)

for names, direction in CYCLES:
    swap_cycle(names, direction)

for folder in ROOT.iterdir():
    if folder.is_dir():
        for png in folder.glob('*.png'):
            clean_strip(png)

print('fixed animation set mismatches:', ', '.join('/'.join(c[0]) for c in CYCLES))
print('cleaned all animation PNG strips')
