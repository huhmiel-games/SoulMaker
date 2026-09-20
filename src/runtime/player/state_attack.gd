class_name StateAttack
extends PlayerState

## Light single swing (P2): three marker sections played at their data
## speeds (windup → attack → release) via controller.play_phase. Committed
## from the press (souls rule — no dodge-cancel, not even in windup): only
## enemy hits break it, through poise (05/17, arrives with the enemy
## archetype). Attack section carries forward (hitbox hook logs here for the
## ShapeCast step); release runs out to the buffered state. Stamina prepaid
## by the caller. Grounded only. Locked: facing + camera keep tracking;
## free: heading frozen like a roll. Missing clip = instant finish.
const SECTIONS := [&"windup_start", &"attack_start", &"release_start", &"anim_end"]
const SPEEDS := ["windup_speed", "attack_speed", "release_speed"]
## Sections shorter than this are skipped WITHOUT calling the native section
## player (degenerate 0-length sections behave undefinedly there and caused
## the R1 drift-then-late-swing bug on placeholder markers).
const MIN_SECTION := 0.05

var _phase := 0
var _instant := false
## Chain fired this swing (strongest-once: first connect triggers hitstop +
## trauma + rumble; later connects on the same swing only spark + damage).
var _chained := false
## Delayed sweep arming (bug 2 fix): the blade travels down first — the
## sweep arms sweep_start into the attack section, not on its first frame.
## _section_t runs in scaled time (the sweep follows the anim, hitstop
## included); durations are clip seconds / play speed.
var _section_t := 0.0
var _section_dur := 0.0
var _section_frac := 0.4
var _armed := false


func enter() -> void:
	_phase = 0
	_chained = false
	# Single facing: nothing to realign — the body already looks where the
	# character looks (moving: the wish; still: keep-last). Locked swings
	# keep the enemy tracking in step().
	ctrl.anim_state = &"attack_light_1"
	_play_phase()
	print("[SM] Attack %s body=%.0f lock=%s" % [ctrl.attack_clip(), rad_to_deg(ctrl.rotation.y), str(ctrl.lock_target != null)])


func exit() -> void:
	print("[SM] Attack exit body=%.0f" % rad_to_deg(ctrl.rotation.y))
	ctrl.swing_end()
	ctrl.anim_manual = false


func step(delta: float) -> int:
	if ctrl.is_on_floor():
		if ctrl.velocity.y < 0.0:
			ctrl.velocity.y = -0.5
	else:
		ctrl.velocity.y -= PlayerController.GRAVITY * delta
	if ctrl.lock_target != null:
		ctrl.track_lock_target(delta)
	# Displacement: planted windup/release, forward step through attack.
	var planar := Vector3(ctrl.velocity.x, 0.0, ctrl.velocity.z)
	if _phase == 1:
		var b := ctrl.global_transform.basis
		var fwd := -b.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3(0.0, 0.0, -1.0)
		ctrl.velocity.x = fwd.x * PlayerController.ATTACK_STEP
		ctrl.velocity.z = fwd.z * PlayerController.ATTACK_STEP
	else:
		planar = planar.move_toward(Vector3.ZERO, PlayerController.DECEL * delta)
		ctrl.velocity.x = planar.x
		ctrl.velocity.z = planar.z
	# Sweep connects only during the attack section, armed with a delay
	# (blade travel). Poll runs once armed; disabled sweep polls empty.
	if _phase == 1 and not _instant:
		_section_t += delta
		if not _armed and _section_t >= _section_frac * _section_dur:
			_armed = true
			ctrl.swing_begin()
		if _armed:
			_poll_sweep()
	# Section advance: instant-skip, stopped player, or position past end.
	var pos := ctrl.anim_pos()
	if _instant or pos < 0.0 or pos >= ctrl.phase_end() - 0.02:
		if _phase == 1:
			ctrl.swing_end()
			print("[SM] Attack ACTIVE body=%.0f chained=%s" % [rad_to_deg(ctrl.rotation.y), str(_chained)])
		_phase += 1
		if _phase > 2:
			return _finish()
		_play_phase()
	return PlayerStateMachine.KEEP


## Connect loop: every new take_hit carrier takes damage; the first connect
## of the swing fires the full chain (hitstop + shake + rumble + spark),
## later ones spark + damage only (spec: strongest once, never stacked).
func _poll_sweep() -> void:
	var connects := ctrl.sweep_poll()
	if connects.is_empty():
		return
	var impact := ctrl.attack_impact()
	var damage := float(impact.get("damage", 10.0))
	var host := ctrl.impact_host()
	for c in connects:
		var body: Object = c["body"]
		var point: Vector3 = c["point"]
		var killed := bool(body.call("take_hit", damage, ctrl.global_position))
		print("[SM] Attack connect %s dmg %.0f%s" % [body, damage, " KILL" if killed else ""])
		if host == null:
			continue
		if not _chained:
			_chained = true
			host.impact(point, int(impact.get("hitstop_frames", 4)), float(impact.get("shake_scale", 1.0)), ctrl.camera)
		else:
			host.spark_at(point)


func _play_phase() -> void:
	var phases := ctrl.attack_phases()
	var clip := ctrl.attack_clip()
	var start := ctrl.marker_time(clip, SECTIONS[_phase])
	var end := ctrl.marker_time(clip, SECTIONS[_phase + 1])
	_instant = end - start < MIN_SECTION
	if not _instant:
		var speed := float(phases.get(SPEEDS[_phase], 1.0))
		ctrl.play_phase(clip, SECTIONS[_phase], SECTIONS[_phase + 1], speed)
	if _phase == 1:
		_section_t = 0.0
		_armed = false
		_section_frac = clampf(float(phases.get("sweep_start", 0.4)), 0.0, 0.9)
		_section_dur = (end - start) / maxf(float(phases.get(SPEEDS[_phase], 1.0)), 0.01)


func _finish() -> int:
	if ctrl.lock_target != null and ctrl.lock_valid():
		return PlayerStateMachine.LOCKON
	if intent.move_raw() != Vector2.ZERO:
		return PlayerStateMachine.LOCOMOTION
	return PlayerStateMachine.IDLE
