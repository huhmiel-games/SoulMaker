class_name MapEditor
extends Control

## P1 map editor controller (unit 1): the minimal maker loop.
## Place an asset (catalog click) → move it (arrow keys + transform fields) →
## save/reload a versioned JSON map → one-key playtest (free-fly camera).
## The DebugLabel mirrors every state change with a matching print() line.

signal map_saved(path: String)
signal map_loaded(path: String)

const PLACEMENT_GROUP := "placement"
const SELECTOR_GROUP := "placement_selector"
const SELECTOR_LAYER := 2
const GROUND_LAYER := 1
const SELECT_MASK := GROUND_LAYER | SELECTOR_LAYER
const MAPS_DIR := "user://maps"

const MOVE_STEP := 0.25
const MOVE_FINE := 0.05

## Attach points (must exist in the scene scaffold).
@onready var world_viewport: SubViewport = get_node("ViewportContainer/WorldViewport")
@onready var placement_root: Node3D = get_node("ViewportContainer/WorldViewport/Placements")
@onready var editor_camera: OrbitCamera = get_node("ViewportContainer/WorldViewport/EditorCamera")
@onready var play_camera: FlyCamera = get_node("ViewportContainer/WorldViewport/PlayCamera")
@onready var selection_box: MeshInstance3D = get_node("ViewportContainer/WorldViewport/SelectionBox")
@onready var catalog_panel: CatalogPanel = get_node("CatalogPanel")
@onready var debug_label: Label = get_node("DebugLabel")
@onready var toolbar: Control = get_node("ToolBar")
@onready var transform_panel: Control = get_node("TransformPanel")

# Toolbar widgets.
@onready var map_name_edit: LineEdit = get_node("ToolBar/MapName")
@onready var save_button: Button = get_node("ToolBar/SaveButton")
@onready var load_button: Button = get_node("ToolBar/LoadButton")
@onready var load_selector: OptionButton = get_node("ToolBar/LoadSelector")
@onready var delete_button: Button = get_node("ToolBar/DeleteButton")
@onready var play_button: Button = get_node("ToolBar/PlayButton")

# Transform panel rows (each HBox holds 3 SpinBoxes: X, Y, Z).
@onready var position_row: HBoxContainer = get_node("TransformPanel/PositionRow")
@onready var rotation_row: HBoxContainer = get_node("TransformPanel/RotationRow")
@onready var scale_row: HBoxContainer = get_node("TransformPanel/ScaleRow")

var catalog := Catalog.new()
var _placements: Array[Dictionary] = []
var _selected: Node3D = null
var _updating_fields := false
var _playtest_active := false


func _ready() -> void:
	var load_err := catalog.load()
	if load_err != OK:
		_set_status("FATAL: catalog not readable")
		return
	var issues := catalog.validate()
	refill_catalog()
	for issue in issues:
		_set_status("catalog issue: %s" % issue)
	_refresh_saved_maps()
	_set_status("editor ready — click an asset to place it")

	catalog_panel.asset_selected.connect(_on_asset_selected)
	InputManager.action_pressed.connect(_on_input_action)
	InputManager.set_profile(&"editor")
	save_button.pressed.connect(save_map)
	load_button.pressed.connect(_on_load)
	delete_button.pressed.connect(_delete_selection)
	play_button.pressed.connect(toggle_playtest)

	for row in [position_row, rotation_row, scale_row]:
		for spin in row.get_children():
			if spin is SpinBox:
				spin.value_changed.connect(func(_v: float) -> void: _on_field_changed())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not _playtest_active:
			_pick_at_screen(world_viewport.get_mouse_position())


func _process(_delta: float) -> void:
	if _playtest_active or _selected == null:
		return
	var step: float = MOVE_FINE if InputManager.is_pressed(&"fine_mode") else MOVE_STEP
	if InputManager.is_pressed(&"nudge_x_neg"):
		_nudge_selection(Vector3(-step, 0.0, 0.0))
	elif InputManager.is_pressed(&"nudge_x_pos"):
		_nudge_selection(Vector3(step, 0.0, 0.0))
	elif InputManager.is_pressed(&"nudge_z_neg"):
		_nudge_selection(Vector3(0.0, 0.0, -step))
	elif InputManager.is_pressed(&"nudge_z_pos"):
		_nudge_selection(Vector3(0.0, 0.0, step))
	elif InputManager.is_pressed(&"nudge_y_pos"):
		_nudge_selection(Vector3(0.0, step, 0.0))
	elif InputManager.is_pressed(&"nudge_y_neg"):
		_nudge_selection(Vector3(0.0, -step, 0.0))


