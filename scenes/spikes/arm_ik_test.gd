extends Node3D

## Phase 0 arm-IK re-spike (anim_creator gate — the P0 legs spike FAILED on
## orientation/poles, this re-proves the solver family on arms before any rig
## work): TwoBoneIK3D per arm on the male rest pose, hand targets + elbow
## poles, all code-built like the footik spike. Keys drive the selected hand
## target; the headless validator (src/cli_tools/spikes/arm_ik_validate.gd)
## sweeps every pole direction over the reach envelope and reports tracking
## error + elbow flips. GO = max error <= 0.05 m, 0 flips, human visual OK —
## else the Blender workflow wins and the in-Godot rig is dropped.
##
## Recipe (human): run scenes/spikes/arm_ik_test.tscn — Tab selects the hand,
## arrows move its target planar, PgUp/PgDn vertical (Shift = coarse), Space
## toggles IK, P cycles the pole direction, R resets targets to rest; mouse
## orbits around the torso, wheel zooms (0.8-4 m). Each hand target carries a
## cube: C toggles the mouse between orbit-camera and cube-drag (left button,
## camera-facing plane), the selected cube glows orange. Elbow flexion reads
## live in the label (0 = straight, warn > 150). Report: elbow stable on
## the pole side through the whole envelope at the default direction, and if
## P was needed, which direction fixed it.
const MALE_SCENE := preload("res://assets/meshes/characters/Superhero_Male_FullBody.gltf")

const ARM_BONES := {
	&"Left": {"upper": &"LeftUpperArm", "middle": &"LeftLowerArm", "end": &"LeftHand", "shoulder": &"LeftShoulder"},
	&"Right": {"upper": &"RightUpperArm", "middle": &"RightLowerArm", "end": &"RightHand", "shoulder": &"RightShoulder"},
}
const BODY_ROOT := &"Spine"

## 0-bis solver modes (T cycles): two = TwoBoneIK baseline (upper->hand +
## pole); fabrik-arm = FABRIK3D on the same 2-bone chain (defaults = winning
## tuning i64/d0.3 from the validator matrix — live matches measured, so the
## eye judges the same solver the bot measured); fabrik-body = FABRIK3D
## spine->hand (vaulted: unstable); fabrik-twist = fabrik-arm +
## BoneTwistDisperser3D on the forearm.
const SOLVER_MODES := [&"two", &"fabrik-arm", &"fabrik-body", &"fabrik-twist"]

const POLE_DIRS := [
	SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_X, SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_X,
	SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_Y, SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_Y,
	SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_Z, SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_Z,
]
const POLE_NAMES := ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]

const STEP := 0.05
const STEP_COARSE := 0.2

var _skeleton: Skeleton3D
var _character: Node3D
var _ik := {}
var _fabrik_arm := {}
var _fabrik_body := {}
var _twist := {}
var _targets := {}
var _poles := {}
var _rest := {}       # side -> hand rest pos (skeleton local)
var _shoulder_rest := {}  # side -> shoulder rest pos (skeleton local)
var _reach := {}      # side -> shoulder->hand rest length
var _ref_dir := {}    # side -> pole-side reference dir (shoulder-centered, global)
var _err := {&"Left": 0.0, &"Right": 0.0}
var _dot := {&"Left": 1.0, &"Right": 1.0}
var _flex := {&"Left": 0.0, &"Right": 0.0}
var _prox := {&"Left": 0.0, &"Right": 0.0}
const FLEX_WARN := 150.0
var _selected: StringName = &"Left"
var _pole_idx := 5  # MINUS_Z first (legs-proven value)
var _solver := &"two"
var _fab_iters := 64
var _fab_delta := 0.3
var _label: Label
var _cubes := {}      # side -> MeshInstance3D (child of the hand target)
var _mat_sel: StandardMaterial3D
var _mat_idle: StandardMaterial3D
var _mouse_mode := "cam"  # cam = orbit, drag = move selected cube
var _dragging := false
const CUBE_SIZE := 0.06
const PICK_RADIUS := 0.12

## Spike-local inspection camera (mouse only — keyboard stays on the IK
## targets): motion orbits around the torso focus, wheel zooms. Kept in the
## spike on purpose: OrbitCamera's fixed 18 m distance, arrow pan and
## no-zoom design don't fit close joint inspection.
var _cam: Camera3D
var _cam_focus := Vector3(0, 0.9, 0)
var _cam_dist := 2.2
var _cam_yaw := 0.5
var _cam_pitch := 0.18
const CAM_SENS := 0.005
const CAM_MIN_DIST := 0.8
const CAM_MAX_DIST := 4.0
const CAM_MIN_PITCH := -1.2
const CAM_MAX_PITCH := 1.2


