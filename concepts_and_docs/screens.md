# SoulMaker — Screens & user journeys

> Companion document to `roadmap.md` and `decisions.md`. This is the inventory of every visible screen and the user flows through them, plus the vocabulary fixed before any UI code is written. Written in English per the language policy (see AGENTS.md); the opencode conversation remains in French.

---

## Glossary (fixed vocabulary)

Terms in English because they will appear in the in-game UI. The French design term is given in parentheses for our own communication.

| Term | Reference (FR) | Definition |
|---|---|---|
| Asset | asset | Atomic element of the catalog (a mesh, an animation, a light fixture). Provided by the base, never user-made. (Audio is vault, ADR-014.) |
| Prefab | préfab | Reusable group of assets assembled by a creator (e.g. a dungeon corridor: floor + walls + a mounted torch). First level of map construction. |
| Map | map | An assembly of prefabs and/or raw assets. Playable as a standalone level. Second level. |
| World | monde | A graph of maps connected by sockets, with global ambiance (sun, fog). The unit that is shared. Third level. |
| Socket | socket | Discrete connection point (position + orientation) linking two maps inside a world. |
| Save / run | sauvegarde / partie | A serialized run of a world: character config + GameState (flags, doors, boss states). Multiple parallel runs can coexist per world (ADR-015). |
| Run name | nom de la partie | A player-given label for a run, shown in Load/Save (ADR-015). |
| Home | accueil | The navigation hub reached after boot. Two doors: **Play** (consume) and **Create** (produce), with transverse actions (Options, Credits, Quit) in a corner. |
| World library | bibliothèque de mondes | Local catalog of installed/imported worlds (world selection + import management). One of the Play door's destinations. |
| Spawn point | point d'entrée | A map's entry point, where a run starts or a transition arrives. |
| New run | nouvelle partie | Starting a fresh run: choose a world → create the player character → spawn → play. |
| Currency (souls) | monnaie (âmes) | The run's progression resource, earned from kills and items, spent at the bonfire. Dropped on death (ADR-013). **Display name comes from the world's `currency_name` override** (base: "souls"). |
| Estus | estus | Rechargeable healing charges, base-backed, refilled at the bonfire — never a pickable consumable (ADR-011). |
| Bonfire / grace | bonfire / grâce | World object (placed by creators) = respawn point + stat refill + level-up point; unlock state persists in GameState. |
| Soul orb | orbe d'âme | The deposit of dropped currency at the death location, recoverable on respawn (ADR-013). |
| Inventory | inventaire | The run's equipment (weapon, offhand shield, clothing, helmet/chest armor/gauntlets/leggings armor, accessory), estus charges + consumables and key items. Part of the run's GameState (ADR-012/018). |
| Drop table | table de loot | Bounded per-enemy config: currency amount + one possible item drop. |
| Key item | objet-clé | Non-consumable item that gates logic (doors, shortcuts) via flags (P5). |
| Starting template | modèle de départ | The base-defined starting stat spread + starting equipment for a new run (ADR-011); appearance is layered by the character config. |
| Fog gate | porte de brume | A wall of fog blocking a passage until a flagged condition is met (boss killed, key item used). World object, placed in the map editor (P5). |

> Naming decision: "prefab" was chosen (aligned with the existing terminology in `idea.txt`). "Pattern" is avoided because P9 already uses "behavior patterns" for enemies.

---

## Screen inventory

Each entry: *Purpose · Content · Actions · Transitions · Roadmap phase*.

### Boot screen

- **Purpose** : branded entry point; momentary.
- **Content** : logo, version number, engine disclaimer if relevant.
- **Actions** : none (skip on input).
- **Transitions** : auto or click-to-skip → Home.
- **Phase** : P0 (shell) / P12 (logo, credits polish).

### Home (two-door hub)

- **Purpose** : the navigation hub. Two big doors — **Play** (consume) and **Create** (produce) — plus transverse actions in a corner. Rationale: the product has two real audiences (players and creators), and the creator loop is already embedded inside the editors (one-key playtest), so the extra tap at Home is painless. Recorded as a decision.
- **Content** :
  - **Play** door → *Continue run* (resume the latest run) · *New game* (see New game flow) · *Load* (pick a saved run) · *World library* (manage/import worlds).
  - **Create** door → *Prefab editor* · *Map editor* · *World editor* · *Character editor* (player/NPC/enemy). Entries guide in cascade (prefab → map → world), matching the roadmap. (No audio/music editor — the whole audio pillar is in the vault, ADR-014.)
  - **Transverse (corner)** : *Options* · *Credits* · *Quit* — reachable from both branches.
