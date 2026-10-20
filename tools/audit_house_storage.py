"""Render the authored storage anchor on every home painting for visual review."""
from pathlib import Path
import argparse
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".stabilization/python-deps"))
from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".stabilization/house-storage-audit")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().project_root = ROOT.as_posix()
    lua.execute("package.path=project_root..'/?.lua;'..package.path")
    storage = lua.eval("require('game.house_storage')")
    for first in range(6, 256, 25):
        sheet = Image.new("RGB", (2000, 1250), (20, 20, 20))
        draw = ImageDraw.Draw(sheet)
        for offset, index in enumerate(range(first, min(first + 25, 256))):
            spot = storage.definition(index)
            col, row = offset % 5, offset // 5
            painting = Image.open(ROOT / "assets/sprites/interiors" / spot.filename).convert("RGB")
            sheet.paste(painting.resize((400, 225)), (col * 400, row * 250 + 25))
            x, y = col * 400 + spot.u * 400, row * 250 + 25 + spot.v * 225
            draw.ellipse((x-9, y-9, x+9, y+9), outline="black", width=5)
            draw.ellipse((x-8, y-8, x+8, y+8), outline="#ffee55", width=3)
            draw.line((x-12, y, x+12, y), fill="#ffee55", width=2)
            draw.line((x, y-12, x, y+12), fill="#ffee55", width=2)
            draw.text((col*400+5, row*250+5), f"{index}: {spot.filename}", fill="white")
        filename = args.output / f"anchors-{(first-6)//25+1:02}.jpg"
        sheet.save(filename, quality=95)
        print(filename)


if __name__ == "__main__":
    main()
