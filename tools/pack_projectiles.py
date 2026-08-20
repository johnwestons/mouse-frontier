from pathlib import Path
from PIL import Image

root=Path(__file__).resolve().parents[1]
source=Image.open(root/"assets/sprites/projectiles/projectiles-v1.png").convert("RGBA")
cell_w=source.width/5
out=Image.new("RGBA",(5*128,64))
for i in range(5):
    left=round(i*cell_w); right=round((i+1)*cell_w)
    cell=source.crop((left,0,right,source.height))
    if i==3: cell=cell.crop((160,0,min(285,cell.width),cell.height))
    if i==4: cell=cell.crop((190,0,min(315,cell.width),cell.height))
    box=cell.getbbox(); cell=cell.crop(box) if box else cell
    # Firearms launch only the projectile; the brass case stays in the gun.
    # Keep the pointed right-hand portion and discard the case and its streak.
    if i>=3:
        cell=cell.crop((int(cell.width*.58),0,cell.width,cell.height))
        box=cell.getbbox(); cell=cell.crop(box) if box else cell
        target=(30,14) if i==3 else (38,12)
        cell=cell.resize(target,Image.Resampling.NEAREST)
    else:
        cell.thumbnail((112,42),Image.Resampling.NEAREST)
    out.alpha_composite(cell,(i*128+(128-cell.width)//2,(64-cell.height)//2))
out.save(root/"assets/sprites/projectiles/projectiles-packed-v1.png")
print("packed projectile atlas: 5 cells at 128x64")
