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
- **Explicit states, one grammar**: the editor has 4 states (IDLE / SELECTED /
  GRABBED / EDIT_FLOOR) — no gizmos, no menus. Each state re-targets the
  sticks (frozen camera when they drive something else), and **A always
  validates, B always cancels**, so learning one state teaches them all.
  E is pure confirm, never a modifier. Confirm (A/E) is contextual on the
  crosshair — grab red, place green — identically on every device. Free
  transform of placed objects is grab & move (Minecraft-style direct
  manipulation), not gizmos, by decision.
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
| Y | EDIT_FLOOR toggle (sculpt the ground relief) |
| Start | pause menu (SAVE / CANCEL / QUIT modal) |
| R1 + Start | rename (mapped, not consumed yet — rename feature deferred) |
| LT / RT | (unbound in editor — future scale candidate) |
| Guide | pause menu, same as Start |

### The 4 editor states (place ≠ hold)

| State | Camera | Sticks | How to get there |
|---|---|---|---|
| IDLE | live | drive the camera | boot, or drop/cancel/delete |
| SELECTED | live | drive the camera (object only highlighted) | place an asset, or aim red (SelectionBox shows, nothing held) |
| GRABBED | **frozen** | drive the object (crosshair hidden, HUD mapping) | explicit 2nd A/E confirm on red |
| EDIT_FLOOR | **frozen** | drive the relief cursor (crosshair hidden, HUD mapping) | Y/P toggle |

Out of GRABBED: A/E drops (keeps transform), B/Q cancels (restores), R1+B / Shift+Q deletes. Placing never grabs by itself — holding is always an explicit 2nd confirm.
Out of EDIT_FLOOR: A/E checkpoints (stays in mode), B/Q undoes to checkpoint (stays), Y/P exits (keeps relief). R1+B / Shift+Q inert — relief cells are not placements.

Shifted set (R1 held) — grab & utilities (grab = camera frozen, sticks drive the object; shift switches both sticks to their second job):

| Input | Action |
|---|---|
| LS | grabbed object height (Y only — push up lifts, X dead) |
| RS X | roll the grabbed object (alone — Y dead) |
| RS Y | (nothing while shifted) |
| D-pad | catalog panel (unchanged — browse while grabbed) |
| A | drop grab (keeps transform, deselects, unfreezes) |
| B | cancel grab (restores pre-grab transform) — R1+B deletes instead |
| X | (nothing — unbound in editor) |

### EDIT_FLOOR (camera frozen — the sticks drive the relief)

Ground relief: 1 m cells over the 100×100 slab, [−8, +8], sparse in the map
file (flat when absent). Sculpt is continuous-additive, plugin style: holding
the height input grows a cosine-falloff hill (trails while traveling paint
ridges, as intended); memory holds floats, files quantize to 0.001 at save.
Cursor starts under the crosshair ray on entry (slab center if aimed at the
sky); a ground ring shows the brush disk. Single gentle strokes stay walkable
slopes; gaps render as steep unclimbable faces. Spawn raycast, grab clamps
and the save file all follow the relief.

| Gamepad | Keyboard | Action |
|---|---|---|
| LS | WASD | move the cell cursor (camera-relative, like grab) |
| RS Y | mouse Y motion, Shift+WASD | sculpt ±1.0 m/s at disk center (W/up raises, trails active) |
| RS X | mouse X motion, Shift+A-D | brush radius 0..6, default 2 (D/right grows) |
| A | E | checkpoint (stays in mode — A keeps going) |
| B | Q | undo to checkpoint (stays in mode) |
| Y | P | exit mode (keeps relief) |
| R1+B | Shift+Q | (nothing — relief cells are not placements) |

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
| floor mode (Y) | P |
| save | *(nothing direct — SAVE lives in the pause menu)* |
| pause menu | Start, or Escape / Guide (same gesture — S stays WASD-only: sharing it opened the pause on every pan-back) |
| menu | *(merged into pause menu — same as above)* |

