# Character sprite workflow

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
python tools/character_sprite_doctor.py import-atlas CHARACTER path/to/master.png --apply --contact-sheet
```

If the character already has unconscious art, the three authored walk poses are expanded into the established six-frame forward/back loop. The master is retained as `complete-transparent-source.png` when applied.

### One action strip

Generated horizontal strips can be processed independently:

```powershell
python tools/character_sprite_doctor.py import-action CHARACTER melee path/to/melee.png --contact-sheet
python tools/character_sprite_doctor.py import-action CHARACTER melee path/to/melee.png --apply --contact-sheet
```

Use `--source-frames N` when the source panel count is not the action’s final frame count. Green-screen removal only follows green pixels connected to the image edge, which protects green costume details.

## What the doctor detects

- wrong sheet dimensions or frame counts;
- empty or edge-clipped frames;
- bad crops, faint alpha residue, frame-boundary bleed, and suspicious detached fragments;
- mismatched visible scale, horizontal center, and foot baseline;
- missing required and recommended actions;
- action art whose palette identity strongly matches another character.

Geometry repairs are automatic because they do not alter the meaning of a pose. Missing sheets are rebuilt automatically only from a same-character action source or master atlas. If no trustworthy source exists, the report says that new authored art is needed rather than copying an idle pose and calling it complete.

An edge-clipped frame can be reframed, but pixels already lost outside the source cannot be reconstructed. Those repairs are marked medium-confidence and remain on the review list. Small detached opaque components are also reported rather than deleted automatically because they may be an intentional spark, weapon, or dropped accessory.

Identity assignment is audit-only by default. `repair --identity-swaps` permits only reciprocal high-confidence swaps, where two characters’ matching action sheets clearly belong to each other. One-way identity mistakes remain flagged for authored replacement.

## Verification

Run the focused test suite after changing the tool:

```powershell
python -m unittest tools.tests.test_character_sprite_doctor -v
```

The tests cover crop/scale repair, alpha residue and detached fragments, source-backed missing-sheet recovery, modern versus legacy walk counts, guarded identity swaps, and backup-before-replace behavior.
