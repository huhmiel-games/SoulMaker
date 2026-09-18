class_name MapEditor
extends Control

## P1 map editor controller (unit 1): the minimal maker loop.
## Place an asset → move it (grab & move) → save/reload a versioned JSON map.
## Y/P sculpts the ground relief (EDIT_FLOOR: LS moves a grid cursor, RS
## heightens, A checkpoints, B undoes to checkpoint, Y exits).
## Start/S or Guide/ESC opens the pause modal (SAVE / CANCEL / QUIT); QUIT
## while dirty swaps in the quit-confirm (QUIT WITHOUT SAVING / CANCEL).
## The shared EditorHUD shows persistent facts (snap state) + temporary
## confirmations (save toast, 5 s) + command help (hint); every state change
## also prints a matching log line.

signal map_saved(path: String)
signal map_loaded(path: String)

const PLACEMENT_GROUP := "placement"
const SELECTOR_GROUP := "placement_selector"
const SELECTOR_LAYER := 2
const GROUND_LAYER := 1
const SELECT_MASK := GROUND_LAYER | SELECTOR_LAYER
const MAPS_DIR := "user://maps"
## Menu scene (QUIT returns here) + the GameState key the menu uses to hand
## over the map to open ("" = none, boot empty as usual).
const MENU_SCENE := "res://scenes/editors/map_editor_menu.tscn"
const PENDING_KEY := "editor/pending_map"
## Single generic menu scene, configured at runtime (pause + quit-confirm
## are just entries + Callables — zero menu-specific scenes).
const GENERIC_MENU_SCENE := preload("res://scenes/ui/generic_menu.tscn")

const CROSSHAIR_OK: Texture2D = preload("res://assets/textures/ui/crosshair_green.png")
const CROSSHAIR_HIT: Texture2D = preload("res://assets/textures/ui/crosshair_red.png")

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
## Floor relief knobs (EDIT_FLOOR, Y/P): cell size/count/bounds live in MapIO
## (single source: MapIO.GROUND_*). Sculpt is continuous-additive (plugin
## style): rate in m/s at the disk center, cosine falloff to the rim, trails
## while traveling; files quantize to the step at save (MapIO guarantee).
const FLOOR_HEIGHT_RATE := 1.0
const FLOOR_CURSOR_RATE := 8.0
## Brush: RS X / mouse X / Shift+A-D grows the elevation disk (0..6 cells,
## default 2). Radius rate in steps/s at full deflection.
const FLOOR_RADIUS_MAX := 6
const FLOOR_RADIUS_RATE := 3.0
## Ambiance page rows (pause → AMBIANCE): label + flat MapIO key + UI step.
## Min/max come from MapIO.AMBIANCE_BOUNDS (single source); tonemap_mode and
## fog_enabled render as names, not numbers (see _amb_display).
const AMBIANCE_ROWS := [
	{"label": "Fog", "key": "fog_enabled", "step": 1.0},
	{"label": "Fog depth begin", "key": "fog_begin", "step": 5.0},
	{"label": "Fog depth end", "key": "fog_end", "step": 5.0},
	{"label": "Fog height", "key": "fog_height", "step": 1.0},
	{"label": "Fog height density", "key": "fog_hdensity", "step": 0.05},
	{"label": "Tonemap", "key": "tonemap_mode", "step": 1.0},
	{"label": "Exposure", "key": "tonemap_exposure", "step": 0.1},
	{"label": "Sun elevation", "key": "sun_elev", "step": 1.0},
	{"label": "Sun energy", "key": "sun_energy", "step": 0.1},
	{"label": "Ambient energy", "key": "ambient_energy", "step": 0.05},
]
const TONEMAP_NAMES := ["Linear", "Reinhard", "Filmic", "ACES", "AgX"]
const PRESETS_PATH := "res://data/ambiance/presets.json"
## Rebuild throttle: mesh + collision rebuild at most this often while
## sculpting (heights themselves update per frame), plus one final rebuild on
## release.
const FLOOR_REBUILD_INTERVAL := 0.1
const FLOOR_HINT := "LS/WASD cell · RS height · RSX/Sh+A-D radius · A/E keep · B/Q undo · Y/P exit"

## Attach points (must exist in the scene scaffold).
@onready var world_viewport: SubViewport = get_node("ViewportContainer/WorldViewport")
@onready var placement_root: Node3D = get_node("ViewportContainer/WorldViewport/Placements")
@onready var editor_camera: OrbitCamera = get_node("ViewportContainer/WorldViewport/EditorCamera")
@onready var world_env: WorldEnvironment = get_node("ViewportContainer/WorldViewport/WorldEnvironment")
@onready var sun: DirectionalLight3D = get_node("ViewportContainer/WorldViewport/Sun")
@onready var selection_box: MeshInstance3D = get_node("ViewportContainer/WorldViewport/SelectionBox")
@onready var ground_mesh: MeshInstance3D = get_node("ViewportContainer/WorldViewport/Ground/GroundMesh")
@onready var ground_shape: CollisionShape3D = get_node("ViewportContainer/WorldViewport/Ground/GroundShape")
@onready var catalog_panel: CatalogPanel = get_node("CatalogPanel")
@onready var hud: EditorHUD = get_node("HUD")
@onready var crosshair: TextureRect = get_node("Crosshair")
@onready var modal: ModalDialog = get_node("ModalLayer/ModalDialog")

