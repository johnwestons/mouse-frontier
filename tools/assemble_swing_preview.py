"""Assemble the actual LÖVE-rendered frog frames into a review animation."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
frames = []
for index in range(1, 7):
    with Image.open(ROOT / f'.stabilization/character-swing/desktop-frog-frame-{index}.png') as image:
        frames.append(image.crop((140, 60, 370, 280)).convert('RGB').resize((460, 440), Image.Resampling.NEAREST))
output = ROOT / 'output/character-swings/botanist-frog-equipped.gif'
frames[0].save(output, save_all=True, append_images=frames[1:], duration=[250, 100, 100, 80, 100, 400], loop=0)
print(output)
