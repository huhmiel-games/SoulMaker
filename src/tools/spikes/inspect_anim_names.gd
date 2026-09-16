extends SceneTree

const LIB := "res://assets/animations/sword_and_shield_anims.glb"
const LIB2 := "res://assets/animations/great_sword_anim.glb"
const LIB3 := "res://assets/animations/various.glb"
const LIB4 := "res://assets/animations/idle_torch.glb"
const LIB5 := "res://assets/animations/various2.glb"

func _init() -> void:
	for path in [LIB, LIB2, LIB3, LIB4, LIB5]:
		var lib: AnimationLibrary = load(path)
		if lib == null:
			print("ERROR ", path)
			continue
		print("\n=== ", path, " (", lib.get_animation_list().size(), ") ===")
		for name in lib.get_animation_list():
			var a: Animation = lib.get_animation(name)
			print("  ", name, "  len=", "%.2f" % a.length, " tracks=", a.get_track_count())
	quit()
