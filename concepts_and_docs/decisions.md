# SoulMaker — Decision records (ADR)

> Every founding decision is tracked here with its rationale and context. A decision is never irreversible, but changing an entry here requires updating `roadmap.md` and the phases depending on it.

## ADR-001 — Godot 4.7, Jolt, GDScript

**Status** : locked.
**Rationale** : engine choice ratified in the discussions (runtime blend shapes, editor tooling, lightweight). Jolt already active in `project.godot`. GDScript for all tooling (see AGENTS.md).

## ADR-002 — Forward+ only, no Compatibility fallback

**Status** : locked (Forward+ exclusive). Revised on 12/09/2026 — the Compatibility path was dropped following the HD4600 benchmark (was "dev in Forward+, Compatibility target at final hardening", then "export fallback").

**Initial postulate overturned** : "the HD4600 has no Vulkan" is false on Linux (Mesa HASVK driver — partial Vulkan but enough to run Godot Forward+). The question that actually mattered was therefore: *does Compatibility do better on this machine?* — the measured answer is **no**, and it confirms Philippe's earlier tests (Compatibility degraded performance instead of improving it).

**Real HD4600 benchmark** (Godot 4.7.2, 1280x720, P2-representative case: ~40 meshes, shadowed directional light, 16 point lights, fog, 4 animated characters; ~1600-2200 frames/run):

| Renderer | avg fps | p95 fps | p99 fps | % frames > 33 ms |
|---|---|---|---|---|
| Forward+ high | 40.1 | 28.0 | 21.2 | 6.5 |
| Forward+ low (scaling .6, 8 lights) | **55.1** | **31.9** | 23.0 | **3.2** |
| Compatibility high | 34.8 | 23.2 | 18.9 | 17.0 |
| Compatibility low | 40.5 | 22.7 | 17.8 | 13.3 |

**Reading** : Forward+ wins on every setting, and the gap widens precisely where it matters for a souls-like — stability (p95/p99, % slow frames). The "Compatibility safety net" was not a net: it was the worse option. (Bench on primitives only; the **skinning** cost still to be measured at P2 on the real rig.)

**Decision** : **Forward+ is the project's only renderer — no Compatibility fallback, neither in dev nor at export.** Permanent hardware requirement: **Vulkan required** (no OpenGL path). The low-end target is served exclusively by **quality tiers** (render scale, MSAA, shadow quality, per-zone light cap, automatic dropping of heavy features — PCSS, SSAO, volumetrics — according to the detected hardware floor). No intersection constraint: all features are developed in Forward+.
**History (trace)** : the Compatibility path (hardening pass, then export fallback for Vulkan-less GPUs) was dropped on 12/09/2026: slower, less stable, never better at any setting.

## ADR-003 — First prototype: map editor

**Status** : locked.
**Rationale** : the maker IS the product. We prove the loop "place → play → place" + serialization from day 1, before the combat.

## ADR-004 — All data, no server

**Status** : locked.
**Rationale** : solo enthusiast, no infra budget; free servers exclude the games. Sharing through JSON files (no zip — readability and validation at import), solo-only, never arbitrary client-side code.

## ADR-005 — Worlds = graph of zones connected by sockets

**Status** : locked.
**Rationale** : no chunk streaming (too heavy for amateur creators). Small self-sufficient zones + links through discrete points (position/orientation), fog transitions. Largely sufficient and simple to tool.
**Ambiance (precision)** : sun and fog are configured **at the world level as defaults, with an optional per-map override** (e.g. a dark cave inside a sunny world). The world defines the baseline identity; a map can deviate where its layout calls for it.

## ADR-006 — Assets provided by the base, standard humanoid skeleton

**Status** : locked.
**Rationale** : creators only have access to the catalog (no 3D). All animations are re-targeted onto a standard humanoid skeleton (so sources are contingent: Mixamo, Quaternius, etc. — the license will decide, not the format). A single skeleton = guaranteed shared animations.
**Community as a source (precision)** : the community is another contingent source. Community-made 3D creations soberly enter the catalog through the validated submission pipeline (see ADR-010); their licenses are tracked in the catalog manifest and feed the Credits screen.

## ADR-007 — Enemies = archetypes + bounded morphs

**Status** : locked.
**Rationale** : variety through combinatorics (bounded blend shapes, identical topology), preserved gameplay readability, zero player-produced asset. No boss editor in V1.

## ADR-008 — Flags registry declared before use

