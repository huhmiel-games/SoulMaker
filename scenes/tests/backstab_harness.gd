extends Node

## S2 deterministic backstab bot (P3, features/17 criticals): drives
## soldier.take_hit directly with positioned attacker points — no AI timing
## variance, fully synchronous, so every assert is exact. Covers: rear-arc
## crit in neutral (IDLE) and committed (RECOVER) states, frontal shield
## block unaffected, FLINCH ineligible, flag-off veto, legacy mult 1.0 =
## normal hit, attacker crit-iframes. Prints PASS/FAIL per step plus a
## summary line, then quits (headless).
## Run: Godot --headless --path . scenes/tests/backstab_harness.tscn
var _fails := 0


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_run()
	print("[Harness] backstab S2: %d FAIL" % _fails)
	get_tree().quit()


func _check(name: String, cond: bool, detail: String) -> void:
	if cond:
		print("[Harness] PASS %s (%s)" % [name, detail])
	else:
		_fails += 1
		print("[Harness] FAIL %s (%s)" % [name, detail])


func _run() -> void:
	var soldier := get_tree().get_first_node_in_group("backstab_dummy") as SoldierEnemy
	if soldier == null:
		_check("harness boot", false, "no soldier in group")
		return
	_check("harness boot", true, "soldier found, flag %s" % str(soldier.cfg.get("backstab_vulnerable", "?")))
	# Soldier faces -Z (rotation.y = 0): rear attacker at +Z.
	var rear := soldier.global_position + Vector3(0.0, 0.0, 2.0)
	var front := soldier.global_position + Vector3(0.0, 0.0, -2.0)

	# 1. Rear + IDLE + mult = crit x1.5: hp 60 -> 45, poise 30 -> 7.5.
	soldier.hp = 60.0
	soldier.poise = 30.0
	soldier.state = SoldierEnemy.IDLE
	var res: Dictionary = soldier.take_hit(10.0, rear, 1.5)
	_check("rear idle crit", bool(res.get("crit", false)) and not bool(res.get("blocked", false)), str(res))
	_check("crit damage", is_equal_approx(soldier.hp, 45.0) and is_equal_approx(soldier.poise, 7.5), "hp %.1f poise %.1f" % [soldier.hp, soldier.poise])

	# 2. Frontal + IDLE + mult = shield block, no crit (regression).
	soldier.hp = 60.0
	soldier.poise = 30.0
	soldier.state = SoldierEnemy.IDLE
	res = soldier.take_hit(10.0, front, 1.5)
	_check("front still blocks", bool(res.get("blocked", false)) and not bool(res.get("crit", false)), str(res))
	_check("block spares hp", is_equal_approx(soldier.hp, 60.0), "hp %.1f" % soldier.hp)

	# 3. Rear + FLINCH + mult = normal hit, no chain-crit on a stagger.
	soldier.hp = 60.0
	soldier.poise = 30.0
	soldier.state = SoldierEnemy.FLINCH
	res = soldier.take_hit(10.0, rear, 1.5)
	_check("flinch ineligible", not bool(res.get("crit", false)) and is_equal_approx(soldier.hp, 50.0), str(res))

	# 4. Flag off = veto (future boss/immune config).
	soldier.hp = 60.0
	soldier.poise = 30.0
	soldier.state = SoldierEnemy.IDLE
	soldier.cfg["backstab_vulnerable"] = false
	res = soldier.take_hit(10.0, rear, 1.5)
	_check("flag veto", not bool(res.get("crit", false)) and is_equal_approx(soldier.hp, 50.0), str(res))
	soldier.cfg["backstab_vulnerable"] = true

	# 5. Rear + RECOVER (committed) + low poise = crit + flinch.
	soldier.hp = 60.0
	soldier.poise = 10.0
	soldier.state = SoldierEnemy.RECOVER
	res = soldier.take_hit(10.0, rear, 1.5)
	_check("committed crit", bool(res.get("crit", false)), str(res))
	_check("crit breaks poise", soldier.state == SoldierEnemy.FLINCH and is_equal_approx(soldier.poise, 30.0), "state %s poise %.1f" % [SoldierEnemy.NAMES.get(soldier.state, "?"), soldier.poise])

	# 6. Legacy caller (mult 1.0) rear = plain 10 dmg, no crit.
	soldier.hp = 60.0
	soldier.poise = 30.0
	soldier.state = SoldierEnemy.IDLE
	res = soldier.take_hit(10.0, rear)
	_check("no mult no crit", not bool(res.get("crit", false)) and is_equal_approx(soldier.hp, 50.0), str(res))

	# 7. Attacker crit-iframes: player.take_hit ignored while set.
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		_check("crit iframes", false, "no player in group")
		return
	player.hp = 100.0
	player.poise = 50.0
	player.crit_iframes = PlayerController.CRIT_IFRAMES
	res = player.take_hit(10.0, 20.0, front, 10.0)
	_check("crit iframes", not bool(res.get("staggered", false)) and not bool(res.get("blocked", false)) and is_equal_approx(player.hp, 100.0), str(res))
