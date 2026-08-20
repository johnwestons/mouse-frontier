from pathlib import Path
import shutil
import tempfile

ROOT = Path('assets/sprites/character-animations')
CYCLES = [
    (['botanist-frog', 'cook-frog', 'engineer-frog'], -1),
    (['medic-fox', 'tinker-fox', 'trail-fox'], 1),
    (['river-raccoon', 'watch-raccoon'], 1),
]

for names, direction in CYCLES:
    with tempfile.TemporaryDirectory(prefix='anim-remap-', dir=str(ROOT.parent)) as tmp_name:
        tmp = Path(tmp_name)
        saved = {}
        for name in names:
            saved[name] = tmp / name
            shutil.copytree(ROOT / name, saved[name])
        for i, name in enumerate(names):
            destination = ROOT / name
            for p in destination.glob('*.png'):
                p.unlink()
            source = saved[names[(i + direction) % len(names)]]
            for p in source.glob('*.png'):
                shutil.copy2(p, destination / p.name)
print('remapped:', ', '.join('/'.join(c[0]) for c in CYCLES))
