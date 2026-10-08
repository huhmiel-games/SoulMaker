extends SceneTree

## One-shot exporter: face-sculpt boxes authored in
## scenes/tests/face_sculpt_author.tscn -> data/characters/face_sculpt.json.
## Run: <godot> --headless --path . --script res://src/cli_tools/export_face_sculpt.gd
## Reads each SculptBoxes child (MeshInstance3D + BoxMesh, world/world-aligned
## T-pose authoring) and stores center/size in HEAD-LOCAL meters, using the
## nude bind-pose Head bone as the frame (runtime recomputes the same frame,
## so the user never touches a number). taper_top narrows the XZ influence
## from box bottom (1.0) to box top (nose bridge must spare the eyes).
## The authoring scene is throwaway; the JSON is the shipped artifact.

const AUTHOR_SCENE := "res://scenes/tests/face_sculpt_author.tscn"
const NUDE_DIR := "res://assets/meshes/characters/"
const OUT_PATH := "res://data/characters/face_sculpt.json"
const TAPER := {"Nose": 0.45, "Mouth": 1.0, "Chin": 1.0}


func _init() -> void:
	var err := _run()
	quit(0 if err == OK else 1)


func _run() -> Error:
	var ps := load(AUTHOR_SCENE) as PackedScene
	if ps == null:
		push_error("[FaceSculpt] cannot load %s" % AUTHOR_SCENE)
		return ERR_CANT_OPEN
	var author := ps.instantiate()
	var holder := author.get_node_or_null("SculptBoxes")
	if holder == null:
		push_error("[FaceSculpt] SculptBoxes missing")
		return ERR_CANT_OPEN
	var gender := "Male" # authoring scene previews Male; Female gets its own pass
	var hw: Variant = _head_bind_world(gender)
	if hw == null:
		push_error("[FaceSculpt] no Head bone in nude")
		return ERR_CANT_OPEN
	var head_inv: Transform3D = (hw as Transform3D).affine_inverse()
	var boxes := {}
	for b in holder.get_children():
		var mi := b as MeshInstance3D
		if mi == null or not (mi.mesh is BoxMesh):
			continue
		var wt: Transform3D = _world_of(mi)
		var size: Vector3 = (mi.mesh as BoxMesh).size
		var c_local: Vector3 = head_inv * wt.origin
		var half_world: Vector3 = wt.basis * (size * 0.5)
		var half_local: Vector3 = head_inv.basis * half_world
		var size_local := Vector3(absf(half_local.x), absf(half_local.y), absf(half_local.z)) * 2.0
		boxes[String(mi.name)] = {
			"center": [c_local.x, c_local.y, c_local.z],
			"size": [size_local.x, size_local.y, size_local.z],
			"taper_top": float(TAPER.get(String(mi.name), 1.0)),
		}
		print("[FaceSculpt] %s center=%s size=%s" % [String(mi.name), str(c_local), str(size_local)])
	if boxes.is_empty():
		push_error("[FaceSculpt] no boxes found")
		return ERR_CANT_OPEN
	var prev: Dictionary = JsonFile.load_object(OUT_PATH)
	if prev.is_empty():
		prev = {"version": 1}
	prev[gender] = {"boxes": boxes}
	if JsonFile.save_atomic(OUT_PATH, prev) != OK:
		return ERR_FILE_CANT_WRITE
	print("[FaceSculpt] wrote %s (%s, %d boxes)" % [OUT_PATH, gender, boxes.size()])
	return OK


## Manual world transform (walk the local chain): SceneTree scripts run before
## nodes are inside the tree, so global_transform is unavailable. Exact for
## any rigid authoring placement, not just origin-identity.
func _world_of(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## Bind-pose world transform of the Head bone (walked, same reason).
func _head_bind_world(gender: String) -> Variant:
	var packed := load("%sSuperhero_%s_FullBody.gltf" % [NUDE_DIR, gender]) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate()
	var found := inst.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	var sk := found[0] as Skeleton3D
	var bi := sk.find_bone(&"Head")
	if bi == -1:
		return null
	return _world_of(sk) * sk.get_bone_global_pose(bi)
