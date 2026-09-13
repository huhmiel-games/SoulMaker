# 11 — UI & Screens

> Every visible screen + the user flows. Companion to `screens.md` (the authoritative screen inventory); this spec adds behavior detail. Neutral spec — status lives in `features.md`.

## Boot screen

**Goal** — branded entry point, momentary.
**Behaviors** — logo, version number, engine disclaimer; skip on input (auto advance).
**Data / JSON** — none.
**Interactions** — `14` (version stamp).
**Sources** — screens Boot (P0/P12).

## Home (two-door hub)

**Goal** — Play vs Create, contextual Continue per door, transverse actions in a corner.
**Behaviors** — Play door → Continue run · New game · Load (lists runs) · World library; Create door → four editors in cascade (prefab → map → world → character); each door keeps its own "Recent"; import split by nature (world → Play, prefab/character → Create); "user content, not verified" disclaimer shown at import.
**Data / JSON** — Continue pointer (run vs project).
**Interactions** — `09`, `14`.
**Sources** — screens Home, idea.txt 1675.

## World library (Play destination)

**Goal** — local installed/imported worlds.
**Behaviors** — list/cards with title, thumbnail, creator info; import zone (drag & drop of a shared file or file-picker — frictionless, "like opening an image"); open → New game / Load (run list per world, ADR-015); delete with confirm; (later) Workshop browse.
**Data / JSON** — installed-world index.
**Interactions** — `14` import, `03` runs.
**Sources** — screens Hub/World library, idea.txt 1675-1677.

## New game flow

**Goal** — make a fresh run in a chosen world.
**Behaviors** — 1) choose world → 2) create player character (editor, "start quickly" default) → 3) optionally name the run (ADR-015: New game never overwrites) → 4) choose beginning spawn point → 5) start.
**Interactions** — `02` character editor, `03` starting template/runs, `06` spawns.
**Sources** — screens New game.

## Options

**Goal** — graphics, audio, controls, interface.
**Behaviors** —
- **Graphics**: quality tiers (ADR-002 — render scale, MSAA, shadow quality, light cap); vsync; windowed/fullscreen; resolution; low-end tier is a first-class preset.
- **Audio**: master / music / SFX / ambiance / UI (sliders are an **inert shell** until audio lands — ADR-014).
- **Controls**: gamepad via **bounded layout rows** (Souls default + alternates), **keyboard full per-key remap**, sensitivity, camera invert, **rumble on/off + intensity (gamepad)**.
- **Interface**: UI scale, reset to defaults; apply-and-keep with confirm when reversible. (No language row — English-only, resolved 13/09/2026.)
**Data / JSON** — settings file, versioned.
**Interactions** — `15` tiers, `12` audio (vault), `16` accessibility.
**Sources** — screens Options.

## Menu hub at bonfire (no in-game pause)

**Goal** — the souls convention: no pause during play; the run's management lives at the bonfire.
**Behaviors** — gameplay never freezes (not even mid-fight): Options · Save run · Quit to menu · Level-up are all reachable **only from a bonfire**; quitting mid-run returns to Home with progress since the last bonfire discarded (bonfire = the save point, ADR-013/015); no hitstop-pause handling needed in combat.
**Data / JSON** — none; save at bonfire.
**Interactions** — `03` runs/saves/bonfire, `01` (no pause during hitstop).
**Sources** — screens bonfire hub, decision (souls convention).

## HUD (in-game)

**Goal** — live readout: HP, stamina, souls, estus, quickbar, buffs, boss bar.
**Behaviors** —
- HP bar, stamina bar, souls counter (name per world `currency_name`), estus charges, equipped consumable quickbar, buff icons;
- **buff icon strip** (resolved 13/09/2026): small catalog icons (24-28px) anchored to the HP/stamina corner block, each on a **depleting ring** = time left; one icon per **active timed effect** (canonical id — no-stack gives ≤1 per id), **permanent/ambient effects hidden**, **cap visible 4 + "+N"**, tooltip on hover (name + remaining time, no on-screen numbers); status build-up meters stay separate small bars;
- **boss HP bar** (bottom, boss-level enemies only) — HUD element, *not* a cinematic (ADR-014);
- **FP bar** shown only when FP content exists (V2 hook);
- no flying damage numbers (bars-only — resolved 13/09/2026, souls convention);
- **no souls pop-text** on kills (resolved 13/09/2026 — the counter readout is enough);
- **soul-orb recovery beacon** (resolved 13/09/2026): faint golden pulse at the orb's world point, visible through geometry while `orb_state = present`, hidden once recovered — no arrow/compass (`03`).
**Data / JSON** — HUD layout config (souls name from world override).
**Interactions** — `03`, `04` quickbar, `01` impact feel.
**Edge cases** — respawn HUD reset, death HUD override, UI scale adjustment.
**Open questions** — none (buff icon strip resolved 13/09/2026 — cap 4+N, depleting ring, catalog icons).
**Sources** — screens HUD, ADR-011, ADR-014.

## Boss HP bar (dedicated)

**Goal** — boss-level enemies show a persistent bottom bar during the fight.
**Behaviors** — enabled only for enemies flagged `boss_level` (catalog/enemy config); fades in on aggro, fades out on death/disengage; no phase segments in V1 (single HP pool — phases arrive with the vaulted phase editor).
**Parameters / bounds** — min boss-level marker bound.
**Data / JSON** — `boss_level: bool` on enemy config.
**Interactions** — `05` bosses, HUD; nice-with `13` boss intro (vault).
**Edge cases** — two boss-level enemies simultaneously (multi-bar), HP-name display.
**Sources** — decision 12/09, `features.md` §10.

## Level-up screen (bonfire)

