extends Node3D

const AnimPrepScript := preload("res://src/cli_tools/spikes/anim_prep.gd")
const MALE_SCENE := preload("res://assets/meshes/characters/Superhero_Male_FullBody.gltf")
const LIBRARY := "res://assets/animations/sword_and_shield_anims.glb"

const WALK_ANIM := "retarget/sword_and_shield__sword and shield walk"
const IDLE_ANIM := "retarget/sword_and_shield__sword and shield idle"

const LEG_BONES := {
	&"Left": {
		"upper": &"LeftUpperLeg", "lower": &"LeftLowerLeg", "foot": &"LeftFoot",
	},
	&"Right": {
		"upper": &"RightUpperLeg", "lower": &"RightLowerLeg", "foot": &"RightFoot",
	},
}

const STEP_HEIGHT := 0.2
const STEP_DEPTH := 1.2

const SOLE_OFFSET := 0.08          # ankle height above the sole when foot is flat
const DESCEND_RANGE := 0.25        # max gap where descent may ramp the IK
const PLANT_HOLD := 0.06           # gap (m) below which the foot counts as planted
const STEP_PULL_MAX := 0.22        # max static pull-up distance onto an elevated surface
const WALK_SPEED := 1.2            # manual character advance (no root motion)

var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _character: Node3D
var _ik := {}         # side -> TwoBoneIK3D
var _targets := {}    # side -> Node3D
var _poles := {}      # side -> Node3D
var _freeze_targets: bool = false
var _label: Label
var _step: StaticBody3D
var _col_shape: CollisionShape3D
var _step_h: float = STEP_HEIGHT
var _in_idle: bool = false
var _idle_latched: bool = false
var _on_step_frames: int = 0
var _foot_state := {}  # side -> {gap: float, vel: float, phase: int}
var _cam: Camera3D
var _cam_fly: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
const _MOUSE_SENS := 0.002
const _FLY_SPEED := 4.0

const PHASE_SWING := 0
const PHASE_DESCEND := 1
const PHASE_PLANT := 2


func _ready() -> void:
	_build_lighting()
	_build_floor()
	_build_step()
	_build_camera()
	_build_character()
	_build_ik()
	_build_ui()
	if _character != null:
		_character.position.z = 3.2
	_player.play(WALK_ANIM)


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
	mi.position.y = -0.05
	add_child(mi)


func _build_step() -> void:
	_step = StaticBody3D.new()
	_step.name = "Step"
	add_child(_step)
	_col_shape = CollisionShape3D.new()
	_step.add_child(_col_shape)
	var mesh_mi := MeshInstance3D.new()
	mesh_mi.name = "StepMesh"
	_step.add_child(mesh_mi)
	_update_step()


func _update_step() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(4.0, _step_h, 2.0)
	_col_shape.shape = BoxShape3D.new()
	_col_shape.shape.size = box.size
	var mesh_mi := _step.get_node("StepMesh") as MeshInstance3D
	mesh_mi.mesh = box
	_step.position = Vector3(0, _step_h * 0.5, 5.0)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.position = Vector3(2.2, 1.4, 0.5)
	_cam.look_at_from_position(_cam.position, Vector3(0, 0.7, 4.8))
	add_child(_cam)


func _build_character() -> void:
	var scene_root: Node3D = MALE_SCENE.instantiate()
	add_child(scene_root)
	_character = scene_root
	_character.rotation.y = PI
	_skeleton = scene_root.get_node_or_null("Armature/GeneralSkeleton") as Skeleton3D
	var armature: Node3D = scene_root.get_node("Armature")
	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	_player.root_node = NodePath("..")
	armature.add_child(_player)
	var libs := AnimationLibrary.new()
	var lib: AnimationLibrary = load(LIBRARY)
	if lib == null:
		push_error("library missing: ", LIBRARY)
		return
	for anim_name in lib.get_animation_list():
		var copy: Animation = AnimPrepScript.retarget_copy(lib.get_animation(anim_name), _player, _skeleton)
		libs.add_animation("sword_and_shield__%s" % anim_name, copy)
	_player.add_animation_library("retarget", libs)


func _build_ik() -> void:
	for side: StringName in LEG_BONES:
		var bone_map: Dictionary = LEG_BONES[side]
		var ik := TwoBoneIK3D.new()
		ik.name = "%sFootIK" % side
		ik.set_setting_count(1)
		ik.set_root_bone_name(0, bone_map["upper"])
		ik.set_middle_bone_name(0, bone_map["lower"])
		ik.set_end_bone_name(0, bone_map["foot"])
		ik.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_Z)

		var target := Node3D.new()
		target.name = "%sFootTarget" % side
		_skeleton.add_child(target)

		var pole := Node3D.new()
		pole.name = "%sPole" % side
		_skeleton.add_child(pole)

		_skeleton.add_child(ik)
		ik.set_target_node(0, ik.get_path_to(target))
		ik.set_pole_node(0, ik.get_path_to(pole))
		ik.influence = 0.0
		_ik[side] = ik
		_targets[side] = target
		_poles[side] = pole
		_foot_state[side] = {"gap": 0.0, "vel": 0.0, "phase": PHASE_SWING}


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)
	_label = Label.new()
	_label.name = "StatusLabel"
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override("font_size", 14)
	canvas.add_child(_label)


