# SoulMaker

## Project

- Engine: **Godot 4.7.2** (stable)
- Local executable: `~/App/Godot/Godot_v4.7.2-stable_linux.x86_64`
- Renderer: Forward+ (only — no Compatibility fallback, see `concepts_and_docs/decisions.md` ADR-002)
- 3D physics: Jolt Physics
- P0 state (tracked in `WORKLOG.md`): spikes done/redirected, schemas v0.1 + `decisions.md` in place, autoload `GameState` + test scenes live in `scenes/tests/`; remaining P0 = none (GameState + conventions delivered).

## Languages

- Game content and code (identifiers, comments, display strings): **English**
- Design docs (`concepts_and_docs/`): **English**
- Live discussions (this opencode session): **French** — matches the current team (single dev); this may change if the team grows.

## Documentation

- Official 4.7 docs: https://docs.godotengine.org/en/4.7/
- Stable docs (more recent): https://docs.godotengine.org/en/stable/
- GDScript (follow engine conventions).
- **`concepts_and_docs/naming_conventions.md`** — file/node/script conventions (P0 deliverable); AGENTS.md rules override it on conflict.
- **Local 4.7.2 class-reference cache**: `reference/godot47_docs/` (gitignored, added on demand) — answer class-API questions from it (Read/Grep) before webfetch; see `concepts_and_docs/godot47_api_notes.md` for the regeneration command and the 4.7 API deltas.
- **`concepts_and_docs/features.md` is the master feature list** (completeness net): a new feature lands there first (with a status), then an ADR/roadmap entry may implement it.
- **V1 = the public launch build**; post-V1 additions live in the vault. The V1 ships a **1st-party starter catalog** (CC0 + re-targeted animations, ADR-017) — the community pipeline is augmentative post-V1, never a V1 dependency.

## Input

- **Device parity (standing rule, editors + game)**: keyboard/mouse and gamepad are the same logical device. No code path may branch on which device drives it — every action resolves through a named `InputManager` action (arrows/D-pad share actions, A/E share actions, …); no raw `Input.*` polling and no device-specific paths in `src/`. The gamepad defines the capabilities (source of truth): the keyboard mirrors them — extra mirrors of an existing capability are allowed (Q, Shift+LMB), new capabilities are not. R1-pad chords are editor-only; Shift-key chords exist in every profile. The keyboard sets are **frozen** (editor table + game table; features/11 wins over DS3 PC). Enforced headless by `src/cli_tools/input_audit.gd` — run it after any input change. Consequences: no catalog drag & drop (placement is arrows/D-pad + A/E), no OS file-drop import (file-picker only). Per-context device tables live in `concepts_and_docs/editor_input_mapping.md`.

## Folder structure

- `concepts_and_docs/` — design docs (English); `features.md` is the master list.
- `data/` — all game content as JSON (data-driven):
  - `schema/` world/character/prefab schemas (versioned), `catalog/` starter manifest + its schema, `items/` item instances, `characters/` base humanoid + morphs, `enemies/` definitions, `worlds/` world compositions, `localization/` `en` key table (later).
- `src/` — GDScript organized by concept: `autoloads/`, `runtime/` (combat, bonfire, camera, streaming), `ingame_editors/` (maker in-game), `ui/`, `dataio/` (JSON load/validate), `cli_tools/` (headless: `import_check.gd`, `build_pck`, data validation), `editor_tools/` (`@tool` Godot-editor helpers, never in game).
- `scenes/` — `.tscn` (main, prefabs, UI screens, humanoid template).
- `creator_docs/` — short creator-facing docs (decision I).
- `reference/` — read-only reference snippets salvaged from the sibling project `rpg-base` (toon shaders, state-machine pattern) plus the gitignored `godot47_docs/` class-ref cache; never imported by the game, see `reference/README.md`.
- `assets/` — 1st-party local sources (CC0 + re-targeted), **gitignored** (ADR-017): packed into the PCK at P10; never versioned.
- `catalog/cache/` — community Drive download cache, gitignored (ADR-010).
- `addons/` — editor-only personal tools (`godotty/`, gitignored).
- Run saves never live in the repo: `user://` (GameState serialized).

## Useful commands

- Run the project live from the terminal:
  `~/App/Godot/Godot_v4.7.2-stable_linux.x86_64 --path .`
- Run a given script without launching the game:
  `~/App/Godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script <path>`

## Workflow: division of labor

Single-dev team; the human runs the visual/interactive parts. Cost of full
headless validation is high, so:

- **AI (writing)**: verify every API from `reference/godot47_docs/` before
  writing; self-check parse errors only with
  `~/App/Godot/Godot_v4.7.2-stable_linux.x86_64 --headless --check-only --script <file>`
  (fast, no game launch). Headless auto-runs stay limited to *deterministic*
  validations (JSON/schema, data pipeline, track coverage) where "feel" does
  not exist. Scripts referencing an autoload singleton cannot be compile-checked
  that way (autoloads are unknown in standalone `--script`); validate them by a
  headless run of their scene: `... --headless --path . <scene>.tscn`.
