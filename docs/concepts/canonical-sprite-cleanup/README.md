# Canonical sprite cleanup evidence

This is a read-only review of the 50 animation sheets that differed from the previous canonical PNG references. Every one of the 277 changed frames was inspected on dark and white backgrounds, with enlarged removed-region comparisons. No source or installed sprite was edited for this review.

## Result

The 26,164 removed pixels are background-connected magenta matte or dark magenta fringe. No loss of genuine skin, red clothing, carried tools, or main outline structures was observed.

| Character | Sheets | Changed frames | Removed pixels |
| --- | ---: | ---: | ---: |
| Botanist Frog | 21 | 124 | 16,624 |
| Conductor Cat | 4 | 9 | 13 |
| Cook Frog | 6 | 35 | 35 |
| Cook Mouse | 18 | 108 | 9,491 |
| Trail Fox | 1 | 1 | 1 |
| Total | 50 | 277 | 26,164 |

All removed pixels were attached to the main character component in the reference. None were detached fragments. Each is connected to transparent background through the exact cleanup color predicate: 26,145 match the hard magenta rule with blue floor 55, and 19 match the dark fringe rule. None of the removed pixels match the former hard magenta rule with blue floor 105.

Only 54 removed pixels were more than two pixels from the reference background. The deepest 16 are in Botanist Frog `run_west` frames 3 and 7: a two-pixel-thick magenta bridge in the gap between the basket bottom and foot. The maximum background depth is eight pixels. The basket outline and foot remain intact in the enlarged comparisons.

## Evidence

- The 20 character contact sheets show all changed frames. Their lower panels highlight the exact removed pixels in cyan.
- The three `deep-regions-page-*.png` sheets enlarge every changed frame containing removals deeper than two pixels. Cyan means removed; gold means removed and deeper than two.
- [Deepest Botanist Frog region, frame 3](deepest-botanist-frog-run_west-frame-03.png) and [frame 7](deepest-botanist-frog-run_west-frame-07.png) show the magenta bridge at a larger scale.
- [frame-audit.json](frame-audit.json) records all reference and installed PNG hashes, per-frame counts and bounding boxes, background-depth measurements, per-character totals, and SHA-256 hashes of the 25 retained diagnostic PNGs. Copies were checked against the generated analysis images.

Connectivity uses eight neighbors for character components and four neighbors for cleanup flooding and background depth. Foreground is alpha at least 16. Measurements describe the previous reference-to-installed differences recorded by the smoke audit; these diagnostics are evidence, not replacement sprite references.
