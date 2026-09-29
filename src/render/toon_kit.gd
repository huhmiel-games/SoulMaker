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
			var normal_tex: Texture2D = null
			var normal_scale := 1.0
			var orm_tex: Texture2D = null
			var orm_metallic := 1.0
			if original is StandardMaterial3D:
				tex = (original as StandardMaterial3D).albedo_texture
				tint = (original as StandardMaterial3D).albedo_color
				normal_tex = (original as StandardMaterial3D).normal_texture
				normal_scale = (original as StandardMaterial3D).normal_scale
				orm_tex = (original as StandardMaterial3D).metallic_texture
				orm_metallic = (original as StandardMaterial3D).metallic
			mi.set_surface_override_material(s, material_for(tex, tint, normal_tex, normal_scale, orm_tex, orm_metallic))


## One cached material per (texture, tint, normal, normal scale, ORM, metal
## factor). Null texture = flat tint (relief). Null normal = vertex normals
## (use_normal_map off). Null ORM = matte (use_specular off: specular is
## reserved for metal pixels, gated per-pixel by factor x ORM blue).
static func material_for(tex: Texture2D, tint: Color, normal_tex: Texture2D = null, normal_scale: float = 1.0, orm_tex: Texture2D = null, orm_metallic: float = 1.0) -> ShaderMaterial:
	if tex == null:
		tex = white_tex()
	var normal_id := 0
	if normal_tex != null:
		normal_id = normal_tex.get_instance_id()
	var orm_id := 0
	if orm_tex != null:
		orm_id = orm_tex.get_instance_id()
	var key := "%d@%s@n%d@%.3f@o%d@m%.3f" % [tex.get_instance_id(), tint.to_html(), normal_id, normal_scale, orm_id, orm_metallic]
	if not _cache.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = BASE_TOON
		mat.set_shader_parameter("albedo_texture", tex)
		mat.set_shader_parameter("albedo", Color(tint.r, tint.g, tint.b, 1.0))
		mat.set_shader_parameter("use_normal_map", normal_tex != null)
		if normal_tex != null:
			mat.set_shader_parameter("texture_normal", normal_tex)
			mat.set_shader_parameter("normal_scale", normal_scale)
		mat.set_shader_parameter("use_specular", orm_tex != null)
		mat.set_shader_parameter("use_orm_mask", orm_tex != null)
		if orm_tex != null:
			mat.set_shader_parameter("orm_texture", orm_tex)
			mat.set_shader_parameter("orm_metallic", orm_metallic)
		_cache[key] = mat
	return _cache[key]


## Shared 1x1 white (flat-tint backs albedo-less surfaces; reused by the
## color editor so albedo-less targets dress identically to ToonKit's).
static func white_tex() -> Texture2D:
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
