# JSON versioning & schema discipline (P0, ADR-009)

The `data/` schemas and the files that validate against them share one versioning policy. Every serialized file carries a `format_version` field; the schemas in this folder are the only validators.

## Rules

1. **`format_version` on every file.** A file without it is rejected at import — no guessing.
   Current versions: catalog manifest `0.1`, character config `0.1`, prefab `0.1`, world `0.1`.

2. **Tolerance to unknown fields (ADR-009).** Import **never** fails on an extra unknown field: readers ignore what they don't know. The schema files keep `additionalProperties = true` at leaf level; only the required fields are strict. This is what makes old files load in a new build.

3. **Never silent deletion.** A reader may not silently drop a field's *effect*. If a new build stops supporting a feature, the player gets a clear message ("created with version X — some new features missing"), never silent degradation.

4. **Strict validation on required + bounds.** `format_version`, required ids, enum values, bounded ranges are validated at import for every file treated as untrusted (world files, character configs, prefabs, dialogue resources, catalog manifest).

5. **Missing asset → fallback, not error (character config).** A referenced catalog id that no longer resolves loads the config with a default/neutral visual and logs a warning. World files are stricter: a missing prefab is a hard error (the map is broken).

6. **Format debt is the debt that kills (roadmap P0).** A schema added later forces a `format_version` bump: bumping must be rare, documented (this file), and conservative — forward-compatible by rule 2.

7. **Data is untrusted.** All imported JSON (drag & drop, world via Play, prefab/character via Create) passes the same validation. Errors carry precise file/line diagnostics (features/14, features/09).

## Where the schemas live

- `data/catalog/schema_v0.1.json` — catalog manifest (ADR-010/017, features/10).
- `data/schema/character_v0.1.json` — shared player/NPC/enemy config (features/02, features/09).
- `data/schema/prefab_v0.1.json` — prefab groups (features/06).
- `data/schema/world_v0.1.json` — composed world file (features/06, features/14).
- Dialogue resources (features/08) will get their schema at P5, under the same rules.