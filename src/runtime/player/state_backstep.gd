class_name StateBackstep
extends PlayerState

## Spacing hop (P2, features/17): neutral or backward dodge input becomes a
## quick rear hop — NOT a roll. No body rotation (the character keeps facing),
## no camera touch, NO i-frames (the roll stays the unique invuln tool).
## Cheap stamina, chains into run/dodge/attack on exit. Grounded only.
## The clip ("Jump Away", 2.67 s) idles ~0.8 s before the impulse — enter
## seeks past it (ctrl.anim_seek) so the hop reads on time.
var _t := 0.0
var _dir := Vector3.ZERO


func enter() -> void:
	_t = 0.0
	var b := ctrl.global_transform.basis
	_dir = b.z
	_dir.y = 0.0
	_dir = _dir.normalized() if _dir.length_squared() > 0.0001 else Vector3(0.0, 0.0, 1.0)
	ctrl.anim_state = &"backstep"
	ctrl.anim_seek = PlayerController.BACKSTEP_SEEK
	print("[SM] Backstep")


func step(delta: float) -> int:
	_t += delta
	if ctrl.is_on_floor():
		if ctrl.velocity.y < 0.0:
			ctrl.velocity.y = -0.5
	else:
		ctrl.velocity.y -= PlayerController.GRAVITY * delta
		if _t > 0.15:
			return PlayerStateMachine.FALL
	# Same tracking as Roll: locked backsteps keep facing + camera glued.
	ctrl.track_lock_target(delta)
	ctrl.velocity.x = _dir.x * PlayerController.BACKSTEP_SPEED
	ctrl.velocity.z = _dir.z * PlayerController.BACKSTEP_SPEED
	if _t >= PlayerController.BACKSTEP_TIME:
		# Same lock routing as Roll: still valid = back to LockOn.
		if ctrl.lock_target != null and ctrl.lock_valid():
			return PlayerStateMachine.LOCKON
		if intent.move_raw() != Vector2.ZERO:
			return PlayerStateMachine.LOCOMOTION
		return PlayerStateMachine.IDLE
	return PlayerStateMachine.KEEP
