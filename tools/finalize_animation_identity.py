from pathlib import Path
import shutil
import tempfile
import numpy as np
from PIL import Image

ROOT = Path('assets/sprites/character-animations')

def swap_files(names, direction, files):
    with tempfile.TemporaryDirectory(prefix='anim-action-', dir=str(ROOT.parent)) as tmp_name:
        tmp = Path(tmp_name); saved = {}
        for name in names:
            saved[name] = tmp / name
            shutil.copytree(ROOT / name, saved[name])
        for i, name in enumerate(names):
            src = saved[names[(i + direction) % len(names)]]
            for filename in files:
                p = src / filename
                if p.exists(): shutil.copy2(p, ROOT / name / filename)

# The authored action atlases used a different response ordering than the
# movement atlases. Correct the action-only files independently.
swap_files(['botanist-frog', 'cook-frog', 'engineer-frog'], 1,
           ['sit.png','lay.png','melee.png','ranged.png','use.png','hit.png','unconscious.png'])
swap_files(['medic-fox', 'tinker-fox', 'trail-fox'], -1,
           ['sit.png','lay.png','melee.png','ranged.png','use.png','hit.png','unconscious.png'])

def clean_frame(im):
    a = np.array(im.convert('RGBA'))
    alpha = a[:, :, 3]
    transparent = alpha == 0
    near = transparent.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx or dy:
                near |= np.roll(np.roll(transparent, dy, axis=0), dx, axis=1)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    spill = near & (alpha > 0) & (g > 28) & (g.astype(np.int16) > r.astype(np.int16)*1.12) & (g.astype(np.int16) > b.astype(np.int16)*1.12)
    a[spill, 3] = 0
    # Remove full-width/height atlas divider strokes, never interior details.
    opaque = a[:, :, 3] > 0
    white = opaque & (a[:, :, 0] > 220) & (a[:, :, 1] > 220) & (a[:, :, 2] > 220)
    green = opaque & (a[:, :, 1].astype(np.int16) > a[:, :, 0].astype(np.int16)*1.35) & (a[:, :, 1].astype(np.int16) > a[:, :, 2].astype(np.int16)*1.35)
    for y in np.where(white.sum(axis=1) > im.width * .78)[0]: a[y, :, 3] = 0
    for x in np.where(white.sum(axis=0) > im.height * .78)[0]: a[:, x, 3] = 0
    for y in np.where(green.sum(axis=1) > im.width * .78)[0]: a[y, :, 3] = 0
    for x in np.where(green.sum(axis=0) > im.height * .78)[0]: a[:, x, 3] = 0
    return Image.fromarray(a, 'RGBA')

for folder in ROOT.iterdir():
    if not folder.is_dir(): continue
    for path in folder.glob('*.png'):
        if path.name in ('walk.png', 'idle.png'): continue
        im = Image.open(path).convert('RGBA')
        count = im.width // im.height if im.width >= im.height and im.width % im.height == 0 else 1
        fw = im.width // count
        out = Image.new('RGBA', im.size, (0,0,0,0))
        for i in range(count):
            out.alpha_composite(clean_frame(im.crop((i*fw, 0, (i+1)*fw, im.height))), (i*fw, 0))
        out.save(path, optimize=True)
print('corrected action identity and cleaned animation edges')
