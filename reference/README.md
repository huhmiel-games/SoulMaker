# Reference snippets

Copied read-only reference material salvaged from a sibling Godot project
(`~/Projets_3D/rpg-base`, currently converted to Godot 4.7, authored on
4.5/4.6-era). Used — in definition, **not** used as runtime code — to guide
SoulMaker's own implementations (P1 toon shader per ADR-019, P2 controller,
future state machine). No file here is imported by the game.

## Provenance and licensing

| File | Origin | Credit |
| --- | --- | --- |
| `shaders/toon_nekotoarts.gdshader` | `rpg-base/shaders/toon.gdshader` (renamed on copy) | BoTW toon shader by NekotoArts — header comment preserved |
| `shaders/flexible_toon.gdshader` | `rpg-base/addons/flexible_toon_shader/` | flexible toon addon shader — header preserved |
| `shaders/hatch_toon.gdshader` | `rpg-base/addons/flexible_toon_shader/` | hatch variant of the same addon — header preserved |
| `state_machine/state.gd` | `rpg-base/state_machine/state.gd` | rpg-base project code (own project) |

Original attribution comments inside the files were kept verbatim. License
terms of third-party shaders were **not** confirmed at copy time — re-check
before any reuse. These files are personally-owned project references, not a
source for assets shipped in the catalog.

## Godot version notes

- All three shaders use the Godot 3.x-era `void light()` processor with
  `DIFFUSE_LIGHT` / `SPECULAR_LIGHT` — these constructs **still exist and
  compile in Godot 4.7** (confirmed against the official 4.7 spatial shader
  reference), so they remain useful as-is.
- `toon_nekotoarts.gdshader` is the most relevant to SoulMaker: `render_mode
  diffuse_toon, specular_toon` + soft shadow step (`smoothstep` on `NdotL`)
  — this is exactly the "diffuse_toon + shadow ramps" target locked in
  ADR-019.

## Normalizations applied (state machine only)

- `class_name State` → `RefState`, `class_name StateMachine` →
  `RefStateMachine` (prevents global-class collisions with future SoulMaker
  code).
- Type annotations referencing classes that do not exist in SoulMaker
  (`Player`, `Movement`) were de-referenced to untyped. All logic is
  byte-for-byte identical to the source files.

## Godot 4.7.2 class reference cache (`godot47_docs/`)

- Regenerated from the local binary (`--doctool`), **gitignored**, added on
  demand per class. See `concepts_and_docs/godot47_api_notes.md` for the
  command, the convention, and the 4.7 API deltas it documents.