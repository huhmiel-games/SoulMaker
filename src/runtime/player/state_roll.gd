class_name StateRoll
extends PlayerState

## Committed directional roll (P3 S4 tiers, features/17 equip-load): always
## in the input direction, which is nonzero by construction (neutral stick
## goes to Backstep). The tier (fast/mid/fat from equip_load_ratio) sets
## i-frames, distance-derived speed and a recovery tail — the fat roll is
## visibly taxed (slow anim, short roll, long planted recovery). Free, the
## body turns toward _dir (single facing); locked rolls keep tracking the
## enemy instead. Stamina is prepaid by the caller — enter only arms
## i-frames. Grounded only: walked off an edge mid-roll -> Fall.
## The clip ("Quick Roll To Run", 1.43 s) opens on ~0.55 s of anticipation
## crouch — enter seeks past it (ctrl.anim_seek) so the visible tuck matches
## the committed displacement.
var _t := 0.0
var _dir := Vector3.ZERO
var _speed := 6.0
var _base_time := 0.8
var _recovery := 0.0
var _tier := &"fast"
var _thudded := false


func enter() -> void:
	_t = 0.0
	_dir = intent.wish_direction(intent.move_raw())
	_tier = ctrl.roll_tier()
	_thudded = false
	var params := ctrl.roll_params()
	_base_time = float((ctrl.mobility_cfg.get("roll", {}) as Dictionary).get("base_time", PlayerController.ROLL_TIME))
	_speed = float(params.get("distance", 4.0)) / maxf(_base_time, 0.05)
	_recovery = maxf(float(params.get("recovery_bonus", 0.0)), 0.0)
	ctrl.anim_state = &"roll"
	ctrl.anim_seek = PlayerController.ROLL_SEEK
	ctrl.iframes = float(params.get("iframes", PlayerController.ROLL_IFRAMES))
	ctrl.set_anim_speed(maxf(float(params.get("anim_speed", 1.0)), 0.1))
	print("[SM] Roll tier=%s dir %s" % [str(ctrl.roll_tier()), str(_dir)])


func exit() -> void:
	ctrl.set_anim_speed(1.0)


func step(delta: float) -> int:
	_t += delta
	if ctrl.is_on_floor():
		if ctrl.velocity.y < 0.0:
			ctrl.velocity.y = -0.5
	else:
		ctrl.velocity.y -= PlayerController.GRAVITY * delta
		if _t > 0.15:
			return PlayerStateMachine.FALL
	# Fat-roll thud (graybox): rumble when the back hits the ground. Timing is
	# FAT_THUD_TIME on the controller — recalibrate on the real anim (P4).
	if not _thudded and _tier == &"fat" and _t >= PlayerController.FAT_THUD_TIME:
		_thudded = true
		InputManager.rumble(0.4, 0.8, 0.2)
		print("[SM] Roll fat thud")
	# Locked rolls keep tracking the target through the displacement; free
	# rolls turn the body toward the roll (single facing). Either way the
	# camera never freezes mid-roll.
	if ctrl.lock_target != null:
		ctrl.track_lock_target(delta)
	else:
		ctrl.turn_body_to(_dir, delta)
	if _t < _base_time:
		ctrl.velocity.x = _dir.x * _speed
		ctrl.velocity.z = _dir.z * _speed
	elif _t < _base_time + _recovery:
		# Recovery tail (fat tax): planted, velocity decays, no re-steer.
		var planar := Vector3(ctrl.velocity.x, 0.0, ctrl.velocity.z)
		planar = planar.move_toward(Vector3.ZERO, PlayerController.DECEL * delta)
		ctrl.velocity.x = planar.x
		ctrl.velocity.z = planar.z
		return PlayerStateMachine.KEEP
	else:
		# Lock survives the roll: still valid = back to LockOn (re-snaps
		# facing on enter), otherwise the free exit routing.
		if ctrl.lock_target != null and ctrl.lock_valid():
			return PlayerStateMachine.LOCKON
		if intent.move_raw() != Vector2.ZERO:
			return PlayerStateMachine.LOCOMOTION
		return PlayerStateMachine.IDLE
	return PlayerStateMachine.KEEP