func _ready() -> void:
	_build_lighting()
	_build_floor()
	_build_camera()
	_build_character()
	_build_ik()
	_build_ui()
	print("[ArmIK] ready — solver two, pole %s, Tab/Arrows/PgUpDn move, Space IK, P pole, T solver, R reset, mouse orbit/wheel zoom" % POLE_NAMES[_pole_idx])


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)


func _build_floor() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	var box := BoxMesh.new()
	box.size = Vector3(12, 0.1, 12)
	mi.mesh = box
	mi.position = Vector3(0, -0.05, 0)
	add_child(mi)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "Camera"
	add_child(_cam)
	_apply_cam()


## Recomputes the camera transform from yaw/pitch/dist around the focus.
func _apply_cam() -> void:
	var cp := cos(_cam_pitch)
	_cam.position = _cam_focus + Vector3(sin(_cam_yaw) * cp, sin(_cam_pitch), cos(_cam_yaw) * cp) * _cam_dist
	_cam.look_at(_cam_focus)


func _input(event: InputEvent) -> void:
	if _cam == null:
		return
	if event is InputEventMouseMotion:
		if _mouse_mode == "cam":
			_cam_yaw -= (event as InputEventMouseMotion).relative.x * CAM_SENS
			_cam_pitch = clampf(_cam_pitch - (event as InputEventMouseMotion).relative.y * CAM_SENS, CAM_MIN_PITCH, CAM_MAX_PITCH)
			_apply_cam()
		elif _dragging:
			_drag_selected_to_mouse()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = clampf(_cam_dist * 0.9, CAM_MIN_DIST, CAM_MAX_DIST)
			_apply_cam()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = clampf(_cam_dist * 1.1, CAM_MIN_DIST, CAM_MAX_DIST)
			_apply_cam()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed and _mouse_mode == "drag" and _pick_cube_at_mouse()


## Picks the nearest hand cube under the mouse (sphere test, no colliders):
## selects it on click, returns true when a cube was hit (starts the drag).
func _pick_cube_at_mouse() -> bool:
	var mpos := get_viewport().get_mouse_position()
	var origin := _cam.project_ray_origin(mpos)
	var dir := _cam.project_ray_normal(mpos)
	var best_side: StringName = &""
	var best_d := PICK_RADIUS
	for side in _targets:
		var c: Vector3 = (_targets[side] as Node3D).global_position
		var t := (c - origin).dot(dir)
		var d: float = (origin + dir * maxf(t, 0.0) - c).length()
		if d < best_d:
			best_d = d
			best_side = side
	if best_side != &"":
		_selected = best_side
		_refresh_cube_colors()
		return true
	return false


## Slides the selected hand target on the camera-facing plane through its
## current position (skeleton-local write — the IK follows live).
func _drag_selected_to_mouse() -> void:
	var mpos := get_viewport().get_mouse_position()
	var origin := _cam.project_ray_origin(mpos)
	var dir := _cam.project_ray_normal(mpos)
	var target: Node3D = _targets[_selected]
	var n: Vector3 = -_cam.global_transform.basis.z.normalized()
	var plane := Plane(n, target.global_position.dot(n))
	var hit: Variant = plane.intersects_ray(origin, dir)
	if hit != null:
		target.global_position = hit


func _build_character() -> void:
	var scene_root: Node3D = MALE_SCENE.instantiate()
	add_child(scene_root)
	_character = scene_root
	_character.rotation.y = PI
	_skeleton = scene_root.get_node_or_null("Armature/GeneralSkeleton") as Skeleton3D
	if _skeleton == null:
		push_error("[ArmIK] GeneralSkeleton not found")


