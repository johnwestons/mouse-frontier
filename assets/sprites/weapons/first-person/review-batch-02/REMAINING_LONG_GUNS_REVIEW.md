# Remaining long-gun first-person review

> First-pass generation record. Final selected filenames and corrected ADS versions are authoritative in `REVIEW_BATCH_02_MASTER.md`.

Generated with the built-in image-generation tool. These are visual review candidates only; they are not wired into runtime.

Each pair used the existing inventory sprite as the finish/decorative authority and the approved Batch 01 Marlin 39A pair as the first-person framing standard. Real firearm anatomy and sight geometry follow `references/weaponRef/FIREARM_REFERENCE_CATALOG.md`.

| Game asset | Locked physical platform | Hip / low-ready | Rear ADS | Geometry and sight QA |
| --- | --- | --- | --- | --- |
| `weathered-lever-rifle` | Henry H001L Classic Large Loop | `weathered-lever-rifle-hip-v1.png` | `weathered-lever-rifle-sights-v1.png` | Black side-eject receiver, large loop beneath wrist, barrel/tube pair, full straight stock, open rear and hoodless front bead. Distinct from the brass H004 Golden Boy. |
| `patched-22-survival-rifle` | Ruger 10/22 Carbine | `patched-22-survival-rifle-hip-v2.png` | `patched-22-survival-rifle-sights-v3.png` | One-piece patched stock, short receiver, right-side charging handle/ejection port, barrel band and flush rotary-magazine area. No tube magazine. |
| `frontier-ak-compact` | AKS-74U | `frontier-ak-compact-hip-v2.png` | `frontier-ak-compact-sights-v4.png` | Coherent AKS-74U with short booster/front end, laminated handguards, top-cover rear sight and triangular left side-folder. Game caliber remains stale metadata; no Zastava M92 or underfolder geometry. |
| `frontier-single-shot-hunter` | H&R/NEF Sportster / Handi-Rifle | `frontier-single-shot-hunter-hip-v1.png` | `frontier-single-shot-hunter-sights-v1.png` | Exactly one barrel, separate short fore-end, break-action breech/hinge, external hammer, normal trigger guard, open rear/front blade. No tube magazine or lever. |
| `frontier-lever-carbine` | Winchester 1892 / Rossi R92 large-loop carbine | `frontier-lever-carbine-hip-v1.png` | `frontier-lever-carbine-sights-v1.png` | Compact black-steel Model 1892-pattern carbine, large loop below wrist, tube below short barrel, semi-buckhorn rear/front bead. `.30 Carbine` remains gameplay abstraction. |

## Shared final prompt rules

- One complete weapon, including buttplate/stock and muzzle, fully inside a tall canvas with deliberate padding.
- Hip view: mechanically coherent rear three-quarter first-person low-ready perspective; butt near lower right and muzzle toward upper left.
- ADS view: straight rear bore-axis perspective; butt, wrist, receiver, barrel, and both sights centered; front post centered in the rear notch with equal side clearance and correct height relationship.
- Crisp hand-authored pixel-art finish matching the approved Batch 01 long-gun pair.
- No hands, arms, optics, reticle, text, logo, watermark, muzzle flash, smoke, ammunition, props, or scenery.
- Requested genuine transparent alpha with no checkerboard baked into the pixels.

## Targeted corrections used

- `frontier-ak-compact` hip and ADS: the M92/underfolder interpretation was rejected and rebuilt as an AKS-74U with a triangular side-folder; the ADS magazine and pistol grip are hidden edge-on behind the centered receiver.
- `frontier-single-shot-hunter` hip: removed a false under-barrel tube, leaving one barrel and a short separate fore-end.
- `frontier-single-shot-hunter` ADS: removed an inherited lever-loop fragment and restored the break-action trigger-guard/hinge silhouette.

No additional retry was used for the other six selected variants.

## Transparency status

All ten selected PNGs are RGB/color-type 2 files (`Format24bppRgb`) with a baked white/gray checkerboard, despite explicit requests for genuine transparent alpha. The raw built-in outputs are retained unchanged as requested; no scripted/code cleanup was performed. Geometry and identity are ready for visual review, but these files are **not runtime-ready** until transparency is resolved through an approved image workflow.

## Review scope

- Selected images are stored non-destructively in this directory.
- No existing first-person asset was overwritten.
- No runtime tables, weapon mappings, UI, or gameplay code were changed.
