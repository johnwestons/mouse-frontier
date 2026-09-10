# Character sprite workflow

For eight-direction locomotion upgrades, start with
`character-motion/README.md`. The directional runtime is opt-in by complete
asset set, so the legacy rules below continue to apply to characters that have
not yet been upgraded.

`character_sprite_doctor.py` is the single entry point for checking, repairing, and importing character animation art. It understands the game’s actual runtime contract and the project’s established source formats.

## Canonical runtime format

Every frame uses a transparent 512×512 RGBA cell. Visible art is centered at x=256, has a target maximum extent of 385 pixels, and rests on baseline y=458.

| Action | Frames | Requirement |
| --- | ---: | --- |
| idle | 2 | required |
| walk | 6 modern / 3 legacy | required |
| sit | 2 | required |
| lay | 2 | required |
| melee | 3 | required |
| ranged | 3 | required |
| use | 3 | required |
| hit | 3 | required |
| unconscious | 2 | recommended |
| death | 3 | recommended |

A set containing `unconscious.png` is modern, so its walk sheet must contain six frames. A set without unconscious art retains the runtime-compatible three-frame walk layout.

## Fast, safe repair workflow

Audit one complete character and render a visual QA sheet:

```powershell
python tools/character_sprite_doctor.py audit gecko-mechanic --contact-sheets output/sprite-audits
```

Preview every safe repair without changing game assets:

```powershell
python tools/character_sprite_doctor.py repair gecko-mechanic --contact-sheets
```

The preview, post-repair audit, and JSON report are written under `output/sprite-doctor/<timestamp>/`. Review the contact sheet, then apply the same operation:

```powershell
python tools/character_sprite_doctor.py repair gecko-mechanic --apply --contact-sheets
```

Every replaced PNG is copied first to `output/sprite-doctor/backups/<timestamp>/`. New files do not overwrite source atlases.

To inspect the entire library:

```powershell
python tools/character_sprite_doctor.py audit --report output/sprite-doctor/full-audit.json
```

To make missing death sheets fail the audit instead of producing recommendations, add `--require-death`.

For a faster crop/scale-only pass that skips palette identity matching, add `--geometry-only` to `audit` or `repair`.

## Creating or replacing sprites

### Complete 6×4 atlas

The supported master-atlas layout is:

```text
row 1: idle 1, idle 2, sit 1, sit 2, lay 1, lay 2
row 2: walk 1, walk 2, walk 3, death 1, death 2, death 3
row 3: melee 1–3, ranged 1–3
row 4: use 1–3, hit 1–3
```

Preview an import:

```powershell
python tools/character_sprite_doctor.py import-atlas CHARACTER path/to/master.png --contact-sheet
```

Install it after review:

```powershell
python tools/character_sprite_doctor.py import-atlas CHARACTER path/to/master.png --apply --reviewed-contact-sheet
```

If the character already has unconscious art, the three authored walk poses are expanded into the established six-frame forward/back loop. The master is retained as `complete-transparent-source.png` when applied.

### One action strip

Generated horizontal strips can be processed independently:

```powershell
python tools/character_sprite_doctor.py import-action CHARACTER melee path/to/melee.png --contact-sheet
python tools/character_sprite_doctor.py import-action CHARACTER melee path/to/melee.png --apply --reviewed-contact-sheet
```

Imports always write a contact sheet. `--apply` is rejected until `--reviewed-contact-sheet` explicitly confirms that the preview was inspected; a clean geometry audit is not visual approval. Use `--source-frames N` when the source panel count is not the action’s final frame count. Green-screen removal only follows green pixels connected to the image edge, which protects green costume details.

## Weapon attachment points

The doctor can estimate the character's weapon hand in every melee and ranged frame and generate the attachment list used by the game:

```powershell
python tools/character_sprite_doctor.py weapon-anchors
```

