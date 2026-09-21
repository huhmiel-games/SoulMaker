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
## Blade rebound (features/01): a blocked connect (shield / heavy armor,
## take_hit reports blocked) recoils the swing — native reverse playback of
## the clip from the impact position back to the clip start once the
## hitstop ends (the freeze masks the transition), then a frozen hold of
## the recoiled pose (souls beat), then a data-timed blend to idle. Sweep
## disarms at reversal start; killed wins over blocked.
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
## Blade rebound driver (real seconds — hitstop must not stretch the
## recoil): _rebound latches on a blocked connect, _hitstop_left counts
## down the freeze, then _reversing replays the clip backwards from the
## impact position, _holding freezes the recoiled pose for the souls beat,
## and _blending crossfades to idle over the data reblend time before
## _finish().
var _rebound := false
var _hitstop_left := 0.0
## Wall rebound latch: one wall recoil per swing (the sweep registry
## already dedupes bodies, this gates the rebound trigger itself).
var _wall_rebounded := false
var _reversing := false
var _holding := false
var _hold_t := 0.0
var _hold_dur := 0.0
var _blending := false
var _reblend_t := 0.0
var _reblend_dur := 0.0


func enter() -> void:
	_phase = 0
	_chained = false
	_rebound = false
	_hitstop_left = 0.0
	_wall_rebounded = false
	_reversing = false
	_holding = false
	_blending = false
	_hold_t = 0.0
	_reblend_t = 0.0
	# Single facing: nothing to realign — the body already looks where the
	# character looks (moving: the wish; still: keep-last). Locked swings
	# keep the enemy tracking in step().
	ctrl.anim_state = &"attack_light_1"
	_play_phase()
	print("[SM] Attack %s body=%.0f lock=%s" % [ctrl.attack_clip(), rad_to_deg(ctrl.rotation.y), str(ctrl.lock_target != null)])


func exit() -> void:
	print("[SM] Attack exit body=%.0f" % rad_to_deg(ctrl.rotation.y))
	ctrl.swing_end()
	ctrl.set_anim_speed(1.0)
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
	# The recoil plants the body — it reads from the shoulders, not the feet.
	var planar := Vector3(ctrl.velocity.x, 0.0, ctrl.velocity.z)
	if _phase == 1 and not _reversing and not _holding and not _blending:
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
	# The recoil disarms it (no re-connects on the way back).
	if _phase == 1 and not _instant and not _reversing and not _holding and not _blending:
		_section_t += delta
		if not _armed and _section_t >= _section_frac * _section_dur:
			_armed = true
			ctrl.swing_begin()
		if _armed:
			_poll_sweep()
	# Blade rebound driver (real time — see _start_reversal): the hitstop
	# masks the handover, then the section rewinds, holds the recoiled
	# pose, and blends to idle.
	if _rebound and not _reversing and not _holding and not _blending:
		_hitstop_left -= delta / maxf(Engine.time_scale, 0.001)
		if _hitstop_left <= 0.0:
			_start_reversal()
	if _reversing:
		# Native reverse runs to the clip start on its own (LOOP_NONE) —
		# when the player stops, the recoil pose is reached: hold it.
		var player := ctrl.anim_player()
		if player == null or not player.is_playing():
			_start_hold()
	elif _holding:
		_hold_t += delta / maxf(Engine.time_scale, 0.001)
		if _hold_t >= _hold_dur:
			_holding = false
			_start_reblend()
	elif _blending:
		_reblend_t += delta / maxf(Engine.time_scale, 0.001)
		if _reblend_t >= _reblend_dur:
			_blending = false
			_rebound = false
			return _finish()
	# Section advance: instant-skip, stopped player, or position past end.
	# Frozen through the recoil — the recovery owns the playback.
	var pos := ctrl.anim_pos()
	if not _reversing and not _holding and not _blending and (_instant or pos < 0.0 or pos >= ctrl.phase_end() - 0.02):
		if _phase == 1:
			ctrl.swing_end()
			print("[SM] Attack ACTIVE body=%.0f chained=%s" % [rad_to_deg(ctrl.rotation.y), str(_chained)])
		_phase += 1
		if _phase > 2:
			return _finish()
		_play_phase()
	return PlayerStateMachine.KEEP


