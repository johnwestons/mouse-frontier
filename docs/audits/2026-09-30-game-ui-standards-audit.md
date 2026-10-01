# Mouse Frontier — Game UI and Menu Standards Audit

**Reviewed:** September 30, 2026

**Scope:** Player-facing game screens and menus, including gameplay HUDs and activity screens.

**Method:** Source review across the screen flow, screen drawing, HUD, inventory, input, save, and accessibility modules. I also reviewed the project's existing 32-screen mobile UI capture set, dated September 12. I did not launch the current build or run the visual audit during this review.

## How to read this audit

There is no single checklist that defines a “standard game.” Feature expectations depend on genre, platform, and whether a game is single-player, online, mobile, or controller-first. This comparison uses common expectations for a modern single-player adventure, plus the Xbox Accessibility Guidelines (XAG) and Game Accessibility Guidelines as practical industry references. XAG explicitly describes itself as best-practice guidance, not a compliance standard. [XAG overview](https://learn.microsoft.com/en-us/xbox/accessibility/guidelines) · [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/full-list/)

“Missing” means I could not find that feature in the screens and modules reviewed. “Partial” means the game has a useful version, with a notable limit. Pixel-level readability, contrast ratios, clipping in the current build, screen-reader behavior, and recent changes since the September 12 capture set are **not verified** here.

## Overall assessment

Mouse Frontier already has a substantial UI for its scope. It is ahead of a minimal indie game in its number of supported activities, contextual prompts, player settings, mobile layouts, save slots, item details, tactical battle information, and progression feedback. The visual language is cohesive: dark panels and brass trim suit the frontier setting, and the same button treatment carries across many screens.

The main standards gaps are concentrated in access and error prevention:

1. **Save deletion is immediate.** Selecting Delete removes the slot and its related files without a confirmation step. XAG 115 recommends a review/confirm or undo path for destructive changes to player data.
2. **Accessibility settings are not available before starting a journey.** The normal accessibility page lives in gameplay Settings. The title/save screen's separate “Cheats / Controls” panel can move touch controls, but does not expose the accessibility preferences.
3. **Menus are not consistently keyboard-only or controller navigable.** The main navigation is click/tap driven. Keyboard shortcuts exist for parts of gameplay and some choices, but there is no general focus ring, directional menu traversal, or full action-remapping screen. A special controller path exists in Last Stand; it is not a whole-game controller interface.
4. **Text/accessibility options have useful basics but a limited range.** Text size tops out at 130%, with one bundled typeface. High contrast is available, but the UI has not been measured against the XAG contrast targets. Screen narration and icon text alternatives are not apparent in the custom UI.
5. **There is no dedicated quest/journal screen.** The route map shows a compressed summary of current tasks; it does not provide a browsable objective list.

These are recommendations, not a claim that the game fails a certification. XAG suggests 200% text scaling, 4.5:1 contrast for standard text, 3:1 for large text, and 7:1 in high-contrast mode; these require measured runtime captures to assess. [XAG 101: Text display](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/101) · [XAG 102: Contrast](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/102)

## Screen-by-screen review

| Screen / surface | What the game has | Gaps compared with common expectations | Priority |
|---|---|---|---|
| **Intro / first launch** | Branded intro cinematic followed by the journey-slot screen; intro can be skipped with a key. | No first-launch accessibility setup. No general control primer appears in the registered screen flow; the first useful movement/interact explanations come from in-world prompts. Confirm that the skip affordance is visible on screen, not only discoverable by pressing a key. | **High:** access before play. **Medium:** onboarding. |
| **Journey slots / title** | Three local save slots; Continue, New, and Delete; each populated slot shows the traveler and current stop. A “Cheats / Controls” entry is reachable here. | Delete acts immediately, with no review, confirm, or undo. No play time, last-played time, save thumbnail, or compact progress summary is shown. Accessibility options are not on this screen. The “Cheats / Controls” label combines player control setup with a developer-style item/resource grant menu. | **High:** deletion safety and pre-game access. **Medium:** slot information and separating normal settings from cheats. |
| **Traveler selection and profile** | Character grid with role; profile gives trait and ability descriptions, an animated preview, and a choose/back step. The choice is explicit before play starts. | The grid is pointer/touch based. Keyboard can scroll but does not provide a clear way to focus and choose a card; no visible keyboard focus state. No character search/filter (not essential for the current roster, but useful if it grows). | **High:** keyboard-only access. **Low:** search. |
| **World HUD — train, stops, homes** | Resource counts with icons; health, level/XP, goodwill, train condition/cars, and ammo; context-sensitive interaction hints; map/backpack/settings/scene actions; camera zoom and pan. Mobile gets a fixed-width HUD and edge controls. | Desktop presents scene actions directly instead of a unified pause hub. On small displays the HUD is dense, and some abbreviated labels/icons rely on recognition. The resource icons have no visible word labels in their compact form; a text alternative or optional labels would help new players and assistive narration. There is no dedicated objective tracker with task details. | **High:** icon alternatives and input access. **Medium:** more detailed objectives. |
| **Journey menu / pause access** | On mobile, the Journey Menu groups travel, backpack, map, train upgrades, furniture placement, maintenance, poses, Settings, and scene-specific actions. A Back/Menu control returns to play. Desktop keeps common actions on screen and Escape closes active panels. | There is no single pause screen shared by desktop and mobile. The mobile menu has no labeled Resume button; return is explained as “Tap BACK or CLOSE.” There is no visible menu-wide control legend or keyboard/controller focus order. | **Medium:** consistent pause/resume/navigation. |
| **Route map** | Illustrated trail of visited stops, biomes, current-stop status, scroll controls, and a short active-delivery/passenger summary. Expedition areas have a separate local map. | No text-list alternative for route points and no dedicated quest/journal page. The summary truncates to the first task plus a count, so players cannot inspect every active task from the map. XAG 112 recommends a non-map way to locate information on complex maps. | **Medium:** task list and map alternative. |
| **Backpack and storage** | Item sprites, slot count, ammo storage, equipped weapons, item-specific details, use/equip/drop actions, containers/mailbox, and mouse/touch transfer. Some keyboard shortcuts and quick-transfer gestures are supported. | No backpack sort, category filter, or item search. Some item actions are tied to double-click/double-tap or drag. Drop is immediate; an undo or confirmation for rare/unique items would reduce accidental loss. Several action hints are compact text that may be hard to discover without hover/inspection. | **Medium:** low-effort alternatives and safer drop. |
| **Dialogue / help / quest offers** | Speaker and dialogue text, authored choice menus, Continue Later for multi-step help conversations, and explicit accept/decline controls for quest offers. The game has regular NPC chatter and persistent conversation progress. | Dialogue is already presented as readable text, so a subtitle toggle is not an obvious missing feature for current content. No general text-to-speech/screen narration option is apparent. Control prompts and available choices need to remain usable without a pointer. | **Medium:** screen narration and non-pointer navigation. |
| **Trading post** | Separate buy/sell columns; item names and sprites, prices, player scrap, merchant budget, relationship terms/discount, paging, and Give for eligible gifts. Unaffordable purchases are disabled. | Buy, sell, and gift actions execute on selection without a second transaction review. Prices are visible, which makes this less risky than an unlabeled transaction, but a review/undo step is still safer for high-value items. No search/filter is visible in the shop. | **Medium:** transaction review for valuable actions. |
| **Travel confirmation** | Destination and next stop, food/water/coal costs, terrain preview/unknown state, passenger load, maintenance penalty, affordability, Confirm, and Cancel. | No destination/event preview when the route is unknown; this is appropriate for exploration, not necessarily a usability bug. The key cost information is otherwise explicit before departure. | **Good coverage.** |
| **Train workshop / upgrades** | Engine stats, current scrap/condition/oil, unlock stop, cost/owned/max states, train-car descriptions, repair status, and close. | A purchase/repair result is communicated after action, but the list does not appear to offer a separate comparison view or transaction confirmation. Upgrade costs and unlocks are clear enough for a first pass. | **Low–medium:** review for costly changes. |
| **Maintenance activity** | Dedicated visual activity, oil and condition feedback, progress lamps, Done/Close, and reduced-motion support in the shared accessibility system. | It relies on visual targeting and interaction. I did not verify whether the current activity has an equivalent non-pointer input path or whether status changes are announced outside visual feedback. | **Medium:** alternative input and feedback. |
| **Settings — audio** | Separate Music, Sound FX, and Rain volume controls; station/track status; previous, play/pause, next, and mute. Radio panel exposes station and rain selection. | No master volume, language, display/UI-scale, or voice/dialogue channel appears in the settings UI. Separate audio categories are already present. Voice volume may be unnecessary if the game has no spoken dialogue. | **Low:** optional settings breadth. |
| **Settings — accessibility** | Normal/Large/Extra Large text (100/115/130%), high contrast, reduced motion, control hints, touch feedback, and large touch targets; options are saved with the journey. | Settings are reachable after entering a journey, not before. Text scaling is capped at 130%, and there is no alternate font or spacing control. High-contrast behavior is implemented but its ratios are unmeasured. No screen narration, color-vision presets, or broad UI-scale control surfaced in the checked modules. XAG recommends scaling text to 200% and measurable contrast targets. | **High:** expose before play. **Medium:** expand and verify options. |
| **Touch control editor / Player Options** | Move touch controls, adjust their opacity, restore defaults; item/resource grants are paged and searchable where relevant. Touch positions persist on the device. | This is not a full control remapper: it changes touch positions and opacity, not gameplay key/button assignments. Cheats and control setup share the same panel. No equivalent mouse/keyboard layout editor. | **Medium:** remapping and clearer grouping. |
| **Radio / pose panel** | Radio offers station, rain, track, playback and mute controls. Pose panel offers stand/sit/lie/use. Context hints explain nearby radio interactions. | These small surfaces depend on pointer/touch selection; no general controller or focus navigation. No material content gap for their current purpose. | **Low–medium:** shared navigation consistency. |
| **Furniture placement / edit controls** | Move, resize, rotate, change layer, hue/saturation, pick up, Done; keyboard directional movement is also supported. | Color sliders are pointer/touch driven; labels and slider values are present, but alternatives for keyboard-only fine adjustment are unclear. There is no clearly visible reset-to-default action for an individual placed item in the panel. | **Low–medium:** keyboard slider support and reset. |
| **Expedition local map** | Area name and guidance, paths, player marker, points of interest, sealed/available/surveyed states, threats, flood information, and a legend. | Information uses map markers and some color coding. A navigable text list of POIs/statuses is not apparent. This is a practical accessibility gap for players who cannot distinguish the drawn map quickly. | **Medium:** text list and redundant marker shapes/labels. |
| **Tactical battle** | Round/objective, board, highlighted reachable/target tiles, unit health/status, battle feed, weapon/action buttons, backpack, retreat, touch/click hints, and high-contrast variants. Keyboard shortcuts support several actions. | Board targeting remains pointer/touch driven; no keyboard/controller cursor navigation across tiles. Battle feed shows only a small number of lines at once. Status visibility and color distinction should be checked at larger text settings and with color-vision simulation. | **High:** non-pointer board navigation. **Medium:** feed review. |
| **Random event choice** | Event category/title/art, progress for story/mystery sequences, three labeled choices, and affordability feedback; keyboard number keys can choose. | Choice text, consequences, and input access should be visually checked at large text sizes. A confirm step before narrative choices is not essential when the options themselves are clear. | **Good coverage; verify readability.** |
| **Campaign ending** | Journey summary, legacy choices with descriptions, a selected outcome, and return to slots. | No replay/continue-after-ending path is evident from this screen; likely intentional for a 50-stop campaign. | **Good coverage.** |
| **Exit / return prompt** | Yes/No confirmation for quitting or returning to title; keyboard yes/no shortcuts. | Good safety pattern. Confirm focus and touch hit targets in a fresh runtime capture. | **Good coverage.** |
| **First aid, target range, Last Stand, and other activity screens** | These have dedicated interfaces and interaction logic rather than being embedded in the world HUD. Last Stand includes a controller-specific input path. | I did not visually re-audit each activity at runtime. The controller support is activity-specific rather than evidence of game-wide controller support. Apply the same text, focus, input-alternative, and reduced-motion review to each activity. | **Needs fresh visual/accessibility pass.** |

## Features the game already handles well

- **Save continuity:** three slots and automatic persistence are present; in-world progress is saved through the project's persistence system.
- **Confirmation before travel:** costs and important modifiers are shown before the player commits.
- **Contextual help:** control hints appear for nearby interactions, and there are explicit interaction prompts in battles.
- **Useful mobile adaptation:** large touch targets, editable control positions, touch feedback, fixed-edge controls, and several viewport layouts are implemented.
- **Readable panel structure:** content is separated into labeled sections, resource/health values have bars, and inventory uses item sprites with detail panels.
- **Choice clarity:** character selection, quest offers, and ending choices have distinct selection/accept steps.
- **Accessibility foundations:** text scaling, high contrast, reduced motion, hints, feedback, and target-size options already exist.

## Recommended order of work

### Priority 1 — reduce accidental loss and unlock access before play

1. Add a neutral **Delete this save?** confirmation with cancel as the default-safe path. Keep deletion as a separate deliberate action. Consider an undo window if the save architecture makes that simple.
2. Put a compact **Accessibility** entry on the first journey screen (or show a one-time setup panel), so players can adjust text/contrast before reading the intro or beginning a save.
3. Add a consistent keyboard navigation and visible focus state to the title, character select, settings, map, inventory, shops, and dialogs. Keep pointer/touch as additional input methods.

XAG 112 recommends consistent keyboard/digital navigation and back paths; XAG 113 calls for a highly visible focus indicator. [XAG 112](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/112) · [XAG 113](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/113) · [XAG 115](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/115)

### Priority 2 — make core systems easier to read and revisit

4. Add a **Quest / Journey Log** that lists every active task, destination, passenger, and current objective. Keep the route-map summary as a quick glance.
5. Add a **full control remapping** page, including keyboard and any controller inputs the game intends to support. If gamepad support is not a target for the full game, say so in the player-facing controls help rather than leaving it ambiguous.
6. Increase the text-size ceiling and measure key screens at each level. Audit the normal and high-contrast palettes against contrast ratios; add text alternatives for icon-only resource counters and map symbols.
7. Provide a clear **Resume/Back** route shared across pause-like interfaces, and make the return-to-title/quit actions discoverable without requiring users to know Escape or Android Back.

### Priority 3 — quality-of-life safeguards

8. Add search/filter or sort to the backpack when capacity/content makes item retrieval slow.
9. Add review/undo for high-value shop transactions and accidental drops of rare/unique gear.
10. Add a text/list alternative for expedition map markers and improve screen narration support if blind/low-vision access is in scope.

## Evidence reviewed

### Project sources

- [Screen flow](../../game/screen_flow.lua) — registered full-screen states.
- [Screen UI](../../game/screen_ui.lua) — title, character select, HUD data, trade, route map, dialogue, travel, events, upgrades, editing, ending, and exit prompt.
- [Gameplay HUD](../../game/gameplay_hud.lua) — scene controls, mobile journey menu, settings, radio, contextual hints, and modal overlays.
- [Gameplay input](../../game/gameplay_input.lua) — keyboard shortcuts, pointer handling, save deletion path, and modal dismissal.
- [Accessibility settings](../../game/accessibility.lua) — text scaling, contrast, motion, hints, feedback, and touch target settings.
- [Mobile accessibility notes](../../ACCESSIBILITY_MOBILE.md) — intended behavior and previous review scope.
- [Inventory UI](../../game/inventory_ui.lua) — pack, equipment, storage, and item actions.
- [Battle UI](../../game/battle_ui.lua) — combat HUD, board actions, hints, and feed.
- [Player options](../../game/player_tools_ui.lua) — touch control editor and item/resource tools.
- [World pause rules](../../game/world_pause.lua) — which screens pause the simulation.
- Existing visual reference: `.stabilization/mobile-ui-audit/contact-sheet.png` (32-screen capture dated September 12, 2026). It is a prior snapshot, not a fresh validation of the September 30 source.

### Industry references

- [Xbox Accessibility Guidelines overview](https://learn.microsoft.com/en-us/xbox/accessibility/guidelines) — community-developed best practices, not a compliance checklist.
- [XAG 101: Text display](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/101)
- [XAG 102: Contrast](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/102)
- [XAG 107: Input](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/107)
- [XAG 112: UI navigation](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/112)
- [XAG 113: UI focus handling](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/113)
- [XAG 115: Error messages and destructive actions](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/115)
- [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/full-list/) — cross-platform accessibility recommendations with basic, intermediate, and advanced tiers.
