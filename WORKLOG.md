# SoulMaker — Worklog & current state

**Updated**: 2026-09-17

## Current thread

- **Objective**: P1 map editor — continue building the maker loop (post-input-layer)
- **Expected mode**: edit
- **Next step**: pick the next slice (gizmos transform? reload key? parity doc cleanup?).
- **Last step done**: VERDICT world_3d saga — probes removed, quirk documented in code. Facts: `world_3d` member null despite `own_world_3d=true` (+`using_own=true`); `find`/`cam` resolve the real own world, ≠ main window world (so never query `root.world_3d`); pick via `editor_camera.get_world_3d()` + guard; crosshair red-on-asset confirmed live; SelectionBox fixed to world space. Crosshair recipe: PASSED. Headless import passes. Deferred: free transform (gizmo/move rework), reload key, spawn-fallback sign, first-AABB ground snap, menu scene, ESC cursor release, parity doc cleanup (roadmap l.52/l.246, features.md l.143/l.216, features/09 l.8/l.25, features/11 l.24/l.121, features/14 l.14/l.17, screens.md l.77/l.108/l.192, versioning.md l.20 — idea.txt untouched).

## Test recipe (human) — effective world

1. Launch `scenes/editors/map_editor.tscn`. Copy the `probe worlds:` line (own / find / cam / root / using_own) + any `probe pick` line.
2. Place an asset → SelectionBox on the asset (not center).
3. Aim at the placed asset → red expected. A/E on red selects, on green places.
4. Report: probe worlds line, red/green, SelectionBox, any debugger break.

## Open items / waiting on you

- Live test of the tabbed catalog (recipe above).
- Gamepad live test on the map editor (earlier recipe, overlapping — the D-pad role changed to catalog navigation; object nudge is deferred to the move rework).
- Deferred spikes: ShapeCast3D (REPORTED), Foot IK + Upper/lower (FAIL).

## Status snapshot

- **P0 complete** ✓ — spikes (retarget ✓, markers ✓, Foot IK ❌, Upper/lower ❌, ShapeCast3D ⏭ REPORTED), schemas v0.1 + versioning, `decisions.md` (ADR), repo structure + naming conventions, autoload `GameState`.
- Next phase: **P1 — map editor vertical slice** (the core maker loop). Input layer (keyboard+gamepad, data-driven) shipped 16/09/2026; catalog panel tabbed by category 17/09/2026; camera zoom removed 17/09/2026.
