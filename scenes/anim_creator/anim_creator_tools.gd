@tool
extends Node3D

## AnimCreator — authoring-rig scaffold, hands + wrist, feet + ankle.
##
## DOCTRINE (human 25/09, after a day of fighting steerable planes): the rig
## CONSTRAINS, the user places. No steerable poles, no solver choice — one
## analytic solver per limb family (arms: TwoBoneIK3D + AUTOMATIC pole ;
## legs: custom analytic, stateless + explicit anatomical branch — TwoBone
## prouvé bistable sur cuisse, nudge 5 mm = flip 140° permanent), honest
## stretch past reach, wrist/ankle toggles for the extremities. The user
## places 5 handles (2 hands, 2 feet, hips) + 4 cube rotations; every other
## pose must be anatomically valid by construction (impossible poses are
## refused by the plane/limits, never authored).
## Auto-pole rule (same pre-pipeline slot as the hips follow): pole = chain
## root world pos + fixed anatomical offset (elbows down-back, knees forward).
## Internal Node3Ds, invisible, never user-touched — the trace logs their
## positions so the constraint stays observable. Torso handle = deferred.
## Step 2 wrist follow is CODE-DRIVEN (global-pose override, relative mode):
## CopyTransformModifier3D proved fully inert in 4.7.2 — node AND bone
## references, minimal code-built skeleton, both pose channels, every flag
## combo (axes/all, additive, absolute path, child order) — it processes
## (signal fires) but never writes. So the tool applies the handle's
## relative rotation itself each frame: rest cube = zero offset, turned
## cube = poignée/revers at the wrist. The override wins non-destructively
## and reads back through get_bone_global_pose (bake-safe, 1-frame lag in
## live preview — invisible in the editor).
## Twist/disperser verdicts superseded 25/09 (constraint doctrine): TwoBone /
## FABRIK / disperser all stay in the spike as reference — this tool builds
## only TwoBone + auto-pole, every feature written once.
## No InputManager, no key/mouse polling: this is an editor @tool scene
## (like anim_lab), not an in-game editor — the editor viewport IS the UI.
## Metrics publish to StateLabel (Label3D, editor-visible) + ready print.
## Validator seam (tracking_error/elbow_dot/elbow_flexion/hand_bone_quat/...)
## mirrors the arm spike for the future bake guard (step 5).
##
## API note: the TwoBone setters (set_setting_count, set_root/middle/end_bone
## name, set_pole_direction/node, set_target_node) are absent from the 4.7
## doctool XML (incomplete dump for modifier classes) — verified at runtime
## instead: the leg switch ran headless-green (drag +15 cm → err 0.00 mm,
## commit 8f6dd4c). Label3D props verified in reference/godot47_docs/*.xml.
const ARM_BONES := {
	&"Left": {"upper": &"LeftUpperArm", "middle": &"LeftLowerArm", "end": &"LeftHand", "shoulder": &"LeftShoulder"},
	&"Right": {"upper": &"RightUpperArm", "middle": &"RightLowerArm", "end": &"RightHand", "shoulder": &"RightShoulder"},
}
## Legs: TwoBone root = thigh, hip reference = Hips (shared, never overridden).
const LEG_BONES := {
	&"LeftLeg": {"upper": &"LeftUpperLeg", "middle": &"LeftLowerLeg", "end": &"LeftFoot", "shoulder": &"Hips"},
	&"RightLeg": {"upper": &"RightUpperLeg", "middle": &"RightLowerLeg", "end": &"RightFoot", "shoulder": &"Hips"},
}
## Per-limb scaffold wiring (user handle + joint word). Poles AND solver
## targets are INTERNAL (auto-placed / eased, invisible) — the only user nodes
## are handles + HipsHandle.
const LIMB_NODES := {
	&"Left": {"handle": &"LeftHandle", "joint": "elbow"},
	&"Right": {"handle": &"RightHandle", "joint": "elbow"},
	&"LeftLeg": {"handle": &"LeftFootHandle", "joint": "knee"},
	&"RightLeg": {"handle": &"RightFootHandle", "joint": "knee"},
}
## Max input speed, m/s (slew, re-added 25/09): TwoBone twist is a MOTION
## TRANSIENT (measured: fast target jumps excite up to ~180° thigh roll that
## decays over tens of static frames; static holds settle clean). Capping
## per-frame input jumps keeps transients invisible; static poses always
## settle exact. Rubber-bands violent flicks; Reset animates smooth.
const SLEW_SPEED := 1.5
## Anatomical pole DIRECTIONS (world space — elbows behind, knees forward)
## + distance. The direction is re-projected perpendicular to the live
## root→target line every frame (see _update_auto_poles): a rest-anchored
## pole lets the line rotate onto it on large excursions (measured 25/09:
## foot +60 cm crouched → pole 2 cm off the line → degenerate plane → knee
## flips backward/forward at random, bow -167 with dot +0.83). The torso never
## rotates in this rig; revisit if a torso handle lands.
const ARM_POLE_DIR := Vector3(0, 0, -1)
const LEG_POLE_DIR := Vector3(0, 0, 1)
const POLE_DIST := 0.45
## Lateral pole bias for LEGS (25/09): TwoBone rolls the thigh ~180° when it
## aims forward because the forward pole goes parallel to the thigh axis
## (roll reference degenerate — plane stays perfect, bow +252, but the bone
## spins). A lateral component keeps the pole off the thigh axis in all
## sagittal motions (thighs never leave the YZ plane). Mirrored per side
## (outward). Small on purpose: knees must still track forward over the toes.
const LEG_POLE_LAT := 0.0
## TEMP 25/09 pole search (remove after): when true, _update_auto_poles skips
## (probe positions _poles directly to map twist_vs_bind over directions).
var lock_poles := false
const LIMB_ORDER := [&"Left", &"Right", &"LeftLeg", &"RightLeg"]
const FLEX_WARN := 150.0

