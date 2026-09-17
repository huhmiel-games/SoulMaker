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
const GROUND_LAYER := 1
const SELECT_MASK := GROUND_LAYER | SELECTOR_LAYER
const MAPS_DIR := "user://maps"

const CROSSHAIR_OK: Texture2D = preload("res://assets/textures/ui/crosshair_green.png")
const CROSSHAIR_HIT: Texture2D = preload("res://assets/textures/ui/crosshair_red.png")

const MOVE_STEP := 0.25
const MOVE_FINE := 0.05
## Grab feel knobs (tune live): object move/height speed (m/s at full
## deflection) and turn speed (rad/s).
const OBJ_MOVE_SPEED := 2.5
const OBJ_HEIGHT_SPEED := 3.0
const OBJ_TURN_SPEED := 1.8
## Snap knobs (tune live): position grid step (m, all axes) and angle step
## (rad) applied while _snap_on (L1/Tab toggle). 0.1 m / 15° align any asset
## size (every usual multiple divides evenly); the accumulators make fine
## steps safe (no freeze).
const SNAP_STEP := 0.1
const SNAP_ANGLE := PI / 12.0

## Attach points (must exist in the scene scaffold).
@onready var world_viewport: SubViewport = get_node("ViewportContainer/WorldViewport")
@onready var placement_root: Node3D = get_node("ViewportContainer/WorldViewport/Placements")
@onready var editor_camera: OrbitCamera = get_node("ViewportContainer/WorldViewport/EditorCamera")
@onready var play_camera: FlyCamera = get_node("ViewportContainer/WorldViewport/PlayCamera")
@onready var selection_box: MeshInstance3D = get_node("ViewportContainer/WorldViewport/SelectionBox")
@onready var catalog_panel: CatalogPanel = get_node("CatalogPanel")
@onready var debug_label: Label = get_node("DebugLabel")
@onready var crosshair: TextureRect = get_node("Crosshair")

var catalog := Catalog.new()
var _placements: Array[Dictionary] = []
var _selected: Node3D = null
var _playtest_active := false
var current_map_name := "corridor_01"
## Monotonic placement counter — instance ids must stay unique even after
## deletions, so they are never derived from _placements.size().
var _next_iid: int = 0
## Grab state (Minecraft-style direct manipulation): while true the camera is
## frozen and the sticks drive the selected placement instead of the view.
var _grabbed := false
## Pre-grab transform, restored by cancel (B/Q).
var _grab_from := Transform3D.IDENTITY
## Snap toggle (L1/Tab): grid position + stepped angles while grabbed.
var _snap_on := false
## Grabbed rotation accumulator (yaw/pitch/roll): applied ABSOLUTE each frame
## (snapped or not) so stepping never drifts — incremental rotate_* calls
## would oscillate under snap.
var _grab_rot := Vector3.ZERO
## Grabbed position accumulator (unsnapped logical pose): deltas apply here,
## the node shows the snapped (or raw) copy. Rounding the live node position
## in place would erase sub-half-step progress every frame and freeze motion.
var _grab_pos := Vector3.ZERO


func _ready() -> void:
	# CAPTURED at all times in the editor: orbit must behave like the right
	# stick (unbounded relative motion — the cursor must never hit a window
	# edge), and no UI needs a visible cursor (panel is arrows/D-pad only).
	# Cursor release arrives with the menu scene; Alt-Tab still works at OS
	# level. Playtest manages its own capture via FlyCamera.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var load_err := catalog.load()
	if load_err != OK:
		_set_status("FATAL: catalog not readable")
		return
	var issues := catalog.validate()
	refill_catalog()
	# Initial crosshair texture: _refresh_crosshair() only assigns on change,
	# so without this the crosshair stays invisible while aiming at empty
	# space from launch (hit == _crosshair_hit == false).
	crosshair.texture = CROSSHAIR_OK
	for issue in issues:
		_set_status("catalog issue: %s" % issue)
	_set_status("editor ready — arrows browse the catalog, E confirms at the crosshair")

	InputManager.action_pressed.connect(_on_input_action)
	InputManager.set_profile(&"editor")


