# 09 — Editors (Create)

> The entire product: "the maker IS the product". All editors share UX, gizmos, catalog, instant playtest, save/export/import. Neutral spec — status lives in `features.md`.

## Shared editor shell

**Goal** — one coherent editing language across map/prefab/world/character/dialogue.
**Behaviors** — shared left/top toolbars; catalog panel (arrows/D-pad browse + A/E place, no drag & drop); world/selection views; undo/redo; validation banner; in-editor help; consistent shortcuts; instant **playtest toggle** (editor ↔ player in one key).
**Parameters / bounds** — toolbar/undoredo uniform across editors.
**Data / JSON** — editor state separate from game data (auto-save edits vs run saves).
**Interactions** — individual editor specs below.
**Sources** — idea.txt 296-304, 683-688.

## Home hub (two doors)

**Goal** — Play (consume) / Create (produce), contextual Continue per door, transverse actions (Options, Credits, Quit) in a corner.
**Behaviors** — Play → Continue run · New game · Load · World library; Create → the four editors in cascade order (prefab → map → world); each door keeps its own "Recent". Import split by nature: world → Play; prefab/character config → Create.
**Data / JSON** — Continue = last run / last edited project pointer.
**Interactions** — `11_ui`, per-editor specs below.
**Sources** — decisions 12/09, screens Home.

## Map editor

**Goal** — build a map from prefabs/raw assets, anti-grid.
**Behaviors** — orbit/zoom editing camera; **free transform gizmos** (translate/rotate/scale, snap off by default, fine snap 0.1); catalog browse + place (arrows/D-pad + A/E, no drag & drop); selection/move/copy/delete; **undo/redo**; save/load (JSON); **instant playtest** (one key); ambiance override per map; floor + ambiance presets; bounded directional sun with elevation bounds; embedded lights; ground-attach hint; live **light-count counter**.
**Data / JSON** — map placements + world refs.
**Interactions** — `06`, `10` catalog, `07` objects.
**Edge cases** — snapshot/auto-recover on crash (editor state).
**Sources** — idea.txt 296-358, 683-736; roadmap P1.

## Prefab editor

**Goal** — save reusable groups of assets.
**Behaviors** — miniature of the map editor (same gizmos, same panel); select several → group → name → save as prefab; preview thumbnail; delete (confirm).
**Data / JSON** — prefab set (list of asset ids + transforms).
**Interactions** — map editor, catalog.
**Sources** — idea.txt 330, roadmap P1.

## World editor (graph, sockets, ambiance)

**Goal** — assemble maps into a world and connect them.
**Behaviors** — world graph view (map nodes + socket links); add/remove maps; create/edit sockets; place spawn points; set world ambiance (sun/fog/tonemapping) + per-map override; set world display overrides (labels only — `stat_names`, `currency_name`, `accessory_name`, `03`); playtest the whole world from a spawn point; **export the world** (the sharing unit).
**Data / JSON** — composed world file.
**Interactions** — `06` world graph, `14` export.
**Sources** — idea.txt 2500-2529; screens World editor (P6).

## Character editor (player / NPC / enemy, shared base)

**Goal** — the part-mixer: creators assemble from catalogs, never model.
**Behaviors** — 3D preview; base template; attachment slots (hair, ears, equipment); **clothing slot (outfit texture set — painted layer, `02`/`04`); armor overlay preview** (4 sockets shown on the rig; armor is an in-game item, not set here — P8); bounded morph sliders (linked groups); geometric face sculpt + palette; preset gallery; **exportable character config** (JSON) with graceful fallback (`02`); same base for player/NPC/enemy; NPC binds a dialogue, enemy binds behavior pattern + drops (`04`/`05`).
**Data / JSON** — character config, NPC config, enemy config (shared schema `data/schema/character_v0.1.json`).
**Interactions** — `02` full character spec, `03` starting template, New game flow.
**Sources** — idea.txt 883-935, 525-557; roadmap P4.

## Dialogue editor

**Goal** — first-class conversation authoring for non-developers.
**Behaviors** — node graph of line/choice/conditional/exit; inline `+ new flag`; effects as menu verbs; **validation in-editor** (broken gotos, orphan flags, near-miss typo hints).
**Data / JSON** — dialogue resource, split dialogues/nodes.
**Interactions** — `08` narrative spec.
**Sources** — idea.txt 1730-1871, 1908, 1945.

## Enemy behavior editor

**Goal** — data-driven state machine + behavior sliders (no scripting).
**Behaviors** — state nodes (idle/patrol/chase/windup/attack/recover) + slider parameters (aggression, telegraph duration, poise, cadence); trigger conditions from the `08` grammar; playtest with a simulated player.
**Data / JSON** — behavior pattern resource (reusable).
**Interactions** — `05` enemy spec, `04` drops.
**Sources** — idea.txt 100, 496; roadmap P2/P9.

## Boss editor (vault)

**Goal** — phase-based boss authoring (post-V1).
**Behaviors** — state machine with phases, phase transitions via conditions, per-phase pattern sets; fairness preview (simulated player).
**Data / JSON** — boss config (phases + transitions).
**Sources** — idea.txt 102, 108, 496-500.

## Editor light budget counter

**Goal** — keep creators inside the perf envelope, visibly.
**Behaviors** — live per-map light count vs cap; trap fluid warnings; red when over.
**Interactions** — `06` embedded lights, `15` perf.
**Sources** — idea.txt 358, 736.

## Editor validation & error surfacing

**Goal** — catch broken refs while editing, not at export.
**Behaviors** — live validation (flags, dialogue gotos, morph bounds, light budget, unknown asset ids); errors as inline banner with jump-to-owner; warnings softer color; typo hints.
**Interactions** — `08` validation, `14` export validation.
**Sources** — idea.txt 1871, 1908.

## JSON save/load + validation at import (editor + player)

**Goal** — no format debt (ADR-009).
**Behaviors** — all editor assets save as versioned JSON; import validates (schema, bounds, whitelist) — every file treated as untrusted; unknown extra fields tolerated; never silent feature removal; clear "created with version X" message for old worlds.
**Data / JSON** — all formats above.
**Interactions** — `14` distribution/import/export.
**Sources** — ADR-009, idea.txt 1671-1677, 2648-2670.

## Undo/redo

**Goal** — safe trial-and-error.
**Behaviors** — full undo/redo across transform, placement, deletion, live in all editors.
**Data / JSON** — command stack (memory).
**Interactions** — save/export (undo before save).
**Sources** — roadmap P1, screens Map editor.