# SoulMaker — Worklog & current state

**Updated**: 2026-09-17

## Current thread

- **Objective**: P1 map editor — continue building the maker loop (post-input-layer)
- **Expected mode**: edit
- Next step: human check (import) + visual HUD recipe (below); map_menu HUD migration AFTER.
- **Last step done**: EditorHUD v2 (persistent registry + toast + hint): `set/clear_persistent(key)` joined by " · " (future-proof for more permanent facts), `flash(msg, 5s)` with anti-stale seq, `set_status` removed. map_editor: snap = persistent "SNAP ON/OFF" (no angles); save 4 sites = log + toast (SNAP survives); GRAB_HINT drops values-prefix, gains "L1/Tab snap". tscn: ToastLabel above status (green tint), mouse_filter=2 restored on labels (were eating clicks). Deferred: map_menu migration, rename, face-link snap, scale, spawn-fallback sign, first-AABB ground snap, nudge dead-code cleanup.

## Test recipe (human) — map menu round-trip

1. Launch the project (boots the menu, not the editor). Arrows/D-pad move the highlight (first row = New).
2. A/E on New → `untitled_01`, straight into the editor (empty map). Place 2 assets, S save, ESC → auto-saves + back to menu, map listed.
3. A/E on the map row → editor reopens WITH the 2 assets (reload works!).
4. X on the row → armed red text ("DELETE ? X / B") → B cancels → X, X deletes (row gone, neighbor selected).
5. Gamepad only, then keyboard only: strict 1:1. Report: rows, highlight, prints, any break.

## Open items / waiting on you

- Live test of the tabbed catalog (recipe above).
- Gamepad live test on the map editor (earlier recipe, overlapping — the D-pad role changed to catalog navigation; object nudge is deferred to the move rework).
- Deferred spikes: ShapeCast3D (REPORTED), Foot IK + Upper/lower (FAIL).

## Status snapshot

- **P0 complete** ✓ — spikes (retarget ✓, markers ✓, Foot IK ❌, Upper/lower ❌, ShapeCast3D ⏭ REPORTED), schemas v0.1 + versioning, `decisions.md` (ADR), repo structure + naming conventions, autoload `GameState`.
- Next phase: **P1 — map editor vertical slice** (the core maker loop). Input layer (keyboard+gamepad, data-driven) shipped 16/09/2026; catalog panel tabbed by category 17/09/2026; camera zoom removed 17/09/2026.
