class_name StateLand
extends PlayerState

## Hard landing reception (P3 S4 close-out): entered only from StateFall when
## the landing dealt fall damage (> 0 and non-lethal — lethal routes HURT).
## Committed: the land_hard clip plays from its contact frame (airborne intro
## skipped via anim_seek, snap blend) to the end. Exit is clip-position
## based (seek-aware), routing mirrors Hurt: guard still held = GUARD, valid
## lock = LOCKON, input = LOCOMOTION, else IDLE.
var _t := 0.0


func enter() -> void:
	_t = 0.0
	ctrl.anim_state = &"land_hard"
	ctrl.anim_seek = ctrl.land_contact
	ctrl.anim_blend = PlayerController.LAND_ENTER_BLEND
	print("[SM] Land seek %.3fs len %.2fs" % [ctrl.land_contact, ctrl.land_duration()])


func step(delta: float) -> int:
	_t += delta
	if ctrl.is_on_floor():
		if ctrl.velocity.y < 0.0:
			ctrl.velocity.y = -0.5
	else:
		ctrl.velocity.y -= PlayerController.GRAVITY * delta
	# Landing plants the body: damp the inherited displacement to zero.
	var planar := Vector3(ctrl.velocity.x, 0.0, ctrl.velocity.z)
	planar = planar.move_toward(Vector3.ZERO, PlayerController.DECEL * delta)
	ctrl.velocity.x = planar.x
	ctrl.velocity.z = planar.z
	if ctrl.land_finished() or _t >= ctrl.land_duration() + 0.5:
		if ctrl.guard_wanted():
			return PlayerStateMachine.GUARD
		if ctrl.lock_target != null and ctrl.lock_valid():
			return PlayerStateMachine.LOCKON
		if intent.move_raw() != Vector2.ZERO:
			return PlayerStateMachine.LOCOMOTION
		return PlayerStateMachine.IDLE
	return PlayerStateMachine.KEEP
