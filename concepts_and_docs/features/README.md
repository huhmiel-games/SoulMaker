# SoulMaker — Feature specs (detailed)

> The detailed specification companion to `features.md` (the master completeness **net**). One file per domain. This folder describes **how each feature behaves**, exhaustively and phase-neutral: status lives only in `features.md` (single source of truth). Sources mined from `idea.txt`, `decisions.md` (ADR-001→019), `roadmap.md`, `screens.md`, `asset_pipeline.md`.

## Files

| File | Domain |
|---|---|
| `01_player_combat.md` | Controller, camera, dodge/stamina, attacks, game feel (hitstop, shake, VFX, blade rebound, swept hitboxes), haptics |
| `02_character.md` | Rig/skeleton, retargeting, animation library, attachments, morphs, 2D faces (atlas, talk loop, blink), config JSON, per-instance duplication, character perf |
| `03_progression.md` | 8 attributes + derived, cost curve, currency, bonfire, estus, starting template, death + soul orb, display overrides, respec/NG+ |
| `04_inventory.md` | Slots, equipment on rig, quickbar, consumables, key items, drop tables, loot, min requirements, shops |
| `05_enemies.md` | Archetypes, bounded morphs, AI (state machine, telegraphs, poise), data-driven patterns, bosses (phases/state machine), miniboss/gank |
| `06_worlds_levels.md` | Prefabs, maps, sockets, world graph, fog transitions, ambiance, zones/chunks, streaming, impostors/backdrops, light budget, collisions |
| `07_world_objects.md` | Chests, corpses, levers, doors, fog gates, elevators/moving platforms, shortcuts, triggers, key-item gates |
| `08_narrative.md` | Flags registry, conditions/effects engine, dialogue graph, NPCs, lore, quests, graph validation |
| `09_editors.md` | Every Create editor + shared UX (gizmos, snap, catalog panel, undo/redo, one-key playtest, save/export/import, live validation) |
| `10_catalog.md` | Asset taxonomy, manifest, schema, bounds, palette/style, starter catalog (1st-party), Discord→Drive community stream, credits |
| `11_ui_screens.md` | Boot, two-door hub, world library, options, bonfire hub (no pause), HUD, level-up/inventory/death screens, import/export, gamepad/keys/localization |
| `12_audio.md` | Audio system (neutral spec): buses, positional, music-as-data (tracker/synth), SFX per material, ambiance, volumes |
| `13_presentation.md` | Cutscenes, area name cards, boss intro/defeat, camera framing, face-visible moments |
| `14_distribution.md` | Shared JSON format, versioning, exhaustive validation, tutorial + example world, Steam Workshop, "user content" scope |
| `15_tech_platform.md` | Godot 4.7/Jolt/GDScript, rendering, quality tiers, perf budget, save serialization/atomicity, streaming, data-only modding |
| `16_polish_qol.md` | Difficulty, accessibility, settings, comfort, explicitly-out items (photo mode, achievements) |
| `17_combat_depth.md` | V1 martial extensions (ADR-018): shield guard, parry/backstab/riposte criticals, ranged weapons + ammo, damage types + status build-up, buffs/debuffs, player poise/hyper-armor, roll tiers, backstep, plunge, two-hand grip, kick, ladder locomotion, held torch |

## Template

Every feature follows the same block:

```
### <Feature>

**Goal** — player value / why it exists.
**Behaviors** — complete behavior description.
**Parameters / bounds** — numeric bounds, allowed ranges.
**Data / JSON** — serialization fields.
**Interactions** — links to other specs (file:feature).
**Edge cases** — corner cases, failure modes.
**Open questions** — decisions still pending.
**Sources** — idea.txt line ranges, ADR/roadmap/features refs.
```

Not all fields are always filled — empty ones are deliberately left blank (missing detail, not forgotten).

## Neutrality rule

- These specs describe the **complete final feature** without referencing V1/V2/vault status.
- **Status** (🔒 locked / 🟡 pending / 🔵 vault / ⚫ out / ❔ open) lives only in `features.md`.
- When a feature's status changes, only `features.md` is edited. When behavior changes, only the spec is edited.

## Maintenance contract

- The spec is the **"what is missing?" detail review** — run design discussions against it, not against the roadmap.
- Editing a spec does not change sequencing; sequencing changes go to `roadmap.md`.
- New behavior must pass through: `features.md` (existence + status) → this folder (detail) → ADR if it's a rule change → roadmap if it needs a phase.