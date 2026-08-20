from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
GENERATED = Path(r"C:\Users\johnw\.codex\generated_images\019fecb0-a456-7410-a95b-1e8ee57838ee")
SETS = (
    ("exec-e316dc60-36ae-4d42-9b71-f98fe61cdb2d.png", "stop-tiles", 4, 4, (
        "grass-bright", "grass-dark", "grass-dirt-edge", "mossy-stone", "mud", "rocky-dirt", "flower-meadow", "cracked-stone",
        "tall-grass", "tilled-soil", "sparse-weeds", "wildflower-field", "stone-cliff", "earth-cliff", "worn-path", "compacted-dirt")),
    ("exec-43c9623f-62af-4a0b-a32d-f149b663dbe9.png", "stop-props", 5, 4, (
        "pine-tree", "fir-tree", "small-broadleaf-tree", "large-broadleaf-tree", "autumn-tree", "white-birch", "dead-white-tree", "dead-brown-tree", "tall-stump", "mossy-stump",
        "flowering-shrub", "white-flower-shrub", "red-berry-bush", "fern-cluster", "tall-reeds", "red-mushrooms", "brown-mushrooms", "hanging-vine", "wild-herb-patch", "butterfly-flowers")),
    ("exec-2395904e-d5b2-4089-b1ff-aa392e228044.png", "stop-props", 5, 4, (
        "mossy-boulders", "fallen-log", "hollow-log", "branch-pile", "stone-footbridge", "wood-footbridge", "broken-fence", "signpost", "straight-fence", "stone-fire-ring",
        "lit-campfire", "patched-tent", "rusty-barrel", "wooden-barrel", "supply-crate", "reinforced-crate", "closed-travel-chest", "old-stone-well", "weathered-gravestone", "loose-stones")),
    ("exec-d137d931-0c06-4b0b-88c1-d016d95eebeb.png", "stop-wildlife", 4, 3, (
        "gray-rabbit", "brown-rabbit", "young-deer", "adult-deer", "sparrow", "crow", "owl", "blue-butterfly", "orange-butterfly", "small-lizard", "field-mouse", "perched-songbird")),
)


def remove_magenta(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, _ = pixels[x, y]
            if r > 200 and b > 185 and g < 75:
                pixels[x, y] = (r, g, b, 0)
            else:
                if r > g * 2.2 and b > g * 2.0:
                    r = b = max(g, 12)
                pixels[x, y] = (r, g, b, 255)
    return image


for source_name, folder, columns, rows, names in SETS:
    source = remove_magenta(Image.open(GENERATED / source_name))
    output = ROOT / "assets" / "sprites" / folder
    output.mkdir(parents=True, exist_ok=True)
    source.save(output / (Path(source_name).stem + "-atlas.png"), optimize=True)
    x_edges = [round(source.width * i / columns) for i in range(columns + 1)]
    y_edges = [round(source.height * i / rows) for i in range(rows + 1)]
    for index, name in enumerate(names):
        column, row = index % columns, index // columns
        cell = source.crop((x_edges[column], y_edges[row], x_edges[column + 1], y_edges[row + 1]))
        bounds = cell.getchannel("A").getbbox()
        if not bounds:
            continue
        subject = cell.crop(bounds)
        canvas_size = 320 if folder != "stop-wildlife" else 256
        maximum = canvas_size - 24
        scale = min(maximum / subject.width, maximum / subject.height)
        subject = subject.resize((max(1, round(subject.width * scale)), max(1, round(subject.height * scale))), Image.Resampling.NEAREST)
        sprite = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
        sprite.alpha_composite(subject, ((canvas_size - subject.width) // 2, canvas_size - 10 - subject.height))
        destination = output / f"{name}.png"
        sprite.save(destination, optimize=True)
        print(destination.relative_to(ROOT))
