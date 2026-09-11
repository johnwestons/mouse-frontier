# Accessibility and Mobile Controls

Mouse Frontier uses one accessibility system in the shared Windows and Android Lua source. Preferences were added safely in save schema version 29 and remain preserved by subsequent save migrations.

## Typewriter typography and mobile layout

The game uses bundled Courier Prime regular and bold fonts with a shared 20-pixel base size. Text layout measures the actual font width and wrapped height before drawing; buttons and paragraphs reserve room for the selected text size. The font files, source attribution, and SIL Open Font License are included in `assets/fonts/`.

The mobile journey HUD spans the physical viewport across the top of the screen, giving supplies, health, progression, and train status more room. Its size and position stay fixed while the world is zoomed or panned. The surrounding phone edge controls remain reachable independently of the world camera.

The mobile UI review also widened menu and settings layouts, enlarged inventory and battle information, improved dialogue and trading text flow, and clarified radio, maintenance, first aid, shooting range, and Last Stand controls. Measured text boxes keep labels and messages clear of neighboring controls; longer text wraps within its allotted panel.

## Settings

Open **Settings** from the world interface or Android journey menu, then choose **Accessibility**.

| Preference | Behavior |
| --- | --- |
| Text size | Cycles through Normal, Large, and Extra Large for shared buttons, mobile HUD, dialogue, battle status, and other measured text panels. |
| High contrast | Gives panels and controls dark solid backgrounds, bright outlines, stronger health bars, and clearer tactical markers. |
| Reduced motion | Speeds through travel, train-car, and battle transitions while preserving decisions and results. |
| Control hints | Shows nearby interaction instructions and permanent battle guidance. It can be disabled after the controls are familiar. |
| Touch feedback | Shows a short confirmation ring and requests a brief Android vibration for successful taps. |
| Large touch targets | Enlarges the movement stick, action controls, and fixed Back/Menu bars. It is enabled by default. |

On Windows, `Tab` changes the settings page and number keys `1–6` change the six accessibility preferences. Every new setting also has a direct mouse and Android touch control.

## Battle readability

- Movement and attack spaces use distinct shapes, colors, and high-contrast line weights rather than color alone.
- Health bars gain bright borders in high-contrast mode, while status names and the battle feed follow the chosen text size.
- Mobile battles always show the current ability name, rank, and description without requiring hover.
- Guidance identifies touch/click targeting and camera zoom controls above the battlefield.

## Mobile interaction contract

- Action, secondary action, joystick, Back, and Menu controls remain anchored to the physical phone edges.
- Large-target mode uses a 58-pixel primary-action radius and an 82-pixel joystick radius on the 960×720 logical canvas.
- Menu and modal controls retain at least a 58-pixel mobile height in the new settings interface.
- Touches that become pinch/pan gestures do not also activate the underlying interface.
- Losing focus releases held actions and clears active touch gestures.

Automated checks exercise preference migration, mouse/touch and keyboard settings controls, text scaling, high-contrast rendering, reduced-motion timing, touch feedback, large control geometry, pinch/pan cleanup, and the complete packaged Android playthrough.

The September 11, 2026 UI update passed 165 regression tests and a 32-screen real-application review using isolated audit saves. The review includes the 2340×1080 phone viewport, 16:9 and 4:3 HUD layouts, world zoom, and Normal/Extra Large settings samples. It verifies the captured interfaces and reported text bounds; it does not establish every level, encounter, or text-size combination. The reproducible review is `tools/mobile-ui-audit/run.ps1`, with captures and the geometry report under `.stabilization/mobile-ui-audit/`.
