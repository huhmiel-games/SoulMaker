# 10 — Catalog & asset pipeline

> The closed catalog: every mesh/animation/light. Creators compose from it. Two growth streams: the **1st-party starter catalog** (ADR-017, V1 launch content) and **community submissions** (ADR-010, post-V1 augmentative). Neutral spec — status lives in `features.md`.

## Asset taxonomy

**Goal** — a browsable, searchable closed set of composable primitives.
**Behaviors** — categories: prop/natural (organic asymmetric pieces — rocks, cliffs, arches), architecture, light fixtures (torch/fireplace/lantern/brazier, 2-3 intensity variants), enemy/character (archetype families), **clothing** (outfit **texture sets** — the painted fitted layer, 0 stats/0 weight, `02`/`04`), equipment/attachments (**base equipment types: weapon, offhand shield, armor pieces — 3D overlay shells on rig sockets, held torch — visuals bound to rig sockets, `02`/`04`/`17`; accessory = data item, no mesh, `04**), animation library (locomotion/melee/**talk cycle** — text-only speech, shared rig, `02`/`08`), prefabs (asset groups), materials/colors (bounded presets), (audio — vault/`12`). **Layer split**: clothing = painted on the body mesh; armor = volume mesh overlay (the hybrid rule, `02`).
**Parameters / bounds** — registry is closed; new categories only by pipeline decision.
**Data / JSON** — catalog manifest (schema v0.1, `data/catalog/schema_v0.1.json`).
**Interactions** — `06`, `09`, `02`.
**Sources** — ADR-010, ADR-017, `asset_pipeline.md`, idea.txt 314-330, 706-707.

## Catalog manifest (in git)

**Goal** — the manifest is the source of truth; humans read it, build consumes it.
**Behaviors** — JSON in git: per entry `id`, `name`, `category`, `license`, `bounds` (triangles max, texture size max, bbox), `files[]` with `path` + `sha256`; unknown/extra fields tolerated at load (ADR-009); one commit per entry (small batch). Both streams write into the same manifest.
**Data / JSON** — `data/catalog/manifest.json` + `schema_v0.1.json`.
**Interactions** — `14` build, `11` credits.
**Sources** — ADR-010, `asset_pipeline.md` §4.

## Starter catalog (1st-party, stream A)

**Goal** — the V1 ships a playable, launch-complete content set authored by the base itself — no dependence on external contributors.
**Behaviors** — curated CC0 packs (Quaternius et al.) across every taxonomy category + an animation library re-targeted onto the standard humanoid skeleton (Mixamo and other license-compatible sources, `02`); validated with the same checklist as the community stream (headless import, bounds, style/palette, skeleton); assembled from **local sources** and packed into the PCK — no Drive/Discord involved.
**Parameters / bounds** — per-category bounds identical for both streams.
**Data / JSON** — manifest entries + licenses → Credits.
**Interactions** — `02` re-targeting, `14` PCK, `11` Credits, `13_followup` example world (`14`).
**Edge cases** — missing licensed source at build → fail loudly (same as community).
**Sources** — ADR-017, roadmap P10, `asset_pipeline.md` Stream A.

## Community submissions (Discord intake, stream B)

**Goal** — post-V1, artists contribute additional content without learning git (never a release dependency).
**Behaviors** — artist submits `.glb` (textures separate `.png/.jpg`, never embedded) + casual description via Discord threads (status emojis: pending/approved/rejected); maintainer validates via **headless import** (`import_check.gd`), license check, bounds, style/palette, skeleton check (standard humanoid if character); then uploads to Drive (`pending/`→`approved/`), writes the manifest entry.
**Parameters / bounds** — submission format fixed; style gate by eye.
**Data / JSON** — manifest entry.
**Interactions** — `02` (skeleton check), `15` headless tooling.
**Edge cases** — resubmit after rejection with reason; revision = new id (never overwrite in place, history lives in manifest/git).
**Sources** — ADR-010, ADR-017, `asset_pipeline.md`.

## Build pipeline (local → PCK, then Drive → cache → PCK)

**Goal** — deterministic, reproducible catalog builds for both streams.
**Behaviors** — build script (`build_catalog.gd`): read manifest → resolve source per stream — **local repos/build dir for 1st-party** (Stream A), **Drive id → gitignored local cache** for community (Stream B) → verify `sha256` → reference cached files into the build → pack into game PCK; fail loudly on missing/hash/license problems. Players receive assets only via game updates — never query the Drive.
**Parameters / bounds** — cache dir `catalog/cache/` gitignored; offline after first fetch.
**Data / JSON** — manifest-driven.
**Interactions** — `14` distribution, `11` credits.
**Sources** — ADR-010, `asset_pipeline.md` §5.

## Bounds & validation rules

**Goal** — bounded assets keep runtime + validation cheap.
**Behaviors** — per-category bounds: triangle count, texture size, bounding box; **armor shell clearance** (min gap vs the max-morph body — the `02` fit rule); clothing texture-set budget; animation bounds; enemy config bounds (morphs, stats); complexity limits at export (ADR-009).
**Data / JSON** — bounds in manifest/schema.
**Interactions** — `14` exhaustive validation, `09` editor errors.
**Sources** — ADR-010, `asset_pipeline.md` §2, idea.txt 168-172.

## Style & palette rules

**Goal** — cohesion despite disparate sources (Quaternius low-poly vs "anime").
**Behaviors** — base shader (toon/cel, ADR-019) + imposed palette; texture-mapping rules (front-unfold face UV, two-texture split); cohesion checked by eye at intake; created assets use hand-made built-in blend shapes from official models.
**Data / JSON** — material/palette presets in catalog.
**Interactions** — `02`, `06` ambiance.
**Sources** — idea.txt 202, 522, 995-1005, 1488-1518.

## Dev-speed exception (first test assets)

**Goal** — P1 prototype speed without the pipeline.
**Behaviors** — the first 5-6 test assets live directly in the repo and are the **seed of the starter catalog** (ADR-017); from P1 on, Stream A assembles from local CC0 packs (manifest stays the source of truth).
**Data / JSON** — exception documented in manifest/commit.
**Sources** — ADR-010 ("Working detail"), ADR-017, `asset_pipeline.md` open points.

## Credits screen (fed by manifest)

**Goal** — honor contributors.
**Behaviors** — Credits reads the manifest (licenses + authors) → computed credits/attribution screen; updates with each catalog build.
**Interactions** — `11_ui` Credits, `14` build.
**Sources** — ADR-010, `asset_pipeline.md`, screens.

## Headless import validation tooling

**Goal** — maintainers validate without the editor.
**Behaviors** — headless Godot import (`--headless --script`), logs errors; also usable as CI seed (vault).
**Data / JSON** — outputs logs.
**Interactions** — `15` CI (vault), `14`.
**Sources** — `asset_pipeline.md` §2.1.

## Audio assets (vault)

**Goal** — (post-V1) "a sound" becomes a catalog category.
**Behaviors** — the glossary once allowed "a sound" as an asset; the whole audio pillar is vaulted (ADR-014) — SFX would enter here when audio returns.
**Sources** — ADR-014, `12_audio.md`.