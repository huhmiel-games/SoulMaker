@tool
extends Node3D

## AnimCreator steps 1-3 — authoring-rig scaffold, hands position + wrist,
## feet position.
##
## Hand + foot handles (plain scene nodes, moved with the standard Godot
## gizmo — mouse) drive one solver per limb TYPE (never per-feature ×3):
## arms = FABRIK3D i64/d0.3 deterministic + BoneTwistDisperser3D (Phase 0-bis
## feel verdict — the wrist needs the disperser), legs = TwoBoneIK3D analytic
## + REAL front pole node (knees must NEVER invert: FABRIK holds no plane and
## flips at extremes — spike fold-fabrik 4 flips, human eye confirmed dot<0 =
## inverted every time; TwoBone+pole pins the plane by construction).
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
## Legs mirror the arms (step 3, position-only feet — no ankle orientation
## yet): FABRIK root = thigh, hip reference = Hips (shared, never overridden).
const LEG_BONES := {
	&"LeftLeg": {"upper": &"LeftUpperLeg", "middle": &"LeftLowerLeg", "end": &"LeftFoot", "shoulder": &"Hips"},
	&"RightLeg": {"upper": &"RightUpperLeg", "middle": &"RightLowerLeg", "end": &"RightFoot", "shoulder": &"Hips"},
}
## Per-limb scaffold wiring (handle + joint-side reference nodes) and joint
## word for the overlay. Elbow refs sit BEHIND (-Z), knee refs IN FRONT (+Z).
const LIMB_NODES := {
	&"Left": {"handle": &"LeftHandle", "pole": &"LeftPole", "joint": "elbow"},
	&"Right": {"handle": &"RightHandle", "pole": &"RightPole", "joint": "elbow"},
	&"LeftLeg": {"handle": &"LeftFootHandle", "pole": &"LeftKnee", "joint": "knee"},
	&"RightLeg": {"handle": &"RightFootHandle", "pole": &"RightKnee", "joint": "knee"},
}
const LIMB_ORDER := [&"Left", &"Right", &"LeftLeg", &"RightLeg"]
const FLEX_WARN := 150.0

## Solver is fixed per limb TYPE (never a per-feature switch): arms =
## FABRIK3D i64/d0.3 deterministic + disperser (feel), legs = TwoBoneIK3D +
## front pole (exact, plane pinned). Every wrist feature is implemented once.
## FABRIK budget (0-bis winning tuning — live matches measured, arms only).
@export var fab_iters := 64:
	set(v):
		fab_iters = maxi(v, 1)
		_apply_fabrik_tuning()
@export var fab_delta := 0.3:
	set(v):
		fab_delta = clampf(v, 0.01, 1.0)
		_apply_fabrik_tuning()
## Joint-side nodes: elbow refs are metric-only (FABRIK holds its plane);
## knee cubes are REAL TwoBone poles (drag to steer the knee plane) AND the
## flip-metric reference.
## Wrist orientation follow (step 2 gate): the handle's relative rotation
## (vs its rest) is applied onto the hand bone as a global-pose override.
## Toggle = A/B proof (off clears the override, hand falls back to solver).
@export var wrist_copy := true:
	set(v):
		wrist_copy = v
		_apply_override_clear()
## Ankle orientation (step 3b gate): TwoBone positions the leg but leaves the
## foot orientation to the chain (measured: crouch+step yawed the toes 180°
## backward) — so the foot is WORLD-FLAT by default (rest orientation,
## authored once per take via the cube delta on top), like a planted foot.
## Toggle = A/B proof (off = raw chain orientation).
@export var ankle_copy := true:
	set(v):
		ankle_copy = v
		_apply_override_clear()
## Diagnosis trace (human 25/09: overlay unreadable, paste Output instead) —
## prints a timestamped snapshot line ONLY on change (handle/pole moved, hips
## moved, or metric transition — throttled to 4 Hz during drags), plus an
## immediate EVENT line on every ok↔FLIP/INV transition. Paste the lines here
## for analysis. show_label re-enables the old Label3D overlay.
@export var trace_log := true
@export var show_label := false
## Min interval between change-snaps (spam guard during continuous drags).
const TRACE_MIN_INTERVAL := 0.25
@export_tool_button("Reset handles") var reset_action: Callable = reset_handles

