# 01 — Player controller & combat

> Everything about moving, fighting and *feeling* the fight. Companion to `03_progression.md` (stats), `04_inventory.md` (weapons as data), `05_enemies.md` (opponents), `17_combat_depth.md` (the V1 martial extensions — guard, criticals, ranged, damage types & status, poise, roll tiers, movement tools). Neutral spec — status lives in `features.md`.

## Third-person controller

**Goal** — precise, readable locomotion that makes a souls-like feel fair: you move exactly where you meant to.
**Behaviors** — character follows input direction in camera space; rotation is instant or eased depending on state (walk vs combat); movement is locked/slowed while attacking; depth-perceived via shadows, orientation and feet.
**Parameters / bounds** — base speed scalable by equipment load (see `03_progression.md`); acceleration/deceleration curves; walk/run/jog thresholds.
**Data / JSON** — none (base behavior); speed multipliers live on equipment weight (inventory spec).
**Interactions** — stamina (`03_progression`), i-frames dodge (below), foot IK (`02_character`), camera (below).
**Edge cases** — slope handling, ledge/step detection, death while running, input buffering of roll on release.
**Open questions** — exact feel of rotation easing (locked to camera vs free) — calibrated at prototype.
**Sources** — idea.txt 42-52, 447-458.

## Orbit camera + lock-on

**Goal** — the souls camera: orbit behind the character, clean lock-on that never feels sticky or swimmy.
**Behaviors** — orbit with mouse/right-stick; wall avoidance (camera pulls forward/down to avoid cutting through the character); lock-on centers target on screen, camera tracks it, keeps both near-vertical plane; unlocked on target death/range or by input.
**Parameters / bounds** — orbit speed (separate X/Y), min/max pitch, zoom range, lock-on max distance, lock breaking distance.
**Data / JSON** — world-level camera hints? none required.
**Interactions** — dodge rolls relative to camera-facing direction; hitstop displays a "frozen but camera alive" feel.
**Edge cases** — camera in tight corridors (wall clip), lock target behind you, multi-target switching, death of locked target mid-combo.
**Open questions** — none (resolved 13/09/2026: **tap-to-lock** — tap R3 locks the nearest target, camera-lean + tap switches, tap again on the same target unlocks; **no hold semantics**; auto-unlock on target death/range unchanged; aligns with the R3 binding, `11_ui`).
**Sources** — idea.txt 42-52, 447-458.

## Dodge + i-frames