func _build_ik() -> void:
	if _skeleton == null:
		return
	_mat_sel = StandardMaterial3D.new()
	_mat_sel.albedo_color = Color(1.0, 0.55, 0.1, 0.85)
	_mat_sel.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_sel.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_idle = StandardMaterial3D.new()
	_mat_idle.albedo_color = Color(0.2, 0.8, 1.0, 0.6)
	_mat_idle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_idle.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var back_w := -_character.global_transform.basis.z.normalized()
	for side: StringName in ARM_BONES:
		var bones: Dictionary = ARM_BONES[side]
		var upper_idx := _skeleton.find_bone(bones["upper"])
		var hand_idx := _skeleton.find_bone(bones["end"])
		var elbow_idx := _skeleton.find_bone(bones["middle"])
		var shoulder_idx := _skeleton.find_bone(bones["shoulder"])
		if upper_idx == -1 or hand_idx == -1 or elbow_idx == -1 or shoulder_idx == -1:
			push_error("[ArmIK] arm bones missing: %s" % String(side))
			return
		var hand_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(hand_idx).origin)
		var elbow_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(elbow_idx).origin)
		var shoulder_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(shoulder_idx).origin)
		_rest[side] = _skeleton.to_local(hand_w)
		_shoulder_rest[side] = _skeleton.to_local(shoulder_w)
		_reach[side] = shoulder_w.distance_to(hand_w)
		var pole_w := elbow_w + back_w * 0.45 + Vector3(0, 0.1, 0)
		_ref_dir[side] = (pole_w - shoulder_w).normalized()
		var ik := TwoBoneIK3D.new()
		ik.name = "%sHandIK" % String(side)
		ik.set_setting_count(1)
		ik.set_root_bone_name(0, bones["upper"])
		ik.set_middle_bone_name(0, bones["middle"])
		ik.set_end_bone_name(0, bones["end"])
		ik.set_pole_direction(0, POLE_DIRS[_pole_idx])
		var target := Node3D.new()
		target.name = "%sHandTarget" % String(side)
		_skeleton.add_child(target)
		target.position = _rest[side]
		var pole := Node3D.new()
		pole.name = "%sElbowPole" % String(side)
		_skeleton.add_child(pole)
		pole.position = _skeleton.to_local(pole_w)
		_skeleton.add_child(ik)
		ik.set_target_node(0, ik.get_path_to(target))
		ik.set_pole_node(0, ik.get_path_to(pole))
		ik.influence = 1.0
		ik.modification_processed.connect(_on_ik_processed.bind(side))
		_ik[side] = ik
		_targets[side] = target
		_poles[side] = pole
		_build_fabrik(side, bones, target)
		var cube := MeshInstance3D.new()
		cube.name = "%sHandCube" % String(side)
		var box := BoxMesh.new()
		box.size = Vector3.ONE * CUBE_SIZE
		cube.mesh = box
		target.add_child(cube)
		_cubes[side] = cube
	_refresh_cube_colors()


func _build_ui() -> void:
	_label = Label.new()
	_label.name = "State"
	_label.position = Vector2(16, 16)
	_label.size = Vector2(640, 200)
	add_child(_label)


## Orange on the selected hand target, cyan on the other.
func _refresh_cube_colors() -> void:
	for side in _cubes:
		(_cubes[side] as MeshInstance3D).set_surface_override_material(0, _mat_sel if side == _selected else _mat_idle)


## 0-bis builders: FABRIK solvers share the hand target nodes; only the
## active solver runs (SkeletonModifier3D.active). Twist disperser is added
## last so it executes after the solver in the modifier stack.
func _build_fabrik(side: StringName, bones: Dictionary, target: Node3D) -> void:
	var farm := FABRIK3D.new()
	farm.name = "%sFabrikArm" % String(side)
	_skeleton.add_child(farm)
	farm.set_setting_count(1)
	farm.set_root_bone_name(0, bones["upper"])
	farm.set_end_bone_name(0, bones["end"])
	farm.set_target_node(0, farm.get_path_to(target))
	farm.set_deterministic(true)
	farm.set_max_iterations(_fab_iters)
	farm.set_angular_delta_limit(_fab_delta)
	farm.influence = 1.0
	farm.active = false
	farm.modification_processed.connect(_on_ik_processed.bind(side))
	_fabrik_arm[side] = farm
	var fbody := FABRIK3D.new()
	fbody.name = "%sFabrikBody" % String(side)
	_skeleton.add_child(fbody)
	fbody.set_setting_count(1)
	fbody.set_root_bone_name(0, BODY_ROOT)
	fbody.set_end_bone_name(0, bones["end"])
	fbody.set_target_node(0, fbody.get_path_to(target))
	fbody.set_deterministic(true)
	fbody.set_max_iterations(_fab_iters)
	fbody.set_angular_delta_limit(_fab_delta)
	fbody.influence = 1.0
	fbody.active = false
	fbody.modification_processed.connect(_on_ik_processed.bind(side))
	_fabrik_body[side] = fbody
	var tw := BoneTwistDisperser3D.new()
	tw.name = "%sTwistDisperse" % String(side)
	_skeleton.add_child(tw)
	tw.set_setting_count(1)
	tw.set_root_bone_name(0, bones["upper"])
	tw.set_end_bone_name(0, bones["end"])
	tw.set_twist_from_rest(0, true)
	tw.active = false
	tw.modification_processed.connect(_on_ik_processed.bind(side))
	_twist[side] = tw