var _skeleton: Skeleton3D
var _fabrik := {}
var _twist := {}
var _two := {}
var _handles := {}
var _poles := {}
## Body handle (HipsHandle): drags the whole RigRoot so planted feet stay
## planted while the body moves (translation only). Scene-space rest + node.
var _hips: Node3D
var _hips_rest := Vector3.ZERO
var _label: Label3D
var _handle_rest_rot := {&"Left": Quaternion(), &"Right": Quaternion()}
## Fresh solver snapshot per side (written mid-pipeline, consumed pre-pipeline).
var _solve_pos := {}
var _solve_fore := {}
var _rest := {}
var _joint_rest := {}
var _shoulder_rest := {}
var _reach := {}
## Expected bow direction per limb (skeleton space, from initial pole pos):
## the joint must stay on the pole side of the root→end line; crossing it =
## backward bend (invisible to the dot metric on quasi-straight limbs).
var _bow_ref := {}
var _err := {&"Left": 0.0, &"Right": 0.0, &"LeftLeg": 0.0, &"RightLeg": 0.0}
var _dot := {&"Left": 1.0, &"Right": 1.0, &"LeftLeg": 1.0, &"RightLeg": 1.0}
var _flex := {&"Left": 0.0, &"Right": 0.0, &"LeftLeg": 0.0, &"RightLeg": 0.0}
var _prox := {&"Left": 0.0, &"Right": 0.0, &"LeftLeg": 0.0, &"RightLeg": 0.0}
var _bow := {&"Left": 0.0, &"Right": 0.0, &"LeftLeg": 0.0, &"RightLeg": 0.0}
var _built := false
var _warned := false
var _trace_accum := 1.0
var _trace_elapsed := 0.0
var _flag := {&"Left": "ok", &"Right": "ok", &"LeftLeg": "ok", &"RightLeg": "ok"}
var _label_cleared := false
## Last printed change-signature (mm/deg ints): hips offset + per limb
## handle pos/rot + pole pos. Compared each frame — silence when idle.
var _trace_key: Array = []
## Fresh end-bone world orientation per limb (stored in-signal — the only
## reliable read of deterministic solves; _process reads would show rest).
var _solve_end := {}
## Foot rest world orientation per leg (ankle reference — static, captured at
## build; the rig only ever translates so it stays valid for the session).
var _ankle_rest := {}


## Limb table lookup (arms vs legs share every solver feature).
func _bones_of(limb: StringName) -> Dictionary:
	if ARM_BONES.has(limb):
		return ARM_BONES[limb]
	return LEG_BONES.get(limb, {})


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
	_hips = get_node_or_null("HipsHandle") as Node3D
	if _hips == null:
		push_error("[AnimCreator] HipsHandle node missing in scaffold")
		return
	_hips_rest = _hips.global_position
	for limb: StringName in LIMB_ORDER:
		var nodes: Dictionary = LIMB_NODES[limb]
		var handle := get_node_or_null(String(nodes["handle"])) as Node3D
		var pole := get_node_or_null(String(nodes["pole"])) as Node3D
		if handle == null or pole == null:
			push_error("[AnimCreator] %s handle/pole node missing in scaffold" % String(limb))
			return
		_handles[limb] = handle
		_poles[limb] = pole
		_snapshot_rest(limb)
		if LEG_BONES.has(limb):
			_build_two_leg(limb, handle, pole)
			_ankle_rest[limb] = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone((LEG_BONES[limb] as Dictionary)["end"]))).basis.get_rotation_quaternion()
		else:
			_build_fabrik(limb, handle)
		_handle_rest_rot[limb] = handle.global_transform.basis.get_rotation_quaternion()
	_apply_fabrik_tuning()
	_apply_override_clear()
	_built = true
	print("[AnimCreator] ready — arms fabrik-twist + legs two+pole, fab i%d/d%.3f, wrist %s (gizmo handles, no keys)" % [fab_iters, fab_delta, "on" if wrist_copy else "off"])


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
	_two.clear()
	if _skeleton == null:
		return
	for child in _skeleton.get_children():
		if child is SkeletonModifier3D and (str(child.name).ends_with("HandIK") or str(child.name).ends_with("FabrikArm") or str(child.name).ends_with("FabrikLeg") or str(child.name).ends_with("FootIK") or str(child.name).ends_with("TwistDisperse")):
			_skeleton.remove_child(child)
			child.queue_free()


