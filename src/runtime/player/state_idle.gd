class_name StateIdle
extends PlayerState

## Standing (P2): planar velocity decays, camera orbits freely (yaw follow
## on), any move input enters Locomotion. First nonzero input is logged —
## the boot self-test that proves input reaches the states.
var _air := 0.0
var _logged_input := false


func enter() -> void:
	_air = 0.0
	ctrl.anim_state = &"idle"
	ctrl.set_cam_yaw(true)


func step(delta: float) -> int:
	var raw := intent.move_raw()
	if not _logged_input and raw != Vector2.ZERO:
		_logged_input = true
		print("[SM] first input raw %s" % raw)
	if ctrl.is_on_floor():
		_air = 0.0
		if ctrl.velocity.y < 0.0:
			ctrl.velocity.y = -0.5
	else:
		ctrl.velocity.y -= PlayerController.GRAVITY * delta
		_air += delta
		if _air > PlayerController.IDLE_AIR_TO_FALL:
			return PlayerStateMachine.FALL
	var planar := Vector3(ctrl.velocity.x, 0.0, ctrl.velocity.z)
	planar = planar.move_toward(Vector3.ZERO, PlayerController.DECEL * delta)
	ctrl.velocity.x = planar.x
	ctrl.velocity.z = planar.z
	# Lock-on tap wins over everything below (acquire gates the transition).
	if intent.lock_pressed() and ctrl.try_acquire_lock():
		return PlayerStateMachine.LOCKON
	# Dodge tap: neutral stick = backstep hop (no rotation, no i-frames),
	# any input = committed roll in the input direction. Stamina prepaid here.
	if intent.dodge_pressed() and ctrl.is_on_floor():
		if raw == Vector2.ZERO:
			if ctrl.spend_stamina(PlayerController.BACKSTEP_COST):
				return PlayerStateMachine.BACKSTEP
		elif ctrl.spend_stamina(PlayerController.ROLL_COST):
			return PlayerStateMachine.ROLL
	if raw != Vector2.ZERO and ctrl.is_on_floor():
		return PlayerStateMachine.LOCOMOTION
	return PlayerStateMachine.KEEP
