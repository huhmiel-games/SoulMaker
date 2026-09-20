class_name StateRoll
extends PlayerState

## Committed directional roll (P2 single tier — fast/mid/fat roll tiers are
## P3): always in the input direction, which is nonzero by construction
## (neutral stick goes to Backstep). Free, the body turns toward _dir
## (single facing — a diagonal roll ends facing the roll, souls rule); the
## camera is never touched beyond the world-yaw preserve. Locked rolls keep
## tracking the enemy instead (zero extra code). Stamina is prepaid by the
## caller — enter only arms i-frames. Grounded only: walked off an edge
## mid-roll -> Fall.
## The clip ("Quick Roll To Run", 1.43 s) opens on ~0.55 s of anticipation
## crouch — enter seeks past it (ctrl.anim_seek) so the visible tuck matches
## the committed displacement.
var _t := 0.0
var _dir := Vector3.ZERO


func enter() -> void:
	_t = 0.0
	_dir = intent.wish_direction(intent.move_raw())
	ctrl.anim_state = &"roll"
	ctrl.anim_seek = PlayerController.ROLL_SEEK
	ctrl.iframes = PlayerController.ROLL_IFRAMES
	print("[SM] Roll dir %s" % _dir)


func step(delta: float) -> int:
	_t += delta
	if ctrl.is_on_floor():
		if ctrl.velocity.y < 0.0:
			ctrl.velocity.y = -0.5
	else:
		ctrl.velocity.y -= PlayerController.GRAVITY * delta
		if _t > 0.15:
			return PlayerStateMachine.FALL
	# Locked rolls keep tracking the target through the displacement; free
	# rolls turn the body toward the roll (single facing). Either way the
	# camera never freezes mid-roll.
	if ctrl.lock_target != null:
		ctrl.track_lock_target(delta)
	else:
		ctrl.turn_body_to(_dir, delta)
	ctrl.velocity.x = _dir.x * PlayerController.ROLL_SPEED
	ctrl.velocity.z = _dir.z * PlayerController.ROLL_SPEED
	if _t >= PlayerController.ROLL_TIME:
		# Lock survives the roll: still valid = back to LockOn (re-snaps
		# facing on enter), otherwise the free exit routing.
		if ctrl.lock_target != null and ctrl.lock_valid():
			return PlayerStateMachine.LOCKON
		if intent.move_raw() != Vector2.ZERO:
			return PlayerStateMachine.LOCOMOTION
		return PlayerStateMachine.IDLE
	return PlayerStateMachine.KEEP