**Status** : locked (detailed in P4).
**Rationale** : eliminates ghost flags from typos, enables autocompletion + exhaustive validation + safe renaming. "Declared before use", not "generated on the fly".

## ADR-009 — Renderer/format: never break the sharing format

**Status** : permanent principle.
**Rationale** : the JSON format is the game's public API; breaking it breaks existing worlds. Versioning from v0.1, tolerance to unknown fields, never a silent deletion, a clear "created with version X" message for old worlds.

## ADR-010 — Asset pipeline: Discord → validation → Drive → build

**Status** : locked.
**Context** : git is a skill of developers, not artists. Forcing artists to learn git (PRs, manifests) to contribute 3D assets would create a barrier. The catalog must grow continuously, driven by the community, without burdening non-dev contributors.

**Pipeline** :
1. **Artists submit** their 3D creation (.glb + textures kept separate, PNG/JPG) via **Discord**. No git needed on their side.
2. **Maintainers validate** the asset: headless Godot import (errors visible), license check, bounded parameters, palette/style coherence (ADR-006/007).
3. Maintainers **upload the binaries to the Drive** (`pending/` → `approved/`).
4. Maintainers **add an entry to the catalog manifest** (JSON in git, schema v0.1 from P0): id, name, category, license, bounds, `sha256`.
5. **Build script** downloads each asset **by id** from the Drive, **verifies `sha256`**, uses a **local cache** (gitignored), and packs the assets into the game's PCK.

**Properties** :
- Asset binaries are **never versioned in git** (repo stays light; no LFS quota).
- Builds are **deterministic and reproducible** (id + hash + cache).
- Players receive the catalog through **game updates** — never from the Drive.
- The manifest feeds the **Credits screen**, the runtime catalog (whitelists), and import validation (P8 for the 1st-party catalog, P9 for community — ADR-017).

**Working detail** : see `concepts_and_docs/asset_pipeline.md`. Legacy/exception: the first few test assets (P1, 5-6 items) live in the repo as the **seed of the starter catalog** (ADR-017); the manifest remains the source of truth for the final catalog.

## ADR-011 — Player progression: fixed rules, base-controlled

**Status** : locked. *(Amended by ADR-018 — 13/09/2026: derived mappings + bounded damage-type resistances; equip-load roll tiers derive from the existing equip-load mapping.)*
**Context** : creators shape *content* (where bonfires sit, which enemies drop what), never *rules*. Exposing leveling math (stat lists, growth curves, caps) to every world would fragment the identity of the base and explode the validation surface. Same philosophy as combat and enemies: constrain the "how" to liberate the "what".

**Rules (base-owned, fixed in V1)** :
- **8 fixed canonical attributes** (Elden Ring-style, locking the stat list) :
  | Attribute (canonical id) | Derived effect |
  |---|---|
  | Vigor | Max HP |
  | Mind | Max FP |
  | Endurance | Stamina + equip load |
  | Strength | Damage scaling (heavy weapons) + equipment requirements |
  | Dexterity | Damage scaling (light weapons) + cast speed + equipment requirements |
  | Intelligence | Magic damage scaling (reserved content) |
  | Faith | Sacred damage scaling (reserved content) |
  | Arcane | Item discovery (loot), occult scaling |
- **One single level-up cost curve by total level** (Elden Ring style), base-owned — creators never tune the math.
- **Currency (souls)** : accumulated from killed enemies or consumed items. **V1 economy: no shops** — currency is only spent at the bonfire (leveling). NPC vendors are deferred outside V1.
- **Bonfire / grace** = respawn point + stat refill + opens the level-up screen (spend currency → raise a stat, bounded sliders). Its unlock state (lit/unlit) + respawn anchor persist in the run's `GameState` (P6).
- **Healing: rechargeable estus** — max charges, base-backed, refilled at the bonfire, **never a pickable consumable**. Charge count/potency may be raised by bounded catalog items (optional). Disposable consumables exist too, but the estus carries the bonfire pressure.
- **Run start = fixed base template** — starting stat spread + starting equipment defined once in the base ("start quickly"); the character config (P4) only layers appearance on top. No classes, not world-configurable in V1.
- Creators place the content (bonfires, drop tables, loot) through the catalog — see ADR-012. Equipment may require minimum attribute values (validated at import, ADR-009).
- **FP framework only in V1, no magic content** : Int/Faith are bankable, requirements possible, but no spells ship in the base catalog — content deferred. Accepted risk: these stats feel "dead" until magic content lands.
- **World-level display overrides (labels only)** : a world may rename the *displays* — stats (`faith` → `Spirit`) via `stat_names` and **currency** (`souls` → `runes`, `blood echoes`…) via `currency_name` — mechanics never change. Data always stores canonical ids; names are resolved only at display time (level-up, HUD, inventory). Validation: unknown id → error; missing → base name. These are the only world-level tunings allowed in V1 (flavor, not rules).

