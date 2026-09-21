# 05 — Enemies & bosses

> Opponent variety through combinatorics, not through new models. Readability first: telegraphs must stay readable on any morph. Neutral spec — status lives in `features.md`.

## Enemy archetypes (soldier / beast / mage)

**Goal** — a closed set of base enemies with distinct behavior identities, reused across worlds.
**Behaviors** — archetype families (soldier, beast, mage...) share the humanoid skeleton (`02`) for one shared animation library; per-archetype config = stats, colors, sounds, behavior only — creators never build new archetypes.
**Parameters / bounds** — archetype list catalog-bound; telemetry readability is design constraint.
**Data / JSON** — archetype id + config (stats, colors, sounds, behavior pattern id).
**Interactions** — `02` morphs, `04` drop tables, `08` events (miniboss spawn).
**Edge cases** — morphs that break telegraph readability → slider bounds; custom skeletons → reject (ADR-006).
**Sources** — idea.txt 122-164, 525-557, ADR-007.

## Bounded morphs for variety

**Goal** — worlds tell enemies apart without new assets: variation from combinatorics.
**Behaviors** — same topology + bounded blend-shape values → distinct silhouettes/faces; strict generous bounds; linked slider groups to prevent clipping (shoulders/torso).
**Parameters / bounds** — shape values bounded, linked-track groups.
**Data / JSON** — enemy config morph map.
**Interactions** — `02` morph system, `01` readability constraint (morphs must not hide the windup).
**Edge cases** — a morph making an enemy unrecognizable vs base family → rejected by bounds.
**Sources** — ADR-007, idea.txt 148-172, 560-564.

## AI — data-driven state machine + behavior sliders

**Goal** — enemy behavior as *data*, editable by creators without scripting (no arbitrary code in world files, ADR-004).
**Behaviors** — state machine (idle → patrol/chase → windup → attack → recover → combo/break); **telegraphs** visibly signal incoming attacks; behavior tuned via bounded sliders (aggression, reaction lag, attack cadence, poise); use a **condition/action grammar** like the narrative engine (`08`) for triggers — creators compose, never code.
**Parameters / bounds** — bounded sliders; registry of reusable condition/action nodes.
**Data / JSON** — enemy config: trigger conditions + behavior graph (data-driven).
**Interactions** — `01` combat clock sync (hitbox fairness), `08` events (miniboss), `04` drops.
**Edge cases** — behavior loops, unreachable idsle, missing return-to-state.
**Open questions** — slider set exact list (aggression, telegraph duration, poise, hitbox forgiveness per enemy).
**P9 pattern requirement (logged 21/09/2026)** — spear-behind-shield archetypes need an `attacks_while_guarding` pattern flag (guard-up + strike simultaneously is inexpressible in a guard-XOR-swing model); guard temperament (turtle-vs-aggressive, advance-while-guarding speed tax) is pattern data, never stats.
**P3 migration (logged 21/09/2026)** — the P2 `shielded` / `shield_half_angle` config fields merge into the unified `{damage, damage_type, guard_absorb, stability, block_arc}` stat block (`17`/`04`); `take_hit → {killed, blocked}` stays the resolution seam, only its internals become a stat lookup. No guard-depth code until the P3 stat block lands.
**Sources** — idea.txt 100, 496, 134, 527; roadmap P2/P9.

## Enemy activation (proximity)

**Goal** — enemies sleep until the player is near; big zones stay cheap.
**Behaviors** — AI disabled when player far; activates on proximity (aggro radius); deactivation returns to idle/patrol.
**Parameters / bounds** — activation radius per archetype (bounded), state resets.
**Data / JSON** — per-enemy `activation_radius`.
**Interactions** — zone streaming (`06`), character perf budget (`02`).
**Edge cases** — enemy spawned mid-aggro (blocked), activation during a cutscene.
**Sources** — idea.txt 2434.

## Poise / stagger

**Goal** — poise is a real mechanic, not cosmetic: enemies react visibly and can be interrupted.
**Behaviors** — poise pool; hits accumulate stagger; at breakpoint → flinch/knockback/interruption; flinch cancels the windup in-flight.
**Parameters / bounds** — poise/breakpoint per enemy, hit poise damage from weapon data (bounded).
**Data / JSON** — `poise`, `poise_reset_time`, `hit_poise` fields.
**Interactions** — `01` impact chain (flinch micro-reactions), `04` weapon payloads.
**Edge cases** — boss windup vs player flinch (bosses resist more), stagger during boss phase change.
**Sources** — idea.txt 2006, 2026.

## Per-enemy weaknesses / resistances (damage-type table)

