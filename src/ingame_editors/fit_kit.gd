class_name FitKit
extends RefCounted

## Runtime garment fit (merge-avatar phase 1, 01/10): conforms a slot holder's
## meshes to the nude snapshot IN MEMORY (no files, no bake). Single pass:
## nearest-nude signed test (authored-normal dot, 96% parity agreement
## measured headless) + margin hug/extract + clamp + interior-skip +
## Laplacian smooth (weld-consistent) + ride-along + lone-peak revert.
## Writes back new ArrayMesh surfaces (VERTEX only — weights/UVs/materials
## untouched, skinning preserved). Male numbers ported from the offline bake
## tuning; female slots have their own table below.
## Pure geometry, no autoloads, no input — headless-checkable.

const CELL := 0.02
const MAX_PUSH := 0.06
const SMOOTH_ITERS := 3
const RIDE_RADIUS := 0.015
const INTERIOR_DOT := -0.2
const SPIKE_MM := 0.008
const SKIP_SUBSTR := "Regular"
# slot -> [ax, az, bx, bz, margin, zone[y0, y1, xmax, zmargin] or []]
# Male table from the offline bake tuning; female table: same doctrine,
# narrower limb axes.
const SLOT_CFG := {
	&"Body": [0.0, 0.01, 0.0, 0.01, 0.008, []],
	&"Arms": [0.32, -0.07, -0.32, -0.07, 0.006, []],
	&"Legs": [0.09, -0.03, -0.09, -0.03, 0.010, [0.75, 0.98, 0.10, 0.012]],
	&"Feet": [0.11, -0.06, -0.11, -0.06, 0.008, []],
	&"Head": [0.0, 0.0, 0.0, 0.0, 0.008, []],
	&"Accessories": [0.0, 0.0, 0.0, 0.0, 0.008, []],
}
const SLOT_CFG_FEMALE := {
	&"Body": [0.0, 0.01, 0.0, 0.01, 0.008, []],
	&"Arms": [0.30, -0.07, -0.30, -0.07, 0.006, []],
	&"Legs": [0.09, -0.03, -0.09, -0.03, 0.010, [0.75, 0.98, 0.10, 0.012]],
	&"Feet": [0.10, -0.06, -0.10, -0.06, 0.008, []],
	&"Head": [0.0, 0.0, 0.0, 0.0, 0.008, []],
	&"Accessories": [0.0, 0.0, 0.0, 0.0, 0.008, []],
}


static func cfg_for(slot: StringName, gender: int) -> Array:
	if gender == 1 and SLOT_CFG_FEMALE.has(slot):
		return SLOT_CFG_FEMALE[slot]
	return SLOT_CFG.get(slot, [])


## ---- merge-avatar phase 2: suppression + fusion (01/10) ----
## The nude shows VISIBLE skin only: any nude triangle fully buried under
## garments is deleted (kept: head above the neck plane + sanctuary
## meshes Head/Eyebrows/Eyes by node name). Remaining nude + garments
## fuse into ONE ArrayMesh on the master skeleton. Pure geometry, no tree
## writes except the in-place nude suppression; fusion returns a fresh mesh.

## Custom vertex-attribute slots (6..9) cannot round-trip through
## add_surface_from_arrays (importer-filled float custom data is rejected —
## byte packing expected) and the toon shader never reads them: strip.
static func _strip_custom(a: Array) -> void:
	for k in [6, 7, 8, 9]:
		if k < a.size():
			a[k] = null


## Pass-1 garment volumes (03/10, replaces the N+E + 7-tier doctrine): the nude
## shows the head only by default; each garment chain owns a convex volume
## built from its FITTED verts (bind pose, global space). A nude vert of chain
## C is deleted when its 3D distance to volume(C) is within VOL_REACH —
## arms/legs are flat-ended cylinders (axis segment + rmax), torso and boots are AABBs,
## all directions included (no along-axis exception). Convex volumes auto-fill drape hollows; openings (V, window, neckline) are holes inside
## the volumes, recovered in pass 2 — expect them deleted after pass 1 alone.
## Volumes follow the garment SHAPE (limb boxes oriented along the bone chain,
## torso AABB), never world AABBs (a world AABB of a T-pose sleeve eats the
## torso). Requires fitted garments (runs after the FitKit conform, as before).
## Single uniform reach in ALL directions (limbs included, 03/10): pass 1
## roughs out, pass 2 refines — wrists/ankles/neck eaten within reach are
## pass-2 debt (hem/collar rims), not pass-1 bugs. Legs and boots own separate
## volumes (03/10): the shoe no longer fattens the whole leg — each boot gets
## its own AABB box (an L-shaped shaft+foot has no single capsule axis: PCA
## went diagonal and missed the shaft top and toes at zero reach). Same split
## available for hands later; arms keep one capsule (hand included) until the
## eye recipe says otherwise.
const VOL_REACH := 0.04
const SANCTUARY_SUBSTR := ["Head", "Eye", "Brow", "Hair", "Teeth", "Tongue"]
## Vendor skin ("Regular") is real skin, not cloth: conform it snug to the
## nude (small margin, tight clamp) instead of skipping it, so it serves as
## an occlusion witness where the body is. Never welded: clamp caps travel.
const REGULAR_MARGIN := 0.004
const REGULAR_CLAMP := 0.015
## Cylinder axes only (arms/legs — straight in bind): start point + unit axis
## from first -> last bone global-rest origin. Boxes (torso, boots) need no
## frame. Bones are used for nothing else in pass 1.
const LIMB_CHAINS := {
	"ArmL": ["LeftUpperArm", "LeftLowerArm", "LeftHand"],
	"ArmR": ["RightUpperArm", "RightLowerArm", "RightHand"],
	"LegL": ["LeftUpperLeg", "LeftLowerLeg"],
	"LegR": ["RightUpperLeg", "RightLowerLeg"],
}
## Garment slot -> volume piece. Side (limb pieces) comes from the x sign of
## the vert itself, calibrated once per skeleton (below): bones never decide
## which garment volume a vert belongs to — a knee-high and a thigh-high boot
## both land exactly on their own mesh.
const SLOT_PIECE := {
	"Body": "Torso", "Head": "Torso", "Accessories": "Torso",
	"Arms": "Arm", "Legs": "Leg", "Feet": "Foot",
}
## Nude test order (first hit wins the stat; deletion is the union).
const VOL_ORDER := ["Torso", "ArmL", "ArmR", "LegL", "LegR", "FootL", "FootR"]


