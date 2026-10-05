# Canonical sprite cleanup review

October 5, 2026. Follow-up to the [smoke-test audit](../SMOKE_TEST_AUDIT.md), under the user's request to fix the discovered errors and finish the tests.

## Cause and resolution

The five failing character subtests compared installed October pixels to September normalized references. The October 1 cleanup broadened the existing magenta matcher from a blue-channel minimum of 105 to 55, removing dark pink fringe left around the sprites. The reference files and fingerprints still represented the earlier output.

The correction records an explicit cleanup derivation in the canonical fingerprint contract. Original source hashes, animation specifications, timing, dimensions, and artwork remain intact. Expected installed hashes are computed from the canonical references using the existing `remove_edge_connected_magenta_fringe_pixels` function. Installed artwork is only a comparison target; it is never an input to fingerprint generation.

## Independent provenance checks

- All 144 canonical source sheets match decoded RGBA from Git commit `e13ad7f655cc1f48394e5a0e22118aab125d576a`, before the cleanup.
- All 144 installed sheets match commit `a5cee7ccdda17b79286390088031a4c91dba1a50` from October 1.
- Applying the existing cleanup function to every canonical source reproduces all 144 installed RGBA arrays exactly. There are no unexplained differences.
- The connected cleanup helper and its preservation tests were introduced in commit `258d605`; the October change broadened the hard-magenta color match. The calibrated build manifests already opt in to fringe removal.
- The preserved September semantic/installation records certify the base art. This review covers the later cleanup; it does not invent an additional historical human approval.

The complete per-sheet proof is [canonical_cleanup_review.json](../../character-motion/canonical_cleanup_review.json): original and derived RGBA hashes, dimensions, paths, removed counts, module fingerprint, and matching installed output. The review uses the original references and independent Git history rather than adopting installed pixels as the expected result.

## Pixel and visual review

| Character | Changed sheets | Changed frames | Removed pixels |
| --- | ---: | ---: | ---: |
| Botanist Frog | 21 | 124 | 16,624 |
| Conductor Cat | 4 | 9 | 13 |
| Cook Frog | 6 | 35 | 35 |
| Cook Mouse | 18 | 108 | 9,491 |
| Trail Fox | 1 | 1 | 1 |
| Total | 50 | 277 | 26,164 |

Every removed pixel is connected to transparent background through the declared four-neighbor magenta/fringe rule. Of these, 26,145 satisfy the broadened hard-magenta rule and 19 satisfy the connected dark-fringe rule. These are edge pixels attached to the main silhouette, not detached components. The cleanup clears their complete RGBA values. All surviving visible RGB values are unchanged.

Contrast contact sheets show the original over dark, installed output over white, and enlarged regions with removed pixels marked cyan. Review covers all 277 affected frames, including the 16 Botanist Frog pixels more than four pixels from the original transparent boundary. Character anatomy, outlines, cloak/apron detail, flowers, baskets, carried tools, and camera identity remain intact; the thin magenta boundary residue disappears. These are static transparency checks; earlier gait acceptance and current runtime movement tests continue to cover motion.

The reviewed contact pages are retained in [the cleanup evidence folder](../concepts/canonical-sprite-cleanup/). Detailed local numerical diagnostics remain under `.stabilization/smoke-audit/alpha-analysis/`.

## Contract safeguards

The original source fingerprint and the derived installed fingerprint are separate. The cleanup policy is pinned by a fingerprint of its module with line endings normalized, covering the matcher, connected cleanup, and alpha threshold. A different source hash or policy requires a reviewed contract update. Dimensions, all 24 actions per character, eight authored directions, and walk/run calibration remain required.

The generator is read-only by default and requires an explicit write flag. It derives from canonical reference PNGs and refuses unexpected changes to the retained source or cleanup policy. Clean-checkout regression tests need no ignored source PNGs and still compare every installed RGBA byte against the recorded output hash. An arbitrary changed alpha or RGB pixel remains a failure.

## Verification

All 13 focused generator and contract tests pass. Negative fixtures reject changed source pixels, paths, dimensions, cleanup policy/provenance, disabled per-action cleanup (including runs), swapped mode/direction mappings, restored matte pixels, missing subject pixels, and changed surviving RGB. Original reference files remain byte-for-byte intact.

An independent production check passes with every `output/` PNG read prohibited: exactly 144 installed sheets are opened, with no failures, errors, or skips. All 144 original hashes, paths, filenames and dimensions remain unchanged against Git `4847e1e`. Every derived hash and removal count matches the independently saved proof, and each actual installed RGBA hash matches its derived result.

The default read-only generator also reports an exact match for all 144 sheets. Complete seven-group validation results are recorded in the follow-up section of the [smoke-test audit](../SMOKE_TEST_AUDIT.md).