var catalog := Catalog.new()
var _placements: Array[Dictionary] = []
var _selected: Node3D = null
var current_map_name := "corridor_01"
## Ambiance override (flat MapIO dict): live values driving the viewport.
## _amb_has_section tracks whether the map OWNS a section (user-edited,
## preset-applied, or loaded) — only then does save serialize it.
var _ambiance: Dictionary = {}
var _amb_has_section := false
## Preset registry {id: {label, values flat}} from presets.json + match state
## ("" = Custom/diverged, shown in the page title).
var _amb_presets := {}
var _amb_preset := ""
var _sun_azimuth := 0.0
## Unsaved-changes flag: set by every edit (place, grab, delete, sculpt),
## cleared by save/load. QUIT consults it (clean quits directly, dirty swaps
## in the quit-confirm).
var _dirty := false
## Pause modal state (0 = none, 1 = pause, 2 = quit-confirm). While open the
## editor ignores every input except the Start/ESC toggle, and _process edit
## paths are gated — the modal owns A/E/B. Grab/floor state underneath is
## kept as-is (camera restore flag below).
var _modal_open := false
var _modal_level := 0
## True when the camera was NOT frozen before the modal opened (IDLE /
## SELECTED) — restored on close. Grabbed/floor states stay frozen.
var _cam_unfreeze_on_close := false
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
## Floor relief (EDIT_FLOOR, the 4th editor state): sparse heights
## ({Vector2i cell: float}, default 0 = flat), camera frozen like a grab, LS
## moves a grid cursor, RS heightens the hovered cell. Entering snapshots the
## relief; A checkpoints (stays), B restores to checkpoint (stays), Y exits
## (keeps). Same grammar as grab: A validates, B cancels.
var _ground: Dictionary = {}
var _floor_mode := false
var _floor_cursor := Vector2i(50, 50)
var _floor_checkpoint := {}
var _floor_rep := Vector2.ZERO
## Brush radius (disk around the cursor) + radius accumulator.
var _floor_radius := 2
var _floor_rad_accum := 0.0
## Rebuild dirty flag + cooldown (throttled sculpt visuals).
var _floor_dirty := false
var _floor_cd := 0.0
## SelectionBox's own mesh (BoxMesh scaffold), swapped for the floor ring
## while sculpting and restored on exit.
var _selection_mesh_orig: Mesh = null
## Ring material (red translucent, carried by the ring mesh itself) — the
## SelectionBox's yellow stays placements-only.
var _ring_mat: StandardMaterial3D = null


func _ready() -> void:
	# CAPTURED at all times in the editor: orbit must behave like the right
	# stick (unbounded relative motion — the cursor must never hit a window
	# edge), and no UI needs a visible cursor (panel is arrows/D-pad only).
	# Cursor release arrives with the menu scene; Alt-Tab still works at OS
	# level.
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
	if hud != null:
		hud.set_persistent(&"snap", "SNAP ON" if _snap_on else "SNAP OFF")
	# Flat relief until a map (with its ground section) loads; the mesh +
	# HeightMapShape replace the tscn placeholders here.
	_rebuild_ground()
	# Ambiance owns its resource: duplicate the tres so live tweaks never
	# touch the asset, then boot on defaults (a loaded section overlays).
	world_env.environment = (world_env.environment as Environment).duplicate()
	_sun_azimuth = sun.rotation_degrees.y
	_load_presets()
	_ambiance = (MapIO.AMBIANCE_DEFAULTS as Dictionary).duplicate()
	_apply_ambiance()

	InputManager.action_pressed.connect(_on_input_action)
	InputManager.set_profile(&"editor")
	# Menu handover: open the pending map if the menu set one, else boot
	# empty as usual (direct scene runs).
	var pending := str(GameState.get_value(PENDING_KEY, ""))
	GameState.set_value(PENDING_KEY, "")
	if not pending.is_empty():
		current_map_name = pending
		load_map(pending)


func _process(delta: float) -> void:
	_refresh_crosshair()
	if _modal_open:
		return
	if _floor_mode:
		_move_floor(delta)
		return
	if _grabbed:
		_move_grabbed(delta)
		return


## ── catalog & placement ────────────────────────────────────────────────

func refill_catalog() -> void:
	catalog_panel.populate(catalog)