**Goal** — the survival core: committed, readable, forgiving but costly.
**Behaviors** — dodge consumes stamina, grants invulnerability frames (i-frames), interrupts attack startup but cancels commit; direction determined by input (defaults to back if neutral); recovery state.
**Parameters / bounds** — i-frame count, stamina cost, speed/distance curve, recovery window; dodge chain depth (light roll → fast roll limits).
**Data / JSON** — base mechanic (world, on stats) — see `03_progression` for stamina/load interplay.
**Interactions** — stamina economy (`03_progression`), swept hitbox timing on enemies (`05_enemies`), boss forgiveness asymmetry (enemies' hitboxes not inflated — `05_enemies`).
**Edge cases** — dodge-in-place (neutral), direction relative to camera when locked, buffer during hitstop, dodge out of map (wall/edge).
**Open questions** — iframes standard (approx 0.4-0.5s at low/own stats) — exact tuning at combat prototype.
**Sources** — idea.txt (dodge implied by souls references), 2154-2286 (hitbox fairness).

## Stamina economy

**Goal** — a shared resource that gates every action, forcing choices (attack vs block vs dodge).
**Behaviors** — stamina drains on attack/block/dodge running; regenerates after a short delay; depleted = cannot act (limp/stagger recovery).
**Parameters / bounds** — capped, base pool derived from Endurance (`03_progression`); regen delay and rate; exhaustion stagger state.
**Data / JSON** — Endurance-derived (see `03_progression`).
**Interactions** — damage scaling vs equip load (`03_progression`), weight slows regen.
**Edge cases** — stamina during i-frames, overdraw on simultaneous actions.
**Open questions** — none major (gen-stable).
**Sources** — idea.txt (implied souls), `03_progression.md`.

## Attack system (melee, windup/attack/release)

**Goal** — a readable attack cycle: anticipation makes dodge fair, the swing makes contact exactly when expected.
**Behaviors** — attacks are segmented with **animation markers** (`play_section_with_markers`): windup → active frames (attack) → recover (release); cancel windows per phase; combos chain by input timing; attack deliberately **continues through** the target (unphysical, for flow — see 2086-2098); half-attacks never cancel commitments without cost.
**Parameters / bounds** — per-phase cancel window flags; combo chains (light→light→heavy); per-attack damage/stamina/recovery (catalog data).
**Data / JSON** — weapon/attack entries carry: `phase_markers` (windup/attack/release), `damage`, `stamina_cost`, `recovery`, `hitstop_frames`, combo data. Validated at import (ADR-009).
**Interactions** — game feel (hitstop/shake/VFX below), stamina (`03_progression`), swept hitbox (below).
**Edge cases** — attack input during knockback, mid-combo sidestep, empty swing (no target), attack while out of stamina.
**Open questions** — combo depth (2-3 hits) and whether heavies are chargeable (charge-release as a heavy variant).
**Sources** — idea.txt 1412-1445, 2024-2030, 2086-2098, 2126-2148.

## Game feel — impact chain

**Goal** — a hit must *feel* like a physical impact the first frame; remove one layer and the whole punch collapses.
**Behaviors** — on the impact frame the chain stack fires: **hitstop** (freeze this hit's result processing, camera stays alive), **screen shake** (proportional to hit power), **impact VFX** at the exact contact point (sparks/blood/flash/dust), **SFX** per material (clong metal / thud flesh at first impact image, `12_audio`), **hit reaction** (enemy flinch/stagger, micro). Heavy attacks get longer hitstop and bigger shake.
**Parameters / bounds** — hitstop 2-10 frames by power, heavier > longer; shake amplitude/duration proportional; VFX point = contact point; SFX must not drift (audio spec).
**Data / JSON** — per-weapon fields: `hitstop_frames`, `shake_scale`, `impact_vfx_id`, `impact_sfx_material`.
**Interactions** — all listed below; also `13_presentation` (boss HP bar doesn't hide the hit feel).
**Edge cases** — two opponents on the same swing (apply strongest once, not stack), hitstop (no in-game pause anyway — bonfire hub only, `11`), effect on empty swing.
**Open questions** — exact shake curve, whether character feet lock during hitstop.
**Sources** — idea.txt 1998-2030, 2064-2076.

## Screen shake

**Goal** — communicate impact magnitude through the hands.
**Behaviors** — camera shake with amplitude ∝ hit power; decay curve; tiny on light, violent on heavy.
**Parameters / bounds** — amplitude, decay, duration; separate multiplier setting (Options 11).
**Data / JSON** — attack/weapon shake field (see impact chain).
**Interactions** — hitstop keeps camera alive to read as impact; haptic rumble adds a second channel.
**Edge cases** — shake during cutscene (disabled), sidescreen dyslexia-friendliness (Options).
**Open questions** — none.
**Sources** — idea.txt 2000-2020.

## Impact VFX (sparks/blood/flash/dust)

**Goal** — orient the eye to exactly where the weapon hit, same frame as the sound.
**Behaviors** — spawn a small local effect at the contact point (world space), facing the camera implicitly (billboard or oriented to surface); color/type per material (metal, flesh, stone, wood).
**Parameters / bounds** — burst count, scale range, life — bounded presets only (catalog); per-material mapping.
**Data / JSON** — `impact_vfx_id` on weapon/attack.
**Interactions** — material lookup shared with SFX; VFX budget counter in editors (`09_editors`).
**Edge cases** — effects on invisible/transparent surfaces, fog depth hiding particles.
**Open questions** — particle budget per enemy (≤≈20 bursts).
**Sources** — idea.txt 2002, 2028.

## Blade rebound & attack recovery

**Goal** — make misses and hits both readable: after the swing, return to idle smoothly — not a video-rewind, a short reverse *allowed* by the hitstop.
**Behaviors** — the classic full reverse is rejected (breaks anticipation/gravity, 2100-2124); instead: **reverse only 3-6 frames** then elastic-blend to idle; hitstop masks the reversal so it reads as impact, not glitch; optionally a procedural weapon recoil layer or a dedicated recovery pose.
**Parameters / bounds** — reverse length 3-6 frames, blend time.
**Data / JSON** — recovery params per weapon.
**Interactions** — hitstop masks the reversal; combos decide when recovery is skipped.
**Edge cases** — reversal into another attack (chain), reversal while knocked back.
**Open questions** — recoil layer vs static pose — pick at combat prototype.
**Sources** — idea.txt 2100-2148.

## Swept hitbox (`ShapeCast3D`, masked)

**Goal** — no inflated "pool-noodle" volumes that feel unfair — the *attacker* is forgiven, never the world.
**Behaviors** — a swept capsule runs on `ShapeCast3D` per physics tick during **offensive frames only**; non-offensive frames mask the hitbox; physics callback set to `Physics` clock so hit windows match real frames; substepping only on weapon-driven casts (not the whole world).
**Parameters / bounds** — cast length = weapon range class; mask = offensive frames only; collision_mask filtered.
**Data / JSON** — per-attack mask ranges.
**Interactions** — enemy fairness corpus `05_enemies`; perf bounded (shape cast cheap; the expensive parts are `force_update_all_skeletons` and uncached bone lookups — avoided).
**Edge cases** — two targets on one tick (apply once strongest), tunneling at high speed (the sweep prevents it), boss-arena forgiveness.
**Open questions** — none (the technique is chosen).
**Sources** — idea.txt 2154-2286, 2294-2316, 2318-2340.

**Status** : spike P0 **REPORTED** 15/09/2026 — pas indispensable au démarrage ; la technique est déjà choisie, la validation est décalée en amont de P2.

## Upper/lower body layers

**Goal** — attacks without interrupting locomotion: enemy can move legs while upper body swings.
**Behaviors** — `AnimationTree` wires upper/lower via **bone filtering**, not bone-mask layers (see 1337-1401): excluded-bones on upper groups affect lower? — chosen variant: blend upper body nodes onto lower locomotion, masked by bone sets.
**Parameters / bounds** — skip excluded bones; no overlapping translations.
**Data / JSON** — character animation config (02).
**Interactions** — with melee combos and speed sync (`02_character`).
**Edge cases** — feet sliding when upper locks; animation events (footsteps) still fire on lower layer.
**Open questions** — whether weapon-swing state also freezes lower (usually yes in souls).
**Sources** — idea.txt 1337-1401.

**Status** : spike FAIL 15/09/2026 — section conservée comme intent ; l'option « blend upper body nodes onto lower locomotion, masked by bone sets » via `AnimationNodeBlend2` est écartée (somme des poids = 1 → pas de superposition bas/haut à pleine intensité). Rework de topologie (additive / masques par os) à réévaluer en P2.

## Foot IK (SkeletonModifier3D)

**Status** : spike FAIL 15/09/2026 — section conservée comme intent, pas implémentée en V1.

**Goal** — feet land on terrain, not floating on sloped geometry.
**Behaviors** — two-bone IK / FABRIK (`SkeletonModifier3D`) per leg, raycast target for ground height; influence blending to avoid pops; polish needed (~half day expected).
**Parameters / bounds** — ray max distance, blend rate.
**Data / JSON** — none (per-character, rig-owned).
**Interactions** — locomotion blend, upper/lower layers must not fight.
**Edge cases** — walking off ledges, stairs, death during foot correction.
**Open questions** — feet-on-slope vs full pose lock.
**Sources** — idea.txt 1455-1481.

## Controller rumble (haptics)

**Goal** — haptic channel reinforcing hits, dodges, deaths.
**Behaviors** — gamepad rumble on impact (same trigger as hitstop/shake), on player damage, on death/recovery.
**Parameters / bounds** — on/off + intensity in Options (`11_ui_screens`); small/large motor mapping.
**Data / JSON** — none.
**Interactions** — impact chain (above).
**Edge cases** — rumble in menus, disabled input users.
**Open questions** — none.
**Sources** — decision 12/09 (features.md §1).

---

## Open questions (whole domain — pending decisions)

- Exact rotation easing / camera feel.
- ~~Lock-on tap vs hold behavior~~ — **resolved 13/09/2026**: tap-to-lock / camera-lean tap-to-switch / tap-to-unlock, no hold (R3, `§11`).
- Combo depth and whether heavies are chargeable.
- Full reverse rejected; recoil layer vs static recovery pose.
- Pause handling during hitstop: moot — no in-game pause (menu hub at bonfire only, `11`).
- Charge-attack / weapon arts seat: theirs is `04_inventory` (weapon data) — weapon arts themselves are **vault**, but the data fields may appear.
