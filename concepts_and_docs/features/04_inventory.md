# 04 — Inventory & equipment

> Base-system items, bounded slots, drop tables. Creators place *instances* and configure *drops*, never define new item types. Neutral spec — status lives in `features.md`.

## Equipment slots (weapon, offhand shield, clothing, armor, accessory, consumables, key items)

**Goal** — a bounded equipment scheme bound to the character rig, over a **two-layer look**: the *clothing layer* (painted texture on the body, `02`) is the character's base appearance; the *armor layer* (3D overlay shells on the rig, `02`) sits on top.
**Behaviors** — slots: weapon, offhand shield (with guard system `17`), **clothing** (outfit texture set — painted layer, cosmetic 0 stats/0 weight, swappable in-game like any slot, `02`), armor (helmet, chest armor, gauntlets, leggings — **3D overlay meshes** on rig sockets, `02`), accessory (**4 slots, no same-id, no rig visual — data/stat items**, `03`/`17`), consumables (quickbar), key items (logical gates). Equipment visuals bind to rig sockets via `BoneAttachment`/`Marker` (ADR-012/018, P4); clothing binds as a texture swap on the base body mesh.
**Parameters / bounds** — slot ids canonical; armor/equipment visual binding validated; armor shell-clearance vs max-morph checked at intake (`02` fit rule, `10_catalog`); **four accessory slots** (distinct ids only); one shield (tool torch occupies the offhand instead of a shield — `17`); one clothing set.
**Data / JSON** — equipped entries in run `GameState` (item id + slot); clothing default from the character config (`02`, `data/schema/character_v0.1.json`).
**Interactions** — `02_character` attachment sockets + clothing layer + armor overlay, `03` min-stat requirements, `17` guard/ranged/torch.
**Edge cases** — item requires attribute not met → cannot equip (info shown); slot conflict (torch vs shield vs crossbow offhand).
**Sources** — ADR-012/018, idea.txt 883-899.

## Base item types

**Goal** — the base defines the closed item vocabulary; every item is an instance of a base type.
**Behaviors** — types: rechargeable healing flask (**estus**, restored at bonfire — ADR-011/`03`), disposable consumables (quickbar — incl. **homeward bone** `03`, healing/spirit consumables, **buff consumables** `17`), **ammunition** (arrows/bolts, stacks, `17` ranged), key items, currency. All bounded, all base-provided.
**Parameters / bounds** — type whitelist, bounded payloads, ammunition stack bounds.
**Data / JSON** — item = base type id + bounded params.
**Interactions** — drop tables, chests/corpses/pickups (`07`), dialogue effects (`08`), ranged/ammo (`17`), buffs (`17`).
**Edge cases** — world requests unknown type → validation error; ammo type without a matching ranged weapon → import warning.
**Sources** — ADR-012/018.

## Base item vocabulary (DS3-derived, bounded)

