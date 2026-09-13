# 16 — Polish, QoL & accessibility

> The "feels good / is fair / can be played by anyone" layer plus explicitly-out items. Neutral spec — status lives in `features.md`.

## Difficulty & fairness guarantees

**Goal** — the genre's brutal-but-fair contract survives authoring chaos.
**Behaviors** — design guarantee: the engine's combat rules are base-owned (`01`, `03`); creators tune content placement, never the fairness algebra; heuristic checks at export (light budget, enemy density soft quotas); telegraph readability enforced by morph-bounds.
**Parameters / bounds** — density/light quotas (soft, informational).
**Data / JSON** — validation reports.
**Sources** — idea.txt 168-172, 2755 (quality-abuse ponder), ADR-007.

## Accessibility (settings-level — post-V1)

**Goal** — the essential comfort/access toggles at Options.
**Behaviors** — UI scale; screen-shake reduction toggle; color-blind-safe HUD options (HP bars vs palette-safe colors); subtitle option for dialogue text. (Rumble on/off + intensity is a base setting from P2 — see Controller rumble below.)
**Parameters / bounds** — binary toggles + scales.
**Data / JSON** — settings persistence.
**Interactions** — `11` Options.
**Open questions** — full colorblind palette mapping vs simple contrast.
**Edge cases** — none in V1: the whole access-toggles set ships **post-V1** (resolved 13/09/2026) — only rumble (below) is a V1 setting.
**Sources** — screens Options; idea.txt (not discussed — gap).

## Controller rumble (haptics)

**Goal** — a second feedback channel on hits/dodges/death.
**Behaviors** — gamepad rumble on impact (with hitstop/shake), on player damage, on death; on/off + intensity in Options from P2 (base setting, not an accessibility extra); disabled-safe in menus.
**Parameters / bounds** — on/off + intensity in Options.
**Data / JSON** — settings.
**Interactions** — `01` impact chain, `11` Options.
**Sources** — decision 12/09 (V1, P2).

## Editor comfort

**Goal** — the maker is the product: its ergonomics matter as much as the game.
**Behaviors** — auto-save/editor state recovery; undo depth; quick one-key playtest everywhere; error surfacing (inline, jump-to); light-budget counter; keyboard/gamepad both usable in editors; status bar per editor.
**Data / JSON** — editor prefs.
**Interactions** — `09`.
**Sources** — idea.txt (editor comfort implied), roadmap.

## Localization readiness (UI)

**Goal** — string-table architecture so languages are data-only later.
**Behaviors** — keyed string tables; content text (creator-authored) stays data/English; **English-only table + no language setting in V1** (resolved 13/09/2026 — V2 adds languages and the selector).
**Data / JSON** — string table.
**Sources** — screens Options, features.md §12 (🔒).

## Save/load polish messaging

**Goal** — players understand save state at a glance.
**Behaviors** — toasts ("saved"), an explicit Save run (bonfire hub), run list metadata, quarantine dialog on corrupt save.
**Data / JSON** — run metadata.
**Interactions** — `15` save integrity, `11`.
**Sources** — ADR-016.

## Out-of-scope (explicit)

**Photo mode** (⚫) — no value/cost ratio in a maker (features.md §10).
**Achievements** (⚫) — needs an account/service (features.md §12, ADR-004).
**Crafting/upgrades** (⚫) — excluded (features.md §3).
**Standalone game export** (⚫) — rejected for liability/versioning reasons (idea.txt 220-238).
**P2P co-op** (⚫ deferred) — deferred technology (idea.txt 368-378).
**Multiplayer/server** (⚫) — ADR-004 (idea.txt 614-627, 632-638).

## Open-ended QoL (not yet decided)

- ~~Damage numbers vs bars-only for hosts~~ — **resolved 13/09/2026**: bars-only in V1, no flying numbers.
- ~~Input remap depth (per-button vs preset rows)~~ — **resolved 13/09/2026**: gamepad = bounded layout rows, keyboard = full per-key remap; per-button gamepad remap joins the post-V1 accessibility group.
- ~~Buff icons vs minimal HUD~~ — **resolved 13/09/2026**: minimal catalog icon strip, cap 4 + "+N", depleting ring for time left (see `11`).