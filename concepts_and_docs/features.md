# SoulMaker — Feature list (complete final-game scope)

> The **master completeness net**: every feature the final game could have, one line each, whatever its status. Ask "what is missing?" against this file, not against the roadmap. Companion to `roadmap.md` (when), `decisions.md` (rules), `screens.md` (where it shows). Details live in those docs — this file only tracks existence + status.

**Maintenance contract** : every new feature lands here **first** (with a status); an ADR and/or a roadmap entry may then implement it. A status change must stay in sync with `decisions.md`.

## Status legend

- 🔒 **V1 locked** — decided, in V1 (ADR/roadmap)
- 🟡 **V1 pending** — in V1 scope, design decision still open
- 🔵 **Post-V1 (vault)** — deferred by decision
- ⚫ **Out of scope** — explicitly excluded
- ❔ **Open question** — not scoped yet

**V1 = the public launch build** (the complete installable game at first release). Post-V1 = every addition after that build. The V1 ships with a **1st-party starter catalog** (CC0 + re-targeted, ADR-017); the community pipeline is augmentative post-V1.

Legend per column: *Phase* refers to the roadmap phase (P0-P13); *Ref* points to ADR / screen / roadmap.

---

## 1. Gameplay core — player

| Feature | Status | Phase | Ref | Notes |
|---|---|---|---|---|
| Third-person controller (locomotion) | 🔒 | P2 | roadmap P2 | |
| Orbit camera + lock-on | 🔒 | P2 | roadmap P2 | |
| Dodge + i-frames | 🔒 | P2 | roadmap P2 | |
| Stamina economy | 🔒 | P2 | roadmap P2 | Endurance-based |
| Combat feel: windup/attack/release markers | 🔒 | P2 | roadmap P2, idea.txt | |
| Upper/lower body layers (combos) | 🔒 | hors V1 | roadmap P2 | P0 spike FAIL 15/09/2026 — Blend2 somme des poids = 1, pas de superposition bas/haut ; décision sortie P2 (21/09/2026) : reporté hors V1 |
| Hitstop, screen shake, hit reactions | 🔒 | P2 | roadmap P2 | |
| Blade rebound, easing, variation | 🔒 | P2 | roadmap P2 | |
| Swept `ShapeCast3D` hitbox, masked off-attack | 🔒 | P2 | roadmap P2 | spike P0 REPORTED — technique déjà choisie, validation en amont de P2 |
| Controller rumble (haptics) | 🔒 | P2 | roadmap P2 | On/off + intensity in Options (P2) |
| Foot IK | 🔒 | P0 | roadmap P0 spike | spike FAIL 15/09/2026, abandonné — à retester en V1 |
| Block / guard (stability, stamina drain, guard break) | 🔒 | P3 | features/17 | Guard via shield or weapon (shared stat block — every item carries guard values); two-handing keeps guard (weapon values); break = extended punish stagger (stance/riposte = V2) |
| Criticals: backstab direct (P3) ; parry / riposte (V2) | 🔒 | P3 / V2 | features/17 | Backstab = positional trigger ±30° / 0.6 s → immediate crit ×1.5-×2, feel validated at P3 ; parry+stance+riposte cut to V2 21/09/2026 (frozen spec: light 8-12 f / medium 6-8 f / great none, stance 1.5 s) |
| Ranged weapons (bow/crossbow): draw/hold, ranged lock-on, ammo economy | 🔒 | P3 | features/17 | Ammo = base item (`§3`, P8); feel settled at P3 |
| Damage types (physical slash/thrust/strike + elemental fire/lightning/magic/dark) + status build-up (bleed/poison/frost) + resistances | 🔒 | P3/P7 | features/17 | 7 types (elemental joins V1 via resins/bundles — ADR-018); **armor-dominant philosophy + additive `resist-push`** (resolved 13/09/2026); mechanics at P3; derived resists at P7; feeds weaknesses (`§4`, P9) |
| Player poise / hyper-armor (heavy weapons trade through hits) | 🔒 | P3 | features/17 | |
| Equip-load roll tiers (fast / mid / fat) | 🔒 | P3 | features/17 | Derived from equip load (ADR-011) |
| Backstep | 🔒 | P3 | features/17 | |
| Plunging attacks (drop on a target below) | 🔒 | P3 | features/17 | |
| Two-handed grip (moveset + strength scaling) | 🔒 | P3 | features/17 | STR ×1.5 (min-req + scaling); keeps guard via weapon values, stamina unchanged; delivers with STR at P7 (parry = V2, nothing to cancel in V1) |
| Push / shove guard-break (heavy classes P3, kick V2) | 🔒 | P3 / V2 | features/17 | Forward + light attack (universal input); blade-shove ~60-80 stability-equivalent on heavies → guard break → extended punish stagger ; kick cut to V2 21/09/2026 ; shove readability feel-validated at P3 |
| Weapon / shield stat block (unified — every weapon guards, every shield attacks) | 🔒 | P3 | features/17, features/04 | `{damage, damage_type, guard_absorb, stability, block_arc, weight, poise}` + `parry_window` reserved on shields (0 in V1, active V2) |
| Ladders (climb up/down locomotion) | 🔒 | P3 | features/17, features/07 | Interactive level object |
| Held torch (player-attached light) | 🔒 | P3 | features/17 | Tool slot, distinct from world fixtures |
| Weapon arts | 🔵 | — | roadmap P7 V2 note | |
| Casting / spells | 🔵 | — | roadmap P7 V2 note | FP framework in V1 |