func _process(delta: float) -> void:
	_refresh_crosshair()
	if _playtest_active:
		return
	if _grabbed:
		_move_grabbed(delta)
		return
	if _selected == null:
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


## ── selection & grab ─────────────────────────────────────────────────
## A/E is contextual on the crosshair, identically on every device (parity).
## IDLE: red grabs the aimed placement (camera freezes, sticks drive it),
## green places the current catalog entry. GRABBED: A/E drops (applies +
## deselects + unfreezes), B/Q cancels (restores pre-grab transform),
## R1+B/X/Delete deletes. There is no mouse-click path.

## Last crosshair pick result (drives the red/green texture, assigned only
## on change by _refresh_crosshair).
var _crosshair_hit := false


## A/E confirm at the crosshair: grabs the aimed placement, otherwise places
## the current catalog entry at the spawn point. While grabbed, confirms the
## drop instead.
func _place_or_select() -> void:
	if _grabbed:
		_drop_grab()
		return
	var aimed := _pick_placement_at_screen(_viewport_center())
	if aimed != null:
		_grab(aimed)
		return
	var id := catalog_panel.current_id
	if id.is_empty():
		_set_status("no catalog entry to place")
		return
	_on_asset_selected(id)


## Grabs a placement: the camera freezes and the sticks drive the object
## (see _move_grabbed) until drop/cancel/delete.
func _grab(placement: Node3D) -> void:
	_selected = placement
	_grabbed = true
	_grab_from = placement.global_transform
	_grab_rot = placement.rotation
	_grab_pos = placement.position
	editor_camera.frozen = true
	_update_selection_visual()
	var iid := String(placement.get_meta("instance_id", "?"))
	var pid := String(placement.get_meta("prefab_id", "?"))
	_set_status("grabbed %s (%s) — sticks drive it, camera frozen" % [pid, iid])
	_refresh_grab_label()


## Drops the grab: keeps the live transform, deselects, unfreezes.
func _drop_grab() -> void:
	if _selected == null:
		return
	var iid := String(_selected.get_meta("instance_id", "?"))
	_grabbed = false
	_selected = null
	editor_camera.frozen = false
	_update_selection_visual()
	_set_status("dropped %s" % iid)


## Cancels the grab: restores the pre-grab transform, deselects, unfreezes.
func _cancel_grab() -> void:
	if _selected == null:
		return
	_selected.global_transform = _grab_from
	_apply_placement_transform(_selected)
	var iid := String(_selected.get_meta("instance_id", "?"))
	_grabbed = false
	_selected = null
	editor_camera.frozen = false
	_update_selection_visual()
	_set_status("grab cancelled %s (restored)" % iid)