**Goal** — the tactical texture of the combat-depth layer (`17`): a world tells players "use the shock-knight's weakness" without any engine change.
**Behaviors** — each enemy config carries a **bounded resist table** per damage type (**7**: slash / thrust / strike + fire / lightning / magic / dark) + a **status susceptibility** set (bleed / poison / frost build-up multipliers) sourced from bounded presets (×0.5 resistant… ×1.25 weak — the base rosette, never free floats); bosses use the same fields with a preset "boss-level resist" cap (ADR-018 keeps boss fights fair/readable, never requiring a niche type to win).
**Parameters / bounds** — preset rosette bound (×0.5 … ×1.25), status multipliers bounded, boss cap preset.
**Data / JSON** — enemy config: `resist {slash, thrust, strike, fire, lightning, magic, dark}` + `status_suscept {bleed, poison, frost}`; validated at import (ADR-009), defaults = neutral.
**Interactions** — damage types/status (`17`), stat-derived resistances (`03`), weapon damage type (`04`), damage-type HUD hints (tooltip hints, `11`).
**Edge cases** — missing table (neutral by default), overshoot bounds (import error), boss immune-type requirement accidentally authored (validator warns — bosses must stay beatable with any valid build).
**Sources** — ADR-018, features.md §4, `17_combat_depth`.

## Boss in V1 (archetype + marker)

**Goal** — every world can have a boss-level encounter without a dedicated boss editor.
**Behaviors** — a boss is **any enemy archetype** flagged `boss_level: true` on its config; the base applies a bounded stat scaling set (HP, damage, poise multipliers from a preset table — same bounds-based discipline as weapons); the archetype's own telegraphs/behavior pattern stay fully readable; on death the base auto-sets the `boss_defeated(id)` flag (`08`), which any fog gate / condition can read; no multi-phase state machine in V1 — a boss has one HP pool and one behavior pattern (phases are the vaulted editor's job).
**Parameters / bounds** — `boss_level` bound on config; multiplier presets bounded (no unbounded boss inflation).
**Data / JSON** — `boss_level: bool` + `boss_scale` preset id on the enemy config.
**Interactions** — `08` (`boss_defeated` condition), `07` fog gates, `11` boss HP bar, `13` boss intro (vault).
**Edge cases** — two boss-level enemies in one arena = placement of N companions (multi-bar `11`); boss defeated state persists in run `GameState` (`15`).
**Sources** — features.md §4 (decision).

## Boss editor (state machine, phases)

**Goal** — (post-V1 per roadmap) author bosses: keyed phases, phase-change triggers, unique behaviors on humanoid bones.
**Behaviors** — a boss is an archetype + a **state machine with phases** (e.g. phase 1 → phase 2 at 50% HP); each phase can gate patterns, attacks, speeds, visuals via flags/conditions; fairness tuned "frame by frame", playtested with a simulated player in the editor.
**Parameters / bounds** — phase count bounded, pattern registry per archetype.
**Data / JSON** — boss config: phase states + transitions (condition/action grammar reused).
**Interactions** — `01` fairness (never inflated boss hitboxes), `08` (boss-defeated flags / fog gates), `13` (boss intro — vault).
**Edge cases** — player skips phase (overly aggressive), phase-triggered fog gate, death mid-transition.
**Open questions** — position of boss editor in roadmap (deferred); pattern authoring depth.
**Sources** — idea.txt 102, 108, 496-500, 2225-2251; roadmap P9.

## Boss hitbox fairness (critical learning)

**Goal** — bosses play by the same swept-hitbox rules as the player: no "pool noodle" unfair pulls.
**Behaviors** — knob learned from Radahn 1.14 (shrunk non-weapon hitboxes) and modern souls-likes (Nioh, Lies of P precise detection): forgiveness asymmetry favors the *player* only.
**Parameters / bounds** — boss hits = swept casts on offensive frames, not inflated volumes.
**Data / JSON** — weapon/attack data reused (mask ranges).
**Interactions** — `01` swept hitbox, dodge i-frames.
**Edge cases** — attack vs dodge simultaneous (favor attacker only for player).
**Sources** — idea.txt 2225-2286, 2154-2212.

## Miniboss / gank encounters

**Goal** — mid-tier threats and multi-enemy fights from placement + flags, no new system.
**Behaviors** — "gank" = placement-level concern (several enemies around a point); miniboss spawning is an `08` trigger event (flag → spawn miniboss).
**Parameters / bounds** — placement only; spawn via event grammar.
**Data / JSON** — miniboss spawn event; gank = enemy placements.
**Interactions** — `08` events, per-zone boss state (`15`).
**Edge cases** — miniboss respawn after death (persisted state).
**Sources** — idea.txt 1913.

## Per-zone boss/chest/lever state persistence

**Goal** — cleared content stays cleared across sessions.
**Behaviors** — world_id-scoped state: boss defeated, chests open, levers pulled, items taken (idea.txt 2519); stored in run/world `GameState`.
**Data / JSON** — per-world state map.
**Interactions** — GameState save (`15`), loot (`04`), fog gates (`07`).
**Sources** — idea.txt 2438, 2519.

## Boss state references

**Goal** — allow flags/conditions to read "boss X defeated".
**Behaviors** — the state system exposes a readable condition (e.g. `boss_defeated(X)`) usable in dialogue conditions and fog gates.
**Data / JSON** — see `08` flag conditions + `15` GameState.
**Sources** — idea.txt 2438, 2519; `08_narrative.md`.