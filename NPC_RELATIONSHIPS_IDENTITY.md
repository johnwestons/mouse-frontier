# NPC Relationships and Character Identity

NPC relationships are persistent, goodwill-only records. Helping, carrying, and gifting to a traveler can build recognition; refusing a request or offering an unusable item never creates negative alignment.

## Relationship progression

Each NPC record preserves help earned, gifts, unique gifts, rides, conversations, and trades. Its relationship score advances through these tiers:

| Tier | Score | Result |
| --- | ---: | --- |
| New Face | 0 | Standard introduction and trade terms |
| Familiar Face | 3 | The NPC recognizes early kindness |
| Friend | 7 | Stronger personal dialogue and trade benefits |
| Trusted Friend | 14 | The warmest recognition and passenger responses |

Global goodwill and the personal relationship both improve merchant terms. Discounts and resale bonuses are capped at 20%, while trusted merchants also bring a larger effective scrap budget. The displayed price, affordability check, transaction, and saved merchant budget all use the same calculated terms.

Accepted gifts receive a response suited to weapons, medicine, food, water, gear, or fuel. Rejected gifts remain in the backpack and receive a friendly response. Passenger conversations remember gifts, acknowledge relationship rank, identify the passenger's job, and mention the shared destination.

Relationship data is stored in save schema version 28. Older saves gain an empty relationship table during the normal sequential migration; no previous goodwill, quests, equipment, or roster data is discarded.

## Character identity

Every selectable character is audited against the playable roster policy and receives:

- one of nine journey traits with a concrete gameplay effect;
- one of twelve implemented special-ability types;
- a combat role: Support, Guardian, Controller, Striker, or Leader;
- a complete trait and ability explanation before the save is created.

Selecting a character card now opens a confirmation profile instead of immediately starting the journey. The profile has large **Choose This Traveler** and **Back** controls, so mouse, keyboard, and Android touch players can review the choice safely. Every other eligible character remains available to the NPC roster.

## Verification contract

The automated playthrough checks save migration, persistent gift recognition, relationship tiers, buying and selling benefits, merchant budget growth, passenger-aware dialogue, complete roster assignments, identity diversity, and touch-sized profile controls. Windows and Android package the same relationship and identity modules.
