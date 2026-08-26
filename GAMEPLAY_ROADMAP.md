# Mouse Frontier Gameplay Upgrade Roadmap

This roadmap orders the remaining work by dependency and gameplay impact. Every target must preserve existing saves, use the shared Windows/Android Lua source, pass desktop and full-route smoke checks, pass the packaged mobile smoke checks, and end in a clean Git commit.

## 1. Stop activities, help requests, and goodwill — Complete

- Give stops meaningful activities beyond looting.
- Add persistent NPC requests for needed items and local help.
- Add wounded-NPC encounters with a first-aid minigame.
- Award goodwill for completed help; there is no evil or negative alignment.
- Show the goodwill score and use it to shape the ending.
- Reduce the frequency of letters, rides, supply deliveries, trades, and other requests so new stop content has room to breathe.
- Expand ambient NPC dialogue, including the supplied sludge, bandit, family, track, cooperation, and safe-travel lines.

## 2. Quest cargo and delivery variety — Complete

- Supply deliveries consume three eligible food items first, then draw any shortfall from the train's stored food resource.
- Never create free delivery food merely because the backpack is empty or full.
- Add medicine, water, repair-material, ammunition, and recovery deliveries with distinct requirements and rewards.
- Keep active-objective, destination, reward-overflow, and mobile presentation behavior consistent.

## 3. Endgame and family-story payoff — Complete

- Replace the generic stop-50 ending with a finale shaped by goodwill, clues, completed help, passengers, and train condition.
- Add multiple positive ending tiers without an evil alignment.
- Add a meaningful final encounter or decision and a campaign summary.

## 4. Tactical battle expansion — Complete

- Enlarge the battlefield and add more traversable grid spaces.
- Add new terrain-square art and biome variety.
- Add impassable obstacles such as dead trees, small buildings, and rusty vehicles.
- Make obstacles block movement and appropriately obscure or block attacks.
- Correct battle zoom so tiles, units, obstacles, effects, and hit testing scale together instead of tiles separating.
- Improve enemy AI, ally ability use, battle objectives, status effects, and boss encounters.
- Ensure later-stop allied NPCs receive progression-appropriate weapons.

## 5. Global camera and input — Complete

- Make zoom and pan work consistently in every scene and interface where it is useful.
- Define deliberate camera behavior for menus and overlays rather than silently disabling controls.
- Provide touch pan and pinch zoom parity on Android.

## 6. Train presentation and maintenance — Complete

- Make all acquired train cars fit the visible train presentation at desktop and mobile aspect ratios.
- Centralize maintenance wear, oil supply, servicing costs, upgrade effects, and route-wide balance.

## 7. Audio and weapon variety — Complete

- **Complete:** Give every slingshot and eagle attacks appropriate non-firearm sounds.
- **Complete:** Add 18 cataloged melee weapons, including four new blades, four polearms, four axes, two restored sabers, and four mixed frontier weapons. Quick, blade, axe, blunt, polearm, and piercing families now have distinct accuracy, armor penetration, bleeding, staggering, reach, animations, sounds, loot tiers, pricing, durability, and repair values.

## 8. World interaction and visual polish

- **Complete:** Attach melee and ranged weapons to per-character, per-frame hand points in battle and world attacks. Sprite Doctor generates, reviews, validates, and permits authored corrections to the shared desktop/mobile attachment list.
- **Complete:** Redesign sludge creatures with mouse ears instead of antennae while preserving their established silhouette and animation contract. Four-frame idle/walk, attack, hit, and collapse atlases share one mouse-eared identity and render from the shared desktop/mobile source.
- **Complete:** Add a clearly clickable `EXIT HOME` button inside every home. The shared scene control has a compact desktop layout, a larger Android touch target, and uses the same save-safe exit action as the nearby-door shortcut.
- **Complete:** Expand stops with five persistent community activities whose deterministic rotation prevents either of the previous two activities from repeating. Telegraph environmental hazards, limit them to one nonlethal damage event with movement slowdown, reward help with goodwill and supplies, and make chickens and field mice flee travelers or gather around a filled wildlife trough. Desktop and Android use the same interaction path.

## 9. NPC relationships and character identity

- Extend goodwill into persistent NPC recognition, gift responses, merchant benefits, and passenger dialogue.
- Audit all character traits, special abilities, roster assignments, and selection-screen explanations.

## 10. Accessibility and mobile polish

- Improve text scaling, control guidance, touch feedback, settings, battle readability, and accessibility options.
- Keep all new buttons and minigames usable without mouse-only assumptions.

## Mobile parity contract

Android is not a later port. `BUILD_ANDROID.ps1` packages the same tracked Lua tree used by the desktop build. Each completed target must produce a package report whose `sourceCommit` matches the new commit and whose `sourceDirty` value is `false`.
