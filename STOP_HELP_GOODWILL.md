# Stop Help and Goodwill

Stops use `game/stop_help_progression.lua` as the shared Windows/Android policy for local help, goodwill, and ending-facing reputation. Refusing or failing help never removes points and cannot create an evil alignment.

## Request pacing

Each stop has at most one ordinary request opportunity across its residents. A dedicated crow merchant may still offer trade independently. Existing unaccepted stop offers are moved to the new policy when that stop is loaded.

| Route phase | Any ordinary request | No request |
| --- | ---: | ---: |
| Early | 40% | 60% |
| Late | 36% | 64% |

Letters and rides become less common later. Supply deliveries remain uncommon, while item help, first aid, and occasional trade create variety without making every conversation an assignment.

## Item help

An NPC may persistently ask for clean water, food, a bandage, coal, or a small oil canister. Accepting does not fail if the item is missing: the NPC remembers the offer and checks again on later conversations. Completing the request consumes the exact backpack item and awards 2 goodwill.

## First aid

A wounded NPC can ask for treatment. Starting first aid requires any backpack item with a medical healing effect. The overlay asks the player to complete CLEAN, PRESS, and WRAP treatment markers in the displayed order.

- Mouse and touch select the treatment markers.
- Number keys 1–3 select the same markers on desktop.
- Three incorrect selections end the attempt without consuming the medical item or goodwill.
- Cancel and Android back preserve both the request and medical item.
- A successful treatment consumes one medical item and awards 3 goodwill.

## Goodwill

Goodwill is a nonnegative campaign score saved with the player. The journey display shows the total, and the current ending screen previews how settlements remember the player.

| Score | Recognition |
| ---: | --- |
| 0–4 | New Neighbor |
| 5–11 | Helping Hand |
| 12–23 | Trusted Friend |
| 24+ | Trail Guardian |

The later endgame target will use this score together with completed help, family clues, passengers, and train condition to select the final outcome.