## 2. Progression (ADR-011)

| Feature | Status | Phase | Ref | Notes |
|---|---|---|---|---|
| 8 canonical attributes + derived mappings | 🔒 | P7 | ADR-011 | Vigor, Mind, Endurance, Strength, Dexterity, Intelligence, Faith, Arcane |
| Single level-up cost curve by total level | 🔒 | P7 | ADR-011 | Base-owned, never creator-tuned |
| Currency (souls) accumulation | 🔒 | P7 | ADR-011 | Kills + items |
| Bonfire / grace object (respawn + refill + level-up) | 🔒 | P7 | ADR-011, screens* | Unlock state persisted |
| Estus healing (rechargeable, bonfire refill) | 🔒 | P7 | ADR-011, ADR-012 | Bounded upgrades via catalog |
| Death: souls drop + soul orb recovery | 🔒 | P7 | ADR-013 | Second death = loss |
| Drop tables per enemy (bounded) | 🔒 | P8 | ADR-012 | Currency + one possible item |
| Equipment min-attribute requirements | 🔒 | P8 | ADR-012 | Validated at import |
| Run start = fixed base template | 🔒 | P7 | ADR-011 | No classes, not world-configurable |
| World display overrides (`stat_names` + `currency_name`) | 🔒 | P7 | ADR-011 | Labels only, canonical ids in data |
| NPC vendor shops | 🔵 | — | roadmap P7 V2 note | |
| World-level bounded tuning (drop multiplier, death penalty toggle) | 🔵 | — | ADR-011 headroom | Deferred, not V1 |
| Fantasy-themed stat/cost variants | ⚫ | — | ADR-011 | Mechanics are base-fixed |

## 3. Inventory & equipment (ADR-012)

