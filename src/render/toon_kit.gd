class_name ToonKit
extends RefCounted

## Presentation helper (ADR-019): dresses 3D content in the base toon shader.
## Textures ship ready-made (GIMP) — original albedo textures carry through,
## tint carries the original albedo color. One ShaderMaterial per
## (texture, tint) pair, cached; defaults are the P1 look (cuts/wrap/steepness
## frozen by eye on the dungeon kit). Gizmos/selection stay standard.
## P2-ready: the game dresses characters the same way.

const BASE_TOON := preload("res://src/shaders/base_toon.gdshader")

static var _cache := {}
static var _white: Texture2D = null


## Dresses every MeshInstance3D under root (multi-surface safe). The physics
## selector and other non-mesh nodes are untouched.
static func apply_to(root: Node) -> void:
	for mi in _meshes_under(root):
		var mesh := mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var original := mi.get_surface_override_material(s)
			if original == null:
				original = mesh.surface_get_material(s)
			var tex: Texture2D = null
			var tint := Color.WHITE
			if original is StandardMaterial3D:
				tex = (original as StandardMaterial3D).albedo_texture
				tint = (original as StandardMaterial3D).albedo_color
			mi.set_surface_override_material(s, material_for(tex, tint))


## One cached material per (texture, tint). Null texture = flat tint (relief).
static func material_for(tex: Texture2D, tint: Color) -> ShaderMaterial:
	if tex == null:
		tex = _white_tex()
	var key := "%d@%s" % [tex.get_instance_id(), tint.to_html()]
	if not _cache.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = BASE_TOON
		mat.set_shader_parameter("albedo_texture", tex)
		mat.set_shader_parameter("albedo", Color(tint.r, tint.g, tint.b, 1.0))
		_cache[key] = mat
	return _cache[key]


static func _white_tex() -> Texture2D:
	if _white == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white


static func _meshes_under(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect_meshes(root, out)
	return out


static func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)