## Solver: TwoBoneIK3D + auto-pole on all four limbs. No tuning, no switch,
## no disperser (dropped 25/09 — its roll problem was FABRIK-specific; one
## line re-adds it if the wrist regresses).
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
## immediate EVENT line on every ok↔INV transition. Paste the lines here
## for analysis. show_label re-enables the old Label3D overlay.
@export var trace_log := true
@export var show_label := false
## Min interval between change-snaps (spam guard during continuous drags).
const TRACE_MIN_INTERVAL := 0.25
@export_tool_button("Reset handles") var reset_action: Callable = reset_handles

var _skeleton: Skeleton3D
var _two := {}
var _twist := {}
var _handles := {}
## Code version printed at ready — stale-cache insurance (25/09: rapid
## edit/run cycles served mixed bytecode; if the printed REV isn't the
## latest, the run is void — reload).
const SCRIPT_REV := 11
## Auto-pole nodes (internal, invisible, created at build — never scene nodes,
## never user-touched; re-created on every _build, old ones freed).
var _poles := {}
## Solver-target proxies (internal, invisible): TwoBone reads these, they ease
## toward the user handles at SLEW_SPEED. Snapped to handles at build;
## freed/re-created with the poles.
var _proxy := {}
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
var _upper_rest := {}
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
## Fresh thigh/upper-arm world orientation per limb (same slot — hip-fold and
## thigh-roll diagnosis, future bake guard).
var _solve_upper := {}
var _solve_middle := {}
## Upper-bone staged origin per limb (skeleton space, in-signal).
var _solve_upper_pos := {}
## TEMP 25/09 staged thigh basis determinant (mirror hunt).
var _solve_upper_det := {}
## Foot rest world orientation per leg (ankle reference — static, captured at
## build; the rig only ever translates so it stays valid for the session).
var _ankle_rest := {}
## Upper-bone rest world orientation + long axis (rest-local) per limb, for
## the twist de-lock (captured at build, skeleton at rest).
var _upper_rest_w := {}
var _roll_axis := {}
## Custom analytic leg solver refs (25/09 : TwoBoneIK3D prouvé bistable —
## nudge 5 mm = flip 140° permanent à pôles/solver-inputs identiques.
## Le solveur custom est STATELESS (pur fonction des inputs) + branche
## EXPLICITE (côté anatomique imposé, roll minimal vs rest) : le flip est
## impossible par construction. Bras inchangés (TwoBone stable, gaté).
## Per leg: L1/L2 rest lengths, rest world orients (upper/middle/end),
## rest-local length dirs, constant bend-side ref (world).
var _leg_len := {}
var _leg_rest_w := {}
var _leg_len_local := {}
var _leg_bend_ref := {}
var _leg_side := {}


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
	_clear_auto_poles()
	_hips = get_node_or_null("HipsHandle") as Node3D
	if _hips == null:
		push_error("[AnimCreator] HipsHandle node missing in scaffold")
		return
	_hips_rest = _hips.global_position
	for limb: StringName in LIMB_ORDER:
		var handle := get_node_or_null(String((LIMB_NODES[limb] as Dictionary)["handle"])) as Node3D
		if handle == null:
			push_error("[AnimCreator] %s handle node missing in scaffold" % String(limb))
			return
		_handles[limb] = handle
		var pole := Node3D.new()
		pole.name = "%sAutoPole" % String(limb)
		add_child(pole)
		_poles[limb] = pole
		var proxy := Node3D.new()
		proxy.name = "%sTargetProxy" % String(limb)
		add_child(proxy)
		proxy.global_position = handle.global_position
		_proxy[limb] = proxy
		_snapshot_rest(limb)
		# Legs: custom analytic solver (stateless, explicit branch — see
		# _solve_leg). Arms keep TwoBone (stable, gated — _build_two).
		if ARM_BONES.has(limb):
			_build_two(limb, proxy, pole)
		elif LEG_BONES.has(limb):
			_capture_leg_refs(limb)
		if LEG_BONES.has(limb):
			_ankle_rest[limb] = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone((LEG_BONES[limb] as Dictionary)["end"]))).basis.get_rotation_quaternion()
		# Twist de-lock references (skeleton known at rest here): upper-bone
		# rest world orientation + long axis in rest-local space (from rest
		# joint positions — hip→knee for legs, shoulder→elbow for arms).
		var ub: Dictionary = _bones_of(limb)
		var u_idx := _skeleton.find_bone(ub["upper"])
		var j_idx := _skeleton.find_bone(ub["middle"])
		var r_idx := _skeleton.find_bone(ub["shoulder"])
		if u_idx != -1 and j_idx != -1 and r_idx != -1:
			var qw: Quaternion = (_skeleton.global_transform * _skeleton.get_bone_global_pose(u_idx)).basis.get_rotation_quaternion()
			_upper_rest_w[limb] = qw
			var jw: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(j_idx).origin)
			var rw: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(r_idx).origin)
			if jw.distance_to(rw) > 0.001:
				_roll_axis[limb] = (qw.inverse() * (jw - rw)).normalized()
		_handle_rest_rot[limb] = handle.global_transform.basis.get_rotation_quaternion()
	_update_auto_poles()
	_apply_override_clear()
	_built = true
	# Stale-build detector (25/09 : proxies snappés sur handles au build — si
	# les globals n'étaient pas propagées, le solve part de travers).
	var max_gap := 0.0
	for limb in LIMB_ORDER:
		if _proxy.has(limb) and _handles.has(limb):
			max_gap = maxf(max_gap, (_proxy[limb] as Node3D).global_position.distance_to((_handles[limb] as Node3D).global_position))
	print("[AnimCreator r%d ready — arms two+pole, legs custom analytic, wrist %s ankle %s (5 handles + 4 cubes, no poles to steer) proxy_gap=%.1fmm" % [SCRIPT_REV, "on" if wrist_copy else "off", "on" if ankle_copy else "off", max_gap * 1000.0])


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
## Keeps every historical suffix so stale pre-doctrine nodes get collected.
func _clear_modifiers() -> void:
	_two.clear()
	_twist.clear()
	if _skeleton == null:
		return
	for child in _skeleton.get_children():
		if child is SkeletonModifier3D and (str(child.name).ends_with("HandIK") or str(child.name).ends_with("LimbIK") or str(child.name).ends_with("FabrikArm") or str(child.name).ends_with("FabrikLeg") or str(child.name).ends_with("FootIK") or str(child.name).ends_with("TwistDisperse")):
			_skeleton.remove_child(child)
			child.queue_free()


