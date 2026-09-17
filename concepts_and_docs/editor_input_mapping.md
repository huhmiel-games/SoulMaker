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
| A | confirm at the crosshair: grab the aimed asset (red, camera freezes), else place the current catalog entry (green) |
| B | cancel grab (restores pre-grab transform) / deselect |
| R1 + B | delete selection (grabbed or not) |
| X | delete selection |
| Y | toggle playtest |
| Start | quick save |
| Back | load map |
| Guide | menu (reserved) |

Shifted set (R1 held) — grab & utilities (grab = camera frozen, sticks drive the object; shift switches both sticks to their second job):

| Input | Action |
|---|---|
| LS | grabbed object height (Y only — push up lifts, X dead) |
| RS X | roll the grabbed object (alone — Y dead) |
| RS Y | (nothing while shifted) |
| D-pad | catalog panel (unchanged — browse while grabbed) |
| A | drop grab (keeps transform, deselects, unfreezes) |
| B | cancel grab (restores pre-grab transform) — R1+B deletes instead |
| X | delete selection (grabbed or not) |
| Y | toggle snap (reserved) |

### Grabbed object, unshifted (camera frozen — the sticks drive the object)

| Gamepad | Keyboard | Action |
|---|---|---|
| LS | WASD | move on the ground plane (camera-relative) |
| RS | mouse motion | yaw (X) + pitch (Y) |
| A | E | drop grab (keeps transform, deselects, unfreezes) |
| B | Q | cancel grab (restores pre-grab transform) |
| R1+B | Shift+Q | delete selection (grabbed or not) |

## Keyboard mapping (editor profile)

The keyboard mirrors the gamepad action set 1:1 with **no click or drag**:
**WASD pans the camera** like the LS (pitch included), **mouse motion orbits**
like the RS (in place, RS direction), **arrows browse the catalog panel** like
the D-pad, **E confirms** like A. While grabbed (camera frozen) the same inputs
drive the object: WASD moves, mouse turns, Shift+WASD sets the height
(W up), Shift+mouse rolls. Shift is the keyboard R1 (editor only); E is pure
confirm, never a modifier. UI buttons are deliberately **not mouse-clickable** (and not
keyboard-focusable) so panel input never fights the mouse; the `MapName`
LineEdit keeps normal text focus.

| Action | Key |
|---|---|
| camera pan (LS) | WASD |
| camera orbit (RS) | mouse motion (no click) |
| catalog prev / next | Up / Down arrows |
| category tab prev / next | Left / Right arrows |
| confirm at the crosshair (grab red / place green) | E |
| grabbed: move object (LS) | WASD (Shift+WASD = height, W up) |
| grabbed: yaw + pitch object (RS) | mouse motion (Shift+mouse X = roll alone) |
| grabbed: drop (A) / cancel (B) / delete (R1+B) | E / Q / Shift+Q |
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