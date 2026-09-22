@tool
extends AnimationPlayer

## Lab-only mounter (scenes/anim_lab/anim_lab.tscn): loads the baked take
## library so the editor Animation dock lists the takes on selection —
## nothing to launch, just open the scene and scrub. Dev only. This is the
## SAME player_pack.res the game mounts: one file, one bake, lab and game
## always in sync. Re-bake when packs change:
## <godot> --headless --path . --script res://src/tools/bake_player_pack.gd
const PACK := "res://scenes/anim_lab/player_pack.res"


func _ready() -> void:
	if not has_animation_library(&"rig"):
		var lib := load(PACK) as AnimationLibrary
		if lib != null:
			add_animation_library(&"rig", lib)