## Frees previously built internal auto-poles AND proxies.
func _clear_auto_poles() -> void:
	for limb in _poles:
		var p: Node3D = _poles[limb]
		if is_instance_valid(p):
			remove_child(p)
			p.queue_free()
	_poles.clear()
	for limb in _proxy:
		var t: Node3D = _proxy[limb]
		if is_instance_valid(t):
			remove_child(t)
			t.queue_free()
	_proxy.clear()


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
	_upper_rest[limb] = _skeleton.to_local(_skeleton.to_global(_skeleton.get_bone_global_pose(upper_idx).origin))
	_reach[limb] = root_w.distance_to(end_w)
	# Bow reference = anatomical pole side (skeleton space). Kept in sync with
	# the adaptive pole each frame (see _update_auto_poles); the build-time
	# value below is just the rest fallback.
	if root_w.distance_to(end_w) > 0.001:
		var off := LEG_POLE_DIR if LEG_BONES.has(limb) else ARM_POLE_DIR
		_bow_ref[limb] = (_skeleton.global_transform.basis.inverse() * off).normalized()


## Single solver for all limbs (doctrine 25/09): TwoBoneIK3D analytic + the
## internal auto-pole. Exact in one shot (0.0 mm in the spike), plane pinned
## by construction — no flips, no backward bends, honest stretch. The pole
## direction enum is belt-and-braces (the node does the work).
## NO disperser (25/09): measured zero effect on the TwoBone root roll
## (thigh 182° with and without) — dead weight + extra signals. If a future
## fix needs redistribution, one block re-adds it.
func _build_two(limb: StringName, target: Node3D, pole: Node3D) -> void:
	var bones: Dictionary = _bones_of(limb)
	var ik := TwoBoneIK3D.new()
	ik.name = "%sLimbIK" % String(limb)
	_skeleton.add_child(ik)
	ik.set_setting_count(1)
	ik.set_root_bone_name(0, bones["upper"])
	ik.set_middle_bone_name(0, bones["middle"])
	ik.set_end_bone_name(0, bones["end"])
	ik.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_Z if LEG_BONES.has(limb) else SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_Z)
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.influence = 1.0
	ik.active = true
	ik.modification_processed.connect(_on_ik_processed.bind(limb))
	_two[limb] = ik


