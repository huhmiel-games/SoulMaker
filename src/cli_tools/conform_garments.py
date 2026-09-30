#!/usr/bin/env python3
"""Conform a garment part to the nude body (route A, 30/09; signed push 30/09).

SIGNED containment: each garment vertex is tested inside/outside the nude
volume (raycast parity on the nude triangles).
- outside + closer than margin -> pushed out to (nearest skin + margin);
- INSIDE (buried) -> EXTRACTED along the skin normal at the nearest skin
  vert (radial limb-axis fallback) by (depth + margin), landing outside + margin.
Unsigned push was proven blind here: 28-39% of part verts are buried in the
bulky hero (pack authored slimmer), and unsigned push buries them deeper.

Restricted to an anatomical window (y-band + x-side rule) so inner-thigh
cloth never snaps to the opposite leg. Displacement field is Laplacian-
smoothed over the mesh topology, then a signed touch-up loop re-processes
leftovers (re-push outsiders, re-extract buried).

Writes `<base>_Fitted.glb` next to the vendor part (vendor files untouched);
the editor loads the fitted variant when present (see _fitted_or_raw).
POSITION bytes are rewritten in place (same layout); accessor min/max updated.
Normals are left as authored (shading error negligible vs the fit gain).

Assumes bind pose, single .bin buffer, tightly packed POSITION floats.

Usage (single part):
  conform_garments.py --nude <Superhero_gltf> --part <part_gltf>
      --window Y0,Y1,SIDE --axes AX,AZ,BX,BZ [--hug-window Y0,Y1,SIDE]
      [--margin M] [--max-push P] [--smooth-iters N]
      [--skip-material-substr Regular] [--outdir DIR] [--dry-run]

Usage (batch, the versioned path — see conform_manifest.json):
  conform_garments.py --manifest src/cli_tools/conform_manifest.json --root .

SIDE: sign = same x sign as garment vert (|x|<5mm: any), any = no x filter.
AXES: limb XZ centers, A for +X verts, B for -X verts (fallback radial +
anti-gap reference: extraction never points back toward the limb).
HUG-WINDOW: outsiders are hugged to margin only inside it (authored ease —
flared hems — preserved elsewhere); buried cloth is extracted everywhere.
"""
import argparse
import base64
import json
import os
import struct
import sys

import numpy as np

EPS = 1e-9


def load_gltf(path):
    with open(path, "rb") as f:
        head = f.read(12)
    if head[:4] == b"glTF":  # .glb container: JSON + BIN chunks
        with open(path, "rb") as f:
            data = f.read()
        off = 12
        js, buffers = None, []
        while off < len(data):
            ln, typ = struct.unpack("<II", data[off:off + 8])
            chunk = data[off + 8:off + 8 + ln]
            if typ == 0x4E4F534A:
                js = json.loads(chunk)
            elif typ == 0x004E4942:
                buffers.append(bytes(chunk))
            off += 8 + ln
        return js, buffers
    with open(path) as f:
        js = json.load(f)
    base = os.path.dirname(os.path.abspath(path))
    buffers = []
    for b in js.get("buffers", []):
        uri = b.get("uri", "")
        if uri.startswith("data:"):
            buffers.append(base64.b64decode(uri.split(",", 1)[1]))
        else:
            with open(os.path.join(base, uri), "rb") as f:
                buffers.append(f.read())
    return js, buffers


def node_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    m = np.eye(4)
    if "scale" in node:
        m[:3, :3] = m[:3, :3] * np.array(node["scale"], dtype=np.float64)
    if "rotation" in node:
        x, y, z, w = node["rotation"]
        m[:3, :3] = np.array([
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]) @ m[:3, :3]
    if "translation" in node:
        m[:3, 3] = np.array(node["translation"], dtype=np.float64)
    return m


def world_of(js, idx, cache):
    if idx in cache:
        return cache[idx]
    parent = None
    for i, n in enumerate(js.get("nodes", [])):
        if idx in n.get("children", []):
            parent = i
    local = node_matrix(js["nodes"][idx])
    w = local if parent is None else world_of(js, parent, cache) @ local
    cache[idx] = w
    return w


def mesh_node(js, mi):
    for i, n in enumerate(js.get("nodes", [])):
        if n.get("mesh") == mi:
            return i
    return None


def accessor_array(js, buffers, ai):
    acc = js["accessors"][ai]
    bv = js["bufferViews"][acc["bufferView"]]
    buf = buffers[bv.get("buffer", 0)]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    if acc["componentType"] != 5126 or acc["type"] != "VEC3":
        raise ValueError(f"accessor {ai}: expected float VEC3")
    stride = bv.get("byteStride", 12)
    n = acc["count"]
    if stride == 12:
        return np.frombuffer(buf, dtype=np.float32, count=n * 3, offset=off
                             ).reshape(n, 3).astype(np.float64), off
    arr = np.empty((n, 3))
    for i in range(n):
        arr[i] = struct.unpack_from("<3f", buf, off + i * stride)
    return arr, off


