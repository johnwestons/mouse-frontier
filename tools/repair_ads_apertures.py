"""Clear reviewed ADS aperture fill by changing alpha only.

Run without --apply to write candidates and contrasting-background review sheets
under output/ads-aperture-audit/repair. Requires Pillow and NumPy. Coordinates
refer to authored source pixels, never normalized aim anchors. The masks leave
front posts, sight rims, and authored muzzle flashes intact.
"""
from pathlib import Path
import argparse
import json
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets/sprites/weapons/first-person'
OUTPUT = ROOT / 'output/ads-aperture-audit/repair'

# White backing is enclosed by the original dark sight outline. Bounds exclude
# the external silhouette and any unrelated pale metal highlights.
WHITE = {
    'compact-carbine': ((454, 294, 507, 345), [(480, 302)]),
    'frontier-556-carbine': ((490, 203, 526, 236), [(508, 208)]),
    'improvised-556-rifle': ((413, 238, 451, 276), [(432, 243)]),
    'frontier-9mm-smg': ((418, 238, 469, 287), [(442, 245), (441, 257), (442, 282)]),
    'wood-stock-survival-carbine': ((487, 252, 536, 282), [(510, 257)]),
}

# Dark backing cannot be selected by brightness. These small, hand-reviewed
# polygons follow the aperture interior and stop before the front post.
POLYGONS = {
    'rugged-submachine-gun-sights.png': [
        [(585,148),(591,148),(591,159),(585,159)],
    ],
    'actions/wood-stock-survival-carbine-ads-fire.png': [
        [(266,218),(277,218),(279,221),(279,226),(278,226),
         (278,222),(276,220),(268,220),(267,222),(267,226),(264,226),(264,221)],
        [(267,953),(276,953),(279,956),(280,961),(278,962),
         (278,957),(276,955),(269,955),(267,957),(267,962),(264,962),(264,957)],
        [(750,953),(759,953),(762,956),(763,962),(760,962),
         (760,957),(758,955),(752,955),(750,957),(749,962),(747,962),(747,957)],
    ],
    'actions/rugged-submachine-gun-ads-fire.png': [
        [(271,144),(276,144),(276,148),(271,148)],
        [(737,152),(741,152),(741,155),(737,155)],
        [(272,886),(277,886),(277,891),(272,891)],
        [(739,897),(743,897),(743,901),(739,901)],
    ],
}


def white_mask(pixels, bounds, seeds):
    rgb = pixels[:, :, :3].astype(int)
    eligible = (rgb.min(2) >= 110) & ((rgb.max(2) - rgb.min(2)) < 45)
    mask = np.zeros(eligible.shape, dtype=bool)
    x0, y0, x1, y1 = bounds
    queue = deque(seeds)
    while queue:
        x, y = queue.popleft()
        if not (x0 <= x < x1 and y0 <= y < y1):
            continue
        if mask[y, x] or not eligible[y, x]:
            continue
        mask[y, x] = True
        queue.extend(((x-1,y),(x+1,y),(x,y-1),(x,y+1)))
    return mask


def review_sheet(before, after, regions, path):
    # Every changed region is shown before/after on both light and dark, plus
    # a vivid split background that exposes any remaining opaque backing.
    sheet = Image.new('RGB', (1200, len(regions) * 220), '#252529')
    draw = ImageDraw.Draw(sheet)
    for row, box in enumerate(regions):
        for col, (label, color) in enumerate([
            ('light', '#e9e9e9'), ('dark', '#151520'), ('split', '#00c6b4')
        ]):
            for side, sprite in enumerate((before, after)):
                crop = sprite.crop(box)
                bg = Image.new('RGBA', crop.size, color)
                if label == 'split':
                    ImageDraw.Draw(bg).rectangle(
                        (crop.width//2, 0, crop.width, crop.height), fill='#ec009b')
                bg.alpha_composite(crop)
                bg.thumbnail((180,180))
                scale = min(180 // bg.width, 180 // bg.height)
                bg = bg.resize((bg.width*scale,bg.height*scale),Image.Resampling.NEAREST)
                x, y = col*400+side*200, row*220
                sheet.paste(bg.convert('RGB'), (x, y+30))
                draw.text((x+4,y+4),f'{label} {"before" if side == 0 else "after"}',fill='white')
    sheet.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    report = []
    filenames = [f'{name}-sights.png' for name in WHITE] + list(POLYGONS)
    for name in filenames:
        source = ASSETS / name
        before = Image.open(source).convert('RGBA')
        original = np.array(before)
        modified = original.copy()
        regions = []
        if name[:-11] in WHITE and name.endswith('-sights.png'):
            bounds, seeds = WHITE[name[:-11]]
            mask = white_mask(original, bounds, seeds)
            x0,y0,x1,y1 = bounds
            regions.append((x0-12,y0-12,x1+12,y1+12))
        else:
            mask_image = Image.new('1',before.size)
            draw = ImageDraw.Draw(mask_image)
            for polygon in POLYGONS[name]:
                draw.polygon(polygon, fill=1)
                xs,ys = zip(*polygon)
                regions.append((min(xs)-15,min(ys)-15,max(xs)+16,max(ys)+16))
            mask = np.array(mask_image, dtype=bool)
        modified[mask,3] = 0
        changed = original[:,:,3] != modified[:,:,3]
        assert np.array_equal(original[:,:,:3],modified[:,:,:3]), name
        assert np.array_equal(original[~mask],modified[~mask]), name
        assert np.all(modified[:,:,3] <= original[:,:,3]), name
        after = Image.fromarray(modified)
        target = OUTPUT / name
        target.parent.mkdir(parents=True, exist_ok=True)
        after.save(target)
        review_sheet(before,after,regions,OUTPUT/(Path(name).stem+'-review.png'))
        report.append({'file':name,'cleared_pixels':int(changed.sum()),
                       'rgb_unchanged':True,'outside_mask_unchanged':True})
        if args.apply and changed.any():
            after.save(source)
    (OUTPUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
