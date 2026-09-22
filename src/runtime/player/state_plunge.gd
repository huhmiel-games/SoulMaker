class_name StatePlunge
extends PlayerState

## Plunging attack (P3 S4, features/17): entered mid-fall once the buffered
## attack + the real drop clear min_drop. Committed dive (gravity + slight
## forward drive), PlungeCast armed, connects as take_plunge (soldier:
## bypasses the shield, knockback + FLINCH) with drop-scaled capped damage.
## Souls forgiveness: the cast is a generous body-riding box (weapon-sized
## reach, facing-independent 180° pardon — NOT the blade sweep), and a free
## commit adopts the enemy below as a fake lock (Fall tracks it, restored on
## landing). Landing with a connect = short hit recovery; landing clean =
## full miss recovery; both roll-cancelable past roll_cancel_at
## (stamina-gated). Miss = no damage, no fall damage either (the plunge IS
## the landing). Melee only. Stamina prepaid? No: the fall paid it — entry
## is free, the recovery is the cost.
## Graybox: reuses the attack clip; the juice (hitstop + shake + crack log)
## carries the read until the shared rig (P4).

var _t := 0.0
var _landed := false
var _land_t := 0.0
var _recovery := 0.9
var _connected := false
var _armed := false


func enter() -> void:
	_t = 0.0
	_landed = false
	_land_t = 0.0
	_connected = false
	_armed = false
	var pl: Dictionary = ctrl.mobility_cfg.get("plunge", {})
	_recovery = maxf(float(pl.get("miss_recovery", 0.9)), 0.2)
	ctrl.anim_state = &"attack_light_1"
	print("[SM] Plunge drop %.1fm" % (ctrl.fall_start_y - ctrl.global_position.y))


func exit() -> void:
	ctrl.plunge_end()
	ctrl.release_plunge_lock()
	ctrl.set_anim_speed(1.0)
	print("[SM] Plunge exit")


func step(delta: float) -> int:
	_t += delta
	var pl: Dictionary = ctrl.mobility_cfg.get("plunge", {})
	if not _landed:
		ctrl.velocity.y -= PlayerController.GRAVITY * delta
		# Slight forward drive (the dive commits toward the facing).
		var b := ctrl.global_transform.basis
		var fwd := -b.z
		fwd.y = 0.0
		if fwd.length_squared() > 0.0001:
			fwd = fwd.normalized()
			ctrl.velocity.x = lerpf(ctrl.velocity.x, fwd.x * 2.0, minf(delta * 3.0, 1.0))
			ctrl.velocity.z = lerpf(ctrl.velocity.z, fwd.z * 2.0, minf(delta * 3.0, 1.0))
		ctrl.validate_plunge_lock()
		if ctrl.lock_target != null:
			ctrl.track_lock_target(delta)
		if not _armed and _t >= 0.05:
			_armed = true
			ctrl.plunge_begin()
		if _armed:
			_poll_sweep()
		if ctrl.is_on_floor():
			_landed = true
			_land_t = 0.0
			ctrl.last_fall_drop = maxf(ctrl.fall_start_y - ctrl.global_position.y, 0.0)
			ctrl.velocity = Vector3.ZERO
			if _connected:
				_recovery = maxf(float(pl.get("hit_recovery", 0.4)), 0.2)
				print("[SM] Plunge LAND hit drop %.1fm" % ctrl.last_fall_drop)
			else:
				_recovery = maxf(float(pl.get("miss_recovery", 0.9)), 0.2)
				ctrl.plunge_end()
				_armed = false
				print("[SM] Plunge MISS drop %.1fm" % ctrl.last_fall_drop)
		return PlayerStateMachine.KEEP
	# Landed recovery: planted, roll-cancelable past the cancel point.
	_land_t += delta
	ctrl.velocity = Vector3.ZERO
	var raw := intent.move_raw()
	if _land_t >= float(pl.get("roll_cancel_at", 0.5)) and intent.dodge_pressed():
		if raw == Vector2.ZERO:
			if ctrl.spend_stamina(ctrl.backstep_cost()):
				return PlayerStateMachine.BACKSTEP
		elif ctrl.spend_stamina(ctrl.roll_cost()):
			return PlayerStateMachine.ROLL
	if _land_t >= _recovery:
		return _finish()
	return PlayerStateMachine.KEEP


## Plunge connect: the PlungeCast (generous body box, NOT the blade sweep)
## polls the fall column; take_plunge carriers (soldier) resolve the
## vertical crack, legacy carriers take the scaled damage as a plain hit.
## Walls skimmed mid-dive are skipped silently (no rebound on a plunge).
## First connect fires the juice stack (hitstop 5 + shake 1.2 + spark);
## later ones spark + damage only. Damage scales on the total drop at
## connect time, capped by data. Never rebounds.
func _poll_sweep() -> void:
	var connects := ctrl.plunge_poll()
	if connects.is_empty():
		return
	var pl: Dictionary = ctrl.mobility_cfg.get("plunge", {})
	var drop := maxf(ctrl.fall_start_y - ctrl.global_position.y, 0.0)
	var damage := ctrl.compute_plunge_damage(drop)
	if damage <= 0.0:
		return
	var knockback := float(pl.get("knockback", 1.5))
	var host := ctrl.impact_host()
	for c in connects:
		if bool(c.get("is_wall", false)):
			continue
		var body: Object = c["body"]
		var point: Vector3 = c["point"]
		var raw: Variant
		if body.has_method("take_plunge"):
			raw = body.call("take_plunge", damage, knockback, ctrl.global_position)
		else:
			raw = body.call("take_hit", damage, ctrl.global_position, 1.0)
		var result: Dictionary = raw if raw is Dictionary else {"killed": bool(raw), "blocked": false}
		var killed := bool(result.get("killed", false))
		print("[SM] Plunge connect %s dmg %.0f drop %.1f%s" % [str(body), damage, drop, " KILL" if killed else ""])
		if not _connected:
			_connected = true
			if host != null:
				host.impact(point, 5, 1.2, ctrl.camera)
		elif host != null:
			host.spark_at(point)


func _finish() -> int:
	# Same exits as an attack: guard held = back behind the shield.
	if ctrl.guard_wanted() and ctrl.is_on_floor():
		return PlayerStateMachine.GUARD
	# A fake plunge lock never routes to LockOn (crash 22/09: _finish saw
	# the temp lock, then exit() released it, then LockOn.enter() derefed
	# Nil — free dives land free; exit() stays the single release point).
	if ctrl.lock_target != null and not ctrl.plunge_temp_lock and ctrl.lock_valid():
		return PlayerStateMachine.LOCKON
	if intent.move_raw() != Vector2.ZERO:
		return PlayerStateMachine.LOCOMOTION
	return PlayerStateMachine.IDLE
