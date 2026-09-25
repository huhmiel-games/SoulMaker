@tool
extends Node3D

## AnimCreator steps 1-2 — authoring-rig scaffold, hands position + wrist.
##
## Two hand handles + two elbow poles (plain scene nodes, moved with the
## standard Godot gizmo — mouse) drive the Phase 0-bis winning stack:
## FABRIK3D i64/d0.3 deterministic + BoneTwistDisperser3D on each arm.
## Step 2 wrist follow is CODE-DRIVEN (global-pose override, relative mode):
## CopyTransformModifier3D proved fully inert in 4.7.2 — node AND bone
## references, minimal code-built skeleton, both pose channels, every flag
## combo (axes/all, additive, absolute path, child order) — it processes
## (signal fires) but never writes. So the tool applies the handle's
## relative rotation itself each frame: rest cube = zero offset, turned
## cube = poignée/revers at the wrist. The override wins non-destructively
## and reads back through get_bone_global_pose (bake-safe, 1-frame lag in
## live preview — invisible in the editor).
## Twist-only: TwoBoneIK3D and bare FABRIK live in the spike as reference —
## this tool builds only the Phase 0-bis winner, each wrist feature written once.
## No InputManager, no key/mouse polling: this is an editor @tool scene
## (like anim_lab), not an in-game editor — the editor viewport IS the UI.
## Metrics publish to StateLabel (Label3D, editor-visible) + ready print.
## Validator seam (tracking_error/elbow_dot/elbow_flexion/hand_bone_quat/...)
## mirrors the arm spike for the future bake guard (step 5).
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

## Solver is fixed: FABRIK3D i64/d0.3 deterministic + BoneTwistDisperser3D
## (Phase 0-bis winner). No solver switch — TwoBone / bare FABRIK stay in
## the spike; every wrist feature is implemented once.
## FABRIK budget (0-bis winning tuning — live matches measured).
@export var fab_iters := 64:
	set(v):
		fab_iters = maxi(v, 1)
		_apply_fabrik_tuning()
@export var fab_delta := 0.3:
	set(v):
		fab_delta = clampf(v, 0.01, 1.0)
		_apply_fabrik_tuning()
## Elbow poles are gizmo-moved scene nodes used only as the elbow-side
## reference for the flip metric (FABRIK holds its plane without a pole).
## Wrist orientation follow (step 2 gate): the handle's relative rotation
## (vs its rest) is applied onto the hand bone as a global-pose override.
## Toggle = A/B proof (off clears the override, hand falls back to solver).
@export var wrist_copy := true:
	set(v):
		wrist_copy = v
		_apply_wrist()
@export_tool_button("Reset handles") var reset_action: Callable = reset_handles

var _skeleton: Skeleton3D
var _fabrik := {}
var _twist := {}
var _handles := {}
var _poles := {}
var _label: Label3D
var _handle_rest_rot := {&"Left": Quaternion(), &"Right": Quaternion()}
## Fresh solver snapshot per side (written mid-pipeline, consumed pre-pipeline).
var _solve_pos := {}
var _solve_fore := {}
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
		_build_fabrik(side, handle)
		_handle_rest_rot[side] = handle.global_transform.basis.get_rotation_quaternion()
	_apply_fabrik_tuning()
	_apply_wrist()
	_built = true
	print("[AnimCreator] ready — fabrik-twist, fab i%d/d%.3f, wrist %s (gizmo handles, no keys)" % [fab_iters, fab_delta, "on" if wrist_copy else "off"])


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
	farm.active = true
	farm.modification_processed.connect(_on_ik_processed.bind(side))
	_fabrik[side] = farm
	var tw := BoneTwistDisperser3D.new()
	tw.name = "%sTwistDisperse" % String(side)
	_skeleton.add_child(tw)
	tw.set_setting_count(1)
	tw.set_root_bone_name(0, bones["upper"])
	tw.set_end_bone_name(0, bones["end"])
	tw.set_twist_from_rest(0, true)
	tw.active = true
	tw.modification_processed.connect(_on_ik_processed.bind(side))
	_twist[side] = tw


## Step 2 wrist follow (code-driven override, split across the pipeline):
## the modifier signal stores fresh solver data (_store_solver_pose), and
## _process writes the override from that snapshot (_apply_stored_wrist).
## Position is NEVER read back and NEVER the handle (read-back self-pins the
## first frame and hides the solver; the handle rips the hand past the arm's
## max extension with zero visible limit — both reported 24/09 vs the spike)
## — it is the stored parent-rebuilt solver origin, so the hand keeps the
## honest solver position (stretch limit visible, like the spike).
## Rotation is relative to the arm, never world-locked (reported 24/09:
## FABRIK preserves end-bone world orientation, so fingers froze on X):
## live parent × bind rest-local × cube delta — the wrist follows the
## forearm when translating, plus the authored cube rotation on top.
## No hand read-back anywhere, no feedback loop (the parent is never
## overridden). get_bone_global_pose_no_override is unusable (bind-pose
## semantics, not solver pose — verified by probes, avoided).
## Solver snapshot (mid-pipeline, fresh): parent-rebuilt hand origin (pure
## solver — no override on the parent) + parent world rotation (the wrist
## base — see below). Written to the skeleton by _process.
func _store_solver_pose(side: StringName) -> void:
	if _skeleton == null or _handles.is_empty():
		return
	if not _handles.has(side):
		return
	var bones: Dictionary = ARM_BONES[side]
	var hand_idx := _skeleton.find_bone(bones["end"])
	if hand_idx == -1:
		return
	var parent_idx := _skeleton.get_bone_parent(hand_idx)
	var parent_global: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(parent_idx)
	# Origin in skeleton space (override space); rotation in world frame.
	_solve_pos[side] = (_skeleton.get_bone_global_pose(parent_idx) * _skeleton.get_bone_rest(hand_idx)).origin
	_solve_fore[side] = parent_global.basis.get_rotation_quaternion()


