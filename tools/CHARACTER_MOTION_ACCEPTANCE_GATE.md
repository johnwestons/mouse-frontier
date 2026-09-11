# Character motion semantic acceptance gate

`character_motion_acceptance_gate.py` is the final project-local gate for a
directional character overhaul. It complements, but does not replace, the
structural sprite-motion audit. Pixel differences alone are never treated as
proof of a valid walk.

## Workflow

1. Build the reviewed runtime strips and run the strict motion audit and sprite
   doctor into `output/character-motion/<character>/audit` and
   `output/character-motion/<character>/sprite-doctor`.
   Sprite doctor can inspect staged strips before installation:

   ```powershell
   python tools/character_sprite_doctor.py audit <character> --animation-root output/character-motion --animation-subdirectory runtime --locomotion-only --build-manifest character-motion/<character>-build.json --report output/character-motion/<character>/sprite-doctor/report.json --contact-sheets output/character-motion/<character>/sprite-doctor
   ```

   These options apply only to the read-only audit command. Without them,
   sprite doctor still inspects installed character directories and all actions.
   Staged contact sheets show every selected locomotion action and all eight
   walk frames.
2. Record prompt provenance in
   `output/character-motion/<character>/source/prompt-provenance.json`.
3. Prepare the visual-review evidence:

   ```powershell
   python tools/character_motion_acceptance_gate.py character-motion/<character>.json --prepare-review
   ```

   This creates 1x walk GIFs, half-speed walk GIFs, four half-cycle comparison
   sheets per unique walk, and `semantic-review-template.json`. A prepare run can
   reject the art while still producing useful inspection material.
   `prepared` means inspection material exists; it never means the character is
   accepted. The existing review is not updated by preparation.
4. Copy the template to `semantic-review.json`. Inspect every listed contact
   sheet and animation, set a checkbox to `true` only after observing it, and
   write direction-specific notes. Do not reuse an older review after changing
   art: every evidence item is bound to its SHA-256 hash.
   The template also binds the full-resolution staged strips, motion
   specification, and build manifest. Changing sprite pixels, direction or
   mirror mappings, source phase order, or build instructions requires a fresh
   review. Old templates without these bindings are intentionally rejected.
5. Run the final gate:

   ```powershell
   python tools/character_motion_acceptance_gate.py character-motion/<character>.json
   ```

The final report is written beneath that character at
`acceptance-gate/report.json`. Acceptance evidence and reports cannot point
outside `output/character-motion/<character>`.

## Per-frame scale policy

Per-frame corrections may normalize authored size uniformly by at most 5% in
either direction (`0.95` through `1.05`). The effective x/y scale may differ by
at most `0.005` to allow harmless decimal rounding. One-axis scaling, larger
uniform scaling, stretching, shearing, rotation, and forced width/height changes
are rejected. A frame outside those limits must be re-authored.

A single-frame replacement may have a different source resolution than its
atlas. `resolution_normalization: "match_base_visible_height"` measures both
cleaned images and uniformly matches the original cell height. This resolution
conversion is allowed even when the ratio exceeds 5%; it does not authorize a
different body size. Explicit `reviewed_visible_height` values are checked
against measured source height, and their effective body correction is combined
with ordinary frame adjustments before applying the same 5% limit. Splitting a
7% enlargement between these two fields does not make it acceptable.

## Prompt provenance schema

Prompt provenance is JSON rather than a prose summary. Every source image used
by the build manifest must appear in an artifact list.
This includes every string or structured `frame_sources` replacement, not just
the base walk and idle atlases.

```json
{
  "version": 1,
  "character": "example-mouse",
  "records": [
    {
      "id": "walk-cardinals-v2",
      "capture": "exact",
      "capture_source": "Exported image-generation call 2026-09-09T04:12:00-04:00",
      "prompt_text": "The exact complete prompt goes here.",
      "artifacts": [
        {
          "path": "output/character-motion/example-mouse/source/walk-cardinals-v2-reviewed.png",
          "sha256": "<64 lowercase hexadecimal characters>"
        }
      ]
    },
    {
      "id": "idle-study-v1-reconstruction",
      "capture": "reconstructed",
      "prompt_text": "The best faithful reconstruction goes here.",
      "reconstruction_notes": "The original tool-call text was not retained; reconstructed from the request and output, so this is not verbatim.",
      "artifacts": [
        {
          "path": "output/character-motion/example-mouse/source/idle-study-v1-reviewed.png",
          "sha256": "<64 lowercase hexadecimal characters>"
        }
      ]
    }
  ]
}
```

`capture` must be exactly `exact` or `reconstructed`. Exact records require a
traceable `capture_source`. Reconstructed records require candid
`reconstruction_notes` and may not set or claim `verbatim`, `is_verbatim`, or
`exact_prompt`.

## Required directional review

The generated review template contains all eight directions. Each direction
must retain the motion-spec walk and idle names, hash-bound evidence, a nonempty
note, and these explicit observations:

- `walk_phase_order_valid`
- `alternating_foot_contacts_valid`
- `idle_matches_walk`
- `identity_preserved`
- `asymmetry_preserved`
- `reviewed_at_1x`
- `reviewed_at_half_speed`

