from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path('assets/sprites/MainCharacters')
out = Path('.stabilization/character-base-audit.png')
out.parent.mkdir(exist_ok=True)
files = sorted(ROOT.glob('*.png'))
font = ImageFont.load_default()
cw, ch, cols = 180, 150, 6
sheet = Image.new('RGB', (cols*cw, ((len(files)+cols-1)//cols)*ch), '#202020')
d = ImageDraw.Draw(sheet)
for i, p in enumerate(files):
    im = Image.open(p).convert('RGBA')
    im.thumbnail((cw-16, ch-34), Image.Resampling.NEAREST)
    x = (i%cols)*cw + (cw-im.width)//2
    y = (i//cols)*ch + 4
    sheet.paste(im, (x, y), im)
    d.text(((i%cols)*cw+4, (i//cols)*ch+ch-25), p.stem, fill='#f3e9b0', font=font)
sheet.save(out)
print(out)