func _ground_height_at(pos: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var origin := Vector3(pos.x, 100.0, pos.z)
	var end := Vector3(pos.x, -100.0, pos.z)
	var query := PhysicsRayQueryParameters3D.create(origin, end, 0x7FFFFFFF)
	var hit := space.intersect_ray(query)
	if hit.size() > 0:
		return hit["position"].y
	return 0.0


func _foot_phase(gap: float, vel: float, ground_y: float) -> int:
	if _idle_latched and ground_y > 0.1 and gap > -STEP_PULL_MAX:
		return PHASE_PLANT
	if gap < -PLANT_HOLD:
		return PHASE_SWING
	if gap < PLANT_HOLD:
		return PHASE_PLANT
	if vel < 0.0 and gap < DESCEND_RANGE:
		return PHASE_DESCEND
	return PHASE_SWING


func _update_ik(delta: float) -> void:
	if _skeleton == null or _freeze_targets:
		return
	for side: StringName in LEG_BONES:
		var bone_map: Dictionary = LEG_BONES[side]
		var hip_idx: int = _skeleton.find_bone(bone_map["upper"])
		var foot_idx: int = _skeleton.find_bone(bone_map["foot"])
		if foot_idx == -1 or hip_idx == -1:
			continue

		var foot_world := _skeleton.to_global(_skeleton.get_bone_global_pose(foot_idx).origin)
		var local_foot := _skeleton.to_local(foot_world)
		var ground_y: float = _ground_height_at(foot_world)

		var st: Dictionary = _foot_state[side]
		var gap: float = (foot_world.y - SOLE_OFFSET) - ground_y
		var vel: float = (gap - st["gap"]) / maxf(delta, 0.001)
		st["gap"] = gap
		st["vel"] = vel

		var phase: int = _foot_phase(gap, vel, ground_y)
		st["phase"] = phase

		var surface_y: float = ground_y + SOLE_OFFSET
		var pulled_y: float = minf(maxf(local_foot.y, surface_y), local_foot.y + STEP_PULL_MAX)
		var cible_y: float = local_foot.y
		if phase == PHASE_PLANT:
			st["influence_target"] = 1.0
			cible_y = surface_y
		elif phase == PHASE_DESCEND:
			st["influence_target"] = 1.0
			cible_y = pulled_y
		else:
			st["influence_target"] = 0.0
			cible_y = pulled_y

		var target: Node3D = _targets[side]
		target.position.x = local_foot.x
		target.position.z = local_foot.z
		target.position.y = cible_y

		_ik[side].influence = lerpf(_ik[side].influence, st["influence_target"], 1.0 - pow(0.001, delta))

		var hip_world := _skeleton.to_global(_skeleton.get_bone_global_pose(hip_idx).origin)
		var pole_local := _skeleton.to_local(hip_world)
		_poles[side].position = pole_local + Vector3(0, -0.1, -0.6)


func _process(delta: float) -> void:
	_move_character(delta)
	_update_ik(delta)
	_update_camera(delta)
	_update_label()


func _update_camera(delta: float) -> void:
	if _cam == null:
		return
	if _cam_fly:
		_update_fly_camera(delta)


func _update_fly_camera(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_UP):
		dir -= _cam.global_basis.z
	if Input.is_key_pressed(KEY_DOWN):
		dir += _cam.global_basis.z
	if Input.is_key_pressed(KEY_LEFT):
		dir -= _cam.global_basis.x
	if Input.is_key_pressed(KEY_RIGHT):
		dir += _cam.global_basis.x
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	if dir != Vector3.ZERO:
		_cam.position += dir.normalized() * _FLY_SPEED * delta
	_cam.rotation = Vector3(_pitch, _yaw, 0)


func _move_character(delta: float) -> void:
	if _character == null or _cam_fly:
		return
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_UP):
		dir.z += 1.0
	if Input.is_key_pressed(KEY_DOWN):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir != Vector3.ZERO:
		_character.position += dir.normalized() * WALK_SPEED * delta


func _update_label() -> void:
	if _skeleton == null:
		return
	var parts: Array[String] = ["step_h=%.2f  anim=%s  cam=%s | A=anim  F=cam  PgUp/PgDn=step  arrows=perso" % [
		_step_h, "idle" if _in_idle else "walk",
		"fly" if _cam_fly else "free",
	]]
	for side: StringName in [&"Left", &"Right"]:
		var st: Dictionary = _foot_state.get(side, {})
		var foot_idx := _skeleton.find_bone(LEG_BONES[side]["foot"])
		if foot_idx == -1:
			continue
		var foot_world := _skeleton.to_global(_skeleton.get_bone_global_pose(foot_idx).origin)
		var ground_y: float = _ground_height_at(foot_world)
		var phase_name: String = ["swing", "desc", "plant"][st.get("phase", 0)]
		parts.append("%s gap=%.3f ground=%.3f %s infl=%.2f" % [
			side, st.get("gap", 0.0), ground_y, phase_name, _ik[side].influence,
		])
	_label.text = "\n".join(parts)


func _disable_follow() -> void:
	if _cam == null:
		return
	var e := _cam.global_transform.basis.get_euler()
	_yaw = e.y
	_pitch = e.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _cam_fly:
		_yaw -= event.relative.x * _MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * _MOUSE_SENS, -1.5533, 1.5533)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				_cam_fly = not _cam_fly
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _cam_fly else Input.MOUSE_MODE_VISIBLE)
				if _cam_fly:
					_disable_follow()
			KEY_A:
				if _in_idle:
					_player.play(WALK_ANIM)
					_in_idle = false
					_idle_latched = false
					_on_step_frames = 0
				else:
					_player.play(IDLE_ANIM)
					_in_idle = true
			KEY_PAGEUP:
				_step_h = clampf(_step_h + 0.05, 0.0, 1.0)
				_update_step()
			KEY_PAGEDOWN:
				_step_h = clampf(_step_h - 0.05, 0.0, 1.0)
				_update_step()
