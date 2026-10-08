extends SceneTree

## Face-sculpt exporter v3 (regions, 08/10): painted triangles (work file)
## -> data/characters/face_sculpt.json. MERGE semantics: painted regions
## overwrite the shipped artifact, unpainted regions are kept as-is — the run
## never wipes a hand mask. No boxes anywhere (all regions hand-painted).
## Run: <godot> --headless --path . --script res://src/cli_tools/export_face_sculpt.gd
## Regions resolve to Head-local meter POINTS (quantized 0.01mm, deduped): the
## shipped artifact carries no box and no triangle index, so Blender reimports
## (renumbered verts) cannot silently break it. Triangle indices live only in
## the authoring-local work file (scenes/tests/face_sculpt_work.json).
## Shared helpers (paintable_surfaces, head_world_of, world_of) are static so
## the interactive paint tool (face_sculpt_paint.gd, dev scene outside src/)
## enumerates byte-identical surfaces.

const NUDE_DIR := "res://assets/meshes/characters/"
const WORK_PATH := "res://scenes/tests/face_sculpt_work.json"
const OUT_PATH := "res://data/characters/face_sculpt.json"
const QUANT := 100000.0 # 0.01mm grid: float dust-proof matching both sides


func _init() -> void:
	var err := _run()
	quit(0 if err == OK else 1)


func _run() -> Error:
	var gender := "Male" # paint tool authors Male; Female gets its own pass
	var nude := nude_inst(gender)
	if nude == null:
		push_error("[FaceSculpt] cannot load nude %s" % gender)
		return ERR_CANT_OPEN
	var surfs := paintable_surfaces(nude)
	if surfs.is_empty():
		push_error("[FaceSculpt] no paintable surfaces")
		return ERR_CANT_OPEN
	var hw: Variant = head_world_of(nude)
	if hw == null:
		push_error("[FaceSculpt] no Head bone in nude")
		return ERR_CANT_OPEN
	var head_inv: Transform3D = (hw as Transform3D).affine_inverse()
	var prev: Dictionary = JsonFile.load_object(OUT_PATH)
	var psec: Dictionary = (prev.get(gender, {}) as Dictionary).get("regions", {})
	var regions := {}
	for region in psec:
		regions[String(region)] = psec[region]
	var work: Dictionary = JsonFile.load_object(WORK_PATH)
	var wsec: Dictionary = work.get(gender, {})
	var n_new := 0
	for region in wsec:
		var tris: Array = []
		for t in ((wsec[region] as Dictionary).get("tris", []) as Array):
			tris.append(t)
		if tris.is_empty():
			continue
		var pts := resolve_points(surfs, head_inv, tris)
		if pts.is_empty():
			push_error("[FaceSculpt] %s resolved 0 points" % String(region))
			return ERR_INVALID_DATA
		regions[String(region)] = {"points": pts}
		n_new += 1
		print("[FaceSculpt] %s: %d points (painted)" % [String(region), pts.size()])
	if regions.is_empty():
		push_error("[FaceSculpt] nothing to write")
		return ERR_INVALID_DATA
	if JsonFile.save_atomic(OUT_PATH, {"version": 2, gender: {"regions": regions}}) != OK:
		return ERR_FILE_CANT_WRITE
	print("[FaceSculpt] wrote %s (%s, %d regions, %d repainted)" % [OUT_PATH, gender, regions.size(), n_new])
	return OK


## Nude FullBody instance (never added to the tree: mesh arrays only).
static func nude_inst(gender: String) -> Node:
	var packed := load("%sSuperhero_%s_FullBody.gltf" % [NUDE_DIR, gender]) as PackedScene
	if packed == null:
		return null
	return packed.instantiate()


## Paintable surfaces in STABLE order (ancestor name path, then surface index):
## every skin MeshInstance except the eyeballs (brows stay: future brow rows
## paint them). Shared with the paint tool (byte-identical enumeration both
## sides). Name paths (not get_path(): nodes are out-of-tree here).
static func paintable_surfaces(inst: Node) -> Array:
	var out := []
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	var paths: Array[String] = []
	var by_path := {}
	for mi in mis:
		if String((mi as Node).name).to_lower().contains("eyes"):
			continue
		var np := _name_path(mi)
		by_path[np] = mi
		paths.append(np)
	paths.sort()
	for p in paths:
		var mi := by_path[p] as MeshInstance3D
		var mesh := mi.mesh as ArrayMesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			out.append({"mi": mi, "verts": verts, "idx": a[Mesh.ARRAY_INDEX], "normals": a[Mesh.ARRAY_NORMAL]})
	return out


## Bind-pose world transform of the Head bone (walked locals: SceneTree
## scripts run before nodes are inside the tree, so global_transform is
## unavailable). Runtime recomputes the same frame from bone rests.
static func head_world_of(inst: Node) -> Variant:
	var found := inst.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	var sk := found[0] as Skeleton3D
	var bi := sk.find_bone(&"Head")
	if bi == -1:
		return null
	return world_of(sk) * sk.get_bone_global_pose(bi)


## Ancestor name path (stable out-of-tree sort key: get_path() needs a tree).
static func _name_path(n: Node) -> String:
	var parts: PackedStringArray = []
	var cur: Node = n
	while cur != null:
		parts.append(String(cur.name))
		cur = cur.get_parent()
	parts.reverse()
	return "/".join(parts)


## Manual world transform (walk the local chain). Exact for any rigid
## authoring placement, not just origin-identity.
static func world_of(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## Tri list (pairs [surf, tri]) -> flat quantized Head-local points [x,y,z...].
static func resolve_points(surfs: Array, head_inv: Transform3D, tris: Array) -> Array:
	var seen := {}
	var pts := []
	for t in tris:
		var ta: Array = t
		var si := int(ta[0])
		var ti := int(ta[1])
		if si < 0 or si >= surfs.size():
			continue
		var e: Dictionary = surfs[si]
		var verts: PackedVector3Array = e["verts"]
		var idx: PackedInt32Array = e["idx"]
		var mi := e["mi"] as Node3D
		var wt := world_of(mi)
		for k in 3:
			var vi := ti * 3 + k
			if not idx.is_empty():
				vi = idx[ti * 3 + k]
			if vi < 0 or vi >= verts.size():
				continue
			var q: Vector3 = head_inv * (wt * verts[vi])
			var key := Vector3i(int(round(q.x * QUANT)), int(round(q.y * QUANT)), int(round(q.z * QUANT)))
			if seen.has(key):
				continue
			seen[key] = true
			pts.append([float(key.x) / QUANT, float(key.y) / QUANT, float(key.z) / QUANT])
	return pts