## Switches the running solver (T cycles, validator drives): exactly one
## solver per side runs; the twist disperser only joins fabrik-twist.
func set_solver_mode(mode: StringName) -> void:
	if not mode in SOLVER_MODES:
		push_warning("[ArmIK] unknown solver '%s'" % String(mode))
		return
	_solver = mode
	for side in ARM_BONES:
		(_ik[side] as TwoBoneIK3D).active = mode == &"two"
		(_fabrik_arm[side] as FABRIK3D).active = mode == &"fabrik-arm" or mode == &"fabrik-twist"
		(_fabrik_body[side] as FABRIK3D).active = mode == &"fabrik-body"
		(_twist[side] as BoneTwistDisperser3D).active = mode == &"fabrik-twist"
	reset_targets()
	print("[ArmIK] solver %s" % String(mode))


func solver_mode() -> StringName:
	return _solver


## 0-bis tuning: FABRIK iteration budget + per-joint angular step (global,
## like deterministic). Low delta + few iterations = smooth but lazy (never
## reaches); raise both until tracking converges while staying natural.
func set_fabrik_tuning(iters: int, delta: float) -> void:
	_fab_iters = iters
	_fab_delta = delta
	for side in ARM_BONES:
		(_fabrik_arm[side] as FABRIK3D).set_max_iterations(iters)
		(_fabrik_arm[side] as FABRIK3D).set_angular_delta_limit(delta)
		(_fabrik_body[side] as FABRIK3D).set_max_iterations(iters)
		(_fabrik_body[side] as FABRIK3D).set_angular_delta_limit(delta)
	print("[ArmIK] fabrik tuning i%d/d%.3f" % [iters, delta])


## Post-IK read (the only valid moment per the footik rule): hand tracking
## error + elbow side vs the pole-side reference (dot < 0 = flipped).
func _on_ik_processed(side: StringName) -> void:
	var bones: Dictionary = ARM_BONES[side]
	var hand_idx := _skeleton.find_bone(bones["end"])
	var elbow_idx := _skeleton.find_bone(bones["middle"])
	var shoulder_idx := _skeleton.find_bone(bones["shoulder"])
	var hand_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(hand_idx).origin)
	var elbow_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(elbow_idx).origin)
	var shoulder_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(shoulder_idx).origin)
	var target: Node3D = _targets[side]
	_err[side] = hand_w.distance_to(target.global_position)
	var d: Vector3 = (elbow_w - shoulder_w).normalized()
	_dot[side] = (_ref_dir[side] as Vector3).dot(d)
	# Elbow flexion: 0 = straight arm, ~145 = human max. Warn-only (a hard
	# clamp would fight the solver) — the bake guard enforces it later.
	_flex[side] = rad_to_deg((elbow_w - shoulder_w).angle_to(hand_w - elbow_w))
	_prox[side] = hand_w.distance_to(shoulder_w)


func _process(_delta: float) -> void:
	_drive_keys()
	var lines := PackedStringArray()
	for side in [&"Left", &"Right"]:
		var mark := ">>" if side == _selected else "  "
		var flip := "FLIP" if float(_dot[side]) < 0.0 else "ok"
		var flex := float(_flex[side])
		var fwarn := " OVERFLEX" if flex > FLEX_WARN else ""
		lines.append("%s%s err=%.1fmm elbow=%s (dot %.2f) flex=%.0f%s dist=%.0fcm" % [mark, String(side), float(_err[side]) * 1000.0, flip, float(_dot[side]), flex, fwarn, float(_prox[side]) * 100.0])
	lines.append("solver %s | fab i%d/d%.3f | pole %s | IK %s | mouse:%s | Tab/Arrows/PgUpDn Space P C T R" % [String(_solver), _fab_iters, _fab_delta, POLE_NAMES[_pole_idx], "on" if _active_influence() > 0.5 else "off", _mouse_mode])
	_label.text = "\n".join(lines)