func _on_asset_selected(id: String) -> void:
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
	_dirty = true
	_set_status("spawned %s (%s) — placed: %d" % [id, iid, _placements.size()])
	_refresh_grab_label()


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
	# ADR-019: every 3D asset renders toon (GIMP textures carry through).
	ToonKit.apply_to(placement)

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
	_dirty = true
	_set_status("dropped %s" % iid)
	_refresh_grab_label()


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
	_dirty = true
	_set_status("grab cancelled %s (restored)" % iid)
	_refresh_grab_label()


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
	var applied := false
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
			applied = true
			var cbasis := editor_camera.global_basis
			var right := cbasis.x
			right.y = 0.0
			right = right.normalized() if right.length() > 0.001 else Vector3.RIGHT
			var fwd := -cbasis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.FORWARD
			_grab_pos += (right * mv.x + fwd * -mv.y) * OBJ_MOVE_SPEED * delta
	# Height, shifted only: LS Y / W-S, push up lifts. Base clamped above
	# the relief (on the accumulator); outside the slab the old 0.0 floor
	# applies.
	if shifted:
		var ls := InputManager.left_stick()
		var h := -ls.y
		if InputManager.is_pressed(&"cam_pan_fwd"):
			h += 1.0
		if InputManager.is_pressed(&"cam_pan_back"):
			h -= 1.0
		if h != 0.0:
			applied = true
			_grab_pos.y += h * OBJ_HEIGHT_SPEED * delta
			var box := _find_mesh_aabb(node)
			var gh := _ground_height_at(_grab_pos.x, _grab_pos.z)
			var floor_y := 0.0 if is_nan(gh) else gh
			_grab_pos.y = maxf(_grab_pos.y, floor_y - box.position.y)
	# Display pose: raw accumulator, or base-snapped to the grid (the base
	# lands exactly on-grid and never below the relief — rounding the origin
	# instead would bury it up to half a step).
	if _snap_on:
		var sbox := _find_mesh_aabb(node)
		var gh2 := _ground_height_at(_grab_pos.x, _grab_pos.z)
		var floor_y2 := 0.0 if is_nan(gh2) else gh2
		var base_y := maxf(roundf((_grab_pos.y + sbox.position.y) / SNAP_STEP) * SNAP_STEP, floor_y2)
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
	if tx != 0.0 or ty != 0.0:
		applied = true
	if shifted:
		_grab_rot.z += -tx * OBJ_TURN_SPEED * delta
	else:
		_grab_rot.y += -tx * OBJ_TURN_SPEED * delta
		_grab_rot.x += -ty * OBJ_TURN_SPEED * delta
	if _snap_on:
		node.rotation = _snap_vec(_grab_rot, SNAP_ANGLE)
	else:
		node.rotation = _grab_rot
	if applied:
		_dirty = true
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


## Shared HUD hint texts. SELECT_HINT is the missing link the mapping doc
## audit surfaced: placing selects, it never grabs — the hint says the 2nd
## confirm out loud. GRAB_HINT is the live mapping while held.
const SELECT_HINT := "A/E on red grabs it — 2nd press holds (camera freezes)"
const GRAB_HINT := "LS/WASD move · R1+LS/Shift+WASD height · RS/mouse turn · R1+RS/Shift+mouse roll · L1/Tab snap · A drop · B cancel · R1+B delete"


## Refreshes the shared HUD from selection state (no print — one-shot events
## use _set_status for their log line; _move_grabbed calls this per frame).
## GRABBED: hint = live mapping (shift flag); status untouched (it
## keeps the last snap/save state). SELECTED: hint = the 2nd-confirm prompt.
## Neither: hint cleared.
func _refresh_grab_label() -> void:
	if hud == null:
		return
	if _floor_mode:
		# Owned by _update_floor_visual (cursor cell + height facts); nothing
		# to do here beyond keeping them.
		return
	if _grabbed and _selected != null:
		var bits := GRAB_HINT
		if InputManager.is_shifted():
			bits = "SHIFTED · " + bits
		hud.set_hint(bits)
	elif _selected != null:
		hud.set_hint(SELECT_HINT)
	else:
		hud.clear_hint()


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


## Crosshair upkeep (runs before the _process gate): hidden while grabbed
## (the SelectionBox takes over) and in floor mode (the 3D cell cursor takes
## over), otherwise green = empty space (A/E places), red = aiming at a
## placed asset (A/E grabs it).
func _refresh_crosshair() -> void:
	if _grabbed or _floor_mode:
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


## ── ground relief ────────────────────────────────────────────────────
## Heightfield over the 100x100 slab (MapIO.GROUND_* bounds): (N+1)x(N+1)
## vertex heights sampled from the sparse _ground cells, mesh + HeightMapShape
## rebuilt from the same grid so visual and collision agree by construction
## (shape convention probed headless 2026-09-18: data[ix + iz*w] sits at
## x=ix-(w-1)/2, z=iz-(d-1)/2). Gentle strokes render as walkable slopes for
## the future walker; sharp gaps as steep unclimbable faces.

func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x + MapIO.GROUND_N * 0.5), floori(z + MapIO.GROUND_N * 0.5))


func _cell_valid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < MapIO.GROUND_N and c.y < MapIO.GROUND_N


## Relief height at a world XZ; NAN outside the slab (callers fall back).
func _ground_height_at(x: float, z: float) -> float:
	var c := _cell_of(x, z)
	if not _cell_valid(c):
		return NAN
	return float(_ground.get(c, 0.0))


func _vertex_height(ix: int, iz: int) -> float:
	var c := Vector2i(clampi(ix, 0, MapIO.GROUND_N - 1), clampi(iz, 0, MapIO.GROUND_N - 1))
	return float(_ground.get(c, 0.0))


func _rebuild_ground() -> void:
	var n := MapIO.GROUND_N
	var v := n + 1
	var verts := PackedVector3Array()
	verts.resize(v * v)
	var heights := PackedFloat32Array()
	heights.resize(v * v)
	for iz in range(v):
		for ix in range(v):
			var h := _vertex_height(ix, iz)
			var i := ix + iz * v
			verts[i] = Vector3(ix - n * 0.5, h, iz - n * 0.5)
			heights[i] = h
	# (a,b,d) + (a,d,c) per quad: clockwise seen from above = Godot front
	# (CCW renders from below only — caught 2026-09-18: floor invisible
	# from above, gray from below).
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
	ground_mesh.mesh = mesh
	var shape := HeightMapShape3D.new()
	shape.map_width = v
	shape.map_depth = v
	shape.map_data = heights
	ground_shape.shape = shape


