# Character motion semantic acceptance gate

`character_motion_acceptance_gate.py` is the final project-local gate for a
directional character overhaul. It complements, but does not replace, the
structural sprite-motion audit. Pixel differences alone are never treated as
proof of a valid walk.

## Workflow

1. Build the reviewed runtime strips and run the strict motion audit and sprite
   doctor into `output/character-motion/<character>/audit` and
   `output/character-motion/<character>/sprite-doctor`.
2. Record prompt provenance in
   `output/character-motion/<character>/source/prompt-provenance.json`.
3. Prepare the visual-review evidence:

   ```powershell
   python tools/character_motion_acceptance_gate.py character-motion/<character>.json --prepare-review
   ```

   This creates 1x walk GIFs, half-speed walk GIFs, four half-cycle comparison
   sheets per unique walk, and `semantic-review-template.json`. A prepare run can
   reject the art while still producing useful inspection material.
4. Copy the template to `semantic-review.json`. Inspect every listed contact
   sheet and animation, set a checkbox to `true` only after observing it, and
   write direction-specific notes. Do not reuse an older review after changing
   art: every evidence item is bound to its SHA-256 hash.
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

## Prompt provenance schema

Prompt provenance is JSON rather than a prose summary. Every source image used
by the build manifest must appear in an artifact list.

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

## Matte and checkerboard rejection

Every gait frame is examined independently. A large alpha bounding box that is
at least 97% opaque-filled is rejected as a rectangular matte or baked
checkerboard, regardless of color variation. This catches opaque checkerboards
that ordinary transparency and duplicate-frame checks can mistake for valid
art.
