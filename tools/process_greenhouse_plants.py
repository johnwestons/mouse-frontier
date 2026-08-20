from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"C:\Users\johnw\.codex\generated_images\019fecb0-a456-7410-a95b-1e8ee57838ee\exec-80349fca-8e32-40c8-9572-bb35255d938b.png")
OUTPUT = ROOT / "assets" / "sprites" / "plants"
CROPS = ("tomato", "corn", "carrot", "medicinal-herb")
STAGES = ("sprout", "growing", "mature")


def remove_magenta(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, _ = pixels[x, y]
            keyed = r > 180 and b > 150 and g < min(r, b) * 0.58
            if keyed:
                pixels[x, y] = (r, g, b, 0)
            else:
                # Hard-edge despill preserves the deliberately chunky pixels.
                if r > g * 1.7 and b > g * 1.45:
                    shared = max(g, min(r, b) // 2)
                    r, b = min(r, shared), min(b, shared)
                pixels[x, y] = (r, g, b, 255)
    return image


source = Image.open(SOURCE)
transparent_atlas = remove_magenta(source)
OUTPUT.mkdir(parents=True, exist_ok=True)
transparent_atlas.save(OUTPUT / "greenhouse-growth-atlas-v1.png", optimize=True)

alpha = transparent_atlas.getchannel("A")
mask = alpha.load()
width, height = alpha.size
visited = bytearray(width * height)
components = []
for sy in range(height):
    for sx in range(width):
        start = sy * width + sx
        if visited[start] or mask[sx, sy] == 0:
            continue
        queue = deque([(sx, sy)])
        visited[start] = 1
        left = right = sx
        top = bottom = sy
        count = 0
        while queue:
            x, y = queue.popleft()
            count += 1
            left, right = min(left, x), max(right, x)
            top, bottom = min(top, y), max(bottom, y)
            for nx, ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if 0 <= nx < width and 0 <= ny < height:
                    index = ny * width + nx
                    if not visited[index] and mask[nx, ny] != 0:
                        visited[index] = 1
                        queue.append((nx, ny))
        if count > 1000:
            components.append((left, top, right + 1, bottom + 1, count))

# Sort complete silhouettes into the visual 4x3 arrangement.
components = sorted(components, key=lambda box: box[4], reverse=True)[:12]
components = sorted(components, key=lambda box: (box[1] + box[3]) / 2)
rows = [sorted(components[i:i+4], key=lambda box: (box[0] + box[2]) / 2) for i in range(0, 12, 4)]
for row, stage in enumerate(STAGES):
    for column, crop in enumerate(CROPS):
        left, top, right, bottom, _ = rows[row][column]
        subject = transparent_atlas.crop((left, top, right, bottom))
        scale = min(220 / subject.width, 220 / subject.height)
        size = (max(1, round(subject.width * scale)), max(1, round(subject.height * scale)))
        subject = subject.resize(size, Image.Resampling.NEAREST)
        sprite = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        sprite.alpha_composite(subject, ((256 - subject.width) // 2, 246 - subject.height))
        destination = OUTPUT / f"{crop}-{stage}.png"
        sprite.save(destination, optimize=True)
        print(destination.relative_to(ROOT))
