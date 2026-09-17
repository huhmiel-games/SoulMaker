# SoulMaker — Worklog & current state

**Updated**: 2026-09-17

## Current thread

- **Objective**: P1 map editor — continue building the maker loop (post-input-layer)
- **Expected mode**: edit
- **Next step**: human live test of the parity pass (recipe below).
- **Last step done**: AGENTS.md gained a standing **device-parity rule** (new `## Input` section, project-wide: editors + game — no device branching, no catalog drag & drop, no OS file-drop import, file-picker only). Pending doc cleanup from that decision: roadmap l.52/l.246, features.md l.143/l.216, features/09 l.8/l.25, features/11 l.24/l.121, features/14 l.14/l.17, screens.md l.77/l.108/l.192, versioning.md l.20, editor_input_mapping.md l.12 (idea.txt untouched, archive). Earlier: parity pass (panel display-only, A/E always places, click-select removed — Jolt crash gone by construction) + monotonic `_next_iid`. Headless import passes. Deferred: selection of placed objects (gizmo/move rework), reload key, spawn-fallback sign, first-AABB ground snap, menu scene.

## Test recipe (human) — parity + iid

1. Launch `scenes/editors/map_editor.tscn`.
2. Clicks do nothing: clicking panel asset rows, tab buttons, or the 3D viewport must NOT place, switch tabs, or select. No debugger break on any click.
3. Keyboard only: arrows ←/→ switch tabs, ↑/↓ cycle assets, E places at the spawn point. B/Q = no-op.
4. Gamepad only: D-pad ←/→ tabs, ↑/↓ cycle, A places. Same behavior as keyboard, 1:1.
5. iid check: place 3 assets (`inst_0000…0002`), Delete one, place again → new id never reused. S saves without SAVE ISSUES.
6. Report: any click having an effect, any debugger break (esp. `direct_space_state`), the spawned ids, DebugLabel state.

## Open items / waiting on you

- Live test of the tabbed catalog (recipe above).
- Gamepad live test on the map editor (earlier recipe, overlapping — the D-pad role changed to catalog navigation; object nudge is deferred to the move rework).
- Deferred spikes: ShapeCast3D (REPORTED), Foot IK + Upper/lower (FAIL).

## Status snapshot

- **P0 complete** ✓ — spikes (retarget ✓, markers ✓, Foot IK ❌, Upper/lower ❌, ShapeCast3D ⏭ REPORTED), schemas v0.1 + versioning, `decisions.md` (ADR), repo structure + naming conventions, autoload `GameState`.
- Next phase: **P1 — map editor vertical slice** (the core maker loop). Input layer (keyboard+gamepad, data-driven) shipped 16/09/2026; catalog panel tabbed by category 17/09/2026; camera zoom removed 17/09/2026.
