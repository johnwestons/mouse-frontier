# ADS correction wave: improvised weapons

Built-in image generation was used in edit/reference mode. Existing candidates were not overwritten.

## Selected review candidates

| Weapon | New candidate | Sight lock | Full framing | Mechanical identity | Review status |
| --- | --- | --- | --- | --- | --- |
| Scrap pistol | `scrap-pistol-sights-v2.png` | Pass: one brass blade nested in one U-notch; no separated upper post | Pass | Pass | Review candidate |
| Sawed-off shotgun | `sawed-off-shotgun-sights-v2.png` | Pass: one brass bead nested in one shallow U-notch | Pass | Pass: stacked double barrels, break action, bird's-head grip | Review candidate |
| Machine pistol | `machine-pistol-sights-v3.png` | Pass: one iron blade nested in one U-notch; no duplicate sight | Pass | Pass: the separate forward black magazine is offset left with a visible gap from the tan-wrapped rear pistol grip and its independent endcap | Review candidate; v2 superseded |
| Rugged submachine gun | `rugged-submachine-gun-sights-v2.png` | Pass after retry: one post centered inside one aperture; duplicate receiver sight removed | Pass | Pass: Thompson-like receiver, separate magazine, pistol grip, and forward wood remain readable | Review candidate |

## Prompt set

Every initial prompt used the approved hip sprite as the weapon-identity reference and `compact-scrap-pistol-sights-v1.png` as the straight-bore-axis alignment reference. The shared lock required:

- true eye-level view directly behind the bore axis;
- exactly one front blade, bead, or post visibly nested in the nearest rear notch or aperture;
- equal lateral clearance and correct sight height;
- no separated post, bead, hood, or muzzle silhouette above the sight cluster;
- complete grip, endcap, and any separate magazine or foregrip visible;
- no hands, firing effects, text, watermark, or cropping.

Targeted retries changed only the duplicated sight structures. No scripted or code-based image cleanup was applied.

The final identity-focused machine-pistol edit locked the approved v2 sight cluster and changed only the lower geometry. It restored the TEC-9 layout with a distinct forward magazine and rear pistol grip. The final five-weapon comparison is `review-02-improvised-final.png`; the compact scrap pistol intentionally retains its approved `compact-scrap-pistol-sights-v1.png` ADS candidate.

## Transparency note

The built-in generator returned pale checkerboard pixels rather than reliable alpha on these candidates. They are suitable for visual approval only and must not be wired into runtime until a genuinely transparent output is produced by the image tool.
