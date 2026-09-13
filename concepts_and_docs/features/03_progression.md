# 03 — Progression

> The run's long-term rules: what you earn, how you spend it, what death costs. Rules **base-owned and fixed** (creators shape content, never maths) — ADR-011/013. Neutral spec — status lives in `features.md`.

## Eight canonical attributes (Vigor, Mind, Endurance, Strength, Dexterity, Intelligence, Faith, Arcane)

**Goal** — the stat skeleton of the genre, instantly legible to souls players, reskinned per world by labels only.
**Behaviors** —
- **Vigor** → Max HP
- **Mind** → Max FP
- **Endurance** → Stamina + equip load
- **Strength** → damage scaling (heavy weapons) + equipment requirements
- **Dexterity** → damage scaling (light weapons) + cast speed + equipment requirements
- **Intelligence** → magic damage scaling (reserved content)
- **Faith** → sacred damage scaling (reserved content)
- **Arcane** → item discovery (loot), occult scaling
**Parameters / bounds** — stat list is locked canonical; values derive at load from the spec sheet; no creator tuning. FP framework exists but no FP content ships in the base catalog (Int/Faith bankable).
**Data / JSON** — canonical ids in all data; **display** ids resolved at runtime from the world's `stat_names` override (labels only).
**Interactions** — level-up (`03`), equipment requirements (`04`), cast speed (vault but the hook exists via Dexterity).
**Edge cases** — unknown id in override → validation error (ADR-009); missing → base name.
**Sources** — ADR-011, idea.txt attributes implied, `features.md §2`.

## Single level-up cost curve by total level

**Goal** — one economic curve, base-owned; creators never tune the math.
**Behaviors** — cost of a point = f(total level) (Elden-Ring style); raising a stat costs one point at the current level's price.
**Parameters / bounds** — curve formula base-only; level cap and soft-cap behavior defined by base.
**Data / JSON** — curve not configurable; level + allocated points live in run `GameState`.
**Interactions** — bonfire level-up screen (`11_ui`), `stat_names` display.
**Edge cases** — refunds (none in V1), max level near cap.
**Open questions** — whether the cap is soft (diminishing) or hard; respec rules (vault).
**Sources** — ADR-011.

## Currency (souls)

**Goal** — the earn→spend loop's medium, reskinnable per world.
**Behaviors** — earned by killed enemies and consumed items; spent at the bonfire (leveling) — **no shops in the base economic loop**; dropped on death as a recoverable orb (ADR-013).
**Parameters / bounds** — amounts bounded by world tuning; display name from world's `currency_name`.
**Data / JSON** — `currency` counter in run `GameState`; canonical id `souls` + world display name.
**Interactions** — death drop (`03`), level-up, drop tables (`04`).
**Edge cases** — currency overflow bounds, display name mismatch.
**Sources** — ADR-011, ADR-013.

## Bonfire / grace (respawn + refill + level-up)

**Goal** — the checkpoint object placed by creators: respawn, refill, spend.
**Behaviors** — world object (catalog) = respawn anchor + stat refill (HP/FP/stamina/estus) + opens the level-up screen; also the run's management hub (options/save/quit — no in-game pause, souls convention, `11`); unlock state (lit/unlit) + respawn anchor persisted in run `GameState` (P6).
**Parameters / bounds** — count is content (creators place them), not a base rule.
**Data / JSON** — lit/unlit flag, respawn transform in GameState; bonfire entries in world data.
**Interactions** — estus recharge (`04`), death respawn (`03`), shortcut unlocks (`07`).
**Edge cases** — respawn inside a fog gate (always light a near-safe spawn), level-up with zero currency.
**Sources** — ADR-011, roadmap P7, screens `levels`.

## Estus (rechargeable healing)

**Goal** — the bonfire pressure: limited but **renewable** healing; never a pickable consumable.
**Behaviors** — fixed max charges, base-backed; refilled at bonfire; upgrades (charges/potency) via bounded catalog items; disposable consumables exist but don't carry the bonfire loop.
**Parameters / bounds** — max charges base-owned; upgrade bounds validated.
**Data / JSON** — charges in GameState; estus as a base item entry (ADR-012); quickbar slot.
**Interactions** — inventory quickbar (`04`), HUD (`11_ui`), bonfire (`03`).
**Edge cases** — estus at low health, upgrade beyond cap rejection.
**Sources** — ADR-011, ADR-012.

