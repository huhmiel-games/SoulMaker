# SoulMaker — Worklog & current state

**Updated**: 2026-09-17

## Current thread

- **Objective**: P1 map editor — continue building the maker loop (post-input-layer)
- **Expected mode**: edit
- **Next step**: pick the next slice (gizmos transform? reload key? parity doc cleanup?).
- **Last step done**: parity doc cleanup DONE — drag & drop purged from roadmap (P1 catalog, P12 file-drop), features.md, features/09/11/14, screens.md, versioning.md, editor_input_mapping.md (re-grep: zero prescriptive mention left; idea.txt archive untouched). Earlier: world_3d verdict (pick via camera effective world + guard, red confirmed live, SelectionBox world-space). Headless import passes. Deferred: free transform (gizmo/move rework), reload key, spawn-fallback sign, first-AABB ground snap, menu scene, ESC cursor release.

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
