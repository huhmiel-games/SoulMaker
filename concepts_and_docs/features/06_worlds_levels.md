# 06 — Worlds & levels

> The navigation architecture: small zones, a graph of links, cheap seams, budget-aware loading. The **anti-grid identity** is the core goal. Neutral spec — status lives in `features.md`.

## Prefab system (Level 1)

**Goal** — reusable groups of assets: "a dungeon corridor" placed as one entity.
**Behaviors** — select several assets → group → save as prefab; prefabs place in the map editor like single assets; prefab = list of asset ids + local transforms.
**Parameters / bounds** — prefab file is a light JSON; reuse unlimited.
**Data / JSON** — prefab schema (`data/schema/prefab_v0.1.json`, vs `features.md`).
**Interactions** — `09` prefab editor, catalog validation.
**Edge cases** — prefab referencing a missing asset → graceful fallback (ADR-009).
**Sources** — idea.txt 330-332, roadmap P1.

## Map assembly (Level 2)

**Goal** — free placement, never "grid"; the product's signature.
**Behaviors** — translation/rotation/scale **free, snap off by default** (fine adjustable 0.1); overlaps accepted (paired with buried bases / organic pieces); irregular-asymmetric catalog geometry; collisions embedded in official assets (auto convex + manual override).
**Parameters / bounds** — snap default off; accepted overlap convention.
**Data / JSON** — map = list of placement records (asset/prefab id + transform).
**Interactions** — `09` editor UX, `10` catalog geometry spec.
**Edge cases** — sealed tunnels / impossible jumps → caught by **instant playtest** gate.
**Sources** — idea.txt 288-332, 675-710.

## Sockets (Level 3)

**Goal** — the connection points of the world graph.
**Behaviors** — discrete points (position + orientation) on zone edges; links connect two sockets; nominal typing (type cave/fog/boat) deferred — V1 untyped, add if incoherent compositions appear.
**Parameters / bounds** — socket number per zone bounded.
**Data / JSON** — sockets in zone scene/resource (`Marker3D` + `SocketData`).
**Interactions** — world graph (`06`), fog transitions (`06`).
**Edge cases** — unpaired socket (dead end or V2 impostor), overlapping sockets.
**Sources** — idea.txt 2398-2401, 2498-2527.

## World = graph of links (Level 3, final)

**Goal** — worlds **compose**, they never stream geography: composer links existing worlds.
**Behaviors** — world = node list + link arcs (two ids + two sockets); links directional but bidirectional by default; cycles allowed (souls shortcuts/elevators); composed world file is tiny (list of worlds + links), shareable anywhere.
**Parameters / bounds** — world/library growth bounded by zone count.
**Data / JSON** — composed world schema (`data/schema/world_v0.1.json`).
**Interactions** — `07` shortcuts/elevators close cycles; `13` impostors for visual contiguity.
**Edge cases** — cycle of length 1, duplicate links, link to missing world.
**Sources** — idea.txt 2498-2529.

## Fog transitions (fade seams + loading)

**Goal** — the souls seam that doubles as the loading screen.
**Behaviors** — fade + fog depth/height over 2-4 s; sync-load fallback; used for map-to-map transitions inside a world.
**Parameters / bounds** — 100-200 m overlay terrain cap per socket OR volumetric fog (`FogVolume`) hides seams.
**Data / JSON** — transition config server-side default.
**Interactions** — world graph, `15` streaming.
**Edge cases** — player mid-socket when saving/quitting.
**Sources** — idea.txt 2436, 2450.

## Streaming & loading fragments

**Goal** — swap fragments without blocking the frame or reloading the scene graph.
**Behaviors** — one active world centered near origin; `ResourceLoader.load_threaded_*` proximity streaming; fragments stay **node-light** (logic deferred to a shared root); no `get_tree().change_scene_to_file` mid-game; persistent World/Player/UI roots, fragments swapped in; logic activated on proximity (see `05` enemy activation).
**Parameters / bounds** — fragment node budget; no world repositioning (avoid floating origin at bounded sizes).
**Data / JSON** — zone fragment resources.
**Interactions** — `15` loading, `05` activation.
**Edge cases** — streamed-in enemy triggering instantly (activation radius), fragment change during save.
**Sources** — idea.txt 2410-2447, 2460-2490 (superseded by final world graph).

## Ambiance: sun + fog + tonemapping (world defaults + per-map override)

**Goal** — a world's identity through light/air; maps may deviate where the layout calls for it.
**Behaviors** — world-level defaults (sun elevation/exposure, fog depth/height, tonemapping) with optional per-map override (dark cave in a sunny world); ambient presets are named bundles (clear day / misty dusk / stormy night / underground dungeon); live preview in editor.
**Parameters / bounds** — sun elevation bounded (>10-15°); preset registry bounded.
**Data / JSON** — world ambiance + overrides.
**Interactions** — `15` lighting, `09` editor preview.
**Sources** — idea.txt 336-346, 362-364, 717-740; ADR-005, roadmap P6.

