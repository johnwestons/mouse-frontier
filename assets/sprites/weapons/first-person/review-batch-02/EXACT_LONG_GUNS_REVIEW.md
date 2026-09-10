# Exact long-gun first-person review

> First-pass generation record. Final selected filenames and corrected ADS versions are authoritative in `REVIEW_BATCH_02_MASTER.md`.

Generated with the built-in image-generation tool. Each pair used the existing side sprite as the weapon identity/finish reference and the approved Marlin 39A pair from `review-batch-01` as the composition standard.

| Game asset | Real-world anchor | Hip / low-ready | Rear ADS | Geometry and sight QA |
| --- | --- | --- | --- | --- |
| `frontier-lever-rifle` | Henry H004 Golden Boy | `frontier-lever-rifle-hip-v1.png` | `frontier-lever-rifle-sights-v1.png` | Full brass-and-walnut rifle; straight stock; centered open rear notch and front bead. |
| `wood-stock-survival-carbine` | U.S. M1 Carbine | `wood-stock-survival-carbine-hip-v1.png` | `wood-stock-survival-carbine-sights-v1.png` | Compact walnut carbine with short box magazine; centered rear aperture/front post axis. |
| `vintage-bolt-action-rifle` | Karabiner 98k | `vintage-bolt-action-rifle-hip-v1.png` | `vintage-bolt-action-rifle-sights-v1.png` | Full military stock and right-side turned-down bolt; centered rear V-notch and hooded front post. |
| `frontier-12g-pump-shotgun` | Remington 870 Fieldmaster Fully Rifled Deer / slug-gun configuration | `frontier-12g-pump-shotgun-hip-v1.png` | `frontier-12g-pump-shotgun-sights-v2.png` | Base sprite keeps its adjustable open rear and ramped front blade. The rejected v1 overhead/bead-only view is superseded by a true rear-shoulder stock/receiver/barrel axis. |
| `frontier-762-carbine` | Soviet-pattern SKS | `frontier-762-carbine-hip-v1.png` | `frontier-762-carbine-sights-v1.png` | Reddish wood, fixed magazine, gas system and hooded front post; centered tangent rear V-notch/front-post axis. |

## Shared prompt constraints

- One complete weapon, including buttplate and muzzle, fully inside the canvas.
- Hip view: mechanically coherent rear three-quarter first-person perspective.
- ADS view: straight bore-axis rear perspective, sights and stock on the image centerline.
- Crisp project-compatible pixel art; no hands, arms, text, logo, watermark, muzzle flash, smoke, or extra props.
- Requested genuine transparent alpha and no baked checkerboard.

## Transparency status

The built-in generator returned the selected candidates as RGB images with a baked white/gray checkerboard despite the transparency constraint. Targeted built-in background-extraction retries for the M1 hip view and Kar98k ADS view also returned RGB checkerboards. Geometry and identity are ready for visual review, but this set is **not runtime-ready** until transparency is resolved through the approved image-generation workflow.