def index_array(js, buffers, prim):
    acc = js["accessors"][prim["indices"]]
    bv = js["bufferViews"][acc["bufferView"]]
    buf = buffers[bv.get("buffer", 0)]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    ct = acc["componentType"]
    dt = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32}[ct]
    return np.frombuffer(buf, dtype=dt, count=acc["count"], offset=off).astype(np.int64)


def mat_name(js, prim):
    mats = js.get("materials", [])
    if "material" in prim and prim["material"] < len(mats):
        return mats[prim["material"]].get("name", "")
    return ""


def collect_gnormals(js, buffers, skip_substrs):
    """Authored garment NORMALs world-space, SAME row order as
    collect_positions (same loop, same skip) so rows align 1:1."""
    cache = {}
    out = []
    has = False
    for mi, mesh in enumerate(js.get("meshes", [])):
        ni = mesh_node(js, mi)
        w = world_of(js, ni, cache) if ni is not None else np.eye(4)
        rot = w[:3, :3]
        for prim in mesh["primitives"]:
            if any(s in mat_name(js, prim) for s in skip_substrs):
                continue
            ai = prim["attributes"]["POSITION"]
            n = js["accessors"][ai]["count"]
            if "NORMAL" in prim["attributes"]:
                narr, _ = accessor_array(js, buffers,
                                         prim["attributes"]["NORMAL"])
                nn = narr @ rot.T
                nn /= np.linalg.norm(nn, axis=1, keepdims=True) + EPS
                out.append(nn)
                has = True
            else:
                out.append(np.zeros((n, 3)))
    if not out:
        raise ValueError("no conformable verts (all skipped?)")
    return np.vstack(out), has


def collect_positions(js, buffers, skip_substrs):
    """(verts, owners) world-space; owners[k] = (acc_idx, abs_offset) per vert."""
    cache = {}
    verts, owners = [], []
    for mi, mesh in enumerate(js.get("meshes", [])):
        ni = mesh_node(js, mi)
        w = world_of(js, ni, cache) if ni is not None else np.eye(4)
        for prim in mesh["primitives"]:
            if any(s in mat_name(js, prim) for s in skip_substrs):
                continue
            ai = prim["attributes"]["POSITION"]
            arr, off = accessor_array(js, buffers, ai)
            h = np.ones((len(arr), 4))
            h[:, :3] = arr
            verts.append((h @ w.T)[:, :3])
            owners.append((ai, off, len(arr)))
    if not verts:
        raise ValueError("no conformable verts (all skipped?)")
    return np.vstack(verts), owners


def collect_nude(js, buffers):
    """(verts, normals) world-space, all meshes (skin + underwear + eyes)."""
    cache = {}
    verts, norms = [], []
    for mi, mesh in enumerate(js.get("meshes", [])):
        ni = mesh_node(js, mi)
        w = world_of(js, ni, cache) if ni is not None else np.eye(4)
        rot = w[:3, :3]
        for prim in mesh["primitives"]:
            ai = prim["attributes"]["POSITION"]
            arr, _ = accessor_array(js, buffers, ai)
            h = np.ones((len(arr), 4))
            h[:, :3] = arr
            verts.append((h @ w.T)[:, :3])
            if "NORMAL" in prim["attributes"]:
                narr, _ = accessor_array(js, buffers, prim["attributes"]["NORMAL"])
                nn = (narr @ rot.T)
                nn /= np.linalg.norm(nn, axis=1, keepdims=True) + EPS
                norms.append(nn)
            else:
                norms.append(np.zeros_like(arr))
    return np.vstack(verts), np.vstack(norms)


def collect_tris(js, buffers):
    """All nude triangles world-space (for parity containment)."""
    cache = {}
    tris = []
    for mi, mesh in enumerate(js.get("meshes", [])):
        ni = mesh_node(js, mi)
        w = world_of(js, ni, cache) if ni is not None else np.eye(4)
        for prim in mesh["primitives"]:
            if "indices" not in prim:
                continue
            arr, _ = accessor_array(js, buffers, prim["attributes"]["POSITION"])
            h = np.ones((len(arr), 4))
            h[:, :3] = arr
            V = (h @ w.T)[:, :3]
            tris.append(V[index_array(js, buffers, prim).reshape(-1, 3)])
    return np.vstack(tris) if tris else np.empty((0, 3, 3))


def ray_parity(pts, tris, chunk=150):
    """Odd +X crossings => inside. Vectorized Moller-Trumbore per chunk."""
    inside = np.zeros(len(pts), dtype=bool)
    if len(pts) == 0 or len(tris) == 0:
        return inside
    d = np.array([1.0, 0.0, 0.0])
    e1 = tris[:, 1] - tris[:, 0]
    e2 = tris[:, 2] - tris[:, 0]
    p = np.cross(d, e2)
    det = np.einsum("ij,ij->i", e1, p)
    ok_tri = np.abs(det) > 1e-12
    inv = np.zeros_like(det)
    inv[ok_tri] = 1.0 / det[ok_tri]
    for s in range(0, len(pts), chunk):
        P = pts[s:s + chunk]
        T = P[:, None, :] - tris[None, :, 0]
        u = np.einsum("ktj,tj->kt", T, p) * inv[None, :]
        q = np.cross(T, e1[None, :, :])
        v = np.einsum("ktj,j->kt", q, d) * inv[None, :]
        t = np.einsum("tj,ktj->kt", e2, q) * inv[None, :]
        hit = ok_tri[None, :] & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-9)
        inside[s:s + chunk] = (hit.sum(axis=1) % 2) == 1
    return inside