## Override write (pre-pipeline _process, from the stored snapshot): the hand
## keeps the honest solver position and takes its orientation from the live
## parent bone × the bind rest-local × the cube delta — i.e. the wrist is
## relative to the arm (fingers follow the forearm when translating, like a
## real wrist), plus the authored cube rotation on top. No read-back of the
## hand, no feedback loop (the parent is never overridden).
func _apply_stored_wrist() -> void:
	if _skeleton == null or _handles.is_empty() or not wrist_copy:
		return
	if _solve_pos.is_empty():
		return
	for side in ARM_BONES:
		if not _solve_pos.has(side) or not _solve_fore.has(side) or not _handles.has(side):
			continue
		var handle: Node3D = _handles[side]
		var hq: Quaternion = handle.global_transform.basis.get_rotation_quaternion()
		var h0: Quaternion = _handle_rest_rot.get(side, Quaternion())
		var delta: Quaternion = h0.inverse() * hq
		var hand_idx := _skeleton.find_bone((ARM_BONES[side] as Dictionary)["end"])
		if hand_idx == -1:
			continue
		# Wrist relative to the arm: live parent × bind rest-local × delta.
		var rest_local: Quaternion = _skeleton.get_bone_rest(hand_idx).basis.get_rotation_quaternion()
		var world_q: Quaternion = (_solve_fore[side] as Quaternion) * rest_local * delta
		var sk_q: Quaternion = _skeleton.global_transform.basis.get_rotation_quaternion()
		var target := Transform3D(Basis(sk_q.inverse() * world_q * sk_q), _solve_pos[side] as Vector3)
		_skeleton.set_bone_global_pose_override(hand_idx, target, 1.0, true)


## Wrist toggle (A/B proof): off clears the override, the hand falls back
## to the raw solver pose. Only our overrides live on this skeleton.
## No other state to reset (no feedback loop by construction).
func _apply_wrist() -> void:
	if _skeleton == null:
		return
	if not wrist_copy:
		_skeleton.clear_bones_global_pose_override()


func set_wrist_copy(v: bool) -> void:
	wrist_copy = v
	_apply_wrist()


func _apply_fabrik_tuning() -> void:
	if _fabrik.is_empty():
		return
	for side in _fabrik:
		(_fabrik[side] as FABRIK3D).set_max_iterations(fab_iters)
		(_fabrik[side] as FABRIK3D).set_angular_delta_limit(fab_delta)


## Post-IK read (spike rule: only valid moment) + solver snapshot.
## PIPELINE ORDER (probes 24/09): node _process runs BEFORE skeleton
## modifier processing (its reads see rest); modifier signals run post-solve
## (fresh). A skeleton mutation made inside the signal does NOT survive
## pipeline finalization (wrist follow fell to exactly 0.0°). So: the signal
## only STORES fresh solver data, and _process WRITES the override from the
## stored snapshot (1-frame lag, invisible, exact once settled — persistent
## overrides set pre-pipeline do survive to render, proven twice).
func _on_ik_processed(side: StringName) -> void:
	_store_solver_pose(side)
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
	# Wrist write (pre-pipeline, from the stored snapshot — see
	# _on_ik_processed): label only reads below.
	_apply_stored_wrist()
	var lines := PackedStringArray()
	for side in [&"Left", &"Right"]:
		var flip := "FLIP" if float(_dot[side]) < 0.0 else "ok"
		var flex := float(_flex[side])
		var fwarn := " OVERFLEX" if flex > FLEX_WARN else ""
		lines.append("%s err=%.1fmm elbow=%s (dot %.2f) flex=%.0f%s dist=%.0fcm" % [String(side), float(_err[side]) * 1000.0, flip, float(_dot[side]), flex, fwarn, float(_prox[side]) * 100.0])
	lines.append("fabrik-twist | fab i%d/d%.3f | wrist %s | gizmo: drag/rotate handles" % [fab_iters, fab_delta, "on" if wrist_copy else "off"])
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
		(_handles[side] as Node3D).global_rotation = Vector3.ZERO
		# Zero-point follows the reset (else a saved rotated handle would
		# leave a stale rest-rot and offset the wrist after reset).
		_handle_rest_rot[side] = Quaternion()
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


## World orientation of the hand bone (step 2 gate: follow angle).
func hand_bone_quat(side: StringName) -> Quaternion:
	if _skeleton == null:
		return Quaternion()
	var bones: Dictionary = ARM_BONES.get(side, {})
	if bones.is_empty():
		return Quaternion()
	var hand_idx := _skeleton.find_bone(bones["end"])
	if hand_idx == -1:
		return Quaternion()
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(hand_idx)).basis.get_rotation_quaternion()