## Embedded lights & light budget

**Goal** — creator-friendly lighting: lights inside assets, a per-map budget with an editor counter.
**Behaviors** — light fixtures embedded in catalog pieces (torch, fireplaces, lanterns, braziers) with 2-3 fixed intensity variants + animated flicker; per-map light-count cap **with a live editor counter** (informed limits).
**Parameters / bounds** — light cap per zone; intensity variants fixed.
**Data / JSON** — map light usage counted at save/validation.
**Interactions** — `15` perf, `09` editor UI (counter), ADR-002 tiers.
**Edge cases** — light leaking past walls → occlusion boxes / thick interior pieces (documented amateur pitfall).
**Sources** — idea.txt 348-358, 729-736.

## Map lighting baked per zone

**Goal** — static baked lighting so runtime cost is low (low-end target).
**Behaviors** — per-zone `LightmapGI`; day/night only as cheap cosmetic combos (flipbook baked suns); dynamic shadow map limited to player + near enemies.
**Parameters / bounds** — bake on save; runtime light entities limited.
**Data / JSON** — lightmap artifacts; lighting config in zone data.
**Interactions** — ADR-002 tiers, `15` perf.
**Edge cases** — baked light stale after asset change (re-bake), dynamic overlaps.
**Sources** — idea.txt 1137-1181.

## Ambient occlusion / light leak guard

**Goal** — no black holes or glaring seams from amateur lighting.
**Behaviors** — presets + occlusion geometry assist; validator flags potential leaks at import.
**Parameters / bounds** — preset-driven.
**Data / JSON** — none.
**Interactions** — `09` validation messages.
**Sources** — idea.txt 348, 729.

## Spawn points & player entry

**Goal** — where a run starts and transitions arrive.
**Behaviors** — world-level entry points; per-zone spawn markers; respawn anchor at last lit bonfire (`03`).
**Data / JSON** — spawn markers in zone data; GameState tracks respawn transform.
**Interactions** — New game flow, death respawn, transitions.
**Sources** — roadmap P2/P6, ADR-011.

## Backdrops (neutral distance planes) — vault

**Goal** — fill the horizon without building the world's geography.
**Behaviors** — (post-V1) catalog-neutral distant planes (mountains, sea, misty plains), skybox/fog ambiance, local closure; automatic edge dressing; auto placement on non-connected world sides; washed-out oversized silhouettes; one valid viewpoint per window.
**Parameters / bounds** — backdrop family registry; placed only when justified.
**Data / JSON** — backdrop picks at composition.
**Interactions** — `06` world graph, `13` impostors.
**Sources** — idea.txt 2682-2728.

## Photo impostors (content-keyed hash cache) — vault

**Goal** — (post-V1) fake panoramic windows showing the *neighbor world*.
**Behaviors** — flat billboard from an actual scene capture, via a deterministic auto-photo at composition; regeneration at load vs embedded photo hybrid (embed at publication + runtime-regeneration fallback); captured from a natural viewpoint.
**Parameters / bounds** — one valid viewpoint per window.
**Data / JSON** — impostor reference + content-keyed hash cache + game version.
**Interactions** — `14` export, streaming.
**Sources** — idea.txt 2531-2641.

## Day/night cycle (cheap cosmetic)

**Goal** — time-of-day flavor without a dynamic sun cost.
**Behaviors** — flipbook of baked sun positions across a palette cycle; ambiance preset switching; no re-bake at runtime.
**Parameters / bounds** — palette entries bounded.
**Data / JSON** — preset list.
**Interactions** — `06` ambiance, `15`.
**Sources** — idea.txt 1137-1181.

## Anti-grid design rules (catalog & placement)

**Goal** — keep the "no grid" feel through both asset design and editor behavior.
**Behaviors** — free rotation with no snap by default; ±15-20% per-instance scale variance; accepted overlap; organic asymmetric base pieces (rocks, cliffs, arches, irregular ruins ≈ 20 pieces); buried bases so overlap looks intentional.
**Parameters / bounds** — scale variance bound; base piece budget.
**Data / JSON** — per-instance scale (bounded).
**Interactions** — `10` catalog geometry.
**Sources** — idea.txt 306-316, 690-696, 706-707.

## Broken geometry guard (instant playtest)

**Goal** — creators can't ship a world they can't physically traverse.
**Behaviors** — one-key editor→player toggle (no reload) to test playability; validator catches sealed tunnels/impossible jumps heuristically at export.
**Parameters / bounds** — heuristic-based.
**Data / JSON** — none.
**Interactions** — `09` playtest, `14` export validation.
**Sources** — idea.txt 324, 702.

## Gravity guide / ground attach

**Goal** — help amateurs place objects on the ground, without a rigid grid.
**Behaviors** — non-intrusive ground-attach hint: base snap or influence line to the surface; keeps the grid invisible.
**Parameters / bounds** — hint strength, snap on/off.
**Data / JSON** — none.
**Interactions** — editor UX (`09`).
**Sources** — idea.txt 326, 704.