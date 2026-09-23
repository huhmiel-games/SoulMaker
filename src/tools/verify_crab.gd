extends SceneTree

## Headless crab-slot check (S4-bis): resolves the 6 directional slots for
## every body/stance combo against the baked player_pack.res take list and
## asserts the expected clips (melee = sword_shield default, greatsword =
## two_hand, female = female strafe + melee backward fallback, adventure
## legacy untouched). Pure Moveset.resolve_clip — no scene, no autoloads.
## Run: <godot> --headless --path . --script res://src/tools/verify_crab.gd
const PACK := "res://scenes/anim_lab/player_pack.res"

const CASES := [
	# [slot, body, stance, expected_suffix]
	["walk_back", "male", "sword_shield", "melee__sword and shield walk backward"],
	["run_back", "male", "sword_shield", "melee__sword and shield run backward"],
	["walk_strafe_left", "male", "sword_shield", "melee__sword and shield strafe walk left"],
	["walk_strafe_right", "male", "sword_shield", "melee__sword and shield strafe walk right"],
	["run_strafe_left", "male", "sword_shield", "melee__sword and shield strafe run left"],
	["run_strafe_right", "male", "sword_shield", "melee__sword and shield strafe run right"],
	["walk_back", "male", "two_hand", "greatsword__great sword walk backward"],
	["run_back", "male", "two_hand", "greatsword__great sword run backward"],
	["walk_strafe_left", "male", "two_hand", "greatsword__great sword strafe walk left"],
	["run_strafe_right", "male", "two_hand", "greatsword__great sword strafe run right"],
	["walk_strafe_left", "female", "sword_shield", "female__left strafe walk"],
	["run_strafe_right", "female", "sword_shield", "female__right run strafe"],
	["walk_back", "female", "sword_shield", "melee__sword and shield walk backward"],
	["run_back", "female", "two_hand", "melee__sword and shield run backward"],
	["walk", "male", "sword_shield", "adventure__walking"],
	["run", "female", "sword_shield", "female__running"],
	["guard_idle", "male", "sword_shield", "melee__sword and shield block idle loop"],
	["guard_idle", "male", "two_hand", "greatsword__great sword blocking loop"],
	["guard_idle", "female", "sword_shield", "melee__sword and shield block idle loop"],
	["roll_fast", "male", "sword_shield", "aerial__fast roll"],
	["roll", "male", "sword_shield", "aerial__Medium roll"],
	["idle", "male", "two_hand", "greatsword__great sword idle"],
	["idle", "male", "sword_shield", "adventure__idle"],
]


func _initialize() -> void:
	var fail := 0
	var lib := ResourceLoader.load(PACK) as AnimationLibrary
	if lib == null:
		print("[Crab] FAIL: cannot load player_pack.res")
		quit(1)
		return
	var have := PackedStringArray()
	for n in lib.get_animation_list():
		have.append("rig/%s" % n)
	var ms := Moveset.load_object()
	var slots: Dictionary = ms.get("slots", {})
	for c in CASES:
		var slot: Dictionary = slots.get(c[0], {})
		var got := Moveset.resolve_clip(slot, have, StringName(c[1]), StringName(c[2]))
		var want := "rig/%s" % c[3]
		if got != StringName(want):
			fail += 1
			print("[Crab] FAIL %s %s/%s: got '%s' want '%s'" % [c[0], c[1], c[2], got, want])
	print("[Crab] %d/%d PASS" % [CASES.size() - fail, CASES.size()])
	# 2H attack timing (S5 R1): variant phases win per-key over the slot,
	# impact/rebound fall back to the slot, legacy SS untouched.
	var eff := Moveset.effective_phases(ms, &"attack_light_1", &"male", &"two_hand")
	for k in ["attack_start", "release_start", "sweep_start"]:
		print("[Crab] 2H %s = %s" % [k, str(eff.get(k))])
	if not is_equal_approx(float(eff.get("attack_start", -1.0)), 0.374):
		fail += 1
		print("[Crab] FAIL 2H attack_start")
	if not is_equal_approx(float(eff.get("release_start", -1.0)), 0.681):
		fail += 1
		print("[Crab] FAIL 2H release_start")
	if not is_equal_approx(float(eff.get("sweep_start", -1.0)), 0.339):
		fail += 1
		print("[Crab] FAIL 2H sweep_start")
	if not is_equal_approx(float((eff.get("impact", {}) as Dictionary).get("damage", -1.0)), 10.0):
		fail += 1
		print("[Crab] FAIL 2H impact fallback")
	if (eff.get("rebound", {}) as Dictionary).is_empty():
		fail += 1
		print("[Crab] FAIL 2H rebound fallback")
	var leg := Moveset.effective_phases(ms, &"attack_light_1", &"male", &"sword_shield")
	if not is_equal_approx(float(leg.get("attack_start", -1.0)), 0.4416):
		fail += 1
		print("[Crab] FAIL legacy attack_start")
	print("[Crab] phases %s" % ("PASS" if fail == 0 else "FAIL"))
	quit(1 if fail > 0 else 0)
