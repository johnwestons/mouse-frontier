"""Conservative chroma extraction for generated sprite-atlas cells.

Only green connected to the outside of a cell is made transparent. Remaining
green spill at the silhouette edge is darkened, never deleted, so green/teal
characters keep all of their body pixels.
"""
from collections import deque

import numpy as np
from PIL import Image


def _border_background(rgb):
    band_size = min(64, rgb.shape[0]//3, rgb.shape[1]//3)
    border = np.concatenate((rgb[:band_size].reshape(-1,3), rgb[-band_size:].reshape(-1,3),
                             rgb[:, :band_size].reshape(-1,3), rgb[:, -band_size:].reshape(-1,3)), axis=0)
    r, g, b = border[:, 0], border[:, 1], border[:, 2]
    green = border[(g > 150) & ((g - r) > 80) & ((g - b) > 80)]
    if len(green):
        score = green[:,1] - np.maximum(green[:,0], green[:,2])
        green = green[score >= np.percentile(score, 80)]
        return np.median(green, axis=0).astype(np.int32)
    return np.array((0, 255, 0), dtype=np.int32)


def _flood_from_edge(candidate, margin=64):
    h, w = candidate.shape
    seen = np.zeros((h, w), dtype=bool)
    q = deque()
    margin = min(margin, h//2, w//2)
    edge_band = np.zeros_like(candidate)
    edge_band[:margin, :] = True; edge_band[-margin:, :] = True
    edge_band[:, :margin] = True; edge_band[:, -margin:] = True
    for y, x in np.argwhere(candidate & edge_band):
        if not seen[y, x]: q.append((int(y), int(x))); seen[y, x] = True
    while q:
        y, x = q.popleft()
        for ny, nx in ((y-1,x), (y+1,x), (y,x-1), (y,x+1)):
            if 0 <= ny < h and 0 <= nx < w and candidate[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


def _remove_far_fragments(a):
    """Remove panel-overlap fragments while retaining nearby held particles."""
    mask = a[:, :, 3] > 0
    h, w = mask.shape
    seen = np.zeros_like(mask)
    components = []
    for y in range(h):
        for x in range(w):
            if not mask[y, x] or seen[y, x]:
                continue
            q = deque([(y, x)]); seen[y, x] = True; pixels = []
            minx = maxx = x; miny = maxy = y
            while q:
                cy, cx = q.popleft(); pixels.append((cy, cx))
                minx=min(minx,cx); maxx=max(maxx,cx); miny=min(miny,cy); maxy=max(maxy,cy)
                for ny, nx in ((cy-1,cx),(cy+1,cx),(cy,cx-1),(cy,cx+1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny,nx] and not seen[ny,nx]:
                        seen[ny,nx]=True; q.append((ny,nx))
            components.append((len(pixels), (minx,miny,maxx,maxy), pixels))
    if not components:
        return a
    components.sort(reverse=True, key=lambda c: c[0])
    main_area, main_box, _ = components[0]
    mx0,my0,mx1,my1 = main_box
    for area, (x0,y0,x1,y1), pixels in components[1:]:
        dx = max(mx0-x1-1, x0-mx1-1, 0)
        dy = max(my0-y1-1, y0-my1-1, 0)
        close = max(dx, dy) <= 42
        substantial = area >= max(80, int(main_area * .035))
        if not close and not substantial:
            for py, px in pixels:
                a[py, px, 3] = 0
    return a


def extract_panel(image: Image.Image) -> Image.Image:
    image = image.convert('RGBA')
    a = np.array(image)
    rgb = a[:, :, :3].astype(np.int32)
    bg = _border_background(rgb)
    dist = np.sqrt(np.sum((rgb - bg) ** 2, axis=2))
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    candidate = (g > 90) & (g > r * 1.12) & (g > b * 1.12) & (dist < 100)
    outside = _flood_from_edge(candidate)
    a[outside, 3] = 0

    # Enclosed gaps are not outside-connected. Remove only the unmistakable
    # neon key; muted greens, teal skin, foliage, and clothing are excluded.
    exact_key = (a[:, :, 3] > 0) & (g > 205) & (r < 80) & (b < 80)
    a[exact_key, 3] = 0

    transparent = a[:, :, 3] == 0
    near = transparent.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx or dy:
                near |= np.roll(np.roll(transparent, dy, axis=0), dx, axis=1)
    r8, g8, b8 = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    spill = near & (a[:, :, 3] > 0) & (g8.astype(np.int16) > r8.astype(np.int16)*1.18) & (g8.astype(np.int16) > b8.astype(np.int16)*1.18)
    a[spill, 1] = np.maximum(r8[spill], b8[spill])
    a = _remove_far_fragments(a)
    return Image.fromarray(a, 'RGBA')


def remove_green_background(image: Image.Image) -> Image.Image:
    return image.convert('RGBA')