## Rest snapshot (spike formula): end/joint/root rest + reach.
## The joint-side reference is read live from the pole node (gizmo-moved),
## never snapshotted. Handles keep their scene positions.
func _snapshot_rest(limb: StringName) -> void:
	var bones: Dictionary = _bones_of(limb)
	var upper_idx := _skeleton.find_bone(bones["upper"])
	var end_idx := _skeleton.find_bone(bones["end"])
	var joint_idx := _skeleton.find_bone(bones["middle"])
	var root_idx := _skeleton.find_bone(bones["shoulder"])
	if upper_idx == -1 or end_idx == -1 or joint_idx == -1 or root_idx == -1:
		push_error("[AnimCreator] limb bones missing: %s" % String(limb))
		return
	var end_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(end_idx).origin)
	var joint_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(joint_idx).origin)
	var root_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(root_idx).origin)
	_rest[limb] = _skeleton.to_local(end_w)
	_joint_rest[limb] = _skeleton.to_local(joint_w)
	_shoulder_rest[limb] = _skeleton.to_local(root_w)
	_reach[limb] = root_w.distance_to(end_w)
	# Bow reference = initial pole side (skeleton space, build-time only).
	var pole: Node3D = _poles.get(limb)
	if pole != null and root_w.distance_to(end_w) > 0.001:
		var ref: Vector3 = (_skeleton.to_local(pole.global_position) - _skeleton.to_local(root_w))
		_bow_ref[limb] = ref.normalized()


func _build_fabrik(limb: StringName, handle: Node3D) -> void:
	var bones: Dictionary = _bones_of(limb)
	var chain := "Leg" if LEG_BONES.has(limb) else "Arm"
	var farm := FABRIK3D.new()
	farm.name = "%sFabrik%s" % [String(limb), chain]
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
	farm.modification_processed.connect(_on_ik_processed.bind(limb))
	_fabrik[limb] = farm
	var tw := BoneTwistDisperser3D.new()
	tw.name = "%sTwistDisperse" % String(limb)
	_skeleton.add_child(tw)
	tw.set_setting_count(1)
	tw.set_root_bone_name(0, bones["upper"])
	tw.set_end_bone_name(0, bones["end"])
	tw.set_twist_from_rest(0, true)
	tw.active = true
	tw.modification_processed.connect(_on_ik_processed.bind(limb))
	_twist[limb] = tw


## Legs: TwoBoneIK3D analytic + REAL pole node (the knee cubes in front).
## The pole pins the bend plane by construction — no flips, ever — and the
## analytic solve is exact in one shot (0.0 mm in the spike), with no
## per-frame convergence. No disperser on legs (position-only feet: nothing
## distributes; proven innocent AND unnecessary here).
func _build_two_leg(limb: StringName, handle: Node3D, pole: Node3D) -> void:
	var bones: Dictionary = _bones_of(limb)
	var ik := TwoBoneIK3D.new()
	ik.name = "%sFootIK" % String(limb)
	_skeleton.add_child(ik)
	ik.set_setting_count(1)
	ik.set_root_bone_name(0, bones["upper"])
	ik.set_middle_bone_name(0, bones["middle"])
	ik.set_end_bone_name(0, bones["end"])
	ik.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_Z)
	ik.set_target_node(0, ik.get_path_to(handle))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.influence = 1.0
	ik.active = true
	ik.modification_processed.connect(_on_ik_processed.bind(limb))
	_two[limb] = ik


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
	var bones: Dictionary = _bones_of(side)
	var hand_idx := _skeleton.find_bone(bones["end"])
	if hand_idx == -1:
		return
	var parent_idx := _skeleton.get_bone_parent(hand_idx)
	var parent_global: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(parent_idx)
	# Origin in skeleton space (override space); rotations in world frame.
	_solve_pos[side] = (_skeleton.get_bone_global_pose(parent_idx) * _skeleton.get_bone_rest(hand_idx)).origin
	_solve_fore[side] = parent_global.basis.get_rotation_quaternion()
	# End-bone world orientation (trace only — arms AND legs; the foot bone
	# orientation is what the human sees, no solver writes it on legs).
	_solve_end[side] = (_skeleton.global_transform * _skeleton.get_bone_global_pose(hand_idx)).basis.get_rotation_quaternion()


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


