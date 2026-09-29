# SoulMaker — Roadmap

> Working document. Originates from the discussions in `idea.txt`. Nothing is set in stone: each phase can be adjusted, but the founding decisions are tracked in `decisions.md` and must not change lightly.

## Vision

A game that is not a game: a base that lets anyone create their own souls-like world and share it. Creators manipulate **no 3D at all** — they compose from provided assets (pre-rigged, pre-animated) and bounded parameters. Everything flows as **JSON data**, no server, sharing through files.

**V1 = the public launch build** : the complete installable game released at first launch (P0 → P13 below). Everything added after that build lives in the vault (`features.md`, ADR-014+). The V1 ships with a **1st-party starter catalog** (CC0 packs + re-targeted animations, ADR-017) — the community pipeline (ADR-010) is an augmentative post-V1 growth stream, never a V1 dependency.

## Founding decisions (locked — see decisions.md)

1. **Godot 4.7** + Jolt Physics + **GDScript**
2. **Renderer** : **Forward+ only — no Compatibility fallback**, neither in dev nor at export (decision ADR-002, calibrated on the **HD4600 benchmark** of 12/09/2026: Forward+ beats Compatibility on every setting, and especially on stability p95/p99). Permanent hardware requirement: **Vulkan required**. The low-end target is served by **quality tiers** (render scale, MSAA, shadows, light cap, heavy features disabled based on detected floor).
3. **1st prototype = map editor** : we prove the loop "place an asset → play → place", versioned JSON serialization from day 1.
4. **All data, no server** : sharing through JSON files (no zip — readability and validation at import), solo-only.
5. **Worlds = graph of small zones connected by sockets** (no chunk streaming). Fog transitions. **Ambiance (sun, fog): world-level defaults + optional per-map override**.
6. **Assets provided by the base** : CC0/one-time-purchase sources, **animations re-targeted onto a standard humanoid skeleton** — the source doesn't matter, the standard skeleton does (shared animation ecosystem).
7. **Enemies** = archetypes + bounded morphs. No 3D creation by users.
8. **The 3D look is anime/cel** : a base toon shader (`diffuse_toon` + shadow ramps), real shadow maps, no ink outlines in V1 — enforced on every asset (ADR-019).

---

## P0 — Foundations (~1 week)

**Goal** : validate that everything the architecture needs exists on Godot 4.7, and lay the foundations that avoid format debt.