static func _is_sanctuary(mi_name: String) -> bool:
	for s in SANCTUARY_SUBSTR:
		if mi_name.contains(s):
			return true
	return false


## Sign of the skeleton's left side on the bind X axis (LeftFoot rest, leg
## fallbacks): calibrates the mesh x-sign side test once per avatar. Bones as
## a ruler only — never a volume key.
static func _left_sign(master: Skeleton3D) -> float:
	for bn in ["LeftFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftHand", "LeftUpperArm"]:
		var bi := master.find_bone(bn)
		if bi == -1:
			continue
		var x := master.get_bone_global_rest(bi).origin.x
		if absf(x) > 1e-6:
			return signf(x)
	return 1.0


## Chain bind-frame data from the master skeleton: limb chains get a start
## point + unit axis (first -> last bone global-rest origin).
static func _chain_data(master: Skeleton3D) -> Dictionary:
	var out := {}
	for chain in LIMB_CHAINS:
		var names: Array = LIMB_CHAINS[chain]
		var a := master.find_bone(names[0])
		var b := master.find_bone(names[names.size() - 1])
		if a == -1 or b == -1:
			continue
		var pa: Vector3 = master.get_bone_global_rest(a).origin
		var pb: Vector3 = master.get_bone_global_rest(b).origin
		var d := pb - pa
		if d.length() < 1e-6:
			continue
		out[chain] = {"start": pa, "dir": d.normalized()}
	return out


## Neck-plane height from the master skeleton rest (Standard "Neck", UE
## fallback "neck_01", else a 1.35 m constant) plus NECK_MARGIN: the plane
## keeps the head/neck tube, but the trapezius dome sloping up to the neck
## base must fall below it so the torso box can delete it. Lower neck
## removed with it is pass-2 (neckline) debt. Holders are identity so
## skeleton-space Y == global Y.
const NECK_MARGIN := 0.04
static func neck_height(master: Skeleton3D) -> float:
	if master != null:
		var bi := master.find_bone("Neck")
		if bi == -1:
			bi = master.find_bone("neck_01")
		if bi != -1:
			return master.get_bone_global_rest(bi).origin.y + NECK_MARGIN
	return 1.35 + NECK_MARGIN


## Garment volumes (global bind space) from the FITTED meshes: arms/legs ->
## {"limb": true, "tmin", "tmax", "rmax"} cylinders in the skeleton chain frame
## (axis from _chain_data, extents from the mesh); torso and boots ->
## {"limb": false, "bmin", "bmax"} AABB boxes. Garment verts are grouped by
## (slot, x-sign side) — mesh inspection only, no bones. Pieces with no
## garment verts are absent (skin kept).


## Robust span: percentile of a sorted float array (stray verts with bad
## skinning weights must not balloon the volumes).
static func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	var f: float = clampf(p, 0.0, 1.0) * float(sorted.size() - 1)
	var lo := int(floor(f))
	var hi := int(ceil(f))
	return lerpf(float(sorted[lo]), float(sorted[hi]), f - float(lo))


