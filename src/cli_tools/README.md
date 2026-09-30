# cli_tools — dev pipeline (headless, never shipped)

## Garment-fit bake (route A): vendor parts -> fitted parts

Conforms each outfit part to the nude body (signed push + margin) and writes
`<Part>_Fitted.glb` into `assets/meshes/outfits/fitted/`. The game loads the
fitted variant when present, else the raw vendor part (see `_fitted_or_raw`
in `src/ingame_editors/character_editor.gd`).

### Prereqs (dev machine only, never at runtime)

- `python3` (3.12 used here)
- `numpy`: `pip3 install --break-system-packages numpy` (2.5.3 used here;
  the flag is required by this distro, see PEP 668)

### Bake (from the repo root)

```sh
# full rebuild, all 8 Peasant parts @ manifest margins (~30 min, Female Arms ~9)
python3 src/cli_tools/conform_garments.py --manifest src/cli_tools/conform_manifest.json --root .

# one part only (fast iteration)
python3 src/cli_tools/conform_garments.py --manifest src/cli_tools/conform_manifest.json --root . --only Arms

# dry run (full compute, no files written)
python3 src/cli_tools/conform_garments.py --manifest src/cli_tools/conform_manifest.json --root . --only Legs --dry-run

# single part, explicit params (no manifest)
python3 src/cli_tools/conform_garments.py --nude <Superhero_gltf> --part <part_gltf> \
  --window Y0,Y1,SIDE --axes AX,AZ,BX,BZ [--hug-window Y0,Y1,SIDE] [--margin M] [--outdir DIR]
  [--axes-limb XMIN,AX,AZ,BX,BZ] [--ride-radius R] [--interior-dot D] [--exclude-x X]
```

### Verify

1. Read the bake table: `buried BEFORE` (how much cloth sat inside the body),
   `buried AFTER` (leftovers = occluded folds, reported not fixed),
   `signed_min` (clearance, must be positive outside), `reverted:` (trap/spike
   verts sent back to vendor-raw instead of needles), `tear-risk`
   (coincident-vert spread, must be ~0 post-smooth — else the mesh tore).
2. Headless self-test (loads all 8 fitted + Male/Female swaps):
   `~/App/Godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . scenes/ingame_editors/character_editor.tscn -- --chartest`
   → `0 FAIL` + log lines `-> ..._Fitted.glb` + `PASS body albedo wired`
   (the albedo check fails loudly on white materials — stale-import regression).
3. Visual recipe: profile views per slot (seams shut?), shirt hem flare vs
   pants waistband (no clip?), sleeve backs from behind (skin showing?), boots.

### Second pass: garment order

Per-part conforming is blind across parts — run after every conform bake:

```sh
python3 src/cli_tools/enforce_order.py --manifest src/cli_tools/conform_manifest.json --root .  # ~3 min
```

Pulls inner parts back under outer parts per the manifest `order` pairs
(shirt OVER pants, shoulder OVER sleeve cap); skin-blocked pulls are kept as
overlap and reported. Same `--only` / `--dry-run` flags.

### Full sequence (fresh bake)

```sh
python3 src/cli_tools/conform_garments.py --manifest src/cli_tools/conform_manifest.json --root .  # ~30 min
# the bake rewrites texture URIs as outdir->source relpaths: delete any
# hand-copied PNGs inside fitted/ (stale duplicates), then:
python3 src/cli_tools/enforce_order.py --manifest src/cli_tools/conform_manifest.json --root .    # ~3 min
# Godot auto-reimports the new .glb on next scan (fresh .import); if materials
# ever show white at runtime while the import preview is textured, the .glb
# import cache is stale: delete fitted/*.glb.import and relaunch.
```

### Adjust

Edit `conform_manifest.json` (per-part `window` / `hug_window` / `axes` /
`axes_limb` / `margin`, `defaults` for `ride_radius` / `interior_dot` /
`smooth_iters`, `order` pairs with `band` / `gap`), rebake (`--only <Name>` for one
slot, then re-run the order tool — it reads the fitted files). The manifest +
scripts are the versioned source of truth — never rely on terminal history.

### License / distribution

The vendor pack (`.../Modular Parts/`, see its `License_Standard.txt`) forbids
redistribution: `fitted/` holds local-only rebuilds (geometry derived from
vendor meshes) and stays gitignored under `assets/` (ADR-017) — it is NEVER
committed. Fresh clone flow: drop the vendor pack in place, run the full bake.
