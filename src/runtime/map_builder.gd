class_name MapBuilder
extends RefCounted

## Shared map construction (P2 round-trip): the editor AND the game run
## build the same ground, placements and ambiance from the same map dict —
## one codepath, no drift. Moved verbatim from MapEditor (relief winding,
## HeightMap layout, ambiance clamps); the editor keeps its scaffold nodes,
## selectors and groups, the run assembles plain nodes.

const GROUND_LAYER := 1


## Relief mesh from the sparse {Vector2i: float} relief (flat when empty).
static func build_ground_mesh(ground: Dictionary) -> ArrayMesh:
	var n := MapIO.GROUND_N
	var v := n + 1
	var verts := PackedVector3Array()
	verts.resize(v * v)
	for iz in range(v):
		for ix in range(v):
			var c := Vector2i(clampi(ix, 0, n - 1), clampi(iz, 0, n - 1))
			var h := float(ground.get(c, 0.0))
			verts[ix + iz * v] = Vector3(ix - n * 0.5, h, iz - n * 0.5)
	# (a,b,d) + (a,d,c) per quad: clockwise seen from above = Godot front
	# (CCW renders from below only — caught 2026-09-18).
	var indices := PackedInt32Array()
	indices.resize(n * n * 6)
	var k := 0
	for cz in range(n):
		for cx in range(n):
			var a := cx + cz * v
			var b := (cx + 1) + cz * v
			var c := cx + (cz + 1) * v
			var d := (cx + 1) + (cz + 1) * v
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = d
			indices[k + 3] = a
			indices[k + 4] = d
			indices[k + 5] = c
			k += 6
	var normals := PackedVector3Array()
	normals.resize(v * v)
	for t in range(0, indices.size(), 3):
		var p0 := verts[indices[t]]
		var p1 := verts[indices[t + 1]]
		var p2 := verts[indices[t + 2]]
		# Operand order mirrors the flipped winding so normals stay +Y-up.
		var fn := (p2 - p0).cross(p1 - p0)
		normals[indices[t]] += fn
		normals[indices[t + 1]] += fn
		normals[indices[t + 2]] += fn
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, ToonKit.material_for(null, Color(0.35, 0.36, 0.4)))
	return mesh


## HeightMap collision matching the mesh above (x = ix-(w-1)/2 layout).
static func build_ground_shape(ground: Dictionary) -> HeightMapShape3D:
	var n := MapIO.GROUND_N
	var v := n + 1
	var heights := PackedFloat32Array()
	heights.resize(v * v)
	for iz in range(v):
		for ix in range(v):
			var c := Vector2i(clampi(ix, 0, n - 1), clampi(iz, 0, n - 1))
			heights[ix + iz * v] = float(ground.get(c, 0.0))
	var shape := HeightMapShape3D.new()
	shape.map_width = v
	shape.map_depth = v
	shape.map_data = heights
	return shape


## Assembled ground body (mesh + collision, toon): the run's slab. The
## editor keeps its scaffold nodes and assigns mesh/shape itself.
static func ground_node(ground: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = GROUND_LAYER
	body.collision_mask = GROUND_LAYER
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "GroundMesh"
	mesh_inst.mesh = build_ground_mesh(ground)
	body.add_child(mesh_inst)
	var shape_node := CollisionShape3D.new()
	shape_node.name = "GroundShape"
	shape_node.shape = build_ground_shape(ground)
	body.add_child(shape_node)
	return body


## One catalog asset under a fresh placement node (toon applied). Editor-only
## extras (placement group, click selector) stay with the editor — the run
## gets the asset as authored (its own collision included).
static func instantiate_prefab(packed: PackedScene, prefab_id: String, iid: String) -> Node3D:
	var placement := Node3D.new()
	placement.name = "Placement_%s" % iid
	placement.set_meta("prefab_id", prefab_id)
	placement.set_meta("instance_id", iid)
	var asset := packed.instantiate()
	placement.add_child(asset)
	# ADR-019: every 3D asset renders toon (GIMP textures carry through).
	ToonKit.apply_to(placement)
	return placement


## Placement dict transform ({position/rotation(Vector3, degrees)/scale},
## tolerant defaults) onto a node.
static func apply_node_transform(node: Node3D, t: Dictionary) -> void:
	node.position = t.get("position", Vector3.ZERO)
	node.rotation_degrees = t.get("rotation", Vector3.ZERO)
	node.scale = t.get("scale", Vector3.ONE)


## Flat ambiance dict (MapIO.AMBIANCE_DEFAULTS overlay) onto a live
## Environment + sun. Bounds single-sourced from MapIO, clamped as usual.
static func apply_ambiance(env: Environment, sun: DirectionalLight3D, amb: Dictionary, azimuth: float) -> void:
	if env == null:
		return
	var get := func(key: String) -> float:
		var bounds: Array = MapIO.AMBIANCE_BOUNDS.get(key, [0.0, 1.0])
		return clampf(float(amb.get(key, (MapIO.AMBIANCE_DEFAULTS as Dictionary).get(key, 0.0))), float(bounds[0]), float(bounds[1]))
	env.fog_enabled = bool(amb.get("fog_enabled", false))
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = get.call("fog_begin")
	env.fog_depth_end = maxf(get.call("fog_end"), env.fog_depth_begin + 1.0)
	env.fog_height = get.call("fog_height")
	env.fog_height_density = get.call("fog_hdensity")
	env.tonemap_mode = clampi(int(amb.get("tonemap_mode", 2.0)), 0, 4) as Environment.ToneMapper
	env.tonemap_exposure = get.call("tonemap_exposure")
	env.ambient_light_energy = get.call("ambient_energy")
	if sun != null:
		sun.light_energy = get.call("sun_energy")
		sun.rotation_degrees = Vector3(-get.call("sun_elev"), azimuth, 0.0)
