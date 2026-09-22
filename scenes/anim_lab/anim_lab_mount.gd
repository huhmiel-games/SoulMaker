@tool
extends AnimationPlayer

## Lab-only mounter (scenes/anim_lab/anim_lab.tscn): loads the baked take
## library so the editor Animation dock lists the takes on selection —
## nothing to launch, just open the scene and scrub. Dev only, the game
## keeps loading packs at runtime. Re-bake when packs change:
## <godot> --headless --path . --script res://src/tools/bake_anim_lab.gd
const LAB_LIB := "res://scenes/anim_lab/anim_lab_lib.res"


func _ready() -> void:
	if not has_animation_library(&"rig"):
		var lib := load(LAB_LIB) as AnimationLibrary
		if lib != null:
			add_animation_library(&"rig", lib)
