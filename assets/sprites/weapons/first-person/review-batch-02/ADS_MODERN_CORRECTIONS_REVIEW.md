# Modern long-gun ADS corrections

Generated with the built-in image-generation workflow. These are non-destructive visual-review candidates only; no runtime asset mapping was changed.

Review sheet: `ads-modern-corrections-review.png`

> 2026-08-30 zero-yaw addendum: user review found laterally exposed magazine and pistol-grip side profiles in several otherwise aligned ADS candidates. The files in the table below are the replacement review candidates for that specific defect. They remain review-only because the generator again flattened transparency into RGB checkerboard pixels.

| Project ID | Zero-yaw candidate | Furniture-occlusion QA |
| --- | --- | --- |
| `compact-carbine` | `compact-carbine-sights-v5.png` | Magazine and pistol grip remain edge-on beneath the receiver; no lateral slab. |
| `frontier-556-carbine` | `frontier-556-carbine-sights-v3.png` | Magazine and pistol grip remain edge-on beneath the receiver; no lateral slab. |
| `improvised-556-rifle` | `improvised-556-rifle-sights-v3.png` | Patched lower furniture remains centered and foreshortened. |
| `improvised-service-rifle` | `improvised-service-rifle-sights-v4.png` | Magazine and wrapped grip no longer project from opposite sides. |
| `frontier-9mm-smg` | `frontier-9mm-smg-sights-v4.png` | Magazine remains hidden behind the centered receiver/endcap axis. |
| `rugged-submachine-gun` | `rugged-submachine-gun-sights-v3.png` | Magazine and forward furniture no longer form a broad side profile. |
| `machine-pistol` | `machine-pistol-sights-v4.png` | Magazine remains edge-on beneath the receiver rather than yawing left. |
| `frontier-ak-compact` | `frontier-ak-compact-sights-v4.png` | Rebuilt separately as an AKS-74U; magazine and pistol grip are fully hidden behind the receiver. |

## Selected corrected candidates

| Project ID | Locked platform / sight family | Selected ADS | Sight QA |
| --- | --- | --- | --- |
| `compact-carbine` | Colt Model 733, carry-handle aperture / A2 post | `compact-carbine-sights-v4.png` | One front post inside one rear aperture; no external duplicate; complete wrapped CAR stock visible. |
| `frontier-556-carbine` | Colt M4/M4A1, rear aperture / A2 post | `frontier-556-carbine-sights-v2.png` | One centered post inside one rear aperture; clean M4 identity and complete collapsible stock. |
| `improvised-556-rifle` | Patched M4, rear aperture / A2 post | `improvised-556-rifle-sights-v2.png` | One centered post inside one rear aperture; wood, cloth and metal repairs retained without obscuring mechanics. |
| `improvised-service-rifle` | 5.56 AK / Zastava M90 logic, tangent open notch / protected post | `improvised-service-rifle-sights-v3.png` | One protected post nested in the nearest open notch; no separated sight above it; complete fixed stock visible. |
| `frontier-9mm-smg` | Full-size stockless MP5, rotary diopter / hooded post | `frontier-9mm-smg-sights-v3.png` | Large rear aperture, smaller concentric front hood and one post; no second hood; full A1 endcap and grip visible. |
| `frontier-ak-compact` | AKS-74U, top-cover rear notch / protected front post | `frontier-ak-compact-sights-v4.png` | User-corrected AKS-74U anatomy, one centered sight stack, complete triangular side-folder, and no lateral magazine/grip profile. |
| `frontier-single-shot-hunter` | H&R/NEF break-action, open notch / hoodless blade | `frontier-single-shot-hunter-sights-v3.png` | One hoodless blade nested in one open notch; one barrel/action and full wood stock remain visible. |

## Shared final prompt set

- Create one new first-person ADS sprite in a perfectly straight shooter-eye view with zero yaw or roll.
- Use the inventory sprite and existing hip candidate as the weapon-identity, materials and repair authority.
- Render exactly one nearest rear sight and exactly one physical front post or blade, wholly nested inside that rear aperture/notch with equal side clearance and correct height.
- The visible weapon terminates at the nested sight picture; do not repeat a post, hood, tower, bead or sight icon farther up the barrel.
- Preserve the platform-specific sight family: Colt aperture/A2 post, AK tangent notch/protected post, MP5 rotary diopter/concentric hooded post, or H&R open notch/hoodless blade.
- Keep the complete weapon below the sight picture, including receiver and full stock/endcap/buttplate, with clear padding and no cropping.
- Camera has exactly zero yaw and zero roll. Detachable magazine and pistol grip stay directly beneath the receiver centerline and appear edge-on with strong foreshortening. Their broad side profiles may not project left or right; preserve physical length through depth, not by splaying the parts laterally.
- Crisp project-compatible pixel art; no hands, arms, optic, reticle, sling, ammunition, muzzle flash, smoke, text, logo, watermark, extra weapon or detached parts.
- Request genuine transparent alpha with no baked checkerboard.

For the open-sight and MP5 cases, a single targeted built-in edit removed or completed only the sight picture after visual inspection; the weapon body and framing were held invariant.

## Superseded correction drafts

- `compact-carbine-sights-v3.png`: rejected because it still separated the A-frame sight above the rear aperture.
- `improvised-service-rifle-sights-v2.png`: rejected because it still placed the protected post above the nearer rear notch.
- `frontier-9mm-smg-sights-v2.png`: rejected because the post lacked the smaller nested MP5 front hood.
- `frontier-ak-compact-sights-v2.png`: rejected because it still placed the protected post above the nearer rear notch.
- `frontier-single-shot-hunter-sights-v2.png`: rejected because it still separated the front blade above the nearer rear notch.

Earlier Batch 02 ADS files remain preserved as history and are superseded by the selected versions listed above.

## Output status

- All seven selected candidates were visually inspected at full size and again on the full-view / sight-close-up review sheet.
- All selected candidates keep the complete rear stock, endcap or side-folder within the canvas and contain no hands or arms.
- All seven built-in outputs are RGB PNGs with a baked pale checkerboard despite the explicit alpha request. They are visual-review candidates, **not runtime-ready transparent sprites**.
- No scripted image cleanup, alpha extraction or runtime wiring was performed.
