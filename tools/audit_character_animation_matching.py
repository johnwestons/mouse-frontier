from pathlib import Path
from PIL import Image
import numpy as np

ROOT = Path('assets/sprites')
BASE = ROOT / 'MainCharacters'
ANIM = ROOT / 'character-animations'

def rgba(path):
    return Image.open(path).convert('RGBA')

def first_frame(path):
    im = rgba(path)
    # Current strips use 2 idle frames or 6 movement/action frames.
    if im.width >= im.height * 4:
        n = 6
    elif im.width >= im.height * 2:
        n = 2
    else:
        n = 1
    return im.crop((0, 0, im.width // n, im.height))

def feature(im):
    a = np.asarray(im)
    alpha = a[:, :, 3] > 12
    if not alpha.any():
        return np.zeros(48 * 48 * 4, dtype=np.float32)
    ys, xs = np.where(alpha)
    # Trim transparent padding while retaining a small silhouette margin.
    pad = 3
    x0, x1 = max(0, xs.min()-pad), min(im.width, xs.max()+pad+1)
    y0, y1 = max(0, ys.min()-pad), min(im.height, ys.max()+pad+1)
    crop = im.crop((x0, y0, x1, y1)).resize((48, 48), Image.Resampling.LANCZOS)
    q = np.asarray(crop).astype(np.float32) / 255.0
    # Green-screen remnants are deliberately excluded from matching.
    qalpha = q[:, :, 3:4]
    qrgb = q[:, :, :3] * qalpha
    mask = qalpha[:, :, 0]
    gray = (qrgb[:, :, 0] * .299 + qrgb[:, :, 1] * .587 + qrgb[:, :, 2] * .114)[:, :, None]
    return np.concatenate([qrgb.reshape(-1), gray.reshape(-1), mask.reshape(-1)])

base_features = {}
for p in sorted(BASE.glob('*.png')):
    base_features[p.stem] = feature(rgba(p))

for d in sorted(ANIM.iterdir()):
    if not d.is_dir():
        continue
    p = d / 'walk.png'
    if not p.exists():
        p = d / 'idle.png'
    if not p.exists():
        continue
    f = feature(first_frame(p))
    scores = []
    for name, b in base_features.items():
        # Blend appearance and silhouette; appearance catches gear swaps,
        # silhouette keeps pose differences from dominating.
        rgb = np.mean(np.abs(f[:48*48*3] - b[:48*48*3]))
        gray = np.mean(np.abs(f[48*48*3:48*48*4] - b[48*48*3:48*48*4]))
        mask = np.mean(np.abs(f[48*48*4:] - b[48*48*4:]))
        scores.append((0.55*rgb + 0.30*gray + 0.15*mask, name))
    scores.sort()
    print(f"{d.name:28} -> {scores[0][1]:28} {scores[0][0]:.4f} | {scores[1][1]:28} {scores[1][0]:.4f} | {scores[2][1]:28} {scores[2][0]:.4f}")
