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
## Vendor skin ("Regular") is real skin, not cloth: conform it snug to the
## nude (small margin, tight clamp) instead of skipping it, so it serves as
## an occlusion witness where the body is. Never welded: clamp caps travel.
const REGULAR_MARGIN := 0.004
const REGULAR_CLAMP := 0.015
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


## Occlusion cover test: from each skin vert, cast taps over the outward
## hemisphere (normal + rings at 45°/75°). A tap is blocked when a garment
## vert sits within OCC_CELL_R of a march sample (OCC_STEP steps up to
## OCC_RANGE). Covered = blocked fraction >= OCC_CUT. Encircled skin (even
## under loose cloth) cuts; skin seeing open air (hems, V, bare limbs)
## stays — no hole can open past a garment edge. Only garment verts occlude,
## never the nude itself. Early-out: bare skin fails fast, covered zones pay
## the full taps.
const OCC_RING_ANGLES := [0.7853982, 1.309]
const OCC_PER_RING := 8
const OCC_RANGE := 0.06
const OCC_STEP := 0.01
const OCC_CELL := 0.04
const OCC_CELL_R := 0.025
const OCC_CUT := 0.55
## Past-end margin (rule E): skin past the cloth max extent + E_MARGIN
## (toward hands/feet) is kept — the garment ends there. Wide enough to cover
## real hem fringe (wrist band, shoe mouth, bracer transition); cmax is the
## per-chain max over ALL garments, so mid-garment poke is never past-end.
const E_MARGIN := 0.025
## Crease-joint guard radius: skin this close to a limb joint center (bind)
## is a fold/crease zone (armpits, wrist/ankle bands, elbow/knee pits), never
## mid-segment poke — exempt from the no-sky clear-behind cut.
const JOINT_R := 0.10


## Open-air guard (rule N): the normal tap escapes AND fewer than half the
## ring taps are blocked (V, garment windows, hems, bare skin) — overrides
## everything. Tight folds (walls block the ring taps) return false.
## Skyline: the straight-up ray must also escape (SKY_RANGE). Mid-garment skin
## under a loose drape (outer thighs, tibias, torso sides) escapes sideways
## past the cloth while more garment hangs above it; true openings (V,
## window, wrists, fingers, shoe mouths) see the sky. Taps see cloth only.
static func _open_air(ogrid: Dictionary, occ: PackedVector3Array, g: Vector3, sn: Vector3) -> bool:
	if _tap_blocked(ogrid, occ, g, sn):
		return false
	if _tap_blocked_range(ogrid, occ, g, Vector3.UP, SKY_RANGE):
		return false
	var dirs := _occ_dirs(sn)
	var blocked := 0
	for k in range(1, dirs.size()):
		if _tap_blocked(ogrid, occ, g, dirs[k]):
			blocked += 1
			if blocked >= OCC_PER_RING:
				return false
	return true


## Cloth max extent per chain (rule E): max bind-space projection of garment
## verts along the chain axis, chain-matched (a sleeve never extends the leg).
## Torso excluded (no E: neck/nape guarded by the Neck joint point, V by rule
## N, collar-covered chest cut by the plain tiers). Past-end limb skin is
## opening fringe: wrists, ankles, bracer transitions.
static func _cloth_extent(garment_holders: Array, master: Skeleton3D, cdata: Dictionary) -> Dictionary:
	var cmax := {}
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
					var db := _dominant_bone(a, i)
					if db < 0 or db >= master.get_bone_count():
						continue
					var chain := _chain_of_bone(String(master.get_bone_name(db)))
					if chain == "Torso" or not cdata.has(chain):
						continue
					var g: Vector3 = xf * vv[i]
					var d: Dictionary = cdata[chain]
					var t: float = (g - (d["start"] as Vector3)).dot(d["dir"] as Vector3)
					if not cmax.has(chain) or t > float(cmax[chain]):
						cmax[chain] = t
	return cmax


## True when skin sits past the cloth max extent on its limb chain.
static func _past_end(cdata: Dictionary, cmax: Dictionary, chain: String, g: Vector3) -> bool:
	if chain == "Torso" or not cdata.has(chain) or not cmax.has(chain):
		return false
	var d: Dictionary = cdata[chain]
	var t: float = (g - (d["start"] as Vector3)).dot(d["dir"] as Vector3)
	return t > float(cmax[chain]) + E_MARGIN
