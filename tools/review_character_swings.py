"""Assemble all staged swing frames over contrasting backgrounds for review."""
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/character-swings'
names=sorted(p.parent for p in OUT.glob('*/contact-backgrounds.png'))
dest=OUT/'reviews';dest.mkdir(exist_ok=True)
for start in range(0,len(names),5):
    batch=names[start:start+5]
    sheet=Image.new('RGB',(1152,220*len(batch)))
    for j,name in enumerate(batch):sheet.paste(Image.open(name/'contact-backgrounds.png'),(0,j*220))
    sheet.save(dest/f'page-{start//5+1:02d}.png')
print(f'{len(names)} character contact sheets')
