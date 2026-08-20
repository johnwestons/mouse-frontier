from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]; GENERATED=Path(r"C:\Users\johnw\.codex\generated_images\019fecb0-a456-7410-a95b-1e8ee57838ee")
SHEETS={
"cowboy-mouse-no-skull":"exec-f2ec2e30-0a34-4e44-aad0-0eab0951a4f7.png","cowboy-mouse-on-skull":"exec-47215a7e-b31a-4020-8252-ccb5ddc98ef7.png","crow-merchant":"exec-27185b01-d62e-42d3-a9ed-ff9db71a71bd.png","dog-red-scarf":"exec-12df6420-4250-44d6-a28c-e63f066ea43a.png",
"dog-yellow-scarf":"exec-51b8985d-650e-4444-a829-8a3fc62fcea5.png","hedgehog-botanist":"exec-6f941084-4260-44c7-a3a3-45b7c44cc7d7.png","jackrabbit-courier":"exec-78032f0e-f39f-4a04-88a9-3e26a7c7167e.png","lizard-cook":"exec-19a44c06-9bf1-4c7b-be83-8aad2c6aadc3.png",
"mole-prospector":"exec-c74a0136-9ace-41fe-94e1-e9b5dc2ed6e0.png","mouse-engineer":"exec-7bdb0c10-5e6b-49e9-b69a-a47688615cb4.png","musician-frog":"exec-3dd6fa6b-7fee-42a2-8e1a-6fbfb5e3d882.png","opossum-medic":"exec-74e4be27-064c-43ac-92d2-6f857c1a67bc.png",
"otter-scout":"exec-7b02bfbc-5b10-4957-a7a2-4d51dfd31708.png","pipe-frog":"exec-301f9cff-35aa-46d3-b3ca-aa4aee2c98e9.png","prairie-dog-mechanic":"exec-363f4f94-1a9f-4038-8e58-708b400c2192.png","raccoon-cape":"exec-cef40bd9-1c57-4b43-9320-4fa838210729.png",
"raccoon-heart":"exec-152301e5-ef8f-4ec4-b904-8a0fbc408b83.png","raccoon-witch":"exec-bebc854c-f07c-442a-b538-a11eed022ece.png","red-hood-mouse":"exec-e9670a6f-2480-4feb-b14f-b04ac113a9a9.png","shield-mouse":"exec-ddc6f724-21c1-41af-bab2-0565d5742229.png",
"skateboard-mouse":"exec-d05db011-3645-44d6-abaa-bc7ce979eca7.png","tortoise-conductor":"exec-3ab08433-11a1-4879-b58a-36c389f2d2d6.png","vampire-mouse":"exec-3669409c-52ca-44c6-a2c9-91bb07b8fd7a.png"}
CELL,MARGIN=160,8
def key(im):
 im=im.convert("RGBA"); p=[]
 for r,g,b,a in im.getdata(): p.append((r,g,b,0) if g>150 and g>r*1.65 and g>b*1.65 else (r,g,b,a))
 im.putdata(p); return im
def norm(im):
 b=im.getchannel("A").getbbox()
 if not b: raise ValueError("empty melee frame")
 s=im.crop(b); z=min((CELL-MARGIN*2)/s.width,(CELL-MARGIN*2)/s.height); s=s.resize((max(1,round(s.width*z)),max(1,round(s.height*z))),Image.Resampling.NEAREST)
 c=Image.new("RGBA",(CELL,CELL),(0,0,0,0)); c.alpha_composite(s,((CELL-s.width)//2,CELL-MARGIN-s.height)); return c
for name,file in SHEETS.items():
 source=key(Image.open(GENERATED/file)); step=source.width//3; frames=[norm(source.crop((i*step,0,(i+1)*step if i<2 else source.width,source.height))) for i in range(3)]
 sheet=Image.new("RGBA",(CELL*3,CELL),(0,0,0,0))
 for i,f in enumerate(frames): sheet.alpha_composite(f,(i*CELL,0))
 out=ROOT/"assets"/"sprites"/"character-animations"/name; out.mkdir(parents=True,exist_ok=True); sheet.save(out/"melee.png"); source.save(out/"melee-generated-source.png"); print(name,sheet.size)