## ── catalog & placement ────────────────────────────────────────────────

func refill_catalog() -> void:
	catalog_panel.populate(catalog)


func _on_asset_selected(id: String) -> void:
	if _playtest_active:
		return
	var scene_path := catalog.resolve_scene_path(id)
	if scene_path.is_empty():
		_set_status("no scene file for %s" % id)
		return
	var packed: PackedScene = ResourceLoader.load(scene_path)
	if packed == null:
		_set_status("cannot load %s" % scene_path)
		return
	var iid := "inst_%04d" % _placements.size()
	var placement := _instance_placement(packed, id, iid)
	var spot := _spawn_point()
	placement.position = spot
	_move_asset_to_ground(placement)
	_select(placement)
	_set_placement_data(placement)
	_set_status("spawned %s (%s) — placed: %d" % [id, iid, _placements.size()])


## Instances one catalog scene under a fresh placement node + a physics
## selector (AABB box) used for click-picking later.
func _instance_placement(packed: PackedScene, id: String, iid: String) -> Node3D:
	var placement := Node3D.new()
	placement.name = "Placement_%s" % iid
	placement.add_to_group(PLACEMENT_GROUP)
	placement.set_meta("prefab_id", id)
	placement.set_meta("instance_id", iid)
	placement_root.add_child(placement)

	var asset := packed.instantiate()
	placement.add_child(asset)

	var box: AABB = _find_mesh_aabb(placement)
	var selector := StaticBody3D.new()
	selector.name = "Selector"
	selector.collision_layer = SELECTOR_LAYER
	selector.collision_mask = 0
	selector.add_to_group(SELECTOR_GROUP)
	var shape_node := CollisionShape3D.new()
	shape_node.name = "SelectorShape"
	var shape := BoxShape3D.new()
	shape.size = box.size
	shape_node.shape = shape
	shape_node.position = box.position + box.size * 0.5
	selector.add_child(shape_node)
	placement.add_child(selector)

	_placements.append(_placement_entry(placement))
	return placement


## ── selection ──────────────────────────────────────────────────────────

func _pick_at_screen(screen_pos: Vector2) -> void:
	var placement := _pick_placement_at_screen(screen_pos)
	if placement != null:
		_select(placement)
		_refresh_debug()
		return
	var origin := editor_camera.project_ray_origin(screen_pos)
	var dir := editor_camera.project_ray_normal(screen_pos)
	var space := world_viewport.world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 1000.0, SELECT_MASK)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var collider: Node = hit.get("collider")
		if collider != null and collider.is_in_group("ground"):
			_select(null)
			_refresh_debug()
			return
	_set_status("miss (empty space)")


## Gamepad (A) fallback: selects whichever placement the camera center hits,
## otherwise places the current catalog entry at the spawn point.
func _place_or_select() -> void:
	var center := world_viewport.get_visible_rect().size * 0.5
	var placement := _pick_placement_at_screen(center)
	if placement != null:
		_select(placement)
		_refresh_debug()
		return
	var id := catalog_panel.current_id
	if id.is_empty():
		_set_status("no catalog entry to place")
		return
	_on_asset_selected(id)


func _pick_placement_at_screen(screen_pos: Vector2) -> Node3D:
	var origin := editor_camera.project_ray_origin(screen_pos)
	var dir := editor_camera.project_ray_normal(screen_pos)
	var space := world_viewport.world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 1000.0, SELECT_MASK)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Node = hit.get("collider")
	if collider != null and collider.is_in_group(SELECTOR_GROUP):
		var placement := collider.get_parent() as Node3D
		if placement != null and placement.is_in_group(PLACEMENT_GROUP):
			return placement
	return null


func _select(placement: Node3D) -> void:
	_selected = placement
	_sync_fields_from_selection()
	_update_selection_visual()


func _update_selection_visual() -> void:
	if _selected == null:
		selection_box.visible = false
		return
	var box: AABB = _find_mesh_aabb(_selected)
	selection_box.visible = true
	selection_box.position = box.position + box.size * 0.5
	var mat := selection_box.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color.a = 0.25
	var mesh := selection_box.mesh as BoxMesh
	if mesh:
		mesh.size = box.size


## ── transform ──────────────────────────────────────────────────────────

