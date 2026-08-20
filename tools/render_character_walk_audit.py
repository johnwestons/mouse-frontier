from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path('assets/sprites')
out = Path('.stabilization/character-walk-audit.png')
out.parent.mkdir(exist_ok=True)
dirs = sorted((ROOT/'character-animations').iterdir())
font = ImageFont.load_default()
cell_w, cell_h = 180, 150
cols = 6
rows = (len(dirs)+cols-1)//cols
sheet = Image.new('RGB', (cols*cell_w, rows*cell_h), '#202020')
d = ImageDraw.Draw(sheet)
for i, folder in enumerate(dirs):
    if not folder.is_dir():
        continue
    p = folder/'walk.png'
    if not p.exists(): p = folder/'idle.png'
    if not p.exists(): continue
    im = Image.open(p).convert('RGBA')
    n = 6 if im.width >= im.height*4 else (2 if im.width >= im.height*2 else 1)
    frame = im.crop((0,0,im.width//n,im.height))
    frame.thumbnail((cell_w-16, cell_h-34), Image.Resampling.NEAREST)
    x = (i%cols)*cell_w + (cell_w-frame.width)//2
    y = (i//cols)*cell_h + 4
    sheet.paste(frame, (x,y), frame)
    d.text(((i%cols)*cell_w+4, (i//cols)*cell_h+cell_h-25), folder.name, fill='#f3e9b0', font=font)
sheet.save(out)
print(out)
