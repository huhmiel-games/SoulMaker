class_name StateLockOn
extends PlayerState

## Lock-on locomotion (P2, one fake enemy): the body auto-faces the target
## (eased, camera world-yaw preserved via shift_yaw) and the camera eases
## behind the body (track_aft), so it looks at the target — pitch stays
## manual. Movement is body-relative, hence enemy-relative for free: forward
## closes in, strafe orbits, neutral backstep hops away. Rolls from here are
## lock-on rolls with zero extra code. Exit on toggle, dead/gone target, or
## past break range. No exit() yaw restore: Idle/Locomotion enters own the
## yaw mode, Roll/Backstep inherit it.
var _air := 0.0


func enter() -> void:
	_air = 0.0
	# Null guard (hardening 22/09 — the Plunge->LockOn Nil crash): a LockOn
	# enter without target skips the snap; step() releases next tick.
	if ctrl.lock_target == null or not is_instance_valid(ctrl.lock_target):
		ctrl.set_cam_yaw(true)
		ctrl.anim_state = &"idle"
		print("[SM] LockOn enter without target (release next tick)")
		return
	_snap_face()
	ctrl.set_cam_yaw(false)
	ctrl.anim_state = &"idle"
	print("[SM] LockOn %s" % ctrl.lock_target.name)


func step(delta: float) -> int:
	if intent.lock_pressed() or not ctrl.lock_valid():
		return _release()
	var raw := intent.move_raw()
	var force := raw.length()
	if ctrl.is_on_floor():
		_air = 0.0
		if ctrl.velocity.y < 0.0:
			ctrl.velocity.y = -0.5
	else:
		ctrl.velocity.y -= PlayerController.GRAVITY * delta
		_air += delta
		if _air > PlayerController.AIR_TO_FALL or ctrl.falling_fast():
			return PlayerStateMachine.FALL
	# Track the target: shared helper (body ease + camera follow).
	ctrl.track_lock_target(delta)
	# Dodge gates, same as Locomotion: neutral = backstep (away, free),
	# input = roll (enemy-relative, free).
	if intent.dodge_pressed() and ctrl.is_on_floor():
		if raw == Vector2.ZERO:
			if ctrl.spend_stamina(ctrl.backstep_cost()):
				return PlayerStateMachine.BACKSTEP
		elif ctrl.spend_stamina(ctrl.roll_cost()):
			return PlayerStateMachine.ROLL
	# Light attack (after dodge): forward + shove carrier = blade shove
	# (S3), otherwise the normal swing. Same clip + stamina gate, lock kept.
	if intent.attack_light_pressed() and ctrl.is_on_floor() and ctrl.attack_clip() != &"":
		if intent.forward_held() and ctrl.shove_available():
			if ctrl.spend_stamina(PlayerController.SHOVE_STAMINA):
				return PlayerStateMachine.SHOVE
		elif ctrl.spend_stamina(float(ctrl.attack_phases().get("stamina_cost", 20.0))):
			return PlayerStateMachine.ATTACK
	# Guard hold (after attack — a tap attacks, a hold guards).
	if ctrl.guard_wanted() and ctrl.is_on_floor():
		return PlayerStateMachine.GUARD
	var planar := Vector3(ctrl.velocity.x, 0.0, ctrl.velocity.z)
	if raw == Vector2.ZERO:
		ctrl.anim_state = &"idle"
		planar = planar.move_toward(Vector3.ZERO, PlayerController.DECEL * delta)
		ctrl.velocity.x = planar.x
		ctrl.velocity.z = planar.z
		return PlayerStateMachine.KEEP
	var cap := PlayerController.RUN_SPEED if force >= PlayerIntent.RUN_TRIGGER else PlayerController.WALK_SPEED
	ctrl.anim_state = &"run" if force >= PlayerIntent.RUN_TRIGGER else &"walk"
	var wish := intent.wish_direction(raw)
	var target := wish * cap * clampf(force, PlayerIntent.SNEAK_TRIGGER, 1.0)
	planar = planar.move_toward(target, PlayerController.ACCEL * delta)
	ctrl.velocity.x = planar.x
	ctrl.velocity.z = planar.z
	return PlayerStateMachine.KEEP


## Snap the body onto the target at engage (camera frozen via shift_yaw —
## reset_camera convention).
func _snap_face() -> void:
	var to: Vector3 = ctrl.lock_chest() - ctrl.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	var before := ctrl.rotation.y
	ctrl.rotation.y = atan2(-to.x, -to.z)
	ctrl.camera.shift_yaw(ctrl.rotation.y - before)


func _release() -> int:
	ctrl.clear_lock()
	if intent.move_raw() != Vector2.ZERO:
		return PlayerStateMachine.LOCOMOTION
	return PlayerStateMachine.IDLE
