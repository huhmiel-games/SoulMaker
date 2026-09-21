class_name StateHurt
extends PlayerState

## Hit flinch (P2 minimal + P3 S1 guard break — hyper-armor/stance are P7/V2
## per features/17): entered only via take_hit (poise break, guard break or
## death). The only interruption a committed attack knows (souls rule, 05) —
## take_hit forces the transition, so step only times the flinch and routes
## the exit. Duration = controller hurt_duration() (guard break stretches it
## via the one-shot override, consumed in exit). No hurt clip on the rig:
## anim_state &"hurt" is unresolved, _resolve_anim keeps the current anim
## (never T-poses). Dead: HURT holds until the controller respawns
## (machine.start(IDLE)).
var _t := 0.0


func enter() -> void:
	_t = 0.0
	ctrl.anim_state = &"hurt"
	ctrl.anim_seek = -1.0
	print("[SM] Hurt hp %.0f%s%s" % [ctrl.hp, " DEAD" if ctrl.dead else "", " BREAK" if ctrl.hurt_time_override >= 0.0 else ""])


func exit() -> void:
	ctrl.hurt_time_override = -1.0


func step(delta: float) -> int:
	_t += delta
	if ctrl.is_on_floor():
		if ctrl.velocity.y < 0.0:
			ctrl.velocity.y = -0.5
	else:
		ctrl.velocity.y -= PlayerController.GRAVITY * delta
	# Flinch plants the body: damp the inherited displacement to zero.
	var planar := Vector3(ctrl.velocity.x, 0.0, ctrl.velocity.z)
	planar = planar.move_toward(Vector3.ZERO, PlayerController.DECEL * delta)
	ctrl.velocity.x = planar.x
	ctrl.velocity.z = planar.z
	if ctrl.dead:
		return PlayerStateMachine.KEEP
	if _t >= ctrl.hurt_duration():
		# Guard still held through the flinch = back behind the shield
		# (except after a guard break — re-press to re-raise, guard_wanted).
		if ctrl.guard_wanted():
			return PlayerStateMachine.GUARD
		# Lock survives the flinch (souls rule): still valid = LockOn,
		# otherwise the free exit routing.
		if ctrl.lock_target != null and ctrl.lock_valid():
			return PlayerStateMachine.LOCKON
		if intent.move_raw() != Vector2.ZERO:
			return PlayerStateMachine.LOCOMOTION
		return PlayerStateMachine.IDLE
	return PlayerStateMachine.KEEP
	if _t >= PlayerController.HURT_TIME:
		# Lock survives the flinch (souls rule): still valid = LockOn,
		# otherwise the free exit routing.
		if ctrl.lock_target != null and ctrl.lock_valid():
			return PlayerStateMachine.LOCKON
		if intent.move_raw() != Vector2.ZERO:
			return PlayerStateMachine.LOCOMOTION
		return PlayerStateMachine.IDLE
	return PlayerStateMachine.KEEP
