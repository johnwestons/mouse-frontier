# Event pacing and choice safety

Trail-event pacing is owned by `game/event_balance.lua`. Ordinary stops, event selection, desktop builds, and Android builds use the same phase rules.

## Stop pacing

| Journey phase | Stops | Ordinary mob chance | Random-event chance after required chapters |
| --- | --- | ---: | ---: |
| Easy | 1-12 | 48% | 52% |
| Medium | 13-30 | 58% | 42% |
| Hard | 31-50 | 64% | 36% |

Story and mystery chapters still take priority at their assigned stops. The phase curve gives early runs more opportunities to recover and make choices, while combat becomes the dominant ordinary interruption later in the journey.

## Event families

Early random events favor fortune and help encounters. Mishaps and settlement defenses become more prominent later. The immediately previous event family is removed from the next weighted draw, preventing back-to-back runs of the same category while retaining all five families throughout the journey.

## Choice safety

Every one of the 40 events now has at least one choice that is always actionable: a battle, a no-cost narrative option, or an explicit last resort. Mishap fallbacks still consume whatever supplies or inventory remain, preserving their consequences, but an exhausted player can no longer become permanently trapped because all three buttons require unavailable resources, ammunition, or inventory.

## Automated guarantee

The deterministic event audit validates 40 events and 120 choices, verifies that every event remains escapable, checks all phase weights and encounter rates, and confirms immediate category repeats are prevented. It runs in the desktop and mobile smoke suites.
