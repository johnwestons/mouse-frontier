# First-Person Special Ranged Review Batch 04

Status: **review-only**. These sprites are not wired into the shooting-range runtime and no existing runtime asset was overwritten.

## Scope

This batch completes the remaining special ranged weapons:

- `wrist-braced-slingshot`: relaxed low-ready, loaded, full-draw centered aim, release/band-return
- `metal-scrap-slingshot`: relaxed low-ready, loaded, full-draw centered aim, release/band-return
- `long-hunting-slingshot`: relaxed low-ready, loaded, full-draw centered aim, release/band-return
- `scrap-boomerang`: ready/throw, flight-spin, return/approach

The slingshots intentionally contain no hands or arms. Their centered aim states place the loaded pouch/projectile on the vertical image-center launch axis through the fork gap. The boomerang intentionally has no ADS state.

## Selected review files

| Weapon | State | File | Generator transparency |
| --- | --- | --- | --- |
| Wrist-braced slingshot | Low ready | `wrist-braced-slingshot-low-ready-v1.png` | Raw RGB checkerboard |
| Wrist-braced slingshot | Loaded | `wrist-braced-slingshot-loaded-v1.png` | Genuine RGBA alpha |
| Wrist-braced slingshot | Full draw / aim | `wrist-braced-slingshot-full-draw-aim-v1.png` | Raw RGB checkerboard |
| Wrist-braced slingshot | Release / return | `wrist-braced-slingshot-release-band-return-v1.png` | Raw RGB checkerboard |
| Metal scrap slingshot | Low ready | `metal-scrap-slingshot-low-ready-v1.png` | Raw RGB checkerboard |
| Metal scrap slingshot | Loaded | `metal-scrap-slingshot-loaded-v1.png` | Raw RGB checkerboard |
| Metal scrap slingshot | Full draw / aim | `metal-scrap-slingshot-full-draw-aim-v1.png` | Raw RGB checkerboard |
| Metal scrap slingshot | Release / return | `metal-scrap-slingshot-release-band-return-v1.png` | Raw RGB checkerboard |
| Long hunting slingshot | Low ready | `long-hunting-slingshot-low-ready-v1.png` | Raw RGB checkerboard |
| Long hunting slingshot | Loaded | `long-hunting-slingshot-loaded-v1.png` | Raw RGB checkerboard |
| Long hunting slingshot | Full draw / aim | `long-hunting-slingshot-full-draw-aim-v1.png` | Raw RGB checkerboard |
| Long hunting slingshot | Release / return | `long-hunting-slingshot-release-band-return-v1.png` | Raw RGB checkerboard |
| Scrap boomerang | Ready / throw | `scrap-boomerang-ready-throw-v1.png` | Genuine RGBA alpha |
| Scrap boomerang | Flight spin | `scrap-boomerang-flight-spin-v1.png` | Raw RGB checkerboard |
| Scrap boomerang | Return / approach | `scrap-boomerang-return-approach-v1.png` | Raw RGB checkerboard |

Contact sheet: `review-batch-04-contact-sheet.png`

## Mechanical and identity decisions

### Wrist-braced slingshot

- Corrected from the source art's unbraced wooden fork into a mechanically continuous classic Wrist-Rocket-family layout.
- Uses a dark powder-coated tubular steel fork, two rear brace rods, and a real horizontal padded wrist yoke.
- Retains the project identity through olive cord wrap, reddish-orange tubular bands, brown leather pouch, weathered wood accents, and frontier wear.
- The mechanical reference was the official Saunders SR-7 product image saved at `references/saunders-sr7-official.png` from [Saunders](https://sausa.com/product/sr-7-wrist-rocket/).

### Metal scrap slingshot

- Remains a welded gray-steel Y-frame with a visible center bolt/weld plate.
- Retains wood tip caps, tan binding/bands, rust-brown leather grip and metal butt cap.
- Loaded and aim states use one polished steel ball bearing.

### Long hunting slingshot

- Remains an all-natural long hardwood handle and compact fork with visible grain/knot.
- Retains tan twine binding, unusually long olive bands and a dark leather pouch.
- Loaded and aim states use one polished steel ball bearing.
- The selected release frame is a readable post-release return moment. One targeted retry was rejected because the generator introduced impossible extra band loops; it was not selected or copied into this review set.

### Scrap boomerang

- Preserves the shallow-V two-wing construction, gray salvaged arm plates, brown/bronze reinforcement plate, exposed rivets, layered seams and worn red tip caps.
- Flight spin uses subtle motion accents without ghosting a second physical boomerang.
- Return/approach uses asymmetric foreshortening instead of a fake sight picture.

## Prompt set

Built-in image generation was used, with one call per state.

Shared prompt rules:

- polished hand-painted pixel art with crisp square pixels, clean dark outlines and restrained highlights
- isolated complete weapon centered inside the canvas with generous margin
- preserve each source weapon's materials, wear, silhouette and color identity
- no hands, arms, character, text, logo, watermark, scenery, stand, shadow plane, duplicates, detached parts or cropping
- request genuine transparent alpha and explicitly forbid a checkerboard background
- slingshot bands must stay attached from both fork tips to opposite ends of one pouch
- full-draw aim states must use symmetric real tension and center the loaded pouch/projectile on the image-center launch axis

State modifiers:

- **Low ready:** three-quarter presentation, slack bands and naturally hanging pouch.
- **Loaded:** one ammunition piece seated in the pouch, light pre-draw tension only.
- **Full draw / aim:** fork square to target, two straight equally stretched bands, pouch behind the fork in depth, strong centered foreshortening.
- **Release / return:** empty pouch after projectile departure, attached bands visibly contracting with restrained elastic oscillation.
- **Boomerang ready:** dynamic complete throwing orientation without a hand.
- **Boomerang flight:** single solid boomerang with an oblique spin angle and small curved pixel motion accents.
- **Boomerang return:** one wing larger and closer, opposite wing receding, complete V silhouette preserved.

## Transparency warning

The built-in generator returned only **2 of 15** selected files with genuine RGBA transparency. The other **13 files are RGB images with a baked light checkerboard** even though every prompt explicitly requested transparent alpha and forbade checkerboards.

Per the review-batch requirement, the raw generated results are retained as-is. No scripted checkerboard removal, alpha reconstruction, resampling cleanup or runtime conversion was performed.

## Production promotion status — 2026-08-30

All 15 selected Batch 04 special-weapon states were subsequently promoted to unversioned production files; the raw review sources and warning above remain preserved as history. Across all four batches, production contains **103 sprites**: **39 firearm pairs** plus **25 special states**. Runtime views are loaded lazily, and `review-batch-*` folders are excluded from mobile packaging. ADS data now comprises **41 calibrated anchors**, **4 provisional anchors**, and no boomerang ADS anchor. Only the hunting-bow v4 master is approved for the bow. Android deployment remains deferred, and the connected device was not touched.
