# Mouse Frontier Gameplay Upgrade Roadmap

This roadmap orders the remaining work by dependency and gameplay impact. Every target must preserve existing saves, use the shared Windows/Android Lua source, pass desktop and full-route smoke checks, pass the packaged mobile smoke checks, and end in a clean Git commit.

Current content: the shooting range, Last Stand rescue, crow-caravan trading camps, and the stop-6 surface/dungeon expedition are integrated into the shared game, with persistent progress and return paths.

First aid now uses cut inspection and five treatment steps. Water-pump repair remains a short instant chore. The four retired community minigames and their regional variants are absent from this release; their redesign remains future content work.

Latest visual polish: every help-minigame stage now presents its authored full-color atlas art with distinct scene and choice treatments instead of repeated stage-one placeholders. First aid also displays the actual medical-supply sprite being used. The enlarged locomotive now has distance-accurate drivers, rigid coupling and connecting rods, animated car bogies, layered vibrating ballast, and fullscreen seam regression captures. Desktop car selectors no longer cover the exit control, long battle weapon/item labels are compacted into their buttons, and the two Ferret Scout idle frames have repaired crops and baselines.

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
- **Revised:** Water-pump repair remains available with a telegraphed nonlethal runoff hazard and persistent goodwill/scrap reward. Sludge containment, debris clearing, garden rescue, and trough care were retired for individual redesign. Ambient critters still respond to nearby travelers.

## 9. NPC relationships and character identity — Complete

- **Complete:** Extend goodwill into persistent per-NPC recognition, category-aware gift responses, merchant discounts and resale benefits, and relationship-aware passenger dialogue.
- **Complete:** Audit every selectable character's trait, implemented special ability, roster eligibility, combat role, and explanation. Character cards now open a touch-friendly confirmation profile before creating the save.

## 10. Accessibility and mobile polish — Complete

- **Complete:** Add persistent Normal, Large, and Extra Large text choices, high contrast, reduced motion, optional control hints, visual/haptic touch feedback, and adjustable large touch targets.
- **Complete:** Improve battle readability with stronger movement and target shapes, bordered health bars, scalable status/feed text, always-visible mobile ability explanations, and keyboard/touch-accessible settings.
- **Complete:** Keep every new control usable by mouse, keyboard, and Android touch without hover-only assumptions.

## 11. Final desktop/Android parity and regression audit — Complete

- **Complete:** Require every desktop gameplay checkpoint to pass unchanged in the packaged Android build, plus reviewed touch-only coverage for movement, actions, menus, home exits, settlement help, and pinch zoom.
- **Complete:** Require the full route to reach stop 50, package from a clean tracked commit, verify the APK contents and signature, install on a connected Android device, and confirm the game reaches its startup marker.
- **Complete:** Keep the release gate repeatable with `tools/audit_platform_parity.py` and document it in `FINAL_PARITY_AUDIT.md`.

## 12. Deeper help quests and authored minigames — In progress

- **Complete:** Build the shared, persistent help-quest session framework. Item requests, first aid, and community activities now share lifecycle states, resumable progress, graded results, active objectives, and exactly-once goodwill rewards on desktop and Android.
- **Complete:** Replace placeholder first aid with cut inspection, tool selection, five treatment steps, mouse/touch dragging, keyboard treatment, and saved pause/resume progress.
- **Retired:** Sludge containment, track-debris clearing, garden rescue, and wildlife-trough care were removed with their world spots and assets so they can be redesigned individually.
- **Planned:** Add the sprite-driven water-pump repair activity.
- **Complete:** Add the first four branching investigation and conversation quests: Missing Family Trail, Crop Dispute, Bandit Warning, and Broken Promise. Choices and evidence persist, every conclusion remains constructive, stronger investigation can earn exceptional goodwill, and NPC follow-ups reflect the saved relationship.
- **Planned:** Expand the authored dialogue pool beyond the first four quests and connect later-stop variants to regional characters and world-state consequences.

## Mobile parity contract

Android is not a later port. `BUILD_ANDROID.ps1` packages the same tracked Lua tree used by the desktop build. Each completed target must produce a package report whose `sourceCommit` matches the new commit and whose `sourceDirty` value is `false`.
