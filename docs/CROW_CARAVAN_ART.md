# Rookery Caravan art

The campsite uses authored raster sprites for its background, wagons, wheels,
stalls, tents, cargo, merchants, entrance banner and fire. The campsite renderer
does not construct scenery, fallback characters or ground shadows from shapes.
Text panels and interaction indicators remain UI drawing. Missing required
artwork raises an asset error rather than substituting a procedural object.

## Runtime files

- `assets/backgrounds/crow-caravan-campsite-v1.png`
- `assets/sprites/caravans/rookery/wagon-body-v1.png`
- `assets/sprites/caravans/rookery/wagon-wheel-v1.png`
- `assets/sprites/caravans/rookery/merchant-stall-body-v2.png`
- `assets/sprites/caravans/rookery/animations/merchant-stall-breeze-4-v1.png`
- `assets/sprites/caravans/rookery/patched-tent-v1.png`
- `assets/sprites/caravans/rookery/cargo-cluster-v1.png`
- `assets/sprites/caravans/rookery/crow-banner-v1.png`
- `assets/sprites/caravans/rookery/animations/campfire-idle-4-v1.png`

The original `merchant-stall-v1.png` remains as the approved art reference;
it is not the runtime stall. Merchants retain their existing crow animation set.

## Attachment and animation

`game/crow_caravan_art.lua` describes the cloth's source rectangles and pins.
The sheet contains four authored poses, each split into canopy and front drape.
It is a packed sheet, not an equal-cell grid: the third canopy extends into the
spare gutter beside pose four. Its rectangle owns that feather; pose four starts
after it. Do not replace these rectangles with an automatic grid slicer.

`game/crow_caravan_area.lua` maps each cloth piece's two source pins onto fixed
attachment points on the 1536 x 1024 stall body. The canopy attaches at
(300,130) and (1210,200); the counter drape attaches at (595,656) and (865,656).
The body and goods never change frames. Two cap regions from the same body
sprite render above the cloth so the brass finials stay visible.

The calm breeze uses poses 1,2,4,2 at two poses per second, with offsets between
stalls. Pose three is the stronger gust and is excluded from the idle loop.
Reduced Motion freezes the cloth and fire on their first poses and stops the
entrance banner's sway. Animation consists of sampling saved sprite frames;
there is no runtime fabric mesh, noise texture, particle fire or generated art.

Wagon wheels use the body artwork's axle sockets (462,828) and (1175,815), with
wheel hub (625,617) in the 1254 x 1254 wheel source. The parts share a single
normalized transform. The wheels render over the near-side sockets and remain
stationary while parked. Source-relative anchors survive mobile resizing.

## Mobile and verification

Mobile packaging resizes the eight cloth regions independently, preserving
their positions and avoiding bleed from the neighboring pose. Runtime source
rectangles and packaging rectangles have a parity check. The optimized cloth
is 768 x 512; the fire is 768 x 256 with four frames.

Verified on 2026-09-10:

- Focused area checks pass, including explicit missing-art failure.
- Desktop smoke: 88 checkpoints passed.
- Mobile-mode smoke: 96 checkpoints passed, nine required art components loaded,
  no asset failures, warnings or errors.
- Seven mobile packaging tests pass, including transparency, isolated source
  regions and runtime-manifest parity.
- Inspected desktop and optimized-mobile scene captures and close-up breeze
  poses. Post caps, goods, barrel base and lower wooden base retain identical
  pixels across the idle poses; moving cloth naturally changes its occlusion.
- All 40 captured Reduced Motion frames are identical.

One repeated desktop run timed out in the separate audio-priority check. A
fresh sequential run passed all 88 checkpoints; no audio code was changed.
The confirmed report is `.stabilization/smoke-caravan-sprite-final-confirmed.rpt`.

The preview tool supports `CARAVAN_PREVIEW_MODE=cloth` or `animation` for a
complete two-second loop, and uses the game's nearest filtering. Setting
`CARAVAN_PREVIEW_ASSET_ROOT` to an optimized asset directory checks packaged
images with the same runtime renderer. Preview capture is not art generation.

## Image-generation prompt set

The new fabric artwork was created with built-in ImageGen. The approved stall
was the visual reference. These were the production briefs:

1. Fixed body: remove only the flexible canopy, hanging cloth, tassels and crow
   feathers; retain the wooden posts, brass fittings, counter, shelves, lanterns
   and goods on the original 1536 x 1024 canvas with genuine transparency.
2. Cloth animation: create only the burgundy/plum patched canopy, gold hems and
   tassels, purple feathers, side banner and diamond-emblem counter cloth.
   Four poses show rest, a right breeze, a stronger gust and settling, while
   preserving tied corners. Keep all wood, posts, goods and lanterns out of the
   overlay and retain transparent gaps between its parts.
3. Alpha extraction: "Remove the checkerboard background from this sprite
   sheet. Make the background actually transparent (PNG alpha channel),
   including holes between the fabric pieces. Keep the four frames and artwork
   exactly unchanged. Use transparent-background output, not an illustration
   of checkerboard transparency."

Rejected opaque/checkerboard outputs and full-stall frames with moving wood
are not runtime assets. Runtime attachment corrections are sprite placements
described above; they do not synthesize or paint replacement artwork.
