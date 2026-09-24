@tool
extends Node3D

## AnimCreator step 1 — authoring-rig scaffold, hands position-only.
##
## Two hand handles + two elbow poles (plain scene nodes, moved with the
## standard Godot gizmo — mouse) drive the Phase 0-bis winning stack:
## FABRIK3D i64/d0.3 deterministic + BoneTwistDisperser3D on each arm.
## TwoBoneIK3D stays as diagnostic fallback ([member solver_mode]).
## No InputManager, no key/mouse polling: this is an editor @tool scene
## (like anim_lab), not an in-game editor — the editor viewport IS the UI.
## Metrics publish to StateLabel (Label3D, editor-visible) + ready print.
## Validator seam (tracking_error/elbow_dot/elbow_flexion/...) mirrors the
## arm spike for the future bake guard (step 5).
##
## API note: the FABRIK tuning setters (set_setting_count,
## set_root/end_bone_name, set_deterministic, set_max_iterations,
## set_angular_delta_limit) are absent from the 4.7 doctool XML (incomplete
## dump for modifier classes) — verified at runtime instead: the arm spike
## calls the exact same setters headless-green (commit 77336c1). TwoBone /
## Twist setters + Label3D props verified in reference/godot47_docs/*.xml.
const ARM_BONES := {
	&"Left": {"upper": &"LeftUpperArm", "middle": &"LeftLowerArm", "end": &"LeftHand", "shoulder": &"LeftShoulder"},
	&"Right": {"upper": &"RightUpperArm", "middle": &"RightLowerArm", "end": &"RightHand", "shoulder": &"RightShoulder"},
}
const FLEX_WARN := 150.0

## Active solver (inspector dropdown, no keys): fabrik-twist = Phase 0-bis
## winner, fabrik-arm = same chain without disperser, two = analytic fallback.
@export_enum("fabrik-twist", "fabrik-arm", "two") var solver_mode := "fabrik-twist":
	set(v):
		solver_mode = v
		if is_node_ready():
			_apply_solver()
			print("[AnimCreator] solver %s" % v)
## FABRIK budget (0-bis winning tuning — live matches measured).
@export var fab_iters := 64:
	set(v):
		fab_iters = maxi(v, 1)
		_apply_fabrik_tuning()
@export var fab_delta := 0.3:
	set(v):
		fab_delta = clampf(v, 0.01, 1.0)
		_apply_fabrik_tuning()
## Elbow pole side (TwoBone only — FABRIK holds its plane without a pole).
@export_enum("+X", "-X", "+Y", "-Y", "+Z", "-Z") var pole_dir := "-Z":
	set(v):
		pole_dir = v
		_apply_pole_dir()
@export_tool_button("Reset handles") var reset_action: Callable = reset_handles

var _skeleton: Skeleton3D
var _ik := {}
var _fabrik := {}
var _twist := {}
var _handles := {}
var _poles := {}
var _label: Label3D
var _rest := {}
var _elbow_rest := {}
var _shoulder_rest := {}
var _reach := {}
var _err := {&"Left": 0.0, &"Right": 0.0}
var _dot := {&"Left": 1.0, &"Right": 1.0}
var _flex := {&"Left": 0.0, &"Right": 0.0}
var _prox := {&"Left": 0.0, &"Right": 0.0}
var _built := false
var _warned := false


func _ready() -> void:
	_build()


## Idempotent build (editor re-entry safe): clears runtime modifiers, then
## resolves the skeleton + scene handles and stacks the solvers on them.
## Handles are NEVER moved here — the .tscn holds probed rest defaults and
## the human owns them via the gizmo (Reset button re-snaps on demand).
func _build() -> void:
	_skeleton = _find_skeleton()
	_label = get_node_or_null("StateLabel") as Label3D
	if _skeleton == null:
		if not _warned:
			_warned = true
			push_warning("[AnimCreator] skeleton not resolved (RigRoot asset missing?)")
		if _label != null:
			_label.text = "AnimCreator: skeleton missing"
		return
	_clear_modifiers()
	for side: StringName in ARM_BONES:
		var handle := get_node_or_null("%sHandle" % String(side)) as Node3D
		var pole := get_node_or_null("%sPole" % String(side)) as Node3D
		if handle == null or pole == null:
			push_error("[AnimCreator] %s handle/pole node missing in scaffold" % String(side))
			return
		_handles[side] = handle
		_poles[side] = pole
		_snapshot_rest(side)
		_build_two(side, handle, pole)
		_build_fabrik(side, handle)
	_apply_pole_dir()
	_apply_fabrik_tuning()
	_apply_solver()
	_built = true
	print("[AnimCreator] ready — solver %s, fab i%d/d%.3f, pole %s (gizmo handles, no keys)" % [solver_mode, fab_iters, fab_delta, pole_dir])


