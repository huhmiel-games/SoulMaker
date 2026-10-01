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
	&"Legs": [0.09, -0.03, -0.09, -0.03, 0.006, [0.75, 0.98, 0.10, 0.012]],
	&"Feet": [0.11, -0.06, -0.11, -0.06, 0.008, []],
	&"Head": [0.0, 0.0, 0.0, 0.0, 0.008, []],
	&"Accessories": [0.0, 0.0, 0.0, 0.0, 0.008, []],
}
const SLOT_CFG_FEMALE := {
	&"Body": [0.0, 0.01, 0.0, 0.01, 0.008, []],
	&"Arms": [0.30, -0.07, -0.30, -0.07, 0.006, []],
	&"Legs": [0.09, -0.03, -0.09, -0.03, 0.006, [0.75, 0.98, 0.10, 0.012]],
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


## A nude vertex counts as covered when cloth passes within reach
## OUTWARD along the skin normal (nude frame: immune to stale garment
## normals after large fit moves). Straddling triangles (neckline/wrists)
## are KEPT — the fringe hides under the cloth edge, hitch irrelevant.
const COVER_DIST := 0.025
const COVER_OUT := 0.004
const SANCTUARY_SUBSTR := ["Head", "Eye", "Brow", "Hair", "Teeth", "Tongue"]
## Anatomical loop cut: skin verts vote per ring along their bone chain
## (dominant skinning bone, bind pose) instead of per-vertex. Ring width in
## meters, cut when the covered fraction reaches RING_CUT with enough votes,
## plus a 1D despeckle per chain. Boundaries are full rings — no speckle.
const RING_W := 0.015
const RING_CUT := 0.5
const RING_MIN_VOTES := 3
const LIMB_CHAINS := {
	"ArmL": ["LeftUpperArm", "LeftLowerArm", "LeftHand"],
	"ArmR": ["RightUpperArm", "RightLowerArm", "RightHand"],
	"LegL": ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"],
	"LegR": ["RightUpperLeg", "RightLowerLeg", "RightFoot"],
}
const FINGER_SUBS := ["thumb", "index", "middle", "ring", "little", "pinky"]
const TOE_SUBS := ["toe", "ball"]
## Tuck-under: kept-tri rim verts dive TUCK_UNDER below the cloth along the
## skin normal (clamped to TUCK_CLAMP) so no slit shows between the cut rim
## and the garment edge. Rim verts with no cloth in reach are left alone
## and counted (a large untucked count means the hole is too big to tuck).
const TUCK_UNDER := 0.004
const TUCK_CLAMP := 0.015
## Runtime cloth-on-cloth order (bands/gap tuned offline):
## the inner garment stays GAP inside the outer surface in the band.
const ORDER_PASS := [
	{"outer": &"Body", "inner": &"Legs", "y0": 0.85, "y1": 1.10, "gap": 0.003},
	{"outer": &"Body", "inner": &"Arms", "y0": 1.30, "y1": 1.62, "gap": 0.003},
]
## Order pair reach: beyond this the inner vert is outside the overlap
## (sleeve past the torso edge) and must be left alone — never dragged.
const ORDER_REACH := 0.015


static func _is_sanctuary(mi_name: String) -> bool:
	for s in SANCTUARY_SUBSTR:
		if mi_name.contains(s):
			return true
	return false


## Dominant skinning bone of a vertex (bind). -1 when unreadable.
static func _dominant_bone(a: Array, i: int) -> int:
	if a[Mesh.ARRAY_BONES] == null or a[Mesh.ARRAY_WEIGHTS] == null:
		return -1
	var bi: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var bw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	if i * 4 + 3 >= bi.size() or i * 4 + 3 >= bw.size():
		return -1
	var bb := -1
	var ww := 0.0
	for k in 4:
		if bi[i * 4 + k] >= 0 and bw[i * 4 + k] > ww:
			ww = bw[i * 4 + k]
			bb = bi[i * 4 + k]
	return bb


## Which anatomical chain owns a bone (master/Standard names, with UE-leaf
## fallbacks: lowercase + _l/_r suffixes). Torso is the default.
static func _chain_of_bone(bn: String) -> String:
	for chain in LIMB_CHAINS:
		if bn in (LIMB_CHAINS[chain] as Array):
			return String(chain)
	var low := bn.to_lower()
	var side := ""
	if low.begins_with("left") or low.ends_with("_l"):
		side = "L"
	elif low.begins_with("right") or low.ends_with("_r"):
		side = "R"
	if side != "":
		for f in FINGER_SUBS:
			if low.contains(f):
				return "Arm" + side
		for t in TOE_SUBS:
			if low.contains(t):
				return "Leg" + side
	return "Torso"


## Chain bind-frame data from the master skeleton: limb chains get a start
## point + unit axis (first -> last bone global-rest origin), torso uses Y.
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


## Ring key "Chain|n" for a bind-space point, or "" when unassignable.
static func _ring_key(cdata: Dictionary, chain: String, g: Vector3) -> String:
	if chain == "Torso":
		return "Torso|%d" % int(floor(g.y / RING_W))
	if not cdata.has(chain):
		return ""
	var t: float = (g - (cdata[chain] as Dictionary)["start"]).dot((cdata[chain] as Dictionary)["dir"])
	return "%s|%d" % [chain, int(floor(t / RING_W))]


## Neck-plane height from the master skeleton rest (Standard "Neck", UE
## fallback "neck_01", else a 1.35 m constant). Holders are identity so
## skeleton-space Y == global Y.
static func neck_height(master: Skeleton3D) -> float:
	if master != null:
		var bi := master.find_bone("Neck")
		if bi == -1:
			bi = master.find_bone("neck_01")
		if bi != -1:
			return master.get_bone_global_rest(bi).origin.y
	return 1.35


## Pointwise cover test shared by the vote and delete passes: cloth within
## COVER_DIST outward along (or grazing) the SKIN normal. Returns [covered, nbuy].
static func _point_covered(gv: PackedVector3Array, grid: Dictionary, g: Vector3, sn: Vector3) -> Array:
	if sn.length_squared() < 0.25:
		return [0, -1]
	var j := _nearest(grid, gv, g)
	if j == -1 or gv[j].distance_to(g) > COVER_DIST:
		return [0, -1]
	# Fold interiors diving behind the skin fail the gate and stay visible
	# (correct: no cloth covers them).
	if (gv[j] - g).dot(sn) > -COVER_OUT:
		return [1, j]
	return [0, j]


## Deletes covered nude triangles in place. garment_holders carry FITTED
## garment meshes. Returns stats {ok, tris_before, tris_after, removed}.
static func suppress_covered(nude_holder: Node, garment_holders: Array, master: Skeleton3D) -> Dictionary:
	var stats := {"ok": false, "tris_before": 0, "tris_after": 0, "removed": 0}
	var ny := neck_height(master)
	# garment cloud positions (global space). NOTE: the cover test reads the
	# NUDE normal, not the garment's — fitting displaces cloth up to ~100mm
	# while authored garment normals stay put, so the garment frame lies
	# after large moves (male torso covered 16% vs 52% female, 01/10).
	var gv := PackedVector3Array()
	for h in garment_holders:
		if h == null:
			continue
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
					gv.append(xf * vv[i])
	if gv.is_empty():
		stats["skipped"] = "no garment verts"
		return stats
	if master == null:
		stats["skipped"] = "no master (bone names needed)"
		return stats
	var grid := _build_grid(gv)
	var cdata := _chain_data(master)
	# Pass 1 — vote per ring along each bone chain (bind pose). Pointwise
	# noise dies in the majority vote; the cut becomes contiguous bands.
	var votes := {} # "Chain|n" -> [covered, total]
	for mi in meshes_under(nude_holder):
		var vmi := mi as MeshInstance3D
		var vm := vmi.mesh as ArrayMesh
		if vm == null or vm.get_blend_shape_count() > 0:
			continue
		if _is_sanctuary(String(vmi.name)):
			continue
		var vxf: Transform3D = vmi.global_transform
		var vnrm := vxf.basis.inverse().transposed()
		for s in vm.get_surface_count():
			var a := vm.surface_get_arrays(s)
			if a[Mesh.ARRAY_VERTEX] == null:
				continue
			var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var an: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in vv.size():
				var g: Vector3 = vxf * vv[i]
				if g.y >= ny:
					continue
				var sn := Vector3.ZERO
				if i < an.size() and an[i].length_squared() > 0.25:
					sn = (vnrm * an[i]).normalized()
				if sn.length_squared() < 0.25:
					continue
				var db := _dominant_bone(a, i)
				if db < 0 or db >= master.get_bone_count():
					continue
				var rk := _ring_key(cdata, _chain_of_bone(String(master.get_bone_name(db))), g)
				if rk.is_empty():
					continue
				var pc := _point_covered(gv, grid, g, sn)
				if votes.has(rk):
					(votes[rk] as Array)[0] += pc[0]
					(votes[rk] as Array)[1] += 1
				else:
					votes[rk] = [pc[0], 1]
	var cut := {}
	for rk in votes:
		var v: Array = votes[rk]
		if v[1] >= RING_MIN_VOTES and float(v[0]) >= RING_CUT * float(v[1]):
			cut[rk] = 1
	# 1D despeckle per chain: isolated cut/kept rings flip to their neighbours.
	var by_chain := {}
	for rk in votes:
		var parts := String(rk).split("|")
		if parts.size() != 2:
			continue
		if not by_chain.has(parts[0]):
			by_chain[parts[0]] = []
		(by_chain[parts[0]] as Array).append([int(parts[1]), cut.has(rk)])
	for chain in by_chain:
		var arr: Array = by_chain[chain]
		arr.sort_custom(func(a, b): return a[0] < b[0])
		for k in arr.size():
			var is_cut: bool = arr[k][1]
			var prev: bool = arr[k - 1][1] if k > 0 else is_cut
			var nxt: bool = arr[k + 1][1] if k + 1 < arr.size() else is_cut
			var want := (prev or nxt) if is_cut else (prev and nxt)
			if want != is_cut:
				arr[k][1] = want
				var key := "%s|%d" % [String(chain), int(arr[k][0])]
				if want:
					cut[key] = 1
				else:
					cut.erase(key)
	# Cut intervals per chain for the headless log.
	for chain in by_chain:
		var arr: Array = by_chain[chain]
		var spans := []
		var open := -1
		for k in arr.size():
			if arr[k][1] and open == -1:
				open = int(arr[k][0])
			if (not arr[k][1] or k == arr.size() - 1) and open != -1:
				var last: int = int(arr[k - 1][0]) if not arr[k][1] else int(arr[k][0])
				spans.append("[%d..%d]" % [open, last])
				open = -1
		if not spans.is_empty():
			print("[Merge] cut %s: %s" % [String(chain), " ".join(spans)])
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
			var an: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var inv_nrm := xf.basis.inverse().transposed()
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
			var nbuy := PackedInt32Array()
			nbuy.resize(vv.size())
			for i in vv.size():
				nbuy[i] = -1
			var snrm := PackedVector3Array()
			snrm.resize(vv.size())
			var vring := []
			vring.resize(vv.size())
			for i in vv.size():
				vring[i] = ""
				var g: Vector3 = xf * vv[i]
				if g.y >= ny:
					continue
				var sn := Vector3.ZERO
				if i < an.size() and an[i].length_squared() > 0.25:
					sn = (inv_nrm * an[i]).normalized()
				if sn.length_squared() < 0.25:
					continue
				snrm[i] = sn
				var pc := _point_covered(gv, grid, g, sn)
				covered[i] = pc[0]
				nbuy[i] = pc[1]
				var db := _dominant_bone(a, i)
				if db < 0 or db >= master.get_bone_count():
					continue
				var rk := _ring_key(cdata, _chain_of_bone(String(master.get_bone_name(db))), g)
				if cut.has(rk):
					vring[i] = rk
			# Delete = tris fully inside cut rings. Boundaries are ring
			# loops by construction — no tri-level speckle possible.
			var ntris := idx.size() / 3
			var del := PackedByteArray()
			del.resize(ntris)
			for t in ntris:
				if String(vring[idx[t * 3]]).is_empty():
					continue
				if String(vring[idx[t * 3 + 1]]).is_empty():
					continue
				if String(vring[idx[t * 3 + 2]]).is_empty():
					continue
				del[t] = 1
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
			# Rim = uncovered verts of kept tris touching the cut. Tuck them
			# under the cloth (idempotent per vert: same nearest + normal).
			var vv2 := (vv as PackedVector3Array).duplicate()
			var rim_marks := PackedByteArray()
			rim_marks.resize(vv.size())
			for t in ntris:
				if del[t] == 1:
					continue
				var touches := false
				for k in 3:
					var e0: int = idx[t * 3 + k]
					var e1: int = idx[t * 3 + (k + 1) % 3]
					for nt in (edge_map[Vector2i(mini(e0, e1), maxi(e0, e1))] as Array):
						if del[nt] == 1:
							touches = true
							break
					if touches:
						break
				if not touches:
					continue
				for k in 3:
					var vi: int = idx[t * 3 + k]
					if covered[vi] == 0:
						rim_marks[vi] = 1
			for i in vv.size():
				if rim_marks[i] != 1:
					continue
				if nbuy[i] == -1:
					# Rim with no cloth in reach: hole too big to tuck,
					# left as-is and counted for the recipe.
					stats["untucked"] = int(stats.get("untucked", 0)) + 1
					continue
				var g: Vector3 = xf * vv[i]
				var target: Vector3 = gv[nbuy[i]] - snrm[i] * TUCK_UNDER
				var d := target - g
				if d.length() > TUCK_CLAMP:
					d = d.normalized() * TUCK_CLAMP
				stats["tucked"] = int(stats.get("tucked", 0)) + 1
				stats["tuck_max"] = maxf(float(stats.get("tuck_max", 0.0)), d.length())
				vv2[i] = xf.affine_inverse() * (g + d)
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
	print("[Merge] nude tris %d->%d (removed %d, tucked %d untucked %d tuck_max %.1fmm, neck_y=%.3f)" % [tb, ta, tb - ta, int(stats.get("tucked", 0)), int(stats.get("untucked", 0)), float(stats.get("tuck_max", 0.0)) * 1000.0, ny])
	return stats


## Runtime cloth-on-cloth order: in each ORDER_PASS band the inner garment is
## pushed GAP inside the outer surface along the outer normal (VERTEX only,
## clamped to MAX_PUSH). holders: Dictionary slot -> holder node.
## Returns {ok, pairs: [{name, moved, max_mm}]}.
static func order_pass(holders: Dictionary) -> Dictionary:
	var stats := {"ok": true, "pairs": []}
	for e in ORDER_PASS:
		var outer_h: Node = holders.get(e["outer"])
		var inner_h: Node = holders.get(e["inner"])
		var pname := "%s_over_%s" % [String(e["outer"]), String(e["inner"])]
		if outer_h == null or inner_h == null:
			continue
		var y0: float = e["y0"]
		var y1: float = e["y1"]
		var gap: float = e["gap"]
		var ov := PackedVector3Array()
		var on := PackedVector3Array()
		for mi in meshes_under(outer_h):
			var m := (mi as MeshInstance3D).mesh as ArrayMesh
			if m == null or m.get_blend_shape_count() > 0:
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
					var g: Vector3 = xf * vv[i]
					if g.y < y0 or g.y > y1:
						continue
					ov.append(g)
					if i < an.size() and an[i].length_squared() > 0.25:
						on.append((nrm * an[i]).normalized())
					else:
						on.append(Vector3.ZERO)
		if ov.is_empty():
			continue
		var grid := _build_grid(ov)
		var moved := 0
		var mx := 0.0
		for mi in meshes_under(inner_h):
			var mmi := mi as MeshInstance3D
			var m := mmi.mesh as ArrayMesh
			if m == null or m.get_blend_shape_count() > 0:
				continue
			var xf: Transform3D = mmi.global_transform
			var inv := xf.affine_inverse()
			for s in m.get_surface_count():
				var a := m.surface_get_arrays(s)
				if a[Mesh.ARRAY_VERTEX] == null:
					continue
				var vv: PackedVector3Array = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
				var dirty := false
				for i in vv.size():
					var g: Vector3 = xf * vv[i]
					if g.y < y0 or g.y > y1:
						continue
					var j := _nearest(grid, ov, g)
					if j == -1 or on[j].length_squared() < 0.25:
						continue
					if ov[j].distance_to(g) > ORDER_REACH:
						continue
					var d := (g - ov[j]).dot(on[j])
					if d > -gap:
						var push: Vector3 = on[j] * (-(d + gap))
						if push.length() > MAX_PUSH:
							push = push.normalized() * MAX_PUSH
						vv[i] = inv * (g + push)
						dirty = true
						moved += 1
						mx = maxf(mx, push.length())
				if dirty:
					var na := a.duplicate()
					na[Mesh.ARRAY_VERTEX] = vv
					_strip_custom(na)
					var nm := ArrayMesh.new()
					nm.add_surface_from_arrays(m.surface_get_primitive_type(s), na)
					nm.surface_set_material(0, m.surface_get_material(s))
					mmi.mesh = nm
		(stats["pairs"] as Array).append({"name": pname, "moved": moved, "max_mm": mx * 1000.0})
		print("[Merge] order %s: moved=%d max=%.1fmm" % [pname, moved, mx * 1000.0])
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


static func _build_grid(verts: PackedVector3Array) -> Dictionary:
	var g := {}
	for i in verts.size():
		var k := Vector3i((verts[i] / CELL).floor())
		if g.has(k):
			(g[k] as Array).append(i)
		else:
			g[k] = [i]
	return g


static func _nearest(g: Dictionary, verts: PackedVector3Array, q: Vector3) -> int:
	var c := Vector3i((q / CELL).floor())
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
## Returns stats {ok, verts, buried_before, buried_after, moved, max_push, ms}.
static func fit_holder(holder: Node, nude: Dictionary, slot: StringName, gender: int = 0) -> Dictionary:
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
	var margin: float = cfg[4]
	var zone: Array = cfg[5]
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
			if mat != null and SKIP_SUBSTR in mat.resource_name:
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
		if deltas[i].length() > MAX_PUSH:
			deltas[i] = deltas[i].normalized() * MAX_PUSH
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
				if fix[i].length() > MAX_PUSH:
					fix[i] = fix[i].normalized() * MAX_PUSH
				deltas[i] = deltas[i] + fix[i]
				moved[i] = gv[i] + deltas[i]
	var nfrozen := 0
	for i in gv.size():
		if strikes[i] >= 3:
			nfrozen += 1
	print("[FitKit] %s: touchup rounds=%d remaining=%d frozen=%d" % [String(slot), rounds, remaining, nfrozen])
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
	# write back (global delta -> local; VERTEX only, skinning preserved)
	var per_mi := {}
	for i in owners.size():
		var o: Array = owners[i]
		var key := str((o[0] as Node).get_instance_id()) + "|" + str(o[1])
		if not per_mi.has(key):
			per_mi[key] = [o[0], o[1], []]
		(per_mi[key][2] as Array).append([o[2], deltas[i]])
	for key in per_mi:
		var e: Array = per_mi[key]
		var mi: MeshInstance3D = e[0]
		var s: int = e[1]
		var m := mi.mesh as ArrayMesh
		if m == null:
			continue
		var a := m.surface_get_arrays(s)
		var vv: PackedVector3Array = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		var inv := mi.global_transform.basis.inverse()
		for pair in (e[2] as Array):
			vv[pair[0]] = vv[pair[0]] + inv * (pair[1] as Vector3)
		a[Mesh.ARRAY_VERTEX] = vv
		var nm := ArrayMesh.new()
		nm.add_surface_from_arrays(m.surface_get_primitive_type(s), a)
		nm.surface_set_material(0, m.surface_get_material(s))
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
	print("[FitKit] %s: %d verts buried %d->%d (free %d) moved=%d max=%.1fmm spikes=%d %dms" % [String(slot), gv.size(), b0, b1, b1free, nmoved, mx * 1000.0, nspike, ms])
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
