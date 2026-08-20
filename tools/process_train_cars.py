from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
GENERATED=Path(r"C:\Users\johnw\.codex\generated_images\019fecb0-a456-7410-a95b-1e8ee57838ee")
CARS={"coal-hauler":"exec-52bd413c-d755-4059-90c0-ae60d92e0517.png","greenhouse":"exec-999fa602-badd-4849-abf2-c5af13840f0d.png","sleeper":"exec-e6767117-f2f8-4c3f-89d5-3304c9bb512c.png","storage":"exec-0990394e-3580-4bc0-ae92-1779d54b6e33.png","medical":"exec-39cb861f-8459-433b-9c2d-43fa60f5f9b8.png","navigator":"exec-66d5740f-36e8-4209-b484-d5320438986c.png"}
OUT=ROOT/"assets"/"sprites"/"train"/"cars"; OUT.mkdir(parents=True,exist_ok=True)
for name,file in CARS.items():
 im=Image.open(GENERATED/file).convert("RGBA"); pixels=[]
 for r,g,b,a in im.getdata(): pixels.append((r,g,b,0) if g>150 and g>r*1.65 and g>b*1.65 else (r,g,b,a))
 im.putdata(pixels); bbox=im.getchannel("A").getbbox()
 if not bbox: raise ValueError(f"empty car: {name}")
 sprite=im.crop(bbox); scale=min(620/sprite.width,340/sprite.height); sprite=sprite.resize((round(sprite.width*scale),round(sprite.height*scale)),Image.Resampling.NEAREST)
 canvas=Image.new("RGBA",(640,360),(0,0,0,0)); canvas.alpha_composite(sprite,((640-sprite.width)//2,350-sprite.height)); canvas.save(OUT/f"{name}.png")
 im.save(OUT/f"{name}-generated-source.png"); print(name,canvas.size)
