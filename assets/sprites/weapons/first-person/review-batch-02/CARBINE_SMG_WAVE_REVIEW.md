# Carbine, 5.56 Rifle, and SMG First-Person Review

> First-pass generation record. Final selected filenames and corrected ADS versions are authoritative in `REVIEW_BATCH_02_MASTER.md`.

Generated with the built-in image-generation workflow. These are review-only candidates; nothing in the runtime has been wired or replaced.

Review sheet: `carbine-smg-wave-review.png`

## Selected candidates

| Game asset | Real-world geometry anchor | Hip / low-ready | Rear ADS | Review notes |
| --- | --- | --- | --- | --- |
| `compact-carbine` | Colt Model 733 / Commando | `compact-carbine-hip-v1.png` | `compact-carbine-sights-v2.png` | Short barrel, fixed carry handle, A-frame front sight, compact CAR stock, short 5.56 magazine, and stock wrap preserved. ADS is centered on the bore axis. |
| `frontier-556-carbine` | Colt M4/M4A1 | `frontier-556-carbine-hip-v1.png` | `frontier-556-carbine-sights-v1.png` | Clean M4-family geometry with A2 tower, rear aperture, collapsible stock, and short 5.56 magazine. |
| `improvised-556-rifle` | Patched M4/M4A1 | `improvised-556-rifle-hip-v1.png` | `improvised-556-rifle-sights-v1.png` | Wood, cloth, tape, rust, and repair plate preserved without covering the ejection port, controls, trigger, magazine well, or stock adjustment. |
| `improvised-service-rifle` | 5.56 AK using AK-101 / Zastava M90 logic | `improvised-service-rifle-hip-v1.png` | `improvised-service-rifle-sights-v1.png` | Coherent AK gas system and receiver, fixed wood stock, tangent rear notch, protected front post, and visibly less-curved 5.56 magazine. |
| `frontier-9mm-smg` | Full-size HK MP5 with A1-style stockless endcap | `frontier-9mm-smg-hip-v1.png` | `frontier-9mm-smg-sights-v1.png` | Full receiver/cocking-tube length, no MP5K shortening, no shoulder stock, curved magazine, rotary diopter, hooded front post, and complete rear endcap. |

## Source identity references

- `compact-carbine`: `references/weaponRef/source-crops/firearms-v1-compact-carbine.png`, cropped non-destructively from the bottom-row third cell of `assets/sprites/atlases/firearms-v1.png`.
- `improvised-service-rifle`: `references/weaponRef/source-crops/firearms-v1-improvised-service-rifle.png`, cropped non-destructively from the bottom-row second cell of the same atlas.
- `frontier-556-carbine`: `assets/sprites/weapons/frontier-556-carbine.png`.
- `improvised-556-rifle`: `assets/sprites/weapons/improvised-556-rifle.png`.
- `frontier-9mm-smg`: `assets/sprites/weapons/frontier-9mm-smg.png`.
- Approved perspective standards: the Batch 01 Marlin hip/ADS pair, plus the Batch 02 M1 Carbine aperture and SKS open-sight ADS examples.

## Final prompt set

Every generation used this shared brief:

- One complete weapon rendered as crisp, high-detail, project-compatible pixel art.
- Hip view: believable rear three-quarter first-person low-ready perspective, with the muzzle receding toward the upper left and the complete rear assembly toward the lower right.
- ADS view: straight rear shooter-eye view with bore, receiver, stock or endcap, and sights on one vertical centerline.
- Full muzzle, sights, receiver, grip, magazine, and stock/endcap remain inside the canvas with clear padding.
- No hands, arms, sling, optic, ammunition, muzzle flash, smoke, text, logo, watermark, extra weapon, detached parts, or cropping.
- Genuine transparent alpha requested explicitly; no baked checkerboard requested.

Weapon-specific prompt locks:

- **Compact carbine:** Colt 733/Commando short barrel, fixed carry-handle aperture, A-frame front post, CAR stock, short 5.56 magazine, and tan wrap only on the stock.
- **Frontier 5.56 carbine:** clean M4/M4A1, flat-top rear aperture, A2 front tower/post, centered buffer tube and full collapsible stock.
- **Improvised 5.56 rifle:** repaired M4 mechanics; wraps and splints stay off the ejection port, charging handle, selector, trigger, magazine well, and stock adjustment.
- **Improvised service rifle:** AK-101/Zastava M90 5.56 logic, tangent notch/protected post, coherent gas system, and a distinctly less-curved 5.56 magazine.
- **Frontier 9mm SMG:** full-size stockless MP5 rather than MP5K, rotary rear diopter, hooded post, curved 30-round magazine, and complete A1-style endcap with no stock rails.

## QA and transparency status

- All ten selected candidates have complete uncropped silhouettes and preserve the required platform identities.
- The hip views keep stock, receiver, barrel, and muzzle on coherent axes.
- The ADS views keep the rear sight, front sight, bore, receiver, and butt/endcap centered horizontally and preserve each platform's correct sight family.
- The built-in generator returned the selected files as RGB images with baked white/gray checkerboards despite the explicit alpha request.
- `compact-carbine-sights-v1.png` initially contained an alpha channel but also a broad dark semi-transparent halo. One permitted background-extraction retry removed the visible halo but returned the selected `compact-carbine-sights-v2.png` as another RGB checkerboard.
- No code-based transparency cleanup was performed. These assets are suitable for visual review but are not runtime-ready until transparency is resolved through the approved image workflow.
