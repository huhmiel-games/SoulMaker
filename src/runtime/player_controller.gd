class_name PlayerController
extends CharacterBody3D

## P2 thin player, body-relative locomotion (old feel, nodess states): owns
## velocity + move_and_slide, the state machine, the visual rig facing (the
## BODY yaws for real in Locomotion — the camera never inherits a yaw it did
## not ask for) and anim resolution via RigKit. No AnimationTree.
## Body forward is -Z (Godot convention); the rig is authored +Z, hence the
## PI base yaw below. Spawn faces away from the aft camera.
const WALK_SPEED := 2.5
const RUN_SPEED := 8.0
const ACCEL := 36.0
const DECEL := 44.0
const TURN_RATE := 168.0 # degrees/sec, mirrors PlayerCamera.YAW_RATE: same feed, same feel
const GRAVITY := 22.0
const AIR_TO_FALL := 0.65
const IDLE_AIR_TO_FALL := 0.35
const RIG_TURN := 10.0
const RIG_BASE_YAW := PI
const ANIM_BLEND := 0.15
## Stamina (P2 local pool — P7 derives max/regen from Endurance): dodge is
## the only spender for now. Depleted = dodge denied, regen pauses REGEN_DELAY
## after every spend.
const STAMINA_MAX := 100.0
const DODGE_COST := 25.0
const STAMINA_REGEN := 45.0
const REGEN_DELAY := 0.8
## Dodge rolls (P2 single tier — fast/mid/fat roll tiers are P3): committed
## constant-speed roll (forward/laterals), i-frames up front, then recovery
## to the buffered state. Neutral/backward input becomes a BACKSTEP instead
## (spacing hop, no rotation, no i-frames — features/17).
const ROLL_COST := 25.0
const ROLL_SPEED := 6.0
const ROLL_TIME := 0.8
const ROLL_IFRAMES := 0.5
## Clip opens on ~0.55 s anticipation — seek past it on enter (see anim_seek).
const ROLL_SEEK := 0.55
const BACKSTEP_COST := 15.0
const BACKSTEP_SPEED := 3.5
const BACKSTEP_TIME := 0.7
## Clip idles ~0.8 s before the impulse — seek past it on enter.
const BACKSTEP_SEEK := 0.8
## Light attack (P2 single swing): forward step during the attack section
## (the swing carries through — features/01), planted otherwise.
const ATTACK_STEP := 2.0

## Locomotion clips resolve from data/characters/player_moveset.json (packs
## + slots + active variant); FALLBACK lives in Moveset, not here.

## Attach points (must exist in the scene scaffold).
@onready var rig_root: Node3D = get_node("RigRoot")
@onready var wedge: Node3D = get_node("FootWedge")
@onready var cam_pivot: Node3D = get_node("CamPivot")
@onready var camera: PlayerCamera = get_node("CamPivot") as PlayerCamera
@onready var state_label: Label = get_node("../HUD/State")

var intent := PlayerIntent.new()
var machine := PlayerStateMachine.new()
var anim_state := &"idle"
## One-shot anim offset (seconds) consumed by _resolve_anim: states seek past
## clip anticipation so the visible motion matches the committed displacement.
var anim_seek := -1.0
## Manual playback flag: StateAttack drives marker sections itself
## (play_phase) — _resolve_anim stands down while set.
var anim_manual := false
var stamina := STAMINA_MAX
## Invulnerability countdown (seconds left): set by StateDodge on enter,
## ticked here, read by future enemy hitboxes via is_invulnerable().
var iframes := 0.0
var _regen_wait := 0.0

var _player: AnimationPlayer = null
var _clips := {}
var _anim_cur := &""
## Resolved attack phases per attack slot (Moveset.phases_for at boot).
var _attack_phases := {}


## Light-attack clip ("" = unresolved, attack refused — never T-poses).
func attack_clip() -> StringName:
	return _clips.get(&"attack_light_1", &"")


