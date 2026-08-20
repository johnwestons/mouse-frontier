from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GENERATED = Path(r"C:\Users\johnw\.codex\generated_images\019fecb0-a456-7410-a95b-1e8ee57838ee")
SHEETS = {
    "cowboy-mouse-no-skull": "exec-877c423e-c910-4ca3-9582-12db4258c7f4.png",
    "cowboy-mouse-on-skull": "exec-971f669a-3828-4a00-bc86-ee1918b735cd.png",
    "crow-merchant": "exec-9f5f130a-fbcd-4322-befd-a354c5dbef62.png",
    "dog-red-scarf": "exec-da9000c3-6ad1-435c-8808-d7eb1ac418e7.png",
    "dog-yellow-scarf": "exec-2eba6721-8f2c-4b93-a4ca-c95f2ad5039a.png",
    "hedgehog-botanist": "exec-45ae3ed6-d96c-4245-bcaf-5914736e78fd.png",
    "jackrabbit-courier": "exec-a0b9f03d-3821-4d27-8a8e-522e38229fc5.png",
    "lizard-cook": "exec-a7ba96b6-d6e0-4e3f-9c97-833e150d3d77.png",
    "mole-prospector": "exec-b2a788e5-e411-476a-a104-eac5ddec1d9e.png",
    "mouse-engineer": "exec-85eb9c2a-ee20-4a0f-beb1-a6f214bcdacb.png",
    "musician-frog": "exec-a4b85922-701e-4e5a-97d4-7b2dd3a446d3.png",
    "opossum-medic": "exec-a9fe0e27-31f6-4124-a5b2-8425e8a097fa.png",
    "otter-scout": "exec-172ef974-d812-4f0e-84d6-b6179a09ed49.png",
    "pipe-frog": "exec-9f2e5793-1fc5-43f8-975b-a927cc55374a.png",
    "prairie-dog-mechanic": "exec-f84684a3-3a0f-46f4-89ac-0e795e01455d.png",
    "raccoon-cape": "exec-e70fec0e-0aa4-4d7f-baff-8126412ea10a.png",
    "raccoon-heart": "exec-7290cac1-6c70-47c2-bc32-ac574a437063.png",
    "raccoon-witch": "exec-5c4394b2-323c-4f25-b35d-7372c93c5708.png",
    "red-hood-mouse": "exec-d929dce2-2e99-4b38-93e2-7b82b21a5604.png",
    "shield-mouse": "exec-eb2e8263-9cbe-470f-b21f-22ae2409649b.png",
    "skateboard-mouse": "exec-3841a2c7-aaea-4c61-9c87-e809c6f0fd25.png",
    "tortoise-conductor": "exec-e86da64c-790e-46fc-889b-ed500f2fafef.png",
    "vampire-mouse": "exec-a010d408-2653-4fc1-a6cc-12d3c6defba1.png",
}

CELL, MARGIN = 160, 8

def remove_green(image):
    image = image.convert("RGBA")
    pixels=[]
    for r,g,b,a in image.getdata():
        pixels.append((r,g,b,0) if g>150 and g>r*1.65 and g>b*1.65 else (r,g,b,a))
    image.putdata(pixels)
    return image

def normalize(frame):
    bbox=frame.getchannel("A").getbbox()
    if not bbox: raise ValueError("empty seated frame")
    sprite=frame.crop(bbox)
    scale=min((CELL-MARGIN*2)/sprite.width,(CELL-MARGIN*2)/sprite.height)
    sprite=sprite.resize((max(1,round(sprite.width*scale)),max(1,round(sprite.height*scale))),Image.Resampling.NEAREST)
    cell=Image.new("RGBA",(CELL,CELL),(0,0,0,0))
    cell.alpha_composite(sprite,((CELL-sprite.width)//2,CELL-MARGIN-sprite.height))
    return cell

for name,filename in SHEETS.items():
    source=remove_green(Image.open(GENERATED/filename))
    mid=source.width//2
    frames=[normalize(source.crop((0,0,mid,source.height))),normalize(source.crop((mid,0,source.width,source.height)))]
    sheet=Image.new("RGBA",(CELL*2,CELL),(0,0,0,0))
    sheet.alpha_composite(frames[0],(0,0)); sheet.alpha_composite(frames[1],(CELL,0))
    out=ROOT/"assets"/"sprites"/"character-animations"/name
    out.mkdir(parents=True,exist_ok=True)
    sheet.save(out/"sit.png")
    source.save(out/"sit-generated-source.png")
    print(f"{name}: sit.png {sheet.size}")
