# SoulMaker — Worklog & current state

**Updated**: 2026-09-16

## Current thread

- **Objective**: P1 map editor — data-driven input layer (keyboard + gamepad)
- **Expected mode**: edit
- **Next step**: live test the gamepad in `map_editor.tscn` (see test recipe below); then resume P1 unit 1 (undo/redo, gizmos, or save/load polish).
- **Last step done**: InputManager autoload delivered (data-driven action mapping, R1 shift/gesture set, `editor` + `playtest` profiles, analog stick getters); map editor + orbit/fly cameras + catalog panel rewired to actions; gamepad camera/pad/orbit, A-place/select, LB/RB catalog cycle, D-pad nudge, L3 fine, Start save, Y playtest; concept doc `concepts_and_docs/editor_input_mapping.md`. Validated: headless boot of `map_editor.tscn` and `main.tscn` clean (parse OK).

## Test recipe (human)

1. Launch `scenes/editors/map_editor.tscn` (or `main.tscn`).
2. Keyboard regression: S save, L load, P playtest, Delete, arrows nudge, Shift fine, PageUp/PageDown Y — must behave as before.
3. Gamepad: LS pans, RS orbits, LT/RT zoom; LB/RB cycle a highlighted catalog entry; A places the current entry (or selects under crosshair); B deselect; D-pad nudges selected; L3 fine; R1+D-pad nudge Y; Y playtest (LS moves, Y exits); Start quick-save.
4. Report: any action not responding, unexpected double-action (e.g. arrows panning + nudging), and the DebugLabel state.

## Open items / waiting on you

- Gamepad live test on the map editor (recipe above).
- Restart opencode to pick up `agent.build.steps 25→60` (config loaded at startup).
- Deferred spikes: ShapeCast3D (REPORTED), Foot IK + Upper/lower (FAIL).

## Status snapshot

- **P0 complete** ✓ — spikes (retarget ✓, markers ✓, Foot IK ❌, Upper/lower ❌, ShapeCast3D ⏭ REPORTED), schemas v0.1 + versioning, `decisions.md` (ADR), repo structure + naming conventions, autoload `GameState`.
- Next phase: **P1 — map editor vertical slice** (the core maker loop). Input layer (keyboard+gamepad, data-driven) shipped 16/09/2026.