func _find_skeleton() -> Skeleton3D:
	var rig := get_node_or_null("RigRoot")
	if rig == null:
		return null
	var direct := rig.get_node_or_null("Armature/GeneralSkeleton") as Skeleton3D
	if direct != null:
		return direct
	var found := rig.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D


## Frees previously built runtime modifiers (hot-reload / re-entry safety).
func _clear_modifiers() -> void:
	_ik.clear()
	_fabrik.clear()
	_twist.clear()
	if _skeleton == null:
		return
	for child in _skeleton.get_children():
		if child is SkeletonModifier3D and (str(child.name).ends_with("HandIK") or str(child.name).ends_with("FabrikArm") or str(child.name).ends_with("TwistDisperse")):
			_skeleton.remove_child(child)
			child.queue_free()


## Rest snapshot (spike formula): hand/elbow/shoulder rest + reach.
## The elbow-side reference is read live from the pole node (gizmo-moved),
## never snapshotted. Handles keep their scene positions.
func _snapshot_rest(side: StringName) -> void:
	var bones: Dictionary = ARM_BONES[side]
	var upper_idx := _skeleton.find_bone(bones["upper"])
	var hand_idx := _skeleton.find_bone(bones["end"])
	var elbow_idx := _skeleton.find_bone(bones["middle"])
	var shoulder_idx := _skeleton.find_bone(bones["shoulder"])
	if upper_idx == -1 or hand_idx == -1 or elbow_idx == -1 or shoulder_idx == -1:
		push_error("[AnimCreator] arm bones missing: %s" % String(side))
		return
	var hand_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(hand_idx).origin)
	var elbow_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(elbow_idx).origin)
	var shoulder_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(shoulder_idx).origin)
	_rest[side] = _skeleton.to_local(hand_w)
	_elbow_rest[side] = _skeleton.to_local(elbow_w)
	_shoulder_rest[side] = _skeleton.to_local(shoulder_w)
	_reach[side] = shoulder_w.distance_to(hand_w)


func _build_two(side: StringName, handle: Node3D, pole: Node3D) -> void:
	var bones: Dictionary = ARM_BONES[side]
	var ik := TwoBoneIK3D.new()
	ik.name = "%sHandIK" % String(side)
	ik.set_setting_count(1)
	ik.set_root_bone_name(0, bones["upper"])
	ik.set_middle_bone_name(0, bones["middle"])
	ik.set_end_bone_name(0, bones["end"])
	ik.set_pole_direction(0, _pole_dir_value())
	_skeleton.add_child(ik)
	ik.set_target_node(0, ik.get_path_to(handle))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.influence = 1.0
	ik.modification_processed.connect(_on_ik_processed.bind(side))
	_ik[side] = ik


func _build_fabrik(side: StringName, handle: Node3D) -> void:
	var bones: Dictionary = ARM_BONES[side]
	var farm := FABRIK3D.new()
	farm.name = "%sFabrikArm" % String(side)
	_skeleton.add_child(farm)
	farm.set_setting_count(1)
	farm.set_root_bone_name(0, bones["upper"])
	farm.set_end_bone_name(0, bones["end"])
	farm.set_target_node(0, farm.get_path_to(handle))
	farm.set_deterministic(true)
	farm.set_max_iterations(fab_iters)
	farm.set_angular_delta_limit(fab_delta)
	farm.influence = 1.0
	farm.modification_processed.connect(_on_ik_processed.bind(side))
	_fabrik[side] = farm
	var tw := BoneTwistDisperser3D.new()
	tw.name = "%sTwistDisperse" % String(side)
	_skeleton.add_child(tw)
	tw.set_setting_count(1)
	tw.set_root_bone_name(0, bones["upper"])
	tw.set_end_bone_name(0, bones["end"])
	tw.set_twist_from_rest(0, true)
	tw.modification_processed.connect(_on_ik_processed.bind(side))
	_twist[side] = tw


## Solver switch: toggles active flags only — handles are user-owned, never
## reset here (unlike the spike, whose targets were code-driven).
func _apply_solver() -> void:
	if not _built and _fabrik.is_empty():
		return
	for side in ARM_BONES:
		if not _ik.has(side):
			continue
		(_ik[side] as TwoBoneIK3D).active = solver_mode == "two"
		(_fabrik[side] as FABRIK3D).active = solver_mode == "fabrik-arm" or solver_mode == "fabrik-twist"
		(_twist[side] as BoneTwistDisperser3D).active = solver_mode == "fabrik-twist"


