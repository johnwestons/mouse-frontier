from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]; GENERATED=Path(r"C:\Users\johnw\.codex\generated_images\019fecb0-a456-7410-a95b-1e8ee57838ee")
SHEETS={
"cowboy-mouse-no-skull":"exec-f69edba8-7e45-46dd-a4ff-deb89af33114.png","cowboy-mouse-on-skull":"exec-7c273d11-2e47-408b-a983-8f872a5148b4.png","crow-merchant":"exec-a493a5ce-8655-4178-ae49-a2186b1dff67.png","dog-red-scarf":"exec-d2fe5daf-94af-479b-bbb8-5b34a80f05fb.png",
"dog-yellow-scarf":"exec-73ec0700-fc6a-4700-ba4b-c139b870d185.png","hedgehog-botanist":"exec-3eeeaa0e-a84c-435e-af31-bada998275c4.png","jackrabbit-courier":"exec-40be27e0-5dab-451b-ac74-e532ba2c0f24.png","lizard-cook":"exec-3e18c9a0-3d93-4838-874d-24cbcd29e9b4.png",
"mole-prospector":"exec-2f77f941-b634-4790-8458-e875dbcbd223.png","mouse-engineer":"exec-35d348a5-f3bf-447d-af75-24b614d17d0d.png","musician-frog":"exec-3622ca15-abe8-4192-af67-118e4452bd6c.png","opossum-medic":"exec-cd0431e4-b811-4bf2-b714-85ab100790d1.png",
"otter-scout":"exec-3521b9fa-1a41-421e-8be6-3a605165779a.png","pipe-frog":"exec-0c61397a-0ef8-46ad-85c7-513ca8502942.png","prairie-dog-mechanic":"exec-c8631fc8-3119-44a8-8d12-44f6ed9c61cd.png","raccoon-cape":"exec-1838dcee-677d-4299-be16-c1b070f27503.png",
"raccoon-heart":"exec-b94ff8bd-1035-4461-8631-e9cc10cb1156.png","raccoon-witch":"exec-4cfae6e4-5928-4b1e-8cc2-5a586963c8a1.png","red-hood-mouse":"exec-fb9cfccc-bafd-4577-9df2-fb413171d44e.png","shield-mouse":"exec-daeda34c-78c1-4210-b0e5-76479821a175.png",
"skateboard-mouse":"exec-5e632a59-d388-4bdf-81cb-7c5253937d79.png","tortoise-conductor":"exec-e6e46f86-b55e-456e-8ba4-57ae86003d1f.png","vampire-mouse":"exec-eedb16ea-c4a9-4e47-a350-f0960264cb7d.png"}
CELL,MARGIN=160,8
def key(im):
 im=im.convert("RGBA"); p=[]
 for r,g,b,a in im.getdata(): p.append((r,g,b,0) if g>150 and g>r*1.65 and g>b*1.65 else (r,g,b,a))
 im.putdata(p); return im
def norm(im):
 b=im.getchannel("A").getbbox()
 if not b: raise ValueError("empty use frame")
 s=im.crop(b); z=min((CELL-MARGIN*2)/s.width,(CELL-MARGIN*2)/s.height); s=s.resize((max(1,round(s.width*z)),max(1,round(s.height*z))),Image.Resampling.NEAREST)
 c=Image.new("RGBA",(CELL,CELL),(0,0,0,0)); c.alpha_composite(s,((CELL-s.width)//2,CELL-MARGIN-s.height)); return c
for name,file in SHEETS.items():
 source=key(Image.open(GENERATED/file)); step=source.width//3; frames=[norm(source.crop((i*step,0,(i+1)*step if i<2 else source.width,source.height))) for i in range(3)]
 sheet=Image.new("RGBA",(CELL*3,CELL),(0,0,0,0))
 for i,f in enumerate(frames): sheet.alpha_composite(f,(i*CELL,0))
 out=ROOT/"assets"/"sprites"/"character-animations"/name; out.mkdir(parents=True,exist_ok=True); sheet.save(out/"use.png"); source.save(out/"use-generated-source.png"); print(name,sheet.size)
