# 17 — Combat depth (guard, criticals, ranged, damage types & status)

> The V1 martial toolkit under ADR-018: the systems that make a souls-like *feel correct* beyond the base swing — blocking, criticals, ranged weapons, damage-type/status layers, movement and tooling depth. Companion to `01_player_combat.md` (base locomotion/attack/impact), `03_progression.md` (stamina, equip load, resistances, roll tiers), `04_inventory.md` (shield/ammo/accessory payloads), `05_enemies.md` (weaknesses, poise). Neutral spec — status lives in `features.md`; the 🟡 open items are settled at the P3 design pass (ADR-018).

## Block / guard with shields

**Goal** — a readable defensive option: blocking commits stamina, breaks when exhausted, and converts a hit into a cost instead of damage.
**Behaviors** — guard raises the **blocking instrument**: a shield (offhand slot `04`) or **any weapon's own guard values** (one- or two-handed); while guarding, incoming hits convert into **stamina damage** on the blocker (based on the instrument's `stability`, attacker's hit stamina damage) and apply reduced HP damage (flat `guard_absorb`); stamina exhausted → **guard break**: posture collapses, shield-pushed, brief vulnerability window, no stamina regen during recovery; blocking faces must respect an **arc** (camera-facing frontal cone) — hits from outside the arc bypass the guard.
**Parameters / bounds** — stat block bounded and **identical between weapons and shields**: every weapon carries guard values, every shield carries attack values (damage/damage_type), the distinction is the value profile (weapon = high damage / weak guard; shield = strong guard / weak damage); payload: `guard_absorb` (0-100% flat reduction), `stability` (stamina-cost multiplier per hit), `block_arc` (front cone), `hit_stamina_damage` upper bound from attackers; guard recovery (cannot re-block during own recover).
**Data / JSON** — **shared stat block for weapons AND shields**: `{damage, damage_type, guard_absorb, stability, block_arc, weight, poise}`; shields add `parry_window` (0 = cannot parry); validated at import (ADR-009/012).
**Interactions** — stamina economy (`01`/`03`), poise break (`01`), enemy attacks deliver `hit_stamina_damage` (`05`), guard break feeds the critical stance (`05`/below).
**Edge cases** — blocking while stamina is 0 (blocked input / delayed guard), mid-combo guard (from block-eligible state only), shield struck while breaking (double-tax avoided — one resolution), guard vs boss heavy (absorb capped so bosses remain threatening).
**Open questions** — guard/parry targeting tuned at P3 (see Two-handed grip below): two-handing **keeps guard** (via the weapon's own guard values, weaker than a good shield) and **cancels parry**; parry requires a shield only — light (ideal window), medium (shorter window), great shields cannot parry. (Corrected 13/09/2026 — the earlier "two-hand disables guard" was wrong against actual souls behavior.)
**Sources** — ADR-018, features.md §1.

## Criticals: parry / backstab / riposte

**Goal** — the high-risk, high-reward resolution: it must read as a *temporary window of truth* after a correctly timed defense.
**Behaviors** — two routes to a **critical stance** on a target (a bounded post-stagger state):
- **Parry**: a quick timed action **available only with a shield in hand** — **light shields** (ideal: **8-12 frames ≈ 135-200 ms**), **medium shields** (shorter: **6-8 frames ≈ 100-135 ms**), **great shields cannot parry** (`parry_window: 0`); **two-handing cancels parry** (shield sheathed). Attacks flagged `parryable` (bounded base set — normal melee; heavy attacks parryable with a narrower window; jump/plunge/moves excluded) that land **within the parry window** → target enters critical stance; wrong timing (**whiff**) → reduced defensive coverage + stamina cost **and a longer recover (~0.5 s)** — a miss is punishable.
- **Backstab**: an attack input on a target caught in neutral **or in animation-commit**, **within the rear arc** (**±30° off the target's back axis**) → critical stance. The window holds **~0.6 s** while the target is animation-caught (attack/slow-recovery states); it resolves on the trigger or clears when the state does.
- In critical stance (**~1.5 s** max), a **riposte** input deals the critical hit with the weapon's **`critical_multiplier`** (**×1.5 light weapons … ×2 heavy**, bounded) on a dedicated shared-rig animation, with brief invulnerability and high poise damage; the stance also opens on **guard break** (above, and kick below); the target shakes it off when the window expires (no chain-crit lock).
**Parameters / bounds** — parry window per shield class at 60 fps reference: **light 8-12 f / medium 6-8 f / great 0**; whiff recover **~0.5 s** + stamina cost; `parryable` list bounded (base catalog); backstab cone **±30°** behind / window **~0.6 s**; stance window **~1.5 s**; `critical_multiplier` **×1.5-×2** (weapon payload); one crit at a time.
**Data / JSON** — attack entries: `parryable: bool` (+ optional `parry_window_shrink` for heavy attacks); weapon entry: `critical_multiplier` (×1.5-×2); shield entry: `parry_window` (frames, 0 for great shields); critical animation via the shared rig (`02`).
**Interactions** — guard break (above) also feeds critical stance (posture broken → same stance); poise/stagger (`05`); boss immunity policy (bosses resist guard-break-to-crit per bounded resist — ADR-018 keeps bosses fair).
**Edge cases** — parry vs projectile (not parryable in V1 — ranged uses dodge), two opponents in stance (take the nearest), enemy in stance while the player dies, parry during hitstop (input buffered).
**Open questions** — **resolved in-doc** (values above); residual: the exact base-catalog `parryable` list is finalized with the starter catalog (feel-tuned at P3).
**Sources** — ADR-018, features.md §1.

## Ranged weapons (bow / crossbow) & ammo

**Goal** — a martial ranged option (no magic in V1): aimed, committed, economy-driven.
**Behaviors** — **bow**: draw/hold with **charge tiers** (light pull → full draw), release fires; travel while drawn (move-slow); manual aim reticle + optional **ranged lock-on** (fov vs distant targeting); **crossbow**: pre-loads one bolt (reload animation between shots), fires on trigger. Projectiles are physical (speed, gravity, range) and reuse the **swept-cast** fairness (`01`) — the projectile's hit corridor, not an inflated AoE. Ammo is a **base item type** (`04`), stacks, consumed per shot (no empty-slot shoot); arrow/bolt variants bounded.
**Parameters / bounds** — draw charge tiers, projectile speed/gravity bounds, max range + falloff, ammo stack bounds, ranged lock-on distance/reticle drift, reload window (crossbow), stamina cost per shot.
**Data / JSON** — ranged weapon item payload: `{projectile_id, draw_tiers, range, stamina_cost, ammo_type, clip_capacity (crossbow)}`; ammo item: `{ammo_type, count, damage, damage_type}`; both validated at import.
**Interactions** — status effects (`04` section below — elemental/status arrows limited to catalog presets), drop tables (`04`), quickbar/ammo HUD (`11`).
**Edge cases** — interrupted draw, shot canceled by hit, shoot at point-blank (projectile spawn clear of camera), out of ammo (slot dims), lock-on target beyond range.
**Open questions** — **resolved 13/09/2026**: ranged lock-on *follows the target* — the camera tracks the locked enemy (souls-style aimed shot, projectile flies toward target). Residual feel (exact reticle drift, ammo-economy pace) tuned at P3. Whether crossbow reload is a timed rhythm or a fixed recovery.
**Sources** — ADR-018, features.md §1.

## Damage types & status build-up

**Goal** — damage with *texture*: choosing a weapon type and a status is a real tactical layer, all bounded by base presets.
**Behaviors** —
- **Damage types** — **7 in V1**: physical (slash / thrust / strike) + elemental (fire / lightning / magic / dark); every damaging hit carries one type; the target's **resist table** (per-entity, bounded) applies a flat multiplier per type from the **preset rosette tags** (`×1.25` weak, `×1.0` neutral, `×0.75` resistant, `×0.5` hard — never arbitrary floats); **armor-dominant philosophy** (resolved 13/09/2026): the 7 resists derive mostly from the armor's flat pool, each type adds a small bounded stat baseline (`03`), accessories stack on top (`resist-push`, additive — `04`); elemental damage also flows from **temporary weapon coatings** (resins/bundles, `04`) — its role is bypassing heavy physical walls.
- **Status build-up** (bleed / poison / frost): attacks add build-up to a per-entity meter; the meter **decays** when not re-applied; at threshold the **proc** fires: bleed → burst HP (hemorrhage) + brief stagger; poison → damage-over-time (bounded ticks) while poisoning; frost → movement/attack slow + amplified damage intake for a window. Meters reset after proc (re-applicable); bosses have bounded status resistance (larger meters).
**Parameters / bounds** — three V1 statuses (bleed/poison/frost); build-up values per catalog preset; proc effects bounded (damage/tick/slow values in a preset table); meter caps per entity class (player / archetype / boss preset); decay rate bounded; status immunity = resist preset.
**Data / JSON** — weapon/ammo: `damage_type` (7 values) + optional `status_bonus {type, build_up}`; entity resist table: `{slash, thrust, strike, fire, lightning, magic, dark} × {multiplier}` + status build-up multipliers; per-entity status meters in combat state (not persisted).
**Interactions** — enemy weakness presets (`05`), resistances derived/egoupment (`03`/`04`), HUD status icons (`11`), buff engine (below shares the per-entity effect slot), weapon coatings (resins/bundles, `04`).
**Edge cases** — two sources same status in one tick (apply once, keep strongest), proc during target death, frost slow vs boss windup (bosses bounded-resist), status on undodgeable environment sources (bounded advice in doc).
**Open questions** — exact roster of the three statuses' proc values (tuned at P3); a 4th status (hollow-type): **not in V1** (resolved 13/09/2026 — bleed/poison/frost only).
**Sources** — ADR-018, features.md §1.

## Temporary buffs / debuffs (effect engine)

**Goal** — timed modifiers as a reusable, base-bounded subsystem — consumed by items, environment and events without new code.
**Behaviors** — an **effect node** = `{effect_id (canonical preset), magnitude (bounded), duration}` applied to an entity for a window; effect presets cover flat/timed modifiers (damage taken/given multipliers, regen rate, speed, stamina regen, resist pushes, **temporary weapon damage coatings** — resins/bundles, elemental + status, `04`); applied by **consumable items** (resins/templates, `04`), **environment zones** (hazards, bonfire-blessing via events), and **narrative events** (`08`, e.g. `trigger_event` → apply buff); same-id effects **do not stack** (refresh duration only); expiry is clean (no mid-action snap-out on damage).
**Parameters / bounds** — preset whitelist base-owned; duration/ magnitude bounds validated at import (ADR-009); per-entity concurrent effect budget (bounded) → HUD icon budget (`11`): **strip cap 4 visible + "+N" per entity** (resolved 13/09/2026).
**Data / JSON** — item payload: `{effect: {id, magnitude, duration}}` (**duration per buff object** — no global preset list, resolved 13/09/2026); zone/event config reuses the same node; applied effects live in combat state (not persisted).
**Interactions** — status build-up (above shares the per-entity effect slot), estus/consumables quickbar (`04`), HUD buff icons (`11`), conditions (V1 dialogue conditions exclude `has_buff` — resolved 13/09/2026; the `08` grammar keeps flag/item/boss-defeated only).
**Edge cases** — effect refresh while active (restart duration), effect on dead entity (dropped), two conflicting effects (preset precedence), duration 0 (disallowed).
**Open questions** — none (resolved 13/09/2026: per-object duration, no `has_buff` in V1 conditions).
**Sources** — ADR-018, features.md §3/§1.

## Player poise / hyper-armor

**Goal** — the mirror of enemy poise (`05`): heavy commitments must be *earned and readable* — big weapons tank small hits.
**Behaviors** — a bounded **hyper-armor set of frames** on heavy attacks (visible in the windup/commit): during these frames the player is not interrupted by hit reactions below a threshold; a flat **poise value** (weapon/armor contribution, bounded) trades against incoming `hit_poise` (enemy payloads, `05`); exceeding the breakpoint interrupts the attack like a normal stagger. Light attacks have minimal/none hyper-armor.
**Parameters / bounds** — hyper-armor frames per weapon class (bounded), poise breakpoints bounded, armor contributes small flat poise (bounded).
**Data / JSON** — weapon payload: `{hyper_armor_frames, poise}`; armor payload contributes `poise` (bounded); enemy payloads supply `hit_poise` (`05`).
**Interactions** — poise/stagger (`05`), stamina (`01`), impact chain (`01`).
**Edge cases** — hyper-armor vs boss heavy (boss bounded-resist breaks through), poise trade while exhausted (0 stamina = no trade), hit during start-up (pre-hyper-armor frames are interruptible).
**Open questions** — none (passive — resolved 13/09/2026).
**Sources** — ADR-018, features.md §1.

## Equip-load roll tiers (fast / mid / fat)

**Goal** — equipment weight should *mean* something in how the character moves — a spelling choice, not a flat downside.
**Behaviors** — equip-load ratio (current load / max from Endurance, `03`) selects a **roll tier** (fast / mid / fat) with visible consequences: i-frame count, roll distance/speed, recovery length, and a distinct **fat-roll** posture (slower, heavier, longer recover — a clear tax). Tiers gate nothing else (no door-weight puzzles in V1).
**Parameters / bounds** — thresholds base-owned: **<30% fast / <70% mid / ≥70% fat** (resolved 13/09/2026), i-frames/distance/recovery per tier bounded, fat-roll tax visible but not crippling.
**Data / JSON** — thresholds in base (not creator-tunable); load computed at runtime from equipped items (`04` weights); nothing in world data.
**Interactions** — dodge/i-frames (`01`), stamina regen by load (`03`), HUD weight readout (inventory screen `04`/`11`).
**Edge cases** — load crossing a threshold mid-run (tier swaps live), over-encumbered at run start (template keeps it legal by construction), fat-roll broken by armor swap mid-recovery.
**Open questions** — none (thresholds resolved 13/09/2026); residual: whether the tiers *feel* right vs Endurance is validated at P3.
**Sources** — ADR-011/018, features.md §1, `03_progression`.

## Backstep

**Goal** — a short, cheap spacing tool that *baits and resets* instead of the i-frame dodge.
**Behaviors** — a quick rear hop (direction-relative, no turn); small stamina cost; **no i-frames** (spacing only — resolved 13/09/2026, the dodge stays the unique invuln tool); can chain into run/dodge/attack; block cancels into backstep.
**Parameters / bounds** — distance/speed curve, stamina cost, recovery window, no forward variant.
**Data / JSON** — base mechanic (not per-weapon); stamina cost scales with load tier (`03`).
**Interactions** — stamina (`01`), lock-on facing (`01`), enemy attack tracking (telegraph readability dedicates `05`).
**Edge cases** — backstep off a ledge, backstep into a wall (clamp), backstep during hitstop (buffered), backstep-into-buffer-roll.
**Open questions** — none (no i-frames, resolved 13/09/2026 — spacing tool only).
**Sources** — ADR-018, features.md §1.

## Plunging attacks

**Goal** — rewarding controlled drops: gravity as a weapon, once per approach.
**Behaviors** — falling (or jumping off a height) through a brief **window** above a valid target triggers a plunging melee: the character commits, deals bounded extra damage (scaled by drop speed, capped) + knockback, and lands with a recovery; only from a real drop (not from normal height).
**Parameters / bounds** — fall-distance trigger threshold, damage cap by weapon, knockback bounded, recovery after landing (can be rolls).
**Data / JSON** — plunging parameters base-owned (melee weapons only — no plunging bow shots V1).
**Interactions** — dodge/fall state (`01`), gravity/Jolt (`15`), enemy hit reactions (`05`), camera (dive reads through the locked view).
**Edge cases** — miss (full fall recovery), ledge that looks plungable but geometry blocks the window, plunging into a hazard floor, mid-plunge death.
**Open questions** — none (resolved 13/09/2026: the plunging attack requires the **attack key buffered mid-fall** — automatic on window rejected, the player commits).
**Sources** — ADR-018, features.md §1.

## Two-handed grip (moveset + strength scaling)

**Goal** — a commitment toggle that trades shield/options for raw power — a *build choice* inside V1 (no new system).
**Behaviors** — toggle (same binding as guard's alternate): **two-hand** the main weapon (shield sheathed/removed from the offhand **visually**); the weapon switches to its **two-hand moveset variant** (a data-parallel attack set — slower windups, bigger multipliers, or distinct combo) and gains a **Strength-scaling modifier**: two-handing counts Strength **×1.5** for both the **minimum-attribute requirement** and the **damage-scaling contribution** (souls convention, bounded base value). **Stamina costs are unchanged** (no monopole tax). **Guard is NOT disabled**: two-handing blocks with the weapon's own guard values (usually weaker than a good shield). **Parry is unavailable** (the shield is out of hand).
**Parameters / bounds** — two-hand variant per weapon (catalog data, falls back to base moveset if absent), scaling modifier **×1.5** (base-owned, not creator-tunable), toggle from neutral/guard states only (no mid-combo).
**Data / JSON** — weapon payload: `{moveset_one_hand, moveset_two_hand, two_hand_strength_scale: 1.5}` — falls back gracefully at import; guard values shared with the unified stat block (above).
**Interactions** — Strength scaling (`03`), shield slot (`04`), guard via the weapon's own guard values (no extra penalty); parry unavailable while two-handing.
**Edge cases** — two-hand with no comparable offhand (nothing changes but moveset), toggle during recovery, two-hand a ranged weapon (bows already two-handed — crossbow keeps offhand).
**Open questions** — **resolved in-doc**: ×1.5 STR (min-req + scaling), stamina unchanged, guard = the weapon's raw guard values with no extra tax; residual: moveset balance/personalization per starter-catalog weapon (feel, P3).
**Sources** — ADR-018, features.md §1.

## Kick / push (guard-break tool — per weapon class)

**Goal** — a cheap, single-purpose tool that cracks turtle-blockers without a full critical; the *move itself* depends on the equipped weapon.
**Behaviors** — input is **universal**: **forward-direction + light attack** (buffered, distinct from chained combos); the resolved move comes from the weapon class's **`push_move`** data. Two move types in V1:
- **Kick** (light/quick classes — daggers, straight swords, thrusting swords, curved swords, katanas, spears): quick shove, **~2 m reach**, **very low damage** (~5% of base light), **~40 stability-equivalent** guard-break (cracks a mid-cap stability block in one kick, a great shield in two); recovery **~0.4 s**; tiny knockback.
- **Blade shove** (heavy classes — greatswords, ultra greatswords, curved greatswords, great axes, great hammers, halberds, twinblades): slower shove, same ~2 m reach, **higher guard-break** (~60-80 stability-equivalent — cracks great shields in one), recovery **~0.6 s**, small forward lunge.
- **None** (bows, crossbows, torch, and any weapon without a defined `push_move`): the input is a no-op.
Whiff or vs non-blockers = near-useless (spacing risk). Pairs with the block/guard-break system (above).
**Parameters / bounds** — per-class `push_move {type: kick|blade_shove|none, reach, guard_break (stability-equivalent, bound shared with `05`), recovery}`; values validated at import (ADR-009); forward-only; no damage scaling.
**Data / JSON** — weapon payload: `push_move: {type, reach, guard_break, recovery}` (base defaults per class; a creator can override within bounds); `hit_stamina_damage` bound shared with `05`.
**Interactions** — block/guard break (above), critical stance (above — a broken guard opens the stance).
**Edge cases** — push into a rolling target (miss), push a boss (bounded-resist → small effect), push while out of stamina (blocked), weapon with no `push_move` (input no-op).
**Open questions** — **resolved in-doc** (types + class mapping, 13/09/2026); residual: the shove's visual readability is feel-validated at P3 — it must read as a *shove*, not an attack.
**Sources** — ADR-018, features.md §1.

## Ladders (climb locomotion)

**Goal** — verticality with real movement: ladders are climbable *level objects*, not teleports.
**Behaviors** — approach a ladder object → prompt → **climb up/down** (locomotion slides onto the ladder rail, snaps player feet/hands to the rig's grab alignment); combined input ascends/descends; exit at top/bottom (step-off); no attacking while climbing in V1 (simplicity); no climbing-stamina drain (accessibility for makers); falling off mid-climb = normal fall.
**Parameters / bounds** — climb speed (per rig), ladder length/alignment defined by the object (`07`), exit offsets bounded, no attacks on ladders in V1.
**Data / JSON** — ladder world object: `{length, top_exit, bottom_exit, alignment}` (`07`); locomotion is base behavior.
**Interactions** — level objects (`07`), character rig snapping (`02`), vertical shortcuts loops (`06`), fog transitions unchanged.
**Edge cases** — climbing into an enemy (enemies don't climb in V1), exit clipped by geometry, ladder rail vs physics collision (ruled by the object's collider), death mid-climb (drop).
**Open questions** — whether a quick "jump-off any point" input appears beyond top/bottom exits.
**Sources** — ADR-018, features.md §1/§7.

## Held torch (player-attached light)

**Goal** — dark spaces become choice, not wall: the player can carry light where the world stays dark.
**Behaviors** — the torch is a **tool/offhand-usable item** (slot-friendly, `04`); toggling lights a **point light attached to the rig's hand socket** (`02`) with a bounded flicker (shared catalog light presets, `10`); influences visibility only in V1 (no stamina/monster-interaction mathematics yet), making darkness a *lighting* consideration — pairs conceptually with world fixtures (torches/braziers, `06`).
**Parameters / bounds** — light preset (range/intensity/flicker) bounded from the catalog; one carried light per player; cannot double with a shield (one hand).
**Data / JSON** — item: `{light_preset_id}` — validated; the shadow/fog behavior is renderer-level (`15`, tiers P13).
**Interactions** — character socket attachment (`02`), world lighting limits (`06`), quality tiers (`15`).
**Edge cases** — torch while two-handing (falls back to sheathed), torch in water (stays lit — no light-out trigger in V1, resolved 13/09/2026), carrying a torch while using a bow (offhand conflict resolved by slot rules).
**Open questions** — none (resolved 13/09/2026: darkness stays **purely visual** — no harsh-in-the-dark gameplay knob in V1).
**Sources** — ADR-018, features.md §1.

---

## Open questions (whole domain — pending decisions)

- ~~Parry window per shield class + `parryable` list~~ — resolved in-doc (light 8-12 f / medium 6-8 f / great none; backstab ±30° / 0.6 s; stance 1.5 s; crit ×1.5-×2); residual `parryable` catalog list at P3.
- Ranged lock-on/aim + ammo-economy feel (→ P3 design pass; ammo economy at P8).
- ~~Two-handed grip Strength-scaling~~ (×1.5 in-doc); ~~kick feel~~ (push_move bounds in-doc); ~~backstep i-frames~~ (0 — spacing tool only, resolved 13/09/2026); ~~roll-tier thresholds~~ (<30/<70/≥70, resolved 13/09/2026).
- Buff/debuff duration bounds (→ P3).
- Status roster/values for the three V1 statuses (bleed/poison/frost) and possible 4th (→ P3).
- ~~Elemental damage-type balance — physical-vs-elemental armor philosophy, 7-type rosette exposure~~ — **resolved 13/09/2026**: armor-dominant 7-pool + per-type stat baseline + additive accessory `resist-push`; rosette = fixed 4-band tags (×0.5 / ×0.75 / ×1.0 / ×1.25), boss band narrowed to ×0.85–×1.15 (→ P3).
- Plunge activation (auto-window vs buffered input); torch-in-water behavior (→ P3/visual).
- ~~Status/buff budgets vs the HUD icon budget (`11`)~~ — **resolved 13/09/2026**: active timed effects iconed with a cap 4 + "+N"; status build-up meters stay separate small bars.

## Sources

ADR-018 (13/09/2026), features.md §1/§3/§4/§7, `01_player_combat.md`, `03_progression.md`, `04_inventory.md`, `05_enemies.md`.