The default output is `game/weapon_attachment_points.lua`. Commit that generated file whenever attack sprites change so desktop and mobile builds use the same hand placement. The export is deterministic: characters are sorted, melee precedes ranged, and normalized coordinates and confidence values use fixed precision.

For a visual review and a machine-readable report, run:

```powershell
python tools/character_sprite_doctor.py weapon-anchors --contact-sheets output/sprite-doctor/weapon-anchors --report output/sprite-doctor/weapon-anchors.json
```

Each contact sheet draws a yellow crosshair on the detected hand and a cyan line toward the side where the weapon should extend. The JSON report lists every normalized `x`/`y` point, `side` (`-1` left or `1` right), and confidence score. Detection is silhouette-based, so visually inspect unusual poses and every low-confidence marker before treating it as final art direction.

If a reviewed marker needs correction, record only that frame in `tools/weapon_attachment_overrides.json` instead of editing generated Lua. For example:

```json
{
  "scout-mouse": {
    "melee": [
      {"frame": 2, "x": 0.625, "y": 0.375, "side": -1}
    ]
  }
}
```

The next generation or check applies the correction with full confidence. The doctor rejects unknown characters, actions, frame numbers, out-of-cell coordinates, and invalid sides. Use `--overrides path/to/reviewed.json` only when validating an alternate correction set.

To update only named characters, put their directory names after the command:

```powershell
python tools/character_sprite_doctor.py weapon-anchors scout-mouse mechanic-mouse
```

Because a partial run replaces the output with only those named characters, use the no-name form before committing the complete runtime list. To verify that the committed list still matches all attack sprites without rewriting it:

```powershell
python tools/character_sprite_doctor.py weapon-anchors --check
```

The check exits unsuccessfully when `game/weapon_attachment_points.lua` is missing or stale, making it suitable for automated verification. Runtime attachment data has this stable shape:

```lua
points["scout-mouse.png"].melee[1] = {
  x = 0.7421,
  y = 0.4813,
  side = 1,
  confidence = 0.912,
}
```

Coordinates are normalized within the character's 512×512 action cell, so placement remains correct when the animation is scaled for battle or world rendering.

## What the doctor detects

- wrong sheet dimensions or frame counts;
- empty or edge-clipped frames;
- bad crops, faint alpha residue, frame-boundary bleed, and suspicious detached fragments;
- mismatched visible scale, horizontal center, and foot baseline;
- unusual top-bound variation and substantial components entering from panel boundaries;
- abrupt adjacent-frame scale, palette, silhouette, and within-action identity drift;
- exact duplicate frames, low effective motion, and unusually harsh idle/walk loop seams;
- missing required and recommended actions;
- action art whose palette identity strongly matches another character.

Geometry repairs are automatic because they do not alter the meaning of a pose. Missing sheets are rebuilt automatically only from a same-character action source or master atlas. If no trustworthy source exists, the report says that new authored art is needed rather than copying an idle pose and calling it complete.

Connected-component analysis runs on every frame even when all basic geometry passes. An edge-clipped frame can be reframed, but pixels already lost outside the source cannot be reconstructed. Those repairs are marked medium-confidence and remain on the review list. Detached opaque components are reported rather than deleted automatically because they may be an intentional spark, weapon, or dropped accessory.

Identity assignment is audit-only by default. `repair --identity-swaps` permits only reciprocal high-confidence swaps, where two characters’ matching action sheets clearly belong to each other. One-way identity mistakes remain flagged for authored replacement.

## Verification

Run the focused test suite after changing the tool:

```powershell
python -m unittest tools.tests.test_character_sprite_doctor -v
```

The tests cover crop/scale repair, alpha residue and detached fragments, source-backed missing-sheet recovery, modern versus legacy walk counts, guarded identity swaps, backup-before-replace behavior, hand-marker detection, detached-fleck rejection, reviewed anchor overrides, deterministic Lua export, and stale attachment-list checks.