## Connect loop, two passes. Enemies: every new take_hit carrier takes
## damage; the first connect of the swing fires the full chain (hitstop +
## shake + rumble + spark), later ones spark + damage only (spec:
## strongest once, never stacked). take_hit reports {killed, blocked} —
## a blocked connect that did not kill latches the blade rebound (recoil
## once hitstop ends); legacy bool carriers are read as killed-only.
## Blocked hits deal no damage. Walls (solid bodies without take_hit):
## a contact on the guard half of the blade (< WALL_REBOUND_RATIO)
## recoils the swing exactly like a blocked enemy; a contact on the tip
## half scrapes through with sparks only and the attack continues.
func _poll_sweep() -> void:
	var connects := ctrl.sweep_poll()
	if connects.is_empty():
		return
	var impact := ctrl.attack_impact()
	var damage := float(impact.get("damage", 10.0))
	var host := ctrl.impact_host()
	for c in connects:
		if bool(c.get("is_wall", false)):
			continue
		var body: Object = c["body"]
		var point: Vector3 = c["point"]
		var raw: Variant = body.call("take_hit", damage, ctrl.global_position)
		var result: Dictionary = raw if raw is Dictionary else {"killed": bool(raw), "blocked": false}
		var killed := bool(result.get("killed", false))
		var blocked := bool(result.get("blocked", false)) and not killed
		print("[SM] Attack connect %s dmg %.0f%s%s" % [body, 0.0 if blocked else damage, " KILL" if killed else "", " BLOCKED" if blocked else ""])
		if blocked and not _rebound:
			# Rebound trigger: the reversal starts when the freeze ends
			# (see step). Duration from the data so host-less scenes still
			# recoil, just unmasked.
			_rebound = true
			_hitstop_left = float(impact.get("hitstop_frames", 4)) / 60.0
		if host == null:
			continue
		if not _chained:
			_chained = true
			host.impact(point, int(impact.get("hitstop_frames", 4)), float(impact.get("shake_scale", 1.0)), ctrl.camera)
		else:
			host.spark_at(point)
	for c in connects:
		if not bool(c.get("is_wall", false)):
			continue
		var point: Vector3 = c["point"]
		if point.y < PlayerController.WALL_GROUND_Y:
			continue
		var ratio := ctrl.blade_contact_ratio(point)
		if ratio < PlayerController.WALL_REBOUND_RATIO and not _rebound and not _wall_rebounded:
			_wall_rebounded = true
			_rebound = true
			_hitstop_left = float(impact.get("hitstop_frames", 4)) / 60.0
			print("[SM] Attack wall rebound ratio %.2f" % ratio)
			if host != null and not _chained:
				_chained = true
				host.impact(point, int(impact.get("hitstop_frames", 4)), float(impact.get("shake_scale", 1.0)), ctrl.camera)
		elif host != null:
			# Scrape: sparks only, the attack continues normally (no
			# hitstop, no chain consumption).
			print("[SM] Attack wall scrape ratio %.2f" % ratio)
			host.spark_at(point)


## Reversal start: capture the impact position and replay the clip
## backwards to the clip start at the data speed (native
## play_section_backwards). The sweep is already spent (no re-connects);
## the section-advance freeze holds until the recovery blends out.
## NOTE (future tuning): the reverse duration is emergent — from / speed —
## so an early connect recoils short and a late one recoils long. Keep it
## (DS3-like timing feel) unless a fixed-length recoil is wanted; in that
## case renormalize here: speed = from / TARGET_REVERSE_DUR.
func _start_reversal() -> void:
	var rb: Dictionary = ctrl.attack_phases().get("rebound", {})
	var speed := maxf(float(rb.get("speed", 3.0)), 0.5)
	_hold_dur = maxf(float(rb.get("hold_time", 0.15)), 0.0)
	_reblend_dur = maxf(float(rb.get("reblend_time", 0.15)), 0.05)
	_reversing = true
	_armed = false
	ctrl.swing_end()
	var from := ctrl.anim_pos()
	if from < 0.0:
		from = ctrl.phase_end()
	ctrl.play_reverse(ctrl.attack_clip(), from, speed)
	print("[SM] Attack rebound reverse from %.2f x%.1f" % [from, speed])


## Souls beat: freeze the recoiled pose so the stop reads before the
## recovery blend. The player stays frozen (speed 0) — no seek drift.
func _start_hold() -> void:
	_reversing = false
	_holding = true
	_hold_t = 0.0
	print("[SM] Attack hold %.2fs" % _hold_dur)


## Recovery blend: restore forward speed and crossfade to idle over the
## data reblend time; _finish() fires when the blend completes.
func _start_reblend() -> void:
	_reversing = false
	ctrl.set_anim_speed(1.0)
	_reblend_t = 0.0
	_blending = true
	ctrl.play_slot_blend(&"idle", _reblend_dur)
	print("[SM] Attack reblend %.2fs" % _reblend_dur)


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
	# Guard still held through the swing = back behind the shield (souls).
	if ctrl.guard_wanted() and ctrl.is_on_floor():
		return PlayerStateMachine.GUARD
	if ctrl.lock_target != null and ctrl.lock_valid():
		return PlayerStateMachine.LOCKON
	if intent.move_raw() != Vector2.ZERO:
		return PlayerStateMachine.LOCOMOTION
	return PlayerStateMachine.IDLE
