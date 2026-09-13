# SoulMaker

## Project

- Engine: **Godot 4.7.2** (stable)
- Local executable: `~/App/Godot/Godot_v4.7.2-stable_linux.x86_64`
- Renderer: Forward+ (only — no Compatibility fallback, see `concepts_and_docs/decisions.md` ADR-002)
- 3D physics: Jolt Physics
- Project still in its initial state (no scenes or scripts yet).

## Languages

- Game content and code (identifiers, comments, display strings): **English**
- Design docs (`concepts_and_docs/`): **English**
- Live discussions (this opencode session): **French** — matches the current team (single dev); this may change if the team grows.

## Documentation

- Official 4.7 docs: https://docs.godotengine.org/en/4.7/
- Stable docs (more recent): https://docs.godotengine.org/en/stable/
- Language: GDScript (follow engine conventions).
- **`concepts_and_docs/features.md` is the master feature list** (completeness net): a new feature lands there first (with a status), then an ADR/roadmap entry may implement it.
- **V1 = the public launch build**; post-V1 additions live in the vault. The V1 ships a **1st-party starter catalog** (CC0 + re-targeted animations, ADR-017) — the community pipeline is augmentative post-V1, never a V1 dependency.

## Folder structure

- `concepts_and_docs/` — design docs (English); `features.md` is the master list.
- `data/` — all game content as JSON (data-driven):
  - `schema/` world/character/prefab schemas (versioned), `catalog/` starter manifest + its schema, `items/` item instances, `characters/` base humanoid + morphs, `enemies/` definitions, `worlds/` world compositions, `localization/` `en` key table (later).
- `src/` — GDScript organized by concept: `autoloads/`, `runtime/` (combat, bonfire, camera, streaming), `editors/`, `ui/`, `dataio/` (JSON load/validate), `tools/` (headless: `import_check.gd`, `build_pck`, data validation).
- `scenes/` — `.tscn` (main, prefabs, UI screens, humanoid template).
- `creator_docs/` — short creator-facing docs (decision I).
- `assets/` — 1st-party local sources (CC0 + re-targeted), **gitignored** (ADR-017): packed into the PCK at P10; never versioned.
- `catalog/cache/` — community Drive download cache, gitignored (ADR-010).
- `addons/` — editor-only personal tools (`godotty/`, gitignored).
- Run saves never live in the repo: `user://` (GameState serialized).

## Useful commands

- Run the project live from the terminal:
  `~/App/Godot/Godot_v4.7.2-stable_linux.x86_64 --path .`
- Run a given script without launching the game:
  `~/App/Godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script <path>`

## Notes

- Check the docs version before using a feature (use 4.7 docs over stable when they differ).
- Do not add files inside `.godot/` (editor cache).
- **godotty** (terminal inside the editor, to run opencode) is an editor-only personal tool: it lives in `addons/godotty/`, is gitignored, and never appears in the game or the build (its `*.editor.*` GDExtension tags only load in the editor binary). Install manually; a fresh clone does not have it.