func _apply_fabrik_tuning() -> void:
	if _fabrik.is_empty():
		return
	for side in _fabrik:
		(_fabrik[side] as FABRIK3D).set_max_iterations(fab_iters)
		(_fabrik[side] as FABRIK3D).set_angular_delta_limit(fab_delta)


func _apply_pole_dir() -> void:
	if _ik.is_empty():
		return
	for side in _ik:
		(_ik[side] as TwoBoneIK3D).set_pole_direction(0, _pole_dir_value())


func _pole_dir_value() -> int:
	match pole_dir:
		"+X":
			return SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_X
		"-X":
			return SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_X
		"+Y":
			return SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_Y
		"-Y":
			return SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_Y
		"+Z":
			return SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_Z
	return SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_Z


## Post-IK read (spike rule: only valid moment): hand tracking error +
## elbow side vs the pole-side reference (dot < 0 = flipped) + flexion.
func _on_ik_processed(side: StringName) -> void:
	var bones: Dictionary = ARM_BONES[side]
	var hand_idx := _skeleton.find_bone(bones["end"])
	var elbow_idx := _skeleton.find_bone(bones["middle"])
	var shoulder_idx := _skeleton.find_bone(bones["shoulder"])
	var hand_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(hand_idx).origin)
	var elbow_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(elbow_idx).origin)
	var shoulder_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(shoulder_idx).origin)
	var handle: Node3D = _handles[side]
	var pole: Node3D = _poles[side]
	_err[side] = hand_w.distance_to(handle.global_position)
	var ref: Vector3 = (pole.global_position - shoulder_w).normalized()
	var d: Vector3 = (elbow_w - shoulder_w).normalized()
	_dot[side] = ref.dot(d)
	_flex[side] = rad_to_deg((elbow_w - shoulder_w).angle_to(hand_w - elbow_w))
	_prox[side] = hand_w.distance_to(shoulder_w)


func _process(_delta: float) -> void:
	if _label == null or _skeleton == null:
		return
	var lines := PackedStringArray()
	for side in [&"Left", &"Right"]:
		var flip := "FLIP" if float(_dot[side]) < 0.0 else "ok"
		var flex := float(_flex[side])
		var fwarn := " OVERFLEX" if flex > FLEX_WARN else ""
		lines.append("%s err=%.1fmm elbow=%s (dot %.2f) flex=%.0f%s dist=%.0fcm" % [String(side), float(_err[side]) * 1000.0, flip, float(_dot[side]), flex, fwarn, float(_prox[side]) * 100.0])
	lines.append("solver %s | fab i%d/d%.3f | pole %s | gizmo: drag handles" % [solver_mode, fab_iters, fab_delta, pole_dir])
	_label.text = "\n".join(lines)


## Re-snaps handles to rest + poles behind the elbows (Reset button).
func reset_handles() -> void:
	if _skeleton == null or _handles.is_empty():
		push_warning("[AnimCreator] reset: rig not built yet")
		return
	var rig := get_node_or_null("RigRoot") as Node3D
	var back := Vector3(0, 0, -1)
	if rig != null:
		back = -rig.global_transform.basis.z.normalized()
	for side in ARM_BONES:
		var elbow_l: Vector3 = _elbow_rest.get(side, Vector3.ZERO)
		var elbow_w: Vector3 = _skeleton.to_global(elbow_l)
		(_handles[side] as Node3D).global_position = _skeleton.to_global(_rest[side] as Vector3)
		(_poles[side] as Node3D).global_position = elbow_w + back * 0.45 + Vector3(0, 0.1, 0)
	print("[AnimCreator] handles reset")


## Validator seam (mirrors the spike — future bake guard).
func hand_rest_local(side: StringName) -> Vector3:
	return _rest.get(side, Vector3.ZERO)


func reach_of(side: StringName) -> float:
	return float(_reach.get(side, 0.5))


func set_hand_target(side: StringName, skeleton_local_pos: Vector3) -> void:
	if _handles.has(side) and _skeleton != null:
		(_handles[side] as Node3D).global_position = _skeleton.to_global(skeleton_local_pos)


func tracking_error(side: StringName) -> float:
	return float(_err.get(side, -1.0))


func elbow_dot(side: StringName) -> float:
	return float(_dot.get(side, 0.0))


func elbow_flexion(side: StringName) -> float:
	return float(_flex.get(side, 0.0))


func hand_shoulder_dist(side: StringName) -> float:
	return float(_prox.get(side, 0.0))
