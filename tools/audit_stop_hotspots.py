"""Check painted hotspot reach against real collision masks and render review sheets."""
from pathlib import Path
import json
import math
import os
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw


def audit(output=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().root = ROOT.as_posix()
    lua.execute("package.path=root..'/?.lua;'..package.path; H=require('game.stop_hotspots')")
    results = []
    pages = []
    for stop in range(1, 51):
        mask = Image.open(ROOT / f'assets/sprites/stops/walkmask-{stop:02}.png').convert('RGB')
        pixels = mask.load()
        def walkable(x, y):
            if not (6 <= x < 954 and 6 <= y < 714):
                return False
            return all(pixels[int(px / 960 * mask.width), int(py / 720 * mask.height)][0] > 127
                       for px, py in [(x, y), (x-6, y), (x+6, y), (x, y-6), (x, y+6)])
        frame = Image.open(ROOT / f'assets/sprites/stops/settlement-wide-{stop:02}.png').convert('RGB').resize((640,480))
        draw = ImageDraw.Draw(frame)
        for spot in lua.globals().H.definitions(stop).values():
            x, y = spot.x, spot.y
            # Match Settlements.clamp's six-pixel rings and 48 directions.
            nearest = (x, y) if walkable(x, y) else None
            if nearest is None:
                for radius in range(6, 300, 6):
                    for step in range(48):
                        theta = step * math.tau / 48
                        point = x + math.cos(theta)*radius, y + math.sin(theta)*radius
                        if walkable(*point):
                            nearest = point
                            break
                    if nearest:
                        break
            distance = math.dist((x,y), nearest) if nearest else 999
            record = dict(stop=stop, id=spot.id, kind=spot.kind, title=spot.title, x=x, y=y,
                          reach=round(distance,2), radius=spot.radius, approach=nearest)
            results.append(record)
            color = '#8dff55' if spot.kind == 'harvest' else '#ffe16a'
            if distance >= spot.radius:
                color = '#ff4040'
            px, py = x/1.5, y/1.5
            if nearest:
                draw.line((px,py,nearest[0]/1.5,nearest[1]/1.5), fill=color,width=2)
            draw.ellipse((px-8,py-8,px+8,py+8),outline='black',width=4)
            draw.ellipse((px-7,py-7,px+7,py+7),outline=color,width=2)
            label=f'{spot.title} ({distance:.0f}px)'
            tx=min(px+10,630-draw.textlength(label))
            draw.text((max(4,tx),py-20),label,fill=color,stroke_width=2,stroke_fill='black')
        draw.text((12,12),f'STOP {stop:02}',fill='white',stroke_width=3,stroke_fill='black')
        pages.append(frame)
    if output:
        output.mkdir(parents=True, exist_ok=True)
        (output/'hotspot-reach.json').write_text(json.dumps(results,indent=2))
        for start in range(0,50,6):
            sheet=Image.new('RGB',(640*3,480*2))
            for i,frame in enumerate(pages[start:start+6]):
                sheet.paste(frame,((i%3)*640,(i//3)*480))
            sheet.save(output/f'hotspots-{start+1:02}-{min(start+6,50):02}.jpg',quality=90)
    return results


if __name__ == '__main__':
    results=audit(ROOT / '.stabilization/stop-hotspots')
    failures=[r for r in results if r['reach']>=r['radius']]
    print(json.dumps({'hotspots':len(results),'unreachable':failures},indent=2))
    sys.exit(bool(failures))
