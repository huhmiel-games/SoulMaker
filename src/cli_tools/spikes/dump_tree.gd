extends SceneTree


func _initialize() -> void:
	var node: Node = (load("res://assets/meshes/characters/Superhero_Male_FullBody.gltf") as PackedScene).instantiate()
	root.add_child(node)
	_dump(node, 0)
	root.remove_child(node)
	quit()


func _dump(n: Node, depth: int) -> void:
	print("  ".repeat(depth) + n.name + " [" + n.get_class() + "]")
	for c in n.get_children():
		_dump(c, depth + 1)