## Physics ray against the relief (spawn point, floor cursor). Empty when the
## ray misses the slab (aimed past the edge or at the sky).
func _ground_hit(screen_pos: Vector2) -> Dictionary:
	var world := editor_camera.get_world_3d()
	if world == null:
		return {}
	var origin := editor_camera.project_ray_origin(screen_pos)
	var dir := editor_camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 1000.0, GROUND_LAYER)
	return world.direct_space_state.intersect_ray(query)


## ── EDIT_FLOOR ───────────────────────────────────────────────────────
## The 4th editor state (Y/P toggles). Same grammar as grab: A validates
## (checkpoint, stays in mode), B cancels (restores to checkpoint, stays),
## Y is the door (exits, keeps). R1+B / Shift+Q are inert here — relief cells
## are not placements, delete stays placements-only everywhere.

func _enter_floor_mode() -> void:
	if _floor_mode:
		return
	if _grabbed:
		_drop_grab()
	_selected = null
	_floor_mode = true
	_floor_checkpoint = _ground.duplicate()
	editor_camera.frozen = true
	crosshair.hide()
	var hit := _ground_hit(_viewport_center())
	if not hit.is_empty():
		var p: Vector3 = hit["position"]
		var c := _cell_of(p.x, p.z)
		_floor_cursor = c if _cell_valid(c) else Vector2i(50, 50)
	else:
		_floor_cursor = Vector2i(50, 50)
	_floor_rep = Vector2.ZERO
	_floor_radius = 2
	_floor_rad_accum = 0.0
	_floor_dirty = false
	_floor_cd = 0.0
	_selection_mesh_orig = selection_box.mesh
	selection_box.mesh = _make_floor_ring(_floor_radius)
	# The ring is a cursor: no shadow on the map (restored on exit).
	selection_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update_floor_visual()
	_set_status("floor mode — LS/WASD moves the cell cursor, RS heightens, camera frozen")


func _exit_floor_mode() -> void:
	if not _floor_mode:
		return
	_floor_mode = false
	editor_camera.frozen = false
	crosshair.show()
	if _selection_mesh_orig != null:
		selection_box.mesh = _selection_mesh_orig
		_selection_mesh_orig = null
	selection_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	selection_box.visible = false
	if hud != null:
		hud.clear_persistent(&"floor")
		hud.clear_hint()
	_set_status("floor mode off — relief kept")


func _floor_commit() -> void:
	_floor_checkpoint = _ground.duplicate()
	_user_status("floor checkpoint — A keeps going, B undoes to here")


func _floor_undo() -> void:
	_ground = _floor_checkpoint.duplicate()
	_rebuild_ground()
	_update_floor_visual()
	_dirty = true
	_user_status("floor restored to checkpoint")


## Cursor cell-by-cell (key-repeat feel, camera-relative like the grab) +
## continuous sculpt. LS/WASD point where the cursor must go on screen; the
## camera basis converts to slab cells (world axes here re-invert as soon as
## the camera orbits — reported 2026-09-18).
func _move_floor(delta: float) -> void:
	var iv := Vector2.ZERO
	if InputManager.is_pressed(&"cam_pan_right"):
		iv.x += 1.0
	if InputManager.is_pressed(&"cam_pan_left"):
		iv.x -= 1.0
	if InputManager.is_pressed(&"cam_pan_back"):
		iv.y += 1.0
	if InputManager.is_pressed(&"cam_pan_fwd"):
		iv.y -= 1.0
	iv = iv * 0.5 + InputManager.left_stick()
	var cbasis := editor_camera.global_basis
	var right := cbasis.x
	right.y = 0.0
	right = right.normalized() if right.length() > 0.001 else Vector3.RIGHT
	var fwd := -cbasis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.FORWARD
	var off := right * iv.x + fwd * -iv.y
	_floor_rep.x += off.x * FLOOR_CURSOR_RATE * delta
	_floor_rep.y += off.z * FLOOR_CURSOR_RATE * delta
	var stepped := false
	while absf(_floor_rep.x) >= 1.0:
		_floor_cursor.x += 1 if _floor_rep.x > 0.0 else -1
		_floor_rep.x -= 1.0 if _floor_rep.x > 0.0 else -1.0
		stepped = true
	while absf(_floor_rep.y) >= 1.0:
		_floor_cursor.y += 1 if _floor_rep.y > 0.0 else -1
		_floor_rep.y -= 1.0 if _floor_rep.y > 0.0 else -1.0
		stepped = true
	if stepped:
		_floor_cursor.x = clampi(_floor_cursor.x, 0, MapIO.GROUND_N - 1)
		_floor_cursor.y = clampi(_floor_cursor.y, 0, MapIO.GROUND_N - 1)
		_update_floor_visual()
	# Brush radius: RS X / mouse X / Shift+A-D, discrete steps (no trail
	# issue here — radius is not positional).
	var r := InputManager.right_stick().x
	r += InputManager.analog(&"cam_orbit_x")
	if InputManager.is_shifted():
		if InputManager.is_pressed(&"cam_pan_right"):
			r += 1.0
		if InputManager.is_pressed(&"cam_pan_left"):
			r -= 1.0
	if r != 0.0:
		_floor_rad_accum += r * FLOOR_RADIUS_RATE * delta
		var resized := false
		while _floor_rad_accum >= 1.0:
			_floor_rad_accum -= 1.0
			if _floor_radius < FLOOR_RADIUS_MAX:
				_floor_radius += 1
				resized = true
		while _floor_rad_accum <= -1.0:
			_floor_rad_accum += 1.0
			if _floor_radius > 0:
				_floor_radius -= 1
				resized = true
		if resized:
			selection_box.mesh = _make_floor_ring(_floor_radius)
			_update_floor_visual()
			_set_status("floor brush R=%d" % _floor_radius)
	# Height: continuous-additive stroke over the disk (plugin style) with
	# trails — traveling with the stick held paints a ridge, as intended.
	var h := -InputManager.right_stick().y
	h += -InputManager.analog(&"cam_orbit_y")
	if InputManager.is_shifted():
		if InputManager.is_pressed(&"cam_pan_fwd"):
			h += 1.0
		if InputManager.is_pressed(&"cam_pan_back"):
			h -= 1.0
	if h != 0.0:
		if _floor_stroke(h * FLOOR_HEIGHT_RATE * delta):
			_floor_dirty = true
			_dirty = true
		_floor_cd -= delta
		if _floor_dirty and _floor_cd <= 0.0:
			_rebuild_ground()
			_floor_cd = FLOOR_REBUILD_INTERVAL
			_update_floor_visual()
	elif _floor_dirty:
		_rebuild_ground()
		_floor_dirty = false
		_update_floor_visual()
	_update_floor_ring_pos()


