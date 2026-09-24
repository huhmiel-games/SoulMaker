extends SceneTree

const ANIM_LIBRARIES := {
	"adventure": "res://assets/animations/adventure.glb",
	"aerial": "res://assets/animations/aerial.glb",
	"female": "res://assets/animations/female.glb",
	"great_sword": "res://assets/animations/great_sword_anim.glb",
	"idle_torch": "res://assets/animations/idle_torch.glb",
	"sword_and_shield": "res://assets/animations/sword_and_shield_anims.glb",
	"various": "res://assets/animations/various.glb",
	"various2": "res://assets/animations/various2.glb",
}


func _init() -> void:
	var total: int = 0
	var with_markers: int = 0
	for lib_name in ANIM_LIBRARIES:
		var path: String = ANIM_LIBRARIES[lib_name]
		var lib: AnimationLibrary = load(path)
		if lib == null:
			print("[ERROR] cannot load library: ", path)
			continue
		print("\n--- ", path)
		for anim_name in lib.get_animation_list():
			var anim: Animation = lib.get_animation(anim_name)
			total += 1
			var markers := anim.get_marker_names()
			if not markers.is_empty():
				with_markers += 1
				print("  [", anim_name, "] length=", "%.3f" % anim.length, " markers=", markers)
	print("\n=== summary: ", total, " animations, ", with_markers, " with markers ===")
	quit()