The gate also requires `status: "accepted"`, a reviewer, ISO review date,
overall notes, a strict-clean motion-audit report, and no sprite-doctor error or
warning attached to an idle/walk action.

Before preparation and final acceptance, the gate compares the shared motion
audit's per-frame alpha measurements and contact-sheet sprite panels against
the current staged strips. A stale report or contact sheet cannot be rebound
merely by copying its current hash into a new template. The shared auditor's
192px panel format is checked without its font-dependent header.

Sprite doctor records `audited_inputs` with the character, action,
project-relative path, and SHA-256 of each file it inspected. It reports an
error if a file changes during inspection, and never labels virtual repair
pixels as inspected file bytes. Final acceptance requires one matching input
record for every locomotion strip. The input may be its staged path or the
character's installed path, but its hash must match the current staged bytes.
Older reports without input hashes must be regenerated before acceptance.

## Explicit sprite-doctor framing

`--build-manifest` uses the builder's declared frame size, visible-height target,
baseline, and per-output `horizontal_anchor`. With `core`, the doctor measures
the same dominant torso anchor as the builder instead of assuming that the
bounding box, including tails and equipment, must be centered. The report
retains every measured anchor, baseline, height, outer width, and core width.
The manifest path, exact file hash, and effective per-action contracts are
recorded; final acceptance verifies them against the current build manifest.

Adjacent size comparisons retain the existing outer-width/height trigger and
10% warning threshold. Under an explicit core contract, a width-only alert with
stable torso support is retained as measured `pose_extent_change` information.
Core-support width cannot independently trigger a resize warning: a one-pixel
threshold gap can disconnect a bag from the selected run without changing body
size. Such isolated run changes are retained as measured
`core_support_topology_change` information. Outer-size alerts with corresponding
core changes, and all height alerts, remain warnings. Absolute height tolerances, palette checks,
identity checks, clipping checks, and all other warning thresholds are
unchanged. Without a build manifest, legacy bounding-box/extent checks remain
unchanged. Contracted framing problems require rebuilding with the declared
builder contract; they are not labelled repairable by the doctor's legacy
bounding-box normalization.

## Explicit motion-audit center contract

`tools/sprite_motion_audit.py` is the project-local auditor. Its default
`audit.center_metric: "bbox"` retains the upstream bounding-box checks and
preview pixels. A build that explicitly anchors every locomotion strip to the
body core can opt into `audit.center_metric: "core"` with `alpha_threshold: 16`.
Run it before preparing the review:

```powershell
python tools/sprite_motion_audit.py character-motion/<character>.json --output output/character-motion/<character>/audit --strict
```

Core mode measures the same dominant torso anchor as the builder on the actual
resized raster. Both core and outer-outline positions remain in each report.
The existing center-jitter tolerance is unchanged: actual core drift still
warns; changing tail/limb outline extent with stable core is informational.
Final acceptance independently recomputes both arrays and the tolerance,
rejects stale measurements, and requires the build and every action override
to agree on core anchoring. This includes the legacy idle fallback. Unknown
center modes or incompatible alpha thresholds fail before writing artifacts.

The builder remeasures the core after pixel resampling before integer placement;
it does not project the source anchor through a resize. This prevents one-pixel
anchor rounding errors without changing cropped artwork or relaxing limits.

## Opt-in background-connected magenta fringe cleanup

The directional builder accepts `remove_edge_connected_magenta_fringe: true`
inside `framing`, an idle source set, or a walk source definition. The source
setting overrides the framing default. The default is `false`; omitting it
retains the established runtime pixels for every other character.

When enabled for reviewed magenta-backed source art, the existing approved hard
magenta matte rule runs unchanged, followed by clearing dark magenta/purple
candidates connected through matching pixels to the removed matte, existing
transparency, or the outside image boundary. Dark candidates require both red
and blue at least 64, green at most 96, at least 48 levels of red/blue chroma above
green, and red/blue difference at most 64. Four-neighbor connectivity cannot jump
across a one-pixel subject outline. Black, blue, orange, and enclosed dark
magenta that survives the existing matte rule remain intact. The new pass does
not replace or broaden the existing hard-magenta rule. It is mechanical
background removal; source images are never overwritten.

The build report records the effective option plus per-frame
`magenta_matte_and_fringe_removed_pixels` (legacy matte plus connected fringe cleared)
and `edge_connected_magenta_fringe_removed_pixels` (additional dark fringe
beyond the legacy matte-color rule). Replacement-image height normalization
and its acceptance check use the same cleanup option. Rebuild and visually
inspect the resulting edges, anchors, and contact sheets before acceptance;
isolated protected colors are not globally erased to force a clean count.

## Matte and checkerboard rejection

Every gait frame is examined independently. A large alpha bounding box that is
at least 97% opaque-filled is rejected as a rectangular matte or baked
checkerboard, regardless of color variation. This catches opaque checkerboards
that ordinary transparency and duplicate-frame checks can mistake for valid
art.