| Feature | Status | Phase | Ref | Notes |
|---|---|---|---|---|
| Equipment slots (weapon, offhand shield, clothing, helmet, chest armor, gauntlets, leggings, accessory ×4) on the rig | 🔒 | P8 | ADR-012 | Clothing = painted texture set (0 stats, `02/04`); armor pieces via `BoneAttachment`/`Marker` (P4); **accessory = ×4, no same-id, no rig visual** + `accessory_name` override (13/09/2026) |
| Consumables quickbar | 🔒 | P8 | screens* | |
| Estus charges in inventory/HUD | 🔒 | P8 | ADR-012, screens* | |
| Key items (flags-gated) | 🔒 | P8 | ADR-012 | Flags from P5 |
| Light stat payload (damage, damage type, weight, poise, resistances) | 🔒 | P8 | ADR-012 | Bounded |
| Loot objects: chests, corpses, pickups | 🔒 | P8 | roadmap P8 | Placed in map editor |
| Base item types (estus, consumables, key items, currency) | 🔒 | P8 | ADR-012 | Base-provided only; V1 starter subset = per-family bounding policy (13/09/2026); exact instance list at P10 (ADR-017) |
| Offhand shield slot | 🔒 | P8 | ADR-012, features/17 | Pairs with combat guard (`§1`, P3) |
| Ammunition as base item type | 🔒 | P8 | ADR-012 | Magic-free ranged economy (P3 feel) |
| Accessory / ring slot (×4, no rig visual) | 🔒 | P8 | features/04, features/17 | No same-id stack; display name per world `accessory_name` (default "ring"); data item — no mesh |
| Homeward bone (return to last bonfire) | 🔒 | P8 | features/03 | Disposable consumable |
| Weapon resins / bundles (elemental + status coatings) | 🔒 | P8 | features/04, features/17 | 60 s resin / 5 s fast bundle; elemental in V1 (7 damage types) |
| Status cures (moss per V1 status) | 🔒 | P8 | features/04 | Bleed / poison / frost counters |
| Throwables (throwing blades, firebombs, aggro-bait, ground hazard) | 🔒 | P8 | features/04 | Universal no-magic ranged tools |
| Soul items (consumable currency) | 🔒 | P8 | features/04 | Bankable souls, drop/loot only |
| Buff / debuff temporary effects (items + environment) | 🔒 | P8 | features/17 | Duration = per buff object (no global preset); no `has_buff` in V1 conditions (resolved 13/09/2026) |
| Item description / lore text (creator-authored) | 🔒 | P5 | features/04 | Lore carrier on items |
| Crafting / upgrades system | ⚫ | — | — | Excluded V1, not in vault |
| Selling / trading | 🔵 | — | ADR-011 | Shops deferred |

## 4. Enemies & bosses

| Feature | Status | Phase | Ref | Notes |
|---|---|---|---|---|
| 1 simple enemy archetype | 🔒 | P2 | roadmap P2 | Aggro, telegraph, hit reaction, poise |
| Archetypes + bounded morphs | 🔒 | P9 | ADR-007 | Variety through combinatorics |
| AI behavior: aggro, telegraph, breaks | 🔒 | P2/P9 | roadmap P2/P9 | |
| Enemy activation on proximity (sleep until near) | 🔒 | P6 | features/05 | Paired with fragment streaming |
| Behavior pattern editing (data-driven) | 🔒 | P9 | screens* character/enemy | |
| Boss editor (state machine, phases) | 🔵 | — | vault | "Late chapter, not V1" |
| Boss-level enemies in V1 (`boss_level` marker) | 🔒 | P7 | features/05 | Archetype + marker + bounded stat multipliers; no phases in V1 |
| Multi-boss / gank encounters authoring | 🔒 | P9 | roadmap P9 | Placement-level: N archetypes + optional `boss_level` markers; no dedicated encounter system (resolved 13/09/2026) |
| Per-enemy weaknesses / resistances (bounded damage-type table) | 🔒 | P9 | features/17 | Feeds the damage-type layer (`§1`) |

## 5. Narrative layer (P5)