def window_nude(V, y0, y1, side, gx_row, exclude_x=0.0):
    """Boolean mask (n_nude, k) of nude verts usable for k garment verts.
    exclude_x drops nude candidates with |x| < exclude_x (limb slots: keeps
    torso skin out of sleeve searches so armpit cloth stops ping-ponging
    between arm and torso volumes)."""
    band = (V[:, 1] >= y0) & (V[:, 1] <= y1)
    if exclude_x > 0.0:
        band = band & (np.abs(V[:, 0]) >= exclude_x)
    if side == "sign":
        s = V[:, 0:1] * gx_row  # (n, k)
        return band[:, None] & ((s >= 0) | (np.abs(V[:, 0:1]) < 0.005)
                                | (np.abs(gx_row) < 0.005))
    return np.repeat(band[:, None], gx_row.shape[1], axis=1)


def nearest_in_window(G, N, y0, y1, side, exclude_x=0.0, chunk=400):
    """Nearest nude vert per garment vert. Returns (idx, dist), -1 if none."""
    idx = np.full(len(G), -1)
    dist = np.full(len(G), np.inf)
    for s in range(0, len(G), chunk):
        g = G[s:s + chunk]
        m = window_nude(N, y0, y1, side, g[:, 0][None, :], exclude_x)
        for i in range(len(g)):
            col = m[:, i]
            if not col.any():
                continue
            d = np.linalg.norm(N[col] - g[i], axis=1)
            j = int(np.argmin(d))
            idx[s + i] = np.flatnonzero(col)[j]
            dist[s + i] = d[j]
    return idx, dist


def radial_dirs(pts, ax, az, bx, bz):
    """Outward XZ fallback from the limb axis (A: +X verts, B: -X verts)."""
    cen = np.where((pts[:, 0] >= 0)[:, None],
                   np.array([ax, az]), np.array([bx, bz]))
    off = pts[:, [0, 2]] - cen
    ln = np.linalg.norm(off, axis=1)
    ln = np.where(ln < 1e-6, 1.0, ln)
    d = np.zeros_like(pts)
    d[:, [0, 2]] = off / ln[:, None]
    return d


def extract_dirs(gv, nn, ax, az, bx, bz):
    """Anti-gap extraction direction: skin normal UNLESS it points back
    toward the limb (inner thigh / armpit normals face the gap: extracting
    along them evacuates the cloth wall into the void and opens a slit).
    Falls back to radial-from-limb-axis there (and when NORMALs are missing).
    """
    r = radial_dirs(gv, ax, az, bx, bz)
    use_n = (np.linalg.norm(nn, axis=1) > 0.5) & ((nn * r).sum(axis=1) > 0.0)
    d = r.copy()
    d[use_n] = nn[use_n]
    ln = np.linalg.norm(d, axis=1)
    ln = np.where(ln < 1e-6, 1.0, ln)
    return d / ln[:, None]


def extract_dirs_zoned(gv, nn, ax, az, bx, bz, lx):
    """Extraction directions with limb-zone override: verts with |x| >= XMIN
    belong to a limb tube (jacket sleeve stubs) and ALWAYS go radial around
    the limb (tube expansion); elsewhere the anti-gap skin normal applies."""
    if lx is not None:
        _lxmin, _lax, _laz, _lbx, _lbz = lx
        _lm = np.abs(gv[:, 0]) >= _lxmin
        dirs = np.empty_like(gv)
        if _lm.any():
            dirs[_lm] = radial_dirs(gv[_lm], _lax, _laz, _lbx, _lbz)
        if (~_lm).any():
            dirs[~_lm] = extract_dirs(gv[~_lm], nn[~_lm], ax, az, bx, bz)
        return dirs
    return extract_dirs(gv, nn, ax, az, bx, bz)


def clamp_len(v, mx):
    """Cap per-vert lengths at mx in place. Returns clamped count."""
    ln = np.linalg.norm(v, axis=1)
    over = ln > mx
    v[over] *= (mx / ln[over])[:, None]
    return int(over.sum())


def smooth_deltas(deltas, neighbors, iters, groups=None):
    """Laplacian smoothing. groups (optional): list of index arrays whose
    members share one position (authored UV/normal seams = duplicated verts).
    After EVERY iteration members are reset to the group mean — otherwise the
    topology-dependent averaging moves coincident verts apart and TEARS the
    mesh open along every seam (proven in Blender 30/09: cm-wide slits)."""
    for _ in range(iters):
        new = deltas.copy()
        for i, nb in enumerate(neighbors):
            if len(nb):
                new[i] = 0.5 * deltas[i] + 0.5 * deltas[nb].mean(axis=0)
        deltas = new
        if groups:
            for g in groups:
                if len(g) > 1:
                    deltas[g] = deltas[g].mean(axis=0)
    return deltas


