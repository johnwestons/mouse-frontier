"""Reference catalog of actual held melee sprites, preserving runtime atlas cells."""
import json,re,sys
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/character-swings/weapons';OUT.mkdir(parents=True,exist_ok=True)
catalog=(ROOT/'game/catalog.lua').read_text(encoding='utf-8')
names=re.findall(r'\["([^"]+)"\]=\{kind="melee"',catalog)
atlases={}
for path,items,cols,rows in re.findall(r'registerItemAtlas\(ui, "([^"]+)", \{([^}]+)\}, (\d+), (\d+)',(ROOT/'game/assets.lua').read_text()):
    for i,name in enumerate(re.findall(r'"([^"]+)"',items)):
        atlases[name]=(path,i,int(cols),int(rows))
records={}
for name in names:
    if name=='mob-claw':continue
    if name in atlases:
        path,i,cols,rows=atlases[name];im=Image.open(ROOT/path).convert('RGBA')
        w,h=im.width//cols,im.height//rows; x,y=i%cols*w,i//cols*h
        im=im.crop((x,y,x+w,y+h));records[name]={'path':path,'cell':[x,y,w,h]}
    else:
        path=f'assets/sprites/weapons/{name}.png'
        if not (ROOT/path).exists():print('MISSING',name);continue
        im=Image.open(ROOT/path).convert('RGBA');records[name]={'path':path,'cell':[0,0,im.width,im.height]}
    im.save(OUT/f'{name}.png')
names=list(records)
for start in range(0,len(names),12):
    sheet=Image.new('RGB',(1000,900),(226,222,209));draw=ImageDraw.Draw(sheet)
    for j,name in enumerate(names[start:start+12]):
        im=Image.open(OUT/f'{name}.png').convert('RGBA');im.thumbnail((230,260))
        x,y=(j%4)*250,(j//4)*300
        sheet.paste(im,(x+(250-im.width)//2,y+30+(260-im.height)//2),im)
        draw.text((x+3,y+5),name,fill='black')
    sheet.save(OUT/f'catalog-{start//12+1}.png')
(OUT/'sources.json').write_text(json.dumps(records,indent=2))
print(len(records),'weapon sprites')