**Goal** — the base defines the closed set of generic item *types* a creator can draw from; V1 ships a **bounded subset per family** (per-family bounding policy resolved 13/09/2026 below; **exact instance list = P10 deliverable**, asset-sourced from CC0/Mixamo — ADR-017), the taxonomy below is the full base vocabulary (genre-derived from the DS3 completeness review, 13/09/2026).
**Behaviors** — families:
- **Weapons** (classes): daggers, straight swords, greatswords, ultra greatswords, thrusting swords, katanas, curved swords, curved greatswords, twinblades, axes, great axes, hammers, great hammers, spears, halberds, pikes, reapers, whips, fist/claws — plus bows, greatbows, crossbows. Casting catalysts (staves, talismans, chimes, pyromancy flame) are vault (magic deferred).
- **Shields** (classes): light (ideal parry), medium (shorter parry window), great (no parry) — shared stat block (`17`).
- **Clothing** (outfit texture sets — the painted fitted layer, 0 stats/0 weight; chosen at creation + swappable in-game, `02`).
- **Armor** (4 pieces): helmet, chest armor, gauntlets, leggings — **3D overlay meshes** (shells on the rig, `02`).
- **Accessory** (×4 slots, no same-id stack; **no rig visual**; display name per world `accessory_name`, default "ring").
- **Consumables**:
  - **Rechargeable** : estus (HP) only in V1 — *ashen estus / FP flask deferred* to the magic vault (no FP consumer in V1).
  - **Disposable heals** (siegbrau-style; potency bound = **flat % of max HP, 25-50 % window, no full-heal**; stack ≤ 10; **never refilled at bonfire** — estus is the only recharge; resolved 13/09/2026, values within bounds at catalog P10).
  - **Weapon resins / bundles** : elemental (fire / lightning / magic / dark) + status (bleed / poison / frost) temporary coatings — 60 s resin / 5 s fast bundle (`17` effect engine).
  - **Status cures** (moss per V1 status: bleed / poison / frost).
  - **Body buffs** — bounded roster of **3 effect presets** (resolved 13/09/2026): **stamina regen up** (Green Blossom-style, ~45-60 s), **hp regen tick** (slow, ~60-90 s), **small all-resist push** (short defensive window).
  - **Throwables** (throwing blades, firebombs/urns, aggro-bait, ground hazard) — universal no-magic ranged tools.
  - **Soul items** (consumable bankable currency).
  - **Homeward bone** (return to last bonfire).