## Phases + speeds + stamina cost for the light attack (data-driven).
func attack_phases() -> Dictionary:
	return _attack_phases.get(&"attack_light_1", Moveset.PHASE_DEFAULTS)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	InputManager.set_profile(&"game")
	ToonKit.apply_to(self)
	var ms := Moveset.load_object()
	for issue in Moveset.validate_moveset(ms):
		push_warning("[Moveset] %s" % issue)
	_player = RigKit.build_player(rig_root, Moveset.packs_of(ms))
	_clips = Moveset.resolve_clips(ms, _player)
	_attack_phases[&"attack_light_1"] = Moveset.phases_for(ms, &"attack_light_1")
	if _player != null:
		_play(_clips.get(&"idle", &""))
		print("[Player] clips idle=%s walk=%s run=%s fall=%s roll=%s backstep=%s attack=%s" % [_clips.get(&"idle"), _clips.get(&"walk"), _clips.get(&"run"), _clips.get(&"fall"), _clips.get(&"roll"), _clips.get(&"backstep"), _clips.get(&"attack_light_1")])
	intent.setup(self)
	var idle := StateIdle.new()
	var loco := StateLocomotion.new()
	var fall := StateFall.new()
	var roll := StateRoll.new()
	var backstep := StateBackstep.new()
	var lockon := StateLockOn.new()
	var attack := StateAttack.new()
	for st in [idle, loco, fall, roll, backstep, lockon, attack]:
		(st as PlayerState).setup(self, intent)
	machine.add_state(PlayerStateMachine.IDLE, idle)
	machine.add_state(PlayerStateMachine.LOCOMOTION, loco)
	machine.add_state(PlayerStateMachine.FALL, fall)
	machine.add_state(PlayerStateMachine.ROLL, roll)
	machine.add_state(PlayerStateMachine.BACKSTEP, backstep)
	machine.add_state(PlayerStateMachine.LOCKON, lockon)
	machine.add_state(PlayerStateMachine.ATTACK, attack)
	machine.start(PlayerStateMachine.IDLE)
	print("[Player] ready — profile %s, body-relative, nodess SM" % InputManager.get_profile())


func _physics_process(delta: float) -> void:
	_tick_stamina(delta)
	if iframes > 0.0:
		iframes = maxf(iframes - delta, 0.0)
	machine.step(delta)
	move_and_slide()
	# Facing ownership: Backstep freezes entry facing, LockOn nails the rig
	# onto the enemy (body already tracks it — mesh must not strafe-profile),
	# everything else eases the rig toward travel.
	var sid := machine.state_id()
	if sid == PlayerStateMachine.LOCKON:
		_face_lock(delta)
	elif sid != PlayerStateMachine.BACKSTEP:
		_face_rig(delta)
	_resolve_anim()
	# Foot bevel follows the visual facing (old StairShapeHandler line).
	wedge.rotation.y = rig_root.rotation.y + PI


## Stamina spend gate: true + deducts when affordable, false when denied
## (no partial spend, no overdraw — edge case from features/01).
func spend_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina -= amount
	_regen_wait = REGEN_DELAY
	return true


func is_invulnerable() -> bool:
	return iframes > 0.0


func _tick_stamina(delta: float) -> void:
	if _regen_wait > 0.0:
		_regen_wait -= delta
		return
	stamina = minf(stamina + STAMINA_REGEN * delta, STAMINA_MAX)


## Lock-on (P2): tap MMB/R3 to lock the nearest lockable in the front cone,
## tap again / target gone / past break range to release. The FakeEnemy
## cylinder carries a LockMarker child shown while locked.
const LOCK_RANGE := 20.0
const LOCK_BREAK := 25.0
const LOCK_HALF_ANGLE := 60.0 # degrees, front cone at acquire
const LOCK_FACE := 10.0 # body ease toward the target (weight/sec)
const LOCK_CHEST := 1.2 # aim height on the target

var lock_target: Node3D = null


## Nearest lockable inside LOCK_RANGE and the front cone. Arms the marker.
func try_acquire_lock() -> bool:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3(0.0, 0.0, -1.0)
	var best: Node3D = null
	var best_d := LOCK_RANGE
	for n in get_tree().get_nodes_in_group("lockable"):
		if not (n is Node3D):
			continue
		var to: Vector3 = (n as Node3D).global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > LOCK_RANGE or d < 0.001:
			continue
		if rad_to_deg(acos(clampf(fwd.dot(to / d), -1.0, 1.0))) > LOCK_HALF_ANGLE:
			continue
		if d < best_d:
			best_d = d
			best = n
	if best == null:
		return false
	lock_target = best
	_set_marker(true)
	print("[Player] lock acquired %s %.1fm" % [best.name, best_d])
	return true


func clear_lock() -> void:
	if lock_target != null and is_instance_valid(lock_target):
		_set_marker(false)
		print("[Player] lock released")
	lock_target = null


## Still locked: target alive and inside break range (called every LockOn tick).
func lock_valid() -> bool:
	if lock_target == null or not is_instance_valid(lock_target):
		lock_target = null
		return false
	var to: Vector3 = lock_target.global_position - global_position
	to.y = 0.0
	if to.length() > LOCK_BREAK:
		return false
	return true


func lock_chest() -> Vector3:
	return lock_target.global_position + Vector3(0.0, LOCK_CHEST, 0.0)


