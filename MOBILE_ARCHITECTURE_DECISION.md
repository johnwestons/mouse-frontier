# Mobile Architecture Decision

**Date:** August 22, 2026
**Status:** Approved project direction
**Affected baseline:** `code-freeze-2026-08-22`, followed by the August 25 architecture migration

## Decision

Android and Windows ship from the same Lua gameplay, content, assets, save schema, and test suite. Android is not maintained as a copied fork. The only mobile-specific runtime code is the touch/control adapter in `game/mobile_controls.lua` plus its application wiring in `game/app.lua`. `main.lua` is platform-neutral lifecycle forwarding.

The August 25 migration lifted the broader code-structure freeze. Platform-specific changes must still remain inside the small adapter boundary so ordinary application and gameplay upgrades are inherited by both builds.

## Update boundary

Every Android build stages the current `main.lua`, `conf.lua`, and `game/*.lua` directly from the PC tree. Runtime artwork and sound are derived into the ignored `output/mobile` area. Generated Android assets are never edited as a second source tree.

The Android-only maintenance surface is:

- `game/mobile_controls.lua`
- Mobile callback wiring and dependency resolution in `game/app.lua`
- Android settings in `conf.lua`
- `mobile/config.json` and `mobile/android/AndroidManifest.xml`
- the mobile package/APK build scripts

## Verification

Each update must pass:

1. The normal desktop smoke playthrough.
2. The mobile callback smoke checks for analog movement, running, action press/release, and touch menus.
3. The smoke playthrough from the staged `.love` archive.
4. APK signature, identity, embedded-package, and ABI inspection.
5. A physical Android launch and controls check before distribution.

## Rollback

Removing the mobile callback wiring and build files restores the frozen Windows baseline. Shared gameplay and save files do not depend on Android packaging.
