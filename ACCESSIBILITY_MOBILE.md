# Accessibility and Mobile Controls

Mouse Frontier uses one accessibility system in the shared Windows and Android Lua source. Preferences were added safely in save schema version 29 and remain preserved by the current version 30 schema.

## Settings

Open **Settings** from the world interface or Android journey menu, then choose **Accessibility**.

| Preference | Behavior |
| --- | --- |
| Text size | Cycles through Normal, Large, and Extra Large for shared buttons, dialogue, battle status, and the battle feed. |
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
