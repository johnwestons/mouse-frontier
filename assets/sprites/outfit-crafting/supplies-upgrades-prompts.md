# Sewing supplies, tools, and upgrade sprite provenance

These assets were authored with the built-in `image_gen.imagegen` tool. No code-generated illustrations, background removal, resampling, or repacking was applied. Generated PNG files were copied unchanged into this directory. The original generated files remain under the Codex generated-images directory.

## Delivered atlases

| File | PNG dimensions | Layout | Source cell size |
| --- | --- | --- | --- |
| `supplies-tools-v1.png` | 1122 × 1402 RGBA | 4 columns × 5 rows | 280 × 280 pixels |
| `upgrades-v1.png` | 1254 × 1254 RGBA | 3 columns × 3 rows | 418 × 418 pixels |

The supplies atlas grid occupies `(0,0,1120,1400)`. Its final two columns and two rows are completely transparent unused canvas padding. Slice using **280**, not PNG width divided by four. Upgrade cells fill their canvas exactly.

Both files have genuine alpha (range 0–255). Fully transparent pixels occupy approximately 77.8% of the supplies atlas and 69.4% of the upgrade atlas. Inspection confirmed the item order, separated silhouettes, and safe padding around the cell boundaries. Tool working ends generally point lower-left. The artwork contains no hands, characters, labels, or full garments.

### Supplies and tools cell order

Rows and columns below are one-based; sprite coordinates start at zero.

| Row | Column 1 | Column 2 | Column 3 | Column 4 |
| --- | --- | --- | --- | --- |
| 1 | thread-spool | fabric-scraps | canvas-bundle | wool-batting |
| 2 | leather-pieces | metal-sheet | waxed-thread | chalk |
| 3 | scissors | pins | needle | awl |
| 4 | hand-snips | file | punch-and-mallet | clips |
| 5 | two-needles | sewing-kit | pocket-tool-roll | thread-loop |

### Upgrade cell order

| Row | Column 1 | Column 2 | Column 3 |
| --- | --- | --- | --- |
| 1 | cloth-repair-patch | quilted-wool-lining | padded-cloth-insert |
| 2 | canvas-reinforcement | mobility-gusset | leather-padding-insert |
| 3 | leather-reinforcement | quilted-weather-lining | segmented-metal-insert |

Quality variants share their recipe's authored sprite.

## Reference inputs

- `assets/sprites/items/sewing-kit.png`: existing inventory object's pixel-art style.
- `assets/concepts/wearables/sewing-bench-minigame.png`: approved concept's material palette and sewing context.

Both references were visually inspected before generation. Every image-generation call used `transparent_background=true`.

## Selected generated source files

- Supplies final: `C:/Users/johnw/.codex/generated_images/01a0fd05-9277-79a1-9816-6ec20c8ac65c/exec-2bfa8525-0b1f-48d5-b01a-7871e8435c75.png`
- Upgrades final: `C:/Users/johnw/.codex/generated_images/01a0fd05-9277-79a1-9816-6ec20c8ac65c/exec-f745acc0-db35-4d8e-91a3-97bc75d0b847.png`

## Standalone metalworking corrections

These authored PNGs override two atlas tool cells without changing the original atlas. Both were generated with the built-in image tool using `supplies-tools-v1.png` as their style reference and `transparent_background=true`, then copied unchanged.

| File | Dimensions | Replaces | Inspection |
| --- | --- | --- | --- |
| `metal-file-v1.png` | 1254 × 1254 RGBA | `file` (row 4, column 2) | Broad steel face with crosshatched abrasive teeth, blunt rounded terminal end, brown wooden handle; alpha range 0–255, 85.5% fully transparent. |
| `metal-punch-mallet-v1.png` | 1254 × 1254 RGBA | `punch-and-mallet` (row 4, column 3) | Straight cylindrical steel punch beside wooden mallet and backing block; no rotary pliers; alpha range 0–255, 74.4% fully transparent. |

Source files:
- `C:/Users/johnw/.codex/generated_images/01a0fd05-9277-79a1-9816-6ec20c8ac65c/exec-db920045-74d0-46f5-973f-cf7389d28aac.png`
- `C:/Users/johnw/.codex/generated_images/01a0fd05-9277-79a1-9816-6ec20c8ac65c/exec-21054d37-41b5-45be-a77e-1c50b9514138.png`

### Exact file replacement prompt