- **Contextual Continue** : each door keeps its own "Recent" — Resume my run (Play) vs. Continue editing (Create).
- **Import split by nature** : a shared **world** imports through Play (World library); a **prefab or character config** imports through Create. Import flow must show a disclaimer: "user-created content, not verified" (per `idea.txt`).
  - (Anti-grouping trap: Create must not become a "catch-all" list — it organizes its four editors, see below.)
- **Transitions** : each door opens its flow; Quit exits; Options/Credits overlay.
- **Phase** : P1 (shell) / P12 (hub, import polish).

### Options

- **Purpose** : graphics, audio, controls, interface.
- **Content** :
  - **Graphics**: quality tiers per ADR-002 (render scale, MSAA, shadow quality, per-zone light cap), vsync, windowed/fullscreen, resolution. The low-end tier is a first-class preset, not buried config.
  - **Audio** : master / music / SFX / ambiance / UI.
  - **Controls** : remapping — **keyboard per-key**, **gamepad via bounded layout rows** (Souls default + alternates), sensitivity, camera invert.
  - **Interface** : UI scale, reset to defaults, apply-and-keep with confirm. (No language selector — English-only string table in V1, resolved 13/09/2026.)
- **Actions** : change setting → apply → (confirm only when reversible) → back to previous screen.
- **Phase** : P1 (shell) / P13 (graphics tiers calibrated).

### Hub / World library

- **Purpose** : the local library of worlds — the Play door's destination for installed content.
- **Content** : list/cards of installed worlds (title, preview thumbnails, creator info when available), import zone (file-picker, no OS file-drop).
- **Actions** : open world → New game / Load (lists the world's runs, ADR-015); import a world; Delete (with confirm); (later) Workshop browse.
- **Transitions** : world card → New game flow or Load list → gameplay.
- **Phase** : P12 (MVP local) — but the world selection entry exists as soon as multiple worlds can be imported.

### New game flow

- **Purpose** : make a fresh run in a chosen world.
- **Steps** :
  1. Choose a world (from the World library).
  2. **Create the player character** (opens the character editor for the player, with a default template for "start quickly"). The character config (P4) carries appearance + **starting equipment slots** (ADR-012).
  3. Optionally name the run (ADR-015: "New game" never overwrites an existing run — a new run is created each time).
  4. Choose the beginning spawn point (world-level entry).
  5. Start.
- **Phase** : P2 (gameplay) / P4 (character editor integrated) / P7 (starting equipment, run state).

---

### Editors

#### Prefab editor

- **Purpose** : save reusable groups of assets (e.g. a dragon corridor: floor + walls + torch).
- **Content** : miniature of the map editor (same gizmos, same catalog panel). Select several assets → group → save as prefab.
- **Actions** : select/deselect, group, name, save, preview thumbnail, delete (confirm).
- **Phase** : P1 (core, right after the map editor basics).

#### Map editor

- **Purpose** : build a map from prefabs and/or raw assets. The core of the product.
- **Content** : 3D view (orbit/zoom camera), asset catalog panel, map structure of prefabs, ambiance override per map.
- **Actions** : place (arrows/D-pad + A/E), free transform (no snap by default, fine snap 0.1), select/move/copy/delete, **undo/redo**, save/load (JSON), **instant playtest** (one key: editor ↔ player), export map as shared file.
- **Phase** : P1 (core). Ambiance override confirmed in P6 but the UI hook is laid out here.

#### World editor

- **Purpose** : assemble maps into a world and connect them.
- **Content** : world graph view (map nodes + socket links), per-map ambiance override, world-level ambiance (sun, fog, tonemapping).
- **Actions** : add/remove maps, create/edit sockets, place spawn points, set world ambiance, **playtest the whole world** (from a spawn point), save/load, **export the world** (the sharing unit).
- **Phase** : P6.

#### Character editor — player (new-run)

- **Purpose** : create the player character at run start, or refine the base template.
- **Content** : 3D preview, base template, slots (hair, ears, equipment), **clothing layer (outfit texture set — the painted base look, swappable in-game)** + **armor overlay preview** (equipment can be shown on the 3D preview but armor is an in-game item, P8), bounded morphs (P4), preset gallery.
- **Actions** : tweak sliders (strict bounds), save config, load config, quick-start with default.
- **Phase** : P4 (config + validation), wired into New game flow.

#### Character editor — NPC

- **Purpose** : create/configure NPCs used in maps and worlds.
- **Content** : same base as the player editor (shared system), plus **dialogue graph link** (which dialogue ID it talks, flags for conditions).
- **Actions** : all the visual ones + bind dialogue/interactions (created in P5).
- **Phase** : P4 (visual) + P5 (dialogue link).

#### Character editor — enemy

- **Purpose** : create/configure enemy archetypes and their variations.
- **Content** : same character base (archetype selected), bounded morphs (ADR-007), **behavior patterns link** (data-driven, P9).
- **Actions** : visual + behavior assignment; enemies are selectable from the map editor's catalog to place them.
- **Phase** : P2 (1 simple archetype) / P4 (visual modularity) / P9 (behavior patterns).

---

### Gameplay screens

#### Bonfire hub (no in-game pause)

- **Purpose** : the run's management — the souls convention: no pause during play; the hub lives at the bonfire.
- **Content** : Options · Save run · Quit to menu · Level-up.
- **Access** : from the bonfire interaction only (quitting mid-run returns to Home; progress since the last bonfire is discarded — bonfire = save point).
- **Phase** : P2.

#### Level-up screen (bonfire / grace)

- **Purpose** : spend the world's currency on stats — the progression heart (ADR-011).
- **Content** : the **8 canonical attributes** (Vigor, Mind, Endurance, Strength, Dexterity, Intelligence, Faith, Arcane), **named from the world's `stat_names` map** (base names by default), current level, **currency held (per the world's `currency_name`)**, cost of next point (single curve by total level), bounded sliders, current/result preview (HP/stamina/FP/load).
- **Actions** : raise stat, raise level, confirm/back, leave at the bonfire.
- **Access** : from the bonfire interaction, not from the pause (souls-like convention).
- **Phase** : P7.