func _nudge_selection(delta: Vector3) -> void:
	if _selected == null:
		return
	_selected.position += delta
	_apply_placement_transform(_selected)


func _on_field_changed() -> void:
	if _updating_fields or _selected == null:
		return
	var pos := _spin_values(position_row)
	var rot := _spin_values(rotation_row)
	var scl := _spin_values(scale_row)
	_selected.position = Vector3(pos)
	_selected.rotation_degrees = Vector3(rot)
	_selected.scale = Vector3(scl)
	_apply_placement_transform(_selected)


func _sync_fields_from_selection() -> void:
	_updating_fields = true
	if _selected == null:
		return
	_set_spin_values(position_row, _selected.position)
	_set_spin_values(rotation_row, _selected.rotation_degrees)
	_set_spin_values(scale_row, _selected.scale)
	_updating_fields = false


func _spin_values(row: HBoxContainer) -> Vector3:
	var i: int = 0
	var out := Vector3.ZERO
	for child in row.get_children():
		if child is SpinBox and i < 3:
			out[i] = (child as SpinBox).value
			i += 1
	return out


func _set_spin_values(row: HBoxContainer, v: Vector3) -> void:
	var i: int = 0
	for child in row.get_children():
		if child is SpinBox and i < 3:
			(child as SpinBox).value = v[i]
			i += 1


func _apply_placement_transform(placement: Node3D) -> void:
	_update_selection_visual()
	_set_placement_data(placement)
	_refresh_debug()


## ── delete / clear ─────────────────────────────────────────────────────

func _delete_selection() -> void:
	if _selected == null:
		_set_status("nothing selected to delete")
		return
	var iid := String(_selected.get_meta("instance_id", ""))
	for i in range(_placements.size() - 1, -1, -1):
		if _placements[i].get("instance_id") == iid:
			_placements.remove_at(i)
	_selected.queue_free()
	_selected = null
	_update_selection_visual()
	_sync_fields_from_selection()
	_set_status("deleted %s — placed: %d" % [iid, _placements.size()])


func _clear_all() -> void:
	for child in placement_root.get_children():
		child.queue_free()
	_placements.clear()
	_selected = null
	_update_selection_visual()


## ── save / load ────────────────────────────────────────────────────────

func _map_path(name: String) -> String:
	return MAPS_DIR.path_join("%s.json" % name)


func save_map() -> void:
	var name := map_name_edit.text.strip_edges()
	if name.is_empty():
		_set_status("save aborted: empty map name")
		return
	var data := MapIO.serialize(name, _placements)
	var issues := MapIO.validate_map(data)
	issues.append_array(MapIO.validate_refs(data, catalog))
	if not issues.is_empty():
		_set_status("SAVE ISSUES: %s" % ", ".join(issues))
		return
	var err := JsonFile.save_atomic(_map_path(name), data)
	if err != OK:
		_set_status("save FAILED (%d)" % err)
		return
	map_saved.emit(_map_path(name))
	_refresh_saved_maps()
	_set_status("saved %s (%d placements)" % [name, _placements.size()])


func _on_load() -> void:
	var name := load_selector.get_item_text(load_selector.selected)
	if name.is_empty():
		_set_status("load aborted: no map chosen")
		return
	load_map(name)


func load_map(name: String) -> void:
	var path := _map_path(name)
	var data := JsonFile.load_object(path)
	if data.is_empty():
		_set_status("cannot load %s (missing or corrupt)" % path)
		_refresh_saved_maps()
		return
	var issues := MapIO.validate_map(data)
	issues.append_array(MapIO.validate_refs(data, catalog))
	_clear_all()
	for placement in MapIO.deserialize(data):
		_instance_from_data(placement)
	if not issues.is_empty():
		for issue in issues:
			_set_status("LOAD ISSUE: %s" % issue)
	map_loaded.emit(path)
	map_name_edit.text = name
	_set_status("loaded %s — placed: %d %s" % [name, _placements.size(), "(issues above)" if not issues.is_empty() else ""])


func _instance_from_data(placement: Dictionary) -> void:
	var id: String = str(placement.get("prefab_id", ""))
	var iid: String = str(placement.get("instance_id", ""))
	var scene_path := catalog.resolve_scene_path(id)
	if scene_path.is_empty():
		_set_status("cannot resolve %s" % id)
		return
	var packed: PackedScene = ResourceLoader.load(scene_path)
	if packed == null:
		return
	var node := _instance_placement(packed, id, iid)
	var t: Dictionary = placement.get("transform", {})
	node.position = t.get("position", Vector3.ZERO)
	node.rotation_degrees = t.get("rotation", Vector3.ZERO)
	node.scale = t.get("scale", Vector3.ONE)
	_apply_placement_transform(node)


