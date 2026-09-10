# Traditional long-gun ADS correction pass

Generated with the built-in image-generation workflow. These are raw visual-review candidates only; no runtime mapping or production asset was changed.

Final contact sheet: `traditional-longguns-ads-corrections-final.png`

## Source hierarchy

- Each weapon's existing `*-hip-v1.png` candidate locked identity, finish, repairs, action, stock, and proportions.
- `review-batch-01/frontier-22-lever-rifle-sights-v4.png` supplied the accepted full-stock pixel-art framing.
- `references/weaponRef/user-photos/marlin-39a/full-ads.jpg` supplied the real shooter-eye long-gun perspective.
- `references/weaponRef/FIREARM_REFERENCE_CATALOG.md` locked each model's rear/front sight family.

## Strict visual QC

| Weapon | Final candidate | Result | Sight-picture review |
| --- | --- | --- | --- |
| Henry H004 Golden Boy | `frontier-lever-rifle-sights-v3.png` | PASS | One brass bead is centered inside the topmost semi-buckhorn/open rear; the formerly separated muzzle/post was erased. |
| U.S. M1 Carbine | `wood-stock-survival-carbine-sights-v2.png` | PASS | One protected front post is centered inside the closest rear aperture; no second post or ring. |
| Kar98k | `vintage-bolt-action-rifle-sights-v3.png` | PASS | One small front tip is nested inside the topmost rear V-notch; the separated upper structure was erased. |
| SKS-45 / Type 56 | `frontier-762-carbine-sights-v3.png` | PASS | One central front post is nested in the topmost tangent notch, approximately level with its shoulders; no separate muzzle sight remains. |
| Henry H001L Large Loop | `weathered-lever-rifle-sights-v3.png` | **FAIL** | The retry removed the long separated muzzle, but produced two stacked rear-sight-like structures. Do not promote this candidate. |
| Patched Ruger 10/22 | `patched-22-survival-rifle-sights-v3.png` | Corrected candidate | User-corrected 10/22 receiver/stock identity, one nested open sight pair, flush rotary-magazine area, and no tube magazine. |
| Winchester 1892 / Rossi R92 | `frontier-lever-carbine-sights-v2.png` | PASS | One brass front element is centered inside the topmost semi-buckhorn rear sight; no separated second sight. |

All seven retain the complete weapon and buttstock with edge padding and no hands. Six of seven now pass the strict overlap test. The one permitted targeted retry was used on the four initial failures; no further retry was made.

## Prompt set used

The initial v2 generation prompt used this shared critical operation, plus the model-specific sight family from the catalog:

> Camera is exactly behind the closest rear sight, directly on the bore/sight axis, not above the gun. The closest rear sight is large in the foreground. The single distant front post or bead must be seen through and visually nested inside that rear notch or aperture in the same screen-space location. Do not display the rear sight lower down the barrel as a separate second object. Exactly one rear sight and exactly one front aiming element. Keep the complete weapon, full stock, and buttplate visible below with padding; no hands or cropping.

The v3 edit prompt for the four failed v2 candidates used this single targeted change:

> Delete and erase the entire separated barrel, muzzle, and front-post structure protruding above the closest rear sight; replace it with background. The closest rear sight becomes the topmost weapon silhouette. The barrel is fully foreshortened behind that sight picture and does not protrude above it. Place exactly one front post or bead inside the closest rear notch or aperture. Preserve every other part of the raw v2 image and weapon identity.

Model-specific sight families were:

- Henry H004: semi-buckhorn/open rear plus brass bead.
- M1 Carbine: rear aperture plus one protected front post.
- Kar98k: tangent V-notch plus one front blade.
- SKS: tangent U/V notch plus one protected front post.
- Henry H001L: open rear plus hoodless bead.
- Ruger 10/22: open rear plus front blade, short receiver, barrel band and flush rotary-magazine geometry; never a tube magazine.
- Winchester 1892/Rossi R92: semi-buckhorn rear plus front bead/blade.

## Raw-output status

The built-in generator again returned all selected candidates as `Format24bppRgb` images with a baked pale checkerboard instead of genuine alpha, despite the transparent-background request. The raw candidates are preserved unchanged. No scripted background removal or code image editing was performed. They remain review-only and are not runtime-ready until transparency is resolved through the approved image workflow.