| Feature | Status | Phase | Ref | Notes |
|---|---|---|---|---|
| Flags registry declared before use | 🔒 | P5 | ADR-008 | + `initial_values` |
| Conditions/effects engine | 🔒 | P5 | roadmap P5 | Base verbs: `set_flag`, `clear_flag`, `give_item`, `remove_item`, `unlock_shortcut`, `trigger_event`, `apply_buff` (+ `open_shop` inert until shops); post-V1 extension verbs (`play_animation`, `set_weather`); conditions: `has_item`, `item_not_full`, `boss_defeated`, ... (no `has_buff` in V1 — 13/09/2026) |
| Dialogue graph (`line`/`choice`/`conditional`/`exit`) | 🔒 | P5 | roadmap P5 | Speech = text only (no voice, no lip-sync — resolved 13/09/2026) |
| Global events reacting to flags | 🔒 | P5 | roadmap P5 | Doors, NPC, hostile zones |
| Lore notes on objects/places | 🔒 | P5 | roadmap P5 | |
| Graph validation tool | 🔒 | P5 | roadmap P5 | Broken gotos, orphan flags |
| Quests / mission objectives UI | 🔒 | — | features/08 | Resolved: no quest tracker in V1 — flags are silent; narrative via dialogue/events/lore |

## 6. Worlds & levels

| Feature | Status | Phase | Ref | Notes |
|---|---|---|---|---|
| Prefab system (Level 1 of construction) | 🔒 | P1 | screens* prefab | Group + save |
| Map assembly (Level 2) | 🔒 | P1 | screens* map | Free placement, overlaps ok |
| Sockets + world graph (Level 3) | 🔒 | P6 | ADR-005, screens* | Discrete points, directional links |
| Fog transitions | 🔒 | P2/P6 | screens* | Double as loading screen |
| Ambiance: world defaults + per-map override | 🔒 | P6 | ADR-005 | Sun, fog, tonemapping |
| Per-world GameState persistence | 🔒 | P6 | roadmap P6, ADR-011 | Boss, chests, levers, bonfire state |
| Fog gates (blocking doors, flags-gated) | 🔒 | P5/P7 | roadmap P5 | Open on boss killed / key item used |
| Spawn points (world-level) | 🔒 | P2/P6 | screens* | New run + transitions |
| Fast travel between lit bonfires | 🔵 | — | — | Post-V1; warping deferred |
| Backdrops (neutral distance planes) | 🔵 | — | roadmap P6 V2 | Auto placement |
| Photo impostors (content-keyed hash cache) | 🔵 | — | roadmap P6 V2 | |

## 7. Editors (Create)

| Feature | Status | Phase | Ref | Notes |
|---|---|---|---|---|
| Home = two-door hub (Play / Create) | 🔒 | P1 | screens* home | Contextual Continue per door |
| Map editor: fluid camera, orbit/zoom | 🔒 | P1 | roadmap P1 | |
| Free transform gizmos, no snap by default (0.1 fine) | 🔒 | P1 | roadmap P1 | Anti-grid identity |
| Catalog panel (arrows/D-pad browse + A/E place, no drag & drop) | 🔒 | P1 | roadmap P1 | 5-6 test assets |
| Floor + ambiance presets (fog + tonemapping) | 🔒 | P1 | roadmap P1 | |
| Bounded directional sun + embedded lights | 🔒 | P1 | roadmap P1 | Torches, fireplaces |
| One-key instant playtest (editor ↔ player) | 🔒 | P1 | roadmap P1 | |
| Undo/redo | 🔒 | P1 | screens* map | |
| Light count bound + editor counter | 🔒 | P1 | idea.txt | Inform creators |
| JSON save/load + validation at import | 🔒 | P1/P6 | ADR-009 | |
| Prefab editor | 🔒 | P1 | screens* prefab | |
| World editor (graph, sockets, ambiance) | 🔒 | P6 | screens* world | |
| Character editor (player / NPC / enemy) | 🔒 | P4 | screens* | Shared base |
| Dialogue link on NPC | 🔒 | P5 | screens* | |
| Behavior pattern link on enemy | 🔒 | P9 | screens* | |
| Character config JSON export/import (graceful fallback) | 🔒 | P4 | roadmap P4 | |
| Drop table editing per enemy | 🔒 | P8 | ADR-012 | Bounded |
| Editor error surfacing + validation banner (jump-to) | 🔒 | P1 | features/09 | Inline errors at save/export/preview |
| Ladders (climbable level objects) | 🔒 | P3 | features/07 | Uses §1 climb locomotion |
| Illusory walls (disappear on trigger/roll) | 🔒 | P5 | features/07 | World object + flag |

