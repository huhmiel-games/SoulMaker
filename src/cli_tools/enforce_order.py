#!/usr/bin/env python3
"""Enforce garment-garment order AFTER conforming (route A, 30/09).

Per-part conforming is blind to other parts: an extracted waistband can
outgrow the shirt hem, a sleeve cap can pierce the shoulder. This tool pulls
the INNER part back under the OUTER part in an explicit y-band, restoring the
authored order (shirt OVER pants, shoulder OVER sleeve cap).

For each inner vert in band: nearest outer vert o (vectorized chunks); if the
inner vert sits at/outside the outer surface (signed distance along the outer
normal > -gap) and within 50mm, pull it to (o - n*gap). Pulls that would bury
the vert in skin (< half margin) or inside the nude volume are reverted
(skin wins over order; leftovers reported).

Reads/writes the FITTED .glb files (they only exist post-bake); vendor files
untouched. POSITION bytes rewritten in place; accessor min/max updated; image
URIs preserved.

Usage:
  enforce_order.py --outer <Outer_Fitted.glb> --inner <Inner_Fitted.glb>
      --nude <Superhero_gltf> --band Y0,Y1 [--gap G] [--margin M] [--dry-run]
  enforce_order.py --manifest src/cli_tools/conform_manifest.json --root .
      [--only <substring>]
Manifest section: "order": [{name, outer, inner (part entry names),
nude, band, gap}].
"""
import argparse
import json
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from conform_garments import (load_gltf, collect_positions, collect_nude,
                              collect_tris, ray_parity)

EPS = 1e-9


def nearest_outer(I, O, chunk=500):
    """(idx, dist) nearest outer vert per inner vert, vectorized chunks."""
    idx = np.empty(len(I), dtype=np.int64)
    dist = np.empty(len(I))
    for s in range(0, len(I), chunk):
        G = I[s:s + chunk]
        D = ((G[:, None, :] - O[None, :, :]) ** 2).sum(axis=-1)
        j = D.argmin(axis=1)
        idx[s:s + chunk] = j
        dist[s:s + chunk] = np.sqrt(D[np.arange(len(G)), j])
    return idx, dist


def nearest_nude(P, N, chunk=500):
    idx = np.empty(len(P), dtype=np.int64)
    dist = np.empty(len(P))
    for s in range(0, len(P), chunk):
        G = P[s:s + chunk]
        D = ((G[:, None, :] - N[None, :, :]) ** 2).sum(axis=-1)
        j = D.argmin(axis=1)
        idx[s:s + chunk] = j
        dist[s:s + chunk] = np.sqrt(D[np.arange(len(G)), j])
    return idx, dist


def order_one(ojs, obuf, ijs, ibuf, owners, nude_N, TRIS,
              y0, y1, gap, margin, skip):
    I, owners = collect_positions(ijs, ibuf, skip)
    in_band = (I[:, 1] >= y0) & (I[:, 1] <= y1)
    Ic = I[in_band]
    print(f"inner={len(I)} in_band={in_band.sum()}")
    if not in_band.any():
        return None
    O, On = collect_nude(ojs, obuf)
    nn = np.linalg.norm(On, axis=1)
    has_n = nn > 0.5
    if not has_n.any():
        sys.exit("abort: outer part has no NORMALs")
    j, d = nearest_outer(Ic, O)
    Oj, Nj = O[j], On[j]
    diff = Ic - Oj
    s = (diff * Nj).sum(axis=1)
    # cone test: enforce only crossings ALONG the outer normal. Past the
    # outer boundary edge (sleeve continuing beyond the shoulder cap) the
    # nearest outer vert is lateral (diff ⊥ normal) — legit, skip.
    cos = (diff * Nj).sum(axis=1) / np.maximum(d, 1e-9)
    viol = (s > -gap) & (d < 0.05) & (cos > 0.5)
    print(f"order violations: {int(viol.sum())}/{len(Ic)}")
    deltas = np.zeros_like(Ic)
    if viol.any():
        T = Oj[viol] - Nj[viol] * gap
        deltas[viol] = T - Ic[viol]
        # skin floor: never bury in flesh, never closer than half margin
        P = Ic + deltas
        ni, nd = nearest_nude(P, nude_N)
        bur = ray_parity(P, TRIS)
        bad = bur | (nd < margin * 0.5)
        nbad = int((bad & viol).sum())
        deltas[viol & bad] = 0.0
        if nbad:
            print(f"skin-blocked (kept overlap): {nbad}")
    moved = int((np.linalg.norm(deltas, axis=1) > 1e-6).sum())
    mx = float(np.linalg.norm(deltas, axis=1).max()) if moved else 0.0
    print(f"pulled={moved} max_pull={mx * 1000:.1f}mm")
    return deltas, in_band, owners