## Continuous stroke: adds amount (signed meters at the disk center, cosine
## falloff to the rim) to every cell in the brush disk, clamped [-8, +8].
## Heights stay float in memory (smooth hills); files quantize to
## MapIO.GROUND_STEP at save. Near-zero cells stay sparse. True when anything
## moved.
func _floor_stroke(amount: float) -> bool:
	var moved := false
	var rad := _floor_radius
	for dz in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var dist := Vector2(dx, dz).length()
			if dist > rad + 0.01:
				continue
			var w := 1.0 if rad == 0 else 0.5 + 0.5 * cos(PI * dist / float(rad + 1))
			var cell := _floor_cursor + Vector2i(dx, dz)
			if not _cell_valid(cell):
				continue
			var cur := float(_ground.get(cell, 0.0))
			var next := clampf(cur + amount * w, MapIO.GROUND_H_MIN, MapIO.GROUND_H_MAX)
			if is_equal_approx(next, cur):
				continue
			if absf(next) < 0.01:
				_ground.erase(cell)
			else:
				_ground[cell] = next
			moved = true
	return moved


## Flat annulus cursor (outer = disk rim + half cell) generated per radius —
## the plugin-style circle on the ground. 48 segments, explicit +Y normals,
## clockwise-from-above winding (Godot front, same fix as the relief mesh).
func _make_floor_ring(rad: int) -> ArrayMesh:
	var segs := 48
	var ro := rad + 0.5
	var ri := maxf(ro - 0.12, 0.05)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in range(segs):
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var o0 := Vector3(cos(a0) * ro, 0.0, sin(a0) * ro)
		var o1 := Vector3(cos(a1) * ro, 0.0, sin(a1) * ro)
		var i0 := Vector3(cos(a0) * ri, 0.0, sin(a0) * ri)
		var i1 := Vector3(cos(a1) * ri, 0.0, sin(a1) * ri)
		for p in [o0, o1, i1, o0, i1, i0]:
			verts.append(p)
			normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _ring_mat == null:
		_ring_mat = StandardMaterial3D.new()
		# Cursor contract: identical red everywhere — opaque (no washout over
		# bright slopes) + unshaded (no light/shadow tint) + no depth test
		# (never buried by the relief).
		_ring_mat.albedo_color = Color(1.0, 0.2, 0.15, 1.0)
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.no_depth_test = true
	mesh.surface_set_material(0, _ring_mat)
	return mesh


## SelectionBox doubles as the floor ring (mesh swapped on enter/exit) +
## persistent HUD facts (cell + center height + radius). Ring position tracks
## per frame (smooth follow while sculpting); facts refresh on rebuilds.
func _update_floor_visual() -> void:
	_update_floor_ring_pos()
	if hud != null:
		var h := float(_ground.get(_floor_cursor, 0.0))
		var sign := "+" if h >= 0.0 else ""
		hud.set_persistent(&"floor", "FLOOR (%d,%d) h=%s%.3f R=%d" % [_floor_cursor.x, _floor_cursor.y, sign, h, _floor_radius])
		hud.set_hint(FLOOR_HINT)


func _update_floor_ring_pos() -> void:
	selection_box.visible = true
	var h := float(_ground.get(_floor_cursor, 0.0))
	selection_box.position = Vector3(_floor_cursor.x - 50.0 + 0.5, h + 0.1, _floor_cursor.y - 50.0 + 0.5)


## ── transform ──────────────────────────────────────────────────────────

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
	_dirty = true
	_set_status("deleted %s — placed: %d" % [iid, _placements.size()])
	_refresh_grab_label()


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


