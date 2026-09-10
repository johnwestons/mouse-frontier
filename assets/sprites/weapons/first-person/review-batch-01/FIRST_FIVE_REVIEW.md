# First-Person Weapon Review — Batch 01

Generated with the built-in image-generation workflow as grounded pixel-art review candidates. Each weapon has a hip/low-ready view and a true rear ADS view, with no hands and the complete weapon kept inside the canvas.

## Selected candidates

| Weapon | Hip / low-ready | Aim down sights | Status |
| --- | --- | --- | --- |
| Marlin Model 39A | `frontier-22-lever-rifle-hip-v2.png` | `frontier-22-lever-rifle-sights-v4.png` | Review candidate |
| Ruger SR22P | `frontier-sr22-pistol-hip-v1.png` | `frontier-sr22-pistol-sights-v2.png` | Locked by user |
| Jennings J-22 | `frontier-22-pocket-pistol-hip-v1.png` | `frontier-22-pocket-pistol-sights-v2.png` | Locked by user |
| Beretta Model 81 | `frontier-compact-9mm-hip-v2.png` | `frontier-compact-9mm-sights-v3.png` | Rebuilt replacement |
| Ruger Wrangler | `frontier-silver-22-revolver-hip-v1.png` | `frontier-silver-22-revolver-sights-v1.png` | Hip view locked; ADS review candidate |

Combined review sheet: `first-five-review.png`

## Shared generation brief

- Crisp, game-ready pixel art grounded in the real firearm's proportions and construction.
- Hip view uses a natural first-person three-quarter low-ready angle.
- ADS view looks straight down the bore from the shooter's eye.
- Rear notch and front post form one centered sight picture on the image centerline.
- No hands, arms, text, logos, muzzle flash, ammunition, or decorative props.
- Entire weapon remains inside the canvas, including the full grip or buttstock.
- References were used for firearm identity, geometry, sight type, materials, and perspective rather than copied as a scene.

## Superseded files

Earlier Beretta files (`frontier-compact-9mm-hip-v1.png`, `frontier-compact-9mm-sights-v1.png`, and `frontier-compact-9mm-sights-v2.png`) are rejected drafts and are not part of the selected review set.

## Production promotion status — 2026-08-30

The selected Batch 01 files were promoted to the unversioned production set. Across all four batches, production now contains **103 sprites**: **39 firearm pairs** plus **25 special states**. Runtime views are loaded lazily, while every `review-batch-*` folder is excluded from mobile packaging. The complete production summary records **41 calibrated ADS anchors**, **4 provisional anchors**, and no boomerang ADS anchor. Only the hunting-bow v4 master is approved for the bow. Android deployment remains deferred, and the connected device was not touched.
