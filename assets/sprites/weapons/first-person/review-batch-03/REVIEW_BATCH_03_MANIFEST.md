# First-Person Ranged Weapons — Review Batch 03

Review-only state sprites for the hunting bow, critter crossbow, and trail slingshot. Nothing in this batch is wired into runtime code.

## Generation mode and references

- Mode: built-in `image_gen` tool, one call per state.
- Identity references:
  - `assets/sprites/weapons/hunting-bow.png`
  - `assets/sprites/weapons/critter-crossbow.png`
  - `assets/sprites/weapons/trail-slingshot.png`
- Hunting-bow first-person perspective references supplied by the user:
  - `references/weaponRef/user-photos/hunting-bow-perspective/outdoor-right-edge-bow-reference.png`
  - `references/weaponRef/user-photos/hunting-bow-perspective/gameplay-bow-hand-reference.png`
  - `references/weaponRef/user-photos/hunting-bow-perspective/draw-hand-string-reference.png`
- Shared prompt foundation: first-person game sprite; preserve the referenced subject's exact wood, wrapping, string/band, metal, pouch, projectile, palette, and crisp square-pixel identity; use plausible stored tension and deformation; keep every required part and projectile inside the canvas with padding; request genuine transparent alpha; exclude text, UI, reticles, shadows, extra props, modern redesigns, and cropped or duplicated geometry.
- Bow-specific player-visibility rule: the hunting bow uses both hands and forearms to establish a readable first-person draw. Both hands are fully gloved and both arms are clothing-covered to the canvas edges; no skin, fur, scales, feathers, claws, paw pads, or other species-specific anatomy may be visible. The firearm no-hands rule is unchanged.
- State-specific prompt set:
  - Hunting bow: relaxed low-ready without arrow; arrow nocked at brace height; half draw with two taut string segments meeting the nock; full draw with the arrow path on canvas center; post-release string/limb return with no arrow.
  - Critter crossbow: unloaded low-ready; unloaded uncocked/forward string; cocked empty string captured at the brass latch; loaded rear rail aim with the bolt on canvas center; post-release forward string with no bolt.
  - Trail slingshot: relaxed empty low-ready; stone seated in pouch under light tension; full draw with symmetric bands and projectile path on canvas center; post-release empty pouch/band return.

## Selected files

| Weapon | State | File | Pixel format | Review status |
| --- | --- | --- | --- | --- |
| Hunting bow | Low ready | — | — | Pending derivation from an approved full-draw master; v1/v2 floating side-icon attempts rejected |
| Hunting bow | Arrow nocked | — | — | Pending derivation from an approved full-draw master; v1/v2 floating side-icon attempts rejected |
| Hunting bow | Partial draw | — | — | Pending derivation from an approved full-draw master; v1/v2 floating side-icon attempts rejected |
| Hunting bow | Full draw / aim | `hunting-bow-full-draw-aim-v4.png` | RGB with baked checkerboard | Perspective proof: true right-handed view, fully gloved hands, fully covered sleeves, bow on right, centered arrow, and two string segments meeting at the draw hand/nock; review-only until user approval and genuine alpha |
| Hunting bow | Release / string return | — | — | Pending derivation from an approved full-draw master; v1/v2 floating side-icon attempts rejected |
| Critter crossbow | Low ready | `critter-crossbow-low-ready-v1.png` | RGBA | Candidate |
| Critter crossbow | Uncocked | `critter-crossbow-uncocked-v1.png` | RGBA | Candidate |
| Critter crossbow | Cocked empty | `critter-crossbow-cocked-v2.png` | RGB with baked checkerboard | Mechanically improved targeted retry; transparency failed |
| Critter crossbow | Bolt-loaded aim | `critter-crossbow-bolt-loaded-aim-v1.png` | RGBA | Candidate; bolt/rail centered |
| Critter crossbow | Release | `critter-crossbow-release-v1.png` | RGBA | Candidate |
| Trail slingshot | Relaxed low ready | `trail-slingshot-low-ready-v1.png` | RGB with baked checkerboard | Transparency failed |
| Trail slingshot | Loaded | `trail-slingshot-loaded-v1.png` | RGBA | Candidate |
| Trail slingshot | Full draw / aim | `trail-slingshot-full-draw-aim-v1.png` | RGB with baked checkerboard | Needs visual review: readable centered path, but the first-person depth is shallow; transparency failed |
| Trail slingshot | Release / band return | `trail-slingshot-release-band-return-v1.png` | RGBA | Candidate |

`review-batch-03-contact-sheet.png` is now historical for the hunting-bow row. The crossbow and trail-slingshot rows remain current.

## QC and retry record

- All selected RGBA files retain the built-in output alpha unchanged and have nonzero transparent padding on every edge.
- The three RGB/checkerboard files above are the untouched built-in outputs. No code-generated transparency cleanup was applied.
- All five v1 hunting-bow states and the v2 floating-bow experiment were rejected because their camera, scale and bow/string geometry changed between states or flattened into side icons.
- The user supplied first-person archery compositions as perspective authority. `hunting-bow-full-draw-aim-v3.png` established the successful right-side first-person framing but exposed human skin and contained extra string branches, so it is superseded.
- `hunting-bow-full-draw-aim-v4.png` applies the universal-animal-player rule with full gloves and covered sleeves and removes the extra string branches. It remains review-only because the built-in generator returned opaque RGB checkerboard pixels.
- Critter-crossbow cocked received one targeted retry to replace a diagonal/crossing string with a center-latch path. The retry is selected, but it returned flattened checkerboard RGB.
- Trail-slingshot full draw received one targeted perspective retry. It cropped the bottom of the handle, so the complete first candidate is retained and flagged for review.
- No state received more than one targeted retry.

## Production promotion status — 2026-08-30

The selected crossbow and trail-slingshot states, plus the user-approved hunting-bow v4 full-draw master, were promoted to unversioned production files. No other bow state was approved or promoted. Across all four batches, production contains **103 sprites**: **39 firearm pairs** plus **25 special states**. Runtime views are loaded lazily, and `review-batch-*` folders are excluded from mobile packaging. ADS data now comprises **41 calibrated anchors**, **4 provisional anchors**, and no boomerang ADS anchor. Android deployment remains deferred, and the connected device was not touched.
