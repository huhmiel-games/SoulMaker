# Editor input mapping (P1)

Resolved 16/09/2026 — keyboard AND gamepad usable in the map editor. The
mapping is **data-driven**: rebinding edits one dictionary
(`src/autoloads/input_manager.gd`), never scattered across editor scripts.

## Principles

- **Device parity is the standing rule** (see `AGENTS.md` `## Input`):
  keyboard/mouse and gamepad are the same logical device. The gamepad's
  limited set is the source of truth — the keyboard mirrors it 1:1, chords
  included (R1-pad / Shift-key, editor only), no keyboard-only actions. Every
  action resolves through a named `InputManager` action; the mouse selects
  nothing, it only orbits.
- **No modal modes.** The gamepad uses a single **shift modifier** (R1,
  Shift-key in the editor) to double the button set instead of switching
  explicit modes. E is pure confirm, never a modifier. Confirm (A/E) is
  contextual on the crosshair — grab red, place green — identically on every
  device. Free transform of placed objects is grab & move (Minecraft-style
  direct manipulation), not gizmos, by decision.
- Gamepad does the **fast loop** (camera + place + grab + save); the keyboard
  mirrors it key for key.
- The mapping lives in `InputManager.PROFILES`, one profile per context
  (`editor`, `playtest`; the map menu reuses the editor profile with
  menu-local meanings). Editor scripts only reference action names via
  `InputManager.is_pressed(...)`, `action_pressed` / `action_released`
  signals, or the analog getters.

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
| R1 + B | delete placement (grabbed or not) — the ONLY placement-delete path |
| L1 | snap toggle: grid position (0.1 m, base on grid) + angles (15°) while grabbed |
| X | (unbound in editor — future use) |
| Y | toggle playtest |
| Start | quick save |
| R1 + Start | rename (mapped, not consumed yet — rename feature deferred) |
| LT / RT | (unbound in editor — future scale candidate) |
| Guide | back to map menu (auto-saves first) |

### The 3 editor states (place ≠ hold)

| State | Camera | Sticks | How to get there |
|---|---|---|---|
| IDLE | live | drive the camera | boot, or drop/cancel/delete |
| SELECTED | live | drive the camera (object only highlighted) | place an asset, or aim red (SelectionBox shows, nothing held) |
| GRABBED | **frozen** | drive the object (crosshair hidden, HUD mapping) | explicit 2nd A/E confirm on red |

Out of GRABBED: A/E drops (keeps transform), B/Q cancels (restores), R1+B / Shift+Q deletes. Placing never grabs by itself — holding is always an explicit 2nd confirm.

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
| Y | (nothing while R1 held) |

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
confirm, never a modifier. UI buttons are deliberately **not mouse-clickable**
(and not keyboard-focusable) so panel input never fights the mouse.

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
| snap toggle (L1) | Tab |
| aim feedback | crosshair, centered on the viewport (green = empty space, red = placed asset) |
| mouse click (panel or viewport) | *(nothing — parity: the mouse only orbits, selection is arrows/D-pad + A/E)* |
| delete placement | Shift+Q (the only path — no Delete-key shortcut) |
| rename | F2 (mapped, not consumed yet) |
| playtest | P |
| save | S |
| menu | Escape (save + back to map menu) |

## Playtest profile

Fly-cam stand-in until the P2 player controller:

| Action | Gamepad | Keyboard |
|---|---|---|
| move forward / back | LS Y (±) | W / S |
| move left / right | LS X (±) | A / D |
| move up / down | — | Space / Shift |
| toggle playtest | Y | P |

ESC still releases mouse capture in the fly-cam (unchanged).

## Map menu (library: Load / New / Delete)

Boot scene. Reuses the editor profile — arrows/D-pad drive the focused
row list (same physical inputs as catalog browsing, menu-local meaning):

| Action | Gamepad | Keyboard |
|---|---|---|
| move highlight (New row + maps) | D-pad U / D | Up / Down arrows |
| Load highlighted / create (New row) | A | E |
| delete: 1st press arms, 2nd executes | X (button) | Delete key |
| cancel delete-arm | B | Q |
| (B with no arm: inert — no hub yet) | — | — |
| (ESC in menu: inert — nothing above the menu yet) | — | — |

Editor returns here via ESC/GUIDE (`menu` action, auto-saves first).
Rename deferred (needs text entry).

Shared overlay: `scenes/ui/editor_hud.tscn` (`EditorHUD`) — persistent facts
(`set/clear_persistent(key)`, e.g. snap, joined by " · "), temporary notes
(`flash`, 5 s auto-clear, e.g. save), command help (hint); display-only,
mouse ignored. The crosshair stays per-editor by decision. map_menu migrates
to it after.

## Architecture notes

- `InputManager` is an **autoload**; no `class_name` (conflicts with the
  singleton name).
- Sticks/triggers are exposed deadzone-applied (`left_stick()`,
  `right_stick()`, `triggers()`); camera scripts consume them continuously.
- A JSON override of the mapping lands with the Options screen (post-V1 per
  ADR / features §11: keyboard per-key, gamepad bounded rows).
