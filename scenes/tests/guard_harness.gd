extends Node

## S1 deterministic guard bot (P3, features/17 block/guard): drives
## player.take_hit directly — no AI timing variance, fully synchronous, so
## every assert is exact. Covers: frontal block (stamina cost + chip + poise
## untouched), guard break on the 4th hit (30 stamina x 1.0 vs 100 pool),
## rear bypass (outside block_arc), unguarded hit, chip-through-guard kill.
## Prints PASS/FAIL per step plus a summary line, then quits (headless).
## Run: Godot --headless --path . scenes/tests/guard_harness.tscn
var _fails := 0


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_run()
	print("[Harness] guard S1: %d FAIL" % _fails)
	get_tree().quit()


func _check(name: String, cond: bool, detail: String) -> void:
	if cond:
		print("[Harness] PASS %s (%s)" % [name, detail])
	else:
		_fails += 1
		print("[Harness] FAIL %s (%s)" % [name, detail])


func _run() -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		_check("harness boot", false, "no player in group")
		return
	_check("harness boot", true, "player found, guard %s" % str(player.guard_cfg.get("equipped_shield", "?")))
	# Face -Z (rotation.y = 0): frontal attacker at -Z, rear at +Z.
	player.global_position = Vector3.ZERO
	player.rotation.y = 0.0
	var front := Vector3(0.0, 0.0, -2.0)
	var rear := Vector3(0.0, 0.0, 2.0)

	# 1. Frontal block: stamina -30, chip 1.0 (medium absorb 0.9), poise kept.
	player.hp = 100.0
	player.stamina = 100.0
	player.poise = 50.0
	player.guard_hold_override = true
	player.machine.start(PlayerStateMachine.GUARD)
	var res: Dictionary = player.take_hit(10.0, 20.0, front, 30.0)
	_check("frontal block", bool(res.get("blocked", false)) and not bool(res.get("staggered", false)), str(res))
	_check("block cost", is_equal_approx(player.stamina, 70.0) and is_equal_approx(player.hp, 99.0), "stam %.1f hp %.1f" % [player.stamina, player.hp])
	_check("block spares poise", is_equal_approx(player.poise, 50.0), "poise %.1f" % player.poise)
	_check("block holds guard", player.is_guarding(), player.machine.state_name())

	# 2. Two more frontal hits = stamina 10, still guarding.
	for i in 2:
		player.take_hit(10.0, 20.0, front, 30.0)
	_check("drain to ten", is_equal_approx(player.stamina, 10.0) and player.is_guarding(), "stam %.1f %s" % [player.stamina, player.machine.state_name()])

	# 3. 4th hit exceeds the remaining pool = guard break (extended HURT).
	res = player.take_hit(10.0, 20.0, front, 30.0)
	_check("guard break", bool(res.get("broken", false)) and bool(res.get("staggered", false)), str(res))
	_check("break stretch", is_equal_approx(player.hurt_time_override, 1.2), "override %.2f" % player.hurt_time_override)
	_check("break holds regen", player._regen_wait > 0.5, "regen_wait %.2f" % player._regen_wait)
	# 3b. Forced drop: holding through the break must NOT re-raise.
	# Override off = held human input still down, but release_needed latches.
	player.guard_hold_override = false
	_check("break forces drop", player.guard_release_needed and not player.guard_wanted(), "release_needed=%s wanted=%s" % [str(player.guard_release_needed), str(player.guard_wanted())])
	player.guard_hold_override = true

	# 4. Rear bypass: outside the 75° frontal arc = full hit, poise damage.
	player.machine.start(PlayerStateMachine.GUARD)
	player.hp = 100.0
	player.stamina = 100.0
	player.poise = 50.0
	res = player.take_hit(10.0, 20.0, rear, 10.0)
	_check("rear bypass", not bool(res.get("blocked", false)), str(res))
	_check("rear full damage", is_equal_approx(player.hp, 90.0) and is_equal_approx(player.poise, 30.0), "hp %.1f poise %.1f" % [player.hp, player.poise])

	# 5. Unguarded frontal = full hit.
	player.guard_hold_override = false
	player.machine.start(PlayerStateMachine.IDLE)
	player.hp = 100.0
	player.poise = 50.0
	res = player.take_hit(10.0, 20.0, front, 10.0)
	_check("unguarded hit", not bool(res.get("blocked", false)) and is_equal_approx(player.hp, 90.0), str(res))

	# 6. Chip kills through the guard (souls: chip is real damage).
	player.guard_hold_override = true
	player.machine.start(PlayerStateMachine.GUARD)
	player.hp = 0.5
	player.stamina = 100.0
	res = player.take_hit(10.0, 20.0, front, 10.0)
	_check("chip kill", bool(res.get("killed", false)) and player.dead, str(res))
