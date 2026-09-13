# SoulMaker — Asset pipeline (maintainer guide)

> Working document for maintainers. Formalizes the workflow decided in `decisions.md` ADR-010 (community stream) + ADR-017 (1st-party starter catalog). The goal: the base curates the V1 content itself (CC0 packs + re-targeted animations), and artists can contribute additional 3D creations without ever touching git; maintainers validate, store binaries on a Drive, and record a manifest entry in git.

---

## Overview

Two asset streams feed the catalog. They share the same validation, the same manifest, the same Credits — they differ in **who** brings the content and **when** it matters.

### Stream A — 1st-party starter catalog (V1, ADR-017)
The base curates the launch content itself: **CC0 packs** (Quaternius et al.) + **animations re-targeted** onto the standard humanoid skeleton (Mixamo and other license-compatible sources, ADR-006). Validated with the exact same checklist (§2), recorded in the manifest (license + author), packed into the game PCK by the build script from **local sources** — no Drive, no Discord. This is the mandatory V1 deliverable (roadmap P10, packages; the example world rides at P11) and the build material of the example world.

### Stream B — community submissions (post-V1 augmentative, ADR-010)
Extra content added after launch: artists submit via Discord, maintainers validate + upload to Drive, the build fetches per id. **Never a V1 dependency** — a release only ever requires Stream A.

```
STREAM A (V1):  CC0 packs + Mixamo round-trip ──validate──▶ PCK (local source)
STREAM B (post-V1):  Artist ──Discord──▶ Maintainer ──validate──▶ Drive (approved/)
                       (validate + hash + manifest)                 │
                                                                  build script
                                                                     │ id + sha256 + cache
                                                                     ▼
                                                                 Game PCK
```

- Artists: submit `.glb` + textures via Discord. No git, no Drive access.
- Maintainers: validate (headless import, license, bounds, style), upload binaries, add a manifest entry.
- Build: fetches per id, verifies `sha256`, caches locally, packs into the game.

---

## 1. Artist submission (Discord)

**What the artist provides** :

- The 3D asset as **glTF**: `.glb` (self-contained, single binary) + **textures kept separate** (`.png`/`.jpg`), never embedded in the `.glb`. Reference format: `.glb` + separate textures. (`.gltf` + `.bin` accepted too — the maintainer normalizes.)
- A casual description (usage intent, animation if relevant). No metadata form, no git, no specific naming.

**Channel conventions** (to agree): submission thread per asset, status emojis (`⏳ pending`, `✅ approved`, `❌ rejected`).

---

## 2. Maintainer validation checklist

Run before uploading:

1. **Headless import check** — import the asset in the project with the engine:
   `~/App/Godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tools/import_check.gd`
   The import must succeed with no errors/warnings. Fail → reject with the log.
2. **License** — must be compatible with the base (CC0 preferred; attribution/paid sources allowed if documented): attribute in the manifest, feeds the Credits screen.
3. **Bounds** — triangle count, texture size, bounding box within catalog limits (see `data/catalog/schema_v0.1.json`). Reject if excessive.
4. **Style/palette** — coherence with the base shader + imposed palette (ADR-006/007). Subjective step, by eye.
5. **Skeleton/animation** — if it's a character: standard humanoid skeleton (ADR-006) so shared animations re-target. Reject if custom skeleton.
6. **Fit (armor shells)** — if it's an armor piece: minimum clearance vs the **max-morph** body at the resting pose (`02` fit rule; starter-catalog armor instead shares the base morph topology). Reject if it clips the max-morph body.

Pass → **3. Upload**. Fail → return to the artist with the precise reason.

---

## 3. Drive storage

Structure (see recap in `decisions.md` ADR-010):

```
AssetDrive/
  pending/    ← uploads as they arrive (before validation)
  approved/   ← validated assets, reference copies
```

Rules :
- One folder per asset id: `approved/<asset_id>/` containing the `.glb` + textures.
- Never overwrite an approved asset in place — a revision gets a new `asset_id` (or a `v2` suffix). History is not on the Drive; the manifest is the source of truth.

---

## 4. Manifest entry (git)

The catalog manifest is a JSON file in git (schema v0.1, defined in P0 — `data/catalog/schema_v0.1.json`). Example entry:

```json
{
  "id": "prop_torch_01",
  "name": "Torch",
  "category": "light",
  "license": "CC0",
  "author": "ArtistName",
  "bounds": {"triangles_max": 4000, "texture_size_max": 1024},
  "files": [
    {"path": "approved/prop_torch_01/prop_torch_01.glb", "sha256": "…"}
  ]
}
```

- The `sha256` is computed by the maintainer at upload time (the build re-verifies it).
- Unknown/extra fields must be tolerated at load (ADR-009).
- One commit per asset entry (or a small batch) — message style: `catalog: add prop_torch_01`.

---

## 5. Build script spec

`res://tools/build_catalog.gd` (or a shell script), run before export:

1. Read the manifest.
2. For each entry: resolve id → Drive location, **download to a local cache** (`catalog/cache/`, gitignored) if not present or if `sha256` mismatches.
3. **Verify `sha256`** against the manifest.
4. Reference the cached files into the build (packed into the PCK).
5. Exit non-zero on any missing file, hash mismatch, or unlicensed entry.

Properties guaranteed:
- Deterministic builds: id + hash + cache → same result, offline after first fetch.
- Players never query the Drive — assets ship with game updates.
- Missing/unlicensed entry ⇒ build fails loudly, never silently.

---

## Open points (to settle when the pipeline is built, P10/P12)

- Drive access protocol (public shared folder via id vs API with token) — decided at P12 implementation time (Stream B only).
- Whether the first 5-6 test assets of P1 live in the repo — **yes**, resolved: they are the seed of the 1st-party starter catalog (ADR-017); Stream A assembles from local CC0 packs from P1 onward.
- ~~Exact schema of the manifest~~ — resolved: `data/catalog/schema_v0.1.json` (P0).
- Moderation rules for the submission channel (Discord as the intake, not a store).