## Saves the map; true on success (dirty cleared), false otherwise (caller
## keeps its context — the pause stays open, the menu still exits).
func save_map() -> bool:
	var name := current_map_name.strip_edges()
	if name.is_empty():
		_user_status("save aborted: empty map name")
		return false
	var data := MapIO.serialize(name, _placements, _ground, _ambiance if _amb_has_section else {})
	var issues := MapIO.validate_map(data)
	issues.append_array(MapIO.validate_refs(data, catalog))
	if not issues.is_empty():
		_user_status("SAVE ISSUES: %s" % ", ".join(issues))
		return false
	var err := JsonFile.save_atomic(_map_path(name), data)
	if err != OK:
		_user_status("save FAILED (%d)" % err)
		return false
	map_saved.emit(_map_path(name))
	_dirty = false
	_user_status("saved %s (%d placements, %d relief cells)" % [name, _placements.size(), _ground.size()])
	return true


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
	_ground = MapIO.ground_from_data(data)
	_rebuild_ground()
	# Ambiance override overlays the boot defaults (absent = defaults stay);
	# the section owns itself from here until save.
	_ambiance = (MapIO.AMBIANCE_DEFAULTS as Dictionary).duplicate()
	var amb := MapIO.ambiance_from_data(data)
	for key in amb:
		_ambiance[key] = amb[key]
	_amb_has_section = data.has("ambiance")
	_amb_preset = _match_preset()
	_apply_ambiance()
	if not issues.is_empty():
		for issue in issues:
			_set_status("LOAD ISSUE: %s" % issue)
	map_loaded.emit(path)
	current_map_name = name
	_dirty = false
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


## ── pause modal ────────────────────────────────────────────────────
## Start/S (pause_menu) and Guide/ESC (menu) toggle the pause. The modal owns all other inputs while open (gated in
## _on_input_action + _process). Grab/floor state underneath is kept as-is;
## only the camera freeze is managed (IDLE/SELECTED thaw on close).

func _open_pause() -> void:
	if _modal_open:
		return
	var content := GENERIC_MENU_SCENE.instantiate() as GenericMenu
	if content == null:
		_set_status("pause FAILED: cannot instance generic menu")
		return
	content.configure(
		"MAP PAUSED",
		"arrows move · A confirm · B cancel",
		_pause_entries(),
		_on_pause_cancel
	)
	_cam_unfreeze_on_close = not editor_camera.frozen
	editor_camera.frozen = true
	modal.open(content)
	_modal_open = true
	_modal_level = 1
	_set_status("paused")


func _close_modal() -> void:
	if not _modal_open:
		return
	modal.close()
	_modal_open = false
	_modal_level = 0
	if _cam_unfreeze_on_close:
		editor_camera.frozen = false
		_cam_unfreeze_on_close = false
	_set_status("resumed")


## Swaps the pause content for the quit-confirm (dirty QUIT only). Back goes
## the other way — one ModalDialog, two contents, never stacked.
func _show_confirm() -> void:
	var content := GENERIC_MENU_SCENE.instantiate() as GenericMenu
	if content == null:
		_set_status("quit-confirm FAILED: cannot instance generic menu")
		return
	content.configure(
		"UNSAVED CHANGES",
		"arrows move · A confirm · B back",
		[
			{"label": "QUIT WITHOUT SAVING", "call": _on_confirm_discard},
			{"label": "CANCEL", "call": _on_confirm_back},
		],
		_on_confirm_back
	)
	modal.close()
	modal.open(content)
	_modal_level = 2
	_set_status("quit-confirm — unsaved changes")


func _back_to_pause() -> void:
	if not _modal_open:
		return
	# Inline (not via _open_pause): the camera freeze flag from the original
	# open must survive the round-trip — re-opening would see a frozen camera
	# and wrongly clear the restore.
	var content := GENERIC_MENU_SCENE.instantiate() as GenericMenu
	if content == null:
		return
	content.configure(
		"MAP PAUSED",
		"arrows move · A confirm · B cancel",
		_pause_entries(),
		_on_pause_cancel
	)
	modal.close()
	modal.open(content)
	_modal_level = 1
	_set_status("paused")


## Pause rows (single source: _open_pause + _back_to_pause rebuild the same
## list). AMBIANCE swaps in the settings page like the quit-confirm does.
func _pause_entries() -> Array:
	return [
		{"label": "SAVE", "call": _on_pause_save},
		{"label": "AMBIANCE", "call": _on_pause_ambiance},
		{"label": "CANCEL", "call": _on_pause_cancel},
		{"label": "QUIT", "call": _on_pause_quit},
	]


func _on_pause_ambiance() -> void:
	_show_ambiance()


## Ambiance settings page (modal level 3): preset rows apply bundles, value
## rows adjust with ←/→ (tab actions, free in modals) and reset with A/E.
## BACK / B returns to the pause (same round-trip as the quit-confirm).
func _show_ambiance() -> void:
	var content := GENERIC_MENU_SCENE.instantiate() as GenericMenu
	if content == null:
		_set_status("ambiance FAILED: cannot instance generic menu")
		return
	var rows := []
	for id in _amb_presets:
		rows.append({"label": "Preset: %s" % str((_amb_presets[id] as Dictionary).get("label", id)), "call": _amb_apply_preset.bind(id)})
	rows.append({"label": "Preset: Default", "call": _amb_apply_preset.bind(&"__default")})
	for spec in AMBIANCE_ROWS:
		var key := str(spec.get("key", ""))
		rows.append({
			"label": str(spec.get("label", key)), "kind": "value",
			"get": _amb_display.bind(key), "adjust": _amb_adjust.bind(key),
			"reset": _amb_reset.bind(key),
		})
	rows.append({"label": "BACK", "call": _on_confirm_back})
	content.configure(
		"AMBIANCE (%s)" % _amb_preset_name(),
		"up/down move · left/right adjust · A reset · B back",
		rows,
		_on_confirm_back
	)
	modal.close()
	modal.open(content)
	_modal_level = 3
	_set_status("ambiance settings — %s" % _amb_preset_name())