## Inward tier (measurement only): garment clearly INSIDE the skin (past the
## grazing tolerance) within INWARD_R counts as covering — cutting the skin
## reveals the authored garment, no fit deformation needed. Logged per ring
## (inw spans); the delete still uses the outward union until the A/B
## comparison validates the switch.
const INWARD_R := 0.06


## 1 when the nearest garment sits buried under the skin (dot past the
## outward gate, within INWARD_R), else 0. Separate nearest query from the
## cover test: _point_covered drops far indices, the inward tier needs them.
static func _point_buried(occ: PackedVector3Array, grid: Dictionary, g: Vector3, sn: Vector3) -> int:
	var j := _nearest(grid, occ, g)
	if j == -1 or occ[j].distance_to(g) > INWARD_R:
		return 0
	if (occ[j] - g).dot(sn) < -COVER_OUT:
		return 1
	return 0


static func _occ_dirs(sn: Vector3) -> Array:
	var dirs := [sn]
	var u := sn.cross(Vector3.UP)
	if u.length_squared() < 1e-8:
		u = sn.cross(Vector3.RIGHT)
	u = u.normalized()
	var w := sn.cross(u).normalized()
	for ang in OCC_RING_ANGLES:
		var ca := cos(ang)
		var sa := sin(ang)
		for k in OCC_PER_RING:
			var phi := TAU * float(k) / float(OCC_PER_RING)
			dirs.append((sn * ca + (u * cos(phi) + w * sin(phi)) * sa).normalized())
	return dirs


static func _tap_blocked(ogrid: Dictionary, occ: PackedVector3Array, g: Vector3, d: Vector3) -> bool:
	return _tap_blocked_range(ogrid, occ, g, d, OCC_RANGE)


## March-based blocked test with explicit range (skyline probe reuses it long).
static func _tap_blocked_range(ogrid: Dictionary, occ: PackedVector3Array, g: Vector3, d: Vector3, rng: float) -> bool:
	var nsteps := int(rng / OCC_STEP)
	for s in range(1, nsteps + 1):
		var p := g + d * (OCC_STEP * float(s))
		var c := Vector3i((p / OCC_CELL).floor())
		if not ogrid.has(c):
			continue
		for j in (ogrid[c] as Array):
			if occ[j].distance_to(p) <= OCC_CELL_R:
				return true
	return false


static func _occ_frac(ogrid: Dictionary, occ: PackedVector3Array, g: Vector3, sn: Vector3) -> float:
	var dirs := _occ_dirs(sn)
	var total := dirs.size()
	# Normal tap escapes = hole in the garment (open air straight out):
	# the skin shows, keep it whatever the other taps say.
	if not _tap_blocked(ogrid, occ, g, dirs[0]):
		return 0.0
	var need: int = int(ceil(OCC_CUT * float(total)))
	var blocked := 1
	var unblocked := 0
	for k in range(1, total):
		if _tap_blocked(ogrid, occ, g, dirs[k]):
			blocked += 1
		else:
			unblocked += 1
			if total - unblocked < need:
				break
	return float(blocked) / float(total)


## Behind tier (poke-through skin): cloth clearly BEHIND the skin normal
## (facing-away gate) within BEHIND_RANGE, with the skyline blocked (more
## garment above = mid-garment, not an opening). Catches skin frankly outside
## the garment (outer feet/knees/thighs, torso sides, buttocks) that proximity
## (too far), buried (out of its 60mm range) and loose (cloth ahead only) all
## miss. Opening-safe: wrists/fingers/V/window/ankles see the sky (T-pose) so
## N or the sky check exempts them before this tier can fire; past-end limbs
## are still saved by rule E afterwards.
const BEHIND_RANGE := 0.10
const BEHIND_GATE := -0.3


## Loose-drape tier (bind-pose T-pose): cloth within LOOSE_DIST clearly OUTSIDE
## along the skin normal (facing gate) counts as covering. Catches mid-garment
## skin under a loose drape (outer thighs, tibias, torso sides) that proximity
## (too far) and occlusion (taps escape beside the drape) both miss.
## V-safe by construction: up-facing normals (V bottom, collar) are exempt,
## hems/end grain fail the facing gate (cloth sits beside or behind the skin
## direction, never ahead of it), bare extremities are out of range.
const LOOSE_DIST := 0.06
const LOOSE_GATE := 0.3
const LOOSE_UP := 0.7