**Goal** — spend currency on stats with live preview (access from bonfire, not pause).
**Behaviors** — 8 canonical attributes **named per world `stat_names`**, currency named per `currency_name`, level, cost of next point (single curve), bounded sliders, current/result preview (HP/stamina/FP/load), confirm/back.
**Interactions** — `03` progression, display overrides.
**Sources** — screens Level-up (P7).

## Inventory / equipment screen

**Goal** — equipment, consumables, key items management.
**Behaviors** — slots (weapon/offhand shield/clothing/helmet/chest armor/gauntlets/leggings/**accessory ×4**), estus charges + consumables quickbar, key items read-only (flags-gated), stat/weight/poise readout incl. min-stat requirements; equip/unequip, consume, sort; no crafting/editing in V1.
**Interactions** — `04` inventory spec.
**Sources** — screens Inventory (P8).

## Death / respawn screen

**Goal** — the souls death loop.
**Behaviors** — death vignette/fade, "grace" message, **"your souls await"** line (ADR-013), respawn at last bonfire with run state restored; a no-lose fork: full screen vs embedded overlay — validated at P2 (screens).
**Interactions** — `03` soul orb recovery (back in the world), `04`.
**Sources** — screens Death, ADR-013.

## Socket/fog transition (screen-level)

**Goal** — the seam that doubles as loading (no dedicated loading screens).
**Behaviors** — fog fade + depth/height, 2-4 s rhythm; world-graph seam (V2 impostors beyond).
**Interactions** — `06`.
**Sources** — screens Transitions, idea.txt 2436.

## Load / Save run UI

**Goal** — browse runs, save current, resume.
**Behaviors** — **Load = main menu only (Play door)**: lists the world's runs (name, date); no run switching during play — the only exit mid-run is a bonfire (save & quit, progress since last bonfire discarded); confirm-overwrite semantics only for manual re-save; atomic write + quarantine messaging (ADR-016); toast "saved".
**Interactions** — `03` runs, `15` save integrity.
**Sources** — screens New game/Load, ADR-015/016.

## Import/export flows (with disclaimer)

**Goal** — frictionless sharing; visible "user content" trust model.
**Behaviors** — drag & drop file anywhere-importable (Play library / Create); "user-created content, not verified" banner on imported worlds; export as a single shareable JSON file from each editor; stale-format notice ("created with version X — some new features missing").
**Interactions** — `14` distribution, `09` editors.
**Sources** — idea.txt 1671-1677, screens.

## Credits

**Goal** — attribution from the manifest.
**Behaviors** — read manifest → credits/attribution grid (engine, assets, community); updates with each build.
**Interactions** — `10` credits.
**Sources** — screens Credits, ADR-010.

## Contextual Continue

**Goal** — one visible "resume" per door, no wasted taps.
**Behaviors** — Play: resume latest run (deep-link right into it); Create: resume latest edited project (its editor).
**Data / JSON** — Continue pointers (run/project ids).
**Interactions** — `03` runs, `09` editors.
**Sources** — screens Home, decisions (hub).

## Gamepad & keyboard controls (UI level)

**Goal** — full controller support in menus & play.
**Behaviors** — UI focus follows gamepad D-pad/left-stick; **gamepad = bounded layout rows** (Souls default + alternates, picked in Options; physical button ids, no contextual labels), **keyboard = full per-key remap**; UI scale for sofa distance; camera invert.
**Parameters / bounds** — focus navigation rules per screen type; gamepad rows validated at import like all data.
**Interactions** — `16` accessibility, Options.
**Open questions** — none (mapping resolved 13/09/2026: gamepad layout rows + keyboard per-key; canonical layout below; per-button gamepad remap joins the post-V1 accessibility group).
**Sources** — idea.txt (absent/gap), screens Options ("controls").

### Default controls (canonical — resolved 13/09/2026)

**Gamepad — "Souls" (default preset row)** — physical button ids:

| Action | Button |
|---|---|
| Move | Left stick |
| Camera (sensitivity + invert in Options) | Right stick |
| Light attack | R1 |
| Heavy attack | R2 |
| Guard (all instruments, `17`) | L1 |
| Offhand action (parry / ranged aim) | L2 |
| Two-hand toggle | Y |
| Dodge (tap) / sprint (hold) / cancel (menus) | B |
| Interact / confirm (menus) | A |
| Quick-item use | X |
| Cycle quickbar (D-pad up = estus when equipped) | D-pad |
| Lock-on / switch target | R3 |
| System menu (bonfire hub in play — no pause) | Start |

Alternate rows (bounded, same validation): **Souls Mirror** (left-handed — mirrored sticks/shoulders/face), **Souls Classic** (DS1-style face conventions). Rumble = on/off + intensity, base setting from P2 (`16`, `01`).

**Keyboard defaults** (full per-key remap — conflicts warned, never blocked): WASD move, mouse look, LMB light, RMB heavy, LShift guard (hold), Alt offhand action (hold), F two-hand, Space dodge/sprint, E interact, R quick-item use, Q cycle quickbar, Middle mouse lock-on, Esc system.

**No dedicated buttons for**: kick/push (forward+Light, `17`), backstep (dodge with neutral/back input, `01`), plunging (attack key buffered mid-fall, `17`).

## Localization (UI string system)

**Goal** — all UI text through a keyed string table so future languages are a data-only add.
**Behaviors** — string-table resource (**English-only table in V1**); **no language select in V1** (resolved 13/09/2026 — V2 adds languages); **game content strings stay data** (creator-authored text is never localized in V1).
**Data / JSON** — string table (en); no language setting in V1.
**Interactions** — none in V1 (no selector; **`Options` carries no language row**).
**Sources** — screens Options, features.md (§12, 🔒).

## Photo mode (out)

**Goal** — excluded: no value/cost ratio in a maker.
**Sources** — features.md ⚫.