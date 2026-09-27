# NPC talk and quest offer probability audit — September 27, 2026

This audit follows regular Talk, scheduled authored conversations, and random stop task offers. The percentages below describe a fresh journey when the player talks to the outdoor resident at each eligible stop. Stop 50 cannot start a new request, so there are 49 eligible stops. Offers and assignments are saved to the stop layout so revisiting or reloading does not reroll them.

## Current behavior

### Regular chatter

The game has 33 user-approved regular lines. Before this audit, NPCs did not select randomly: each NPC always began with line 1, then advanced in list order and repeated after line 33. This made every newly met NPC's first regular line the same and made later lines predictable. The lines themselves are unchanged. Regular chatter now uses a saved shuffled cycle per NPC: each line appears once before the next cycle, and a cycle boundary cannot repeat the previous line. Each line has a 1-in-33 (3.03%) chance of occupying any given position in a fresh cycle.

Passengers use the same regular line pool and now share their own NPC's shuffled cycle. The relationship `talks` counter remains unchanged in purpose and still increments on each regular talk.

### Authored conversations

There are 13 supplied conversation trees. A fresh run always schedules the first at Stop 1; later assignments are spaced by a uniformly random 2, 3, or 4 stops. Each next question is chosen uniformly from unused questions, so the full 13-question set appears once by Stop 49 if the player visits and talks at the assigned stops. The expected pace is one authored conversation every 3 stops after the opening. For each assignment, each still-unused question has equal chance; the first assignment gives each question a 1-in-13 (7.69%) chance.

On a fresh stop, the assignment is made when the outdoor stop layout is first created, before a persistent house door exists. The assigned speaker is therefore the outdoor resident; entering the house does not create a second random question opportunity.

### New task offers

Each stop has one ordinary random task roll, assigned to the outdoor resident. House residents normally have no random task offer; Crow Merchant is a guaranteed-trade exception wherever that NPC is placed. A new-save roster has 45 eligible NPCs after excluding the selected player character, including Crow Merchant unless the player chose Crow Merchant.

The table accounts for the 1-in-45 outdoor Crow Merchant exception. It shows the effective chance that the outdoor NPC displays each task on a player's first talk at that stop. Percentages sum to 100% in each column.

These per-visit rates cover the outdoor NPC. House residents normally have no random offer, but if Crow Merchant is the house resident, talking to them creates a separate guaranteed trade opportunity; those extra house visits are not counted in this table.

| Outcome | Stop 1 | Stop 25 | Stop 49 |
| --- | ---: | ---: | ---: |
| Mail delivery | 7.82% | 5.91% | 3.99% |
| Passenger ride | 5.87% | 4.43% | 2.99% |
| Supply delivery | 5.87% | 5.39% | 4.91% |
| Trade | 6.13% | 7.57% | 9.01% |
| Item request | 2.93% | 3.41% | 3.89% |
| First aid | 3.91% | 3.91% | 3.91% |
| No new task | 67.47% | 69.38% | 71.30% |
| **Any new task** | **32.53%** | **30.62%** | **28.70%** |

The current task odds shift over the journey: mail and rides become less common, trade and item requests become more common, and first aid stays level. Across all 49 eligible stops, the current average is about 15 new task prompts, assuming the player talks to the outdoor NPC at every stop. The estimated campaign totals are 2.89 mail, 2.17 rides, 2.64 supply deliveries, 3.71 trades, 1.67 item requests, and 1.92 first-aid offers.

The 15 prompts are reasonably spread across those six broad outcomes. The estimated chance of seeing each at least once in a fresh full route is: mail 95%, rides 89%, supplies 93%, trades 98%, item requests 82%, and first aid 86%. These figures include the Crow Merchant override. If Crow Merchant is selected as the player character, the forced-trade exception is absent and the average drops to about 14 prompts.

### Supply delivery subtypes

When a supply-delivery task appears, it rolls one of six cargo types. The weights shift with journey progress:

| Cargo | Stop 1 | Stop 49 |
| --- | ---: | ---: |
| Food | 30% | 18.24% |
| Water | 22% | 15.14% |
| Medicine | 20% | 16.08% |
| Repair materials | 12% | 17.88% |
| Ammunition | 8% | 17.80% |
| Keepsake recovery | 8% | 14.86% |

Because supply delivery itself is only offered about 2.64 times per full route on average, the nested roll makes individual cargo types easy to miss. Under the current independent rolls, a player has an estimated 48% chance to see food, 39% water, 38% medicine, 33% repairs, 29% ammunition, and 26% recovery at least once. The chance of seeing all six in one full route is about **0.14%**. This is the clearest remaining gap if the goal is for a player to sample the full range of delivery requests in a single journey.

### Request wording and item variants

The mail, ride, trade, and first-aid prompts each have one fixed request line, so that line has a 100% chance whenever its task appears. Supplies have six cargo-specific lines and follow the cargo weights above. Item help has five requested-item variants, assigned by a stable NPC/stop hash instead of a fresh random roll. Across all eligible NPC/stop combinations, those five variants account for 19.7–20.2% each.

Because item help itself appears only about 1.67 times per full route, the chance to encounter any particular requested item at least once is only about 28–29%. The exact request wording has not been added to or changed in this audit.

## Quest prompt issues fixed

Before this audit, `questAsked` was marked as soon as the offer opened, while the visible choice existed only in runtime memory. Closing the prompt or restarting the game before choosing could permanently consume that stop's offer. The offer is now marked answered only after acceptance or explicit decline. If the player closes or reloads before choosing, the same offer appears again. The rolled delivery subtype is saved with the stop so closing the prompt cannot reroll it.

Declining by keyboard also had an input fall-through bug: Escape marked the request declined, then continued into the generic close handler and erased the decline message. The task choice now consumes the key event, and mouse and keyboard declines share the same save behavior.

## Review summary

- Regular dialogue now feels random while preserving exactly-once coverage within each NPC's 33-line cycle.
- Mail, ride, trade, and first-aid prompts each have one fixed request line; item-help prompts have five roughly even NPC/stop variants.
- The broad stop task rate is about 29–33% per eligible outdoor NPC visit, with roughly 15 task prompts available over a full route.
- Authored conversation pacing is spaced and without repeats; all 13 are scheduled in a new 50-stop run.
- The six cargo requests are individually under-exposed because only about 2–3 supply deliveries occur in a route. Increasing supply task frequency would increase total prompts; reducing the cargo-type weights alone cannot make all six likely. A no-repeat cargo rotation would improve variety among the supply deliveries that do occur without increasing prompt frequency.
- The underlying task category weights are unchanged; this report documents them so the next tuning choice can be deliberate.
- No authored line text was changed.

## Verification

The focused NPC conversation suite passed all 16 tests. The full project suite passed all 284 tests. Tests cover shuffled regular chatter across save migration, authored conversation pacing and one-time completion, preserving an unanswered supply offer and cargo type across reload, accepting once, and declining by keyboard without losing its feedback.