def ride_along(deltas, pts, radius):
    """Spatial ride-along: a part file holds SEPARATE components (Blender
    separate-by-loose-parts 30/09: cloth, belt, buckle, cuff buttons share NO
    verts) — topological smoothing never couples them, so trim sinks when the
    cloth extracts. Blend each delta with the mean delta inside <radius>,
    same-x-sign only (never bridge the crotch gap), all components mixed.
    Returns (new_deltas, max_adjustment)."""
    n = len(pts)
    out = deltas.copy()
    maxadj = 0.0
    sx = np.sign(pts[:, 0])
    r2 = radius * radius
    for s in range(0, n, 500):
        G = pts[s:s + 500]
        D2 = ((G[:, None, :] - pts[None, :, :]) ** 2).sum(axis=-1)
        same = sx[s:s + 500, None] * sx[None, :] >= 0
        m = (D2 <= r2) & same
        cnt = m.sum(axis=1)
        avg = (m[:, :, None] * deltas[None, :, :]).sum(axis=1) / np.maximum(cnt, 1)[:, None]
        new = 0.5 * deltas[s:s + 500] + 0.5 * avg
        maxadj = max(maxadj, float(np.abs(new - deltas[s:s + 500]).max()))
        out[s:s + 500] = new
    return out, maxadj


def weld_groups(pts):
    """Position-identical vert index groups (exact float match: same source
    bytes). Singletons dropped."""
    table = {}
    for i, p in enumerate(pts):
        table.setdefault(p.tobytes(), []).append(i)
    return [np.array(v, dtype=np.int64) for v in table.values() if len(v) > 1]


def tear_report(deltas, groups, label):
    """Max delta spread inside weld groups: what the smoother WOULD have torn
    without weld-consistency. >0.5mm = the mesh was at risk."""
    mx = 0.0
    for g in groups:
        if len(g) > 1:
            mx = max(mx, float((deltas[g].max(axis=0) - deltas[g].min(axis=0)).max()))
    print(f"tear-risk {label}: max coincident spread={mx * 1000:.1f}mm")
    return mx


def main(a=None):
    if a is None:
        a = _parse_cli()
    _bake(a)


def _parse_cli():
    ap = argparse.ArgumentParser()
    ap.add_argument("--nude", required=False, default=None)
    ap.add_argument("--part", required=False, default=None)
    ap.add_argument("--window", required=False, default=None, help="Y0,Y1,SIDE")
    ap.add_argument("--hug-window", required=False, default=None,
                    help="Y0,Y1,SIDE hug zone (default: window). Outsiders are "
                    "hugged to margin only inside it (authored ease elsewhere "
                    "is preserved); buried cloth is extracted everywhere.")
    ap.add_argument("--axes", required=False, default=None,
                    help="AX,AZ,BX,BZ (fallback radial + anti-gap reference)")
    ap.add_argument("--axes-limb", required=False, default=None,
                    help="XMIN,LAX,LAZ,LBX,LBZ: verts with |x| >= XMIN belong "
                    "to a limb tube (e.g. jacket sleeve stubs around the arm) "
                    "and ALWAYS extract along the limb radial — skin normals "
                    "there eject sideways through the deltoid (needles, 30/09)")
    ap.add_argument("--exclude-x", type=float, default=0.0,
                    help="ignore nude candidates with |x| below this (limb "
                    "slots: keeps torso skin out of sleeve searches)")
    ap.add_argument("--margin", type=float, default=0.008)
    ap.add_argument("--max-push", type=float, default=0.06)
    ap.add_argument("--smooth-iters", type=int, default=3)
    ap.add_argument("--ride-radius", type=float, default=0.015,
                    help="spatial ride-along radius in m (trim layers follow "
                    "the cloth; same-x-sign only, never bridges gaps)")
    ap.add_argument("--interior-dot", type=float, default=-0.2,
                    help="freeze cloth whose authored normal faces the limb "
                    "below this dot (fold returns / thickness interiors, "
                    "never coverage); -2.0 disables")
    ap.add_argument("--skip-material-substr", default="Regular")
    ap.add_argument("--outdir", default="",
                    help="bake dir for _Fitted.glb (default: alongside part)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--manifest", default="",
                    help="batch JSON (repo-relative paths, see "
                    "conform_manifest.json) + --root")
    ap.add_argument("--only", default="",
                    help="with --manifest: bake only entries whose name "
                    "contains this substring")
    ap.add_argument("--root", default=".",
                    help="repo root the manifest paths resolve against")
    return ap.parse_args()