## Custom leg references (build time, skeleton at rest): rest lengths,
## rest world orientations, rest-local length dirs, constant bend-side ref.
func _capture_leg_refs(limb: StringName) -> void:
	var bones: Dictionary = LEG_BONES[limb]
	var u_idx := _skeleton.find_bone(bones["upper"])
	var j_idx := _skeleton.find_bone(bones["middle"])
	var e_idx := _skeleton.find_bone(bones["end"])
	if u_idx == -1 or j_idx == -1 or e_idx == -1:
		push_error("[AnimCreator] leg bones missing: %s" % String(limb))
		return
	var u_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(u_idx).origin)
	var j_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(j_idx).origin)
	var e_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(e_idx).origin)
	_leg_len[limb] = [u_w.distance_to(j_w), j_w.distance_to(e_w)]
	var rw := {}
	for key in [&"upper", &"middle", &"end"]:
		var idx := _skeleton.find_bone((bones as Dictionary)[key])
		rw[key] = (_skeleton.global_transform * _skeleton.get_bone_global_pose(idx)).basis.get_rotation_quaternion()
	_leg_rest_w[limb] = rw
	var u_pose: Transform3D = _skeleton.get_bone_global_pose(u_idx)
	var j_pose: Transform3D = _skeleton.get_bone_global_pose(j_idx)
	var ll := {}
	ll[&"upper"] = (u_pose.affine_inverse() * j_pose.origin).normalized()
	ll[&"middle"] = (j_pose.affine_inverse() * _skeleton.get_bone_global_pose(e_idx).origin).normalized()
	_leg_len_local[limb] = ll
	# Constant bend-side ref: rest thigh dir × anatomical pole dir (world).
	# The knee bends toward the pole by design — enforcement target below.
	var t10: Vector3 = (j_w - u_w).normalized()
	var pole_w: Vector3 = (_skeleton.global_transform.basis * LEG_POLE_DIR).normalized()
	var ref: Vector3 = t10.cross(pole_w)
	if ref.length() < 0.001:
		ref = Vector3(1, 0, 0)
	_leg_bend_ref[limb] = ref.normalized()
	# Per-bone enforcement side (bind parity — sonde 21 : thigh X → -X monde
	# comme bendRef, shin X → +X monde, opposé. Imposer le même côté aux deux
	# roulait le tibia de 180° au repos avec des positions exactes).
	var side := {}
	for key in [&"upper", &"middle"]:
		var q0: Quaternion = rw[key]
		var s: float = signf(((q0 * Vector3(1, 0, 0)).normalized()).dot(_leg_bend_ref[limb]))
		side[key] = s if s != 0.0 else 1.0
	_leg_side[limb] = side