## Override write (pre-pipeline _process, same split as the wrist): the foot
## keeps the honest solver position and takes its orientation from the REST
## world orientation × the cube delta — i.e. the ankle is world-flat by
## default (planted foot), plus the authored cube rotation on top (pointe,
## angled stomps). Unlike the wrist this is NOT relative to the parent: the
## chain-dictated orientation is exactly what flips the toes (measured 180°
## on crouch+step), so the parent must not contribute. No read-back of the
## foot, no feedback loop (TwoBone never reads our override as input — the
## deterministic solve restarts from rest every frame).
func _apply_stored_ankle() -> void:
	if _skeleton == null or _handles.is_empty() or not ankle_copy:
		return
	if _solve_pos.is_empty():
		return
	var sk_q: Quaternion = _skeleton.global_transform.basis.get_rotation_quaternion()
	for limb in LEG_BONES:
		if not _solve_pos.has(limb) or not _handles.has(limb) or not _ankle_rest.has(limb):
			continue
		var handle: Node3D = _handles[limb]
		var hq: Quaternion = handle.global_transform.basis.get_rotation_quaternion()
		var h0: Quaternion = _handle_rest_rot.get(limb, Quaternion())
		var delta: Quaternion = h0.inverse() * hq
		var foot_idx := _skeleton.find_bone((LEG_BONES[limb] as Dictionary)["end"])
		if foot_idx == -1:
			continue
		# World-flat × authored delta, back to skeleton (override) space.
		var world_q: Quaternion = (_ankle_rest[limb] as Quaternion) * delta
		var target := Transform3D(Basis(sk_q.inverse() * world_q), _solve_pos[limb] as Vector3)
		_skeleton.set_bone_global_pose_override(foot_idx, target, 1.0, true)


## Override toggles (A/B proofs): clearing drops every override at once, so
## clear ONLY when both wrist and ankle are off — the per-frame writers below
## re-assert the enabled ones every frame anyway. Only our overrides live on
## this skeleton. No other state to reset (no feedback loop by construction).
func _apply_override_clear() -> void:
	if _skeleton == null:
		return
	if not wrist_copy and not ankle_copy:
		_skeleton.clear_bones_global_pose_override()


func set_wrist_copy(v: bool) -> void:
	wrist_copy = v
	_apply_override_clear()


func set_ankle_copy(v: bool) -> void:
	ankle_copy = v
	_apply_override_clear()


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
func _on_ik_processed(limb: StringName) -> void:
	_store_solver_pose(limb)
	var bones: Dictionary = _bones_of(limb)
	var end_idx := _skeleton.find_bone(bones["end"])
	var joint_idx := _skeleton.find_bone(bones["middle"])
	var root_idx := _skeleton.find_bone(bones["shoulder"])
	var end_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(end_idx).origin)
	var joint_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(joint_idx).origin)
	var root_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(root_idx).origin)
	var handle: Node3D = _handles[limb]
	var pole: Node3D = _poles[limb]
	_err[limb] = end_w.distance_to(handle.global_position)
	var ref: Vector3 = (pole.global_position - root_w).normalized()
	var d: Vector3 = (joint_w - root_w).normalized()
	_dot[limb] = ref.dot(d)
	_flex[limb] = rad_to_deg((joint_w - root_w).angle_to(end_w - joint_w))
	_prox[limb] = end_w.distance_to(root_w)
	# Signed bow: joint offset from the root→end line along the pole side.
	# Negative = backward bend (the dot metric stays > 0 on quasi-straight
	# limbs — this is the honest inversion signal). Offset is world-space,
	# converted to skeleton space for the dot with the stored reference.
	var axis: Vector3 = end_w - root_w
	if axis.length() > 0.001 and _bow_ref.has(limb):
		var dir: Vector3 = axis.normalized()
		var off_world: Vector3 = (joint_w - root_w) - dir * ((joint_w - root_w).dot(dir))
		var off_sk: Vector3 = _skeleton.global_transform.basis.inverse() * off_world
		_bow[limb] = off_sk.dot(_bow_ref[limb] as Vector3)