func _refresh_saved_maps() -> void:
	var dir := DirAccess.open(MAPS_DIR)
	var names: PackedStringArray = []
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".json"):
				names.append(f.get_basename())
	names.sort()
	load_selector.clear()
	for n in names:
		load_selector.add_item(n)
	load_selector.disabled = names.is_empty()
	load_button.disabled = names.is_empty()


## ── playtest ───────────────────────────────────────────────────────────

func toggle_playtest() -> void:
	_playtest_active = not _playtest_active
	InputManager.set_profile(&"playtest" if _playtest_active else &"editor")
	if _playtest_active:
		play_camera.global_position = editor_camera.global_position
		play_camera.rotation = editor_camera.rotation
	editor_camera.current = not _playtest_active
	play_camera.current = _playtest_active
	play_camera.set_capture(_playtest_active)
	toolbar.visible = not _playtest_active
	transform_panel.visible = not _playtest_active
	catalog_panel.visible = not _playtest_active
	play_button.text = "Stop" if _playtest_active else "Play"
	_selected = null
	_update_selection_visual()
	_set_status("PLAYTEST %s — WASD to move, mouse to look, P to leave" % ("ON" if _playtest_active else "OFF"))


## ── helpers ────────────────────────────────────────────────────────────

func _on_input_action(action: StringName) -> void:
	match action:
		&"playtest":
			toggle_playtest()
		&"quick_save":
			if not _playtest_active:
				save_map()
		&"load_map":
			if not _playtest_active:
				_on_load()
		&"delete":
			if not _playtest_active:
				_delete_selection()
		&"catalog_next":
			if not _playtest_active:
				catalog_panel.cycle_next()
		&"catalog_prev":
			if not _playtest_active:
				catalog_panel.cycle_prev()
		&"place_select":
			if not _playtest_active:
				_place_or_select()
		&"deselect":
			if not _playtest_active:
				_select(null)
				_refresh_debug()


func _placement_entry(placement: Node3D) -> Dictionary:
	return {
		"prefab_id": str(placement.get_meta("prefab_id", "")),
		"instance_id": str(placement.get_meta("instance_id", "")),
		"transform": {
			"position": placement.position,
			"rotation": placement.rotation_degrees,
			"scale": placement.scale,
		},
	}


func _set_placement_data(placement: Node3D) -> void:
	for i in range(_placements.size()):
		if _placements[i].get("instance_id") == placement.get_meta("instance_id"):
			_placements[i] = _placement_entry(placement)
			return


func _spawn_point() -> Vector3:
	var origin := editor_camera.global_position
	var dir := -editor_camera.global_basis.z
	var spot: Variant = _plane_hit(origin, dir, 0.0)
	if spot != null:
		return spot as Vector3
	return origin - dir * 6.0


func _find_mesh_aabb(node: Node) -> AABB:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var box := _find_mesh_aabb(child)
			if box.size != Vector3.ZERO:
				return box
	return AABB(-Vector3.ONE * 0.5, Vector3.ONE)


func _plane_hit(origin: Vector3, dir: Vector3, height: float) -> Variant:
	if absf(dir.y) < 0.00001:
		return null
	var t := (height - origin.y) / dir.y
	if t < 0.0:
		return null
	return origin + dir * t


func _move_asset_to_ground(placement: Node3D) -> void:
	var box: AABB = _find_mesh_aabb(placement)
	placement.position.y -= box.position.y
	_apply_placement_transform(placement)


func _refresh_debug() -> void:
	if _selected == null:
		_set_status("placed: %d — selected: none" % _placements.size())
		return
	var iid := String(_selected.get_meta("instance_id", "?"))
	var pid := String(_selected.get_meta("prefab_id", "?"))
	_set_status("placed: %d — selected: %s (%s) pos=%s" % [_placements.size(), pid, iid, _selected.position])


func _set_status(msg: String) -> void:
	print("[MapEditor] %s" % msg)
	if debug_label != null:
		debug_label.text = "MODE: %s\n%s" % ["PLAYTEST" if _playtest_active else "EDIT", msg]
