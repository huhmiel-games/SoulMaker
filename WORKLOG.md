# SoulMaker — Worklog & current state

**Updated**: 2026-09-17

## Current thread

- **Objective**: P1 map editor — continue building the maker loop (post-input-layer)
- **Expected mode**: edit
- **Next step**: user retests snap at 0.1 m / 15° (precision feel on small assets).
- **Last step done**: move speed 4.0 → 2.5 m/s (too twitchy; turn speed kept, snap 0.1 m/15° earlier). Headless import passes. Deferred: face-link snap (phase 2, AABB proximity), scale (LT/RT candidates), menu scene, ESC release, reload key, spawn-fallback sign, first-AABB ground snap.

## Test recipe (human) — snap + mini corridor

1. Launch `scenes/editors/map_editor.tscn`. L1/Tab → "snap ON" print + HUD badge (toggle twice to feel it).
2. Grab a floor tile, snap ON: move it — position sticks to 1.0 grid, base never buries. Rotate — yaw/pitch/roll click at 90°.
3. Toggle mid-grab (small pop expected between snapped/unsnapped — report if violent).
4. Mini corridor: 2 floors edge-aligned + 1 wall yawed 90° against them. Then S save, reload via… (no reload UI yet — report save line only).
5. Report: grid feel (sticky? jumpy?), angle clicks, pop on toggle, knobs (1.0/90° fit the 2 m tiles?).

## Open items / waiting on you

- Live test of the tabbed catalog (recipe above).
- Gamepad live test on the map editor (earlier recipe, overlapping — the D-pad role changed to catalog navigation; object nudge is deferred to the move rework).
- Deferred spikes: ShapeCast3D (REPORTED), Foot IK + Upper/lower (FAIL).

## Status snapshot

- **P0 complete** ✓ — spikes (retarget ✓, markers ✓, Foot IK ❌, Upper/lower ❌, ShapeCast3D ⏭ REPORTED), schemas v0.1 + versioning, `decisions.md` (ADR), repo structure + naming conventions, autoload `GameState`.
- Next phase: **P1 — map editor vertical slice** (the core maker loop). Input layer (keyboard+gamepad, data-driven) shipped 16/09/2026; catalog panel tabbed by category 17/09/2026; camera zoom removed 17/09/2026.
