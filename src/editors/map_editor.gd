class_name MapEditor
extends Control

## P1 map editor controller (unit 1): the minimal maker loop.
## Place an asset (catalog click) → move it (arrow keys) →
## save/reload a versioned JSON map → one-key playtest (free-fly camera).
## The DebugLabel mirrors every state change with a matching print() line.

signal map_saved(path: String)
signal map_loaded(path: String)

const PLACEMENT_GROUP := "placement"
const SELECTOR_GROUP := "placement_selector"
const SELECTOR_LAYER := 2
const MAPS_DIR := "user://maps"

const MOVE_STEP := 0.25
const MOVE_FINE := 0.05

## Attach points (must exist in the scene scaffold).
## world_viewport is currently unused (no picking) — kept for the gizmo/move
## rework which will need viewport queries again.
@onready var world_viewport: SubViewport = get_node("ViewportContainer/WorldViewport")
@onready var placement_root: Node3D = get_node("ViewportContainer/WorldViewport/Placements")
@onready var editor_camera: OrbitCamera = get_node("ViewportContainer/WorldViewport/EditorCamera")
@onready var play_camera: FlyCamera = get_node("ViewportContainer/WorldViewport/PlayCamera")
@onready var selection_box: MeshInstance3D = get_node("ViewportContainer/WorldViewport/SelectionBox")
@onready var catalog_panel: CatalogPanel = get_node("CatalogPanel")
@onready var debug_label: Label = get_node("DebugLabel")

var catalog := Catalog.new()
var _placements: Array[Dictionary] = []
var _selected: Node3D = null
var _playtest_active := false
var current_map_name := "corridor_01"
## Monotonic placement counter — instance ids must stay unique even after
## deletions, so they are never derived from _placements.size().
var _next_iid: int = 0


func _ready() -> void:
	# The editor cursor is never shown: orbit is drag-free (motion always feeds
	# the camera) and the mouse selects nothing — panel browsing is arrows /
	# D-pad only, placement is A/E. HIDDEN (invisible yet functional) rather
	# than CAPTURED (locked to center).
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var load_err := catalog.load()
	if load_err != OK:
		_set_status("FATAL: catalog not readable")
		return
	var issues := catalog.validate()
	refill_catalog()
	for issue in issues:
		_set_status("catalog issue: %s" % issue)
	_set_status("editor ready — arrows browse the catalog, E places")

	InputManager.action_pressed.connect(_on_input_action)
	InputManager.set_profile(&"editor")


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
	var iid := "inst_%04d" % _next_iid
	_next_iid += 1
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
## NOTE: picking existing placements (mouse or center-crosshair) is removed
## for keyboard/gamepad parity — the mouse selects nothing, A/E always
## places. Selection of placed objects returns with the gizmo/move rework;
## the Selector bodies are still created per placement for that future use.

## A/E: always places the current catalog entry at the spawn point.
func _place_current() -> void:
	var id := catalog_panel.current_id
	if id.is_empty():
		_set_status("no catalog entry to place")
		return
	_on_asset_selected(id)


func _select(placement: Node3D) -> void:
	_selected = placement
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
	_set_status("deleted %s — placed: %d" % [iid, _placements.size()])


func _clear_all() -> void:
	for child in placement_root.get_children():
		child.queue_free()
	_placements.clear()
	_selected = null
	_next_iid = 0
	_update_selection_visual()


## ── save / load ────────────────────────────────────────────────────────

func _map_path(name: String) -> String:
	return MAPS_DIR.path_join("%s.json" % name)


func save_map() -> void:
	var name := current_map_name.strip_edges()
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
	_set_status("saved %s (%d placements)" % [name, _placements.size()])


func load_map(name: String) -> void:
	var path := _map_path(name)
	var data := JsonFile.load_object(path)
	if data.is_empty():
		_set_status("cannot load %s (missing or corrupt)" % path)
		return
	var issues := MapIO.validate_map(data)
	issues.append_array(MapIO.validate_refs(data, catalog))
	_clear_all()
	for placement in MapIO.deserialize(data):
		_instance_from_data(placement)
	_sync_iid_counter()
	if not issues.is_empty():
		for issue in issues:
			_set_status("LOAD ISSUE: %s" % issue)
	map_loaded.emit(path)
	current_map_name = name
	_set_status("loaded %s — placed: %d %s" % [name, _placements.size(), "(issues above)" if not issues.is_empty() else ""])


## Re-anchors the monotonic iid counter past the highest loaded suffix, so
## placements created after a load never collide with loaded ids.
## Only "inst_NNNN" ids participate; anything else is ignored.
func _sync_iid_counter() -> void:
	var top := -1
	for p in _placements:
		var iid: String = str(p.get("instance_id", ""))
		if not iid.begins_with("inst_"):
			continue
		var tail: String = iid.trim_prefix("inst_")
		if not tail.is_valid_int():
			continue
		top = maxi(top, int(tail))
	_next_iid = top + 1


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
	if not _playtest_active:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	catalog_panel.visible = not _playtest_active
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
		&"delete":
			if not _playtest_active:
				_delete_selection()
		&"catalog_next":
			if not _playtest_active:
				catalog_panel.cycle_next()
		&"catalog_prev":
			if not _playtest_active:
				catalog_panel.cycle_prev()
		&"tab_next":
			if not _playtest_active:
				catalog_panel.next_tab()
		&"tab_prev":
			if not _playtest_active:
				catalog_panel.prev_tab()
		&"place_select":
			if not _playtest_active:
				_place_current()
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