## 8. Character system (P4)

| Feature | Status | Phase | Ref | Notes |
|---|---|---|---|---|
| Standard humanoid skeleton + re-targeted animations | 🔒 | P2/P4 | ADR-006 | Shared animation ecosystem |
| Attachment slots (hair, ears, equipment) | 🔒 | P4 | roadmap P4 | |
| Clothing layer (painted fitted textures, 0 stats — creation + swappable in-game) | 🔒 | P4 | features/02, features/04 | Base-skin layering: clothing under every armor overlay |
| Armor as 3D overlay (helmet/chest armor/gauntlets/leggings shells on rig sockets) | 🔒 | P8 | features/02, features/04 | Fit rule: starter shares base morphs, community = clearance vs max-morph (@ intake) |
| Bounded morphs / blend shapes, linked sliders | 🔒 | P4 | ADR-007 | |
| 2D face layers + blend shapes | 🔒 | P4 | idea.txt, features/02 | 5 overlay layers max (hair, brows, beard, scar, paint…) |
| NPC = base form + a few morphs (5 variants) | 🔒 | P4/P9 | features/08 | Same base as player |
| Character perf budget (≤10 unique, hordes via MultiMesh) | 🔒 | P13 | features/02 | Monsters: low-poly + shared material |
| Same base for player / NPC / enemy | 🔒 | P4 | roadmap P4 | Config = source of truth |
| Per-instance mesh duplication (blend shape quirk) | 🔒 | P4 | idea.txt | `duplicate()` pattern |
| Shared animation library (locomotion, melee) | 🔒 | P2 | roadmap P2 | |

## 9. Catalog & asset pipeline (ADR-010 / ADR-017)

| Feature | Status | Phase | Ref | Notes |
|---|---|---|---|---|
| Test assets (5-6 items, dev-speed exception) | 🔒 | P1 | ADR-010 | Seed of the starter catalog; live in repo |
| **Starter catalog 1st-party (launch content)** | 🔒 | P10 | ADR-017 | CC0 packs + Mixamo re-targeted; same validation/manifest/credits; packed in PCK |
| Catalog manifest JSON in git (schema v0.1) | 🔒 | P0 | ADR-010, asset_pipeline.md | Schema written (`data/catalog/schema_v0.1.json`) |
| Drive storage (`pending/` → `approved/`) (community) | 🔵 | P12 | ADR-010 | Post-V1 augmentative stream |
| Build: download by id + sha256 + cache | 🔵 | P12 | ADR-010 | For community assets; 1st-party uses local source |
| Credits screen fed by manifest | 🔒 | P10 | ADR-017 | From the starter catalog manifest |
| Headless import validation (maintainer check) | 🔒 | P0 | asset_pipeline.md | Checklist complete (both streams); `import_check.gd` written with the code — revised at usage (13/09/2026) |
| Audio assets in catalog ("a sound") | 🔵 | — | ADR-014 | Deferred with the whole audio pillar |
| Community submissions via Discord | 🔵 | P12 | ADR-010 | Post-V1 augmentative, never a V1 dependency |

## 10. UI / Screens

