"""Author a deterministic pixel surface kit for native procedural battle scenery."""
from pathlib import Path
from PIL import Image, ImageDraw
import math
import random

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'assets/sprites/battle-maps/procedural'
SIZE=128

def surface(kind):
    rng=random.Random(1013+kind*7919)
    image=Image.new('RGB',(SIZE,SIZE))
    p=image.load()
    sites=[(rng.randrange(SIZE),rng.randrange(SIZE))for _ in range(42)]
    for y in range(SIZE):
        for x in range(SIZE):
            grain=rng.randint(-11,11)
            value=204+grain
            if kind==0:
                distances=sorted(min(abs(x-a),SIZE-abs(x-a))**2+min(abs(y-b),SIZE-abs(y-b))**2 for a,b in sites)
                seam=math.sqrt(distances[1])-math.sqrt(distances[0])
                if seam<.32:value=139+grain//3
                elif seam<.75:value=220+grain//2
            elif kind==1:
                value=213+grain//2-(11 if (y+int(3*math.sin(x*.09)))%23<3 else 0)
            elif kind==2:
                value=198+grain+int(9*math.sin(y*.29+math.sin(x*.04)*2))
                if (y+int(math.sin(x*.07)*4))%31<2:value=168+grain//2
            elif kind==3:
                value=183+grain*2
            elif kind==4:
                value=176+grain*2
            elif kind==5:
                value=195+grain//2+int(17*math.sin(x*.38+math.sin(y*.07)))
                if x%32<2:value=88+grain
            elif kind==6:
                value=201+grain//2
                if rng.random()<.18:value-=rng.randrange(20,65)
            elif kind==7:
                row=y//20
                mortar=y%20<2 or (x+(row%2)*16)%32<2
                value=(108 if mortar else 211)+grain//2
            value=max(0,min(255,value));p[x,y]=(value,value,value)
    draw=ImageDraw.Draw(image)
    if kind in (0,1,2,4):
        for _ in range(55 if kind==0 else 95):
            x,y=rng.randrange(SIZE),rng.randrange(SIZE);s=rng.choice((1,1,2,3))
            draw.rectangle((x,y,x+s,y+s),fill=(141,141,141));draw.line((x,y,x+s,y),fill=(232,232,232))
    if kind==1:
        for y in (27,84):
            for x in range(0,SIZE,6):
                draw.line((x,y,x+3,y+rng.choice((-1,0,1))),fill=(160,160,160),width=2)
    if kind==4:
        for _ in range(44):
            x,y=rng.randrange(SIZE),rng.randrange(SIZE);w,h=rng.randrange(3,12),rng.randrange(2,7)
            draw.polygon(((x,y),(x+w,y+1),(x+w-2,y+h),(x+1,y+h-1)),fill=rng.choice(((146,146,146),(218,218,218),(184,184,184))))
            draw.line((x,y,x+w,y+1),fill=(239,239,239))
    if kind==3:
        for _ in range(190):
            x,y=rng.randrange(SIZE),rng.randrange(SIZE)
            draw.line((x,y,x+rng.choice((-1,0,1)),y-rng.randrange(2,6)),fill=rng.choice(((116,116,116),(230,230,230),(211,211,211))))
    if kind==6:
        for x in (6,121):
            for y in (6,121):
                draw.rectangle((x-2,y-2,x+2,y+2),fill=(84,84,84));draw.point((x-1,y-1),fill=(246,246,246))
    return image

def main():
    DEST.mkdir(parents=True,exist_ok=True)
    atlas=Image.new('RGB',(SIZE*4,SIZE*2))
    for kind in range(8):atlas.paste(surface(kind),((kind%4)*SIZE,(kind//4)*SIZE))
    path=DEST/'surface-kit-v1.png';atlas.save(path,optimize=True)
    print(f'BATTLE_SURFACE_KIT {path} {atlas.size}')

if __name__=='__main__':main()
