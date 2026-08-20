from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [ROOT / "assets/sprites/MainCharacters", ROOT / "assets/sprites/NPCS"]
OUT = ROOT / "assets/sprites/character-animations"
CELL = 160

def normalized(path):
    im = Image.open(path).convert("RGBA")
    box = im.getbbox()
    if box:
        im = im.crop(box)
    im.thumbnail((124, 132), Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (CELL, CELL))
    canvas.alpha_composite(im, ((CELL-im.width)//2, CELL-im.height-12))
    return canvas

def anchored_resize(im, width, height, xoff=0, yoff=0):
    body = im.crop(im.getbbox() or (0,0,CELL,CELL))
    body = body.resize((max(1,width), max(1,height)), Image.Resampling.NEAREST)
    out = Image.new("RGBA", (CELL,CELL))
    out.alpha_composite(body, ((CELL-width)//2+xoff, CELL-height-12+yoff))
    return out

def rotated(im, degrees, xoff=0, yoff=0, tint=None):
    body = im.crop(im.getbbox() or (0,0,CELL,CELL)).rotate(degrees, Image.Resampling.NEAREST, expand=True)
    body.thumbnail((136,136), Image.Resampling.NEAREST)
    if tint:
        red = Image.new("RGBA", body.size, tint)
        red.putalpha(body.getchannel("A"))
        body = Image.blend(body, red, .30)
    out=Image.new("RGBA",(CELL,CELL)); out.alpha_composite(body,((CELL-body.width)//2+xoff,CELL-body.height-12+yoff)); return out

def reaching_pose(base):
    """Create a clearly different empty-hand reach for characters lacking authored action art."""
    out=base.copy(); box=out.getbbox() or (25,25,135,148); y=box[1]+int((box[3]-box[1])*.48); start=box[0]+32; end=max(8,box[0]-20)
    pixels=[p[:3] for p in out.getdata() if p[3]>180 and max(p[:3])-min(p[:3])<85]
    fill=sorted(pixels,key=lambda p:sum(p))[len(pixels)//2] if pixels else (171,112,68)
    draw=ImageDraw.Draw(out)
    draw.polygon([(start,y-7),(end+7,y-11),(end,y-5),(end,y+5),(end+7,y+11),(start,y+7)],fill=(55,32,22,255))
    draw.polygon([(start,y-3),(end+8,y-6),(end+4,y-2),(end+4,y+2),(end+8,y+6),(start,y+3)],fill=(*fill,255))
    return out

def strip(frames):
    out=Image.new("RGBA",(CELL*len(frames),CELL))
    for i,frame in enumerate(frames): out.alpha_composite(frame,(i*CELL,0))
    return out

def make(path):
    base=normalized(path); bbox=base.getbbox() or (20,20,140,148); bw,bh=bbox[2]-bbox[0],bbox[3]-bbox[1]
    name=path.stem; dest=OUT/name; dest.mkdir(parents=True,exist_ok=True)
    idle2=anchored_resize(base,bw,max(1,bh-2),0,2)
    sit=anchored_resize(base,bw,max(1,int(bh*.72)),0,2)
    lay=rotated(base,90,0,12)
    melee1=rotated(base,-7,-5,0); melee2=rotated(base,10,12,-2)
    ranged1=rotated(base,-5,-6,0); ranged2=rotated(base,5,7,0)
    authored=ROOT/"assets/sprites/MainCharacters/animations"/f"{name}-action.png"
    use_pose=normalized(authored) if authored.exists() else reaching_pose(base)
    hit1=rotated(base,-13,-9,4,(255,70,55,255)); hit2=rotated(base,10,8,2,(255,110,70,255))
    outputs={
        "idle":strip([base,idle2]), "sit":strip([sit,sit]), "lay":strip([lay,lay]),
        "melee":strip([base,melee1,melee2]), "ranged":strip([base,ranged1,ranged2]),
        "use":strip([base,use_pose,use_pose]), "hit":strip([base,hit1,hit2]),
    }
    for action,image in outputs.items(): image.save(dest/f"{action}.png")

seen=set()
for directory in SOURCES:
    for path in sorted(directory.glob("*.png")):
        if path.name=="clown-head.png" or path.stem in seen: continue
        seen.add(path.stem); make(path)
print(f"generated 7 animation sheets for {len(seen)} unique characters ({len(seen)*7} PNG files)")