## ── ambiance engine ────────────────────────────────────────────────
## Registry + live values + viewport apply. Presets fill values (never an
## id); any retouch diverges to Custom and marks dirty + owns a section.

func _load_presets() -> void:
	_amb_presets.clear()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRESETS_PATH))
	if not parsed is Dictionary:
		push_warning("Ambiance presets unreadable, defaults only")
		return
	var bundles: Variant = (parsed as Dictionary).get("presets", {})
	if not bundles is Dictionary:
		return
	for id in (bundles as Dictionary):
		var bundle: Variant = (bundles as Dictionary)[id]
		if not bundle is Dictionary:
			continue
		var flat := MapIO.ambiance_from_data({"ambiance": (bundle as Dictionary).get("values", {})})
		if not _amb_values_valid(flat):
			push_warning("Ambiance preset skipped (incomplete/out of range): %s" % id)
			continue
		_amb_presets[str(id)] = {"label": str((bundle as Dictionary).get("label", id)), "values": flat}


## A bundle is valid when it fills every flat key in bounds (fog_enabled bool).
func _amb_values_valid(flat: Dictionary) -> bool:
	for key in MapIO.AMBIANCE_NEST:
		if not (flat as Dictionary).has(key):
			return false
		if key == "fog_enabled":
			continue
		var bounds: Array = MapIO.AMBIANCE_BOUNDS[key]
		var v := float((flat as Dictionary)[key])
		if v < float(bounds[0]) or v > float(bounds[1]):
			return false
	return true


func _amb_preset_name() -> String:
	return _amb_preset if not _amb_preset.is_empty() else "Custom"


func _match_preset() -> String:
	for id in _amb_presets:
		if _ambiance == (_amb_presets[id] as Dictionary).get("values", {}):
			return str(id)
	if _ambiance == MapIO.AMBIANCE_DEFAULTS:
		return "Default"
	return ""


func _amb_apply_preset(id: StringName) -> void:
	if str(id) == "__default":
		_ambiance = (MapIO.AMBIANCE_DEFAULTS as Dictionary).duplicate()
		_amb_preset = "Default"
	else:
		if not _amb_presets.has(str(id)):
			return
		_ambiance = ((_amb_presets[str(id)] as Dictionary).get("values", {}) as Dictionary).duplicate()
		_amb_preset = str(id)
	_amb_has_section = true
	_apply_ambiance()
	_dirty = true
	_set_status("ambiance preset: %s" % _amb_preset)
	_show_ambiance()


func _amb_display(key: String) -> String:
	if key == "fog_enabled":
		return "ON" if bool(_ambiance.get(key, false)) else "OFF"
	if key == "tonemap_mode":
		var i := clampi(int(_ambiance.get(key, 2.0)), 0, TONEMAP_NAMES.size() - 1)
		return TONEMAP_NAMES[i]
	var bounds: Array = MapIO.AMBIANCE_BOUNDS.get(key, [0.0, 1.0])
	var span := float(bounds[1]) - float(bounds[0])
	var dec := 0 if span >= 100.0 else (1 if span >= 10.0 else 2)
	return "%.*f" % [dec, float(_ambiance.get(key, 0.0))]


## Bound as adjust: the menu calls adjust.call(direction), bound key lands
## second (Callable.bind appends). Applies, clamps, dirties.
func _amb_adjust(direction: int, key: String) -> void:
	var step := 0.1
	for spec in AMBIANCE_ROWS:
		if str(spec.get("key", "")) == key:
			step = float(spec.get("step", 0.1))
	var bounds: Array = MapIO.AMBIANCE_BOUNDS.get(key, [0.0, 1.0])
	var lo := float(bounds[0])
	var hi := float(bounds[1])
	if key == "fog_end":
		lo = maxf(lo, float(_ambiance.get("fog_begin", 0.0)) + 1.0)
	var v := clampf(float(_ambiance.get(key, 0.0)) + float(direction) * step, lo, hi)
	if key == "fog_enabled" or key == "tonemap_mode":
		v = roundf(v)
	_ambiance[key] = v
	_amb_preset = ""
	_amb_has_section = true
	_apply_ambiance()
	_dirty = true


func _amb_reset(key: String) -> void:
	var source: Dictionary = MapIO.AMBIANCE_DEFAULTS
	if not _amb_preset.is_empty() and _amb_preset != "Default" and _amb_presets.has(_amb_preset):
		source = (_amb_presets[_amb_preset] as Dictionary).get("values", source)
	_ambiance[key] = (source as Dictionary).get(key, (MapIO.AMBIANCE_DEFAULTS as Dictionary)[key])
	_amb_has_section = true
	_apply_ambiance()
	_dirty = true
	_set_status("ambiance %s reset" % key)


