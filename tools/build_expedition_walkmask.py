"""Rasterize traced expedition collision geometry; optionally preview it on the art.

The Lua definition is the shared source for navigation, headless collision, and
these editable PNG masks. This changes collision data, never the background art.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
for dependency in (os.environ.get("LUA_RUNTIME_PYTHONPATH"), ROOT / ".stabilization/python-deps"):
    if dependency and Path(dependency).is_dir():
        sys.path.insert(0, str(dependency))
from lupa.lua51 import LuaRuntime


def build(area_id: str, preview_dir: Path | None = None) -> Path:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + lua.globals().package.path
    area = lua.eval("require('game.expedition_areas').definition")(area_id)
    if area is None:
        raise ValueError(f"Unknown expedition area: {area_id}")
    width, height = int(area.width), int(area.height)
    y, x = np.mgrid[:height, :width]
    walkable = np.zeros((height, width), dtype=bool)
    for _, corridor in area.corridors.items():
        dx, dy = corridor.x2 - corridor.x1, corridor.y2 - corridor.y1
        length_squared = dx * dx + dy * dy
        t = np.clip(((x - corridor.x1) * dx + (y - corridor.y1) * dy)
                    / max(length_squared, 0.0001), 0, 1)
        walkable |= ((x - corridor.x1 - dx * t) ** 2
                     + (y - corridor.y1 - dy * t) ** 2 <= corridor.r ** 2)
    for _, clearing in area.clearings.items():
        rx, ry = clearing.rx or clearing.r, clearing.ry or clearing.r
        walkable |= ((x - clearing.x) / rx) ** 2 + ((y - clearing.y) / ry) ** 2 <= 1
    if area.walkRegions is not None:
        regions = Image.new("L", (width, height), 0)
        draw = ImageDraw.Draw(regions)
        for _, region in area.walkRegions.items():
            points = [(point.x if point.x is not None else point[1],
                       point.y if point.y is not None else point[2])
                      for _, point in sorted(region.points.items())]
            if len(points) < 3:
                raise ValueError(f"Walk region {region.id!r} needs at least three points")
            draw.polygon(points, fill=255)
        walkable |= np.asarray(regions) > 127
    mask = Image.fromarray(np.uint8(walkable) * 255).convert("RGB")
    destination = ROOT / area.walkMask
    mask.save(destination)
    if preview_dir is not None:
        preview_dir.mkdir(parents=True, exist_ok=True)
        background = Image.open(ROOT / area.background).convert("RGBA")
        if background.size != (width, height):
            background = background.resize((width, height))
        overlay = np.zeros((height, width, 4), dtype=np.uint8)
        overlay[walkable] = (20, 235, 125, 90)
        preview = Image.alpha_composite(background, Image.fromarray(overlay))
        draw = ImageDraw.Draw(preview)
        for _, point in area.interactions.items():
            draw.ellipse((point.x - 5, point.y - 5, point.x + 5, point.y + 5), fill="yellow")
            draw.text((point.x + 8, point.y - 15), point.id, fill="yellow", stroke_width=2, stroke_fill="black")
        for _, point in area.spawns.items():
            draw.ellipse((point.x - 8, point.y - 8, point.x + 8, point.y + 8), outline="cyan", width=3)
        preview.convert("RGB").save(preview_dir / f"{area_id}-overlay.png")
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--area", required=True, help="Area id whose traced geometry should be rasterized")
    parser.add_argument("--preview-dir", type=Path)
    args = parser.parse_args()
    print(build(args.area, args.preview_dir))