## Pointwise cover test shared by the vote and delete passes: cloth within
## COVER_DIST outward along (or grazing) the SKIN normal. Returns [covered, nbuy].
static func _point_covered(occ: PackedVector3Array, grid: Dictionary, g: Vector3, sn: Vector3) -> Array:
	if sn.length_squared() < 0.25:
		return [0, -1]
	var j := _nearest(grid, occ, g)
	if j == -1 or occ[j].distance_to(g) > COVER_DIST:
		return [0, -1]
	# Fold interiors diving behind the skin fail the gate and stay visible
	# (correct: no cloth covers them).
	if (occ[j] - g).dot(sn) > -COVER_OUT:
		return [1, j]
	return [0, j]


## Loose tier: nearest cloth within LOOSE_DIST, clearly ahead of the skin
## normal (facing gate), skin normal mostly horizontal (V/collar exempt).
static func _point_loose(occ: PackedVector3Array, grid: Dictionary, g: Vector3, sn: Vector3) -> int:
	if absf(sn.y) > LOOSE_UP:
		return 0
	var j := _nearest(grid, occ, g)
	if j == -1:
		return 0
	var d := occ[j].distance_to(g)
	if d <= COVER_DIST or d > LOOSE_DIST:
		return 0
	if ((occ[j] - g) / d).dot(sn) < LOOSE_GATE:
		return 0
	return 1


## Drape tier (very loose garments): cloth clearly ahead of the skin normal
## (strict gate) within DRAPE_DIST, skyline blocked (mid-garment). Catches
## fringe the 60mm tiers miss (torso sides at nipple height, buttocks under a
## wide drape). Same opening guards as loose/facing, plus mandatory blocked
## sky: V, window, wrists, fingers and ankles see the sky so N or this check
## exempts them; past-end limbs are still saved by rule E afterwards.
const DRAPE_DIST := 0.09
const DRAPE_GATE := 0.0


## Facing scan (last resort): ANY cloth within LOOSE_DIST clearly ahead of the
## skin normal (facing gate) — not just the nearest, which may graze while
## another panel faces the skin. Catches mid-distance drape the cheap tiers
## miss (torso sides, buttocks). Same opening guards as the loose tier.
static func _point_facing(occ: PackedVector3Array, grid: Dictionary, g: Vector3, sn: Vector3) -> int:
	if absf(sn.y) > LOOSE_UP:
		return 0
	var c := Vector3i((g / CELL).floor())
	for ring in [1, 2, 4]:
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				for dz in range(-ring, ring + 1):
					if ring > 1 and absi(dx) < ring and absi(dy) < ring and absi(dz) < ring:
						continue
					var k := c + Vector3i(dx, dy, dz)
					if not grid.has(k):
						continue
					for j in (grid[k] as Array):
						var d := occ[j].distance_to(g)
						if d <= COVER_DIST or d > LOOSE_DIST:
							continue
						if ((occ[j] - g) / d).dot(sn) >= LOOSE_GATE:
							return 1
	return 0


## Drape tier: any cloth within DRAPE_DIST strictly ahead of the skin normal
## (strict gate), up-normals exempt, skyline blocked (mid-garment only).
static func _point_drape(occ: PackedVector3Array, grid: Dictionary, g: Vector3, sn: Vector3, ogrid: Dictionary) -> int:
	if absf(sn.y) > LOOSE_UP:
		return 0
	var c := Vector3i((g / CELL).floor())
	for ring in [1, 2, 4]:
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				for dz in range(-ring, ring + 1):
					if ring > 1 and absi(dx) < ring and absi(dy) < ring and absi(dz) < ring:
						continue
					var k := c + Vector3i(dx, dy, dz)
					if not grid.has(k):
						continue
					for j in (grid[k] as Array):
						var d := occ[j].distance_to(g)
						if d <= COVER_DIST or d > DRAPE_DIST:
							continue
						if ((occ[j] - g) / d).dot(sn) >= DRAPE_GATE:
							if _tap_blocked_range(ogrid, occ, g, Vector3.UP, SKY_RANGE):
								return 1
							return 0
	return 0