| Feature | Status | Phase | Ref | Notes |
|---|---|---|---|---|
| Boot screen | 🔒 | P0/P12 | screens* | Logo, version |
| Options (graphics tiers, audio, controls, interface) | 🔒 | P1/P13 | screens*, ADR-002 | Low-end tier first-class; Controls: gamepad layout rows + keyboard per-key (resolved 13/09/2026) |
| World library (import + play in) | 🔒 | P12 | screens* | |
| New game flow (world → character → spawn) | 🔒 | P2/P4/P7 | screens* | |
| Level-up screen (bonfire) | 🔒 | P7 | screens* | Bounded sliders |
| Inventory / equipment screen | 🔒 | P8 | screens* | |
| HUD (HP, stamina, souls, estus, quickbar, buffs) | 🔒 | P7 | screens* | Buff icon strip: cap 4 + "+N", depleting ring (13/09/2026); FP bar only with FP content |
| Boss HP bar (HUD element, no cinematic) | 🔒 | P7 | screens* | For boss-level enemies |
| Accessibility toggles (screen-shake reduction, UI scale, subtitle) | 🔵 | — | features/16, features/11 Options | Post-V1 (resolved 13/09/2026); rumble stays a P2 base setting |
| No in-game pause (souls convention) — hub menu at bonfire (options/save/quit/level-up) | 🔒 | P2 | screens* | Full menu only at a bonfire |
| Death / respawn screen ("your souls await") | 🔒 | P2/P7 | screens*, ADR-013 | |
| Socket/fog transitions | 🔒 | P2/P6 | screens* | |
| Import/export flows + "user content" disclaimer | 🔒 | P1/P12 | screens* | World via Play, prefab/char via Create |
| Credits / attribution | 🔒 | P10 | ADR-017 | From the starter catalog manifest |
| Contextual Continue (Play recent / Create recent) | 🔒 | P1 | screens*, ADR (hub) | |
| Photo mode | ⚫ | — | — | No value / cost ratio in a maker |

## 11. Distribution (P12)

| Feature | Status | Phase | Ref | Notes |
|---|---|---|---|---|
| Local hub + file-picker import (no OS file-drop) | 🔒 | P12 | roadmap P12 | |
| Robust export/import + exhaustive validation | 🔒 | P12 | ADR-009 | Strict schema, whitelists, bounds |
| Catalog built into the game PCK | 🔵 | P12 | ADR-010 | Community assets via updates (1st-party ships at P10) |
| "Vulkan required" notice + requirements display | 🔒 | P12 | ADR-002 | No OpenGL fallback |
| Example world (starter catalog manifesto) | 🔒 | P11 | roadmap P11 | Hackable template, built from 1st-party catalog (P10) |
| Built-in tutorial (rides on the example world) | 🔒 | P12 | roadmap P12 | |
| Creator docs (brief) | 🔒 | P12 | roadmap P12 | Markdown in repo (`creator_docs/`) — revised at usage (13/09/2026) |
| Steam Workshop | ❔ | — | roadmap P12 horizon | If traction |

## 12. Platform / tech

| Feature | Status | Phase | Ref | Notes |
|---|---|---|---|---|
| Godot 4.7 + Jolt + GDScript | 🔒 | P0 | ADR-001 | |
| Forward+ only (no Compatibility fallback) | 🔒 | P0 | ADR-002 | Vulkan required |
| Quality tiers + auto-drop heavy features | 🔒 | P13 | ADR-002, ADR-019 | PCSS, SSAO, volumetrics, light cap; real shadow maps on the toon look |
| HD4600 low-end calibration (skinning + shadows spike) | 🔒 | P13 | ADR-002 | Spike P2 droppé 21/09/2026 — tiers calibrés sur le bench primitives uniquement, risque résiduel accepté |
| Save/run serialization (GameState) | 🔒 | P6/P7 | screens* save/run, ADR-012 | |
| Multiple parallel runs per world | 🔒 | P7 | ADR-015 | Load lists runs |
| Save integrity / crash recovery | 🔒 | P7 | ADR-016 | Atomic write, corruption detection |
| Select another run from the menu | 🔒 | P7 | ADR-015, screens* load | Main menu only (Play → Load); no run switch mid-game — quit only at a bonfire (resolved 13/09/2026) |
| JSON versioning + never break format | 🔒 | P0 | ADR-009 | |
| Git repo (init on `main`, no commit yet) | 🔒 | — | — | First commit pending |
| Localization (UI string system) | 🔒 | P2 | features/11, features/16 | Keyed string table from the first UI; English only + no selector in V1 (languages V2, resolved 13/09/2026) |
| Audio system / pipeline | 🔵 | — | ADR-014 | Music/synth concept in vault, Options volumes = inert shell |
| CI workflow (headless import + export smoke) | 🔵 | — | open q. | Needs real content first |
| Achievements | ⚫ | — | — | No server (ADR-004), not worth it |
| Co-op / multiplayer | ⚫ | — | idea.txt | Solo-only decision |
| Server / leaderboards / auth | ⚫ | — | ADR-004 | No server |
| Modding / arbitrary creator code | ⚫ | — | ADR-004 | Data-only |
| Standalone game export | ⚫ | — | idea.txt 220-238 | Code-signing / liability / version fragmentation |

