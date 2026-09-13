# 07 — World objects & interactables

> What lives *in* the maps: windows of content, gates, traps. Many are **flags-driven** via the narrative engine (`08`). Neutral spec — status lives in `features.md`.

## World object — doors

**Goal** — the simplest gate: opened by interaction, condition or flag.
**Behaviors** — persistent state is a flag (`doors_locked` flip); open/close tied to conditions or lever events; state persisted per world (GameState).
**Parameters / bounds** — animation (open/close) via shared rig assets.
**Data / JSON** — object entry + condition binding.
**Interactions** — `08` events (door opens when flag set), levers (`07`).
**Edge cases** — door state vs player mid-swing.
**Sources** — idea.txt 1734, 2519.

## World object — lever

**Goal** — the classic causal object: flip one thing to affect another.
**Behaviors** — a lever's pull flips a flag → any condition can react (open a door, spawn a miniboss, unlock a shortcut); creator levers = level gimmicks, traps, locked shortcuts, fog gates.
**Parameters / bounds** — one flag per lever (dot irreducibility).
**Data / JSON** — `lever: {flag, on_effect}`.
**Interactions** — `08` conditions/effects, doors, fog gates, elevators.
**Sources** — idea.txt 138, 530, 1734.

## World object — chest / corpse / pickup

**Goal** — loot instances creators place (ADR-012).
**Behaviors** — container with contents (currency / item); opened/looted state persisted in GameState (per world); pickup animation + item grant.
**Data / JSON** — contents + opened flag.
**Interactions** — `04` inventory, GameState (`15`).
**Edge cases** — a chest whose key-item content was already taken; re-loot attempt (locked after open).
**Sources** — idea.txt 1734, 2519, roadmap P8.

## Fog gate (flags-gated blocking door)

**Goal** — the souls boss/key barrier: a wall of fog until the condition clears.
**Behaviors** — blocking fog that persists while its flag is unset (boss alive, key not used); dissipates when the condition is met; world object placed in the map editor like any asset.
**Parameters / bounds** — one linked condition (boss_defeated / key item / flag) per fog gate.
**Data / JSON** — fog gate entry + condition (reuses `08` condition grammar).
**Interactions** — `08` flags, `05` boss state; shortcuts (unlock_shortcut effect).
**Edge cases** — player inside the gate volume when the condition flips; gate straddling a socket.
**Sources** — idea.txt 138, 530; decision 12/09 (P5/P7).

## Shortcut — unlock_shortcut

**Goal** — the souls "open a shortcut back to the bonfire" beat that closes graph cycles.
**Behaviors** — an unlockable gate/elevator path that, once opened (via dialogue effect `unlock_shortcut`, lever, flag), stays open and links back; creates a loop in the world graph.
**Data / JSON** — shortcut config (opened flag).
**Interactions** — world graph cycles (`06`), levers/doors, dialogue `08`.
**Edge cases** — shortcut reopened after reload (persisted), shortcut leading nowhere.
**Sources** — idea.txt 1819, 2525.

## Ladders (climbable level objects)

**Goal** — vertical shortcuts and levels the player *climbs*, not teleports.
**Behaviors** — a placed ladder world object aligned to geometry; the player interacts (prompt) → **climb locomotion** (`17`) slides on the rail (up/down), exits at top/bottom offsets; no attacks while climbing in V1.
**Parameters / bounds** — length/alignment/top-exit/bottom-exit from the object config; bounded per catalog template.
**Data / JSON** — ladder object `{length, alignment, top_exit, bottom_exit, collider}`.
**Interactions** — climb locomotion (`17`), vertical graph loops (`06`), bone/feet snapping (`02`).
**Edge cases** — climbing into a collider (object mis-placed → validator hint), ladder crossing a socket (allowed — geometry decides), exit clipped (offset clamp).
**Sources** — ADR-018, features.md §7, `17_combat_depth`.

## Illusory walls (secrets via flags)

**Goal** — the souls secret: a wall that *is not there* once you know — authored as data.
**Behaviors** — a world object that renders/physics as solid until a **discovery trigger** (roll through, attack, or interact — bounded verb whitelist via the `08` event grammar) toggles it hidden/open; the revealed state persists per world (GameState, same as doors/levers); optional linkage to a flag (part of a secret chain — reveal also sets `flag`).
**Parameters / bounds** — trigger verbs whitelist (roll/attack/interact); persistent `revealed` flag; optional bound `on_reveal_flag`.
**Data / JSON** — illusory object `{hidden_until, verbs, revealed_flag?, on_reveal_flag?}`.
**Interactions** — flags/events (`08`), fog gates (a foggate variant IS the "boss wall"), persisted world state (below).
**Edge cases** — player crossing mid-reveal, reveal while an enemy walks through it (enemies ignore illusory walls — only the player collides until revealed), repeated roll (idempotent).
**Sources** — ADR-018, features.md §7, idea.txt (secrets implied by "gimmicks/traps").

## Elevators / moving platforms (vault)

**Goal** — (post-V1) vertical shortcuts on triggers.
**Behaviors** — platform movement along a path; triggers/levers activate; pairs with fog-transition loops and shortcut cycles.
**Parameters / bounds** — path + speed + trigger binding.
**Data / JSON** — elevator/path config.
**Interactions** — `06` graph cycles, `15` physics.
**Edge cases** — player riding during zone stream swap.
**Sources** — idea.txt 2525.

## Traps (enemy-driven or event-driven)

**Goal** — hazard variety through the grammar: spikes, fire vents, timed blades.
**Behaviors** — trap behavior authored via event patterns (flag-triggered activation, damage-on-touch, cooldown) using the same condition/action registry as the narrative engine.
**Parameters / bounds** — damage quantities bounded, patterns registered.
**Data / JSON** — trap config (pattern + timing).
**Interactions** — `08` events (trap triggers on flag after lever).
**Open questions** — trap pattern list (spike burst, fire vent, swinging blade).
**Sources** — idea.txt 138, 1734.

## Level gimmicks

**Goal** — the creativity dial: creators bend the world's rules with placed objects.
**Behaviors** — "gimmick" = any scripted-but-data behavior composed from the event grammar (drop a bridge, raise waterline, reverse gravity optionally); nothing new shipped — grammar composes.
**Parameters / bounds** — only registered effect verbs.
**Data / JSON** — gimmick objects = placements + event bindings.
**Interactions** — `08` full condition/effect grammar.
**Sources** — idea.txt 138, 530.

## One-shot obstacles & interactable furniture

**Goal** — flavor props with interaction: doors you push, urn you smash.
**Behaviors** — catalog interactive props with one interaction verb (interact/attack only — no arbitrary verbs); visual feedback via shared rig.
**Parameters / bounds** — interaction verbs whitelist.
**Data / JSON** — prop config + verb.
**Sources** — idea.txt (interactables implied by "gimmicks/traps/shortcuts").

## Persisted world state (objects)

**Goal** — what you touched stays touched.
**Behaviors** — per-world persistent state: chests open, levers pulled, doors opened, shortcuts unlocked, boss defeated, miniboss spawned — all serialize into run `GameState` (P6/P7).
**Data / JSON** — per-world state map (id + state).
**Interactions** — `15` GameState, `08` flags/conditions read this state.
**Sources** — idea.txt 2438, 2519.