# Quest and Passenger Balance

Mouse Frontier uses `game/quest_progression.lua` as the shared Windows and Android authority for NPC offer pacing, delivery distance, quest rewards, passenger contributions, objective tracking, and reward delivery.

## Offer pacing

| Route point | Mail | Passenger | Delivery | Trade | Item help | First aid | No offer |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Stop 1 | 10% | 7% | 6% | 4% | 6% | 7% | 60% |
| Stop 50 | 6% | 4% | 5% | 7% | 7% | 7% | 64% |

Only one ordinary NPC offer is available per stop. Early stops emphasize letters and rides; later stops give trading and local help slightly more room. Most conversations remain ambient so stops are not overwhelmed by errands. Crow merchants retain their guaranteed trade role.

## Delivery jobs and cargo

| Job | Requirement at destination | Source order |
| --- | --- | --- |
| Food | 3 food portions | Eligible backpack food, then stored train food |
| Water | 3 water supplies | Eligible backpack drinks, then stored train water |
| Medicine | 2 medical supplies | Backpack bandages, salves, tonics, splints, or medkits |
| Repair | 3 repair materials | Backpack coal/oil items, then stored train coal |
| Ammunition | 8 rounds | Ammunition reserves, using common ammunition first |
| Recovery | Make the destination safe and recover a keepsake | The destination encounter must be clear |

Accepting a delivery never creates free cargo. Cargo is checked atomically at the destination: if the full requirement is unavailable, nothing is removed and the NPC explains the remaining shortage. Old food-delivery saves use the same backpack-first, pantry-second rule, including legacy records that once claimed cargo was stored automatically.

## Distance and rewards

- Mail travels 3–8 stops when enough route remains.
- Supply deliveries travel 2–6 stops.
- Passenger ride length remains job-specific and gains one stop when food and water are both healthy.
- Near the end of the route, every distance contracts safely to the remaining stops.

Every completed mail, delivery, or passenger quest awards coal, scrap, experience, an item, and one goodwill point. Base rewards depend on quest type; medicine, repair, ammunition, and recovery work pays more than ordinary food or water hauling. Scrap increases every two stops, coal increases every four stops, and experience increases every stop. The Scrapper and Diplomat reward multiplier applies to coal and scrap. Excess coal at storage capacity converts one-for-one into scrap, so a completed quest never loses that part of its payment.

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

The journey map shows the nearest active mail, named delivery, or passenger destination and the number of additional objectives. Each delivery label states its cargo type and full requirement.

Ammunition rewards go directly into the correct ammunition reserve. Other quest items first use an empty backpack slot. If the backpack is full, the item is placed in the permanent train mailbox and its unread indicator activates. The mailbox can be opened with the normal interaction key, the inventory key while nearby, or pointer controls. A completely full mailbox falls back to a local supply crate.
