# SoulMaker — Worklog & current state

**Updated**: 2026-09-16

## Current thread

- **Objective**: P1 map editor — data-driven input layer (keyboard + gamepad)
- **Expected mode**: edit
- **Next step**: live test the mouse/wheel-through-InputManager change in `map_editor.tscn` (recipe below); then resume P1 unit 1 (object-move rework decision, undo/redo, gizmos, or save/load polish).
- **Last step done**: mouse motion and wheel now flow through InputManager like the right stick / triggers — `analog(action)` (stick + mouse_x/y + triggers summed, deadzone policy shared) and `wheel_ticks(action)` (discrete per-frame notches). `orbit_camera.gd` dropped all raw mouse event handling; orbit/zoom poll `PROFILES` entries in `_process`, and the `frozen` gate now covers every source (was mouse-only).

## Test recipe (human)

1. Launch `scenes/editors/map_editor.tscn` (or `main.tscn`).
2. Keyboard/mouse: at launch, arrows pan the camera and plain mouse motion orbits it (no click/drag) — directions must match the gamepad 1:1 (mouse right = RS right, mouse up = RS up). Wheel zooms. **New: MOUSE_SCALE=0.14 and ORBIT_SENS=220 are the tuning knobs** — expected feel is unchanged from before this refactor; report zoom/orbit speed and direction if they drift. S save, L load, P playtest, Delete; clicking any toolbar/catalog button must NOT change arrow behavior (no focus steal). Typing in the map-name field keeps normal caret arrows.
3. Gamepad: LS pans, RS orbits, LT/RT zoom; LB/RB cycle a highlighted catalog entry; A places the current entry (or selects under crosshair); B deselect; D-pad nudges selected; L3 fine; R1+D-pad nudge Y; Y playtest (LS moves, Y exits); Start quick-save.
4. Report: any action not responding, unexpected double-action (e.g. arrows panning + nudging), and the DebugLabel state.

## Open items / waiting on you

- Gamepad live test on the map editor (recipe above).
- Restart opencode to pick up `agent.build.steps 25→60` (config loaded at startup).
- Deferred spikes: ShapeCast3D (REPORTED), Foot IK + Upper/lower (FAIL).

## Status snapshot

- **P0 complete** ✓ — spikes (retarget ✓, markers ✓, Foot IK ❌, Upper/lower ❌, ShapeCast3D ⏭ REPORTED), schemas v0.1 + versioning, `decisions.md` (ADR), repo structure + naming conventions, autoload `GameState`.
- Next phase: **P1 — map editor vertical slice** (the core maker loop). Input layer (keyboard+gamepad, data-driven) shipped 16/09/2026.