```text
Use case: stylized-concept.
Asset type: one finished transparent 2D tool sprite for Mouse Frontier's sewing and metalworking minigame.
Input image: the attached supplies atlas is a STYLE REFERENCE ONLY. Match its warm detailed pixel art, dark crisp pixel outlines, brown wooden tool handles and worn steel.
Primary request: ONE actual flat metalworking HAND FILE, displayed diagonally with its brown bulb-shaped wooden handle at upper-right and its flat steel working end pointing lower-left. The entire steel file face must show unmistakable coarse CROSSHATCHED ABRASIVE TEETH: alternating dark and bright diagonal scored ridges crossing each other in a regular diamond pattern. Make the teeth boldly readable at small game-icon scale. Use a thick, broad rectangular steel file body with a rounded BLUNT terminal end; the end has NO sharpened bevel, NO cutting edge, and NO point. Include a narrow neck and small brass ferrule where the rough steel file meets the brown wood handle. Show its broad toothed face from a slight three-quarter top-down view. This is a hand file, NOT a chisel, knife, saw, awl or screwdriver.
Composition: one object only, centered on a square canvas, entire object contained within central seventy percent of the image with at least15percent transparent padding all sides. Desired image768x768. No loose accessories.
Style: visibly authored pixel art, visible square pixel clusters, richly shaded worn walnut wood grain, gray steel with readable abrasive teeth, restrained brass highlight, warm light upper-left. Cohesive with supplied reference.
Transparency: genuinely transparent alpha background, opaque object interior, clean outline. No black/white/checkerboard matte, background, floor, drop shadow, text, frame, border, hands, body parts or watermark.
```

### Exact punch and mallet replacement prompt

```text
Use case: stylized-concept.
Asset type: one finished transparent 2D tool-group sprite for Mouse Frontier's sewing and thin-metal crafting minigame.
Input image: the attached supplies atlas is a STYLE REFERENCE ONLY for warm detailed pixel art, brown wooden handles, gray metal, and crisp dark outlines.
Primary request: a STRAIGHT cylindrical steel HOLE PUNCH, a small wooden MALLET, and a small dark solid BACKING BLOCK grouped together as one clear icon. The punch is a simple straight narrow steel shaft with a flat striking cap at its upper end and a short narrow round cutting tip at its bottom, standing almost upright with a slight diagonal tilt. It rests by the small dark backing block, which supports the work beneath it. The wooden mallet is beside it, showing a stout cylindrical wooden head and a shorter wooden handle at a diagonal. Keep the steel punch completely visible and clearly separate from the mallet. The tool combination represents making fastening holes in thin sheet metal. This is a straight punch struck with a mallet, with NO rotary punch wheel, NO plier jaws, NO leather punch pliers, NO scissors, NO drill, NO claw hammer. Do not include a metal sheet or extra tools.
Composition: one compact balanced three-object group centered in a square canvas, within the central70percent of the image with at least15percent fully transparent padding on every side. Desired768x768. Warm light upper-left and slightly top-down view, consistent with atlas.
Style: authored warm frontier PIXEL ART with visible square pixel clusters, rich wood grain, worn steel highlights, dark outlines and tactile material details. Match supplied inventory art, no vector shapes and no photorealism.
Transparency: genuine transparent alpha everywhere outside tool silhouettes. Opaque object interiors, no black/white/checkerboard matte, no floor or background or drop shadow. No hands, bodies, people, text, numbers, frames or watermark.
```


## Exact prompt history

The requested dimensions were generation guidance. The actual delivered dimensions and slicing rules above are authoritative.

### Supplies: initial generation

Input: Both reference inputs listed above.

```text
Use case: stylized-concept.
Asset type: production 2D game sprite atlas for Mouse Frontier's sewing minigame.
Input images: image 1 is a STYLE REFERENCE ONLY, the existing warm pixel-art sewing kit. Image 2 is a STYLE REFERENCE ONLY for the sewing bench's material palette. Create a new atlas, do not copy the interface or backdrop.
Primary request: exactly TWENTY standalone illustrated supply and tool sprites in a rigid invisible 4-COLUMN by 5-ROW grid on a genuinely transparent RGBA canvas, desired canvas 1024 pixels wide by 1280 pixels high; twenty equal SQUARE cells, 256 by 256 pixels each. No drawn grid.
Composition: each object is centered in its own exact cell with at least 12 percent fully transparent padding on every side, the longest dimension no more than 76 percent of a cell. All twenty cells populated exactly once. Keep clear fully transparent gutters; no object, thread end or shadow may cross into another cell. Similar visual weight, consistent warm light from upper-left. Tool tips point diagonally LOWER LEFT, handles generally upper-right, and tools have no hands or body parts.
Exact cell order, left to right within each row:
ROW 1: (1) one wooden spool of rust-orange sewing thread; (2) loose folded olive and cream fabric scraps tied as a small bundle; (3) thick tan canvas folded bundle with obvious coarse weave; (4) soft off-white loose wool batting gathered into a bundle.
ROW 2: (1) irregular brown supple leather offcuts; (2) two thin flat steel sheet offcuts, clearly sheet not bars or ingots; (3) dark ochre waxed thread spool with slight wax sheen; (4) one ivory wedge of tailor's chalk with its pointed writing corner aimed lower-left.
ROW 3: (1) brass-and-steel tailor scissors, pointed blade tips lower-left; (2) a small cluster of straight sewing pins with colored heads upper-right and pointed ends lower-left; (3) one long steel sewing needle with a visible eye at upper-right and point lower-left; (4) one leatherworker's wooden-handled awl with pointed steel shaft lower-left.
ROW 4: (1) short sturdy sheet-metal hand snips with dark handles upper-right, short steel cutting blades lower-left; (2) one textured metal file with wooden handle upper-right and working tip lower-left; (3) one small steel hole punch paired with a wooden mallet, both wholly contained within this cell; (4) two small brass binder-style sewing clips, clearly clips with jaws.
ROW 5: (1) a matched pair of steel saddle-stitching needles angled toward lower-left, connected by one tidy short piece of thread; (2) a small open wooden sewing kit box with spools and folded cloth matching reference 1; (3) a rolled olive canvas tool pouch partly open to show wooden handles; (4) one loose rust-orange sewing-thread loop with a small knot and two short tails, no needle.
Style: detailed crisp warm frontier pixel art, visible square pixel clusters, rich wood grain, woven cloth, stitched leather, bright steel edges, clean dark pixel outlines. Match the reference's crafted inventory art, not flat symbols, not vector art, not photorealism, not a 3D render. Entirely separate actual object silhouettes.
Transparency: output must contain genuine transparent alpha in all empty space, including gutters. No black, white, beige, checkerboard, paper, or colored background. No background shadows or floor. No labels, text, numbers, frames, borders, characters or watermarks.
```

