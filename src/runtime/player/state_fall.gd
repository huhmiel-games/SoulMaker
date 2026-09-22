class_name StateFall
extends PlayerState

## Airborne past the grace time (walked off an edge — no jump in step 1):
## momentum preserved with a light decay. Captures fall_start_y on enter so
## the landing knows the real drop (S4 plunge + fall damage). An attack
## pressed mid-fall buffers a plunge (plunge_wanted — the player commits, no
## auto-trigger): while free, the commit adopts the enemy below as a fake
## lock (silent — no marker; body tracks through the fall),
## already locked = untouched. Landing: buffered + drop >= min_drop =
## Plunge; else fall damage when drop > threshold (lethal = HURT); else
## Idle/Locomotion by input presence (old Fall landing rule, lock kept).
## The fake lock is always released on landing (free play never gains a
## surprise real lock).
func enter() -> void:
	ctrl.anim_state = &"fall"
	# Measured from the last grounded height (fix 22/09): the air-grace in
	# the grounded states expires mid-fall, so the enter-time height already
	# lost meters of the real drop.
	ctrl.fall_start_y = ctrl.last_ground_y
	ctrl.plunge_wanted = false


func step(delta: float) -> int:
	ctrl.velocity.y -= PlayerController.GRAVITY * delta
	var planar := Vector3(ctrl.velocity.x, 0.0, ctrl.velocity.z)
	planar = planar.move_toward(Vector3.ZERO, planar.length() * 0.25 * delta)
	ctrl.velocity.x = planar.x
	ctrl.velocity.z = planar.z
	# Plunge commit: attack buffered mid-fall (existing attack_light action —
	# no new input, audit untouched). Fires mid-air once the real drop
	# clears min_drop, so the dive itself reads (not an instant landing).
	if intent.attack_light_pressed():
		ctrl.plunge_wanted = true
		ctrl.acquire_plunge_lock()
		print("[SM] Fall plunge buffered")
	# Fake-lock revalidation (target died or left the column) + tracking
	# through the fall (real or fake — the dive starts aligned).
	ctrl.validate_plunge_lock()
	if ctrl.lock_target != null:
		ctrl.track_lock_target(delta)
	var pl: Dictionary = ctrl.mobility_cfg.get("plunge", {})
	if ctrl.plunge_wanted and (ctrl.fall_start_y - ctrl.global_position.y) >= float(pl.get("min_drop", 2.0)):
		ctrl.plunge_wanted = false
		return PlayerStateMachine.PLUNGE
	if ctrl.is_on_floor():
		var drop := maxf(ctrl.fall_start_y - ctrl.global_position.y, 0.0)
		ctrl.last_fall_drop = drop
		ctrl.velocity.y = -0.5
		ctrl.plunge_wanted = false
		ctrl.release_plunge_lock()
		var dealt := ctrl.take_fall_damage(drop)
		if ctrl.dead:
			# Temp lock already released above (same check-then-release
			# race as the Plunge->LockOn crash 22/09 — HURT must never
			# inherit a fake lock into its LockOn exit).
			return PlayerStateMachine.HURT
		if dealt > 0.0:
			print("[SM] Fall hard landing %.1fm" % drop)
		# Lock survives accidental edge falls: still valid = back to LockOn.
		if ctrl.lock_target != null and ctrl.lock_valid():
			return PlayerStateMachine.LOCKON
		if intent.move_raw() != Vector2.ZERO:
			return PlayerStateMachine.LOCOMOTION
		return PlayerStateMachine.IDLE
	return PlayerStateMachine.KEEP