## Starting template (fixed base)

**Goal** — start quickly: fixed stat spread + starting equipment; appearance layered on top by the character config.
**Behaviors** — the base defines the starting template once; not world-configurable. New run applies it (P4 config carries appearance + starting equipment visuals; stats come from the template).
**Parameters / bounds** — template base-only.
**Data / JSON** — template in base; applied at run creation.
**Interactions** — New game flow (`11_ui`), character editor (`09`).
**Edge cases** — creator wants custom start → rejected by rule.
**Sources** — ADR-011.

## Death: souls drop + soul orb recovery

**Goal** — the genre's failure rhythm: you can retrieve, but a second death costs.
**Behaviors** — on death, carried currency deposits as a **soul orb** at the death location; on respawn (last bonfire) the orb is recoverable in-world; dying again before recovery permanently loses it for the run; GameState tracks orb state (present/recovered/lost).
**Parameters / bounds** — orbs only for currency (no XP loss separate from currency in V1); exactly one penalty model in V1.
**Data / JSON** — world_id + zone + orb state + currency amount.
**Interactions** — death screen "your souls await" (`11_ui`), respawn, world object discovery (`07`).
**Edge cases** — death at a map transition, orb in unreachable spot, quitting after death before recovery.
**Open questions** — none (resolved 13/09/2026: **yes**, a faint golden pulse beacon at the orb's world point, visible through geometry while `orb_state = present`, hidden once recovered — no arrow/compass/indicator; see `11_ui`).
**Sources** — ADR-013, idea.txt (per-world state 2519).

## World display overrides (`stat_names`, `currency_name`, `accessory_name`)

**Goal** — flavor without rules: a world can rename stats ("Faith"→"Spirit"), currency ("souls"→"runes") and the accessory family ("ring"→"sigil"/"talisman"/"pendant") for display only.
**Behaviors** — labels resolved only at display time (level-up, HUD, inventory); data always stores canonical ids; unknown id → validation error; missing → base name (**accessory_name default: "ring"**, resolved 13/09/2026). World-level display overrides are the only world tunings allowed in V1.
**Parameters / bounds** — map canonical→display string.
**Data / JSON** — `stat_names: {canonical: display}`, `currency_name`, `accessory_name`.
**Interactions** — HUD/level-up screens; harmless to all other systems.
**Edge cases** — duplicate displays, empty strings.
**Sources** — ADR-011.

## Level-up (bonfire interaction)

**Goal** — spend currency on stats with preview.
**Behaviors** — open from bonfire (not from pause); bounded sliders per stat; cost of next point preview; current/result HP/stamina/FP/load preview; confirm/back.
**Parameters / bounds** — bounded sliders, single curve.
**Data / JSON** — allocation written to GameState on confirm.
**Interactions** — stats (`03`), HUD (`11`).
**Edge cases** — no currency, at cap, slider overflow.
**Sources** — ADR-011, screens `Level-up` (P7).

## FP framework (no content in V1)

**Goal** — the FP bar exists and Int/Faith are bankable even though no spells ship.
**Behaviors** — FP pool derived (Mind) but nothing consumes it in the V1 catalog; equipment may require Int/Faith points (ADR-012).
**Data / JSON** — FP in GameState; requirements validated at import.
**Interactions** — HUD FP bar (V2 content hook), equipment requirements.
**Edge cases** — the FP display shows only when FP content exists (avoid a dead bar).
**Sources** — ADR-011, roadmap P7 V2 note.

## Respec (vault)

**Goal** — (post-V1) reallocate spent points, Elden Ring Larval-Tear style.
**Behaviors** — a catalog mechanism that refunds and redistributes levels.
**Parameters / bounds** — item-based; bounded.
**Interactions** — cost curve, level-up.
**Open questions** — is respec content (catalog item) or system (bonfire toggle).
**Sources** — features.md vault.

## New game+ (vault)

**Goal** — (post-V1) replay a cleared world with scaled rewards.
**Behaviors** — carry run state into a new pass with difficulty/reward multipliers.
**Interactions** — runs (`15`), difficulty tuning.
**Open questions** — full spec deferred.
**Sources** — features.md vault.

## Multiple parallel runs per world

**Goal** — several playthroughs of the same world coexist without overwriting (ADR-015).
**Behaviors** — each run = separate named save (character config + GameState); **New game creates a new run**, never overwrites; Load lists runs per world; run metadata user-facing (name). **Selecting another run happens only from the main menu (Play → Load)** — during a run the only exit is a bonfire (save & quit; progress since the last bonfire discarded) (resolved 13/09/2026).
**Data / JSON** — one folder per world, one subfolder per run.
**Interactions** — save integrity (`15`), Load UI (`11`).
**Edge cases** — orphan run folder, run name collisions (append serial).
**Sources** — ADR-015.

## Equip-load roll tiers (fast / mid / fat)

**Goal** — weight as a movement choice: the equip-load ratio decides how the dodge *feels*, base-owned.
**Behaviors** — ratio = current load / max (from Endurance) selects a **roll tier** (fast / mid / fat) applying bounded modifiers: i-frame count, roll distance/speed, recovery length, and a distinct fat-roll posture; tiers are derived, never creator-tuned.
**Parameters / bounds** — thresholds base-owned (≈ <30% / <70% / ≥70%, exact values → P3 design pass); per-tier bounds fixed.
**Data / JSON** — thresholds in base; load computed from equipped weights (`04`); nothing in world data.
**Interactions** — dodge/i-frames (`01`), stamina regen by load, inventory weight readout (`11`), backstep/fat-roll (`17`).
**Edge cases** — threshold crossing mid-run (live swap), over-encumbered at run start (template keeps it legal).
**Sources** — ADR-011 (derived) + ADR-018, `17_combat_depth`.

## Damage-type resistances (derived)

**Goal** — the defensive counterpart to damage types (`17`): bounded, base-owned, never a raw percentage slider in creators' hands.
**Behaviors** — per-entity resistance to the **7 damage types** (slash/thrust/strike + fire/lightning/magic/dark) is **armor-dominant** (resolved 13/09/2026): the **armor flat pool** (7 bounded flats, `04`) drives most of the value, each type adds a **small bounded stat baseline** (VIG/END → physical; INT → magic, FTH → lightning/dark, small generic for fire), and **accessories stack additively on top** (`resist-push`, `04`); the resulting pool maps to the **preset rosette tags** (×0.5 / ×0.75 / ×1.0 / ×1.25) feeding the damage multiplier in `17`. Boss/enemy resist tables are preset-bound in `05` (boss band narrowed ×0.85–×1.15); the wizard-facing rule: multipliers come from presets, never unbounded floats.
**Parameters / bounds** — armor pool flat bounds, stat baseline bounds, accessory additive bound; resulting multiplier clipped to the preset rosette (×0.5 … ×1.25); boss band narrowed (×0.85 … ×1.15).
**Data / JSON** — base mapping (not configurable); armor payload **7 bounded flats** (`res_slash/thrust/strike/fire/lightning/magic/dark`, `04`); accessory `resist-push` additive (`04`).
**Interactions** — damage types/status (`17`), armor payload (`04`), enemy weaknesses (`05`).
**Edge cases** — zero/negative contributions (clamped), stacking to ≥100% (clipped at the rosette cap).
**Sources** — ADR-011/018, `17_combat_depth`.

## Homeward bone (return to last bonfire)

**Goal** — the classic escape item: leave a sticky spot by consent, at the cost of a consumable.
**Behaviors** — a **disposable consumable** (`04` base type) with a use timer; on completion the run returns to the **last lit bonfire** (respawn anchor, same as death) with current run state preserved (currency, inventory, flags); usable anywhere a quickbar use is legal; interrupts/cancels on hit (commit risk) or input.
**Parameters / bounds** — use duration (a channel, not instant — read as a risk), bounded item count/stack; base-provided type only.
**Data / JSON** — item entry `{type: consumable, effect: return_to_bonfire}` (uses the effect node `17`); GameState unchanged except the location.
**Interactions** — bonfire respawn anchor (`03`), quickbar (`04`), death/orb (`03`), item effect engine (`17`).
**Edge cases** — use during boss aggro (allowed, the timer is the risk), use while a fog gate sealed the room (returns anyway — no trap), use canceled by hit (consumable kept, timer reset).
**Sources** — ADR-018, features.md §3.