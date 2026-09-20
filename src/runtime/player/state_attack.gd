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


func enter() -> void:
	_phase = 0
	ctrl.anim_state = &"attack_light_1"
	_play_phase()
	print("[SM] Attack %s" % ctrl.attack_clip())


func exit() -> void:
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
	# Section advance: instant-skip, stopped player, or position past end.
	var pos := ctrl.anim_pos()
	if _instant or pos < 0.0 or pos >= ctrl.phase_end() - 0.02:
		if _phase == 1:
			print("[SM] Attack ACTIVE (hitbox hook)")
		_phase += 1
		if _phase > 2:
			return _finish()
		_play_phase()
	return PlayerStateMachine.KEEP


func _play_phase() -> void:
	var phases := ctrl.attack_phases()
	var clip := ctrl.attack_clip()
	var start := ctrl.marker_time(clip, SECTIONS[_phase])
	var end := ctrl.marker_time(clip, SECTIONS[_phase + 1])
	_instant = end - start < MIN_SECTION
	if not _instant:
		ctrl.play_phase(clip, SECTIONS[_phase], SECTIONS[_phase + 1], float(phases.get(SPEEDS[_phase], 1.0)))


func _finish() -> int:
	if ctrl.lock_target != null and ctrl.lock_valid():
		return PlayerStateMachine.LOCKON
	if intent.move_raw() != Vector2.ZERO:
		return PlayerStateMachine.LOCOMOTION
	return PlayerStateMachine.IDLE
