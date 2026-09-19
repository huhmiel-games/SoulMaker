class_name StateFall
extends PlayerState

## Airborne past the grace time (walked off an edge — no jump in step 1):
## momentum preserved with a light decay, landing returns to Idle or
## Locomotion by input presence (old Fall landing rule).
func enter() -> void:
	ctrl.anim_state = &"fall"


func step(delta: float) -> int:
	ctrl.velocity.y -= PlayerController.GRAVITY * delta
	var planar := Vector3(ctrl.velocity.x, 0.0, ctrl.velocity.z)
	planar = planar.move_toward(Vector3.ZERO, planar.length() * 0.25 * delta)
	ctrl.velocity.x = planar.x
	ctrl.velocity.z = planar.z
	if ctrl.is_on_floor():
		if intent.move_raw() != Vector2.ZERO:
			return PlayerStateMachine.LOCOMOTION
		return PlayerStateMachine.IDLE
	return PlayerStateMachine.KEEP