- **Ammunition** (arrow/bolt variants): physical + elemental + status (`17`).
- **Key items** (flags-gated, `08`).
**Parameters / bounds** — type whitelist base-owned; pay-per-family bounded (potency, duration, stack); validated at import (ADR-009).
**Data / JSON** — item = base type id + bounded family params (see each family's payload).
**Interactions** — drop tables/loot (`07`), effect engine (`17`), ranged (`17`), narrative `give_item` (`08`).
**Edge cases** — unknown type → import error; family budget exceeded → clamp/warn.
**Open questions** — none (resolved 13/09/2026: per-family bounding policy + body-buff roster + disposable-heal bounds in-doc below; exact instance list = P10, asset-sourced ADR-017).
**Sources** — ADR-012/018, DS3 genre review 13/09/2026.

## V1 starter subset (per-family bounding policy — resolved 13/09/2026)

> The **policy** is pinned here; the exact instance list is a **P10 deliverable** chosen from the sourced CC0/Mixamo catalog (ADR-017) and the P3 design pass (final `parryable` list, per-weapon moveset feel — `17`).

| Family | Starter coverage (budget) |
|---|---|
| Melee weapons | ≥1 per `push_move` class present in V1 (kick / blade-shove / heavy), **8-12 weapons** total; at least one strike and one thrust instrument + one heavy hyper-armor |
| Ranged | ≥1 bow + ≥1 crossbow (`17`) |
| Shields | 1 light / 1 medium / 1 great (`parry_window`, `17`) |
| Clothing | ≥3 outfit texture sets (painted fitted layer, `02`) |
| Armor | ≥1 per-piece set (helmet/chest/gauntlets/leggings — base-topology fit rule, `02`) |
| Accessory | ~6-8 bounded bonus presets covering the 4 kinds (stat-overlay / resist-push / regen / effect `17`) |
| Consumables | estus (rechargeable only) · ≥1 disposable heal (25-50 % max HP, ≤10 stack) · resins: 4 elemental + 3 status · 2-3 fast bundles · status cures ×3 · body-buff roster ×3 · throwables: ≥1 per family (throwing blades / firebomb-urn / aggro-bait / ground hazard) · ≥1 soul item · homeward bone |
| Ammunition | physical arrow + bolt; ≥1 elemental + ≥1 status variant per weapon `ammo_type` |
| Key items | type base-provided; instances authored by worlds (example world P11) |

## Consumables quickbar

**Goal** — assign a consumable to a hot slot and use it mid-combat.
**Behaviors** — quickbar slots (up to N); consume on press; estus occupies one slot; rebind between slots via inventory screen.
**Parameters / bounds** — N quickbar slots, queued use timing (souls-style arc).
**Data / JSON** — quickbar assignment in GameState.
**Interactions** — HUD (`11`), item effects (heal, buff).
**Edge cases** — out of charges (slot dims), use while hit.
**Sources** — idea.txt (implied), screens inventory/HUD.

## Accessory slots (×4, display name per world)

**Goal** — a small, bounded way to twist a build without new systems.
**Behaviors** — **four accessory slots** (resolved 13/09/2026); accessories carry a light, bounded bonus (stat-overlay, resist-push, regen tweak, effect presets from `17`) — no set bonuses in V1; **no same-id stack** (two identical accessories cannot be equipped together); **no rig visual** — accessories are data/stat items, invisible on the character in V1; **`resist-push` is additive** to the entity's per-type resist pool on top of armor + stats (`03`, resolved 13/09/2026).
**Parameters / bounds** — 4 instances max; bonus magnitudes from a preset list; validated at import; stacking = only distinct ids.
**Data / JSON** — accessory item payload `{bonus: {id, magnitude}}` (effect node `17`); equipped ids in GameState; **base display name "ring" overridable per world** via `accessory_name` (display-override pattern `03`, default "ring").
**Interactions** — resistances (`03`), effect engine (`17`), equip-load contribution (`03`), world display override `accessory_name` (`03`).
**Edge cases** — five accessories requested (rejected — 4 slots), same-id equipped (rejected), bonus beyond bounds (import error), missing display name (falls back to "ring").
**Open questions** — none (resolved 13/09/2026: ×4, no same-id, no visual; name = `accessory_name`).
**Sources** — ADR-018, features.md §3.

## Ammunition

**Goal** — ranged weapons consume a storable, stackable resource (archery needs bites).
**Behaviors** — ammunition = base item type, stacks (bounded); ranged weapons reference an `ammo_type` (`17`); a shot consumes one unit; ammo is not refilled at bonfires (estus is the only recharge — ammo is an intentional consumable sink); appears in drop tables/loot; quickbar-friendly.
**Parameters / bounds** — stack bound, ammo categories (arrow/bolt) matched to weapon `ammo_type`, damage/status/elemental carried by the ammo payload (`17`); arrow/bolt variants bounded (physical + elemental + status).
**Data / JSON** — ammo item: `{ammo_type, count, damage, damage_type, status_bonus?}`; weapon references `ammo_type`.
**Interactions** — ranged (`17`), quickbar/HUD ammo readout (`11`), drop tables (`04`).
**Edge cases** — no ammo left (shot blocked, slot dims), mismatched ammo type (import error), trade of ammo (no trading in V1).
**Sources** — ADR-012/018, `17_combat_depth`.

## Item description / lore text

**Goal** — the souls lore carrier on items, authored by creators as data.
**Behaviors** — every item can carry an **owner-written description** (English, plain data — localization note `11`: content text stays data in V1); displayed in the inventory tooltip/inspect; forms the world's item-lore layer alongside object/place lore notes (`08`).
**Parameters / bounds** — bounded length, plain text (no markdown/markup in V1), optional but recommended by the validator.
**Data / JSON** — `description` field on item entries; validated (non-empty/blank, length).
**Interactions** — tooltip/Inventory screen (`11`/`04`), lore notes (`08`).
**Edge cases** — missing description (validator hint, not an error), text-only language (labels via `stat_names`/`currency_name` purely).
**Sources** — ADR-018, features.md §3.

## Key items (flags-gated)

**Goal** — logical gates on progression via flags: shortcuts, doors, dialogue options.
**Behaviors** — non-consumable; presence gates flags/conditions in the narrative engine (`08`); obtained via loot or dialogue effects (`give_item`).
**Data / JSON** — key items as inventory entries + backing flags.
**Interactions** — `08` narrative `has_item` conditions, `07` fog gates/doors.
**Edge cases** — duplicate grant, quest flag without item.
**Sources** — idea.txt 1775-1835.

## Light stat payload

**Goal** — visible, bounded combat stats on equipment — enough to matter, no inflation.
**Behaviors** — **weapons and shields share the same stat block**: every weapon carries guard values (`guard_absorb`, `stability`, `block_arc`) and every shield carries attack values (damage, damage type) — the properties are identical, only the profile differs (weapon = high damage / weak guard; shield = strong guard / low damage) (`17`). Damage, **damage type** (**7**: slash/thrust/strike + fire/lightning/magic/dark, `17`), **resistances** (same 7 bounded flats — armor-dominant payload, `03`), weight, poise (bounded values) + **minimum attribute requirements** (e.g. 12 STR / 10 DEX) validated at import (ADR-009). Shields add `parry_window` (light ideal / medium shorter / great shields 0 — `17`).
**Parameters / bounds** — bounded fields; requirement validated against canonical attributes (`03`); resist multiplier clipped to the base rosette.
**Data / JSON** — shared stat block per item: `{damage, damage_type, guard_absorb, stability, block_arc, weight, poise}`; shields append `parry_window`.
**Interactions** — damage scaling from `03` stats, equip load from `03` Endurance, resistances (`03`), damage types/status (`17`).
**Edge cases** — negative values, oversized stats → reject; resist outside tolerance → clamp+warning.
**Sources** — ADR-012/018.

## Drop tables per enemy (bounded)

**Goal** — creators configure what an enemy yields: currency amount + exactly one possible item.
**Behaviors** — per-enemy config: `[currency_amount, item_drop: {item_id, chance}]`; bounded; validated at import.
**Parameters / bounds** — currency range bounded, exactly one item entry.
**Data / JSON** — enemy config (in world/enemy data) with drop table.
**Interactions** — `05_enemies`, loot objects, currency (`03`).
**Edge cases** — chance ≤0/≥1, empty tables.
**Sources** — ADR-012, roadmap P8.

## Loot objects (chests, corpses, pickups)

**Goal** — placed content: where items live in the world.
**Behaviors** — chest/corpse/pickup world objects placeable in the map editor; contain currency/items; open/pickup state persisted in GameState (per world).
**Parameters / bounds** — bounded contents.
**Data / JSON** — object entry + contents + opened flag.
**Interactions** — `07` world objects, drop tables, GameState persistence (`15`).
**Edge cases** — reopened? (looted once).
**Sources** — idea.txt 1734-1913 (flags), roadmap P8.

## NPC vendor shops (vault)

**Goal** — (post-V1) spend currency at NPCs with per-NPC inventory.
**Behaviors** — dialogue effect `open_shop` with per-NPC shop inventory (`08`).
**Interactions** — dialogue engine, currency.
**Open questions** — economy impact on V1 flow.
**Sources** — idea.txt 1842-1845.

## Crafting / upgrades (out)

**Goal** — excluded by scope decision.
**Sources** — features.md §3 (⚫).

## Selling / trading (vault)

**Goal** — (post-V1) part of the deferred shops work.
**Sources** — features.md §3, ADR-011.

## Inventory screen

**Goal** — manage equipment, consumables, key items.
**Behaviors** — equipment slots (weapon/offhand shield/helmet/chest armor/gauntlets/leggings bound to rig; **accessory ×4 — data items, no rig visual**), estus charges + consumables quickbar, ammunition counters, key items read-only (flags-gated), stat/weight/poise/resist readout incl. min-stat requirements; equip/unequip, consume, sort; no crafting/editing in V1.
**Parameters / bounds** — sorting, no drag-drop in V1 (list + equip action).
**Data / JSON** — GameState inventory.
**Interactions** — HUD, level-up screen, `02` visual slots.
**Edge cases** — equip blocked by min-stats (tooltip).
**Sources** — screens `Inventory` (P8).