## Drives the grabbed placement with the camera sticks (the camera is frozen,
## so its inputs are inert on the view). Shift (R1-pad / Shift-key) switches
## both sticks to their second job — translation stick does Y only, rotation
## stick does roll only. Position AND rotation accumulate unsnapped (_grab_pos
## / _grab_rot) and apply absolute, snapped or not — rounding the live node
## in place would erase sub-half-step progress and freeze motion. All sources
## sum, no device branches.
func _move_grabbed(delta: float) -> void:
	if _selected == null:
		return
	var node := _selected
	var shifted := InputManager.is_shifted()
	# XZ move, unshifted only (keyboard steps scaled like the camera pan +
	# stick on top).
	if not shifted:
		var mv := Vector2.ZERO
		if InputManager.is_pressed(&"cam_pan_right"):
			mv.x += 1.0
		if InputManager.is_pressed(&"cam_pan_left"):
			mv.x -= 1.0
		if InputManager.is_pressed(&"cam_pan_back"):
			mv.y += 1.0
		if InputManager.is_pressed(&"cam_pan_fwd"):
			mv.y -= 1.0
		mv = mv * 0.5 + InputManager.left_stick()
		if mv != Vector2.ZERO:
			var cbasis := editor_camera.global_basis
			var right := cbasis.x
			right.y = 0.0
			right = right.normalized() if right.length() > 0.001 else Vector3.RIGHT
			var fwd := -cbasis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.FORWARD
			_grab_pos += (right * mv.x + fwd * -mv.y) * OBJ_MOVE_SPEED * delta
	# Height, shifted only: LS Y / W-S, push up lifts. Base clamped above
	# the ground (on the accumulator).
	if shifted:
		var ls := InputManager.left_stick()
		var h := -ls.y
		if InputManager.is_pressed(&"cam_pan_fwd"):
			h += 1.0
		if InputManager.is_pressed(&"cam_pan_back"):
			h -= 1.0
		if h != 0.0:
			_grab_pos.y += h * OBJ_HEIGHT_SPEED * delta
			var box := _find_mesh_aabb(node)
			_grab_pos.y = maxf(_grab_pos.y, -box.position.y)
	# Display pose: raw accumulator, or base-snapped to the grid (the base
	# lands exactly on-grid and never below ground — rounding the origin
	# instead would bury it up to half a step).
	if _snap_on:
		var sbox := _find_mesh_aabb(node)
		var base_y := maxf(roundf((_grab_pos.y + sbox.position.y) / SNAP_STEP) * SNAP_STEP, 0.0)
		node.position = Vector3(
			roundf(_grab_pos.x / SNAP_STEP) * SNAP_STEP,
			base_y - sbox.position.y,
			roundf(_grab_pos.z / SNAP_STEP) * SNAP_STEP,
		)
	else:
		node.position = _grab_pos
	# Turn: RS/mouse summed by InputManager. Unshifted = yaw (X) + pitch (Y);
	# shifted = roll alone (Y dead). Accumulated, applied absolute.
	var tx := InputManager.analog(&"cam_orbit_x")
	var ty := InputManager.analog(&"cam_orbit_y")
	if shifted:
		_grab_rot.z += -tx * OBJ_TURN_SPEED * delta
	else:
		_grab_rot.y += -tx * OBJ_TURN_SPEED * delta
		_grab_rot.x += -ty * OBJ_TURN_SPEED * delta
	if _snap_on:
		node.rotation = _snap_vec(_grab_rot, SNAP_ANGLE)
	else:
		node.rotation = _grab_rot
	_set_placement_data(node)
	_update_selection_visual()
	_refresh_grab_label()


## Rounds each component to the grid step (position) or angle step.
func _snap_vec(v: Vector3, step: float) -> Vector3:
	return Vector3(
		roundf(v.x / step) * step,
		roundf(v.y / step) * step,
		roundf(v.z / step) * step,
	)


## Grab HUD text (shared builder). Per-frame refresh is label-only (no
## print — _set_status prints, which would spam the console every frame);
## grab/drop/cancel events use _set_status for their one-shot print.
func _grab_label_text() -> String:
	if _selected == null:
		return "MODE: EDIT"
	var iid := String(_selected.get_meta("instance_id", "?"))
	var pid := String(_selected.get_meta("prefab_id", "?"))
	return "MODE: EDIT (grabbed)%s SH%d\n%s (%s) pos=%s\nLS/WASD move · R1+LS/Shift+WASD height · RS/mouse turn · R1+RS/Shift+mouse roll · A drop · B cancel · R1+B delete" % [
		" · SNAP %.1f/%d°" % [SNAP_STEP, int(roundf(rad_to_deg(SNAP_ANGLE)))] if _snap_on else "",
		1 if InputManager.is_shifted() else 0,
		pid, iid, _selected.position,
	]


func _refresh_grab_label() -> void:
	debug_label.text = _grab_label_text()


func _viewport_center() -> Vector2:
	return world_viewport.get_visible_rect().size * 0.5


