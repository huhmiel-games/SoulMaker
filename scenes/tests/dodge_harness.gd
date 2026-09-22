extends Node

## S4 deterministic mobility bot (P3, features/17 equip-load/backstep/
## plunge): drives controller tier helpers + soldier.take_plunge directly —
## no AI timing variance, fully synchronous, so every assert is exact.
## Covers: tier resolution + boundaries + live swap, roll params per tier,
## costs (roll flat, backstep scaled), stamina gate, ROLL/BACKSTEP/PLUNGE
## enterable, plunge damage scale/cap/min, take_plunge (bypass shield,
## knockback, lethal, DEAD ignored), fall damage bounds + application.
## Prints PASS/FAIL per step plus a summary line, then quits (headless).
## Run: Godot --headless --path . scenes/tests/dodge_harness.tscn
var _fails := 0


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _run()
	print("[Harness] dodge S4: %d FAIL" % _fails)
	get_tree().quit()


func _check(name: String, cond: bool, detail: String) -> void:
	if cond:
		print("[Harness] PASS %s (%s)" % [name, detail])
	else:
		_fails += 1
		print("[Harness] FAIL %s (%s)" % [name, detail])


func _run() -> void:
	var soldier := get_tree().get_first_node_in_group("dodge_dummy") as SoldierEnemy
	if soldier == null:
		_check("harness boot", false, "no soldier in group")
		return
	_check("harness boot", true, "soldier found")
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		_check("player boot", false, "no player in group")
		return
	_check("player boot", true, "weapon %s" % player.weapon_id)

	# 1. Tier resolution + boundaries + live swap.
	player.equip_load_ratio = 0.2
	_check("tier fast", player.roll_tier() == &"fast", str(player.roll_tier()))
	player.equip_load_ratio = 0.5
	_check("tier mid", player.roll_tier() == &"mid", str(player.roll_tier()))
	player.equip_load_ratio = 0.8
	_check("tier fat", player.roll_tier() == &"fat", str(player.roll_tier()))
	player.equip_load_ratio = 0.29
	_check("bound fast", player.roll_tier() == &"fast", str(player.roll_tier()))
	player.equip_load_ratio = 0.30
	_check("bound mid-lo", player.roll_tier() == &"mid", str(player.roll_tier()))
	player.equip_load_ratio = 0.69
	_check("bound mid-hi", player.roll_tier() == &"mid", str(player.roll_tier()))
	player.equip_load_ratio = 0.70
	_check("bound fat", player.roll_tier() == &"fat", str(player.roll_tier()))
	player.equip_load_ratio = 0.2
	_check("live swap", player.roll_tier() == &"fast", str(player.roll_tier()))

	# 2. Roll params per tier (fix 22/09: fast 6.0 m, mid recovery 0.08).
	player.equip_load_ratio = 0.2
	var fast := player.roll_params()
	_check("fast params", is_equal_approx(float(fast.get("iframes", -1.0)), 0.5) and is_equal_approx(float(fast.get("distance", -1.0)), 6.0) and is_equal_approx(float(fast.get("recovery_bonus", -1.0)), 0.0), str(fast))
	player.equip_load_ratio = 0.5
	var mid := player.roll_params()
	_check("mid params", is_equal_approx(float(mid.get("iframes", -1.0)), 0.4) and is_equal_approx(float(mid.get("distance", -1.0)), 4.0) and is_equal_approx(float(mid.get("recovery_bonus", -1.0)), 0.08), str(mid))
	player.equip_load_ratio = 0.8
	var fat := player.roll_params()
	_check("fat params", is_equal_approx(float(fat.get("iframes", -1.0)), 0.25) and is_equal_approx(float(fat.get("distance", -1.0)), 3.0) and is_equal_approx(float(fat.get("recovery_bonus", -1.0)), 0.3), str(fat))

	# 3. Costs: roll flat 25, backstep 15/18/22.
	player.equip_load_ratio = 0.2
	_check("roll flat fast", is_equal_approx(player.roll_cost(), 25.0), "%.1f" % player.roll_cost())
	_check("backstep fast", is_equal_approx(player.backstep_cost(), 15.0), "%.1f" % player.backstep_cost())
	player.equip_load_ratio = 0.5
	_check("roll flat mid", is_equal_approx(player.roll_cost(), 25.0), "%.1f" % player.roll_cost())
	_check("backstep mid", is_equal_approx(player.backstep_cost(), 18.0), "%.1f" % player.backstep_cost())
	player.equip_load_ratio = 0.8
	_check("backstep fat", is_equal_approx(player.backstep_cost(), 22.0), "%.1f" % player.backstep_cost())
	player.stamina = 100.0
	_check("stamina afford", player.spend_stamina(player.roll_cost()), "stam %.1f" % player.stamina)
	player.stamina = 10.0
	_check("stamina deny", not player.spend_stamina(player.roll_cost()), "stam %.1f" % player.stamina)
	player.stamina = 100.0

	# 4. States enterable.
	player.machine.start(PlayerStateMachine.ROLL)
	_check("roll enters", player.machine.state_name() == "Roll", player.machine.state_name())
	player.machine.start(PlayerStateMachine.BACKSTEP)
	_check("backstep enters", player.machine.state_name() == "Backstep", player.machine.state_name())
	player.machine.start(PlayerStateMachine.PLUNGE)
	_check("plunge enters", player.machine.state_name() == "Plunge", player.machine.state_name())
	player.machine.start(PlayerStateMachine.IDLE)

	# 5. Plunge damage: base 10 (light sword) + 8/m over 2 m, cap 40.
	_check("plunge below min", is_equal_approx(player.compute_plunge_damage(1.9), 0.0), "%.1f" % player.compute_plunge_damage(1.9))
	_check("plunge scaled", is_equal_approx(player.compute_plunge_damage(3.0), 18.0), "%.1f" % player.compute_plunge_damage(3.0))
	_check("plunge capped", is_equal_approx(player.compute_plunge_damage(10.0), 40.0), "%.1f" % player.compute_plunge_damage(10.0))

	# 6. take_plunge: bypasses the frontal shield, knockback, never blocked.
	soldier.hp = 60.0
	soldier.poise = 30.0
	soldier.state = SoldierEnemy.IDLE
	var from := soldier.global_position + Vector3(0.0, 3.0, -1.0)
	var before: Vector3 = soldier.global_position
	var res: Dictionary = soldier.take_plunge(18.0, 1.5, from)
	_check("plunge bypass", bool(res.get("plunged", false)) and not bool(res.get("blocked", false)), str(res))
	_check("plunge cost", is_equal_approx(soldier.hp, 42.0), "hp %.1f" % soldier.hp)
	_check("plunge knockback", (soldier.global_position - before).length() > 0.5, "moved %.2f" % (soldier.global_position - before).length())
	soldier.hp = 5.0
	soldier.poise = 30.0
	soldier.state = SoldierEnemy.IDLE
	res = soldier.take_plunge(18.0, 1.5, from)
	_check("plunge lethal", bool(res.get("killed", false)), str(res))
	soldier.hp = 0.0
	soldier.state = SoldierEnemy.DEAD
	res = soldier.take_plunge(18.0, 1.5, from)
	_check("plunge dead ignored", not bool(res.get("plunged", false)) and not bool(res.get("killed", false)), str(res))

	# 7. Fall damage: none at/below 5 m, 15/m above, cap 50.
	_check("fall none", is_equal_approx(player.compute_fall_damage(4.9), 0.0), "%.1f" % player.compute_fall_damage(4.9))
	_check("fall edge", is_equal_approx(player.compute_fall_damage(5.0), 0.0), "%.1f" % player.compute_fall_damage(5.0))
	_check("fall scaled", is_equal_approx(player.compute_fall_damage(6.0), 15.0), "%.1f" % player.compute_fall_damage(6.0))
	_check("fall capped", is_equal_approx(player.compute_fall_damage(10.0), 50.0), "%.1f" % player.compute_fall_damage(10.0))
	player.hp = 100.0
	player.dead = false
	var dealt := player.take_fall_damage(6.0)
	_check("fall applied", is_equal_approx(dealt, 15.0) and is_equal_approx(player.hp, 85.0), "dealt %.1f hp %.1f" % [dealt, player.hp])

	# 8. Mobility data present (thresholds base-owned).
	var mob := MobilityConfig.merged()
	_check("mobility data", is_equal_approx(float((mob.get("thresholds", {}) as Dictionary).get("fast_max", -1.0)), 0.3), str(mob.get("thresholds", {})))

	# 9. Fix 22/09: fat thud timing variable + Fall measures from last
	# grounded height (enter-time height already lost meters of the drop).
	_check("fat thud var", is_equal_approx(PlayerController.FAT_THUD_TIME, 0.45), "%.2f" % PlayerController.FAT_THUD_TIME)
	player.last_ground_y = 6.0
	var probe := StateFall.new()
	probe.setup(player, player.intent)
	probe.enter()
	_check("fall from ground", is_equal_approx(player.fall_start_y, 6.0), "%.1f" % player.fall_start_y)

	# 10. Plunge forgiveness: fake-lock below regardless of facing (180°),
	# weapon-sized reach (min 1.5), PlungeCast connect, temp-lock restore.
	# Full reset first (section 6 killed the dummy: tipped over + collision
	# disabled — manual hp/state pokes cannot revive that).
	soldier._reset()
	var home: Vector3 = soldier.global_position
	player.global_position = home + Vector3(0.0, 4.0, 0.5)
	player.last_ground_y = player.global_position.y
	player.rotation.y = PI # back to the soldier (180°)
	player.lock_target = null
	player.plunge_temp_lock = false
	_check("forgive acquire", player.acquire_plunge_lock() and player.lock_target == soldier, "lock %s" % str(player.lock_target))
	_check("temp flag", player.plunge_temp_lock, "temp=%s" % str(player.plunge_temp_lock))
	var marker := soldier.get_node_or_null("LockMarker") as Node3D
	_check("temp silent", marker != null and not marker.visible, "marker hidden")
	soldier.global_position = home + Vector3(5.0, 0.0, 0.0)
	player.release_plunge_lock()
	_check("no acquire far", not player.acquire_plunge_lock(), "reach %.1f" % player.plunge_reach())
	soldier.global_position = home
	player._blade_length = 3.0
	_check("reach weapon", is_equal_approx(player.plunge_reach(), 3.0), "%.1f" % player.plunge_reach())
	player._blade_length = 1.05
	_check("reach min", is_equal_approx(player.plunge_reach(), 1.5), "%.1f" % player.plunge_reach())
	# Cast connect through the state path, still facing away.
	player.global_position = home + Vector3(0.0, 1.5, 0.8)
	player.rotation.y = PI
	player.lock_target = null
	player.plunge_temp_lock = false
	soldier.hp = 60.0
	soldier.poise = 30.0
	soldier.state = SoldierEnemy.IDLE
	player.fall_start_y = player.global_position.y + 3.0
	_check("forgive reacquire", player.acquire_plunge_lock(), "lock %s" % str(player.lock_target))
	player.plunge_begin()
	var pst := StatePlunge.new()
	pst.setup(player, player.intent)
	pst._poll_sweep()
	_check("cast connect", is_equal_approx(soldier.hp, 42.0), "hp %.1f" % soldier.hp)
	player.plunge_end()
	player.release_plunge_lock()
	_check("temp released", player.lock_target == null and not player.plunge_temp_lock, "lock=%s temp=%s" % [str(player.lock_target), str(player.plunge_temp_lock)])

	# 11. Crash 22/09: a fake lock must never route LockOn (exit releases
	# it before the next enter — free dives land free).
	player.global_position = home + Vector3(0.0, 1.5, 0.8)
	player.lock_target = null
	player.plunge_temp_lock = false
	soldier.global_position = home
	soldier.state = SoldierEnemy.IDLE
	_check("temp reacquire", player.acquire_plunge_lock(), "lock %s" % str(player.lock_target))
	var fin := StatePlunge.new()
	fin.setup(player, player.intent)
	_check("no lockon on temp", fin._finish() == PlayerStateMachine.IDLE, PlayerStateMachine.NAMES.get(fin._finish(), "?"))
	player.release_plunge_lock()

	# 12. LAND reception (S4 close-out, land_hard = hard landing): slot
	# resolves, duration = clip length, Fall routes LAND on damaging drops
	# (lethal still HURT), the state holds the full clip then exits.
	_check("land slot", str(player._clips.get(&"land_hard", &"")) == "rig/adventure__hard landing", str(player._clips.get(&"land_hard", &"")))
	_check("land duration", absf(player.land_duration() - 1.88) < 0.05, "%.2f" % player.land_duration())
	player.lock_target = null
	# Grounded: the section 10-11 teleports left the body airborne, and an
	# airborne Idle re-falls within frames (grace/falling_fast).
	player.global_position = Vector3(0.0, 0.1, 20.0)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.machine.start(PlayerStateMachine.LAND)
	_check("land enters", player.machine.state_name() == "Land", player.machine.state_name())
	var land := StateLand.new()
	land.setup(player, player.intent)
	land.enter()
	_check("land holds", land.step(0.5) == PlayerStateMachine.KEEP, PlayerStateMachine.NAMES.get(land.step(0.0), "?"))
	# Contact entry through the integrated path: the clip starts at the
	# contact frame (airborne intro skipped) and exits to IDLE at its end.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var land_pos := player._player.current_animation_position
	_check("land seeks contact", absf(land_pos - 0.1542) < 0.3, "pos %.3f" % land_pos)
	player._player.seek(2.0, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("land exits idle", player.machine.state_name() == "Idle", player.machine.state_name())
	player.machine.start(PlayerStateMachine.IDLE)
	# Real 6 m landing through the Fall path (drop from the sky, wait for
	# the machine — floor state only exists across physics frames).
	player.hp = 100.0
	player.dead = false
	player.lock_target = null
	player.plunge_wanted = false
	player.global_position = Vector3(0.0, 6.5, 20.0)
	player.velocity = Vector3.ZERO
	player.last_ground_y = 6.5
	player.machine.start(PlayerStateMachine.FALL)
	for i in 120:
		await get_tree().physics_frame
		if player.machine.state_name() == "Land":
			break
	_check("fall routes land", player.machine.state_name() == "Land", "%s hp %.0f" % [player.machine.state_name(), player.hp])
	# Lethal landing still routes HURT (last — leaves the dummy dead).
	player.hp = 5.0
	player.dead = false
	player.lock_target = null
	player.plunge_wanted = false
	player.global_position = Vector3(0.0, 6.5, 20.0)
	player.velocity = Vector3.ZERO
	player.last_ground_y = 6.5
	player.machine.start(PlayerStateMachine.FALL)
	for i in 120:
		await get_tree().physics_frame
		if player.machine.state_name() == "Hurt":
			break
	_check("fall lethal hurt", player.machine.state_name() == "Hurt", player.machine.state_name())
