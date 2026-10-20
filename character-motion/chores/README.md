# Resident chore assets

Each motion specification preserves the character's installed idle and walking
strips and adds three stationary actions: `sweep` and `tend` at 3 fps, and
`carry` at 2 fps. Each action contains four 512 × 256 frames. The wide transparent
canvas leaves room for tools while retaining the existing character's body scale.
The carry action depicts lifting and lowering a crate; locomotion continues to
use the installed directional walk with a separate carried crate attachment.

## Build and review

Generated source atlases remain unchanged in `output/resident-chores/sources`.
The source manifest lists characters in atlas row order, with three action rows
per character and four frames per row. The builder separates actual silhouettes,
including tools and detached details, rather than assuming exact grid boundaries.
It only clears alpha values of 4/255 or less in its staging copy. Visible colors
are preserved. An opaque background, overlapping character rows, or an incomplete
body requires a replacement source. A same-atlas standing row that is much shorter
than the other standing action is rejected for review before normalization can
disguise missing legs by enlarging the remaining torso.

From the repository root, stage a selected batch with the project's Python
runtime and dependency path:

```powershell
$env:PYTHONPATH = '.;.stabilization/python-deps;tools/tests'
python tools/build_resident_chore_assets.py --manifest output/resident-chores/source-manifest.json --only character-slug another-slug --audit
```

Inspect the generated light and dark batch sheets under
`output/resident-chores/reviews`, each character's `contact-backgrounds.png`, and
the normal and half-speed GIFs under its `audit/previews` directory. Check every
pose for identity, articulation, complete tools, transparency, body scale, foot
baseline, and a coherent loop. Resolve all new action errors and review warnings.
Unchanged legacy motion findings are reported separately and remain visible.

After visual review, install the exact staged files:

```powershell
python tools/build_resident_chore_assets.py --only character-slug another-slug --install-reviewed
```

This command verifies that source files, staged strips, motion specifications,
audit reports, and contact sheets have not changed since staging. It copies only
the three reviewed action strips into the character's runtime asset directory.
It then records source and installed hashes, review evidence, action rates, and
audit findings in `acceptance.json`. Do not mark an unreviewed batch accepted.

Run the normalizer regressions with:

```powershell
python -m unittest test_resident_chore_builder -q
```

Runtime rendering and resident behavior are validated separately. Source art,
staging output, accepted runtime strips, and review evidence remain distinct.