#### Inventory / equipment screen

- **Purpose** : manage the run's equipment, consumables and key items (ADR-012).
- **Content** : equipment slots (**weapon, offhand shield, clothing, helmet, chest armor, gauntlets, leggings, accessory** — armor visuals bound to the rig, clothing = painted texture set), **estus charges** + consumables quickbar, **ammunition**, key items (read-only, flags-gated), stat/weight/poise readout (incl. minimum attribute requirements).
- **Actions** : equip/unequip, consume, sort; no crafting/editing in V1.
- **Phase** : P8.

#### HUD (in-game)

- **Purpose** : the live gameplay readout.
- **Content** : HP bar, stamina bar, souls counter, **estus charges**, equipped consumable quickbar, buff icons (**strip cap 4 + « +N », depleting ring = time left, catalog icons — resolved 13/09/2026**), **boss HP bar** (bottom, boss-level enemies only — HUD element, no cinematic) (FP bar shown only once FP content exists — V2).
- **Phase** : P7.

#### Death / respawn screen

- **Purpose** : the souls-like death loop.
- **Content** : death vignette/fade, "grace" message, **"your souls await"** line (ADR-013); respawn at the last bonfire with run state restoration (GameState).
- **Notes** : fork point — a full screen vs an embedded overlay; validate the feel at P2. Soul orb recovery interaction happens back in the world at the death location.
- **Phase** : P2 (loop & feel) / P7 (soul orb + drop message).

#### Transitions (sockets/fog)

- **Purpose** : map-to-map transitions inside a world.
- **Content** : fog fade (depth/height), 2-4 s rhythm — this is the natural loading screen (from `idea.txt`), no dedicated loading screens needed.
- **Phase** : P6.

---

## User journeys

### Player journey (consume)