### Supplies: spacing revision

Input: Initial generated supplies atlas: exec-6c01ad4a-8eb0-458c-853a-1ede703afc19.png.

```text
Use case: precise-object-edit. Edit the attached SUPPLIES AND TOOLS atlas. Keep all twenty exact illustrated objects, their warm pixel-art style, colors, row-major order, and their orientations. Change ONLY their scale and spacing: every object must become significantly smaller and be centered at its correct grid cell center with abundant empty transparent space.
Output an exact 4 columns x 5 rows UNIFORM GRID of equal square cells, aspect ratio4:5. Requested canvas1280x1600 with 320px square cells. The desired cell centers are x=160,480,800,1120 crossed with y=160,480,800,1120,1440. In every cell, the entire sprite silhouette including tails must fit inside the central 176x176 box (55 percent of cell side); make even the scissors, needle, and two-needle tool fully fit. All objects must be fully within their own cell. The outer border and gutters are TRANSPARENT ALPHA, not drawn lines. Retain actual transparent background. Objects themselves substantially opaque, clean edges without colored halos or loose noise.
Exact row-major order to preserve:
row1 orange thread spool; cloth scraps bundle; tan canvas bundle; cream wool batting.
row2 brown leather pieces; thin metal sheets; ochre waxed thread spool; triangular tailor chalk.
row3 scissors; pins; one needle; awl.
row4 hand snips; metal file; hole punch plus mallet; pair of brass clips.
row5 two needles connected by short thread; open sewing kit; tool roll; loose thread loop.
No labels, numbers, grid lines, frames, background panels, new objects, bodies or hands. This is an engineering correction to sprite atlas registration and padding, not a redesign. Preserve the supplied art.
```

### Supplies: final aspect and spacing revision

Input: Spacing revision: exec-c098e507-de13-4067-bf8f-542b353f2fe1.png.

```text
Edit the supplied twenty-object sewing sprite sheet to correct ONLY canvas aspect ratio and grid registration. Required final image aspect ratio is exactly FOUR TO FIVE (width80%height): a 4-column by5-row array of SQUARE cells. Use a1024-wide by1280-high transparent canvas. Do not make a tall1000x1568 or2:3 canvas. Keep the SAME twenty original pixel-art object illustrations and their existing order; no redesign.
Reposition and scale original objects into a true equal-pitch square lattice: columns centered at normalized x=.125,.375,.625,.875; rows centered at normalized y=.1,.3,.5,.7,.9. Horizontal and vertical center-to-center distances must be IDENTICAL in pixels. All twenty cells same square256px size. Each object's entire silhouette should fit within 160x160px, centered within each256px square. Leave generous transparent gutters. Crop no object. This is a regular sprite atlas, not an artistic layout.
Read row by row, exact order remains:
orange thread spool, fabric scraps, tan canvas bundle, wool batting;
brown leather pieces, thin metal sheets, ochre waxed thread, tailor chalk;
scissors, straight pins, steel needle, wooden awl;
metal hand snips, steel file, hole punch with mallet, sewing clips;
two connected needles, open sewing kit, canvas tool roll, orange thread loop.
Genuinely transparent RGBA background, no opaque black, no colored matte, no shadows, no text, no lines or grid. Preserve the authored detail and opaque object interiors. Make the output image visibly the4:5 shape requested, with equal square grid pitch.
```

