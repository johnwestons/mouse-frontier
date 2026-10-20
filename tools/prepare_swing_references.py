"""Contact sheets of existing art for swing identity review (no new artwork)."""
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'output/character-swings/references'; out.mkdir(parents=True,exist_ok=True)
paths=sorted((ROOT/'assets/sprites/character-animations').glob('*/melee.png'))
for start in range(0,len(paths),15):
    sheet=Image.new('RGB',(1200,720),(232,228,215)); draw=ImageDraw.Draw(sheet)
    for i,path in enumerate(paths[start:start+15]):
        im=Image.open(path).convert('RGBA'); im=im.crop((0,0,im.width//6,im.height))
        im.thumbnail((390,210))
        x,y=(i%3)*400,(i//3)*144
        im.thumbnail((390,120)); sheet.paste(im,(x+(400-im.width)//2,y+20),im)
        draw.text((x+5,y+3),path.parent.name,fill='black')
    sheet.save(out/f'roster-{start//15+1}.png')
print([p.parent.name for p in paths])