```
Boot → Home (Play door)
	  → World library (/ import a shared world file via file-picker)
	  → New game → choose a world → create player → spawn → play
	  → HUD (HP/stamina/souls/quickbar)
	  → kill enemies → collect souls → bonfire (level-up) → explore
	  → bonfire hub (save/level-up/options) / inventory & equipment / death-respawn (soul orb recovery) / socket transitions
	  → back to Home
```

### Creator journey (produce & share)

```
Boot → Home (Create door)
Prefab editor  → group assets → save a prefab
Map editor     → assemble prefabs/assets → playtest the map alone → save/export map
World editor   → connect maps via sockets → set ambiance (+ per-map override)
			  → playtest the world → export the world (the shared file)
Consume check  → back to Home → Play door → World library (/ import the exported file) → play
```

### Notes on journeys

- **Import lives where the content type belongs** : a world imports through Play (World library) ; a prefab or character config imports through Create. **Export** lives inside each editor (map, prefab, world, character).
- Contextual Continue: Play resumes the last run; Create resumes the latest project being edited.

---

## Roadmap mapping

| Screen | Phase |
|---|---|
| Boot screen | P0 (shell) / P12 (logo, credits) |
| Home (two-door hub: Play / Create) | P1 (shell) + contextual Continue per door |
| Import (world → Play library; prefab/character → Create) | P1 (flow) / P12 (robust + disclaimer) |
| Options — graphics tiers | P1 (shell) / P13 (calibrated) |
| Options — audio / controls / interface | P1 |
| Credits / attribution | P10 (from the starter catalog manifest, ADR-017) |
| Hub / World library | P12 |
| New game flow | P2 (gameplay) / P4 (player editor) / P7 (run creation, ADR-015) |
| Prefab editor | P1 |
| Map editor | P1 (core) |
| World editor (sockets, ambiance + override) | P6 |
| Character editor (player / NPC / enemy) | P4 (+ P5 dialogue / P9 patterns) |
| Bonfire hub (no in-game pause) | P2 |
| Level-up screen (bonfire) | P7 |
| Inventory / equipment screen | P8 |
| HUD (HP, stamina, souls, quickbar) | P7 |
| Boss HP bar (HUD element for boss-level enemies) | P7 |
| Death / respawn (soul orb) | P2 (loop & feel) / P7 (orb + drop message) |
| Drop tables per enemy (editor) | P8 |
| Socket/fog transitions | P2 (fog feel) / P6 (mesh) |

---

## Decisions tracked here

- **Language** : game UI text is English (see AGENTS.md — Languages).
- **Navigation** : **Home = two-door hub** (Play / Create), transverse actions in a corner, contextual Continue per door. Rationale: two real audiences (player vs creator), embedded playtest makes the extra tap painless, and each door scales without cluttering the other.
- **Terminology** : "prefab" (retained), "map", "world", "socket", "home", "run", "world library".
- **Ambiance** : world-level defaults + optional per-map override (recorded in ADR-005).
- **Loading screens**: not needed as dedicated screens — socket/fog transitions double as loading.
- **Progression & inventory (P7/P8)** : base-fixed souls rules with **8 canonical Elden Ring-style attributes** + **world display overrides** (`stat_names` + `currency_name`) for flavor (ADR-011); **healing = estus** (rechargeable at bonfire, ADR-011); **run start = fixed base template** (ADR-011); inventory = base catalog + bounded slots + estus + equipment min-stat requirements (ADR-012), with **offhand shield + accessory slots** and **ammunition / homeward bone / temporary buff-debuff items** as base item types, plus **item description/lore text** (ADR-018); death = souls drop + soul orb recovery (ADR-013). Level-up, inventory and the HUD are in-game screens (gameplay), never editor screens. **Shops / NPC vendors deferred outside V1.** **Boss HP bar** = HUD element on boss-level enemies (P7, not a cinematic). **Fog gates** = flags-gated blocking doors placed in the map editor (P5).
- **Runs (P7)** : multiple **named parallel runs** per world (ADR-015) — New game creates a run, never overwrites; Load lists runs per world.
- **Save integrity (P7, polished P13)** : atomic tmp→rename writes + corrupt-run quarantine on load (ADR-016).
- **Audio & cinematics (whole pillar → vault, ADR-014)** : no music/SFX/ambience system, no area cards, no boss intro, no cutscenes in V1. Options keeps the volume sliders as an inert shell; the Create hub has **no** audio/music editor.