## 13. Visual style & rendering (ADR-019)

| Feature | Status | Phase | Ref | Notes |
|---|---|---|---|---|
| Cel/toon look mandatory on all 3D (base toon shader: `diffuse_toon` + shadow ramps) | 🔒 | P1 | ADR-019 | World, characters, enemies, effects; UI/screens stay standard |
| Real shadow maps (entities + environment) — no blob shadows | 🔒 | P2 | ADR-019 | Low-end budget via quality tiers (§12); re-confirmed on the shadow bench |
| Imposed palette + texture-mapping rules (front-unfold face UV, two-texture split) | 🔒 | P1 | ADR-019, features/10 | Applied at intake, both streams |
| Anime face light treatment (SDF shadow, Genshin-like) | 🟡 | P4 | ADR-019, features/02 | Keeps the 2D face readable under cel light — ships with the P4 face system |
| Ink outlines (post-process / inverted hull) | 🔵 | — | ADR-019 | Excluded in V1 — fragile to get right |

## 14. Vault (Post-V1, non-priority)

| Feature | Status | Ref |
|---|---|---|
| NPC vendor shops | 🔵 | roadmap P7 V2 note |
| Magic content (spells → FP bar meaningful) | 🔵 | roadmap P7 V2 note |
| Weapon arts | 🔵 | roadmap P7 V2 note |
| Cast speed effects (Dexterity) | 🔵 | roadmap P7 V2 note |
| Backdrops | 🔵 | roadmap P6 V2 |
| Photo impostors | 🔵 | roadmap P6 V2 |
| Audio (system + music/synth/tracker editor + SFX) | 🔵 | ADR-014 |
| Cinematics & presentation (area cards, boss intro, cutscenes) | 🔵 | ADR-014 |
| Emotes / gestures | 🔵 | — |
| Elevators / moving platforms | 🔵 | — |
| Weather particles (ambiance presets) | 🔵 | — |
| Respec at bonfire | 🔵 | — |
| Fast travel (bonfire warp) | 🔵 | — |
| New game+ | 🔵 | — |
| CI workflow | 🔵 | — |
| Steam Workshop | ❔ | roadmap P12 horizon |

---

## Open questions (consistency with roadmap.md)

