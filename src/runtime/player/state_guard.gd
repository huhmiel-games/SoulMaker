class_name StateGuard
extends PlayerState

## Raised shield (P3 S1 graybox, features/17 block/guard): entered from the
## grounded states while guard is held (Shift / L1). Full walk/run speed
## (DS3 check 23/09 — no guard slowdown), body faces the lock target when
## locked, the wish otherwise; dodge and attack drop the guard (same stamina
## gates as LockOn). take_hit resolves blocks while here (controller-side) —
## this state only owns the posture, the movement and the exits.
## Posture is the guard_idle slot (block idle loop, two_hand blocking loop),
## crab locomotion while moving (lock_anim_for, run-capable like LockOn).
var _air := 0.0


func enter() -> void:
	_air = 0.0
	ctrl.anim_state = &"guard_idle"
	ctrl.anim_seek = -1.0
	print("[SM] Guard %s" % str(ctrl.guard_cfg.get("equipped_shield", "?")))


func step(delta: float) -> int:
	var raw := intent.move_raw()
	if ctrl.is_on_floor():
		_air = 0.0
		if ctrl.velocity.y < 0.0:
			ctrl.velocity.y = -0.5
	else:
		ctrl.velocity.y -= PlayerController.GRAVITY * delta
		_air += delta
		if _air > PlayerController.AIR_TO_FALL or ctrl.falling_fast():
			return PlayerStateMachine.FALL
	if not ctrl.guard_wanted():
		return _release()
	if ctrl.lock_target != null and ctrl.lock_valid():
		ctrl.track_lock_target(delta)
	elif raw != Vector2.ZERO:
		ctrl.turn_body_to(intent.wish_direction(raw), delta)
	# Dodge and attack drop the guard (defense still wins ties — same
	# gates as LockOn).
	if intent.dodge_pressed() and ctrl.is_on_floor():
		if raw == Vector2.ZERO:
			if ctrl.spend_stamina(ctrl.backstep_cost()):
				return PlayerStateMachine.BACKSTEP
		elif ctrl.spend_stamina(ctrl.roll_cost()):
			return PlayerStateMachine.ROLL
	# Attack drops the guard: forward + shove carrier = blade shove (S3),
	# otherwise the normal swing. Same gates as LockOn.
	if intent.attack_light_pressed() and ctrl.is_on_floor() and ctrl.attack_clip() != &"":
		if intent.forward_held() and ctrl.shove_available():
			if ctrl.spend_stamina(PlayerController.SHOVE_STAMINA):
				return PlayerStateMachine.SHOVE
		elif ctrl.spend_stamina(float(ctrl.attack_phases().get("stamina_cost", 20.0))):
			return PlayerStateMachine.ATTACK
	var planar := Vector3(ctrl.velocity.x, 0.0, ctrl.velocity.z)
	if raw == Vector2.ZERO:
		ctrl.anim_state = &"guard_idle"
		planar = planar.move_toward(Vector3.ZERO, PlayerController.DECEL * delta)
		ctrl.velocity.x = planar.x
		ctrl.velocity.z = planar.z
		return PlayerStateMachine.KEEP
	var fast := raw.length() >= PlayerIntent.RUN_TRIGGER
	ctrl.anim_state = ctrl.lock_anim_for(raw, fast) if ctrl.lock_target != null else (&"run" if fast else &"walk")
	var wish := intent.wish_direction(raw)
	var cap := PlayerController.RUN_SPEED if fast else PlayerController.WALK_SPEED
	var target := wish * cap
	planar = planar.move_toward(target, PlayerController.ACCEL * delta)
	ctrl.velocity.x = planar.x
	ctrl.velocity.z = planar.z
	return PlayerStateMachine.KEEP


## Release routing: lock kept = LockOn (souls rule), moving = Locomotion,
## still = Idle.
func _release() -> int:
	if ctrl.lock_target != null and ctrl.lock_valid():
		return PlayerStateMachine.LOCKON
	if intent.move_raw() != Vector2.ZERO:
		return PlayerStateMachine.LOCOMOTION
	return PlayerStateMachine.IDLE
