# Title snapshot character coverage

## Scope

The coverage target is every character currently eligible in the selectable traveler pool: the 47 PNGs for which `Roster.isPlayable(file)` is true in `assets/sprites/MainCharacters`. The `raccoon-witch.png` file remains excluded because `Roster.retired` marks it retired. Snapshot scenes must feature every target character at least once across the two title-menu memory bays.

Each scene is an authored transparent four-pose strip showing a helpful or warmly social interaction. Keep the established Mouse Frontier character designs, painterly pixel-art finish, and fixed framing. Do not add text or a frame to the artwork. The existing title renderer fades between poses and scenes.

## Existing coverage

Character identities below were checked visually against the corresponding source sprite sheets.

| Scene | Characters shown | Status |
| --- | --- | --- |
| `share-water` | `cook-mouse`, `medic-fox` | Integrated |
| `share-food` | `cook-frog`, `conductor-cat` | Integrated |
| `bandage` | `medic-fox`, `cook-mouse` | Integrated |
| `laugh` | `cook-frog`, `conductor-cat` | Integrated |
| `help-walk` | `trail-fox`, `young-tinker-fox` | Integrated |
| `handshake` | `scavenger-mouse`, `guard-fox` | Integrated |

All 25 integrated strips now cover all 47 eligible travelers. The original nine scenes covered fourteen characters; sixteen additional scenes complete roster coverage.

## Newly authored scenes

| Scene | Characters shown | Status |
| --- | --- | --- |
| `seedling-care` | `botanist-frog`, `mail-mouse` | Integrated |
| `share-shelter` | `courier-lizard`, `crow-merchant` | Integrated |
| `radio-repair` | `engineer-frog`, `radio-cat` | Integrated |
| `warm-kettle` | `ferret-engineer`, `ferret-medic` | Integrated |
| `shared-haul` | `gardener-lizard`, `jackrabbit-courier` | Integrated |
| `lantern-melody` | `watch-raccoon`, `musician-hedgehog` | Integrated |
| `route-map` | `ferret-scout`, `ferret-trapper` | Integrated |
| `herbal-delivery` | `gecko-courier`, `gecko-herbalist` | Integrated |
| `roadside-repair` | `gecko-mechanic`, `gecko-ranger` | Integrated |
| `quiet-garden` | `hedgehog-botanist`, `herbalist-hedgehog` | Integrated |
| `camp-supper` | `homesteader-cat`, `lizard-cook` | Integrated |
| `lantern-repair` | `mechanic-hedgehog`, `mechanic-raccoon` | Integrated |
| `shared-bandages` | `medic-cat`, `opossum-medic` | Integrated |
| `fair-trade` | `merchant-raccoon`, `mole-prospector` | Integrated |
| `boiler-repair` | `mouse-engineer`, `prairie-dog-mechanic` | Integrated |
| `river-route` | `otter-scout`, `river-raccoon`, `scout-frog` | Integrated |
| `trailmarkers` | `prospector-lizard`, `scout-lizard` | Integrated |
| `signal-lesson` | `scholar-mouse`, `signal-hedgehog` | Integrated |
| `station-map` | `tinker-fox`, `tortoise-conductor` | Integrated |

## Character checklist

| Character | Coverage |
| --- | --- |
| `botanist-frog` | Covered: `seedling-care` |
| `conductor-cat` | Covered: `share-food`, `laugh` |
| `cook-frog` | Covered: `share-food`, `laugh` |
| `cook-mouse` | Covered: `share-water`, `bandage` |
| `courier-lizard` | Covered: `share-shelter` |
| `crow-merchant` | Covered: `share-shelter` |
| `engineer-frog` | Covered: `radio-repair` |
| `ferret-engineer` | Covered: `warm-kettle` |
| `ferret-medic` | Covered: `warm-kettle` |
| `ferret-scout` | Covered: `route-map` |
| `ferret-trapper` | Covered: `route-map` |
| `gardener-lizard` | Covered: `shared-haul` |
| `gecko-courier` | Covered: `herbal-delivery` |
| `gecko-herbalist` | Covered: `herbal-delivery` |
| `gecko-mechanic` | Covered: `roadside-repair` |
| `gecko-ranger` | Covered: `roadside-repair` |
| `guard-fox` | Covered: `handshake` |
| `hedgehog-botanist` | Covered: `quiet-garden` |
| `herbalist-hedgehog` | Covered: `quiet-garden` |
| `homesteader-cat` | Covered: `camp-supper` |
| `jackrabbit-courier` | Covered: `shared-haul` |
| `lizard-cook` | Covered: `camp-supper` |
| `mail-mouse` | Covered: `seedling-care` |
| `mechanic-hedgehog` | Covered: `lantern-repair` |
| `mechanic-raccoon` | Covered: `lantern-repair` |
| `medic-cat` | Covered: `shared-bandages` |
| `medic-fox` | Covered: `share-water`, `bandage` |
| `merchant-raccoon` | Covered: `fair-trade` |
| `mole-prospector` | Covered: `fair-trade` |
| `mouse-engineer` | Covered: `boiler-repair` |
| `musician-hedgehog` | Covered: `lantern-melody` |
| `opossum-medic` | Covered: `shared-bandages` |
| `otter-scout` | Covered: `river-route` |
| `prairie-dog-mechanic` | Covered: `boiler-repair` |
| `prospector-lizard` | Covered: `trailmarkers` |
| `radio-cat` | Covered: `radio-repair` |
| `river-raccoon` | Covered: `river-route` |
| `scavenger-mouse` | Covered: `handshake` |
| `scholar-mouse` | Covered: `signal-lesson` |
| `scout-frog` | Covered: `river-route` |
| `scout-lizard` | Covered: `trailmarkers` |
| `signal-hedgehog` | Covered: `signal-lesson` |
| `tinker-fox` | Covered: `station-map` |
| `tortoise-conductor` | Covered: `station-map` |
| `trail-fox` | Covered: `help-walk` |
| `watch-raccoon` | Covered: `lantern-melody` |
| `young-tinker-fox` | Covered: `help-walk` |

## Integration and verification

- Add each final strip under `assets/sprites/ui/title/snapshots/` and make it available to the title snapshot selector.
- Preserve a common four-cell frame layout so mobile packaging can resize cells independently.
- Review every scene at full size over contrasting backgrounds for transparent edges, character identity, crop, and pose consistency.
- Verify that the title menu cycles through all integrated scenes without covering the save controls, then verify the packaged mobile assets and title-menu render.
