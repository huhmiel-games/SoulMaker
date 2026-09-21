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
	# Light attack (after dodge — defense wins ties): forward + shove carrier
	# = blade shove (S3), otherwise the normal swing. Clip + stamina gates.
	if intent.attack_light_pressed() and ctrl.is_on_floor() and ctrl.attack_clip() != &"":
		if intent.forward_held() and ctrl.shove_available():
			if ctrl.spend_stamina(PlayerController.SHOVE_STAMINA):
				return PlayerStateMachine.SHOVE
		elif ctrl.spend_stamina(float(ctrl.attack_phases().get("stamina_cost", 20.0))):
			return PlayerStateMachine.ATTACK
	# Guard hold (after attack — a tap attacks, a hold guards).
	if ctrl.guard_wanted() and ctrl.is_on_floor():
		return PlayerStateMachine.GUARD
	if raw != Vector2.ZERO and ctrl.is_on_floor():
		return PlayerStateMachine.LOCOMOTION
	return PlayerStateMachine.KEEP