## Custom analytic leg solve (STATELESS — pure function of live inputs).
## Law of cosines for positions (honest stretch past reach, like TwoBone),
## explicit basis construction for orientations: shortest-arc length mapping
## (minimal roll vs rest) + roll correction enforcing the anatomical bend
## side (constant ref). The TwoBone 140° bistability cannot occur: same
## inputs → same outputs, clean branch by construction. Runs pre-pipeline
## in _process (same frame — no signal split); fills the same metric/seam
## dicts as the signal path so trace + bake guard are untouched.
func _solve_leg(limb: StringName) -> void:
	if not _leg_len.has(limb) or not _proxy.has(limb) or not _poles.has(limb):
		return
	var bones: Dictionary = LEG_BONES[limb]
	var u_idx := _skeleton.find_bone(bones["upper"])
	var j_idx := _skeleton.find_bone(bones["middle"])
	var e_idx := _skeleton.find_bone(bones["end"])
	var r_idx := _skeleton.find_bone(bones["shoulder"])
	if u_idx == -1 or j_idx == -1 or e_idx == -1 or r_idx == -1:
		return
	var lens: Array = _leg_len[limb]
	var l1: float = lens[0]
	var l2: float = lens[1]
	var reach: float = l1 + l2
	var h_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(u_idx).origin)
	var root_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(r_idx).origin)
	var target_w: Vector3 = (_proxy[limb] as Node3D).global_position
	var pole_w: Vector3 = (_poles[limb] as Node3D).global_position
	var axis: Vector3 = target_w - h_w
	var d: float = axis.length()
	if d < 0.0001:
		return
	var dir: Vector3 = axis / d
	# Honest stretch: foot stops at reach, err carries the over-reach.
	var dist: float = minf(d, reach)
	var f_w: Vector3 = h_w + dir * dist
	_err[limb] = maxf(0.0, d - reach)
	# Knee: law of cosines (angle at hip) + pole-side height.
	var cos_a := 1.0
	if dist > 0.0001 and l1 > 0.0001:
		cos_a = clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sin_a: float = sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var n: Vector3 = (pole_w - h_w) - dir * ((pole_w - h_w).dot(dir))
	if n.length() < 0.0001:
		var bref: Vector3 = _leg_bend_ref[limb]
		n = bref - dir * (bref.dot(dir))
	if n.length() < 0.0001:
		n = Vector3(0, 0, 1) - dir * dir.z
	n = n.normalized()
	var k_w: Vector3 = h_w + (dir * cos_a + n * sin_a) * l1
	var t1: Vector3 = (k_w - h_w) / maxf(l1, 0.0001)
	var t2: Vector3 = (f_w - k_w) / maxf(l2, 0.0001)
	if t2.length() < 0.5:
		t2 = dir
	else:
		t2 = t2.normalized()
	# Bend axis, sign-enforced to the anatomical side (THE anti-flip lock).
	var bend: Vector3 = t1.cross(t2)
	var bref2: Vector3 = _leg_bend_ref[limb]
	if bend.length() < 0.0001:
		bend = bref2 - t1 * (bref2.dot(t1))
	if bend.length() < 0.0001:
		bend = Vector3(1, 0, 0) - t1 * t1.x
	bend = bend.normalized()
	if bend.dot(bref2) < 0.0:
		bend = -bend
	var sk_basis: Basis = _skeleton.global_transform.basis
	var sk_inv: Basis = sk_basis.inverse()
	var rw: Dictionary = _leg_rest_w[limb]
	var ll: Dictionary = _leg_len_local[limb]
	# Thigh + shin orientations: shortest-arc length map × roll correction.
	# Per-bone side (bind parity): each bone's X returns to its own rest side.
	var side: Dictionary = _leg_side[limb]
	var q_thigh: Quaternion = _aim_bone(rw[&"upper"], ll[&"upper"], t1, bend * float(side.get(&"upper", 1.0)))
	var q_shin: Quaternion = _aim_bone(rw[&"middle"], ll[&"middle"], t2, bend * float(side.get(&"middle", 1.0)))
	# Skeleton-space override targets (same space as the wrist writer).
	var thigh_pos_sk: Vector3 = (_skeleton.get_bone_global_pose(r_idx) * _skeleton.get_bone_rest(u_idx)).origin
	var thigh_sk := Transform3D(Basis(sk_inv * Basis(q_thigh)), thigh_pos_sk)
	var shin_pos_sk: Vector3 = (thigh_sk * _skeleton.get_bone_rest(j_idx)).origin
	var shin_sk := Transform3D(Basis(sk_inv * Basis(q_shin)), shin_pos_sk)
	var foot_pos_sk: Vector3 = (shin_sk * _skeleton.get_bone_rest(e_idx)).origin
	_skeleton.set_bone_global_pose_override(u_idx, thigh_sk, 1.0, true)
	_skeleton.set_bone_global_pose_override(j_idx, shin_sk, 1.0, true)
	_solve_pos[limb] = foot_pos_sk
	_solve_upper[limb] = q_thigh
	_solve_middle[limb] = q_shin
	_solve_upper_det[limb] = 1.0
	# Foot orientation: ankle ON = world-flat × cube delta (ankle writer
	# consumes _solve_pos, unchanged); OFF = follow the shin (rest-local
	# offset carried — relative mode like the wrist).
	var handle: Node3D = _handles[limb]
	var hq: Quaternion = handle.global_transform.basis.get_rotation_quaternion()
	var h0: Quaternion = _handle_rest_rot.get(limb, Quaternion())
	var delta: Quaternion = h0.inverse() * hq
	var foot_q: Quaternion
	if ankle_copy:
		foot_q = (_ankle_rest[limb] as Quaternion) * delta
	else:
		var q_shin0: Quaternion = rw[&"middle"]
		var q_foot0: Quaternion = rw[&"end"]
		foot_q = q_shin * (q_shin0.inverse() * q_foot0) * delta
	_solve_end[limb] = foot_q
	if not ankle_copy:
		_skeleton.set_bone_global_pose_override(e_idx, Transform3D(Basis(sk_inv * Basis(foot_q)), foot_pos_sk), 1.0, true)
	# Metrics — same formulas as the signal path (parity by construction).
	_prox[limb] = f_w.distance_to(root_w)
	_flex[limb] = rad_to_deg((k_w - root_w).angle_to(f_w - k_w))
	var chain_w: Vector3 = h_w
	var pole: Node3D = _poles[limb]
	var ref_v: Vector3 = (pole.global_position - chain_w).normalized()
	var dv: Vector3 = (k_w - chain_w).normalized()
	_dot[limb] = ref_v.dot(dv)
	var lax: Vector3 = f_w - root_w
	if lax.length() > 0.001 and _bow_ref.has(limb):
		var ldir: Vector3 = lax.normalized()
		var off_world: Vector3 = (k_w - root_w) - ldir * ((k_w - root_w).dot(ldir))
		var off_sk: Vector3 = sk_basis.inverse() * off_world
		_bow[limb] = off_sk.dot(_bow_ref[limb] as Vector3)


