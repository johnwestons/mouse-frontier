# Mobile UI visual audit

This standalone LÖVE runner renders the real game at 2340x1080 with the mobile
controls enabled. It captures menus, the HUD, sixteen-slot inventory, normal and
extra-large text settings, trade, dialogue, travel, battle, and activity screens.
It also verifies that the mobile HUD spans the physical screen without touching
the menu control at phone, 16:9, and 4:3 sizes, and remains fixed during world zoom.
Text boxes that cannot fit at their readable minimum are listed in `report.txt`.
Before screenshots, the audit measures every authored event choice using the
real event renderer, every help-quest map summary at normal and extra-large text,
and every three-choice help dialogue. It fails on overflow or intersecting
dialogue controls, so longer branches remain covered between visual reviews.

On Windows, run `tools/mobile-ui-audit/run.ps1`. It creates ignored asset
junctions as needed, launches the audit hidden, and prints its capture report.
Use `-OutputPath` to choose another output directory or `-Visible` to watch it.
Use `-Desktop -OutputPath .stabilization/desktop-ui-audit` to inspect the shared
font and desktop layouts at 1280x720. Desktop audits use a separate desktop audit
identity and skip mobile-only header geometry assertions.

Set `MOUSE_FRONTIER_MOBILE=1`, `MOBILE_UI_AUDIT_ROOT` to the repository's absolute
path, and `MOBILE_UI_AUDIT_OUTPUT` to an existing output directory. Launch LÖVE
with this directory as its source. Assets must be mountable from the repository;
on Windows, a directory junction named `assets` in this directory can point to
the repository's `assets` directory if LÖVE cannot mount the parent source.

The runner uses the separate `mouse-frontier-mobile-ui-audit` save identity and
three synthetic audit slots. The rendered journey is unslotted. Normal game
saves and the connected device are never accessed.