## ADR-012 — Inventory & equipment: base catalog + bounded slots

**Status** : locked. *(Amended by ADR-018 — 13/09/2026: equipment slots + offhand shield and accessory; stat payload + damage type (7) and resistances; base item types + ammunition, homeward bone, elemental resins and the DS3 item vocabulary; 4-piece armor.)*
**Context** : the inventory is a base-system feature: item *types* come from the base, creators place *instances* and configure *drop tables*.

**Rules** :
- Equipment slots: weapon, **clothing (painted texture set, cosmetic — `02`)**, armor (helmet, chest armor, gauntlets, leggings — **3D overlay meshes**) bound to the rig via `BoneAttachment`/`Marker` (P4), consumables (quickbar), key items (logical gates via flags, P5).
- **Base item types**: rechargeable healing flask (**estus**, restored at the bonfire — ADR-011), disposable consumables (quickbar), key items, currency. All bounded, all base-provided.
- Light stat payload on equipment (damage, weight, poise — bounded values) + **minimum attribute requirements** (e.g. a weapon requires 12 STR / 10 DEX), validated at import (ADR-009).
- Items are base-provided types; creators place them via the catalog (chests, corpses, pickups) and write **bounded per-enemy drop tables**: currency amount + one possible item (data-driven, validated at import — ADR-009).
- **Serialization split** : the character config (P4) carries appearance + starting equipment *visual* slots; progression (level, stat points, currency, inventory) lives in the run's `GameState` (P6) — a clean separation: identity vs. run state.

## ADR-013 — Death: classic souls drop + recovery

**Status** : locked.
**Context** : death is the genre's rhythm, and the currency drop is part of its identity. The base implements exactly one penalty model in V1 (no casual toggle yet) — the world-level bounded tuning of ADR-011 may revisit this later.

**Rules** :
- On death: the carried currency is deposited as a **soul orb** at the death location.
- On respawn (last bonfire), the orb is recoverable on the map. Dying a second time before recovery **permanently loses** that currency for the run.
- The GameState save tracks the orb state (present / recovered / lost).
- Powers the death screen line "your souls await" and the recovery interaction (P7).

## ADR-014 — Audio & cinematics deferred to vault (post-V1)

**Status** : locked.
**Context** : audio (music, SFX, ambience system) and all cinematic presentation (area name cards, boss intro/defeat, cutscenes) were scoped, then deliberately deferred to the vault. The risk line "the maker is the product, not the gameplay nor the cinematics" is confirmed. The *music as data* concept (a tracker-style music editor + synth, so every world can have its own theme without shipping audio files) is **retained as an idea** but strictly post-V1.

**Decision** :
- **Audio**: no audio system in V1 — no bus, no positional audio, no music, no SFX. The Options audio sliders stay as an inert UI shell (they exist but have no backing bus until audio lands).
- **SFX**: no SFX in V1. The catalog category "sound" is deferred with the whole audio pillar.
- **Cinematics**: no area name cards, no boss intro/defeat presentation, no cutscenes in V1. Boss HP bars are NOT a cinematic (pure HUD element, in V1 — see roadmap P7 / screens* HUD).
- **Trajectory (for the vault)**: music as a data format (tracker-style editor + synth engine), SFX as community samples via the existing pipeline (ADR-010 extension).
- V1 keeps rumble (haptic) as the only non-visual game-feel channel, and fog gates + boss HP bar as the only non-GameState presentation elements.

## ADR-015 — Multiple parallel runs per world

**Status** : locked.
**Context** : a player should be able to restart a world without losing progress (different builds, different choices). With JSON saves (ADR-009) runs are cheap data.

**Decision** :
- Each run = separate serialization set (its own `GameState` files). Runs are **named** (user-facing in Load + Save).
- **New game** in a world creates a new run — never overwrites an existing one.
- **Load** lists runs per world (run selector), not just "jump to most recent".
- Runs buckets live under user data (one folder per world, one subfolder per run).
- Save integrity rules (ADR-016) apply per run.

## ADR-016 — Save integrity & crash recovery

**Status** : locked.
**Context** : saves are the player's time; a crash mid-write must not corrupt a run. JSON is human-readable but a torn write is corruption.