func _process(_delta: float) -> void:
	# Body follow FIRST (pre-pipeline): the rig translates with the hips
	# handle; limb handles are scene-space so planted feet stay planted and
	# the IK re-solves around them. Translation only, rotation untouched.
	if _hips != null:
		var rig := get_node_or_null("RigRoot") as Node3D
		if rig != null:
			rig.global_position = _hips.global_position - _hips_rest
	if _label == null or _skeleton == null:
		return
	# Wrist + ankle writes (pre-pipeline, from the stored snapshot — see
	# _on_ik_processed): trace/label only read below.
	_apply_stored_wrist()
	_apply_stored_ankle()
	var event_limb := &""
	for limb in LIMB_ORDER:
		var f := _limb_flag(limb)
		if f != String(_flag.get(limb, "ok")):
			_flag[limb] = f
			event_limb = limb
			break
	if show_label:
		_write_label()
	elif _label != null and not _label_cleared:
		_label.text = "AnimCreator: trace in Output (show_label to restore overlay)"
		_label_cleared = true
	if trace_log:
		_trace_elapsed += _delta
		_trace_accum += _delta
		if event_limb != &"":
			_print_trace(true, String(event_limb))
			_trace_accum = 0.0
			_trace_key = _trace_signature()
		elif _trace_accum >= TRACE_MIN_INTERVAL:
			var key := _trace_signature()
			if key != _trace_key:
				_trace_key = key
				_trace_accum = 0.0
				_print_trace(false, "")


## Change signature: hips offset (mm) + per limb handle pos (mm) / handle
## rot (deg) / pole pos (mm), rounded to ints. Idle scene = identical key =
## silence (answers the log-spam report 25/09).
func _trace_signature() -> Array:
	var key: Array = []
	key.append(int(round((_hips.global_position - _hips_rest).length() * 1000.0)) if _hips != null else 0)
	for limb in LIMB_ORDER:
		var h: Node3D = _handles.get(limb)
		var p: Node3D = _poles.get(limb)
		if h != null:
			key.append(int(round(h.global_position.x * 1000.0)))
			key.append(int(round(h.global_position.y * 1000.0)))
			key.append(int(round(h.global_position.z * 1000.0)))
			var e: Vector3 = h.global_rotation * 180.0 / PI
			key.append(int(round(e.x)))
			key.append(int(round(e.y)))
			key.append(int(round(e.z)))
		if p != null:
			key.append(int(round(p.global_position.x * 1000.0)))
			key.append(int(round(p.global_position.y * 1000.0)))
			key.append(int(round(p.global_position.z * 1000.0)))
		# Settled metrics (0.1mm / 0.01 / 1deg / mm): prints the post-move
		# solve once after the handles stop, then silence.
		key.append(int(round(float(_err.get(limb, 0.0)) * 10000.0)))
		key.append(int(round(float(_dot.get(limb, 0.0)) * 100.0)))
		key.append(int(round(float(_flex.get(limb, 0.0)))))
		key.append(int(round(float(_bow.get(limb, 0.0)) * 1000.0)))
	return key


## Joint state flag shared by overlay + trace: FLIP (plane lost, dot<0) wins
## over INV (backward bow on a held plane), else ok.
func _limb_flag(limb: StringName) -> String:
	if float(_dot.get(limb, 1.0)) < 0.0:
		return "FLIP"
	if float(_bow.get(limb, 0.0)) < 0.0:
		return "INV"
	return "ok"


func _write_label() -> void:
	_label_cleared = false
	var lines := PackedStringArray()
	for limb in LIMB_ORDER:
		var joint: String = (LIMB_NODES[limb] as Dictionary)["joint"]
		var flex := float(_flex[limb])
		var fwarn := " OVERFLEX" if flex > FLEX_WARN else ""
		lines.append("%s err=%.1fmm %s=%s (dot %.2f) flex=%.0f%s dist=%.0fcm" % [String(limb), float(_err[limb]) * 1000.0, joint, _limb_flag(limb), float(_dot[limb]), flex, fwarn, float(_prox[limb]) * 100.0])
	lines.append("arms fabrik-twist / legs two+pole | fab i%d/d%.3f | wrist %s | body +%.0fcm | gizmo: drag/rotate handles" % [fab_iters, fab_delta, "on" if wrist_copy else "off", (_hips.global_position - _hips_rest).length() * 100.0 if _hips != null else 0.0])
	_label.text = "\n".join(lines)