**Deliverables**
- Technical spikes verified on the local binary, documented:
  - Retargeting `SkeletonProfileHumanoid` + import of third-party animations (Mixamo/Quaternius/etc. per licenses)
  - Animation markers windup/attack/release (`play_section_with_markers`)
  - ~~Foot IK `SkeletonModifier3D` (two-bone / FABRIK)~~ — **FAIL 15/09/2026** : spike abandonné (orientation perso + rig non inspectable dans l'éditeur) — voir `footik_model.md`
  - ~~Upper/lower body filtering in the `AnimationTree` (excluded bones + translation tracks)~~ — **FAIL 15/09/2026** : spike abandonné — le `AnimationNodeBlend2` pondère les branches à somme 1 (lerp) : impossible de superposer « bas = walk » et « haut = attack » à pleine intensité simultanément ; rework de topologie (additive / masques par os) reporté en P2
  - ~~`ShapeCast3D` following a bone (swept hitbox) + `callback_mode_process = Physics`~~ — **REPORTED (15/09/2026)** : pas indispensable au démarrage ; la technique est déjà choisie (`features/01` §Swept hitbox), validation reportée en amont de P2 (ligne 74)
- Repo structure (folders `scenes/`, `scripts/`, `data/`, `assets/`), naming conventions
- Base autoloads (`GameState`)
- **JSON schema v0.1** (world, character config, versioning) — format debt is the debt that kills
- `decisions.md` filled in (ADR)

**Done** : spikes work (except Foot IK & Upper/lower — FAIL, et ShapeCast3D — REPORTED, voir spike 15/09), schema exists, ADR filled in.

---

## P1 — Map editor vertical slice (the core, ~6-8 weeks)

**Goal** : prove the maker. The loop "I build a 30 m corridor in 5 min without feeling the grid".

> **Amendment 18/09/2026 — functional closure**: free transform is direct grab&move (no gizmos); zoom removed (orbit only); one-key playtest deleted in favor of the editor ⇄ game round-trip (P2); the hub stays single-door (Map editor + EXIT — Play door, Options and Continue arrive with the round-trip). The « play in it » Done criterion moves to the P2 round-trip; palette is dropped (textures ship ready-made from GIMP, intake checklist = shader applied + ready textures).

**Deliverables**
- Home shell: **two-door hub (Play / Create)** — transverse actions (Options, Credits, Quit) in a corner, contextual Continue per door (resume run / resume editing). Details in `screens.md`.
- Fluid camera editing (orbit, zoom)
- Translation/rotation/scale gizmos **free, no snap by default** (fine adjustable snap 0.1)
- Asset catalog panel (**starter catalog proto** — 5-6 seeded CC0 assets first week, grown through P2→P9; 1st-party, ADR-017), keyboard/gamepad browsing (arrows/D-pad + A/E place, no drag & drop per device-parity rule)
- Floor + ambiance presets (fog depth/height + tonemapping)
- Bounded directional sun (minimum elevation), lights embedded in assets (torches, fireplaces)
- **Base toon shader (`diffuse_toon` + shadow ramps) + imposed palette** (ADR-019) — the 3D look is locked from the first visible asset
- **One-key instant playtest** (editor ↔ player)
- JSON save/load + **validation at import** from day 1

**Done** : build a 30 m corridor in 5 min without grid feeling (free rotations, accepted overlaps), save it, reload it, play in it.

---

## P2 — Fighter core (~5-6 weeks)

**Goal** : prove the base combat "slams" — the souls feel, without the toolkit.

**Deliverables**
- Anime character template (re-targeted asset — **first starter-catalog character**, ADR-017) built on the **attachment-slot skeleton** of P4 (hair/ears/equipment markers on the rig) to avoid rework; shared animation library (locomotion, melee)
- 3rd-person controller: locomotion, orbit camera, lock-on, dodge + i-frames, stamina
- Maker round-trip: editor ⇄ game on the current map (symmetric `pending_map` handover — replaces the deleted P1 fly playtest) + return to the editor
- **Game feel**:
  - Markers windup/attack/release; ~~upper/lower body layers (animation combos)~~ — **dropped out of V1 at P2 exit (21/09/2026)**: Blend2 FAIL stands as decision, topology rework post-V1 only
  - Hitstop, screen shake, VFX, hit reactions, controller rumble (haptics) — sound/audio deferred to vault (ADR-014): the "slam" jury reads **without audio**, keep that in mind when judging the P2 baseline
  - Blade rebound (reverse 3-6 frames + blend to idle), easing, variation
  - Swept `ShapeCast3D` hitbox (no inflated volumes), masked on non-offensive frames
- 1 simple enemy archetype (aggro, telegraph, hit reaction, poise)
- ~~**Skinning + shadows spike** (complement to the HD4600 bench of 12/09, done on primitives only): measure GPU skinning (Forward+) with N skinned characters on the real re-targeted rig **and** the real shadow maps on the toon shader (ADR-019) — the last renderer unknowns before locking the low-end tiers (P13)~~ — **dropped at P2 exit (21/09/2026)**: tiers rest on the primitives bench, residual risk accepted (tracked at P13)

> **Note** : the full martial toolkit (block, criticals, ranged, damage types, movement depth) ships in the next phase — **P3, Combat depth slice** (ADR-018). P2 proves the base swing honest and readable.

**Done** : playable/testable criterion — readable impact, honest dodge, the combat is felt. **P2 closed 21/09/2026** (fighter core + soldier_melee_v1 validated over 3 human combat sessions; bench dropped, upper/lower out of V1 — see above).

---

## P3 — Combat depth slice (V1 toolkit, ADR-018) (~5-6 weeks)

**Goal** : prove the whole martial toolkit reads correctly — a gray-box slice before the systems land in their owning phases.

**Deliverables**
- **Design pass at kickoff** validates the **values pinned in `features/17`** (backstab cone/window; two-hand STR ×1.5; push_move — blade-shove ~60-80 stability-equivalent on heavies only, kick cut to V2 21/09/2026) and settles the rest: **blade-shove visual feel**. (Resolved in-doc 13/09/2026: buff duration + `has_buff`, ranged lock-on, roll-tier thresholds <30/<70/≥70, backstep no i-frames, plunging buffered input, torch/darkness visual-only, accessory ×4, elemental balance — armor-dominant 7-pool + per-type stat baseline + additive `resist-push`, rosette 4-band tags ×0.5…×1.25, boss ×0.85–×1.15. Cut 21/09/2026: parry/riposte → V2.)
- **Block/guard with shields** (stability, stamina drain, guard break) — mechanics proven here; the offhand shield slot binds with the inventory at P8
- **Criticals**: backstab only (positional trigger ±30° / 0.6 s → direct critical hit ×1.5-×2, no stance two-step) — **parry / riposte cut to V2 21/09/2026** (frozen spec kept in `features/17`)
- **Ranged weapons** (bow/crossbow): draw/hold, charge tiers, ranged lock-on, ammo consumption — the ammunition item and economy land with the inventory at P8
- **Damage types** (slash/thrust/strike + fire/lightning/magic/dark — 7 in V1) + **status build-up** (bleed/poison/frost): mechanics, meters and procs proven here; derived resistances integrate at P7, per-enemy weakness tables at P9
- **Player poise / hyper-armor**; **equip-load roll tiers** (fast/mid/fat, thresholds <30/<70/≥70 resolved in `features/17`); backstep; plunging attacks; two-handed grip (STR ×1.5 scaling — resolved in `features/17`; **keeps guard via the weapon's own guard values, cancels parry**); kick/push guard-break (per weapon class `push_move`, values resolved, feel-validated at P3); ladder climb up/down; held torch
- **Temporary buff/debuff effect engine** (shared per-entity effect slot) — consumable items land at P8, the `apply_buff` verb rides the P5 narrative grammar

> **Note** : if the slice grows out of shape, a **prototype → deep-pass split** is allowed at P3 exit (re-slim is healthy — ADR-018 keeps the net complete).

**Done** : a small arena fight where each toolkit system reads correctly — block breaks, backstabs land, statuses proc, roll tiers move differently — and the slice feels like a souls-like.

---

## P4 — Modular character system (~5 weeks)

**Goal** : the character editor and its exportable config format.

**Deliverables**
- Base mesh + attachment slots (hair, ears, equipment via `BoneAttachment`/`Marker` on the rig)
- **Clothing layer** : outfit texture sets on the base UV layout (painted, fitted — cosmetic 0 stats/0 weight; picked at creation + **swappable in-game**, `02`/`04`)
- **Armor overlay foundation** : the 4 armor sockets (helmet/chest armor/gauntlets/leggings) on the rig + shell-clearance fit rule vs max-morph body (armor *content* ships with the starter catalog, P10; base rig ready in P4)
- Morphs as bounded blend shapes (generous but strict bounds, linked slider groups)
- 2D face layers + bounded morphs (ADR-007) — the face is texture (ADR-019 look), geometry only for shape
- **Face light treatment gray-box** (ADR-019, 🟡 settled in the P4 design pass)
- **Character config JSON** exportable/importable + validation (graceful fallback on missing assets)
- Same character usable as player **and** as NPC (config = source of truth)

**Done** : a character created via config, replayable, exported to a light file, used as NPC without rework.

> **Boundary** : animation authoring is out of scope — the dev-side anim_creator rig (built in advance during P2/P3) feeds the shared animation library; P4 consumes it, it does not build it.

---

## P5 — Narrative layer (~4 weeks)

**Goal** : the narrative grammar that makes a created world interesting (dialogues, conditions, events).

**Deliverables**
- **Flags registry declared before use** (dropdown in the editor, no free input) + `initial_values`
- Conditions/effects engine (extensible registry: `set_flag` `clear_flag`, `give_item`, `remove_item`, `unlock_shortcut`, `trigger_event`, **`apply_buff`**; conditions: `has_item`, `item_not_full`, `boss_defeated`; `open_shop` inert until shops; `has_buff` excluded — 13/09/2026)
- **Dialogue graph** (JSON schema discussed: `line` / `choice` / `conditional` / `exit`, `next`/`goto`; text-only speech — no voice, no lip-sync, resolved 13/09/2026)
- Global events reacting to flags (disappearing NPC, hostile zone, miniboss)
- Lore notes attachable to objects/places (+ **item description/lore text**, creator-authored — shown in the inventory, P8)
- **Fog gates** (blocking doors tied to flags — open when a boss is killed or a key item is used; placed like any world object)
- Graph validation tool (broken gotos, orphan flags, close typos)

**Done** : a branching dialogue with conditions and effects works end to end, validated at import.

---

## P6 — Worlds & transitions (~4 weeks)

**Goal** : the graph of linked worlds — the sharing architecture.

**Deliverables**
- Sockets in the editor (discrete point: position + orientation), directional links but bidirectional by default
- Composed world graph (world list + links, tiny file)
- Fog transitions (fade + fog depth/height, "souls" rhythm)
- **Ambiance (sun, fog, tonemapping): world-level defaults + optional per-map override** (e.g. a dark cave inside a sunny world)
- Per-world persistence in `GameState` (boss state, chests, levers, **bonfire state** — lit/unlit + respawn anchor)
- The example world serves as a hackable template (an early build; the full manifesto is completed in P11 on the starter catalog)

- **Sharing smoke test** (core promise, ~1 morning): export a world, reimport it into a **wiped cache / fresh profile of the same build**, then play it — validates the packaged JSON round-trip (file deps, previews, catalog resolution) without relying on editor state. The full cross-machine cycle stays at P12.

**V2 (non-priority)** : backdrops provided by the base (neutral distance planes, auto placement), photo impostors regenerated locally from the JSON (content-keyed hash cache + game version).

**Done** : two worlds created by different players connect via sockets, fluid transition, state restored on return — and the file round-trip survives a wiped cache/fresh profile.

---

## P7 — Player progression loop (~3-4 weeks)

**Goal** : the souls-like progression loop — earn, spend, die, recover, and the combat layers integrated with the stats.

**Deliverables**
- **Stats backend** (ADR-011): **8 fixed canonical attributes** — Vigor, Mind, Endurance, Strength, Dexterity, Intelligence, Faith, Arcane — with derived mappings (HP, FP, stamina/equip load, damage scaling, cast speed, item discovery, **damage-type resistances — bounded**); **single level-up cost curve by total level**; canonical ids in data + **world-level display overrides** (`stat_names` + `currency_name`: labels only, resolved at display)
- **FP framework** (no magic content in V1 — Int/Faith bankable, requirements possible, spells deferred via vault)
- **Bonfire / grace** world object: respawn point + stat refill + opens the level-up interface (creators place it via the catalog, like any object); unlock state persisted in GameState
- **Estus healing** (ADR-011): rechargeable charges, refilled at the bonfire, base-backed; bounded upgrades via catalog items
- **Run start = fixed base template** (ADR-011): starting stat spread + starting equipment from the base, appearance layered from the character config (P4)

> **Boundary (P7/P8)** — no equipment-swap screen in P7: the "trades a shield for more damage" feel comes from the **two-handed grip (P3)** — the offhand shield is sheathed on the back (equipment visual anchors, P4) and the weapon two-hands — plus the starting loadout. Composing a real build (shield/bow/accessory swap, min-stats gating) is P8's criterion.
- **Damage-type/status layer integrated with the derived resistances** (ADR-018/011, mechanics from P3)
- **Temporary buff/debuff engine wired** with the HUD buff icons (`apply_buff` from P5, items from P8)
- Level-up screen: spend currency → raise a stat (bounded sliders, stats **and currency** named per the world's display overrides)
- **HUD**: HP bar, stamina bar, souls counter, estus charges, equipped quickbar, buff icons (**strip cap 4 + « +N », depleting ring — resolved 13/09/2026**), **boss HP bar** (for boss-level enemies — HUD element, no cinematic) (FP bar only when FP content exists — see V2 note)
- **Boss-level enemies (V1)**: `boss_level` marker + bounded stat multipliers on any archetype; auto `boss_defeated` flag on death (feeds fog gates); no multi-phase editor in V1 (vault)
- **Death update** (ADR-013): "your souls await" line + **soul orb** recovery on the map
- **GameState persistence** for progression + run state (validated at save/load, ADR-009); **multiple parallel runs per world** (named runs, New game never overwrites, Load lists runs — ADR-015)
- **Save integrity** (atomic tmp→rename write, quarantine of corrupt runs on load — ADR-016)

**V2 (non-priority)** : NPC vendor shops, magic content (spells → FP bar becomes meaningful), weapon arts, cast speed effects.

**Done** : a player runs a map, earns souls, levels at a bonfire (stats and currency displayed per the world's overrides), heals with estus, trades a shield for more damage and feels the resistances, dies and recovers (or loses) the souls — feel and persistence validated end to end.

---

## P8 — Inventory & equipment (~3 weeks)

**Goal** : the equipment system — compose and read a build.

**Deliverables**
- **Inventory / equipment screen**: weapon + **offhand shield** + **clothing** (outfit texture set) + helmet/chest armor/gauntlets/leggings + **accessory ×4** (data items, no rig visual, display name `accessory_name`) slots (armor visuals via `BoneAttachment`/`Marker` on the rig, P4; clothing = painted base layer, `02`); estus charges + consumables quickbar; **ammunition**; key items (read-only, flags-gated); stat/weight/poise readout; **minimum attribute requirements** (validated at import)
- **Combat-depth inventory (ADR-018/012)**: ammunition as base item type, **homeward bone** (return to last bonfire), **temporary buff/debuff items** (feeds the P5 effect engine via `apply_buff`), **item description/lore text** (creator-authored, P5); the **base item vocabulary** (`04`) — **weapon resins/bundles** (elemental + status, 7 damage types), **status cures**, **throwables**, **soul items**, **elemental ammunition variants**
- **Drop tables per enemy** (bounded: currency + one possible item) + loot objects in the catalog (chests, corpses, pickups) placeable in the map editor
- Item lore/inspect display (content authored at P5)

**Done** : a player composes a build (shield + bow + accessory + consumables incl. resins/throwables), the ammo economy works, gear is gated by stats, loot drops per table.

---

## P9 — Content variety (continuous)

**Goal** : flesh out the catalog on demand, without ever building a new system.

**Deliverables**
- **1st-party catalog growth** (ADR-017): CC0 packs + Mixamo re-targeted animations validated/bounds-checked as they're needed by the phases — feeds the P10 launch package
- Enemy archetypes + bounded morphs (variety through combinatorics)
- Behavior pattern editing (data-driven)
- **Per-enemy weaknesses / resistances** (bounded damage-type table — ADR-018): feeds the damage-type + status layer from P7
- `boss_level`+multiplier encounters compose with behavior patterns (the full multi-phase **boss editor** is vaulted, late chapter — not part of V1)
- Community submissions (Discord → Drive → build, ADR-010) stay **post-V1 augmentative** — never a V1 dependency

**Done** : variety comes from combinatorics, not from new assets; the catalog grows through validated community submissions.

---

## P10 — Starter catalog packages (~4-5 weeks)

**Goal** : the base provides the content that makes the V1 a *game you can play*, not a dependency on strangers.

**Deliverables**
- **Starter catalog 1st-party, launch-complete** (ADR-017): curated CC0 packs across every taxonomy category (architecture, natural/prop anti-grid, light fixtures, prefabs, equipment) + **Mixamo/re-targeted animation library** on the standard humanoid skeleton (ADR-006); **V1 starter item subset per the pinned bounding policy** (per-family coverage, `04`; exact instance list settled here — resolved 13/09/2026)
- **Exhaustive validation** of the whole catalog: headless import, bounds, **style/palette (ADR-019)** (same checklist as the community stream); manifest + licenses + **Credits** committed
- **Cohesion pass**: the base toon shader + imposed palette applied across the whole catalog (ADR-019)
- **Packaged into the game PCK** via the build script (local source — no Drive needed for the 1st-party stream)

**Done** : a complete, validated, cohesive 1st-party catalog ships in the PCK.

---

## P11 — Example world (~2-3 weeks)

**Goal** : the manifesto — a full created world demonstrating the whole grammar.

**Deliverables**
- **Example world = the manifesto**: a full created world demonstrating everything — dialogue, events, lore, gimmicks, boss (`boss_level`), fog gates, shortcuts, combat content — built **only** from the starter catalog (P10); doubles as the hackable template (first built at P6)
- Credits screen fed by the starter catalog manifest (ADR-017)

**Done** : a first-time player can create a world, play it end to end, and study the example world like a textbook — all with 1st-party assets.

---

## P12 — Distribution (~4 weeks)

**Goal** : the full create → share → play cycle.

**Deliverables**
- Local hub: list of imported/exported worlds (file-picker import only, no OS file-drop per device-parity rule)
- Robust export/import + **exhaustive validation** (strict schema, ID whitelist, bounds, complexity limits)
- **Catalog build from the Drive** (ADR-010): shipped **capable-but-empty** — the pipeline (download per id, `sha256` verify, local cache, pack into PCK) exists, but community content travels to players **only through game updates**, never from the Drive (augmentative post-V1, ADR-010); the 1st-party catalog already shipped in PCK at P10
- Mention system requirements on distro pages: **Vulkan required** (no OpenGL fallback)
- Built-in tutorial riding on the example world (P11)
- Creator docs (brief — **markdown in repo**, `creator_docs/`; revised at usage)

**Horizon (if traction)** : Steam Workshop.

**Done** : a player creates a world and exports it; another imports it and plays in it without issue.

---

## P13 — Hardening

**Goal** : the low-end target (Forward+ low), the polish.

**Deliverables**
- **Quality tiers** calibrated on the **real HD4600** — bench of 12/09: Forward+ low ≈ 55 avg / 32 p95 fps → the "low-end" tier holds the ~30 fps stable target (primitives bench only — the P2 skinning + shadows spike was dropped 21/09/2026, residual risk accepted)
- Automatic dropping of heavy features if a hardware floor is detected (PCSS, SSAO, volumetrics, per-zone light cap)
- Various polish (LOD, draw call splitting, batching of cloned mobs)

**Done** : quality tiers operational; the game holds ~30 fps stable on the HD4600 in Forward+ low (calibrated on the primitives bench — P2 spike dropped 21/09/2026).

---

## Major risks

- **Assets = bottleneck** (we are dev, not artist): stylistic consistency between disparate sources (e.g. Quaternius = low-poly, not "anime"). Mitigation: **1st-party starter catalog as a V1 deliverable (P10/P11, ADR-017)** + cohesion through the base toon shader + imposed palette (ADR-019); community submissions are post-V1 augmentative, never a release dependency (P1 in temporary low-poly accepted).
- **Data format drift** → versioning + validator from P0/P1, never a silent deletion.
- **Low-end tier drift** → the only remaining renderer risk after dropping Compatibility (12/09): the low settings, now with **real shadow maps** (ADR-019), must stay sustainable. The P2 skinning + shadows spike was dropped (21/09/2026), so tiers rest on the primitives bench. Mitigation: re-bench at P13 on the real game if the HD4600 is still the floor target.
- **Over-scoping** → each phase has a measurable "done" criterion; the maker is the product, not the gameplay nor the cinematics.
- **Toolkit scope pressure (ADR-018)** → the V1 combat toolkit has its own gray-box phase (P3) with a hard "done" criterion; its integrations spread across P5 (narrative verbs), P7 (progression/HUD/resists) and P8 (equipment/ammo). Mitigation: 🟡 items settled at the P3 design pass; a prototype/deep-pass split at P3 exit; re-slim during P3 is allowed — the net (`features.md`) keeps completeness either way, only phase placement moves.
- **Visual-style drift (ADR-019)** → the cel/toon look is a V1 identity element, not a preference. Mitigation: base shader + palette live in P1 and are enforced at intake on every catalog stream; face light treatment gray-boxed at P4 (with the face system).

## Open questions (to settle along the phases)

> Completeness net: the complete final-game scope lives in `features.md` (every feature, with status). That file is the "what is missing?" reference — this list below is only the still-open *decisions*.

- ~~Full detail of the JSON world/character schema (versioning, sockets, mission fields)~~ — **resolved**: `data/schema/world_v0.1.json` (sockets, graph, ambiance, content) + `character_v0.1.json` + `versioning.md`. Mission/quest fields: no quest system in V1 — the world schema tolerates unknown fields until/unless a quest schema exists.
- Editor: in-game (Mario Maker style) — this is the retained direction, to confirm at P1.
- Flags registry granularity (single global = retained).
- Exact boss editor scope (post-V1, vault).
- Starter catalog **pack selection** (which exact CC0 kits + Mixamo actions) — decided at P1/P10 (sourcing direction settled: CC0 + Mixamo re-targeted, ADR-017).
- Post-V1 vault (deferred by decision, not forgotten): NPC vendor shops, magic spells, weapon arts, audio (system/music/SFX — ADR-014), cinematics — area cards, boss intro, cutscenes (ADR-014), **boss editor** (state machine, phases), emotes, elevators/moving platforms, weather, respec, **fast travel (bonfire warp — design kept for post-V1)**, NG+, ink outlines (ADR-019), CI workflow (headless import check + export smoke test) once the repo has real content, **kick, parry + riposte + critical stance** (cut from P3 21/09/2026 — frozen spec in `features/17`).
- Combat depth open items (ADR-018, → P3 design pass, values pinned in `features/17`): ~~parry window + critical stance~~ (cut to V2 21/09/2026); ~~two-handing strength-scaling~~; ~~kick guard-break feel~~ (kick cut to V2 — blade-shove readability stays at P3); ranged lock-on/aim + ammo-economy feel; temporary buff/debuff duration bounds.
