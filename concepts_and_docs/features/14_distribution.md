# 14 — Distribution & sharing

> The create → export → import → play loop. The JSON format is the product's **public API** (ADR-009). Neutral spec — status lives in `features.md`.

## Shared file format (JSON, never zip)

**Goal** — readable, validatable, virus-safe sharing.
**Behaviors** — JSON-only (no zip/binary); strict schema validation at import; prefab-ID whitelist; bounded complexity; `format_version` field; tolerance to unknown fields; never silent deletion; clear "created with version X — some new features missing" message for old worlds; every imported file treated as untrusted.
**Data / JSON** — world file (maps, graph, content), character config, prefab, dialogue resources — all under the same schema discipline.
**Interactions** — `09` export, `10` whitelist, `15` validation.
**Edge cases** — handmade/hostile JSON (validation rejects), exotic encodings.
**Sources** — ADR-009, idea.txt 1671-1677, 2648-2670.

## Local hub + drag & drop import

**Goal** — "import a world like opening an image".
**Behaviors** — local folder of installed worlds; drag & drop file OR file-picker; world appears in list; friction-less; per-world cards (title, thumbnail, creator, version).
**Data / JSON** — installed-world index.
**Interactions** — `11` World library, `09` export, `10` whitelist.
**Sources** — idea.txt 244-254, 1675, 284-286, 665-667.

## Robust export/import + exhaustive validation

**Goal** — round-trip fidelity, zero silent corruption.
**Behaviors** — export: strict schema production (IDs whitelisted vs catalog, bounds for stats/morphs/lights/complexity, graph cycles allowed, prerequisites validated); import: full reverse validation with precise error lines; user-facing diagnostics.
**Interactions** — `10` bounds, `06` complexity, `15`.
**Edge cases** — world referencing an asset the importing player doesn't have (graceful placeholder).
**Sources** — ADR-009, roadmap P12.

## Catalog built into the game PCK (vault feed)

**Goal** — players get assets through updates, never Drive.
**Behaviors** — the catalog build (`10`) packs **1st-party assets at P10** (ships in the PCK from launch) and **community assets via updates** after that; players never query the Drive; deterministic (id + sha256 + cache).
**Interactions** — `10`.
**Sources** — ADR-010.

## Example world + built-in tutorial

**Goal** — first-run onboarding + the piratable manifesto.
**Behaviors** — a shipped example world demonstrating the grammar (dialogue, events, lore, gimmicks, bosses, fog gates); a tutorial level teaching editor basics; both hackable as templates.
**Interactions** — `08` (manifesto world), `09` editors.
**Sources** — idea.txt 1736, roadmap P11 (starter catalog manifesto).

## Creator docs (brief)

**Goal** — low-friction docs.
**Behaviors** — concise in-app help + short docs covering: no-3D rule, catalog, flags/conditions, export/import, the example world internals.
**Sources** — roadmap P12 (🟡).

## User-content trust model

**Goal** — near-free moderation, clear labeling.
**Behaviors** — closed catalog + JSON-only ≈ no malware/gore vectors; residual = free-text fields + asset juxtaposition → char limits + warnings suffice; "user-created content, not verified" banner shown at import.
**Interactions** — `11` import disclaimer, `10`.
**Sources** — idea.txt 88-92, 140, 1688-1708.

## Stale-format notice

**Goal** — nobody silently loses content.
**Behaviors** — old worlds load with new features absent but never stripped; formatted message on load.
**Interactions** — ADR-009.
**Sources** — idea.txt 1677.

## Steam Workshop (horizon)

**Goal** — (if traction) workshop as the sharing endpoint.
**Behaviors** — would enable server-side browse + subscribe; local-first behavior unchanged when offline; GodotSteam as the integration path.
**Interactions** — `03` runs, `14` import.
**Sources** — idea.txt 274, 659; roadmap P12 horizon.

## Continuous content growth (community intake)

**Goal** — the catalog keeps growing without new systems.
**Behaviors** — community submissions validated through Discord → Drive → manifest (`10`); organic anti-grid pieces, light assets, backdrops.
**Sources** — ADR-010, roadmap P9.