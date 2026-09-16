# SoulMaker — Worklog & current state

**Updated**: 2026-09-16

## Current thread

- **Objective**: P1 map editor — continue building the maker loop (post-input-layer)
- **Expected mode**: edit
- **Next step**: make the d-pad select catalog assets (gamepad asset browsing) — `catalog_panel.cycle_next/cycle_prev` already exist and are wired to `catalog_next/catalog_prev` actions in `_on_input_action`, but those actions have no d-pad mapping in `InputManager.PROFILES` yet; add `panel_left/right` (or d-pad up/down) to the profile.
- **Last step done**: editor cleaned up — ToolBar and TransformPanel removed (scene + script), save uses `current_map_name`, layout offsets zeroed, mouse HIDDEN in editor / CAPTURED in playtest with the fly-camera click-capture gated on `current`. Headless run of the scene passes.

## Test recipe (human)

1. Launch `scenes/editors/map_editor.tscn` (or `main.tscn`).
2. Keyboard/mouse: at launch, arrows pan the camera and plain mouse motion orbits it (no click/drag) — directions must match the gamepad 1:1 (mouse right = RS right, mouse up = RS up). Wheel zooms. **New: MOUSE_SCALE=0.14 and ORBIT_SENS=220 are the tuning knobs** — expected feel is unchanged from before this refactor; report zoom/orbit speed and direction if they drift. S save (current_map_name), P playtest, Delete; clicking any catalog button must NOT change arrow behavior (no focus steal).
3. Gamepad: LS pans, RS orbits, LT/RT zoom; LB/RB cycle a highlighted catalog entry; A places the current entry (or selects under crosshair); B deselect; D-pad nudges selected; L3 fine; R1+D-pad nudge Y; Y playtest (LS moves, Y exits); Start quick-save.
4. Report: any action not responding, unexpected double-action (e.g. arrows panning + nudging), and the DebugLabel state.

## Open items / waiting on you

- Gamepad live test on the map editor (recipe above).
- Restart opencode to pick up `agent.build.steps 25→60` (config loaded at startup).
- Deferred spikes: ShapeCast3D (REPORTED), Foot IK + Upper/lower (FAIL).

## Status snapshot

- **P0 complete** ✓ — spikes (retarget ✓, markers ✓, Foot IK ❌, Upper/lower ❌, ShapeCast3D ⏭ REPORTED), schemas v0.1 + versioning, `decisions.md` (ADR), repo structure + naming conventions, autoload `GameState`.
- Next phase: **P1 — map editor vertical slice** (the core maker loop). Input layer (keyboard+gamepad, data-driven) shipped 16/09/2026.