## One pasteable trace line: handle pos + euler + pole pos + END-BONE euler
## (in-signal stored — the visible bone orientation) + solver metrics.
## EVENT lines fire immediately on flag transitions (the flip moments).
func _print_trace(is_event: bool, event_limb: String) -> void:
	var parts := PackedStringArray()
	parts.append("hips=+%.0fcm" % ((_hips.global_position - _hips_rest).length() * 1000.0 / 10.0 if _hips != null else 0.0))
	for limb in LIMB_ORDER:
		var h: Node3D = _handles.get(limb)
		var p: Node3D = _poles.get(limb)
		var hp := Vector3.ZERO
		var he := Vector3.ZERO
		var pp := Vector3.ZERO
		if h != null:
			hp = h.global_position
			var e: Vector3 = h.global_rotation * 180.0 / PI
			he = Vector3(roundf(e.x) + 0.0, roundf(e.y) + 0.0, roundf(e.z) + 0.0)
		if p != null:
			pp = p.global_position
		var be := Vector3.ZERO
		if _solve_end.has(limb):
			var q: Quaternion = _solve_end[limb]
			var eb: Vector3 = q.get_euler() * 180.0 / PI
			be = Vector3(roundf(eb.x) + 0.0, roundf(eb.y) + 0.0, roundf(eb.z) + 0.0)
		parts.append("%s h=(%.2f,%.2f,%.2f) r=(%.0f,%.0f,%.0f) bone=(%.0f,%.0f,%.0f) pole=(%.2f,%.2f,%.2f) err=%.1f dot=%.2f flex=%.0f bow=%.0f %s" % [String(limb), hp.x, hp.y, hp.z, he.x, he.y, he.z, be.x, be.y, be.z, pp.x, pp.y, pp.z, float(_err.get(limb, -1.0)) * 1000.0, float(_dot.get(limb, 0.0)), float(_flex.get(limb, 0.0)), float(_bow.get(limb, 0.0)) * 1000.0, _limb_flag(limb)])
	var tag := "EVENT %s" % event_limb if is_event else "snap"
	print("[AnimCreator %s t=%.1f] %s" % [tag, _trace_elapsed, " | ".join(parts)])


## Re-snaps handles to rest + poles to their joint side (Reset button):
## elbow refs behind (-Z), knee refs in front (+Z, knees bend forward).
## The hips handle also re-snaps (RigRoot follows back via _process).
func reset_handles() -> void:
	if _skeleton == null or _handles.is_empty():
		push_warning("[AnimCreator] reset: rig not built yet")
		return
	var rig := get_node_or_null("RigRoot") as Node3D
	var back := Vector3(0, 0, -1)
	var front := Vector3(0, 0, 1)
	if rig != null:
		back = -rig.global_transform.basis.z.normalized()
		front = rig.global_transform.basis.z.normalized()
	for limb in LIMB_ORDER:
		var joint_l: Vector3 = _joint_rest.get(limb, Vector3.ZERO)
		var joint_w: Vector3 = _skeleton.to_global(joint_l)
		(_handles[limb] as Node3D).global_position = _skeleton.to_global(_rest[limb] as Vector3)
		(_handles[limb] as Node3D).global_rotation = Vector3.ZERO
		# Zero-point follows the reset (else a saved rotated handle would
		# leave a stale rest-rot and offset the wrist after reset).
		_handle_rest_rot[limb] = Quaternion()
		var to_side := back if not LEG_BONES.has(limb) else front
		(_poles[limb] as Node3D).global_position = joint_w + to_side * 0.45 + Vector3(0, 0.1, 0)
	if _hips != null:
		_hips.global_position = _hips_rest
	print("[AnimCreator] handles reset")
	if trace_log:
		_print_trace(false, "")


## Validator seam (mirrors the spike — future bake guard). tracking_error /
## reach_of take any limb key (arms + legs); arms keep their named helpers.
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


## Leg seam (same metrics, keyed by leg limb — future bake guard).
func set_foot_target(limb: StringName, skeleton_local_pos: Vector3) -> void:
	if _handles.has(limb) and _skeleton != null:
		(_handles[limb] as Node3D).global_position = _skeleton.to_global(skeleton_local_pos)


func knee_dot(limb: StringName) -> float:
	return float(_dot.get(limb, 0.0))


func knee_flexion(limb: StringName) -> float:
	return float(_flex.get(limb, 0.0))


func foot_hip_dist(limb: StringName) -> float:
	return float(_prox.get(limb, 0.0))


## Signed joint bow in mm along the pole side (negative = backward bend).
func bend_of(limb: StringName) -> float:
	return float(_bow.get(limb, 0.0))


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


## World orientation of the foot bone, IN-SIGNAL stored (trace bone= column).
## Outside-signal live reads show rest for deterministic solves (pipeline
## lesson 25/09) — this seam returns the staged solve like the metrics do.
func foot_bone_quat(limb: StringName) -> Quaternion:
	return _solve_end.get(limb, Quaternion())