## Bone aiming helper: rest orientation carried by shortest-arc length map,
## then roll-corrected so local X lands on the enforced bend axis.
## Deterministic, continuous, minimal roll — the anti-bistability core.
func _aim_bone(q_rest0: Quaternion, l_local: Vector3, t_world: Vector3, bend_world: Vector3) -> Quaternion:
	var l_w0: Vector3 = (q_rest0 * l_local).normalized()
	var q1 := Quaternion(l_w0, t_world)
	var x1: Vector3 = (q1 * q_rest0) * Vector3(1, 0, 0)
	var ang: float = atan2(x1.cross(bend_world).dot(t_world), x1.dot(bend_world))
	var q_roll := Quaternion(t_world, ang)
	return (q_roll * q1 * q_rest0).normalized()


## Auto-pole placement (the constraint, pre-pipeline like the hips follow).
## pole = joint-rest world pos + ADAPTED anatomical direction × POLE_DIST,
## where the direction = the anatomical forward/backward re-projected
## perpendicular to the live chain-root→target line. Rest-anchored poles let
## the line rotate onto them on large excursions (degenerate plane → random
## knee side); adapted poles can never lie on the line. Near-degenerate input
## (straight horizontal kick along the anatomical axis) keeps the previous
## pole (hysteresis, no snap). All inputs are stored locals + live node
## transforms — no bone reads, no solver feedback.
func _update_auto_poles() -> void:
	if _skeleton == null or _poles.is_empty() or _joint_rest.is_empty():
		return
	if lock_poles:
		return
	for limb in LIMB_ORDER:
		if not _poles.has(limb) or not _joint_rest.has(limb) or not _upper_rest.has(limb) or not _proxy.has(limb):
			continue
		var fwd := ARM_POLE_DIR
		if LEG_BONES.has(limb):
			var side_sign := 1.0 if String(limb).begins_with("Left") else -1.0
			fwd = Vector3(side_sign * LEG_POLE_LAT, 0.0, 1.0).normalized()
		var root_w: Vector3 = _skeleton.to_global(_upper_rest[limb] as Vector3)
		var target_w: Vector3 = (_proxy[limb] as Node3D).global_position
		var line: Vector3 = target_w - root_w
		if line.length() < 0.05:
			continue
		var along: Vector3 = line.normalized()
		var perp: Vector3 = fwd - along * fwd.dot(along)
		if perp.length() < 0.05:
			continue
		var dir: Vector3 = perp.normalized()
		(_poles[limb] as Node3D).global_position = _skeleton.to_global(_joint_rest[limb] as Vector3) + dir * POLE_DIST
		_bow_ref[limb] = (_skeleton.global_transform.basis.inverse() * dir).normalized()


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
	# Upper-bone (thigh/upper-arm) world orientation, same slot.
	var upper_idx := _skeleton.find_bone(bones["upper"])
	if upper_idx != -1:
		_solve_upper[side] = (_skeleton.global_transform * _skeleton.get_bone_global_pose(upper_idx)).basis.get_rotation_quaternion()
		# Upper-bone origin (skeleton space = override space, kept for future
		# bake-guard use).
		_solve_upper_pos[side] = _skeleton.get_bone_global_pose(upper_idx).origin
		# TEMP 25/09: staged basis sanity (mirror hunt) — remove after probe.
		_solve_upper_det[side] = (_skeleton.global_transform * _skeleton.get_bone_global_pose(upper_idx)).basis.determinant()
	# Middle-bone (shin/forearm) world orientation, same slot (chain twist
	# audit: thigh-only vs chain-wide de-twist decision).
	var middle_idx := _skeleton.find_bone(bones["middle"])
	if middle_idx != -1:
		_solve_middle[side] = (_skeleton.global_transform * _skeleton.get_bone_global_pose(middle_idx)).basis.get_rotation_quaternion()


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


