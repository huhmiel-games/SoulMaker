# Editor input mapping (P1)

Resolved 16/09/2026 — keyboard AND gamepad usable in the map editor. The
mapping is **data-driven**: rebinding edits one dictionary
(`src/autoloads/input_manager.gd`), never scattered across editor scripts.

## Principles

- **Keyboard constraint from the gamepad**, not the reverse: the keyboard
  follows the same logical action set as the gamepad, with dedicated extra
  keys for the actions a gamepad cannot express (precise SpinBox editing).
  The mouse selects nothing — it only orbits.
- **No modal modes.** The gamepad uses a single **shift modifier** (R1) —
  the Souls gesture pattern — to double the button set instead of switching
  explicit modes. Confirm (A/E) is contextual on the crosshair — select red,
  place green — identically on every device. Free transform of placed objects
  (gizmos) arrives with the move rework.
- Gamepad does the **fast loop** (camera + place + nudge + save); keyboard
  adds the **precision layer** (SpinBoxes, text fields, mouse selection).
- The mapping lives in `InputManager.PROFILES`, one profile per context
  (`editor`, `playtest`; menus join later). Editor scripts only reference
  action names via `InputManager.is_pressed(...)`, `action_pressed` /
  `action_released` signals, or the analog getters.

## Gamepad layout (editor profile)

Default set (R1 released) — viewport & placement:

| Input | Action |
|---|---|
| LS | move camera along its view vector (pitch included — LS up dives toward the ground when the camera looks down) |
| RS | orbit camera **in place** (turret: rotates around itself, focus re-glued ahead) |
| D-pad U / D | catalog prev / next entry (within the selected category tab) |
| D-pad L / R | catalog category tab prev / next |
| A | confirm at the crosshair: select the aimed asset (red), else place the current catalog entry (green) |
| B | deselect |
| X | delete selection |
| Y | toggle playtest |
| Start | quick save |
| Back | load map |
| Guide | menu (reserved) |

Shifted set (R1 held) — transform & utilities:

| Input | Action |
|---|---|
| LS / RS | move / rotate object (analog, reserved for gizmos) |
| LT / RT | scale (reserved for gizmos) |
| D-pad | catalog panel (unchanged under R1 — object nudge deferred to the move rework) |
| A | cycle translate → rotate → scale |
| B | reset transform |
| X | duplicate |
| Y | toggle snap |
| Back | delete all |

## Keyboard mapping (editor profile)

The keyboard mirrors the gamepad action set 1:1 with **no click or drag**:
**WASD pans the camera** like the LS (pitch included), **mouse motion orbits**
like the RS (in place, RS direction), **arrows browse the catalog panel** like
the D-pad, **E places** like A. UI buttons are deliberately **not
mouse-clickable** (and not keyboard-focusable) so panel input never fights the
mouse; the `MapName` LineEdit keeps normal text focus. The keyboard
object-nudge workflow is **deferred** pending the object-move rework.

| Action | Key |
|---|---|
| camera pan (LS) | WASD |
| camera orbit (RS) | mouse motion (no click) |
| catalog prev / next | Up / Down arrows |
| category tab prev / next | Left / Right arrows |
| confirm at the crosshair (select red / place green) | E |
| aim feedback | crosshair, centered on the viewport (green = empty space, red = placed asset) |
| mouse click (panel or viewport) | *(nothing — parity: the mouse only orbits, selection is arrows/D-pad + A/E)* |
| delete | Delete |
| playtest | P |
| save | S |
| load | L |
| menu | Escape |
| nudge X / Z / Y | *(deferred — gamepad D-pad is the catalog panel; object nudge awaits the move rework)* |

## Playtest profile

Fly-cam stand-in until the P2 player controller:

| Action | Gamepad | Keyboard |
|---|---|---|
| move forward / back | LS Y (±) | W / S |
| move left / right | LS X (±) | A / D |
| move up / down | — | Space / Shift |
| toggle playtest | Y | P |

ESC still releases mouse capture in the fly-cam (unchanged).

## Architecture notes

- `InputManager` is an **autoload**; no `class_name` (conflicts with the
  singleton name).
- Sticks/triggers are exposed deadzone-applied (`left_stick()`,
  `right_stick()`, `triggers()`); camera scripts consume them continuously.
- A JSON override of the mapping lands with the Options screen (post-V1 per
  ADR / features §11: keyboard per-key, gamepad bounded rows).