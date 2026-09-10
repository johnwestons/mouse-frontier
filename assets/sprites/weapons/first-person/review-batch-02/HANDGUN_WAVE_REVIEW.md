# First-Person Handgun Wave Review

> First-pass generation record. Final selected filenames and corrected ADS versions are authoritative in `REVIEW_BATCH_02_MASTER.md`.

Generated with the built-in image-generation workflow. Existing inventory sprites supplied weapon identity and finish; the accepted Batch 01 SR22P/J-22/Model 81 views supplied the hip and ADS camera standards.

## Selected files

| Project ID | Real-world basis | Hip / low-ready | ADS |
| --- | --- | --- | --- |
| `frontier-32-pocket-pistol` | Mauser HSc | `frontier-32-pocket-pistol-hip-v1.png` | `frontier-32-pocket-pistol-sights-v2.png` |
| `frontier-380-pocket-pistol` | Walther PPK, short six-round frame | `frontier-380-pocket-pistol-hip-v1.png` | `frontier-380-pocket-pistol-sights-v2.png` |
| `frontier-pearl-pocket-pistol` | Engraved Astra Model 202 Firecat CE | `frontier-pearl-pocket-pistol-hip-v1.png` | `frontier-pearl-pocket-pistol-sights-v2.png` |
| `frontier-silver-compact-pistol` | Phoenix Arms HP22/HP22A, standard short barrel | `frontier-silver-compact-pistol-hip-v2.png` | `frontier-silver-compact-pistol-sights-v3.png` |
| `frontier-compact-9mm-pistol` | Ruger LCP II | `frontier-compact-9mm-pistol-hip-v2.png` | `frontier-compact-9mm-pistol-sights-v3.png` |
| `frontier-45-1911` | M1911 Government / 1911A1 | `frontier-45-1911-hip-v1.png` | `frontier-45-1911-sights-v1.png` |
| `frontier-9mm-service-pistol` | Beretta 92FS, slide forward/in battery | `frontier-9mm-service-pistol-hip-v2.png` | `frontier-9mm-service-pistol-sights-v1.png` |
| `frontier-9mm-glock` | Glock 17 Gen3 | `frontier-9mm-glock-hip-v1.png` | `frontier-9mm-glock-sights-v1.png` |
| `frontier-22-target-pistol` | Ruger Mark IV Target / Standard family | `frontier-22-target-pistol-hip-approved.png` | `frontier-22-target-pistol-sights-v1.png` |

## Final prompt set

Hip prompt structure:

- Mechanically accurate named firearm using the existing side sprite for finish and identity.
- Natural first-person three-quarter low-ready angle, grip nearer the lower-right and muzzle receding upper-left.
- No hands or arms; the complete muzzle, sights, trigger guard, grip, and magazine base remain inside the canvas.
- Crisp project-compatible pixel art with stepped contours and clustered shading.

ADS prompt structure:

- True straight rear shooter-eye view with strong foreshortening, never a long top-down diagram.
- The distant front post is visibly nested inside the closest rear notch with equal light and level tops.
- Front-post tip is the point of aim on the image centerline; no reticle is drawn.
- Entire grip and base remain visible below the sight picture.
- Model-specific actions, controls, and sight types remain mechanically authentic.

## QA notes

- The first ADS attempts for the five compact pistols used separated top-down sights and were rejected. The selected `v2` files are the corrected nested-sight versions.
- The original HP22 five-inch interpretation, SCCY interpretation, and locked-open Beretta hip view were rejected after user review. The selected versions above follow the compact base sprites and keep the Beretta slide forward/in battery.
- The built-in generator repeatedly baked the pale checkerboard into RGB despite explicit transparent-alpha instructions. These remain visual-review candidates until an approved background-extraction pass is completed.
- No runtime wiring or production-asset replacement was performed.