func lock_distance() -> float:
	if lock_target == null or not is_instance_valid(lock_target):
		return -1.0
	var to: Vector3 = lock_target.global_position - global_position
	to.y = 0.0
	return to.length()


func _set_marker(on: bool) -> void:
	if lock_target != null and lock_target.has_node("LockMarker"):
		(lock_target.get_node("LockMarker") as Node3D).visible = on


## Lock-on tracking shared by LockOn/Roll/Backstep: ease the body toward
## the target (camera world-yaw preserved via shift_yaw) and the camera
## behind the body (track_aft). No-op without a valid lock — free motion is
## untouched. Displacement states keep their own locked _dir; only facing
## and camera track through them, so the camera never freezes mid-roll.
func track_lock_target(delta: float) -> void:
	if lock_target == null or not lock_valid():
		return
	var to: Vector3 = lock_chest() - global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		var before := rotation.y
		rotation.y = lerp_angle(before, atan2(-to.x, -to.z), minf(LOCK_FACE * delta, 1.0))
		camera.shift_yaw(rotation.y - before)
	camera.track_aft(delta)


## Snap the aft camera behind the body (Locomotion enter, old reset_camera).
func reset_camera() -> void:
	rotation.y += cam_pivot.rotation.y
	cam_pivot.rotation.y = 0.0
	camera.snap_aft()


func set_cam_yaw(enabled: bool) -> void:
	camera.yaw_enabled = enabled


## Lock-on facing: ease the rig onto the body heading (RIG_BASE_YAW), i.e.
## the mesh looks at whatever the body looks at — the enemy. Same rate as
## the travel ease so handoffs in/out of LockOn never pop.
func _face_lock(delta: float) -> void:
	rig_root.rotation.y = lerp_angle(rig_root.rotation.y, RIG_BASE_YAW, minf(RIG_TURN * delta, 1.0))


## Visual facing only: ease the rig toward the body-local travel direction
## (strafe turns the rig sideways, body stays — old model.look_at rule).
func _face_rig(delta: float) -> void:
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	if planar.length() < 0.5:
		return
	var local: Vector3 = global_transform.basis.inverse() * planar
	var want := RIG_BASE_YAW + atan2(-local.x, -local.z)
	rig_root.rotation.y = lerp_angle(rig_root.rotation.y, want, minf(RIG_TURN * delta, 1.0))


func _resolve_anim() -> void:
	# Attack drives its own marker sections (play_phase) — the auto-resolve
	# stands down or it would replay the whole clip over the sections.
	if anim_manual:
		return
	_play(str(_clips.get(anim_state, &"")))
	if anim_seek >= 0.0 and _player != null:
		_player.seek(anim_seek, true)
		anim_seek = -1.0


func _play(anim: StringName) -> void:
	if anim != &"" and anim != _anim_cur and _player != null:
		_player.play(anim, ANIM_BLEND)
		if _anim_cur != &"":
			print("[Player] anim %s" % anim)
		_anim_cur = anim


## Manual section playback for StateAttack: plays one marker section at its
## data speed. Sets anim_manual (auto-resolve off) — the state clears it.
func play_phase(clip: StringName, sec_from: StringName, sec_to: StringName, speed: float) -> void:
	if _player == null or clip == &"":
		return
	anim_manual = true
	_player.play_section_with_markers(clip, sec_from, sec_to, ANIM_BLEND, speed)
	_anim_cur = str(clip)


## End time of the currently playing section (0 when idle).
func phase_end() -> float:
	if _player == null:
		return 0.0
	return _player.get_section_end_time()


## Position inside the current section (-1 when nothing plays = done).
func anim_pos() -> float:
	if _player == null or not _player.is_playing():
		return -1.0
	return _player.current_animation_position


## Marker time on a rig clip (0 when missing — lets states detect degenerate
## sections without calling the native section player).
func marker_time(clip: StringName, marker: StringName) -> float:
	if _player == null:
		return 0.0
	var anim: Animation = _player.get_animation(clip)
	if anim == null or not anim.has_marker(marker):
		return 0.0
	return anim.get_marker_time(marker)


func _process(_delta: float) -> void:
	if state_label != null:
		var planar := Vector2(velocity.x, velocity.z).length()
		state_label.text = "%s · speed %.1f · floor %s · anim %s · stam %.0f%s%s\nprofile %s · raw %s" % [
			machine.state_name(),
			planar,
			"yes" if is_on_floor() else "NO",
			_anim_cur,
			stamina,
			" INVULN" if is_invulnerable() else "",
			" LOCK %.1fm" % lock_distance() if lock_target != null else "",
			InputManager.get_profile(),
			intent.move_raw(),
		]