## Game profile (frozen, consumed at P2)

The in-editor fly playtest is deleted (2026-09-18): it noclipped through
everything it was supposed to validate (collisions, walkable slopes), so it
was a duplicate of the future game in worse. The maker loop at P2 becomes
editor ⇄ game on the current map (symmetric `pending_map` handover), and
slopes get walked by the real walker. Until then relief is judged visually.

`InputManager.PROFILES["game"]` holds the frozen game table below —
defined but NOT consumed (mapped-not-consumed, `rename` precedent).
`src/cli_tools/input_audit.gd` validates it headless (bindings unique per
profile, pad+key coverage per capability, consumers name real actions, zero
raw `Input.*` outside `input_manager.gd`). Layout (features/11 wins over
DS3 PC where they conflict, DS3 fills the gaps):

| Action | Gamepad | Keyboard |
|---|---|---|
| move | LS (tilt = walk/run) | WASD (no keyboard walk — Alt is offhand) |
| camera orbit | RS | mouse motion |
| dodge / sprint (tap = roll/backstep, hold+move = dash; jump = sprint+dodge, consumer-side) | B | Space |
| light attack | R1 | LMB |
| heavy attack | R2 (trigger, past half pull) | RMB, or Shift+LMB |
| guard (hold) | L1 | Shift held |
| offhand skill / parry | L2 (trigger) | Alt+RMB (both fire with heavy's RMB — consumer prioritizes, mod wins) |
| two-hand / use item / interact | Y / X / A | F / R / E |
| spells / items / right-hand / left-hand | D-pad | arrows |
| quickbar cycle | — (mirror-only: re-exposes the d-pad capability) | Q (consumed with the quickbar at P8) |
| lock-on (tap) | R3 | middle mouse |
| menu | Start + Guide | Esc |
| gestures | Select | G (mapped-not-consumed) |

Abandoned DS3 rows: RMB block, RMB/Shift+RMB left-hand use, Alt walk,
Q cancel in game, X sort (→ P8). Known limitation: the pad's left-hand
context (L1-tap) has no keyboard mirror — features/11 lists none; settled
at the P3 design pass, never by adding a key.

Resolution rules (in the header of `input_manager.gd`): actions are
source-lists, OR-ed. Keys match shift-blind and mod-blind (chords redirect
consumer-side: Shift+Q lands on deselect, the handler deletes). Buttons,
mouse and triggers are shift-aware (`shifted` == `is_shifted()`, optional
`mod` key). Edges emit centrally from `_process`, so keys/pad/mouse/
triggers share one timing. `is_shifted()` = R1-pad in editor only (R1 taps
attack in game) + Shift-key in every profile. B mirrors per profile
(Q in editor/menus, Space in game); movement keys ignore Shift
(holding Shift to pre-arm a strong never stops WASD).

## Generic menu (hub, library, all future menus)

One behavior (`src/ui/generic_menu.gd` + `scenes/ui/generic_menu.tscn`),
data-driven entries (`open` / `quit` / `new` / `load` / `can_delete`);
subclasses only supply title, hint, entries and delete. Display-only rows,
never clickable: arrows/D-pad move, A/E confirms, X arms/confirms delete on
deletable rows (2nd press executes, red highlight while armed), B cancels the
arm, ESC inert. Feedback = log + HUD toast.

| Action | Gamepad | Keyboard |
|---|---|---|
| move highlight | D-pad U / D | Up / Down arrows |
| confirm (open / load / new) | A | E |
| delete: 1st press arms, 2nd executes | X | Delete key |
| cancel delete-arm | B | Q |
| (X on non-deletable rows: "nothing to delete here") | — | — |
| (ESC anywhere in a menu: inert) | — | — |

## Main hub (SOULMAKER: entries to editors)

Boot scene. Entries: Map editor → map library, EXIT → quit the game
directly (nothing above the hub). More editors append entries in
`src/ui/main_menu.gd`. Routing note: the editor returns to the map
library via the pause QUIT (dirty → quit-confirm) — hub-as-back-target
comes later, with more editors.

## Pause modal (map editor: SAVE / CANCEL / QUIT)

`ModalDialog` (`src/ui/modal_dialog.gd` + `scenes/ui/modal_dialog.tscn`) is
the reusable container (dim backdrop + centered panel, zero business
logic); contents are plain `generic_menu.tscn` instances driven by
`GenericMenu.configure(title, hint, entries, on_cancel)` — no
menu-specific scenes ever. Entries carry `"call"`: Callable (confirm
executes it, args frozen with `.bind()` at build time); `on_cancel` runs on
B/Q with no delete-arm pending. Deletable rows add `"can_delete": true` +
`"delete_call"`: Callable (same contract as `_delete_entry(index)`; success
auto-drops the row, `""` toasts failure) — the future library-as-modal case:
`{"label": name, "call": _load_map.bind(name), "can_delete": true,
"delete_call": _delete_map.bind(name)}`. Pause entries: SAVE (saves, closes
on success, stays open on failure), CANCEL (closes, state underneath
intact), QUIT (clean → map library, dirty → swaps in the quit-confirm:
QUIT WITHOUT SAVING / CANCEL-back-to-pause). Start/S and Guide/ESC toggle
the pause (confirm → pause → close); while open the
editor ignores every other input and freezes its edit paths (grab/floor
kept as-is underneath).

## Ambiance page (pause → AMBIANCE)

Settings page, not a preset dropdown: presets are named bundles
(`data/ambiance/presets.json` — clear day / misty dusk / stormy night /
dungeon) that FILL the settings; every setting stays retouchable. Opened
from the pause 4th row (zero new keys, freeze intact); level-3 modal
content like the quit-confirm (BACK / B returns to the pause). Rows:
presets (A applies, page rebuilds with the new title), 10 value rows
(←/→ adjusts at the row step — tab actions, free in modals; A resets to
the preset/default value), BACK. Title shows the match (`AMBIANCE
(dungeon)`) or `Custom` once diverged. Any apply/adjust/reset marks
`_dirty` and owns a map section, so the quit-confirm covers it gratis.

Engine: `MapIO` sparse `ambiance` section (absent = `env_default.tres`;
bounds single-sourced in `AMBIANCE_BOUNDS`, 3-decimal file quants);
`_apply_ambiance()` pushes clamped values to the duplicated `Environment`
(fog DEPTH mode: begin/end/height/density) + `Sun` (elevation keeps the
azimuth) live. P1 set = features/06 (sun elev/expo, fog depth/height,
tonemap, ambient energy) — no colors, no volumetrics, no light counter
(P6 with placeable lights).

## Map menu (library: Load / New / Delete / Back)

`MapMenu extends GenericMenu` (all menu behavior inherited). Rows: `[ + New
map ]` first, map files (deletable) in the middle, `[ ← Back ]` last (opens
the hub, inert to X like New). New creates `untitled_NN` and enters the
editor; Load enters via `GameState editor/pending_map`; the editor returns
here via the pause QUIT (`pause_menu`/`menu` action — clean quits directly,
dirty swaps in the quit-confirm). Rename deferred (needs
text entry).

Shared overlay: `scenes/ui/editor_hud.tscn` (`EditorHUD`) — persistent facts
(`set/clear_persistent(key)`, e.g. snap, joined by " · "), temporary notes
(`flash`, 5 s auto-clear, e.g. save and menu feedback), command help (hint);
display-only, mouse ignored. The crosshair stays per-editor by decision.

## Architecture notes

- `InputManager` is an **autoload**; no `class_name` (conflicts with the
  singleton name).
- Sticks/triggers are exposed deadzone-applied (`left_stick()`,
  `right_stick()`, `triggers()`); camera scripts consume them continuously.
- A JSON override of the mapping lands with the Options screen (post-V1 per
  ADR / features §11: keyboard per-key, gamepad bounded rows).
