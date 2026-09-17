# SoulMaker — Worklog & current state

**Updated**: 2026-09-17

## Current thread

- **Objective**: P1 map editor — continue building the maker loop (post-input-layer)
- **Expected mode**: edit
- **Next step**: human live test of the shift remap (recipe below).
- **Last step done**: grab remap — shift switches both sticks to job 2: R1+LS / Shift+WASD = height only (Y, up lifts, X dead), R1+RS / Shift+mouse = roll alone (Y dead); triggers/Space/R freed (bindings pruned: obj_height, height_up/down, roll_key deleted). E paradox fixed: `is_shifted()` = R1-pad OR Shift-key gated on editor profile (E = pure confirm; playtest Shift=descend pristine); AGENTS.md doctrine hardened (gamepad set is source of truth, keyboard mirrors 1:1 chords included, no keyboard-only actions). Shift+Q = delete (keyboard mirror of R1+B). Earlier: grab & move base. Headless import passes. Deferred: snap toggle, scale (LT/RT freed candidates), menu scene, ESC release, reload key, spawn-fallback sign, first-AABB ground snap.

## Test recipe (human) — shift remap

1. Launch `scenes/editors/map_editor.tscn`. Grab an asset (red + A).
2. Gamepad: R1+LS up/down lifts (X dead); R1+RS X rolls alone (RS Y dead); plain LS/RS unchanged (XZ / yaw+pitch). R1+B deletes; plain B cancels.
3. Keyboard: Shift+WASD W/S height (A/D dead); Shift+mouse X rolls alone; Shift+Q deletes. E pure confirm (no shift weirdness).
4. Playtest: Shift still descends, gamepad buttons all alive while Shift held (no profile leakage).
5. Report: height/roll directions, anything dead, DebugLabel HUD text.

## Open items / waiting on you

- Live test of the tabbed catalog (recipe above).
- Gamepad live test on the map editor (earlier recipe, overlapping — the D-pad role changed to catalog navigation; object nudge is deferred to the move rework).
- Deferred spikes: ShapeCast3D (REPORTED), Foot IK + Upper/lower (FAIL).

## Status snapshot

- **P0 complete** ✓ — spikes (retarget ✓, markers ✓, Foot IK ❌, Upper/lower ❌, ShapeCast3D ⏭ REPORTED), schemas v0.1 + versioning, `decisions.md` (ADR), repo structure + naming conventions, autoload `GameState`.
- Next phase: **P1 — map editor vertical slice** (the core maker loop). Input layer (keyboard+gamepad, data-driven) shipped 16/09/2026; catalog panel tabbed by category 17/09/2026; camera zoom removed 17/09/2026.
