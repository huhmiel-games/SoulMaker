extends SceneTree

## Bakes the anim-lab library (scenes/tests/anim_lab_lib.res): all moveset
## packs merged + retargeted by RigKit into one AnimationLibrary. The lab
## scene (anim_lab.tscn, handwritten) instances the rig and mounts this
## library on a real AnimationPlayer node for editor scrubbing. Dev only —
## the game keeps loading packs at runtime; re-bake when packs change.
## Run: <godot> --headless --path . --script res://src/tools/bake_anim_lab.gd
const RIG_PATH := "res://assets/meshes/characters/Superhero_Male_FullBody.gltf"
const OUT_LIB := "res://scenes/tests/anim_lab_lib.res"


func _initialize() -> void:
	var ms := Moveset.load_object()
	var packs: Dictionary = Moveset.packs_of(ms)
	var holder := Node3D.new()
	holder.name = "BakeHolder"
	get_root().add_child(holder)
	var rig: Node3D = (load(RIG_PATH) as PackedScene).instantiate()
	rig.name = "RigRoot"
	holder.add_child(rig)
	var player := RigKit.build_player(rig, packs)
	if player == null:
		print("BAKE FAIL: RigKit returned null")
		quit(1)
		return
	var libs: AnimationLibrary = player.get_animation_library("rig")
	if libs == null or libs.get_animation_list().is_empty():
		print("BAKE FAIL: empty library")
		quit(1)
		return
	if ResourceSaver.save(libs, OUT_LIB) != OK:
		print("BAKE FAIL: save failed")
		quit(1)
		return
	print("BAKE OK: %s (%d anims)" % [OUT_LIB, libs.get_animation_list().size()])
	quit(0)
