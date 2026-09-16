# SoulMaker — Naming & structure conventions

Short, enforceable rules for files, nodes and scripts — the Godot official
style guide (https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html)
is the base; this file only pins what the project adds or sharpens.

## Files & folders

- **snake_case** for every file and folder: `*.gd`, `*.tscn`, `*.tres`,
  `*.json`, `*.glb/gltf`.
- Scene roots, node names and `class_name`s are **PascalCase**.
- Schemas are version-prefixed: `data/schema/*_v0.1.json` (`versioning.md`).
- Godot generates `.uid` files next to scripts/scenes — keep them committed
  (stable references, cheap).

## Folders (owners only, see `AGENTS.md`)

| Folder | Contains |
|---|---|
| `scenes/` | `.tscn`; `tests/` interactive test scenes, `spikes/` throwaway experiments |
| `src/` | GDScript by concept: `autoloads/`, `runtime/`, `editors/`, `ui/`, `dataio/`, `tools/` (headless validators + `tools/spikes/`) |
| `data/` | JSON content only (`schema/`, `catalog/`, `items/`, `characters/`, `enemies/`, `worlds/`, `localization/`) |
| `assets/` | 1st-party local sources, gitignored (packed at P10) |
| `concepts_and_docs/` | design docs (English) |
| `reference/` | never imported by the game |

## GDScript naming

- Files: snake_case, matching the main symbol's role (`game_state.gd` →
  autoload `GameState`).
- `class_name`: PascalCase, specific (`AnimPrep`, not `Utils`).
- Methods, variables, signals: snake_case. Private helpers: `_` prefix
  (`_atomic_write`).
- Constants: UPPER_SNAKE (`SAVE_KEY`). `const` with `:=` inference for literals.
- Typed where useful (`: Dictionary`, `-> Error`); prefer `:=` only when the
  static type is meaningful.
- Signals: past-tense verb phrase, e.g. `hit_detected`.
- Export sparingly; every export needs a short `##` doc comment.

## Scenes (shared-language contract, `AGENTS.md`)

- A scene declares its **visible scaffold** (roots, attach points, exported
  vars); a script resolves data-driven parts — it must not *hide* structure.
- Scene file snake_case; the root node is PascalCase and named for the scene.
- Scripts attach to nodes; one script = one concern. Big builders belong in
  `src/` components (e.g. retargeting → `AnimPrep`), not inline in scenes.
- Test scenes always carry a state `Label` + matching prints + optional debug
  markers (shared-artifacts contract).

## Autoloads

- Files in `src/autoloads/`, singleton name PascalCase in `project.godot`
  (`GameState="*res://src/autoloads/game_state.gd"`).
- One concern per autoload; state flows through `GameState`, handling stays
  in the runtime folder.
- Validation note: autoload identifiers are NOT resolvable in
  `--headless --script` standalone compile — validate such scenes by running
  them headless (`.tscn` as main), see `godot47_api_notes.md`.

## Data (JSON)

- snake_case keys, canonical ids (`run`, `weapon`), world-level display
  overrides only at display time (ADR-011).
- Unknown fields tolerated by loaders (ADR-009); never silently dropped by save.