Captured in `roadmap.md` → Open questions; mirrored here as status ❔/🟡 rows above:
- ~~Full JSON world/character schema detail (P0)~~ — **resolved**: `data/schema/` (world_v0.1, character_v0.1, prefab_v0.1) + `versioning.md`.
- In-game editor direction (Mario Maker style — retained, confirm at P1).
- Flags registry granularity.
- Exact boss editor scope (post-V1).
- Animation/source selection per licenses.
- Post-V1 vault items (shops, spells, arts, audio — ADR-014, cinematics — ADR-014, emotes, elevators, weather, respec, fast travel, NG+, CI).
- ~~Full gamepad mapping detail (options: preset rows vs per-button)~~ — **resolved 13/09/2026**: gamepad = bounded layout rows (Souls default + alternates, physical button ids), keyboard = full per-key remap; per-button gamepad remap joins the post-V1 accessibility group.
- ~~Editor gamepad ergonomics (🟡 §16 "keyboard/gamepad both usable")~~ — **resolved 16/09/2026**: data-driven `InputManager` autoload, R1 shift/gesture set, no modal modes; keyboard follows the same action set. See `concepts_and_docs/editor_input_mapping.md`.
- ~~Damage numbers vs bars-only for hosts (souls convention = bars)~~ — **resolved 13/09/2026**: bars-only in V1 — no flying damage numbers, no souls pop-text.
- ~~Equip-load roll-tier thresholds (🟡 `§1` — P3)~~ — **resolved 13/09/2026**: <30% / <70% / ≥70% (fast/mid/fat).
- ~~Backstep i-frames (🟡 `§1` — P3)~~ — **resolved 13/09/2026**: none — spacing only, the dodge stays the unique invuln tool.
- ~~Plunging attack input (🟡 `§1` — P3)~~ — **resolved 13/09/2026**: attack key buffered mid-fall (no auto-trigger).
- ~~Kick per-weapon scope (🟡 `§1` — P3)~~ — **cut 21/09/2026**: kick → V2 (reads arbitrary next to heavy blades); blade shove on heavy classes stays in P3 under the universal forward+light input.
- ~~Torch: water + darkness knob (🟡 `§1`/`§7`)~~ — **resolved 13/09/2026**: torch stays lit in water; darkness purely visual in V1.
- ~~Accessory slot (single vs share-offhand, 🟡 `§3`)~~ — **resolved 13/09/2026**: 4 slots, no same-id, no rig visual; world display name `accessory_name` (default "ring").
- ~~Parry window + critical stance tuning (🟡 `§1` — P3 design pass)~~ — **cut 21/09/2026**: parry + stance + riposte → V2 (no feel jury — dev never parries; frozen spec kept in `features/17`); backstab stays P3 as a direct positional crit.
- ~~Ranged lock-on/aim feel (🟡 `§1` — P3 design pass)~~ — **resolved 13/09/2026**: lock-on follows the target (souls-style); residual reticle/ammo feel tuned at P3.
- ~~Two-handed grip scaling modifier (🟡 `§1` — P3 design pass)~~ — resolved: STR ×1.5 (min-req + scaling); stamina unchanged.
- ~~Temporary buff/debuff duration bounds (🟡 `§3` — P7)~~ — **resolved 13/09/2026**: duration is a per-object config field, no global preset list; `has_buff` excluded from the V1 `08` condition grammar.

- ~~NPC speech style (dubbed vs text, 🟡 §5/§13)~~ — **resolved 13/09/2026**: text only — no voice, no lip-sync; face keeps the generic talk loop (~5-8 poses @ 12fps), visemes dropped.
- ~~Gamepad mapping detail (preset rows vs per-button, 🟡 §11/§16)~~ — **resolved 13/09/2026**: gamepad preset rows + keyboard per-key (see §11 default table).
- ~~Elemental balance / resist philosophy (🟡 §1/§3)~~ — **resolved 13/09/2026**: armor-dominant 7-pool + per-type stat baseline + accessory `resist-push` additive; rosette 4-band tags ×0.5…×1.25, boss band ×0.85–×1.15.
- ~~Buff icon footprint (🟡 §11/§16)~~ — **resolved 13/09/2026**: minimal catalog strip, 4 visible + "+N", depleting ring = time left; status meters separate.
- ~~V1 item subset per family (🟡 §3)~~ — **resolved 13/09/2026**: per-family bounding policy + body-buff roster (3) + disposable-heal bounds (25-50 % max HP, ≤10 stack, not rechargeable) in-doc; exact instance list = P10 (ADR-017).
- ~~Lock-on tap vs hold (🟡 §1 — P2 prototype)~~ — **resolved 13/09/2026**: tap-to-lock / camera-lean tap-to-switch / tap-to-unlock, no hold; R3 binding (`§11`).
- ~~Soul-orb recovery beacon (🟡 §3)~~ — **resolved 13/09/2026**: faint golden pulse through geometry while the orb awaits (`orb_state` present); no arrow/compass.

## Source of truth / sync

- **Status** lives here; **rules** lives in `decisions.md`; **sequencing** in `roadmap.md`; **UI** in `screens.md`. When you change one, update the others.
- This file is the **completeness net** — run the "what is missing?" review against it, not against the roadmap.
