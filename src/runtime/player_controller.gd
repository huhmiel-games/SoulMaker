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
var stamina := STAMINA_MAX
## Invulnerability countdown (seconds left): set by StateDodge on enter,
## ticked here, read by future enemy hitboxes via is_invulnerable().
var iframes := 0.0
var _regen_wait := 0.0

var _player: AnimationPlayer = null
var _clips := {}
var _anim_cur := &""


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	InputManager.set_profile(&"game")
	ToonKit.apply_to(self)
	var ms := Moveset.load_object()
	for issue in Moveset.validate_moveset(ms):
		push_warning("[Moveset] %s" % issue)
	_player = RigKit.build_player(rig_root, Moveset.packs_of(ms))
	_clips = Moveset.resolve_clips(ms, _player)
	if _player != null:
		_play(_clips.get(&"idle", &""))
		print("[Player] clips idle=%s walk=%s run=%s fall=%s roll=%s backstep=%s" % [_clips.get(&"idle"), _clips.get(&"walk"), _clips.get(&"run"), _clips.get(&"fall"), _clips.get(&"roll"), _clips.get(&"backstep")])
	intent.setup(self)
	var idle := StateIdle.new()
	var loco := StateLocomotion.new()
	var fall := StateFall.new()
	var roll := StateRoll.new()
	var backstep := StateBackstep.new()
	for st in [idle, loco, fall, roll, backstep]:
		(st as PlayerState).setup(self, intent)
	machine.add_state(PlayerStateMachine.IDLE, idle)
	machine.add_state(PlayerStateMachine.LOCOMOTION, loco)
	machine.add_state(PlayerStateMachine.FALL, fall)
	machine.add_state(PlayerStateMachine.ROLL, roll)
	machine.add_state(PlayerStateMachine.BACKSTEP, backstep)
	machine.start(PlayerStateMachine.IDLE)
	print("[Player] ready — profile %s, body-relative, nodess SM" % InputManager.get_profile())


func _physics_process(delta: float) -> void:
	_tick_stamina(delta)
	if iframes > 0.0:
		iframes = maxf(iframes - delta, 0.0)
	machine.step(delta)
	move_and_slide()
	# Backstep keeps its entry facing (souls rule): the rig never swings
	# toward the hop, only the displacement goes back.
	if machine.state_id() != PlayerStateMachine.BACKSTEP:
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


## Snap the aft camera behind the body (Locomotion enter, old reset_camera).
func reset_camera() -> void:
	rotation.y += cam_pivot.rotation.y
	cam_pivot.rotation.y = 0.0
	camera.snap_aft()


func set_cam_yaw(enabled: bool) -> void:
	camera.yaw_enabled = enabled


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


func _process(_delta: float) -> void:
	if state_label != null:
		var planar := Vector2(velocity.x, velocity.z).length()
		state_label.text = "%s · speed %.1f · floor %s · anim %s · stam %.0f%s\nprofile %s · raw %s" % [
			machine.state_name(),
			planar,
			"yes" if is_on_floor() else "NO",
			_anim_cur,
			stamina,
			" INVULN" if is_invulnerable() else "",
			InputManager.get_profile(),
			intent.move_raw(),
		]