- **Human (testing)**: when code is ready, AI provides a short test recipe —
  exact scene/command, actions (keys/settings), expected result, and what to
  report back (logs + visual impression). Human launches, AI iterates.
- **Commits only on explicit human order after the test** (standing rule,
  2026-09-20): « ok ça fonctionne » is a test report, not a commit order.
  The AI stages nothing and commits nothing until the human explicitly says
  so (`ok commit`, `tu peux commit`, …) — no anticipatory end-of-build commits.
- **Never delete a file without explicit human approval** (standing rule,
  2026-10-09): no `rm`, no overwriting-by-deletion, no "cleanup" of orphans
  (assets, probes, imports…) on the AI's own initiative — list candidates and
  wait for the order. A name-based orphan is not proof: a renamed `.gltf` keeps
  its old buffer URI, so only a content check (references) decides.
- No pose-diff "eyeball" proofs by the AI: visual confirmation is the human's
  job (faster and better). If a specific inspector/frame inspection is needed,
  the AI may request it explicitly.
- Important changes land in AGENTS.md only when they affect future sessions.
- Scene structure rules and the debug-overlay contract live in **Shared
  artifacts & visual bridge** below.

## Shared artifacts & visual bridge

The AI and the human have complementary senses: the AI cannot see the editor
or the running game, and the human cannot read code at AI speed. Two artifacts
bridge the gap; a third expected bridge was tested and does NOT work (2026-09-15),
see below.

1. **Scene files (`.tscn` / `.tres`) are the shared language** — a text file
   for the AI, a rendered graph for the human in the editor. Rule: push the
   visible scaffold into the `.tscn` (roots, named attach points, exported
   vars); a script resolves the data-driven parts, it does not hide the
   structure. A scene in which the human has zero visual anchor in the editor
   is a defect.
2. **Runtime debug overlay + logs are the primary measurement bridge** — every
   test scene carries a state `Label` (current animation, blend amount, hit
   status, frame), matching `print()` lines, and optional visible markers
   (wireframes / colored gizmos). One run therefore produces both a visual
   signal (human) and a parseable signal (AI) from the same data.
3. **Screenshots are NOT readable by the AI (tested 2026-09-15)** — the model
   has no image input; reading a PNG returns "cannot read image". The human
   may capture screenshots for their own records, but visual feedback reaches
   the AI only through descriptions + instrumentation. Re-test this if the
   model or tier changes.

| Artifact | AI reads | AI writes | Human reads | Human decides |
|---|---|---|---|---|
| `.tscn` / `.tres` | ✓ (text) | ✓ | ✓ (editor) | visual |
| Scripts / validators | ✓ | ✓ | – | functional |
| Logs + prints + overlay | ✓ | ✓ | ✓ | – |
| JSON data / schemas | ✓ | ✓ | ✓ | content |
| Screenshots | ✗ (no image input) | – | ✓ | visual / feel |

## Notes

- **Session resume**: read `WORKLOG.md` (repo root) **first** — it holds the current objective, expected mode, next step and open items. Do not ask to re-explain or re-read the whole `roadmap.md`; update `WORKLOG.md` at each meaningful step (objective, mode, next), not only at session end.
- **Search scope**: stay inside this repo by default — never search the parent directory. `~/Projets_3D/rpg-base` is a sibling reference project (old code, pre-IK, Godot 4.5/4.6-era converted to 4.7): inspect it only on explicit request.
- Check the docs version before using a feature (use 4.7 docs over stable when they differ).
- **Class API**: answer from `reference/godot47_docs/` (Read/Grep), never webfetch. Add a class to the cache on demand (see `concepts_and_docs/godot47_api_notes.md`).
- Do not add files inside `.godot/` (editor cache).
- **No `#` comments in `.tscn` files** (2026-09-25: silently breaks parsing — the following instanced node loads empty, e.g. RigRoot without Skeleton3D + `skeleton not resolved`, character gone with no parse error). Keep notes in colocated `.gd` or docs.
- **Never append to a `Packed*Array` read out of a container** (2026-10-08: appending to a packed array retrieved from a Dictionary/Array mutates a CoW copy — size stays 0, no error. Proven headless: dict/array-packed stay 0, plain `Array` sticks. Use plain Arrays for accumulators/adjacency lists. This silently disabled sculpt diffusion + its metric + paint grow: all green, all hollow).
- **godotty** (terminal inside the editor, to run opencode) is an editor-only personal tool: it lives in `addons/godotty/`, is gitignored, and never appears in the game or the build (its `*.editor.*` GDExtension tags only load in the editor binary). Install manually; a fresh clone does not have it.