func _drive_keys() -> void:
	if Input.is_key_pressed(KEY_TAB) and not _tab_held:
		_tab_held = true
		_selected = &"Right" if _selected == &"Left" else &"Left"
		_refresh_cube_colors()
	elif not Input.is_key_pressed(KEY_TAB):
		_tab_held = false
	var step := STEP_COARSE if Input.is_key_pressed(KEY_SHIFT) else STEP
	var target: Node3D = _targets[_selected]
	if Input.is_key_pressed(KEY_LEFT):
		target.position.x -= step
	if Input.is_key_pressed(KEY_RIGHT):
		target.position.x += step
	if Input.is_key_pressed(KEY_UP):
		target.position.z -= step
	if Input.is_key_pressed(KEY_DOWN):
		target.position.z += step
	if Input.is_key_pressed(KEY_PAGEUP):
		target.position.y += step
	if Input.is_key_pressed(KEY_PAGEDOWN):
		target.position.y -= step
	if Input.is_key_pressed(KEY_SPACE) and not _space_held:
		_space_held = true
		var level := 0.0 if _active_influence() > 0.5 else 1.0
		for solver in [_ik[_selected], _fabrik_arm[_selected], _fabrik_body[_selected]]:
			(solver as SkeletonModifier3D).influence = level
		print("[ArmIK] %s influence %s" % [String(_selected), level])
	elif not Input.is_key_pressed(KEY_SPACE):
		_space_held = false
	if Input.is_key_pressed(KEY_P) and not _p_held:
		_p_held = true
		set_pole_dir((_pole_idx + 1) % POLE_DIRS.size())
	elif not Input.is_key_pressed(KEY_P):
		_p_held = false
	if Input.is_key_pressed(KEY_R):
		reset_targets()
	if Input.is_key_pressed(KEY_T) and not _t_held:
		_t_held = true
		set_solver_mode(SOLVER_MODES[(SOLVER_MODES.find(_solver) + 1) % SOLVER_MODES.size()])
	elif not Input.is_key_pressed(KEY_T):
		_t_held = false
	if Input.is_key_pressed(KEY_C) and not _c_held:
		_c_held = true
		_mouse_mode = "drag" if _mouse_mode == "cam" else "cam"
		_dragging = false
		print("[ArmIK] mouse: %s" % _mouse_mode)
	elif not Input.is_key_pressed(KEY_C):
		_c_held = false


var _tab_held := false
var _space_held := false
var _p_held := false
var _c_held := false
var _t_held := false


## Influence of the currently running solver (label + Space probe).
func _active_influence() -> float:
	if _solver == &"fabrik-arm" or _solver == &"fabrik-twist":
		return (_fabrik_arm[_selected] as FABRIK3D).influence
	if _solver == &"fabrik-body":
		return (_fabrik_body[_selected] as FABRIK3D).influence
	return (_ik[_selected] as TwoBoneIK3D).influence


## Validator + recipe seam below (no scene, no input needed).


func hand_rest_local(side: StringName) -> Vector3:
	return _rest.get(side, Vector3.ZERO)


func shoulder_rest_local(side: StringName) -> Vector3:
	return _shoulder_rest.get(side, Vector3.ZERO)


func reach_of(side: StringName) -> float:
	return float(_reach.get(side, 0.5))


func set_hand_target(side: StringName, local_pos: Vector3) -> void:
	(_targets[side] as Node3D).position = local_pos


func reset_targets() -> void:
	for side in _targets:
		(_targets[side] as Node3D).position = _rest[side]
	print("[ArmIK] targets reset")


func tracking_error(side: StringName) -> float:
	return float(_err.get(side, -1.0))


func elbow_dot(side: StringName) -> float:
	return float(_dot.get(side, 0.0))


func elbow_flexion(side: StringName) -> float:
	return float(_flex.get(side, 0.0))


func hand_shoulder_dist(side: StringName) -> float:
	return float(_prox.get(side, 0.0))


func set_pole_dir(idx: int) -> void:
	_pole_idx = clampi(idx, 0, POLE_DIRS.size() - 1)
	for side in _ik:
		(_ik[side] as TwoBoneIK3D).set_pole_direction(0, POLE_DIRS[_pole_idx])
	reset_targets()
	print("[ArmIK] pole %s" % POLE_NAMES[_pole_idx])


func pole_dir_name() -> String:
	return POLE_NAMES[_pole_idx]