## Override toggles (A/B proofs): turning anything OFF clears ALL overrides
## first (stale persistent locks otherwise survive toggle-off and pin bones —
## measured 25/09: thigh lock froze the leg with the writer disabled). The
## per-frame writers below re-assert the enabled ones on the next frame, so
## clearing is always self-healing. Only our overrides live on this skeleton.
func _apply_override_clear() -> void:
	if _skeleton == null:
		return
	_skeleton.clear_bones_global_pose_override()


func set_wrist_copy(v: bool) -> void:
	wrist_copy = v
	_apply_override_clear()


func set_ankle_copy(v: bool) -> void:
	ankle_copy = v
	_apply_override_clear()


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
	# Flip metric vs the CHAIN root (upper-bone top), not the metric shoulder:
	# for legs the shoulder (Hips) sits above the knee, which would read FLIP
	# at rest. Chain-root-relative, the pole side is the anatomical side.
	var chain_idx := _skeleton.find_bone(bones["upper"])
	var chain_w: Vector3 = _skeleton.to_global(_skeleton.get_bone_global_pose(chain_idx).origin) if chain_idx != -1 else root_w
	var ref: Vector3 = (pole.global_position - chain_w).normalized()
	var d: Vector3 = (joint_w - chain_w).normalized()
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


func _process(delta: float) -> void:
	# Slew FIRST (pre-pipeline): proxies ease toward user handles and the rig
	# toward the hips handle at SLEW_SPEED (frame-rate independent). TwoBone
	# twist is a motion transient (fast jumps excite it, static settles), so
	# the solver only ever sees capped per-frame inputs. Rotations stay direct
	# (stateless overrides, immune). Rubber-bands violent flicks.
	var step: float = SLEW_SPEED * maxf(delta, 0.0001)
	for limb in LIMB_ORDER:
		if _proxy.has(limb) and _handles.has(limb):
			var px: Node3D = _proxy[limb]
			var hx: Vector3 = (_handles[limb] as Node3D).global_position
			var d: Vector3 = hx - px.global_position
			px.global_position = hx if d.length() <= step else px.global_position + d.normalized() * step
	# Constraints next: auto-poles pin the bend planes, then the rig eases
	# toward the hips handle. Limb handles are scene-space so planted feet
	# stay planted and the IK re-solves around them.
	_update_auto_poles()
	if _hips != null:
		var rig := get_node_or_null("RigRoot") as Node3D
		if rig != null:
			var goal: Vector3 = _hips.global_position - _hips_rest
			var rd: Vector3 = goal - rig.global_position
			rig.global_position = goal if rd.length() <= step else rig.global_position + rd.normalized() * step
	if _label == null or _skeleton == null:
		return
	# Custom leg solve (same frame, pre-pipeline — stateless analytic, fills
	# the leg snapshot dicts + writes thigh/shin overrides; the ankle writer
	# below consumes the fresh _solve_pos like it did the signal snapshot).
	for limb in LEG_BONES:
		_solve_leg(limb)
	# Wrist + ankle writes (pre-pipeline, from the stored snapshot — see
	# _on_ik_processed): trace/label only read below.
	# (Thigh de-twist writer removed 25/09: persistent root overrides deadlock
	# the stateful solver. Twist handled as motion transient via slew above.)
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
		_trace_elapsed += delta
		_trace_accum += delta
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
		# solve once after the handles stop, then silence. Upper-bone euler
		# included (25/09 : le roll de cuisse est invisible à err/dot/flex/bow
		# — sans ça le log dit « ok » pendant que la fesse est inversée).
		key.append(int(round(float(_err.get(limb, 0.0)) * 10000.0)))
		key.append(int(round(float(_dot.get(limb, 0.0)) * 100.0)))
		key.append(int(round(float(_flex.get(limb, 0.0)))))
		key.append(int(round(float(_bow.get(limb, 0.0)) * 1000.0)))
		if _solve_upper.has(limb):
			var uq: Quaternion = _solve_upper[limb]
			var ue: Vector3 = uq.get_euler() * 180.0 / PI
			key.append(int(round(ue.x)))
			key.append(int(round(ue.y)))
			key.append(int(round(ue.z)))
	return key