static func _garment_volumes(garment_holders: Array, master: Skeleton3D, cdata: Dictionary) -> Dictionary:
	var vols := {}
	if master == null:
		return vols
	var lsign := _left_sign(master)
	var acc := {} # volume key -> {"t": [], "r": []} cylinders, {"x": [], "y": [], "z": []} boxes
	for h in garment_holders:
		if h == null:
			continue
		# Piece from the slot holder name, side from the vert's own x sign:
		# mesh inspection only, no bones.
		var piece := String(SLOT_PIECE.get(String((h as Node).name), "Torso"))
		var sided := piece != "Torso"
		for mi in meshes_under(h):
			var m := (mi as MeshInstance3D).mesh as ArrayMesh
			if m == null or m.get_blend_shape_count() > 0:
				continue
			var xf: Transform3D = (mi as MeshInstance3D).global_transform
			for s in m.get_surface_count():
				var a := m.surface_get_arrays(s)
				if a[Mesh.ARRAY_VERTEX] == null:
					continue
				var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				for i in vv.size():
					var g: Vector3 = xf * vv[i]
					var key := piece
					if sided:
						key += "L" if g.x * lsign >= 0.0 else "R"
					if key == "Torso" or not cdata.has(key):
						if not acc.has(key):
							acc[key] = {"x": [], "y": [], "z": []}
						var at: Dictionary = acc[key]
						(at["x"] as Array).append(g.x)
						(at["y"] as Array).append(g.y)
						(at["z"] as Array).append(g.z)
						continue
					var d: Dictionary = cdata[key]
					var rel: Vector3 = g - (d["start"] as Vector3)
					var t: float = rel.dot(d["dir"] as Vector3)
					var r: float = (rel - (d["dir"] as Vector3) * t).length()
					if not acc.has(key):
						acc[key] = {"t": [], "r": []}
					var al: Dictionary = acc[key]
					(al["t"] as Array).append(t)
					(al["r"] as Array).append(r)
	for chain in acc:
		var e: Dictionary = acc[chain]
		if e.has("x"):
			var xs: Array = e["x"]
			var ys: Array = e["y"]
			var zs: Array = e["z"]
			xs.sort()
			ys.sort()
			zs.sort()
			vols[chain] = {"limb": false,
				"bmin": Vector3(_pct(xs, 0.01), _pct(ys, 0.01), _pct(zs, 0.01)),
				"bmax": Vector3(_pct(xs, 0.99), _pct(ys, 0.99), _pct(zs, 0.99))}
		else:
			var ts: Array = e["t"]
			var rs: Array = e["r"]
			ts.sort()
			rs.sort()
			vols[chain] = {"limb": true,
				"tmin": _pct(ts, 0.01), "tmax": _pct(ts, 0.99), "rmax": _pct(rs, 0.99)}
	return vols


## 1 when the skin must go: 3D distance to the box volume <= VOL_REACH.
## Torso and boots are AABB boxes (limbs are tested in _vol_hit).
## Chains with no garment volume keep all.
static func _box_hit(v: Dictionary, g: Vector3) -> int:
	var bmin: Vector3 = v["bmin"] as Vector3
	var bmax: Vector3 = v["bmax"] as Vector3
	var dx := maxf(maxf(bmin.x - g.x, 0.0), g.x - bmax.x)
	var dy := maxf(maxf(bmin.y - g.y, 0.0), g.y - bmax.y)
	var dz := maxf(maxf(bmin.z - g.z, 0.0), g.z - bmax.z)
	return 1 if Vector3(dx, dy, dz).length() <= VOL_REACH else 0


## First garment volume containing the skin point (VOL_ORDER), "" when the
## skin survives: a nude vert goes when inside ANY garment volume — thigh
## under thigh-boot, leg under robe, calf under shaft. Limbs are flat-ended
## cylinders (no round caps, unlike capsules); VOL_REACH extends both the
## radius and the end planes. No chain mapping, no exceptions; deletion is
## the union.
static func _vol_hit(vols: Dictionary, cdata: Dictionary, g: Vector3) -> String:
	for key in VOL_ORDER:
		if not vols.has(key):
			continue
		var v: Dictionary = vols[key]
		if not bool(v["limb"]):
			if _box_hit(v, g) == 1:
				return String(key)
		else:
			if not cdata.has(key):
				continue
			var d: Dictionary = cdata[key]
			var start: Vector3 = d["start"] as Vector3
			var dir: Vector3 = (d["dir"] as Vector3).normalized()
			var a := start + dir * (float(v["tmin"]) - VOL_REACH)
			var b := start + dir * (float(v["tmax"]) + VOL_REACH)
			var ab := b - a
			var t: float = (g - a).dot(ab) / maxf(ab.length_squared(), 1e-9)
			if t < 0.0 or t > 1.0:
				continue
			var dist: float = (a + ab * t).distance_to(g)
			if dist <= float(v["rmax"]) + VOL_REACH:
				return String(key)
	return ""


