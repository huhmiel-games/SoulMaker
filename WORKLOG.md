# SoulMaker — Worklog & current state

**Updated**: 2026-09-17

## Current thread

- **Objective**: P1 map editor — continue building the maker loop (post-input-layer)
- **Expected mode**: edit
- **Next step**: human live test of the tabbed catalog (recipe below); then continue the maker loop (floor/ambiance presets, toon shader ADR-019, drag & drop).
- **Last step done**: catalog panel now tabbed by asset `category` — the tab bar shows the full schema taxonomy (empty categories included, so tab navigation is testable before the catalog is multi-category). D-pad/arrows Up/Down cycle assets within the active tab (`catalog_next/prev`), Left/Right switch tabs (`tab_next/prev`); the default tab is the first populated one. Camera zoom removed (molette/triggers redondants — commit `f91f94b`). Headless import passes.

## Test recipe (human)

1. Launch `scenes/editors/map_editor.tscn` (or `main.tscn`).
2. Keyboard/mouse: WASD pans, plain mouse motion orbits, wheel does nothing (zoom removed). Left/Right arrows switch the category tab at the top of the panel, Up/Down cycle the highlighted asset within the tab, A/S (or click a tab button / asset button) selects. S save (current_map_name), P playtest, Delete; clicking any catalog/tab button must NOT change arrow behavior (no focus steal).
3. Gamepad: LS pans, RS orbits; D-pad Up/Down cycle the highlighted catalog entry, Left/Right switch category tab; A places the current entry (or selects under crosshair); B deselect; Y playtest (LS moves, Y exits); Start quick-save.
4. **Tab bar = the full schema taxonomy (9 tabs, empty ones included)** — ←/→ navigation can be tested immediately: Nature is empty, Arch has the 6 dungeon assets, the rest are empty. Switching to an empty tab clears the list and `current_id` (A then reports "no catalog entry to place"). The only populated working tab is Arch.
5. Report: any action not responding, unexpected double-action (e.g. arrows panning + cycling), the DebugLabel state, tab-bar visual (buttons visible, active highlighted).

## Open items / waiting on you

- Live test of the tabbed catalog (recipe above).
- Gamepad live test on the map editor (earlier recipe, overlapping — the D-pad role changed to catalog navigation; object nudge is deferred to the move rework).
- Deferred spikes: ShapeCast3D (REPORTED), Foot IK + Upper/lower (FAIL).

## Status snapshot

- **P0 complete** ✓ — spikes (retarget ✓, markers ✓, Foot IK ❌, Upper/lower ❌, ShapeCast3D ⏭ REPORTED), schemas v0.1 + versioning, `decisions.md` (ADR), repo structure + naming conventions, autoload `GameState`.
- Next phase: **P1 — map editor vertical slice** (the core maker loop). Input layer (keyboard+gamepad, data-driven) shipped 16/09/2026; catalog panel tabbed by category 17/09/2026; camera zoom removed 17/09/2026.
