extends SceneTree

const CHARACTER_FILES := [
	"res://assets/meshes/characters/Superhero_Male_FullBody.gltf",
	"res://assets/meshes/characters/Superhero_Female_FullBody.gltf",
]

const ANIM_LIBRARIES := {
	"adventure": "res://assets/animations/adventure.glb",
	"aerial": "res://assets/animations/aerial.glb",
	"female": "res://assets/animations/female.glb",
	"great_sword_anim": "res://assets/animations/great_sword_anim.glb",
	"idle_torch": "res://assets/animations/idle_torch.glb",
	"sword_and_shield_anims": "res://assets/animations/sword_and_shield_anims.glb",
	"various": "res://assets/animations/various.glb",
	"various2": "res://assets/animations/various2.glb",
}


func _init() -> void:
	print("=== CHARACTERS ===")
	for path in CHARACTER_FILES:
		var scene: PackedScene = load(path)
		if scene == null:
			print("[ERROR] cannot load scene: ", path)
			continue
		var root: Node = scene.instantiate()
		var skeletons := _find_skeletons(root)
		print("\n--- ", path, " (", root.get_child_count(), " children) ---")
		if skeletons.is_empty():
			print("  NO SKELETON FOUND")
		for skel in skeletons:
			print("  Skeleton3D node: ", skel.name, ", parent chain: ", _node_path(skel, root))
			print("  bones (", skel.get_bone_count(), "):")
			for i in skel.get_bone_count():
				print("    [", i, "] ", skel.get_bone_name(i), " parent=", skel.get_bone_parent(i))
		root.free()

	print("\n=== ANIMATION LIBRARIES ===")
	for lib_name in ANIM_LIBRARIES:
		var path: String = ANIM_LIBRARIES[lib_name]
		var lib: AnimationLibrary = load(path)
		if lib == null:
			print("[ERROR] cannot load library: ", path)
			continue
		var anim_names := lib.get_animation_list()
		print("\n--- ", path, " (", anim_names.size(), " animations) ---")
		for anim_name in anim_names:
			var anim: Animation = lib.get_animation(anim_name)
			print("  [", anim_name, "] length=", anim.length, " loops=", anim.loop_mode, " tracks=", anim.get_track_count())
			for ti in min(3, anim.get_track_count()):
				print("      track ", ti, " path=", anim.track_get_path(ti), " type=", anim.track_get_type(ti))
	quit()


static func _find_skeletons(node: Node, out: Array = []) -> Array:
	for child in node.get_children():
		if child is Skeleton3D:
			out.append(child)
		_find_skeletons(child, out)
	return out


static func _node_path(node: Node, root: Node) -> String:
	var parts: Array = []
	var cur: Node = node
	while cur != root and cur != null:
		parts.push_front(cur.name)
		cur = cur.get_parent()
	return "/".join(parts)