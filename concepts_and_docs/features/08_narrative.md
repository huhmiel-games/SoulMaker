# 08 — Narrative layer

> The grammar that makes a created world alive: flags, conditions, events, dialogue, lore. Everything is **declarative data** — creators never write code (ADR-004). The reputation-making feature. Neutral spec — status lives in `features.md`.

## Flags registry (declared before use)

**Goal** — eliminate typo-flags, enable autocompletion + validation + safe rename (ADR-008).
**Behaviors** — **declared before use**: a world declares its flag list with `initial_values` (dropdown/autocomplete in editors, `+ new flag` inline); orphan flags & close-typos detected (hint "did you mean X?"); safe rename built-in; two buckets: session vs persistent; implicit false on read.
**Data / JSON** — `flags.registry: [{id, initial, bucket}]`.
**Interactions** — every other system reads flags (doors, fog gates, bosses, quests).
**Edge cases** — rename cascades (registry-driven), flags used but undeclared → validation error.
**Sources** — idea.txt 1879-1982, ADR-008.

## Condition grammar (no free predicates)

**Goal** — conditions are selectable nodes, never text: safe, autocompleting, validated.
**Behaviors** — combinable predicates, negative supported: `flag_set(id)`, `flag_unset(id)`, `has_item(id)`, `item_not_full(id)`, `boss_defeated(id)`, proximity/zone conditions; AND/OR/NOT. (`has_buff` excluded from the V1 grammar — 13/09/2026; an effect-oriented condition can join post-V1.)
**Parameters / bounds** — node registry (extensible), validation on load.
**Data / JSON** — condition trees in dialogue/doors/fog gates.
**Interactions** — `07` (doors/gates), `05` (boss state), `08` (dialogue).
**Edge cases** — cyclic condition (a gate gating itself), orphan flag referenced → error.
**Sources** — idea.txt 1775-1855, 1860-1864.

## Effect grammar (verbs registry)

**Goal** — declarative reactions: what happens when a condition fires.
**Behaviors** — base V1 verbs: `set_flag`, `clear_flag`, `give_item`, `remove_item`, `unlock_shortcut`, `trigger_event` (see events), `apply_buff` (temporary buff/debuff effects, `17`), `open_shop` (registered, inert until shops land); **post-V1 extension verbs** `play_animation`, `set_weather` (weather content vaulted) are added later — the registry is a dict of verb→handler, versioned, so adding verbs keeps `format_version 1` worlds working (ADR-009).
**Data / JSON** — effect nodes (verb + args).
**Interactions** — dialogue choices, events, levers, traps.
**Edge cases** — unknown verb in old world file → tolerated/ignored (ADR-009), never crash.
**Sources** — idea.txt 1734, 1810-1820, 1869, 1978.

## Global events reacting to flags & triggers

**Goal** — the world reacts: an NPC appears, a zone opens, a miniboss spawns.
**Behaviors** — event = trigger (condition) + effect list (reusable verbs); examples: NPC appears/disappears, hostile zone activates, miniboss spawns, trap arms; events declared in world config.
**Data / JSON** — events list + condition/effect trees.
**Interactions** — `07` world objects (lever/trap), `05` miniboss spawn, NPC presence.
**Edge cases** — event that fires repeatedly (one-shot flag), event after quit/reload (persisted state).
**Sources** — idea.txt 1734, 1913.

## Dialogue graph (line / choice / conditional / exit)

**Goal** — the first-class conversation editor, easy for non-developers.
**Behaviors** — minimal node grammar: `line` (speaker, text), `choice` (options), `conditional` (branch on conditions), `exit`; `next`/`goto` links; choices with conditions (flag/item/boss-defeated); effects attachable to node entry/exit (set_flag, give_item...); full split dialogue/nodes JSON schema; NPC speech = **text only** (no voice, no lip-sync — resolved 13/09/2026): the `line` text carries the dialogue, the NPC plays a generic talk loop while a line is shown (face pose budget ~5-8 @ 12fps, unchanged — no visemes needed).
**Data / JSON** — dialogue resource + node graph, versioned.
**Interactions** — NPCs (`08`), face animation (`02`), key items (`04`), shop (`08`).
**Edge cases** — broken goto → validation error, orphan node, dialogue loop (goto back).
**Open questions** — none (speech resolved 13/09/2026: text-only lines, no voice, no lip-sync).
**Sources** — idea.txt 72, 470, 1730-1855, 1860-1864.

## Lore notes (inspectable descriptions)

**Goal** — Dark-Souls-style lore on objects and places, read on inspect.
**Behaviors** — lore text attached to items/locations; inspect action displays it (items in inventory, objects in world); optional image.
**Data / JSON** — `lore` on item/place data.
**Interactions** — `04` items, `07` objects.
**Edge cases** — localized text, missing lore (no-op inspect).
**Sources** — idea.txt 1732.

## NPCs (base character form + morphs)

**Goal** — NPCs reuse the player character platform.
**Behaviors** — "base form + a few morphs" = 5 variants free; dialogue graph link (which dialogue id it talks, flags for conditions); config packs shareable between players; same base for player, NPC, enemy (`02`).
**Data / JSON** — NPC = character config + dialogue id + condition.
**Interactions** — `02` character editor, dialogue (`08`), events (NPC appears).
**Edge cases** — NPC with missing config → fallback default.
**Sources** — idea.txt 919-925, 1730.

## Quest progress (flags-as-quests — no tracker)

**Goal** — (resolved 13/09/2026) no quest tracker in V1: progression is read through dialogue/events/lore; quest *state* is just **silent flags** (`set_flag`/`clear_flag`, the `08` verb grammar).
**Behaviors** — flags carry all objective state; nothing surfaces as a tracked objectives list (fully silent); NPC dialogue, world events and key-item lore communicate progress.
**Parameters / bounds** — none (no tracker UI in V1).
**Data / JSON** — flags only; no quest-line list.
**Interactions** — `08` flags (verb grammar), dialogue conditions, `11` (no quest screen).
**Edge cases** — the "samey worlds" risk is countered by dialogue + events + lore.
**Sources** — idea.txt 1739.

## Graph validation tool

**Goal** — broken narrative refs surface in-editor before export.
**Behaviors** — validate on load: broken gotos, orphan flags, close-typo warnings ("flag X — did you mean Y?"), unknown-condition/effect verbs, undeclared flags.
**Data / JSON** — read-only validation output.
**Interactions** — `09` editor UX, `14` import validation.
**Edge cases** — large graphs (validation cost), flag renamed mid-session.
**Sources** — idea.txt 1871, 1908, 1945.

## Dialogue effects inventory (full list)

**Goal** — the closed set of things a dialogue can *do*.
**Behaviors** — `give_item`, `remove_item` (checks `item_not_full`), `set_flag`, `unlock_shortcut`, `open_shop` (inert until shops), `trigger_event`, `apply_buff`; post-V1 extension verbs `play_animation`, `set_weather` (weather vaulted).
**Data / JSON** — effect verbs versioned in the registry.
**Sources** — idea.txt 1775-1845, 1869, 1978.

## Writing-as-product philosophy

**Goal** — (positioning) supporting world/story/lore/dialogue creation is the maker's actual promise.
**Behaviors** — the base ships an **example world** as a piratable template/manifesto demonstrating the grammar's range; risk of samey worlds is handled through dialogue+events+lore expressiveness.
**Interactions** — `14` example world, P5.
**Sources** — idea.txt 1715-1739.