def write_back(ijs, ibuf, owners, in_band, deltas, path):
    # scatter band-local deltas to the full vert list
    n_all = len(in_band)
    full = np.zeros((n_all, 3))
    full[in_band] = deltas
    acc_blocks = []
    s = 0
    for ai, off, n in owners:
        acc_blocks.append((ai, s, n))
        s += n
    buf = bytearray(ibuf[0])
    for ai, off, n in owners:
        blk = next(b for b in acc_blocks if b[0] == ai)
        seg = full[blk[1]:blk[1] + n]
        orig = np.frombuffer(ibuf[0], dtype=np.float32, count=n * 3,
                             offset=off).reshape(n, 3).astype(np.float64)
        new = (orig + seg).astype(np.float32)
        struct.pack_into(f"<{n * 3}f", buf, off, *new.ravel())
        ijs["accessors"][ai]["min"] = [float(v) for v in new.min(axis=0)]
        ijs["accessors"][ai]["max"] = [float(v) for v in new.max(axis=0)]
    ijs["buffers"][0]["byteLength"] = len(buf)
    ijs["buffers"][0].pop("uri", None)
    js_bytes = json.dumps(ijs, separators=(",", ":")).encode("utf-8")
    while len(js_bytes) % 4:
        js_bytes += b" "
    glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js_bytes) + 8 + len(buf))
    glb += struct.pack("<II", len(js_bytes), 0x4E4F534A) + js_bytes
    glb += struct.pack("<II", len(buf), 0x004E4942) + bytes(buf)
    with open(path, "wb") as f:
        f.write(glb)
    print(f"wrote {path} ({len(glb)} bytes)")


def run_pair(outer, inner, nude, band, gap, margin, skip, dry_run):
    ojs, obuf = load_gltf(outer)
    ijs, ibuf = load_gltf(inner)
    if len(ibuf) != 1:
        sys.exit(f"abort: inner has {len(ibuf)} buffers (expected 1)")
    njs, nbuf = load_gltf(nude)
    nude_N, _ = collect_nude(njs, nbuf)
    TRIS = collect_tris(njs, nbuf)
    y0, y1 = (float(v) for v in band.split(","))
    print(f"=== order {os.path.basename(outer)} OVER {os.path.basename(inner)} "
          f"[{y0},{y1}] ===")
    I_check, owners = collect_positions(ijs, ibuf, skip)
    res = order_one(ojs, obuf, ijs, ibuf, owners, nude_N,
                    TRIS, y0, y1, gap, margin, skip)
    if res is None:
        return
    deltas, in_band, owners = res
    if dry_run:
        return
    write_back(ijs, ibuf, owners, in_band, deltas, inner)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outer", default=None)
    ap.add_argument("--inner", default=None)
    ap.add_argument("--nude", default=None)
    ap.add_argument("--band", default=None)
    ap.add_argument("--gap", type=float, default=0.003)
    ap.add_argument("--margin", type=float, default=0.008)
    ap.add_argument("--skip-material-substr", default="Regular")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--manifest", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--root", default=".")
    a = ap.parse_args()
    skip = [s for s in a.skip_material_substr.split(",") if s]
    if a.manifest:
        with open(os.path.join(a.root, a.manifest)) as f:
            m = json.load(f)
        outdir = os.path.join(a.root, m.get("outdir", ""))
        by_name = {e["name"]: e for e in m["parts"]}
        for e in m.get("order", []):
            if a.only and a.only not in e.get("name", ""):
                continue
            o = by_name[e["outer"]]
            inn = by_name[e["inner"]]
            of = os.path.join(outdir, o["name"] + "_Fitted.glb")
            inf = os.path.join(outdir, inn["name"] + "_Fitted.glb")
            if not os.path.exists(of) or not os.path.exists(inf):
                print(f"SKIP {e['name']}: bake the parts first")
                continue
            run_pair(of, inf, os.path.join(a.root, e["nude"]), e["band"],
                     float(e.get("gap", a.gap)), a.margin, skip, a.dry_run)
    else:
        if not (a.outer and a.inner and a.nude and a.band):
            sys.exit("need --outer --inner --nude --band (or --manifest)")
        run_pair(a.outer, a.inner, a.nude, a.band, a.gap, a.margin, skip,
                 a.dry_run)


if __name__ == "__main__":
    main()
