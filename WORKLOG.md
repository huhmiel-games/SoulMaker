# SoulMaker — Worklog & current state

**Updated**: 2026-09-18

## Current thread

- **Objective**: P2 fighter core — locomotion rewrite body-relative, nodess state machine (Idle/Locomotion/Fall), uncommitted
- **Expected mode**: build
- Next step: human locomotion recipe (below); commit AFTER human OK (not requested yet).
- **Last step done**: lock-on facing mesh (UNCOMMITTED) — `_face_lock` cloue le rig sur le heading du corps pendant LOCKON (plus de profil en strafe orbitale) ; BACKSTEP garde son gel. Boot clean ; feel à valider humain.

## Test recipe (human) — EDIT_FLOOR relief

1. Launch (boots the hub now) → Map editor → library → New (or open a map): ground flat gray as before.
2. Press Y (gamepad) or P (keyboard) → floor mode: HUD shows `FLOOR (__,__) h=+0.0` + hint line, crosshair hidden, flat yellow quad = cell cursor.
3. LS/WASD moves the cursor (coords update in HUD). RS up (or Shift+W) raises the hovered cell in 0.5 m steps — a mound grows; RS down digs a pit (down to −8, up to +8, stops at bounds).
4. A/E → toast "floor checkpoint"; sculpt more elsewhere; B/Q → relief snaps back to the checkpoint (toast); Y/P exits (relief kept, crosshair back).
5. Start (or ESC) → pause modal: SAVE → toast + stays in editor; CANCEL → resumes; QUIT (clean) → back to library; reopen → relief + placements back (report if not).
6. Place an asset on a mound → it sits on the relief; grab + move it → its base follows the relief.
7. Relief judged visually (slopes get walked by the real walker at P2, via the editor ⇄ game round-trip).
8. Report: sculpt feel (cursor/height rates too fast/slow?), any visible hitch while holding height, all `[MapEditor]` log lines, relief after reload.

## Test recipe (human) — locomotion step 1 (body-relative rewrite)

Scene: run `scenes/tests/player_controller_test.tscn` (boots straight in, game profile, mouse captured).
1. Boot: log shows `[Player] ready — profile game, body-relative, nodess SM` (+ `[SM] Idle -> Fall -> Idle` only if spawn drops — snap 1.0 normally sticks the landing silently). Character faces AWAY from camera (report if it moonwalks = rig authored -Z, one-line fix).
2. Idle: mouse orbits the camera around the character (both axes, pitch clamped). Character does not turn.
3. Z (étiqueté, = W physique) → `Locomotion`: camera snaps behind, character runs forward (8 m/s, `running`). Release in 1 s with no input → back to `Idle`. Q/D (A/D physiques) strafe left/right — the RIG turns sideways, the body keeps its heading.
4. While running: mouse-X / RS-X TURNS the body (no camera orbit); pitch still live. Tilt LS partiel → `walking` (2.5 m/s), full → `running`.
5. Ramp (right side): climb without sliding; walk off its edge → `Fall` → lands → `Idle`/`Locomotion`.
6. Label top-left: state + speed + floor + anim + profile + raw. Report feel (turn rate? accel? sneak/run thresholds? camera distance?) + all `[Player]`/`[SM]`/`[RigKit]` lines.

## Test recipe (human) — base toon (the look locks here)

1. Open a map with placed assets (dungeon kit): everything 3D renders stepped-cel (banded light/shadow, rim on edges). Relief too. HUD/crosshair/ring/selection = standard (gizmos excluded by decision).
2. Judge cuts/wrap/steepness on YOUR assets (you know flexible_toon): shadow bands clean or muddy? Rim too strong? `shade` defaults to black (= legacy look); lift/tint only if a night/dungeon asks for it. Report values to freeze or adjust.
3. Ambiance cross-check: Dungeon preset + toon = readable (not pitch black)? Clear day + toon = not blown out? Ambient energy still lights (ambient_light_disabled stayed OFF)?
4. Reload the map → toon persists on all placements (override per surface, textures intact).
5. Report: screenshots-worth description (no image input on my side), any `[MapEditor]` error lines, which uniform defaults to freeze.

## Test recipe (human) — ambiance page

1. Boot the editor: viewport looks as before (defaults = old tres + fog off).
2. Start → pause now has 4 rows (SAVE / AMBIANCE / CANCEL / QUIT). AMBIANCE → page titled `AMBIANCE (Default)`: 5 preset rows, 10 value rows, BACK.
3. A/E on `Preset: Dungeon` → viewport goes dark/foggy, title becomes `AMBIANCE (dungeon)`. ←/→ on `Fog depth end` → fog visibly moves; row text updates. A/E on the row → resets to the dungeon value.
4. Adjust anything → title flips to `AMBIANCE (Custom)`. BACK (or B) → pause. QUIT on a dirty map → confirm (ambiance edits count as edits).
5. SAVE → reopen the map → override kept (same look). New map without section → defaults.
6. Report: preset feel (dungeon/misty readable?), adjust steps too coarse/fine?, all `[MapEditor]` lines.

## Test recipe (human) — pause modal

1. In the editor (clean map): Start → `MAP PAUSED` (SAVE / CANCEL / QUIT). CANCEL (or B, or Start again) resumes.
2. SAVE → toast "saved …", stays in editor. Edit (place/move/sculpt) → Start → QUIT → `UNSAVED CHANGES` (QUIT WITHOUT SAVING / CANCEL). CANCEL returns to the pause; WITHOUT SAVING returns to the library without saving.
3. Clean map → QUIT quits directly (no confirm).
4. Grab an asset (or enter floor mode) → Start → pause opens, state kept; CANCEL resumes grab/floor intact.
5. Report: modal readable over the scene, every `[MapEditor]`/`[Menu]` log line, any input leaking through (camera moving behind the modal = bug).

## Test recipe (human) — map menu round-trip

1. Launch the project (boots the menu, not the editor). Arrows/D-pad move the highlight (first row = New).
2. A/E on New → `untitled_01`, straight into the editor (empty map). Place 2 assets, Start → SAVE, Start → QUIT → back to menu, map listed.
3. A/E on the map row → editor reopens WITH the 2 assets (reload works!).
4. X on the row → armed red text ("DELETE ? X / B") → B cancels → X, X deletes (row gone, neighbor selected).
5. Gamepad only, then keyboard only: strict 1:1. Report: rows, highlight, prints, any break.

## Open items / waiting on you

- Live test of the tabbed catalog (recipe above).
- Gamepad live test on the map editor (earlier recipe, overlapping — the D-pad role changed to catalog navigation; SELECTED-state arrow-nudge was dead code and is deleted: arrows browse, grab moves).
- Deferred spikes: ShapeCast3D (REPORTED), Foot IK + Upper/lower (FAIL).

## Status snapshot

- **P0 complete** ✓ — spikes (retarget ✓, markers ✓, Foot IK ❌, Upper/lower ❌, ShapeCast3D ⏭ REPORTED), schemas v0.1 + versioning, `decisions.md` (ADR), repo structure + naming conventions, autoload `GameState`.
- Next phase: **P1 — map editor vertical slice** (the core maker loop). Input layer (keyboard+gamepad, data-driven) shipped 16/09/2026; catalog panel tabbed by category 17/09/2026; camera zoom removed 17/09/2026.