def _bake(a):
    if a.nude is None or a.part is None or a.window is None or a.axes is None:
        sys.exit("need --nude --part --window --axes (or --manifest)")
    y0, y1, side = a.window.split(",")
    y0, y1 = float(y0), float(y1)
    if a.hug_window:
        _h = a.hug_window.split(",")
        hy0, hy1 = float(_h[0]), float(_h[1])
    else:
        hy0, hy1 = y0, y1
    ax, az, bx, bz = (float(v) for v in a.axes.split(","))
    _al = getattr(a, "axes_limb", None)
    if _al:
        _av = [float(v) for v in _al.split(",")]
        _lxmin, _lax, _laz, _lbx, _lbz = _av
    else:
        _lxmin = None
    skip = [s for s in a.skip_material_substr.split(",") if s]
    print(f"=== {a.part} (margin={a.margin * 1000:.0f}mm) ===")

    njs, nbuf = load_gltf(a.nude)
    N, Nn = collect_nude(njs, nbuf)
    TRIS = collect_tris(njs, nbuf)
    gjs, gbuf = load_gltf(a.part)
    if len(gbuf) != 1:
        sys.exit(f"abort: part has {len(gbuf)} buffers (expected 1)")
    G, owners = collect_positions(gjs, gbuf, skip)
    # accessor-local -> global index blocks (shared by adjacency + rim)
    acc_blocks = []
    _s = 0
    for _ai, _off, _n in owners:
        acc_blocks.append((_ai, _s, _n))
        _s += _n
    # coincident-edge reading (by POSITION, not indices): an index-based
    # single-use edge is ambiguous — an unwelded panel SEAM is two single-use
    # edges at the same place (v6 froze them -> coverage holes mid-tube).
    # Pair edges by quantized endpoints, then read face normals:
    # - agreeing faces (dot > 0.2) = SEAM: normal path + positional weld
    #   (travel together, v4/v6 behavior that closed the tears);
    # - opposing faces (dot < -0.2) = FOLD (outer wall + inner return, e.g.
    #   the jacket sleeve stub): its buried verts are FROZEN raw below;
    # - lone edge (true boundary: waistband/hem loops) = coverage edge:
    #   normal path (extract if buried).
    _ec = {}
    _ef = {}
    for _mi, _mesh in enumerate(gjs.get("meshes", [])):
        for _prim in _mesh["primitives"]:
            _ai = _prim["attributes"]["POSITION"]
            _blk = next((b for b in acc_blocks if b[0] == _ai), None)
            if _blk is None or "indices" not in _prim:
                continue
            for _t in index_array(gjs, gbuf, _prim).reshape(-1, 3) + _blk[1]:
                _p = G[_t]
                _e1 = _p[1] - _p[0]
                _e2 = _p[2] - _p[0]
                _n = np.cross(_e1, _e2)
                _l = float(np.linalg.norm(_n))
                _n = _n / _l if _l > 1e-12 else np.zeros(3)
                for _a, _b in ((int(_t[0]), int(_t[1])), (int(_t[1]), int(_t[2])), (int(_t[2]), int(_t[0]))):
                    _k = (_a, _b) if _a < _b else (_b, _a)
                    _ec[_k] = _ec.get(_k, 0) + 1
                    _ef.setdefault(_k, []).append(_n)
    _qk = {}
    for _k, _c in _ec.items():
        if _c != 1:
            continue
        _qa = tuple(np.round(G[_k[0]], 9))
        _qb = tuple(np.round(G[_k[1]], 9))
        _qkey = (_qa, _qb) if _qa <= _qb else (_qb, _qa)
        _qk.setdefault(_qkey, []).append(_k)
    _rim_full = np.zeros(len(G), dtype=bool)
    _n_fold = _n_seam = _n_lone = 0
    for _qkey, _ks in _qk.items():
        if len(_ks) == 1:
            _n_lone += 1
            continue
        _d = float(_ef[_ks[0]][0] @ _ef[_ks[1]][0])
        if _d < -0.2:
            _n_fold += 1
            for _k in _ks:
                _rim_full[_k[0]] = True
                _rim_full[_k[1]] = True
        else:
            _n_seam += 1
    print(f"single-use edges: lone={_n_lone} seam={_n_seam} fold={_n_fold}")

    in_band = (G[:, 1] >= y0 - 0.05) & (G[:, 1] <= y1 + 0.05)
    Gc = G[in_band]
    print(f"nude={len(N)} garment={len(G)} in_band={in_band.sum()}")
    rim_band = _rim_full[in_band]
    print(f"fold-rim verts: {int(_rim_full.sum())}/{len(G)} "
          f"(in_band {int(rim_band.sum())})")
    # interior-facing cloth (authored NORMAL against the limb radial:
    # fold return walls diving through the flesh, cuff/thickness interiors)
    # is NEVER moved — it is occlusion dressing, not coverage. Threshold
    # interior_dot (default -0.2, set -2.0 to disable).
    GN, _ghas = collect_gnormals(gjs, gbuf, skip)
    GNc = GN[in_band]
    idot = float(getattr(a, "interior_dot", -0.2))
    _RAD = radial_dirs(Gc, ax, az, bx, bz)
    if _lxmin is not None:
        _lmr = np.abs(Gc[:, 0]) >= _lxmin
        _RAD[_lmr] = radial_dirs(Gc[_lmr], _lax, _laz, _lbx, _lbz)
    interior = _ghas & ((GNc * _RAD).sum(axis=1) < idot)
    print(f"interior-facing verts (skipped): {int(interior.sum())}/{len(Gc)}")

    buried0 = ray_parity(Gc, TRIS)
    print(f"buried BEFORE: {int(buried0.sum())}/{len(Gc)} "
          f"({100.0 * buried0.sum() / max(len(Gc), 1):.1f}%)")

    ex = float(getattr(a, 'exclude_x', 0.0))
    idx, dist = nearest_in_window(Gc, N, y0, y1, side, ex)
    valid = idx >= 0
    # verts exactly ON the skin count as outside (parity noise guard)
    buried = buried0 & valid & (dist > 1e-4)
    # fold rims AND interior-facing walls are FROZEN raw, buried or not
    # (occlusion dressing by design: fold returns, thickness interiors —
    # moving them spikes them through the jacket, 30/09). Excluded from
    # every candidacy below. Lone-boundary and seam edges take the normal
    # path (coverage).
    rim = rim_band | interior
    elig = ~rim
    print(f"rim_frozen (fold rims + interiors, left raw): {int(rim.sum())}")

    deltas = np.zeros_like(Gc)
    # --- outsiders too close: push out to margin along skin->cloth, but ONLY
    # inside the hug window (authored ease — flared hems — is preserved).
    in_hug = (Gc[:, 1] >= hy0 - 0.05) & (Gc[:, 1] <= hy1 + 0.05)
    need = valid & ~buried & elig & in_hug & (dist < a.margin)
    if need.any():
        tgt = N[idx[need]]
        diff = Gc[need] - tgt
        c = np.linalg.norm(diff, axis=1)
        degen = c < 1e-6
        d = np.zeros_like(diff)
        ok = ~degen
        d[ok] = (diff[ok] / c[ok][:, None]) * (a.margin - c[ok])[:, None]
        if degen.any():
            d[degen] = radial_dirs(Gc[need][degen], ax, az, bx, bz) * a.margin
        clamp_len(d, a.max_push)
        deltas[need] = d
        print(f"hugged={int(need.sum())}")
    # --- buried: EXTRACT by (depth + margin): anti-gap direction, except
    # in the limb zone (jacket sleeve stubs expand around the arm, never
    # eject sideways through the deltoid — needles, 30/09).
    # (buried fold rims excluded: frozen raw, see above)
    ext = buried & elig
    if ext.any():
        tgt = N[idx[ext]]
        c = dist[ext]
        dirs = extract_dirs_zoned(Gc[ext], Nn[idx[ext]], ax, az, bx, bz,
                                 (_lxmin, _lax, _laz, _lbx, _lbz) if _lxmin is not None else None)
        d = dirs * (c + a.margin)[:, None]
        clamp_len(d, a.max_push)
        deltas[ext] = d
        print(f"extracted={int(ext.sum())} max_depth={(c.max()) * 1000:.1f}mm")

    # topology smoothing over the full displacement field (acc_blocks was
    # built up front, shared with the open-edge rim detection)
    gnb = [set() for _ in range(len(G))]
    for mi, mesh in enumerate(gjs.get("meshes", [])):
        for prim in mesh["primitives"]:
            ai = prim["attributes"]["POSITION"]
            blk = next((b for b in acc_blocks if b[0] == ai), None)
            if blk is None or "indices" not in prim:
                continue
            _, start, _ = blk
            tri = index_array(gjs, gbuf, prim).reshape(-1, 3)
            for t in tri:
                t = t + start
                gnb[t[0]].update((t[1], t[2]))
                gnb[t[1]].update((t[0], t[2]))
                gnb[t[2]].update((t[0], t[1]))
    band_idx = np.flatnonzero(in_band)
    pos_of = {g: i for i, g in enumerate(band_idx)}
    nb = [np.array([pos_of[h] for h in gnb[g] if h in pos_of], dtype=np.int64)
          for g in band_idx]
    _raw_groups = weld_groups(np.round(Gc, 9))
    _rim_idx = set(np.flatnonzero(rim).tolist())
    groups = [g[np.array([int(i) not in _rim_idx for i in g])] for g in _raw_groups]
    groups = [g for g in groups if len(g) > 0]
    print(f"weld groups: {len(groups)} (raw {len(_raw_groups)}, "
          f"{sum(len(g) for g in groups)} verts on authored seams)")
    tear_report(deltas, groups, "pre-smooth")
    deltas = smooth_deltas(deltas, nb, a.smooth_iters, groups)
    tear_report(deltas, groups, "post-smooth (must be ~0)")
    rr = float(getattr(a, "ride_radius", 0.015))
    deltas, adj = ride_along(deltas, Gc, rr)
    for g in groups:
        deltas[g] = deltas[g].mean(axis=0)
    deltas[rim] = 0.0
    print(f"ride-along pre-touchup R={rr * 1000:.0f}mm: max_adjust={adj * 1000:.1f}mm")

    # signed touch-up loop: re-extract buried, re-push close outsiders
    moved = Gc + deltas
    hug2 = (moved[:, 1] >= hy0 - 0.05) & (moved[:, 1] <= hy1 + 0.05)
    # Strike freeze: a vert still bad after 3 consecutive rounds is ping-
    # ponging between volumes (armpit trap) — freeze it where it is instead
    # of growing a needle. Frozen verts stay buried = occluded = invisible,
    # while the visible flank cloth converges normally around them.
    strikes = np.zeros(len(Gc), dtype=np.int32)
    bad = np.zeros(len(Gc), dtype=bool)
    for _round in range(8):
        idx2, dist2 = nearest_in_window(moved, N, y0, y1, side, ex)
        v2 = idx2 >= 0
        bur2 = ray_parity(moved, TRIS) & v2 & (dist2 > 1e-4)
        out2 = v2 & ~bur2 & hug2 & (dist2 < a.margin * 0.5)
        bad = (bur2 | out2) & (strikes < 3) & elig & elig
        if not bad.any():
            break
        strikes[bad] += 1
        fix = np.zeros((bad.sum(), 3))
        # outsiders -> 3/4 margin. In the limb zone the direction is the limb
        # radial (never back toward the nearest skin: that re-buries sleeve
        # verts into the arm and ping-pongs with the torso candidates).
        mo = out2[bad]
        if mo.any():
            _mv = moved[bad][mo]
            _c = np.linalg.norm(_mv - N[idx2[bad][mo]], axis=1)
            _ok = _c > 1e-6
            fo = np.zeros_like(_mv)
            _amt = (a.margin * 0.75 - _c)
            if _lxmin is not None:
                _lm2 = np.abs(_mv[:, 0]) >= _lxmin
                if _lm2.any():
                    _rd = radial_dirs(_mv[_lm2], _lax, _laz, _lbx, _lbz)
                    fo[_lm2] = _rd * _amt[_lm2][:, None]
                    _ok = _ok & ~_lm2
            diff = _mv - N[idx2[bad][mo]]
            c = np.linalg.norm(diff, axis=1)
            ok = (c > 1e-6) & _ok
            fo[ok] = (diff[ok] / c[ok][:, None]) * _amt[ok][:, None]
            fix[mo] = fo
        # buried -> extract (depth + 3/4 margin), zoned direction
        mb = bur2[bad]
        if mb.any():
            bi = bad.nonzero()[0][mb]
            c = dist2[bi]
            dirs = extract_dirs_zoned(moved[bi], Nn[idx2[bi]], ax, az, bx, bz,
                                      (_lxmin, _lax, _laz, _lbx, _lbz) if _lxmin is not None else None)
            fix[mb] = dirs * (c + a.margin * 0.75)[:, None]
        clamp_len(fix, a.max_push)
        deltas[bad] += fix
        moved = Gc + deltas
    frozen = int((strikes >= 3).sum())
    print(f"touchup rounds={_round + 1} remaining={int(bad.sum())} "
          f"frozen={frozen}")
    # --- revert safety net (keeps only converged changes):
    # (a) trap verts (3+ strikes AND still bad on a fresh mask-free check:
    # armpit ping-pong between volumes, unfixable locally) go back to
    # vendor-raw: occluded folds the user never flagged, instead of needles
    # drilled hundreds of mm;
    # (b) spikes (big move incoherent with neighbours: converged-outside
    # needles) go back to raw; coherent relocations (whole patch travelled)
    # are kept.
    idxF, distF = nearest_in_window(moved, N, y0, y1, side, ex)
    vF = idxF >= 0
    bad_now = ((ray_parity(moved, TRIS) & vF & (distF > 1e-4))
               | (vF & hug2 & (distF < a.margin * 0.5))) & elig
    trap = (strikes >= 3) & bad_now
    dmag = np.linalg.norm(deltas, axis=1)
    # lone-peak guard (30/09: symmetric U-bottom verts at armpits shooting
    # off alone): incoherent moves above 15mm revert to raw. Median is taken
    # over NON-frozen neighbours so fold lips next to frozen rims are not
    # misread; coherent patch relocations keep a high median and survive.
    spike = np.zeros(len(Gc), dtype=bool)
    _frz = set(np.flatnonzero(rim).tolist())
    for i, nb_i in enumerate(nb):
        if dmag[i] > 0.015 and len(nb_i):
            _live = np.array([j for j in nb_i if j != i and int(j) not in _frz],
                             dtype=np.int64)
            if len(_live):
                med = float(np.median(dmag[_live]))
                if dmag[i] > 3.0 * max(med, 0.005):
                    spike[i] = True
    n_trap, n_spike = int(trap.sum()), int(spike.sum())
    deltas[trap | spike] = 0.0
    if n_trap + n_spike:
        print(f"reverted: trap={n_trap} spike={n_spike}")
        moved = Gc + deltas
    deltas, adj2 = ride_along(deltas, Gc, rr)
    for g in groups:
        deltas[g] = deltas[g].mean(axis=0)
    deltas[rim] = 0.0
    print(f"ride-along final: max_adjust={adj2 * 1000:.1f}mm")
    moved = Gc + deltas

    # final SIGNED stats: buried shown as negative clearance
    idx3, dist3 = nearest_in_window(moved, N, y0, y1, side, ex)
    v3 = idx3 >= 0
    bur3 = ray_parity(moved[v3], TRIS)
    signed = dist3[v3].copy()
    signed[bur3] = -signed[bur3]
    n_out = int((~bur3).sum())
    print(f"buried AFTER: {int(bur3.sum())}/{v3.sum()} "
          f"signed_min={signed.min() * 1000:.1f}mm "
          f"outside_min={(signed[~bur3].min() if n_out else float('nan')) * 1000:.1f}mm")
    print(f"moved={int((np.linalg.norm(deltas, axis=1) > 1e-6).sum())} "
          f"max_push={np.linalg.norm(deltas, axis=1).max() * 1000:.1f}mm")

    if a.dry_run:
        return

    full = np.zeros_like(G)
    for g in groups:
        deltas[g] = deltas[g].mean(axis=0)
    deltas[rim] = 0.0
    tear_report(deltas, groups, "pre-write (must be 0)")
    # fold mouths (rim frozen raw + lip extracted out): deliberate separation
    # at coincident verts — the mouth widens showing dark fold interior, NOT
    # skin. Informational: flags runaway separations, never fails the bake.
    mouth = 0.0
    for g in _raw_groups:
        if len(g) > 1:
            mouth = max(mouth, float((deltas[g].max(axis=0) - deltas[g].min(axis=0)).max()))
    print(f"fold-mouth max separation={mouth * 1000:.1f}mm")
    full[in_band] = deltas
    buf = bytearray(gbuf[0])
    for ai, off, n in owners:
        blk = next(b for b in acc_blocks if b[0] == ai)
        seg = full[blk[1]:blk[1] + n]
        orig = np.frombuffer(gbuf[0], dtype=np.float32, count=n * 3,
                             offset=off).reshape(n, 3).astype(np.float64)
        new = (orig + seg).astype(np.float32)
        struct.pack_into(f"<{n * 3}f", buf, off, *new.ravel())
        gjs["accessors"][ai]["min"] = [float(v) for v in new.min(axis=0)]
        gjs["accessors"][ai]["max"] = [float(v) for v in new.max(axis=0)]
    gjs["buffers"][0]["byteLength"] = len(buf)
    gjs["buffers"][0].pop("uri", None)
    outbase = os.path.basename(os.path.splitext(a.part)[0]) + "_Fitted.glb"
    if a.outdir:
        os.makedirs(a.outdir, exist_ok=True)
        out = os.path.join(a.outdir, outbase)
    else:
        out = os.path.splitext(a.part)[0] + "_Fitted.glb"
    # image URIs resolve relative to the OUTPUT file: rewrite them as
    # outdir -> source relpaths BEFORE serializing (a fitted/ bake otherwise
    # loses its textures: white materials at runtime, caught 30/09).
    src_dir = os.path.dirname(os.path.abspath(a.part))
    out_dir = os.path.dirname(os.path.abspath(out))
    for img in gjs.get("images", []):
        uri = img.get("uri", "")
        if not uri or uri.startswith("data:"):
            continue
        src_abs = os.path.normpath(os.path.join(src_dir, uri))
        if not os.path.exists(src_abs):
            print(f"WARNING missing texture source: {src_abs}")
            continue
        img["uri"] = os.path.relpath(src_abs, out_dir)

    js_bytes = json.dumps(gjs, separators=(",", ":")).encode("utf-8")
    while len(js_bytes) % 4:
        js_bytes += b" "
    glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js_bytes) + 8 + len(buf))
    glb += struct.pack("<II", len(js_bytes), 0x4E4F534A) + js_bytes
    glb += struct.pack("<II", len(buf), 0x004E4942) + bytes(buf)
    with open(out, "wb") as f:
        f.write(glb)
    print(f"wrote {out} ({len(glb)} bytes)")


if __name__ == "__main__":
    o = _parse_cli()
    if o.manifest:
        with open(os.path.join(o.root, o.manifest)) as f:
            m = json.load(f)
        outdir = os.path.join(o.root, m.get("outdir", "")) if m.get("outdir") else ""
        for e in m["parts"]:
            if o.only and o.only not in e.get("name", ""):
                continue
            merged = dict(vars(o))
            merged.update(m.get("defaults", {}))
            merged.update(e)
            ns = argparse.Namespace(**merged)
            ns.nude = os.path.join(o.root, ns.nude)
            ns.part = os.path.join(o.root, ns.part)
            ns.outdir = outdir
            main(ns)
    else:
        main(o)