## Joint state flag shared by overlay + trace: bow sign ONLY, with a magnitude
## gate. Rationale (probes 25/09): under pinned-plane TwoBone the elbow cannot
## leave the plane, so dot-perpendicularity (elbow straight below root while
## the pole sits behind — the natural hang) is benign; the old dot<0 guard
## false-fired on every deep fold (attack pose: dot −0.20 with elbow correctly
## 154 mm behind). Crossing to the wrong side (bow<0) is the one real
## inversion — gated at −15 mm because a quasi-straight limb has no bend
## direction and its bow sign is millimeter noise (measured ±13 mm flips
## firing EVENTs on flex-16 legs).
func _limb_flag(limb: StringName) -> String:
	if float(_bow.get(limb, 0.0)) < -0.015 and float(_flex.get(limb, 0.0)) > 20.0:
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
	lines.append("two+pole auto all limbs | wrist %s ankle %s | body +%.0fcm | gizmo: 5 handles + 4 cubes" % ["on" if wrist_copy else "off", "on" if ankle_copy else "off", (_hips.global_position - _hips_rest).length() * 100.0 if _hips != null else 0.0])
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
		var ue := Vector3.ZERO
		if _solve_upper.has(limb):
			var uq: Quaternion = _solve_upper[limb]
			var ub: Vector3 = uq.get_euler() * 180.0 / PI
			ue = Vector3(roundf(ub.x) + 0.0, roundf(ub.y) + 0.0, roundf(ub.z) + 0.0)
		parts.append("%s h=(%.2f,%.2f,%.2f) r=(%.0f,%.0f,%.0f) bone=(%.0f,%.0f,%.0f) ubone=(%.0f,%.0f,%.0f) pole=(%.2f,%.2f,%.2f) err=%.1f dot=%.2f flex=%.0f bow=%.0f %s" % [String(limb), hp.x, hp.y, hp.z, he.x, he.y, he.z, be.x, be.y, be.z, ue.x, ue.y, ue.z, pp.x, pp.y, pp.z, float(_err.get(limb, -1.0)) * 1000.0, float(_dot.get(limb, 0.0)), float(_flex.get(limb, 0.0)), float(_bow.get(limb, 0.0)) * 1000.0, _limb_flag(limb)])
	var tag := "EVENT %s" % event_limb if is_event else "snap"
	print("[AnimCreator %s t=%.1f] %s" % [tag, _trace_elapsed, " | ".join(parts)])


## Re-snaps user handles to rest (Reset button). ATOMIC (log humain 25/09 :
## reset pendant hips baissé plaçait les handles 21 cm trop bas — to_global
## dans le frame déplacé — d'où le « reset 2x » : le 1er posait faux, le 2e
## corrigeait une fois le rig remonté). Ordre : 1) hips au repos, 2) rig
## snappé (pas de slew), 3) handles placés dans le frame corrigé, 4) proxies
## snappés sur les handles (pas de chase — le slew ne sert qu'aux drags).
## Auto-poles need no reset (recomputed every frame).
func reset_handles() -> void:
	if _skeleton == null or _handles.is_empty():
		push_warning("[AnimCreator] reset: rig not built yet")
		return
	if _hips != null:
		_hips.global_position = _hips_rest
		var rig := get_node_or_null("RigRoot") as Node3D
		if rig != null:
			rig.global_position = _hips.global_position - _hips_rest
	for limb in LIMB_ORDER:
		(_handles[limb] as Node3D).global_position = _skeleton.to_global(_rest[limb] as Vector3)
		(_handles[limb] as Node3D).global_rotation = Vector3.ZERO
		# Zero-point follows the reset (else a saved rotated handle would
		# leave a stale rest-rot and offset the wrist after reset).
		_handle_rest_rot[limb] = Quaternion()
		if _proxy.has(limb):
			(_proxy[limb] as Node3D).global_position = (_handles[limb] as Node3D).global_position
	# Stale-snapshot pop (log humain 25/09 : reset posé = 1 frame EVENT err 335
	# bow −99 — les writers rejouaient le snapshot d'avant-reset pendant une
	# frame). Clear overrides + snapshots (les writers skippent sur snapshot
	# vide, les signaux remplissent dès le prochain solve frais).
	_apply_override_clear()
	_solve_pos.clear()
	_solve_fore.clear()
	_solve_end.clear()
	_solve_upper.clear()
	_solve_middle.clear()
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


## World orientation of the upper bone (thigh / upper arm), IN-SIGNAL stored.
## Hip-fold + thigh-roll diagnosis (buttock collapse report 25/09).
func upper_bone_quat(limb: StringName) -> Quaternion:
	return _solve_upper.get(limb, Quaternion())


## World orientation of the middle bone (shin / forearm), IN-SIGNAL stored.
func middle_bone_quat(limb: StringName) -> Quaternion:
	return _solve_middle.get(limb, Quaternion())


## TEMP 25/09 staged thigh basis determinant (mirror hunt).
func thigh_basis_det(limb: StringName) -> float:
	return float(_solve_upper_det.get(limb, 1.0))
