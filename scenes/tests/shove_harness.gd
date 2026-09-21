extends Node

## S3 deterministic shove bot (P3, features/17 push/shove): drives
## soldier.take_shove directly with positioned attacker points — no AI timing
## variance, fully synchronous, so every assert is exact. Covers: frontal
## crack vs raised shield (chip + guard_break poise, FLINCH, no block),
## near-useless vs down guard (small damage + modest poise), DEAD ignored,
## weapon data (greatsword blade_shove vs light-sword none), default player
## carries no shove, SHOVE state enterable. Prints PASS/FAIL per step plus a
## summary line, then quits (headless).
## Run: Godot --headless --path . scenes/tests/shove_harness.tscn
var _fails := 0


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_run()
	print("[Harness] shove S3: %d FAIL" % _fails)
	get_tree().quit()


func _check(name: String, cond: bool, detail: String) -> void:
	if cond:
		print("[Harness] PASS %s (%s)" % [name, detail])
	else:
		_fails += 1
		print("[Harness] FAIL %s (%s)" % [name, detail])


func _run() -> void:
	var soldier := get_tree().get_first_node_in_group("shove_dummy") as SoldierEnemy
	if soldier == null:
		_check("harness boot", false, "no soldier in group")
		return
	_check("harness boot", true, "soldier found")
	# Soldier faces -Z (rotation.y = 0): frontal attacker at -Z.
	var front := soldier.global_position + Vector3(0.0, 0.0, -2.0)
	var rear := soldier.global_position + Vector3(0.0, 0.0, 2.0)

	# 1. Frontal + guard up (IDLE) = CRACK: chip 4, poise 70-break, FLINCH.
	soldier.hp = 60.0
	soldier.poise = 30.0
	soldier.state = SoldierEnemy.IDLE
	var res: Dictionary = soldier.take_shove(4.0, 70.0, front)
	_check("frontal crack", bool(res.get("cracked", false)) and not bool(res.get("blocked", false)), str(res))
	_check("crack cost", is_equal_approx(soldier.hp, 56.0), "hp %.1f" % soldier.hp)
	_check("crack flinch", soldier.state == SoldierEnemy.FLINCH and is_equal_approx(soldier.poise, 30.0), "state %s poise %.1f" % [SoldierEnemy.NAMES.get(soldier.state, "?"), soldier.poise])

	# 2. Guard down (RECOVER) rear = near-useless: 4 dmg + modest poise.
	soldier.hp = 60.0
	soldier.poise = 30.0
	soldier.state = SoldierEnemy.RECOVER
	res = soldier.take_shove(4.0, 70.0, rear)
	_check("no guard no crack", not bool(res.get("cracked", false)) and not bool(res.get("blocked", false)), str(res))
	_check("shove chip", is_equal_approx(soldier.hp, 56.0) and is_equal_approx(soldier.poise, 24.0), "hp %.1f poise %.1f" % [soldier.hp, soldier.poise])

	# 3. DEAD ignored.
	soldier.hp = 0.0
	soldier.state = SoldierEnemy.DEAD
	res = soldier.take_shove(4.0, 70.0, front)
	_check("dead ignored", not bool(res.get("cracked", false)) and not bool(res.get("killed", false)), str(res))

	# 4. Weapon data: greatsword carries blade_shove, fallback has none.
	var gs := WeaponConfig.merged("greatsword_test")
	_check("greatsword shove", str((gs.get("push_move", {}) as Dictionary).get("type", "?")) == "blade_shove", str(gs.get("push_move", {})))
	_check("shove numbers", is_equal_approx(float((gs.get("push_move", {}) as Dictionary).get("guard_break", 0.0)), 70.0) and is_equal_approx(float((gs.get("push_move", {}) as Dictionary).get("recovery", 0.0)), 0.6), str(gs.get("push_move", {})))
	var ls := WeaponConfig.merged("light_sword")
	_check("light sword none", str((ls.get("push_move", {}) as Dictionary).get("type", "?")) == "none", str(ls.get("push_move", {})))
	_check("greatsword heavy", is_equal_approx(float((gs.get("attack", {}) as Dictionary).get("damage", 0.0)), 22.0) and is_equal_approx(float(gs.get("mesh_scale", 0.0)), 1.4), "dmg %s scale %s" % [str((gs.get("attack", {}) as Dictionary).get("damage", "?")), str(gs.get("mesh_scale", "?"))])

	# 5. Default player (light sword) carries no shove; SHOVE enters.
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		_check("default no shove", false, "no player in group")
		return
	_check("default no shove", not player.shove_available(), "weapon %s" % player.weapon_id)
	player.machine.start(PlayerStateMachine.SHOVE)
	_check("shove enters", player.machine.state_name() == "Shove", player.machine.state_name())
