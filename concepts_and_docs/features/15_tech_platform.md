# 15 — Tech & platform

> The engine, the renderer, the format discipline, the perf budgets, the save architecture. Neutral spec — status lives in `features.md`.

## Tech stack (Godot 4.7 + Jolt + GDScript)

**Goal** — a thin, well-known engine base with strong data/custom-pipeline support.
**Behaviors** — Godot 4.7 stable; Jolt physics (jolt enabled in `project.godot`); GDScript for all tooling; no C# required (GDScript-only path); runtime blend shapes, in-game editors via CSG/GridMap/plugins, `.tres`/JSON serialization, threaded loading.
**Data / JSON** — `project.godot` settings (ADR-001).
**Interactions** — every system.
**Sources** — ADR-001, idea.txt 176-204, 578-597.

## Forward+ only (no Compatibility fallback)

**Goal** — one renderer, total.
**Behaviors** — Forward+ exclusively (dev **and** export); **no Compatibility path** (bench 12/09 proved it slower + less stable on the HD4600 at every setting); permanent hardware requirement: **Vulkan required** (no OpenGL).
**Parameters / bounds** — quality tiers serve low-end (below).
**Data / JSON** — `project.godot` renderer.
**Sources** — ADR-002.

## Quality tiers (ADR-002 low-end)

**Goal** — the low-end target (~30 fps stable) via presets, not buried options.
**Behaviors** — render scale, MSAA, shadow quality, per-zone light cap, heavy-feature auto-drop (PCSS, SSAO, volumetrics) based on detected hardware floor; benchmark on real HD4600; Forward+ low ≈ 55 avg / 32 p95 @720p on the 12/09 bench; re-confirm post-skinning + shadows (P2 spike, ADR-019).
**Parameters / bounds** — tier-safe combinations.
**Data / JSON** — settings + auto-detect.
**Interactions** — `06` light cap, `02` char perf, `11` Options.
**Sources** — ADR-002, roadmap P2/P13.

## GameState autoload & serialization

**Goal** — one authoritative run state, versioned, atomic.
**Behaviors** — `GameState` autoload holds: progression (level, stats, currency), inventory/equipment, flags (world state), per-world state (boss, chests, levers, doors, shortcuts), bonfire respawn anchor, orb state; serialized to run JSON; includes metadata (run name, world id, version).
**Data / JSON** — run save format (versioned).
**Interactions** — `03`, `04`, `05`, `07`, `11` (save/load UI).
**Edge cases** — save during a hitstop/socket transition (state is quiescent → safe).
**Sources** — ADR-012, idea.txt 2438, 2519.

## Save integrity & crash recovery (ADR-016)

**Goal** — a crash mid-write never corrupts a run.
**Behaviors** — **atomic save**: write `.tmp` → rename over final (single rename is atomic on same filesystem); deterministic member write order; **validation on load** (schema + bounds); a corrupt run is **quarantined** (moved aside + logged) and the player prompted — never silently wiped; `version` field on every save for forward compatibility.
**Data / JSON** — run save + quarantine dir.
**Interactions** — `03` runs, `11` Load UI.
**Edge cases** — disk full mid-write, interrupted rename across OS.
**Sources** — ADR-016.

## Multiple parallel runs (ADR-015)

**Goal** — several playthroughs per world; New game never overwrites.
**Behaviors** — one folder per world, one subfolder per named run; Load lists per world; run metadata (name, date) user-facing.
**Data / JSON** — run bucket structure.
**Interactions** — `03` runs, `11` Load/New-game UI.
**Sources** — ADR-015.

## JSON public API discipline (ADR-009)

**Goal** — the format is the contract; never break it.
**Behaviors** — schema v0.1 from P0; versioned; tolerant-to-unknown-fields; never silent deletion; clear created-with-X notice; validation treats data as untrusted.
**Data / JSON** — world/character/prefab/dialogue schemas: `data/schema/world_v0.1.json`, `character_v0.1.json`, `prefab_v0.1.json` + `data/schema/versioning.md` (rules, ADR-009); dialogue schema lands at P5 (features/08), same discipline.
**Interactions** — `14`.
**Sources** — ADR-009, idea.txt 2648-2670.

## Loading & streaming (fragments)

**Goal** — swap fragments without reload-scenes mid-game.
**Behaviors** — one active world near origin; proximity streaming with `load_threaded_*`; fragments node-light; logic activated on proximity; no `change_scene_to_file` mid-game; persistent World/Player/UI root.
**Parameters / bounds** — fragment node budget; world bounded near origin (no floating origin).
**Data / JSON** — zone fragment resources.
**Interactions** — `06` streaming, `05` activation.
**Sources** — idea.txt 2410-2447, 2436-2437.

## Physics & hitbox strategy

**Goal** — fair, performant combat rules.
**Behaviors** — swept `ShapeCast3D` per tick on offensive frames only; physics callback clock sync (AnimationMixer `Process Callback = Physics`); broadphase via physics body shapes (Jolt); substepping only on weapon casts; error favors the player; never inflated boss hitboxes.
**Parameters / bounds** — cast length = weapon class; mask ranges per attack.
**Interactions** — `01`, `05`.
**Sources** — idea.txt 2154-2286, 2294-2340.

## Modding / creator code (none)

**Goal** — data-only; never execute user code.
**Behaviors** — no sandboxed script execution in V1 (ADR-004); declarative events/conditions instead; possible future: sandboxed Lua (post-V1 exploration).
**Data / JSON** — declarative only.
**Sources** — idea.txt 1642-1644, ADR-004.

## No server / solo-only (ADR-004)

**Goal** — zero infra; everything local or file-shared.
**Behaviors** — no accounts, no leaderboards, no cloud saves; optional "social hub" proposals dropped at decision; P2P co-op explicitly deferred (host-authority, cheats, NAT); standalone-game export rejected (code-signing/liability/version fragmentation).
**Interactions** — `14` (files are the transport).
**Sources** — idea.txt 220-253, 368-378, 613-638, 748-758, ADR-004.

## CI workflow (vault)

**Goal** — (post-V1) headless import check + export smoke on push.
**Behaviors** — run headless import + schema validation in CI once the repo has real content.
**Sources** — features.md §12 (🔵).

## GodotSteam integration (future)

**Goal** — workshop hook (horizon).
**Sources** — idea.txt 274, 659.

## HD4600 low-end calibration

**Goal** — the minimum hardware is a real, benchmarked target.
**Behaviors** — 12/09 bench (this repo's machine): Forward+ low ≈ 55 avg / 32 p95 fps @720p; Compatibility worse on every metric; skinning + shadows spike at P2 is the remaining renderer unknown.
**Data / JSON** — bench notes in ADR-002.
**Sources** — ADR-002.

## Dynamic hot loading

**Goal** — no "wire everything at startup"; content loads on demand.
**Behaviors** — content references resolve lazily (threaded), assets stream in as needed (config-hash caches for composed textures).
**Sources** — idea.txt 1644.