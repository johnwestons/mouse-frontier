# ADS edge-case corrections

> User review established that this base sprite is a Colt Woodsman, not a Browning Buck Mark. All three Buck Mark ADS attempts and the separated-sight Woodsman v4 are superseded. `frontier-long-22-target-pistol-sights-v5.png` is the corrected nested-sight Woodsman candidate; see `REVIEW_BATCH_02_MASTER.md`.

Two review-only ADS candidates were corrected with the built-in image-generation editor. Neither runtime asset was overwritten or wired into gameplay.

Review sheet: `ads-edgecase-corrections-review.png`

## Strict results

| Weapon | Previous candidate | New candidate | Sight geometry | Identity / framing | PNG alpha | Overall promotion status |
| --- | --- | --- | --- | --- | --- | --- |
| Henry H001L-inspired `weathered-lever-rifle` | `weathered-lever-rifle-sights-v3.png` | `weathered-lever-rifle-sights-v4.png` | **PASS** — exactly one open rear notch and one amber bead centered inside it; the second stacked notch is gone; no sight or barrel projects beyond the combined sight picture. | **PASS** — complete buttstock and buttplate, black receiver, reddish stock, tan wraps, and large loop remain visible and centered; no hands or crop. | **FAIL** — generated file is 1024×1536 `Format24bppRgb` with an opaque pale checkerboard. | **REVIEW ONLY / DO NOT PROMOTE** until a genuine-alpha image-generation pass succeeds. |
| Colt Woodsman long-barrel `frontier-long-22-target-pistol` | Buck Mark `v1`–`v3` family | `frontier-long-22-target-pistol-sights-v4.png` | Corrected identity target: one Woodsman rear notch and front blade on a centered axis. | Preserve the Woodsman's thin fixed round barrel, compact receiver and raked grip; no Buck Mark bull barrel or top rib. | Pending corrected-file alpha audit. | **REVIEW ONLY / DO NOT PROMOTE** until visual and alpha QA pass. |

## Inputs and authority

### Weathered Henry H001L

- Edit target: `weathered-lever-rifle-sights-v3.png`
- Weapon identity / finish authority: `weathered-lever-rifle-hip-v1.png`
- Approved sight-picture grammar reference: Batch 01 `frontier-22-lever-rifle-sights-v4.png`
- Donor platform authority: `references/weaponRef/FIREARM_REFERENCE_CATALOG.md` — Henry H001L Classic Large Loop, open rear and hoodless front bead.

### Long Colt Woodsman target pistol

- Edit target: `frontier-long-22-target-pistol-sights-v1.png`
- Corrected identity / finish authority: `assets/sprites/weapons/frontier-long-22-target-pistol.png`
- Original inventory identity authority: `assets/sprites/weapons/frontier-long-22-target-pistol.png`
- Approved pistol sight-picture grammar reference: Batch 01 `frontier-sr22-pistol-sights-v2.png`
- Donor platform authority: `references/weaponRef/FIREARM_REFERENCE_CATALOG.md` — Colt Woodsman long-barrel Target / Match Target family.

## Final prompt set

### `weathered-lever-rifle-sights-v4.png`

Precise-object edit of v3: preserve the entire weathered Henry H001L-style rifle, its pixel-art style, centered rear-ADS perspective, wraps, large loop, full stock, and buttplate. Keep only the upper black open U-notch and exactly one amber/brass bead centered inside it. Delete the second smaller U/V sight stacked below and rebuild that area as continuous receiver/barrel metal. Nothing may protrude above or beyond the single combined sight picture. No hands, crop, redesign, text, or watermark; request genuine transparent alpha.

### Superseded Buck Mark prompt (`v1`–`v3`)

Historical only. This prompt used the wrong Browning Buck Mark donor and must not be reused. The corrected pass uses the Colt Woodsman's thin fixed round barrel, compact receiver, raked grip, and model-appropriate open sights.

## Generation accounting

- Mode: built-in image-generation editor.
- Calls used: one targeted edit per asset.
- Additional correction calls: none. Both requested sight-geometry repairs passed on the first edit; a second generation was not spent on the known checkerboard/alpha limitation.
- No scripted or deterministic image cleanup was applied to either generated candidate.