## Pass-1 volume cut: deletes nude triangles inside the garment volumes (in
## place). garment_holders carry FITTED garment meshes. Returns stats {ok,
## tris_before, tris_after, removed, vol_del_<volume> (verts)}. No tuck, no
## order, no fringe: the hero diff (log + X-ray) is the measure; pass 2
## recovers the openings (V, window, neckline, limb ends).
static func suppress_covered(nude_holder: Node, garment_holders: Array, master: Skeleton3D) -> Dictionary:
	var stats := {"ok": false, "tris_before": 0, "tris_after": 0, "removed": 0}
	var ny := neck_height(master)
	if master == null:
		stats["skipped"] = "no master (bone names needed)"
		return stats
	var cdata := _chain_data(master)
	var vols := _garment_volumes(garment_holders, master, cdata)
	if vols.is_empty():
		stats["skipped"] = "no garment volumes"
		return stats
	for chain in vols:
		var v: Dictionary = vols[chain]
		if bool(v["limb"]):
			print("[Merge] vol %s: t=[%.0f..%.0f]mm rmax=%.0fmm" % [String(chain), float(v["tmin"]) * 1000.0, float(v["tmax"]) * 1000.0, float(v["rmax"]) * 1000.0])
		else:
			var sz: Vector3 = (v["bmax"] as Vector3) - (v["bmin"] as Vector3)
			print("[Merge] vol %s: box %.0fx%.0fx%.0fmm" % [String(chain), sz.x * 1000.0, sz.y * 1000.0, sz.z * 1000.0])
	var tb := 0
	var ta := 0
	for mi in meshes_under(nude_holder):
		var mmi := mi as MeshInstance3D
		var m := mmi.mesh as ArrayMesh
		if m == null or m.get_blend_shape_count() > 0:
			continue
		if _is_sanctuary(String(mmi.name)):
			var kept := 0
			for s in m.get_surface_count():
				var a0 := m.surface_get_arrays(s)
				if a0[Mesh.ARRAY_INDEX] != null:
					kept += (a0[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			tb += kept
			ta += kept
			continue
		var xf: Transform3D = mmi.global_transform
		var nm := ArrayMesh.new()
		var kept_surf := 0
		for s in m.get_surface_count():
			var a := m.surface_get_arrays(s)
			if a[Mesh.ARRAY_VERTEX] == null or a[Mesh.ARRAY_INDEX] == null:
				continue
			var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			tb += idx.size() / 3
			if idx.size() % 3 != 0:
				var na0 := a.duplicate()
				nm.add_surface_from_arrays(m.surface_get_primitive_type(s), na0)
				nm.surface_set_material(kept_surf, m.surface_get_material(s))
				kept_surf += 1
				ta += idx.size() / 3
				continue
			var covered := PackedByteArray()
			covered.resize(vv.size())
			for i in vv.size():
				var g: Vector3 = xf * vv[i]
				if g.y >= ny:
					continue
				var hit := _vol_hit(vols, cdata, g)
				if not hit.is_empty():
					covered[i] = 1
					var vk := "vol_del_" + hit
					stats[vk] = int(stats.get(vk, 0)) + 1
			# Delete = tris fully inside a garment volume. No fringe, no
			# tuck: boundary verts stay exactly where they are for the diff.
			var ntris := idx.size() / 3
			var del := PackedByteArray()
			del.resize(ntris)
			for t in ntris:
				var c0: int = covered[idx[t * 3]]
				var c1: int = covered[idx[t * 3 + 1]]
				var c2: int = covered[idx[t * 3 + 2]]
				if c0 + c1 + c2 == 3:
					del[t] = 1
					continue
				if c0 + c1 + c2 == 0:
					continue
			var edge_map := {}
			for t in ntris:
				for k in 3:
					var e0: int = idx[t * 3 + k]
					var e1: int = idx[t * 3 + (k + 1) % 3]
					var e := Vector2i(mini(e0, e1), maxi(e0, e1))
					if edge_map.has(e):
						(edge_map[e] as Array).append(t)
					else:
						edge_map[e] = [t]
			# Hole fill (1 pass): a kept tri whose 3 edges all touch deleted
			# tris joins the cut — kills pinholes, cannot open gaps (its
			# neighbours are already gone; open borders never qualify).
			for t in ntris:
				if del[t] == 1:
					continue
				var closed := true
				for k in 3:
					var e0: int = idx[t * 3 + k]
					var e1: int = idx[t * 3 + (k + 1) % 3]
					var e := Vector2i(mini(e0, e1), maxi(e0, e1))
					var any_del := false
					for nt in (edge_map[e] as Array):
						if nt != t and del[nt] == 1:
							any_del = true
							break
					if not any_del:
						closed = false
						break
				if closed:
					del[t] = 1
					stats["holefill"] = int(stats.get("holefill", 0)) + 1
			var vv2 := (vv as PackedVector3Array).duplicate()
			var nidx := PackedInt32Array()
			for t in ntris:
				if del[t] == 1:
					continue
				nidx.append_array([idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]])
			if nidx.is_empty():
				continue
			var na := a.duplicate()
			na[Mesh.ARRAY_VERTEX] = vv2
			na[Mesh.ARRAY_INDEX] = nidx
			_strip_custom(na)
			nm.add_surface_from_arrays(m.surface_get_primitive_type(s), na)
			nm.surface_set_material(kept_surf, m.surface_get_material(s))
			kept_surf += 1
			ta += nidx.size() / 3
		if kept_surf > 0:
			mmi.mesh = nm
		else:
			mmi.mesh = null
	stats["ok"] = true
	stats["tris_before"] = tb
	stats["tris_after"] = ta
	stats["removed"] = tb - ta
	print("[Merge] nude tris %d->%d (removed %d, neck_y=%.3f)" % [tb, ta, tb - ta, ny])
	var vparts := []
	for k in stats:
		if String(k).begins_with("vol_del_"):
			vparts.append("%s=%d" % [String(k).trim_prefix("vol_del_"), int(stats[k])])
	vparts.sort()
	if not vparts.is_empty():
		print("[Merge] vol-del %s" % " ".join(vparts))
	stats["vols"] = vols
	stats["cdata"] = cdata
	return stats


## Fuses nude (post-suppression) + garment surfaces into TWO ArrayMeshes
## bound to master — skin (p["kind"] == "skin") and cloth — sharing the one
## skeleton so the X-ray toggle can show each side. parts: Array of
## {mi, skeleton, kind}. Bone indices remap to master (identity when counts
## match — probe 01/10: same 65 order, names differ; else name map,
## unmapped -> 0 + warning count). Materials prefer the dressed surface
## OVERRIDE (toon) over the base material. Blend-shape sources copy verbatim
## only when already on master, else skipped.
## Returns {ok, skin_mesh, cloth_mesh, skin_srcs, cloth_srcs, verts, ms}.
static func fuse_avatar(master: Skeleton3D, parts: Array) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var stats := {"ok": false}
	var skin := ArrayMesh.new()
	var cloth := ArrayMesh.new()
	var skin_srcs := PackedStringArray()
	var cloth_srcs := PackedStringArray()
	var nverts := 0
	var skipped := 0
	for p in parts:
		var mi: MeshInstance3D = p["mi"]
		var src: Skeleton3D = p["skeleton"]
		if mi == null or mi.mesh == null:
			continue
		var m := mi.mesh as ArrayMesh
		var identity := src == master or (src != null and master != null and src.get_bone_count() == master.get_bone_count())
		var bmap := PackedInt32Array()
		if not identity and src != null and master != null:
			bmap.resize(src.get_bone_count())
			for b in src.get_bone_count():
				var t := master.find_bone(src.get_bone_name(b))
				bmap[b] = t if t != -1 else 0
			var nbad := 0
			for b in bmap.size():
				if bmap[b] == 0 and String(src.get_bone_name(b)) != String(master.get_bone_name(0)):
					nbad += 1
			if nbad > 0:
				print("[Merge] WARN %s: %d bones unmapped (->Root)" % [String(mi.name), nbad])
		if m.get_blend_shape_count() > 0 and not identity:
			skipped += 1
			continue
		for s in m.get_surface_count():
			var a := m.surface_get_arrays(s)
			if a[Mesh.ARRAY_VERTEX] == null:
				continue
			var na := a.duplicate()
			if not identity and a[Mesh.ARRAY_BONES] != null:
				var bi: PackedInt32Array = (a[Mesh.ARRAY_BONES] as PackedInt32Array).duplicate()
				for k in bi.size():
					if bi[k] >= 0 and bi[k] < bmap.size():
						bi[k] = bmap[bi[k]]
				na[Mesh.ARRAY_BONES] = bi
			_strip_custom(na)
			var is_skin := String(p.get("kind", "cloth")) == "skin"
			var out := skin if is_skin else cloth
			var before := out.get_surface_count()
			out.add_surface_from_arrays(m.surface_get_primitive_type(s), na)
			if out.get_surface_count() == before + 1:
				var om := mi.get_surface_override_material(s)
				out.surface_set_material(before, om if om != null else m.surface_get_material(s))
				if is_skin:
					skin_srcs.append(String(mi.name))
				else:
					cloth_srcs.append(String(mi.name))
				nverts += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			else:
				print("[Merge] WARN surface %s:%d rejected" % [String(mi.name), s])
	stats["ok"] = skin.get_surface_count() + cloth.get_surface_count() > 0
	stats["skin_mesh"] = skin
	stats["cloth_mesh"] = cloth
	stats["skin_srcs"] = skin_srcs
	stats["cloth_srcs"] = cloth_srcs
	stats["verts"] = nverts
	stats["skin_surfs"] = skin.get_surface_count()
	stats["cloth_surfs"] = cloth.get_surface_count()
	stats["skipped"] = skipped
	stats["ms"] = Time.get_ticks_msec() - t0
	print("[Merge] fused skin %d + cloth %d surfaces %d verts (skipped blend=%d) %dms" % [skin.get_surface_count(), cloth.get_surface_count(), nverts, skipped, stats["ms"]])
	return stats


static func meshes_under(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out += meshes_under(c)
	return out


## Nude snapshot in GLOBAL space (bind pose: vertex arrays never move with
## bone poses, node transforms are dress-time identity).
static func snapshot_nude(nude_holder: Node) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for mi in meshes_under(nude_holder):
		var m := (mi as MeshInstance3D).mesh as ArrayMesh
		if m == null:
			continue
		var xf: Transform3D = (mi as MeshInstance3D).global_transform
		var nrm := xf.basis.inverse().transposed()
		for s in m.get_surface_count():
			var a := m.surface_get_arrays(s)
			if a[Mesh.ARRAY_VERTEX] == null:
				continue
			var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var an: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in vv.size():
				verts.append(xf * vv[i])
				if i < an.size() and an[i].length_squared() > 0.25:
					norms.append((nrm * an[i]).normalized())
				else:
					norms.append(Vector3.ZERO)
	return {"ok": not verts.is_empty(), "verts": verts, "normals": norms,
		"ms": Time.get_ticks_msec() - t0}


static func _build_grid(verts: PackedVector3Array, cell: float = CELL) -> Dictionary:
	var g := {}
	for i in verts.size():
		var k := Vector3i((verts[i] / cell).floor())
		if g.has(k):
			(g[k] as Array).append(i)
		else:
			g[k] = [i]
	return g


static func _nearest(g: Dictionary, verts: PackedVector3Array, q: Vector3, cell: float = CELL) -> int:
	var c := Vector3i((q / cell).floor())
	for ring in [1, 2, 4]:
		var best := -1
		var bd := 1e30
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				for dz in range(-ring, ring + 1):
					if ring > 1 and absi(dx) < ring and absi(dy) < ring and absi(dz) < ring:
						continue
					var k := c + Vector3i(dx, dy, dz)
					if not g.has(k):
						continue
					for i in (g[k] as Array):
						var dd := verts[i].distance_squared_to(q)
						if dd < bd:
							bd = dd
							best = i
		if best != -1:
			return best
	return -1


static func _radial(pts: PackedVector3Array, ax: float, az: float, bx: float, bz: float) -> PackedVector3Array:
	var d := PackedVector3Array()
	d.resize(pts.size())
	for i in pts.size():
		var ox: float = pts[i].x - (ax if pts[i].x >= 0.0 else bx)
		var oz: float = pts[i].z - (az if pts[i].x >= 0.0 else bz)
		var v := Vector3(ox, 0.0, oz)
		var l := v.length()
		d[i] = v / l if l > 1e-6 else Vector3.ZERO
	return d


## Conforms holder meshes to the nude snapshot, rewrites surfaces in place.
## regular_mode processes ONLY vendor-skin ("Regular") surfaces, snug
## (REGULAR_MARGIN/CLAMP) instead of skipping them; normal mode skips them.
## Returns stats {ok, verts, buried_before, buried_after, moved, max_push, ms}.
static func fit_holder(holder: Node, nude: Dictionary, slot: StringName, gender: int = 0, regular_mode: bool = false) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var stats := {"ok": false, "slot": String(slot)}
	var cfg: Array = cfg_for(slot, gender)
	if cfg.is_empty():
		stats["skipped"] = "no cfg"
		return stats
	var ax: float = cfg[0]
	var az: float = cfg[1]
	var bx: float = cfg[2]
	var bz: float = cfg[3]
	var margin: float = REGULAR_MARGIN if regular_mode else cfg[4]
	var push_cap: float = REGULAR_CLAMP if regular_mode else MAX_PUSH
	var zone: Array = [] if regular_mode else cfg[5]
	var nv: PackedVector3Array = nude["verts"]
	var nn: PackedVector3Array = nude["normals"]
	# working set (global space) + owners for write-back
	var gv := PackedVector3Array()
	var gn := PackedVector3Array()
	var owners := [] # [mi, surf, local_idx]
	var surf_tris := [] # [base, PackedInt32Array] per surface, for adjacency
	for mi in meshes_under(holder):
		var m := (mi as MeshInstance3D).mesh as ArrayMesh
		if m == null or m.get_blend_shape_count() > 0:
			continue
		var xf: Transform3D = (mi as MeshInstance3D).global_transform
		var nrm := xf.basis.inverse().transposed()
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			var is_reg := mat != null and SKIP_SUBSTR in mat.resource_name
			if is_reg != regular_mode:
				continue
			var a := m.surface_get_arrays(s)
			if a[Mesh.ARRAY_VERTEX] == null:
				continue
			var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var an: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var base := gv.size()
			for i in vv.size():
				gv.append(xf * vv[i])
				if i < an.size() and an[i].length_squared() > 0.25:
					gn.append((nrm * an[i]).normalized())
				else:
					gn.append(Vector3.ZERO)
				owners.append([mi, s, i])
			var local_nb: Array = []
			local_nb.resize(vv.size())
			for i in vv.size():
				local_nb[i] = []
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			if idx == null or idx.is_empty():
				idx = PackedInt32Array()
				idx.resize(vv.size())
				for i in vv.size():
					idx[i] = i
			surf_tris.append([base, idx])
	if gv.is_empty():
		stats["skipped"] = "no verts"
		return stats
	# working-space adjacency (per-vertex neighbour lists)
	var adj: Array = []
	adj.resize(gv.size())
	for i in gv.size():
		adj[i] = []
	for blk in surf_tris:
		var b: int = blk[0]
		var ix: PackedInt32Array = blk[1]
		for t in range(0, ix.size(), 3):
			var ta: int = ix[t] + b
			var tb: int = ix[t + 1] + b
			var tc: int = ix[t + 2] + b
			(adj[ta] as Array).append_array([tb, tc])
			(adj[tb] as Array).append_array([ta, tc])
			(adj[tc] as Array).append_array([ta, tb])
	# per-vert margin (optional zone override)
	var marg := PackedFloat32Array()
	marg.resize(gv.size())
	for i in gv.size():
		marg[i] = margin
	if not zone.is_empty():
		var zc := 0
		for i in gv.size():
			if gv[i].y >= zone[0] and gv[i].y <= zone[1] and absf(gv[i].x) <= zone[2]:
				marg[i] = zone[3]
				zc += 1
	# nearest + classify
	var grid := _build_grid(nv)
	var buried := PackedByteArray()
	buried.resize(gv.size())
	var nidx := PackedInt32Array()
	nidx.resize(gv.size())
	var dist := PackedFloat32Array()
	dist.resize(gv.size())
	var b0 := 0
	for i in gv.size():
		var j := _nearest(grid, nv, gv[i])
		nidx[i] = j
		if j == -1:
			dist[i] = 1e30
			continue
		dist[i] = nv[j].distance_to(gv[i])
		if dist[i] > 1e-4 and (gv[i] - nv[j]).dot(nn[j]) < 0.0:
			buried[i] = 1
			b0 += 1
	# interior-skip: authored fold returns diving through flesh never move
	var rad := _radial(gv, ax, az, bx, bz)
	var frozen := PackedByteArray()
	frozen.resize(gv.size())
	for i in gv.size():
		if gn[i].length_squared() > 0.25 and rad[i].length_squared() > 0.25 and gn[i].dot(rad[i]) < INTERIOR_DOT:
			frozen[i] = 1
	# deltas: hug outsiders, extract buried (anti-gap: normal unless facing limb)
	var deltas := PackedVector3Array()
	deltas.resize(gv.size())
	for i in gv.size():
		if frozen[i] == 1 or nidx[i] == -1:
			continue
		var n: Vector3 = nv[nidx[i]]
		var sn: Vector3 = nn[nidx[i]]
		if buried[i] == 1:
			var use_n := sn.length_squared() > 0.25 and sn.dot(rad[i]) > 0.0
			var dir: Vector3 = sn if use_n else rad[i]
			if dir.length_squared() < 0.25:
				continue
			deltas[i] = dir.normalized() * (dist[i] + marg[i])
		elif dist[i] < marg[i]:
			var diff := gv[i] - n
			var c := diff.length()
			if c < 1e-6:
				if rad[i].length_squared() > 0.25:
					deltas[i] = rad[i].normalized() * marg[i]
			else:
				deltas[i] = diff / c * (marg[i] - c)
	for i in gv.size():
		if deltas[i].length() > push_cap:
			deltas[i] = deltas[i].normalized() * push_cap
	# smooth (weld-consistent: coincident verts share one delta)
	var groups := {}
	for i in gv.size():
		var k := Vector3i((gv[i] * 1000.0).round())
		if groups.has(k):
			(groups[k] as Array).append(i)
		else:
			groups[k] = [i]
	for _it in SMOOTH_ITERS:
		var nd := deltas.duplicate()
		for i in gv.size():
			var l: Array = adj[i]
			if l.is_empty():
				continue
			var m := Vector3.ZERO
			for j in l:
				m += deltas[j]
			nd[i] = 0.5 * deltas[i] + 0.5 * m / l.size()
		deltas = nd
		for k in groups:
			var l: Array = groups[k]
			if l.size() > 1:
				var m := Vector3.ZERO
				for j in l:
					m += deltas[j]
				m /= l.size()
				for j in l:
					deltas[j] = m
	# ride-along (trim components follow the cloth; same-x-sign, never gaps).
	# Grid query (cell 20mm >= 15mm radius: ring 1 covers it), not O(n^2).
	var rr2 := RIDE_RADIUS * RIDE_RADIUS
	var sx := PackedFloat32Array()
	sx.resize(gv.size())
	for i in gv.size():
		sx[i] = signf(gv[i].x)
	var ggrid := _build_grid(gv)
	var ride := deltas.duplicate()
	for i in gv.size():
		var c := Vector3i((gv[i] / CELL).floor())
		var acc := Vector3.ZERO
		var cnt := 0
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var k := c + Vector3i(dx, dy, dz)
					if not ggrid.has(k):
						continue
					for j in (ggrid[k] as Array):
						if sx[i] * sx[j] < 0.0:
							continue
						if gv[i].distance_squared_to(gv[j]) <= rr2:
							acc += deltas[j]
							cnt += 1
		if cnt > 0:
			ride[i] = 0.5 * deltas[i] + 0.5 * acc / cnt
	deltas = ride
	for k in groups:
		var l: Array = groups[k]
		if l.size() > 1:
			var m := Vector3.ZERO
			for j in l:
				m += deltas[j]
			m /= l.size()
			for j in l:
				deltas[j] = m
	# touch-up rounds (bake doctrine: smoothing+ride drag extracted verts
	# back in — re-extract leftovers, re-hug close outsiders; grid queries,
	# no parity needed). Frozen (fold interiors) never re-enter.
	var moved := PackedVector3Array()
	moved.resize(gv.size())
	for i in gv.size():
		moved[i] = gv[i] + deltas[i]
	var rounds := 0
	var remaining := 0
	var strikes := PackedInt32Array()
	strikes.resize(gv.size())
	for _round in 8:
		rounds = _round + 1
		var bad := PackedByteArray()
		bad.resize(gv.size())
		var fix := PackedVector3Array()
		fix.resize(gv.size())
		remaining = 0
		for i in gv.size():
			if frozen[i] == 1 or strikes[i] >= 3:
				continue
			var j := _nearest(grid, nv, moved[i])
			if j == -1:
				continue
			var dd := nv[j].distance_to(moved[i])
			var is_bur := dd > 1e-4 and (moved[i] - nv[j]).dot(nn[j]) < 0.0
			var is_out := dd < marg[i] * 0.5 and not is_bur
			if not (is_bur or is_out):
				continue
			bad[i] = 1
			remaining += 1
			strikes[i] += 1
			if is_out:
				var diff := moved[i] - nv[j]
				var c := diff.length()
				if c > 1e-6:
					fix[i] = diff / c * (marg[i] * 0.75 - c)
				elif rad[i].length_squared() > 0.25:
					fix[i] = rad[i].normalized() * marg[i] * 0.75
			else:
				var use_n := nn[j].length_squared() > 0.25 and nn[j].dot(rad[i]) > 0.0
				var dir: Vector3 = nn[j] if use_n else rad[i]
				if dir.length_squared() > 0.25:
					fix[i] = dir.normalized() * (dd + marg[i] * 0.75)
		if remaining == 0:
			break
		for i in gv.size():
			if bad[i] == 1:
				if fix[i].length() > push_cap:
					fix[i] = fix[i].normalized() * push_cap
				deltas[i] = deltas[i] + fix[i]
				moved[i] = gv[i] + deltas[i]
	var nfrozen := 0
	for i in gv.size():
		if strikes[i] >= 3:
			nfrozen += 1
	print("[FitKit] %s%s: touchup rounds=%d remaining=%d frozen=%d" % [String(slot), "/reg" if regular_mode else "", rounds, remaining, nfrozen])
	# trap revert: ping-ponging 3+ rounds AND still bad -> vendor raw
	# (occluded folds, never needles)
	var ntraps := 0
	for i in gv.size():
		if strikes[i] < 3 or frozen[i] == 1:
			continue
		var j := _nearest(grid, nv, moved[i])
		if j == -1:
			continue
		var dd := nv[j].distance_to(moved[i])
		if (dd > 1e-4 and (moved[i] - nv[j]).dot(nn[j]) < 0.0) or dd < marg[i] * 0.5:
			deltas[i] = Vector3.ZERO
			ntraps += 1
	if ntraps > 0:
		print("[FitKit] %s: reverted traps=%d" % [String(slot), ntraps])
	# final ride (touch-up fixes are raw: couple trim, re-weld) then spike guard.
	# Neighbourhood by bind position (bake doctrine), blending live deltas.
	var ride2 := deltas.duplicate()
	for i in gv.size():
		var c := Vector3i((gv[i] / CELL).floor())
		var acc := Vector3.ZERO
		var cnt := 0
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var k := c + Vector3i(dx, dy, dz)
					if not ggrid.has(k):
						continue
					for j in (ggrid[k] as Array):
						if sx[i] * sx[j] < 0.0:
							continue
						if gv[i].distance_squared_to(gv[j]) <= rr2:
							acc += deltas[j]
							cnt += 1
		if cnt > 0:
			ride2[i] = 0.5 * deltas[i] + 0.5 * acc / cnt
	deltas = ride2
	for k in groups:
		var l: Array = groups[k]
		if l.size() > 1:
			var m := Vector3.ZERO
			for j in l:
				m += deltas[j]
			m /= l.size()
			for j in l:
				deltas[j] = m
	# lone-peak revert (needles/pyramids -> raw; buried-origin = occluded)
	var dmag := PackedFloat32Array()
	dmag.resize(gv.size())
	for i in gv.size():
		dmag[i] = deltas[i].length()
	var nspike := 0
	var peaks := []
	for i in gv.size():
		if dmag[i] <= SPIKE_MM or (adj[i] as Array).is_empty():
			continue
		var live := []
		for j in (adj[i] as Array):
			if j != i:
				live.append(dmag[j])
		if live.is_empty():
			continue
		live.sort()
		var med: float = live[live.size() / 2]
		if dmag[i] > 3.0 * maxf(med, 0.005):
			peaks.append([dmag[i], gv[i] + deltas[i]])
			deltas[i] = Vector3.ZERO
			nspike += 1
	peaks.sort()
	peaks.reverse()
	for k in mini(6, peaks.size()):
		var p: Vector3 = peaks[k][1]
		print("[FitKit] spike@%+d,%+d,%+dmm move=%.1fmm" % [int(p.x * 1000.0), int(p.y * 1000.0), int(p.z * 1000.0), float(peaks[k][0]) * 1000.0])
	# write back (global delta -> local; VERTEX only, skinning preserved).
	# One mesh per MI: fitted surfaces take their deltas, the other surfaces
	# (vendor skin in normal mode, cloth in regular mode) copy verbatim.
	# Assigning mi.mesh per surface would drop every other surface.
	var per_mi := {}
	for i in owners.size():
		var o: Array = owners[i]
		var key := str((o[0] as Node).get_instance_id()) + "|" + str(o[1])
		if not per_mi.has(key):
			per_mi[key] = [o[0], o[1], []]
		(per_mi[key][2] as Array).append([o[2], deltas[i]])
	var mi_groups := {}
	for key in per_mi:
		var e0: Array = per_mi[key]
		mi_groups[(e0[0] as Node).get_instance_id()] = e0[0]
	for mid in mi_groups:
		var mi: MeshInstance3D = mi_groups[mid]
		var m := mi.mesh as ArrayMesh
		if m == null:
			continue
		var nm := ArrayMesh.new()
		var inv := mi.global_transform.basis.inverse()
		for s in m.get_surface_count():
			var key := str(mid) + "|" + str(s)
			var a := m.surface_get_arrays(s)
			if per_mi.has(key):
				var e: Array = per_mi[key]
				a = a.duplicate()
				var vv: PackedVector3Array = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
				for pair in (e[2] as Array):
					vv[pair[0]] = vv[pair[0]] + inv * (pair[1] as Vector3)
				a[Mesh.ARRAY_VERTEX] = vv
				_strip_custom(a)
			nm.add_surface_from_arrays(m.surface_get_primitive_type(s), a)
			nm.surface_set_material(s, m.surface_get_material(s))
		mi.mesh = nm
	# final stats (signed recheck; frozen buried = occluded interiors by design)
	var b1 := 0
	var b1free := 0
	var nmoved := 0
	var mx := 0.0
	for i in gv.size():
		var l := deltas[i].length()
		if l > 1e-6:
			nmoved += 1
			mx = maxf(mx, l)
		var j := _nearest(grid, nv, gv[i] + deltas[i])
		if j != -1 and (gv[i] + deltas[i] - nv[j]).dot(nn[j]) < 0.0:
			b1 += 1
			if frozen[i] == 0:
				b1free += 1
	var ms := Time.get_ticks_msec() - t0
	print("[FitKit] %s%s: %d verts buried %d->%d (free %d) moved=%d max=%.1fmm spikes=%d %dms" % [String(slot), "/reg" if regular_mode else "", gv.size(), b0, b1, b1free, nmoved, mx * 1000.0, nspike, ms])
	stats["ok"] = true
	stats["verts"] = gv.size()
	stats["buried_before"] = b0
	stats["buried_after"] = b1
	stats["buried_free"] = b1free
	stats["moved"] = nmoved
	stats["max_push"] = mx
	stats["spikes"] = nspike
	stats["ms"] = ms
	return stats
