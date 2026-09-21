class_name StateShove
extends PlayerState

## Blade shove (P3 S3, features/17 push/shove): the heavies' guard-break
## answer. Forward+attack with a push_move carrier: a short committed lunge
## with a brief sweep window, then the data recovery (punishable). Vs a
## raised block the shove cracks it (take_shove: chip + massive poise, no
## rebound); vs non-blockers it is near-useless (small damage + modest
## poise — spacing risk). Committed like an attack: only enemy hits break
## it, through poise. No dedicated anim yet (graybox) — reuses the attack
## clip; the juice (hitstop + shake + crack log) carries the read. Stamina
## prepaid by the caller. Grounded only. Locked: facing keeps tracking.

var _t := 0.0
var _armed := false
var _connected := false
var _recovery := 0.6
var _dir := Vector3.ZERO


func enter() -> void:
	_t = 0.0
	_armed = false
	_connected = false
	_recovery = maxf(float(ctrl.shove_move().get("recovery", 0.6)), 0.2)
	_dir = intent.wish_direction(intent.move_raw())
	ctrl.anim_state = &"attack_light_1"
	print("[SM] Shove %s recovery %.2f" % [str(ctrl.shove_move().get("type", "?")), _recovery])


func exit() -> void:
	print("[SM] Shove exit")
	ctrl.swing_end()


func step(delta: float) -> int:
	if ctrl.is_on_floor():
		if ctrl.velocity.y < 0.0:
			ctrl.velocity.y = -0.5
	else:
		ctrl.velocity.y -= PlayerController.GRAVITY * delta
	if ctrl.lock_target != null:
		ctrl.track_lock_target(delta)
	else:
		ctrl.turn_body_to(_dir, delta)
	# Committed lunge, decays over the recovery.
	var k := maxf(1.0 - _t / _recovery, 0.0)
	var b := ctrl.global_transform.basis
	var fwd := -b.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3(0.0, 0.0, -1.0)
	ctrl.velocity.x = fwd.x * PlayerController.SHOVE_STEP * k
	ctrl.velocity.z = fwd.z * PlayerController.SHOVE_STEP * k
	_t += delta
	# Sweep window: armed 0.15 s in, closed at 60% of the recovery.
	if not _armed and _t >= 0.15:
		_armed = true
		ctrl.swing_begin()
	if _armed and _t < _recovery * 0.6:
		_poll_sweep()
	elif _armed:
		ctrl.swing_end()
		_armed = false
	if _t >= _recovery:
		return _finish()
	return PlayerStateMachine.KEEP


## Shove connect: take_shove carriers (soldier) resolve the crack; legacy
## carriers take the small shove damage as a plain hit. First connect fires
## a light juice stack (short hitstop + shake + spark); later ones spark +
## damage only. No rebound ever — the shove is the anti-rebound tool.
func _poll_sweep() -> void:
	var connects := ctrl.sweep_poll()
	if connects.is_empty():
		return
	var pm := ctrl.shove_move()
	var damage := float(pm.get("damage", 4.0))
	var guard_break := float(pm.get("guard_break", 70.0))
	var host := ctrl.impact_host()
	for c in connects:
		if bool(c.get("is_wall", false)):
			continue
		var body: Object = c["body"]
		var point: Vector3 = c["point"]
		var raw: Variant
		if body.has_method("take_shove"):
			raw = body.call("take_shove", damage, guard_break, ctrl.global_position)
		else:
			raw = body.call("take_hit", damage, ctrl.global_position, 1.0)
		var result: Dictionary = raw if raw is Dictionary else {"killed": bool(raw), "blocked": false}
		var killed := bool(result.get("killed", false))
		var cracked := bool(result.get("cracked", false))
		print("[SM] Shove connect %s dmg %.0f%s%s" % [body, damage, " KILL" if killed else "", " CRACK" if cracked else ""])
		if host == null:
			continue
		if not _connected:
			_connected = true
			host.impact(point, 3, 0.8, ctrl.camera)
		else:
			host.spark_at(point)


func _finish() -> int:
	# Same exits as an attack: guard held = back behind the shield.
	if ctrl.guard_wanted() and ctrl.is_on_floor():
		return PlayerStateMachine.GUARD
	if ctrl.lock_target != null and ctrl.lock_valid():
		return PlayerStateMachine.LOCKON
	if intent.move_raw() != Vector2.ZERO:
		return PlayerStateMachine.LOCOMOTION
	return PlayerStateMachine.IDLE