**Decision** :
- **Atomic save**: write to a `.tmp` file, then rename over the final file (single `FileAccess` rename is atomic on the same filesystem).
- **Write guarding**: no silent corruption in a normal run (the rank/order of member writes is deterministic).
- **Validation on load** (ADR-009): schema + bounds; a corrupt run is **quarantined** (moved aside, logged) and the player is prompted — never silently wiped.
- A `version` field on every save for forward compatibility.

## ADR-017 — Starter catalog 1st-party & V1 definition

**Status** : locked.

**Context** : the game's identity *is* the catalog for creators — but a community of asset artists only materializes once a playable release exists. Letting V1 depend on community submissions would make the launch unbuildable.

**Decision** :
- **V1 = the public launch build** : the complete installable game released at first launch (roadmap P0 → P13). Everything after is post-V1 (vault, ADR-014+).
- **The base curates a 1st-party starter catalog as a mandatory V1 deliverable** (new roadmap P10, packages; the example world rides as P11): CC0 packs (Quaternius et al.) + animations re-targeted onto the standard humanoid skeleton (ADR-006, sourced from Mixamo et al.). Same discipline as the community stream — headless import validation, bounds, style/palette, manifest + licenses + Credits — and packed into the game PCK (build script, local source, no Drive needed for 1st-party).
- **The community pipeline (ADR-010) is an augmentative post-V1 growth stream** — Discord → Drive → build for *additional* content, never a release dependency. The example world (the manifesto) is built only from the 1st-party catalog.
- The exact pack selection (which CC0 kits + which Mixamo actions) is an implementation detail decided at P1/P10.

**History (trace)** : intra-discussion 13/09/2026 — previously the base's asset provision was only a founding principle (ADR-006) with no scoped deliverable; the « 5-6 test assets » of P1 were the only locked material. The re-scope makes the 1st-party catalog a first-class V1 phase and renumbers the roadmap (inserted P8; Distribution → P9, Hardening → P10). **Later the same day the roadmap was re-cut into smaller testable phases (P0 → P13): the combat toolkit moved to its own gray-box phase (P3), progression/inventory split (P7/P8), and the catalog split into packages (P10) + example world (P11); Distribution → P12, Hardening → P13.**

## ADR-018 — Combat depth in V1 (guard, criticals, ranged, damage types & status)

**Status** : locked (statuses of individual items: 🟡 pending in `features.md §1`).

**Context** : the DS3-style review (13/09/2026) checked the completeness net against the genre and found the V1 combat core thinner than the identity requires — blocking, critical hits, ranged weapons, damage types/status and movement depth were absent entirely. Magic/casting stays vaulted (ADR-011/pending), shops stay vaulted, and the base-fixed stats discipline is kept — this ADR covers the *martial* toolkit only.

