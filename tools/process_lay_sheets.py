from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
GENERATED=Path(r"C:\Users\johnw\.codex\generated_images\019fecb0-a456-7410-a95b-1e8ee57838ee")
SHEETS={
"cowboy-mouse-no-skull":"exec-1487aeca-c990-42e1-b7e7-496d26d3c3ac.png","cowboy-mouse-on-skull":"exec-d28a96e8-6138-4350-9483-d02e09190f37.png",
"crow-merchant":"exec-38f412b4-8911-46c2-80f1-baf366cf3bf0.png","dog-red-scarf":"exec-ef592832-e907-46f3-9230-6ffda1a14746.png",
"dog-yellow-scarf":"exec-c7abc7b3-a7d5-40dc-a98d-d1b8e9e5b920.png","hedgehog-botanist":"exec-71cda12e-baba-4fa9-b85c-2319de9ec89c.png",
"jackrabbit-courier":"exec-11d00993-9cdb-49b0-8674-ba7c25510304.png","lizard-cook":"exec-70eabe48-9995-4585-a3c7-97c3a7311277.png",
"mole-prospector":"exec-1d4c00e9-7027-4c9f-84e4-5f4c426c57e7.png","mouse-engineer":"exec-8e2e9377-2638-4687-a145-e37fa2ee7060.png",
"musician-frog":"exec-5644c02c-80dc-410b-a7c4-e0cdfc4bc9b4.png","opossum-medic":"exec-f94e5601-f09a-4ac8-bd74-eccdac8b82ef.png",
"otter-scout":"exec-8eb66799-953c-441b-9753-2b44e3cebcdd.png","pipe-frog":"exec-375283b5-9176-4704-8f52-5058fa4ec8bf.png",
"prairie-dog-mechanic":"exec-54011517-0cc4-4d77-bdba-61b2b700d36a.png","raccoon-cape":"exec-786f7532-ec91-4450-88b8-e15986643480.png",
"raccoon-heart":"exec-567f9268-2f4a-40a0-816c-7fdd4cf33786.png","raccoon-witch":"exec-c14479f1-4699-4d30-b6cb-328497938681.png",
"red-hood-mouse":"exec-21891665-1563-46b6-a9a8-d3d62addf5b2.png","shield-mouse":"exec-df3c4b94-982c-44b3-b65d-23a55742e373.png",
"skateboard-mouse":"exec-a216b366-bf71-4bdd-9649-ee19605825f6.png","tortoise-conductor":"exec-2e72775d-248e-4771-82d8-ee03a8977d63.png",
"vampire-mouse":"exec-bc1fb2e5-b76c-4c97-bf9a-6e9f06624bfa.png"}
CELL,MARGIN=160,8

def remove_green(im):
    im=im.convert("RGBA"); out=[]
    for r,g,b,a in im.getdata(): out.append((r,g,b,0) if g>150 and g>r*1.65 and g>b*1.65 else (r,g,b,a))
    im.putdata(out); return im

def normalize(frame):
    bbox=frame.getchannel("A").getbbox()
    if not bbox: raise ValueError("empty sleep frame")
    sprite=frame.crop(bbox); scale=min((CELL-MARGIN*2)/sprite.width,(CELL-MARGIN*2)/sprite.height)
    sprite=sprite.resize((max(1,round(sprite.width*scale)),max(1,round(sprite.height*scale))),Image.Resampling.NEAREST)
    cell=Image.new("RGBA",(CELL,CELL),(0,0,0,0)); cell.alpha_composite(sprite,((CELL-sprite.width)//2,CELL-MARGIN-sprite.height)); return cell

for name,filename in SHEETS.items():
    source=remove_green(Image.open(GENERATED/filename)); mid=source.width//2
    a=normalize(source.crop((0,0,mid,source.height))); b=normalize(source.crop((mid,0,source.width,source.height)))
    sheet=Image.new("RGBA",(CELL*2,CELL),(0,0,0,0)); sheet.alpha_composite(a,(0,0)); sheet.alpha_composite(b,(CELL,0))
    out=ROOT/"assets"/"sprites"/"character-animations"/name; out.mkdir(parents=True,exist_ok=True)
    sheet.save(out/"lay.png"); source.save(out/"lay-generated-source.png"); print(f"{name}: lay.png {sheet.size}")
