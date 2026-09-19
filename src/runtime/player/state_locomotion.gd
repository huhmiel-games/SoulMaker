class_name StateLocomotion
extends PlayerState

## Moving, body-relative (old feel): enter snaps the camera behind the body,
## then RS-X / mouse-X turns the BODY (camera yaw follow off, pitch still
## live). Stick tilt scales sneak/walk/run; keyboard saturates to run.
var _air := 0.0


func enter() -> void:
	_air = 0.0
	ctrl.reset_camera()
	ctrl.set_cam_yaw(false)


func exit() -> void:
	ctrl.set_cam_yaw(true)


func step(delta: float) -> int:
	var raw := intent.move_raw()
	var force := raw.length()
	if ctrl.is_on_floor():
		_air = 0.0
		if ctrl.velocity.y < 0.0:
			ctrl.velocity.y = -0.5
	else:
		ctrl.velocity.y -= PlayerController.GRAVITY * delta
		_air += delta
		if _air > PlayerController.AIR_TO_FALL:
			return PlayerStateMachine.FALL
	# Dodge tap wins over the turn/move below: neutral stick = backstep
	# hop, any input = committed roll in the input direction (stamina prepaid).
	if intent.dodge_pressed() and ctrl.is_on_floor():
		if raw == Vector2.ZERO:
			if ctrl.spend_stamina(PlayerController.BACKSTEP_COST):
				return PlayerStateMachine.BACKSTEP
		elif ctrl.spend_stamina(PlayerController.ROLL_COST):
			return PlayerStateMachine.ROLL
	# Turn the body with the shared turn feed (same value/units as the
	# camera orbit, so Idle-orbit and Move-turn feel identical). Degrees
	# in, radians out (rotation.y is radians).
	ctrl.rotation.y -= deg_to_rad(intent.turn_axis() * PlayerController.TURN_RATE * delta)
	if raw == Vector2.ZERO:
		var planar := Vector3(ctrl.velocity.x, 0.0, ctrl.velocity.z)
		planar = planar.move_toward(Vector3.ZERO, PlayerController.DECEL * delta)
		ctrl.velocity.x = planar.x
		ctrl.velocity.z = planar.z
		if planar.length() < 0.5:
			return PlayerStateMachine.IDLE
		return PlayerStateMachine.KEEP
	var cap := PlayerController.RUN_SPEED if force >= PlayerIntent.RUN_TRIGGER else PlayerController.WALK_SPEED
	ctrl.anim_state = &"run" if force >= PlayerIntent.RUN_TRIGGER else &"walk"
	var wish := intent.wish_direction(raw)
	var target := wish * cap * clampf(force, PlayerIntent.SNEAK_TRIGGER, 1.0)
	var planar := Vector3(ctrl.velocity.x, 0.0, ctrl.velocity.z)
	planar = planar.move_toward(target, PlayerController.ACCEL * delta)
	ctrl.velocity.x = planar.x
	ctrl.velocity.z = planar.z
	return PlayerStateMachine.KEEP