## Limb joint centers (bind global-rest origins of every LIMB_CHAINS bone:
## shoulders/elbows/wrists, hips/knees/ankles) plus the Neck (collar ring:
## nape and upper-V rim keep the old path). Creases live at joints, poke
## lives mid-segment — the no-sky clear-behind cut exempts near-joint skin.
static func _joint_points(master: Skeleton3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for chain in LIMB_CHAINS:
		for bn in (LIMB_CHAINS[chain] as Array):
			var bi := master.find_bone(String(bn))
			if bi != -1:
				out.append(master.get_bone_global_rest(bi).origin)
	var ni := master.find_bone("Neck")
	if ni == -1:
		ni = master.find_bone("neck_01")
	if ni != -1:
		out.append(master.get_bone_global_rest(ni).origin)
	return out


## True when a bind-space point sits within JOINT_R of a limb joint center.
static func _near_joint(jpoints: PackedVector3Array, g: Vector3) -> bool:
	for j in jpoints.size():
		if jpoints[j].distance_squared_to(g) <= JOINT_R * JOINT_R:
			return true
	return false
static func _clear_behind(occ: PackedVector3Array, grid: Dictionary, g: Vector3, sn: Vector3) -> bool:
	var j := _nearest(grid, occ, g)
	if j == -1:
		return false
	var d := occ[j].distance_to(g)
	# No lower bound: clearly-behind cloth within 25mm is proximity's blind
	# spot (its gate rejects behind-cloth), not its territory.
	if d < 1e-6 or d > BEHIND_RANGE:
		return false
	return ((occ[j] - g) / d).dot(sn) <= -0.3


## Behind tier: nearest cloth within BEHIND_RANGE, clearly behind the skin
## normal (away-facing gate), skyline blocked (mid-garment, not an opening).
static func _point_behind(occ: PackedVector3Array, grid: Dictionary, g: Vector3, sn: Vector3, ogrid: Dictionary) -> int:
	if absf(sn.y) > LOOSE_UP:
		return 0
	var j := _nearest(grid, occ, g)
	if j == -1:
		return 0
	var d := occ[j].distance_to(g)
	if d <= COVER_DIST or d > BEHIND_RANGE:
		return 0
	if ((occ[j] - g) / d).dot(sn) > BEHIND_GATE:
		return 0
	if not _tap_blocked_range(ogrid, occ, g, Vector3.UP, SKY_RANGE):
		return 0
	return 1


## Skyline probe range: straight +Y world ray. True openings (V, wrists,
## fingers, shoe mouths) see the sky; mid-garment skin has more garment above
## it (tunic over thighs, thigh over calves, shoulder over torso sides). Taps
## only see the CLOTH cloud (bare skin is invisible to them).
const SKY_RANGE := 0.15


## Dense occluder points (global space): garment triangle centroids from the
## FITTED meshes. Verts alone leave holes wider than the tap radius in sparse
## garments (male pantalon 656 verts) — taps escape through the mesh and N
## keeps the skin. Centroids lie strictly INSIDE cloth triangles, so openings
## (V, hems, windows, shoe mouths) stay open: escapes through real holes are
## unaffected, leaks through sparse spans are closed.
static func _dense_occluders(garment_holders: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
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
				if a[Mesh.ARRAY_VERTEX] == null or a[Mesh.ARRAY_INDEX] == null:
					continue
				var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				for t in idx.size() / 3:
					out.append(xf * ((vv[idx[t * 3]] + vv[idx[t * 3 + 1]] + vv[idx[t * 3 + 2]]) / 3.0))
	return out


## Deletes covered nude triangles in place. garment_holders carry FITTED
## garment meshes. Returns stats {ok, tris_before, tris_after, removed}.
static func suppress_covered(nude_holder: Node, garment_holders: Array, master: Skeleton3D, do_tuck: bool = true) -> Dictionary:
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
	var dense := _dense_occluders(garment_holders)
	var occ := PackedVector3Array()
	occ.append_array(gv)
	occ.append_array(dense)
	# NOTE: the fine grid indexes the DENSE cloud (verts + centroids), so all
	# directional tiers (proximity, buried, loose, behind, facing, drape) see
	# through sparse spans exactly like the taps do. nbuy/tuck targets index
	# occ as well (centroids are valid cloth-surface points).
	var grid := _build_grid(occ)
	var ogrid := _build_occ_grid(occ)
	var cdata := _chain_data(master)
	var jpoints := _joint_points(master)
	var cmax := _cloth_extent(garment_holders, master, cdata)
	for chain in cmax:
		print("[Merge] extent %s: t_max=%.0fmm" % [String(chain), float(cmax[chain]) * 1000.0])
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
			var nkept := PackedByteArray()
			nkept.resize(vv.size())
			var esv := PackedByteArray()
			esv.resize(vv.size())
			var nbuy := PackedInt32Array()
			nbuy.resize(vv.size())
			for i in vv.size():
				nbuy[i] = -1
			var snrm := PackedVector3Array()
			snrm.resize(vv.size())
			for i in vv.size():
				var g: Vector3 = xf * vv[i]
				if g.y >= ny:
					continue
				var sn := Vector3.ZERO
				if i < an.size() and an[i].length_squared() > 0.25:
					sn = (inv_nrm * an[i]).normalized()
				if sn.length_squared() < 0.25:
					continue
				snrm[i] = sn
				var pc := _point_covered(occ, grid, g, sn)
				# Nearest cloth stays skin-side: only the tuck target
				# (kept even for open-air rims: fringe tucks under the hem).
				nbuy[i] = pc[1]
				var db2 := _dominant_bone(a, i)
				var ch2 := ""
				if db2 >= 0 and db2 < master.get_bone_count():
					ch2 = _chain_of_bone(String(master.get_bone_name(db2)))
				var cov := 0
				# Clear-behind-first (all chains): squarely-behind cloth +
				# joint-far cuts past open taps (E below still saves limbs).
				if ch2 != "" and _clear_behind(occ, grid, g, sn) and not _near_joint(jpoints, g):
					cov = 1
				elif ch2 != "" and ch2 != "Torso" and _point_buried(occ, grid, g, sn) == 1:
					# Buried-first on limbs (grazing-behind poke cuts past open
					# taps; rule E below still saves past-end skin).
					cov = 1
				elif _open_air(ogrid, occ, g, sn):
					# Rule N: open air wins, skip the tiers.
					nkept[i] = 1
					continue
				elif _point_loose(occ, grid, g, sn) == 1:
					cov = 1
				elif _point_behind(occ, grid, g, sn, ogrid) == 1:
					cov = 1
				elif _occ_frac(ogrid, occ, g, sn) >= OCC_CUT:
					cov = 1
				elif pc[0] == 1:
					cov = 1
				elif _point_buried(occ, grid, g, sn) == 1:
					cov = 1
				elif _point_facing(occ, grid, g, sn) == 1:
					cov = 1
				elif _point_drape(occ, grid, g, sn, ogrid) == 1:
					cov = 1
				if cov == 1:
					# Rule E: past the cloth end on a limb (computed only
					# for would-be cuts).
					if ch2 != "" and _past_end(cdata, cmax, ch2, g):
						cov = 0
						esv[i] = 1
				covered[i] = cov
			# Delete = tris fully occluded. Boundary follows the garment hem
			# exactly (no ring quantization); open-air fringe is kept, so no
			# hole can open past a garment edge.
			# Fringe rule: 2 covered + the uncovered vert union-kept (blind
			# spot, not a true opening) joins the cut — kills the 1-tri fringe
			# poking past the garment silhouette (nipples, buttocks). Same for
			# 1 covered when BOTH uncovered verts are union-kept (2-tri fringe).
			# Kept when any uncovered vert is opening fringe (N), past-end (E)
			# or un-testable (no valid normal).
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
				var cut_fringe := true
				for k in 3:
					var vi: int = idx[t * 3 + k]
					if covered[vi] == 1:
						continue
					if nkept[vi] == 1 or esv[vi] == 1 or snrm[vi].length_squared() < 0.25:
						cut_fringe = false
						break
				if cut_fringe:
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
				if nbuy[i] == -1 or not do_tuck:
					# Rim with no cloth in reach (or --notuck): hole too big
					# to tuck / tuck skipped, left as-is and counted.
					stats["untucked"] = int(stats.get("untucked", 0)) + 1
					continue
				var g: Vector3 = xf * vv[i]
				var target: Vector3 = occ[nbuy[i]] - snrm[i] * TUCK_UNDER
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
			var fitted := {} # surf -> fitted VERTEX array
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
					fitted[s] = vv
			if fitted.is_empty():
				continue
			# Rebuild the whole MI mesh: fitted surfaces take their verts,
			# the rest copy verbatim (per-surface assign drops surfaces).
			var nm := ArrayMesh.new()
			for s in m.get_surface_count():
				var a := m.surface_get_arrays(s)
				if fitted.has(s):
					var na := a.duplicate()
					na[Mesh.ARRAY_VERTEX] = fitted[s]
					_strip_custom(na)
					a = na
				nm.add_surface_from_arrays(m.surface_get_primitive_type(s), a)
				nm.surface_set_material(s, m.surface_get_material(s))
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


static func _build_grid(verts: PackedVector3Array, cell: float = CELL) -> Dictionary:
	var g := {}
	for i in verts.size():
		var k := Vector3i((verts[i] / cell).floor())
		if g.has(k):
			(g[k] as Array).append(i)
		else:
			g[k] = [i]
	return g


## Occluder grid: each vert is indexed in EVERY cell its OCC_CELL_R sphere
## touches (up to 8 cells for R < cell). Single-cell queries then become
## leak-proof: any garment vert within radius of a march sample is found.
## Build costs ~8x once per suppress; queries stay 1x (slightly fuller
## cells). The fine grid stays for fit/order/proximity.
static func _build_occ_grid(gv: PackedVector3Array) -> Dictionary:
	var g := {}
	var rr := Vector3.ONE * OCC_CELL_R
	for i in gv.size():
		var lo := Vector3i(((gv[i] - rr) / OCC_CELL).floor())
		var hi := Vector3i(((gv[i] + rr) / OCC_CELL).floor())
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				for cz in range(lo.z, hi.z + 1):
					var k := Vector3i(cx, cy, cz)
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


## Minimal cloth fit (push-out only): verts closer than margin are pushed OUT
## to margin (anti-z-fight + motion clearance); buried or far verts are NEVER
## touched — the authored silhouette stays intact, the inward cover tier
## reveals buried cloth instead of extracting it. Vendor skin ("Regular")
## still goes through fit_holder regular_mode (skin-tight registration).
## Returns stats {ok, verts, moved, max_push, ms}.
static func fit_pushout(holder: Node, nude: Dictionary, slot: StringName, gender: int = 0) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var stats := {"ok": false, "slot": String(slot)}
	var cfg: Array = cfg_for(slot, gender)
	if cfg.is_empty():
		stats["skipped"] = "no cfg"
		return stats
	var margin: float = cfg[4]
	var zone: Array = cfg[5]
	var nv: PackedVector3Array = nude["verts"]
	var nn: PackedVector3Array = nude["normals"]
	var gv := PackedVector3Array()
	var owners := [] # [mi, surf, local_idx]
	for mi in meshes_under(holder):
		var m := (mi as MeshInstance3D).mesh as ArrayMesh
		if m == null or m.get_blend_shape_count() > 0:
			continue
		var xf: Transform3D = (mi as MeshInstance3D).global_transform
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat != null and SKIP_SUBSTR in mat.resource_name:
				continue
			var a := m.surface_get_arrays(s)
			if a[Mesh.ARRAY_VERTEX] == null:
				continue
			var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			for i in vv.size():
				gv.append(xf * vv[i])
				owners.append([mi, s, i])
	if gv.is_empty():
		stats["skipped"] = "no verts"
		return stats
	var rad := _radial(gv, cfg[0], cfg[1], cfg[2], cfg[3])
	var grid := _build_grid(nv)
	var deltas := PackedVector3Array()
	deltas.resize(gv.size())
	var moved := 0
	var mx := 0.0
	for i in gv.size():
		var marg: float = margin
		if not zone.is_empty() and gv[i].y >= zone[0] and gv[i].y <= zone[1] and absf(gv[i].x) <= zone[2]:
			marg = zone[3]
		var j := _nearest(grid, nv, gv[i])
		if j == -1:
			continue
		var diff := gv[i] - nv[j]
		var c := diff.length()
		if c >= marg:
			continue
		var dir := Vector3.ZERO
		if c > 1e-6:
			dir = diff / c
		elif rad[i].length_squared() > 0.25:
			dir = rad[i].normalized()
		else:
			continue
		var d := dir * (marg - c)
		if d.length() > MAX_PUSH:
			d = d.normalized() * MAX_PUSH
		deltas[i] = d
		moved += 1
		mx = maxf(mx, d.length())
	var per_mi := {}
	for i in owners.size():
		var o: Array = owners[i]
		if deltas[i].length_squared() < 1e-12:
			continue
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
	stats["ok"] = true
	stats["verts"] = gv.size()
	stats["moved"] = moved
	stats["max_push"] = mx
	stats["ms"] = Time.get_ticks_msec() - t0
	print("[FitKit] %s/pushout: %d verts moved=%d max=%.1fmm %dms" % [String(slot), gv.size(), moved, mx * 1000.0, stats["ms"]])
	return stats


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
