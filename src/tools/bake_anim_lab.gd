extends SceneTree

## Bakes the anim-lab library (scenes/anim_lab/anim_lab_lib.res): every take
## for triage in the lab (moveset packs + lab-only packs, minus hidden).
## The lab scene (anim_lab.tscn, handwritten) instances the rig and mounts
## this library on a real AnimationPlayer node for editor scrubbing. Dev only.
## Run: <godot> --headless --path . --script res://src/tools/bake_anim_lab.gd
const OUT_LIB := PlayerPackBaker.LAB_LIB_OUT


func _initialize() -> void:
	var err := PlayerPackBaker.bake_to(get_root(), OUT_LIB, "Bake")
	quit(0 if err == OK else 1)
