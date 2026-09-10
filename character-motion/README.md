# Character motion upgrade lane

Mouse Frontier accepts upgraded characters one at a time while preserving the
legacy animation path for the rest of the roster.

## Runtime asset contract

An upgraded character directory must contain all ten locomotion strips below.
The runtime activates the new controller only when the complete set exists, so
a partial art import cannot change gameplay.

| Direction | Walk strip | Idle strip | Frames |
| --- | --- | --- | ---: |
| east | `walk.png` | `idle.png` | 8 / 2 |
| north | `walk_north.png` | `idle_north.png` | 8 / 2 |
| northeast | `walk_northeast.png` | `idle_northeast.png` | 8 / 2 |
| southeast | `walk_southeast.png` | `idle_southeast.png` | 8 / 2 |
| south | `walk_south.png` | `idle_south.png` | 8 / 2 |

Characters with asymmetric clothing or carried gear also provide `walk_west`,
`walk_northwest`, `walk_southwest` and their matching `idle` strips. The runtime
uses these authored western views when the complete six-strip extension is
present. Five-view sets intentionally mirror their eastern views instead.
Every frame remains a transparent 512x512 cell in a horizontal strip, with a
shared center and foot baseline.

## Per-character workflow

1. Add `character-motion/<character>.json` using the sprite-gait motion spec.
2. Review a five-view direction study and the matching two-pose directional idles.
3. Author all five eight-pose gait strips in the canonical phase order.
4. Run the reusable sprite-motion audit and inspect its contact sheets and GIFs.
5. Copy only reviewed strips into `assets/sprites/character-animations/<character>/`.
6. Add an optional entry to `CharacterMotion.profiles` only when the character
   needs cadence or acceleration values different from the shared defaults.
7. Run `tools/run_character_motion_test.ps1`, the focused sprite audit, and the
   game smoke test.

The shared controller normalizes diagonal input, retains the final movement
sector for idle, advances frames from post-collision distance, freezes the gait
when blocked, preserves wall sliding, and samples synchronized speed and
acceleration curves. Existing characters remain on their original movement and
rendering behavior until their complete directional set is installed.
