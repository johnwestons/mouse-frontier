# Quest and Passenger Balance

Mouse Frontier uses `game/quest_progression.lua` as the shared Windows and Android authority for NPC offer pacing, delivery distance, quest rewards, passenger contributions, objective tracking, and reward delivery.

## Offer pacing

| Route point | Mail | Passenger | Supplies | Trade | No offer |
| --- | ---: | ---: | ---: | ---: | ---: |
| Stop 1 | 22% | 18% | 18% | 8% | 34% |
| Stop 50 | 14% | 12% | 20% | 16% | 38% |

Early stops emphasize social help and rides. Later stops offer more supply work and trading as the player’s train economy becomes established. Crow merchants always retain their guaranteed trade role.

## Distance and rewards

- Mail travels 3–8 stops when enough route remains.
- Supply deliveries travel 2–6 stops.
- Passenger ride length remains job-specific and gains one stop when food and water are both healthy.
- Near the end of the route, every distance contracts safely to the remaining stops.

Every completed mail, supply, or passenger quest awards coal, scrap, experience, and an item. Base rewards depend on quest type; scrap increases every two stops, coal increases every four stops, and experience increases every stop. The Scrapper and Diplomat reward multiplier applies to coal and scrap. Excess coal at storage capacity converts one-for-one into scrap, so a completed quest never loses that part of its payment.

Reward items are at least uncommon for a four-stop delivery or a destination at stop 15+, and at least rare for a seven-stop delivery or a destination at stop 37+.

## Passenger jobs

Passengers contribute after each journey until reaching their destination.

| Job | Base contribution | Matching car | Improved contribution |
| --- | --- | --- | --- |
| Greenhouse | 1 food | Greenhouse | 2 food |
| Fireman | 1 coal | Coal Hauler | 2 coal |
| Medic | 1 health | Medical Car | 3 health |
| Scavenger | 1 scrap | Sleeper Car | 2 scrap |

Passenger destinations and quest deliveries count toward passenger supply load as before; the Sleeper Car still halves that travel cost.

## Objective and delivery safety

The journey map shows the nearest active mail, supply, or passenger destination and the number of additional objectives. Supply cargo accepted with a full backpack is secured as cargo rather than creating an impossible storage requirement.

Ammunition rewards go directly into the correct ammunition reserve. Other quest items first use an empty backpack slot. If the backpack is full, the item is placed in the permanent train mailbox and its unread indicator activates. The mailbox can be opened with the normal interaction key, the inventory key while nearby, or pointer controls. A completely full mailbox falls back to a local supply crate.
