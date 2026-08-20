"""Install the authored walk/idle frames with the verified character mapping."""
from pathlib import Path
import shutil
import numpy as np
from PIL import Image

ROOT = Path('assets/sprites/character-animations')
STAGING = [ROOT/'new-options', ROOT/'new-options-2', ROOT/'new-options-3']

movement_override = {
    'botanist-frog': 'engineer-frog',
    'cook-frog': 'botanist-frog',
    'engineer-frog': 'cook-frog',
    'medic-fox': 'tinker-fox',
    'tinker-fox': 'trail-fox',
    'trail-fox': 'medic-fox',
    'river-raccoon': 'watch-raccoon',
    'watch-raccoon': 'river-raccoon',
}

# The action/idle batch was ordered correctly for frogs and foxes, but the
# river/watch raccoon pair was reversed in both generated batches.
idle_override = {
    'river-raccoon': 'watch-raccoon',
    'watch-raccoon': 'river-raccoon',
}

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
    neon = (alpha > 0) & (g > 205) & (r < 80) & (b < 80)
    a[neon, 3] = 0
    alpha = a[:, :, 3]
    spill = near & (alpha > 0) & (g > 28) & (g.astype(np.int16) > r.astype(np.int16)*1.12) & (g.astype(np.int16) > b.astype(np.int16)*1.12)
    a[spill, 3] = 0
    opaque = a[:, :, 3] > 0
    white = opaque & (a[:, :, 0] > 220) & (a[:, :, 1] > 220) & (a[:, :, 2] > 220)
    green = opaque & (a[:, :, 1].astype(np.int16) > a[:, :, 0].astype(np.int16)*1.35) & (a[:, :, 1].astype(np.int16) > a[:, :, 2].astype(np.int16)*1.35)
    for y in np.where(white.sum(axis=1) > im.width*.78)[0]: a[y, :, 3] = 0
    for x in np.where(white.sum(axis=0) > im.height*.78)[0]: a[:, x, 3] = 0
    for y in np.where(green.sum(axis=1) > im.width*.78)[0]: a[y, :, 3] = 0
    for x in np.where(green.sum(axis=0) > im.height*.78)[0]: a[:, x, 3] = 0
    return Image.fromarray(a, 'RGBA')

def clean_strip(path):
    im = Image.open(path).convert('RGBA')
    count = im.width // im.height if im.width >= im.height and im.width % im.height == 0 else 1
    fw = im.width // count
    out = Image.new('RGBA', im.size, (0, 0, 0, 0))
    for i in range(count):
        out.alpha_composite(clean_frame(im.crop((i*fw, 0, (i+1)*fw, im.height))), (i*fw, 0))
    out.save(path, optimize=True)

installed = 0
for staging in STAGING:
    if not staging.exists():
        continue
    for destination_source in sorted(staging.iterdir()):
        if not destination_source.is_dir():
            continue
        name = destination_source.name
        destination = ROOT/name
        movement_source = staging/movement_override.get(name, name)
        idle_source = staging/idle_override.get(name, name)
        for filename in ('walk.png', 'unconscious.png'):
            shutil.copy2(movement_source/filename, destination/filename)
        for filename in ('idle.png', 'idle-variant.png', 'sit.png', 'lay.png', 'melee.png', 'ranged.png', 'use.png', 'hit.png'):
            source = idle_source/filename
            if source.exists():
                shutil.copy2(source, destination/filename)
        installed += 1

print(f'restored authored animation sequences for {installed} generated characters')
