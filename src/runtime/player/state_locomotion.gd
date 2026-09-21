class_name StateLocomotion
extends PlayerState

## Moving, souls frame (P2): the wish is camera-relative, the body turns
## toward it (turn_body_to — camera world-yaw preserved), the mesh is the
## body (single facing, no strafe-profile). Camera yaw follow stays on —
## orbiting while moving bends the run, souls standard. Stick tilt scales
## sneak/walk/run; keyboard saturates to run. At rest the body keeps its
## facing (decel branch turns nothing).
var _air := 0.0


func enter() -> void:
	_air = 0.0
	ctrl.set_cam_yaw(true)


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
	# Lock-on tap wins over the turn/move below (acquire gates the transition).
	if intent.lock_pressed() and ctrl.try_acquire_lock():
		return PlayerStateMachine.LOCKON
	# Dodge tap wins over the turn/move below: neutral stick = backstep
	# hop, any input = committed roll in the input direction (stamina prepaid).
	if intent.dodge_pressed() and ctrl.is_on_floor():
		if raw == Vector2.ZERO:
			if ctrl.spend_stamina(PlayerController.BACKSTEP_COST):
				return PlayerStateMachine.BACKSTEP
		elif ctrl.spend_stamina(PlayerController.ROLL_COST):
			return PlayerStateMachine.ROLL
	# Light attack (after dodge — defense wins ties): clip + stamina gate.
	if intent.attack_light_pressed() and ctrl.is_on_floor() and ctrl.attack_clip() != &"" and ctrl.spend_stamina(float(ctrl.attack_phases().get("stamina_cost", 20.0))):
		return PlayerStateMachine.ATTACK
	var planar := Vector3(ctrl.velocity.x, 0.0, ctrl.velocity.z)
	if raw == Vector2.ZERO:
		planar = planar.move_toward(Vector3.ZERO, PlayerController.DECEL * delta)
		ctrl.velocity.x = planar.x
		ctrl.velocity.z = planar.z
		if planar.length() < 0.5:
			return PlayerStateMachine.IDLE
		return PlayerStateMachine.KEEP
	var cap := PlayerController.RUN_SPEED if force >= PlayerIntent.RUN_TRIGGER else PlayerController.WALK_SPEED
	ctrl.anim_state = &"run" if force >= PlayerIntent.RUN_TRIGGER else &"walk"
	var wish := intent.wish_direction(raw)
	# Single facing: the body turns toward the wish (free only — this state
	# never runs locked), then the wish accelerates the body.
	ctrl.turn_body_to(wish, delta)
	var target := wish * cap * clampf(force, PlayerIntent.SNEAK_TRIGGER, 1.0)
	planar = planar.move_toward(target, PlayerController.ACCEL * delta)
	ctrl.velocity.x = planar.x
	ctrl.velocity.z = planar.z
	return PlayerStateMachine.KEEP
