"""Import authored home-stop strips without changing their drawn poses.

Source files stay immutable. This only measures gutters, packs full frames,
and aligns their ground contact for the existing 512px animation pipeline.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/home-stop-art-review'
OUT.mkdir(parents=True, exist_ok=True)

def prepare(name):
    source = ROOT / f'assets/sprites/home-stop/{name}-v1.png'
    image = Image.open(source).convert('RGBA')
    alpha = np.asarray(image)[:, :, 3]
    counts = (alpha > 16).sum(axis=0)
    cuts = [0]
    for index in range(1, 4):
        center = round(image.width * index / 4)
        candidates = range(center - 65, center + 66)
        cut = min(candidates, key=lambda x: (counts[x], abs(x-center)))
        cuts.append(cut)
    cuts.append(image.width)
    frames = [image.crop((cuts[i], 0, cuts[i+1], image.height)) for i in range(4)]
    boxes = [frame.getchannel('A').point(lambda a: 255 if a > 16 else 0).getbbox() for frame in frames]
    scale = 385 / float(np.median([box[3]-box[1] for box in boxes]))
    result = Image.new('RGBA', (2048, 512))
    for index, (frame, box) in enumerate(zip(frames, boxes)):
        # Planted feet remain the anchor while the head and wrench can lean.
        band = np.asarray(frame)[:, :, 3] > 16
        top = box[3] - max(12,round((box[3]-box[1])*.07))
        bottom = box[3]
        _, xs = np.where(band[top:bottom])
        anchor = float(np.median(xs))
        sprite = frame.crop(box)
        sprite = sprite.resize((round(sprite.width*scale), round(sprite.height*scale)), Image.Resampling.LANCZOS)
        x = round(index*512+256-(anchor-box[0])*scale)
        y = 458-sprite.height
        assert x >= index*512+2 and x+sprite.width <= (index+1)*512-2, (source, index, x, sprite.width)
        result.alpha_composite(sprite, (x,y))
    destination = ROOT / f'assets/sprites/home-stop/{name}-runtime.png'
    result.save(destination)
    contact = Image.new('RGB', result.size, '#556877')
    contact.paste(result, mask=result.getchannel('A'))
    contact.save(OUT / f'{name}-contact.png')
    return {'source':str(source.relative_to(ROOT)), 'runtime':str(destination.relative_to(ROOT)),
            'cuts':cuts, 'source_frame_boxes':boxes, 'source_scale':scale}

if __name__ == '__main__':
    imports=[]
    for name in ('tinker-wrench', 'tinker-oil-west'):
        if (ROOT / f'assets/sprites/home-stop/{name}-v1.png').exists(): imports.append(prepare(name))
    office = Image.open(ROOT / 'assets/sprites/stops/home-office-exterior-v2.png').convert('RGBA')
    a = np.asarray(office)[:, :, 3]
    print('OFFICE_ALPHA', int(a.min()), int(a.max()), round(float((a==0).mean()), 3))
    print('OFFICE_SAMPLES', [(x,y,int(a[y,x])) for x,y in ((30,600),(800,30),(1400,200),(20,900),(800,1000))])
    for color,label in (('#ffffff','light'),('#9a225c','pink')):
        composite=Image.new('RGB',office.size,color); composite.paste(office,mask=office.getchannel('A'))
        composite.save(OUT/f'office-{label}.png')
    assert (a[:4,:4] == 0).all() and (a[-4:,-4:] == 0).all(), 'Office background is opaque'
    (OUT/'import-report.json').write_text(json.dumps(imports, indent=2), encoding='utf-8')
    from prepare_home_stop_adult_fox import build
    build()
    print(json.dumps(imports))