## Center-crosshair pick, guarded: queries the EFFECTIVE world (the one the
## camera sees). 4.7 quirk, verified 2026-09-17: SubViewport.world_3d stays
## null despite own_world_3d=true (using_own=true, own scenario renders), but
## find_world_3d()/camera world resolve the real own world — which differs
## from the main window world, so root.world_3d must NOT be used. A null
## effective world degrades to "no hit": green crosshair, A/E places.
func _pick_placement_at_screen(screen_pos: Vector2) -> Node3D:
	var world := editor_camera.get_world_3d()
	if world == null:
		return null
	var origin := editor_camera.project_ray_origin(screen_pos)
	var dir := editor_camera.project_ray_normal(screen_pos)
	var space := world.direct_space_state
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


## Crosshair upkeep (runs before the _process gate): hidden in playtest and
## while grabbed (the SelectionBox takes over), otherwise green = empty space
## (A/E places), red = aiming at a placed asset (A/E grabs it).
func _refresh_crosshair() -> void:
	if _playtest_active or _grabbed:
		if crosshair.visible:
			crosshair.hide()
		return
	if not crosshair.visible:
		crosshair.show()
	var hit := _pick_placement_at_screen(_viewport_center()) != null
	if hit != _crosshair_hit:
		_crosshair_hit = hit
		crosshair.texture = CROSSHAIR_HIT if hit else CROSSHAIR_OK


func _select(placement: Node3D) -> void:
	_selected = placement
	_update_selection_visual()


func _update_selection_visual() -> void:
	if _selected == null:
		selection_box.visible = false
		return
	# _find_mesh_aabb returns the MESH-LOCAL box: transform both corners into
	# world space (SelectionBox lives in the viewport, not in the placement).
	# Corner-transform keeps working once rotation/scale editing lands.
	var box: AABB = _find_mesh_aabb(_selected)
	var xform := _selected.global_transform
	var world_box := AABB(xform * box.position, Vector3.ZERO)
	world_box = world_box.expand(xform * (box.position + box.size))
	selection_box.visible = true
	selection_box.position = world_box.position + world_box.size * 0.5
	var mat := selection_box.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color.a = 0.25
	var mesh := selection_box.mesh as BoxMesh
	if mesh:
		mesh.size = world_box.size


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
	_grabbed = false
	editor_camera.frozen = false
	_update_selection_visual()
	_set_status("deleted %s — placed: %d" % [iid, _placements.size()])


func _clear_all() -> void:
	for child in placement_root.get_children():
		child.queue_free()
	_placements.clear()
	_selected = null
	_grabbed = false
	editor_camera.frozen = false
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
		# Entering playtest force-drops any grab (live transform kept).
		_grabbed = false
		editor_camera.frozen = false
		play_camera.global_position = editor_camera.global_position
		play_camera.rotation = editor_camera.rotation
	editor_camera.current = not _playtest_active
	play_camera.current = _playtest_active
	play_camera.set_capture(_playtest_active)
	if not _playtest_active:
		# Back to editor: re-capture (see _ready — the editor is always
		# CAPTURED, set_capture(false) above just released to VISIBLE).
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
		&"delete_shifted":
			# R1+B: delete, grabbed or not (the shifted face of B/cancel).
			if not _playtest_active:
				_delete_selection()
		&"snap_toggle":
			# L1/Tab: grid+angle snap on/off, grabbed or not (applies next
			# transform while grabbed).
			if not _playtest_active:
				_snap_on = not _snap_on
				_set_status("snap %s (grid %.1f m, angles %d°)" % ["ON" if _snap_on else "OFF", SNAP_STEP, int(roundf(rad_to_deg(SNAP_ANGLE)))])
				_refresh_grab_label()
				_refresh_debug()
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
				_place_or_select()
		&"deselect":
			if not _playtest_active:
				if _grabbed:
					_cancel_grab()
				elif InputManager.is_shifted():
					# Shift+Q: the shifted face of cancel (R1+B's keyboard
					# mirror — _resolve_key is shift-blind, so it lands here).
					_delete_selection()
				else:
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