## Pushes live values to the viewport (clamped — files may carry anything
## until validation reports). Sun keeps its azimuth, takes the elevation.
func _apply_ambiance() -> void:
	var env := world_env.environment as Environment
	if env == null:
		return
	var get := func(key: String) -> float:
		var bounds: Array = MapIO.AMBIANCE_BOUNDS.get(key, [0.0, 1.0])
		return clampf(float(_ambiance.get(key, (MapIO.AMBIANCE_DEFAULTS as Dictionary).get(key, 0.0))), float(bounds[0]), float(bounds[1]))
	env.fog_enabled = bool(_ambiance.get("fog_enabled", false))
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = get.call("fog_begin")
	env.fog_depth_end = maxf(get.call("fog_end"), env.fog_depth_begin + 1.0)
	env.fog_height = get.call("fog_height")
	env.fog_height_density = get.call("fog_hdensity")
	env.tonemap_mode = clampi(int(_ambiance.get("tonemap_mode", 2.0)), 0, 4) as Environment.ToneMapper
	env.tonemap_exposure = get.call("tonemap_exposure")
	env.ambient_light_energy = get.call("ambient_energy")
	sun.light_energy = get.call("sun_energy")
	sun.rotation_degrees = Vector3(-get.call("sun_elev"), _sun_azimuth, 0.0)


func _on_pause_save() -> void:
	# Success closes (toast surfaces above the closed modal); failure keeps
	# the pause open (toast still fires behind — visible after close, 5 s).
	if save_map():
		_close_modal()


func _on_pause_cancel() -> void:
	_close_modal()


func _on_pause_quit() -> void:
	if _dirty:
		_show_confirm()
	else:
		_quit_to_menu()


func _on_confirm_discard() -> void:
	_quit_to_menu()


func _on_confirm_back() -> void:
	_back_to_pause()


func _quit_to_menu() -> void:
	_set_status("quit to map menu")
	get_tree().change_scene_to_file(MENU_SCENE)


## ── helpers ────────────────────────────────────────────────────────────

func _on_input_action(action: StringName) -> void:
	# Pause toggle (Start/S = pause_menu, Guide/ESC = menu — same gesture by
	# decision). With the modal open both step one level back: confirm →
	# pause, pause → close.
	if action == &"pause_menu" or action == &"menu":
		if not _modal_open:
			_open_pause()
		elif _modal_level == 2:
			_back_to_pause()
		else:
			_close_modal()
		return
	# Modal owns every other input while open (A/E/B navigate it) — the
	# editor underneath stays untouched (no place/grab/floor/delete).
	if _modal_open:
		return
	match action:
		&"floor_mode":
			# Y/P: the 4th editor state. Shift+P lands here too (keys are
			# shift-blind) and simply enters floor like P.
			if _floor_mode:
				_exit_floor_mode()
			else:
				_enter_floor_mode()
		&"delete_shifted":
			# R1+B: the ONLY delete path (grabbed or not). Inert in floor
			# mode — relief cells are not placements.
			if _floor_mode:
				_set_status("nothing to delete in floor mode")
				return
			_delete_selection()
		&"snap_toggle":
			# L1/Tab: grid+angle snap on/off, grabbed or not (applies next
			# transform while grabbed).
			_snap_on = not _snap_on
			_set_status("snap toggled %s" % ("ON" if _snap_on else "OFF"))
			if hud != null:
				hud.set_persistent(&"snap", "SNAP ON" if _snap_on else "SNAP OFF")
			_refresh_grab_label()
			_refresh_debug()
		&"catalog_next":
			catalog_panel.cycle_next()
		&"catalog_prev":
			catalog_panel.cycle_prev()
		&"tab_next":
			catalog_panel.next_tab()
		&"tab_prev":
			catalog_panel.prev_tab()
		&"place_select":
			# A/E: checkpoint in floor mode (stays), place/grab otherwise.
			if _floor_mode:
				_floor_commit()
			else:
				_place_or_select()
		&"deselect":
			if _floor_mode:
				if InputManager.is_shifted():
					# Shift+Q: inert too — same rule as R1+B above.
					_set_status("nothing to delete in floor mode")
				else:
					_floor_undo()
				return
			if _grabbed:
				_cancel_grab()
			elif InputManager.is_shifted():
				# Shift+Q: the shifted face of cancel (R1+B's keyboard
				# mirror — _resolve_key is shift-blind, so it lands here).
				_delete_selection()
			else:
				_select(null)
				_refresh_debug()
				_refresh_grab_label()


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
	var hit := _ground_hit(_viewport_center())
	if not hit.is_empty():
		var p: Vector3 = hit["position"]
		return p
	var origin := editor_camera.global_position
	var dir := -editor_camera.global_basis.z
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


## Dev log: every state change prints here. The on-screen STATUS label is
## deliberately narrower — snap state + save confirmations only (user
## decision); command help lives in the HINT label. User-facing writes go
## through _user_status, everything else stays log-only.
func _set_status(msg: String) -> void:
	print("[MapEditor] %s" % msg)


## User-facing transient note: log line + toast (auto-clears, never touches
## persistent status). Save confirmations go through here.
func _user_status(msg: String) -> void:
	_set_status(msg)
	if hud != null:
		hud.flash(msg)
