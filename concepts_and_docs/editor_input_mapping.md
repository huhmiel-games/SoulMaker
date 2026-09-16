# Editor input mapping (P1)

Resolved 16/09/2026 — keyboard AND gamepad usable in the map editor. The
mapping is **data-driven**: rebinding edits one dictionary
(`src/autoloads/input_manager.gd`), never scattered across editor scripts.

## Principles

- **Keyboard constraint from the gamepad**, not the reverse: the keyboard
  follows the same logical action set as the gamepad, with dedicated extra
  keys for the actions a gamepad cannot express (precise SpinBox editing,
  mouse picking, drag & drop).
- **No modal modes.** Actions are contextual (what is selected / where the
  viewport center points), and the gamepad uses a single **shift modifier**
  (R1) — the Souls gesture pattern — to double the button set instead of
  switching explicit modes.
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
| LT / RT | zoom out / in |
| D-pad | nudge object (L/R = X, U/D = Z) |
| L3 | fine mode (step ÷5) |
| A | place catalog entry / select under center |
| B | deselect |
| X | delete selection |
| Y | toggle playtest |
| LB / RB | catalog prev / next entry |
| Start | quick save |
| Back | load map |
| Guide | menu (reserved) |

Shifted set (R1 held) — transform & utilities:

| Input | Action |
|---|---|
| LS / RS | move / rotate object (analog, reserved for gizmos) |
| LT / RT | scale (reserved for gizmos) |
| D-pad U / D | nudge Y (up / down) |
| A | cycle translate → rotate → scale |
| B | reset transform |
| X | duplicate |
| Y | toggle snap |
| Back | delete all |

## Keyboard mapping (editor profile)

Same logical actions, dedicated keys — no modifier needed:

| Action | Key |
|---|---|
| nudge X / Z | arrows |
| nudge Y | PageUp / PageDown |
| fine mode | Shift |
| place / select | left click (mouse) / catalog buttons |
| delete | Delete |
| playtest | P |
| save | S |
| load | L |
| menu | Escape |

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