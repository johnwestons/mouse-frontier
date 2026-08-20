from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path('assets/sprites/character-animations')

def clean_frame(im):
    a = np.array(im.convert('RGBA')); alpha = a[:,:,3]; transparent = alpha == 0
    near = transparent.copy()
    for dy in (-1,0,1):
        for dx in (-1,0,1):
            if dx or dy: near |= np.roll(np.roll(transparent,dy,0),dx,1)
    r,g,b = a[:,:,0],a[:,:,1],a[:,:,2]
    spill = near & (alpha > 0) & (g > 28) & (g.astype(np.int16) > r.astype(np.int16)*1.12) & (g.astype(np.int16) > b.astype(np.int16)*1.12)
    a[spill,3] = 0
    opaque = a[:,:,3] > 0
    white = opaque & (a[:,:,0] > 220) & (a[:,:,1] > 220) & (a[:,:,2] > 220)
    green = opaque & (a[:,:,1].astype(np.int16) > a[:,:,0].astype(np.int16)*1.35) & (a[:,:,1].astype(np.int16) > a[:,:,2].astype(np.int16)*1.35)
    for y in np.where(white.sum(axis=1) > im.width*.78)[0]: a[y,:,3] = 0
    for x in np.where(white.sum(axis=0) > im.height*.78)[0]: a[:,x,3] = 0
    for y in np.where(green.sum(axis=1) > im.width*.78)[0]: a[y,:,3] = 0
    for x in np.where(green.sum(axis=0) > im.height*.78)[0]: a[:,x,3] = 0
    return Image.fromarray(a,'RGBA')

for folder in ROOT.iterdir():
    if not folder.is_dir(): continue
    for path in folder.glob('*.png'):
        if path.name in ('walk.png','idle.png'): continue
        im=Image.open(path).convert('RGBA'); count=im.width//im.height if im.width>=im.height and im.width%im.height==0 else 1; fw=im.width//count
        out=Image.new('RGBA',im.size,(0,0,0,0))
        for i in range(count): out.alpha_composite(clean_frame(im.crop((i*fw,0,(i+1)*fw,im.height))),(i*fw,0))
        out.save(path,optimize=True)
print('cleaned action edges')