### Upgrades: initial generation

Input: Both reference inputs listed above.

```text
Use case: stylized-concept.
Asset type: production 2D clothing-upgrade item sprite atlas for Mouse Frontier.
Input images: image 1 is a STYLE REFERENCE ONLY for warm richly shaded pixel art inventory objects. Image 2 is a STYLE REFERENCE ONLY for cloth texture and sewing bench palette. Create a new sprite atlas.
Primary request: exactly NINE individual finished outfit modifications in a rigid invisible 3-COLUMN by 3-ROW grid on a genuinely transparent RGBA square canvas, desired 1536 by 1536 pixels, nine equal square cells 512 by 512 pixels. No drawn grid. These are small sewn panels and inserts for a character's existing clothes, NOT full garments or character outfits.
Composition: each complete object centered in its exact cell and fitting within at most 76 percent of its square cell, at least 12 percent fully transparent padding all around. Clear transparent gutters. All nine cell centers aligned; nothing can cross cells. Mostly front or near-top-down view with a little visible thickness, warm light upper-left.
Exact row-major order:
ROW 1: (1) CLOTH REPAIR PATCH: a small simple olive cloth square with turned-under edges and a neat visible cream backstitched border; (2) QUILTED WOOL LINING: a soft cream and ochre small rectangular wool-filled lining, visible puffy stitched channels and neatly bound fabric edge; (3) PADDED CLOTH INSERT: a muted blue-gray rectangular layered cloth pad with dense parallel quilting and a dark wrapped border, visually denser and flatter than the wool lining.
ROW 2: (1) CANVAS REINFORCEMENT: two sturdy tan canvas rectangles sewn together as one thick reinforcement panel, contrasting cream double stitched edge and coarse weave; (2) MOBILITY GUSSET: a distinct DIAMOND-shaped olive flexible cloth inset with clean turned edges and stitched diamond border, pointed top and bottom and clearly unlike a square patch; (3) LEATHER PADDING INSERT: a warm chestnut leather panel sewn onto a visible cream padded fabric backing, rounded corners, saddle-stitched perimeter.
ROW 3: (1) LEATHER REINFORCEMENT: a dark brown tough leather reinforcement patch mounted on ochre canvas, visible two-needle saddle stitching around its inset margin, flatter and darker than the padded leather insert; (2) QUILTED WEATHER LINING: a more elaborate olive-gray and cream quilted lining panel, closely spaced narrow flexible channels, fabric binding, sturdy layered thickness; (3) SEGMENTED METAL INSERT: several small overlapping worn gray steel segments securely laced onto a dark canvas padded carrier, rounded smooth plate corners and small fastening holes, ivory cushion backing visible at the edge, one small folded-back fabric corner revealing construction.
Style: detailed crisp warm frontier PIXEL ART, visible square pixel clusters, tactile fabric weave, authentic stitched thread, supple leather grain, restrained metal highlights. Match reference inventory art. Cohesive silhouettes readable as small items. No photorealism, no vector pictograms, no smooth cartoon rendering.
Transparency: genuinely transparent alpha everywhere outside each item's own silhouette, including all outer padding and gutters. No background, no floor, no drop shadows, no paper squares, no checkerboard pattern. Do not draw clothing, shirts, coats, armor vests, humanoids, bodies, hands, mannequins, needles or loose tools. No text, labels, numbers, stars, rarity marks, borders, frames or watermarks.
```

### Upgrades: final spacing revision

Input: Initial generated upgrades atlas: exec-c82e9cd9-d96c-4dea-9663-5b1f856e8a71.png.

```text
Use case: precise-object-edit. Edit the attached NINE UPGRADE PANELS atlas. Preserve all nine individual illustrated panels exactly: same pixel-art detail, colors, silhouettes, stitches, materials and row-major order. Change ONLY registration, scale and padding. Keep the canvas perfectly SQUARE, requested1536x1536 pixels. Divide it into 3 equal columns by3 equal rows, each cell512x512. Center each item at x256,768,1280 and y256,768,1280. Reduce every sprite to fit fully inside the central 282x282pixels (55percent of each cell side), including every edge, thread or backing. This will leave very large entirely transparent gutters between items. Every silhouette must be isolated safely inside its cell. Preserve genuine transparent alpha in the background, with substantially opaque objects and clean pixel edges. No colored edge halos or stray noise. No grid, numbers, labels, frames, shadows or added objects.
Row1: olive cloth repair patch; cream quilted wool lining; blue-gray padded cloth insert.
Row2: tan canvas reinforcement; olive DIAMOND mobility gusset; chestnut leather padding insert.
Row3: dark leather reinforcement on canvas; olive quilted weather lining; segmented gray metal insert on padded cloth.
This is a spacing correction, not a redesign.
```

