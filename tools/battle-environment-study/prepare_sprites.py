"""Extract existing idle frames for the independent terrain study; never edit source art."""
from pathlib import Path
from PIL import Image
import base64
import io
import json

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'tmp/battle-environment-study'
DEST.mkdir(parents=True, exist_ok=True)
DIRECTIONS = ['idle', 'idle_southeast', 'idle_south', 'idle_southwest', 'idle_west',
              'idle_northwest', 'idle_north', 'idle_northeast']
result = {}
for name in ['trail-fox', 'watch-raccoon', 'botanist-frog']:
    frames = []
    for direction in DIRECTIONS:
        source = ROOT / 'assets/sprites/character-animations' / name / f'{direction}.png'
        with Image.open(source) as sheet:
            frames.append(sheet.convert('RGBA').crop((0, 0, sheet.width // 2, sheet.height)))
    bounds = [frame.getbbox() for frame in frames]
    crop = (min(b[0] for b in bounds), min(b[1] for b in bounds),
            max(b[2] for b in bounds), max(b[3] for b in bounds))
    urls = []
    for frame in frames:
        frame = frame.crop(crop)
        frame.thumbnail((96, 128), Image.Resampling.NEAREST)
        frame = frame.quantize(colors=128, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
        buf = io.BytesIO()
        frame.save(buf, format='PNG', optimize=True)
        urls.append('data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode('ascii'))
    result[name] = {'directions': urls, 'aspect': frame.width / frame.height}
(DEST / 'sprite-data.json').write_text(json.dumps(result, separators=(',', ':')), encoding='utf-8')
print(f'Extracted {len(result) * 8} reviewed idle views; original sheets untouched')