**Decision** :
- **V1 includes the martial combat depth**: block/guard with shields (stability, stamina drain, guard break) with an **offhand shield slot**; criticals — parry / backstab / riposte (stance break + critical animation); ranged weapons (bow/crossbow, draw/hold, ranged lock-on, ammo economy with **ammunition as a base item type**); damage types (**7 — slash / thrust / strike** physical + **fire / lightning / magic / dark** elemental, 13/09/2026: elemental resins/bundles join V1) with **status build-up** (bleed / poison / frost) and **per-entity resistances/weaknesses** (bounded); player poise / hyper-armor; equip-load **roll tiers** (fast / mid / fat); backstep; plunging attacks; two-handed grip; kick guard-break; ladder climbing locomotion; held torch. See `features.md §1/§3/§4/§7`. **Resist philosophy (13/09/2026): armor-dominant** — the 7 resists derive mostly from the armor pool with a small per-type stat baseline, accessories stack additively (`resist-push`); rosette = 4-band tags (×0.5…×1.25), boss band narrowed ×0.85–×1.15.
- **Weapons and shields share the same stat properties** : every weapon carries guard values (`guard_absorb`, `stability`, `block_arc`) and every shield carries attack values (damage, damage type) — one identical stat block, only the profile differs (weapon = high damage/weak guard; shield = strong guard/low damage). **Guard is available with any instrument, one- or two-handed**; two-handing cancels **parry** (shield out of hand). **Parry requires a shield only** : light (ideal window), medium (shorter window), great shields cannot parry. (Corrected 13/09/2026 — the interim "two-hand disables guard" was wrong against actual souls behavior.)
- **Base item vocabulary = the DS3-derived generic set** (bounded, base-provided): weapon class taxonomy (full; V1 ships a subset chosen at P1/P10 + P3 design pass), shield classes (light/medium/great, `parry_window`), **clothing** (outfit texture sets — painted fitted layer, cosmetic, `02`), **4-piece armor** (helmet, chest armor, gauntlets, leggings — **3D overlay shells**), **accessory (×4 slots, no same-id, no rig visual — data item; world display name `accessory_name`, default "ring")**, consumables (estus as the only rechargeable; disposable heals; elemental + status resins/bundles; status cures; body buffs; throwables; soul items; homeward bone), ammunition variants (physical + elemental + status), key items. **Ashen estus / FP flask deferred** to the magic vault (no FP consumer in V1). (Corrected 13/09/2026 — armor was mis-scoped to 3 pieces, elemental damage types were added alongside the physical rosette, the clothing/armor layering was formalized, the accessory slot expanded to ×4 with no visual, and the **V1 starter subset** was bounded: per-family coverage policy + body-buff roster (3 presets) + disposable-heal bounds (25-50 % max HP, stack ≤10, not refilled at bonfire); exact instance list = P10.)
- **Amends ADR-012** (inventory): the rig slot set gains **offhand shield + accessory ×4** (data/stat items — **no rig visual**; world display name `accessory_name`, default "ring"); the stat payload gains **damage type (7) + resistances**; base item types gain **ammunition** and **homeward bone** (return to last bonfire); shields add `parry_window` to the shared stat block.
- **Amends ADR-011** (progression): **damage-type resistances** join the derived mappings (derived or flat, bounded — body of ADR-011 keeps base-fixed, never creator-tuned maths); equip-load **roll tiers** derive from the existing equip-load mapping.
- **Explicitly NOT in V1** : fast travel / bonfire warp (vaulted, `features.md §6`), magic & spells (vault), weapon arts (vault), shops & trading (vault), mini-boss combat phases (vault — in V1 a boss = `boss_level` marker on an archetype + one HP pool, `features.md §4`).
- **Design-open items stay 🟡 until the P3 design pass** : parry window / critical stance, two-handing strength-scaling modifier, push-move (kick/blade-shove) visual feel. (Resolved pre-pass 13/09/2026: buff/debuff duration = per-buff-object config, no global preset; `has_buff` excluded from the V1 condition grammar; ranged lock-on follows the target; roll tiers <30/<70/≥70; backstep has no i-frames; plunging is buffered-attack; torch stays lit in water; darkness purely visual.)

**History (trace)** : intra-discussion 13/09/2026 — « A + B (sauf fast travel) + C en V1 » after the DS3 completeness review; fast travel deliberately deferred.

## ADR-019 — Visual style: mandatory cel/toon look in V1

**Status** : locked.

**Context** : the game's identity is anime/cel shading (founding idea, `idea.txt`). The look was carried implicitly by `idea.txt` and two specs (`02` face, `10` base-shader) but never formalized — and `10_catalog.md` referenced a non-existent "ADR fidelity". Without a locked decision, catalog intake (1st-party and community), the quality tiers and the face pipeline could drift toward inconsistent rendering.

**Decision** :
- **V1 renders every 3D asset in a cel/toon look** : a **base toon shader** (`diffuse_toon` + custom shadow ramps) applied to all 3D content — world, characters, enemies, effects. The UI/screens stay standard (readable HUD, out of scope).
- **Real shadow maps** on entities and environment — **no blob shadows** (the low-end blob-shadow hypothesis of `idea.txt` is dropped). The low-end budget is served by the existing **quality tiers** (ADR-002: render scale, per-zone light cap, auto-drop of heavy features), re-confirmed against the P2 bench (skinning + shadows).
- **No ink outlines in V1** — post-process/inverted-hull outlines are fragile to get right; deferred to the vault. The look carries on ramps + palette.
- **Imposed palette + texture-mapping rules** (front-unfold face UV, two-texture split) at intake for both streams — the cohesion lever (amends ADR-010/017's "style/palette" checklist item).
- The **anime face light treatment** (SDF shadow, Genshin-like — keeps the 2D face readable under cel light) is 🟡, settled in the **P4** design pass (with the 2D face system — the treatment only matters once the face exists).
- **Correction** : the "ADR fidelity" reference in `10_catalog.md` is now **ADR-019**.

**History (trace)** : intra-discussion 13/09/2026 — user decisions: cel/toon mandatory on 3D only (UI standard); real shadow maps (curbing the early blob-shadow idea); `diffuse_toon` + ramps, **no outlines** (hard to render correctly).
