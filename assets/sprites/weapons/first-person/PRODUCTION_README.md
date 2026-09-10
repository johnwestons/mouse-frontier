# First-Person Ranged Sprites — Production Set

Production status: **promoted 2026-08-30**.

- The runtime set contains **103 unversioned PNGs**: **39 firearm pairs** (78 hip/ADS sprites) and **25 special-weapon state sprites**.
- Weapon views are loaded lazily for the current weapon and released when the weapon changes or the range closes.
- `review-batch-*` folders preserve the versioned review history and are excluded from mobile packaging; the unversioned PNGs in this folder are the production assets.
- The hunting bow uses only the user-approved `hunting-bow-full-draw-aim.png`, promoted from the v4 master. Rejected or unapproved bow states were not promoted.
- ADS alignment records contain **45 calibrated anchors**, **0 provisional anchors**, and no meaningful ADS sight anchor for the boomerang throw view.
- Android build and deployment are intentionally deferred. The connected device was not touched during this promotion.

The review-batch notes remain the historical record for generation, corrections, superseded drafts, and source-file selection.
