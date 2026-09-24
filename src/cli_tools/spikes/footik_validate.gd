extends SceneTree

const FLOOR_ON := 0.20
const TOTAL_FRAMES := 300
const SAMPLE_EVERY := 3
const PENETRATION_TOL := 0.06

var _on_scene: Node
var _off_scene: Node
var _frame: int = 0
var _scenes_ready: bool = false
var _setup_done: bool = false

var _on_penetration: float = 0.0   # maximum amount the on-scene foot sank below ground
var _off_penetration: float = 0.0
var _on_max_above_ground: float = 0.0
var _on_samples: int = 0
var _on_min: float = 99.0
var _on_max: float = -99.0
var _off_min: float = 99.0
var _off_max: float = -99.0
var _off_samples: int = 0
var _left_on_signal: float = NAN


func _initialize() -> void:
	_on_scene = load("res://scenes/spikes/footik_test.tscn").instantiate()
	_off_scene = load("res://scenes/spikes/footik_test.tscn").instantiate()
	_on_scene.position = Vector3(-1.5, 0, 0)
	_off_scene.position = Vector3(1.5, 0, 0)
	_on_scene._step_h = FLOOR_ON
	root.add_child.call_deferred(_on_scene)
	root.add_child.call_deferred(_off_scene)


func _toggle_scene_ik(scene: Node, on: bool) -> void:
	for side: StringName in [&"Left", &"Right"]:
		var ik := scene.get_node_or_null("Superhero_Male_FullBody/Armature/GeneralSkeleton/%sFootIK" % side) as SkeletonModifier3D
		if ik:
			ik.active = on


func _connect_signal_logging(scene: Node, tag: String) -> void:
	var skeleton := scene.get_node_or_null("Superhero_Male_FullBody/Armature/GeneralSkeleton") as Skeleton3D
	if skeleton == null:
		return
	for side: StringName in [&"Left", &"Right"]:
		var ik := skeleton.get_node_or_null("%sFootIK" % side) as SkeletonModifier3D
		if ik:
			ik.modification_processed.connect(_on_signal.bind(scene, skeleton, side, tag))


func _on_signal(scene: Node, skeleton: Skeleton3D, side: StringName, tag: String) -> void:
	var eidx := skeleton.find_bone(LEG_BONES[side]["foot"])
	if eidx == -1:
		return
	var foot_world := skeleton.to_global(skeleton.get_bone_global_pose(eidx).origin)
	var ground: float = scene._ground_height_at(foot_world)
	var penetration: float = ground - foot_world.y
	var above_ground: float = foot_world.y - ground
	if tag == "on":
		_on_min = minf(_on_min, foot_world.y)
		_on_max = maxf(_on_max, foot_world.y)
		_on_penetration = maxf(_on_penetration, penetration)
		_on_max_above_ground = maxf(_on_max_above_ground, above_ground)
		_on_samples += 1
		_left_on_signal = foot_world.y + 0 if side == &"Left" else _left_on_signal
	elif tag == "off":
		_off_min = minf(_off_min, foot_world.y)
		_off_max = maxf(_off_max, foot_world.y)
		_off_samples += 1
		_off_penetration = maxf(_off_penetration, penetration)


const LEG_BONES := {
	&"Left": {"foot": &"LeftFoot"},
	&"Right": {"foot": &"RightFoot"},
}


func _sample_off_scene_foot_penetration() -> void:
	var skeleton := _off_scene.get_node_or_null("Superhero_Male_FullBody/Armature/GeneralSkeleton") as Skeleton3D
	if skeleton == null:
		return
	for side: StringName in [&"Left", &"Right"]:
		var eidx := skeleton.find_bone(LEG_BONES[side]["foot"])
		if eidx == -1:
			continue
		var foot_world := skeleton.to_global(skeleton.get_bone_global_pose(eidx).origin)
		var ground: float = _off_scene._ground_height_at(foot_world)
		var penetration: float = ground - foot_world.y
		_off_penetration = maxf(_off_penetration, penetration)
		_off_min = minf(_off_min, foot_world.y)
		_off_max = maxf(_off_max, foot_world.y)
		_off_samples += 1


func _process(_delta: float) -> bool:
	_frame += 1
	if not _scenes_ready:
		if _frame >= 5 and _on_scene.is_inside_tree() and _off_scene.is_inside_tree():
			_scenes_ready = true
		else:
			return false
	if not _setup_done:
		_setup_done = true
		_toggle_scene_ik(_off_scene, false)
		_connect_signal_logging(_on_scene, "on")
		print("off IK disabled; step height=%.2f, perso walks toward z=5" % FLOOR_ON)

	if _frame % SAMPLE_EVERY == 0:
		_sample_off_scene_foot_penetration()

	if _frame >= TOTAL_FRAMES:
		print("")
		print("=== footik validation ===")
		print("  on-scene  footY min=%.4f max=%.4f samples=%d" % [_on_min, _on_max, _on_samples])
		print("  off-scene footY min=%.4f max=%.4f samples=%d" % [_off_min, _off_max, _off_samples])
		print("  penetration over ground (must be <= %.2f):" % PENETRATION_TOL)
		print("    IK  ON: %.4f" % _on_penetration)
		print("    IK OFF: %.4f" % _off_penetration)
		print("  foot above ground on-scene (must stay small while clamped): %.4f" % _on_max_above_ground)
		print("")
		var failures: int = 0
		if _on_penetration <= PENETRATION_TOL:
			print("PASS: IK keeps feet above ground (penetration=%.4f)" % _on_penetration)
		else:
			print("FAIL: IK feet sank into ground (penetration=%.4f)" % _on_penetration)
			failures += 1
		if _off_penetration > _on_penetration + 0.01:
			print("PASS: without IK the feet sink deeper (%.4f vs %.4f)" % [_off_penetration, _on_penetration])
		else:
			print("FAIL: no measurable IK effect on penetration (off=%.4f on=%.4f)" % [_off_penetration, _on_penetration])
			failures += 1
		print("")
		if failures == 0:
			print("RESULT: ALL OK (feet tracked ground; IK-OFF sinks)")
		else:
			print("RESULT: %d FAILURE(S)" % failures)
		quit()
		return true
	return false