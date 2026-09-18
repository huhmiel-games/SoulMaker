# SoulMaker — Worklog & current state

**Updated**: 2026-09-18

## Current thread

- **Objective**: P1 map editor — ambiance page (pause → AMBIANCE) done, human recipe next
- **Expected mode**: build
- Next step: human ambiance recipe (below); commit AFTER human OK (not requested yet).
- **Last step done**: ambiance settings page (presets JSON + MapIO section + GenericMenu value rows + viewport apply); audit PASS, AMB round-trip PASS, import + editor headless clean.

## Test recipe (human) — EDIT_FLOOR relief

1. Launch (boots the hub now) → Map editor → library → New (or open a map): ground flat gray as before.
2. Press Y (gamepad) or P (keyboard) → floor mode: HUD shows `FLOOR (__,__) h=+0.0` + hint line, crosshair hidden, flat yellow quad = cell cursor.
3. LS/WASD moves the cursor (coords update in HUD). RS up (or Shift+W) raises the hovered cell in 0.5 m steps — a mound grows; RS down digs a pit (down to −8, up to +8, stops at bounds).
4. A/E → toast "floor checkpoint"; sculpt more elsewhere; B/Q → relief snaps back to the checkpoint (toast); Y/P exits (relief kept, crosshair back).
5. Start (or ESC) → pause modal: SAVE → toast + stays in editor; CANCEL → resumes; QUIT (clean) → back to library; reopen → relief + placements back (report if not).
6. Place an asset on a mound → it sits on the relief; grab + move it → its base follows the relief.
7. Relief judged visually (slopes get walked by the real walker at P2, via the editor ⇄ game round-trip).
8. Report: sculpt feel (cursor/height rates too fast/slow?), any visible hitch while holding height, all `[MapEditor]` log lines, relief after reload.

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
