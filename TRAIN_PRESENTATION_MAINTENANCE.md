# Train Presentation and Maintenance

The desktop and Android builds use the same 960×720 train geometry, car navigator, maintenance condition, and upgrade rules.

## Train presentation

- The locomotive occupies virtual x 23–323 and the active car occupies x 315–935, keeping both inside the shared canvas.
- Exactly one active car is rendered at the canonical interaction coordinates. Sliding transitions move complete outgoing and incoming views by one canvas width.
- A numbered consist navigator fits all seven possible cars between x 430 and 935. Its rectangles are shared mouse and touch targets, and selecting any owned car starts the normal door transition.
- Player, passenger, furniture, storage, mailbox, and door coordinates no longer receive a render-only offset in additional cars.

## Condition and wear

Condition ranges from 0 to 100 and begins at 72 for legacy-compatible saves. Each journey applies:

`wear = route wear + train-length wear - engine wear reduction`, with a minimum of 3.

| Factor | Rule |
| --- | --- |
| Route wear | 5 at stops 1–15, 6 at 16–30, 7 at 31–45, and 8 afterward |
| Train length | +1 at four cars and +2 at seven cars |
| Rebuilt Boiler | -1 wear |
| High-Pressure Drive | -1 wear |
| Frontier Express | -2 wear |

Condition of 25–49 adds one coal to a journey and runs travel at 92% speed. Condition below 25 adds two coal and runs at 82% speed. The journey HUD shows condition, status, and projected wear before departure.

## Oil and servicing

- Base train oil capacity is 20.
- Owning the Coal Hauler raises coal and oil capacity to 30.
- A completed running-gear service costs 5 oil and restores 40 condition.
- Oil is charged atomically when all five lamps are lit and the player confirms completion.
- A train can be serviced once at each stop; reopening the activity at that stop preserves the completed state.

The train workshop shows current condition, oil capacity, and the wear reduction supplied by the installed engine. `Maintenance.audit` and `Train.audit` protect these rules in both package variants.
