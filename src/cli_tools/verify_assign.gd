extends SceneTree

## Headless assign-clip check (anim-lab "Assign current take"): exercises the
## Moveset.assign_clip seam on in-memory copies of the shipped moveset (never
## saved) — legacy rewrite, variant upsert/create, loop/phase overrides and
## -1 keep, unknown body/stance rejection, unknown slot tolerance, and
## resolve_clip picking up the assigned takes. Pure Moveset — no scene.
## Run: <godot> --headless --path . --script res://src/cli_tools/verify_assign.gd

var _fail := 0
var _count := 0


func _check(cond: bool, label: String, extra := "") -> void:
	_count += 1
	if cond:
		return
	_fail += 1
	print("[Assign] FAIL %s %s" % [label, extra])


func _initialize() -> void:
	var shipped := Moveset.load_object()
	_check(not Moveset.validate_moveset(shipped).is_empty() == false, "shipped-valid")

	# 1. Legacy rewrite keeps loop/phases, resets active.
	var o1: Dictionary = shipped.duplicate(true)
	var r1 := Moveset.assign_clip(o1, "walk", "any", "any", "ual1__Walk")
	_check(bool(r1.get("ok", false)) and str(r1.get("where", "")) == "legacy", "legacy-ok", str(r1))
	var w1: Dictionary = (o1["slots"] as Dictionary)["walk"]
	_check((w1["clips"] as Array) == ["ual1__Walk"] and int(w1["active"]) == 0, "legacy-clips")
	_check(bool(w1.get("loop", false)), "legacy-loop-kept")
	_check(Moveset.validate_moveset(o1).is_empty(), "legacy-valid")

	# 2. Variant upsert on an existing match leaves legacy untouched.
	var o2: Dictionary = shipped.duplicate(true)
	var r2 := Moveset.assign_clip(o2, "walk", "female", "any", "ual1__Sprint")
	_check(bool(r2.get("ok", false)) and str(r2.get("where", "")).begins_with("variant"), "upsert-ok", str(r2))
	var w2: Dictionary = (o2["slots"] as Dictionary)["walk"]
	_check((w2["clips"] as Array) == ["adventure__walking"], "upsert-legacy-untouched")
	var have := PackedStringArray(["rig/ual1__Sprint", "rig/adventure__walking", "rig/female__walking"])
	_check(Moveset.resolve_clip(w2, have, &"female", &"any") == &"rig/ual1__Sprint", "upsert-resolves")

	# 3. Variant creation on a slot with no variants + loop/phases overrides.
	var o3: Dictionary = shipped.duplicate(true)
	var r3 := Moveset.assign_clip(o3, "roll", "female", "two_hand", "ual1__Sprint", 1,
		{"attack_start": 0.5, "release_start": 0.9, "windup_speed": -1.0})
	_check(bool(r3.get("ok", false)), "create-ok", str(r3))
	var w3: Dictionary = (o3["slots"] as Dictionary)["roll"]
	var created := {}
	for v in w3.get("variants", []):
		var m := (v as Dictionary).get("match", {}) as Dictionary
		if str(m.get("body", "")) == "female" and str(m.get("stance", "")) == "two_hand":
			created = v
	_check(not created.is_empty(), "create-present")
	_check((created.get("clips", []) as Array) == ["ual1__Sprint"], "create-clips")
	_check(not bool((w3.get("loop", true))), "create-slot-loop-untouched")
	var ph: Dictionary = created.get("phases", {})
	_check(float(ph.get("attack_start", -1.0)) == 0.5 and float(ph.get("release_start", -1.0)) == 0.9, "create-phases-set")
	_check(not ph.has("windup_speed"), "create-minus-one-kept-absent")
	_check(Moveset.validate_moveset(o3).is_empty(), "create-valid")
	var have3 := PackedStringArray(["rig/ual1__Sprint", "rig/aerial__Medium roll"])
	_check(Moveset.resolve_clip(w3, have3, &"female", &"two_hand") == &"rig/ual1__Sprint", "create-resolves")
	var eff := Moveset.effective_phases(o3, &"roll", &"female", &"two_hand")
	_check(float(eff.get("attack_start", -1.0)) == 0.5, "create-effective-merge")

	# 4. Unknown body/stance rejected, object untouched.
	var o4: Dictionary = shipped.duplicate(true)
	var before := str(o4)
	var r4 := Moveset.assign_clip(o4, "walk", "orc", "any", "ual1__Walk")
	var r5 := Moveset.assign_clip(o4, "walk", "male", "dual", "ual1__Walk")
	_check(not bool(r4.get("ok", true)) and not bool(r5.get("ok", true)), "reject-unknown-axis")
	_check(str(o4) == before, "reject-untouched")

	# 5. Unknown slot written + reported by the validator (loader ignores it).
	var o5: Dictionary = shipped.duplicate(true)
	var r6 := Moveset.assign_clip(o5, "attack_light_2", "any", "any", "ual1__Sword_Idle")
	_check(bool(r6.get("ok", false)), "unknown-slot-written", str(r6))
	var issues := Moveset.validate_moveset(o5)
	var flagged := false
	for i in issues:
		if "attack_light_2" in str(i):
			flagged = true
	_check(flagged, "unknown-slot-flagged", str(issues))

	# 6. Full -1 phases leave an existing variant's phases byte-identical.
	var o6: Dictionary = shipped.duplicate(true)
	var vbefore := ""
	for v in ((o6["slots"] as Dictionary)["attack_light_1"] as Dictionary).get("variants", []):
		var m := (v as Dictionary).get("match", {}) as Dictionary
		if str(m.get("stance", "")) == "two_hand":
			vbefore = str((v as Dictionary).get("phases", {}))
	var r7 := Moveset.assign_clip(o6, "attack_light_1", "any", "two_hand", "greatsword__great sword slash",
		-1, {"attack_start": -1.0, "release_start": -1.0})
	var vafter := ""
	for v in ((o6["slots"] as Dictionary)["attack_light_1"] as Dictionary).get("variants", []):
		var m := (v as Dictionary).get("match", {}) as Dictionary
		if str(m.get("stance", "")) == "two_hand":
			vafter = str((v as Dictionary).get("phases", {}))
	_check(bool(r7.get("ok", false)) and vbefore == vafter and vbefore != "", "phases-minus-one-identical")

	# 7. The lab-tool slot dropdown lists exactly KNOWN_SLOTS.
	_check_slot_enum()

	# 8. take_usage describe: legacy hit, variant hit, lab-only miss.
	var tool: Node = (load("res://scenes/anim_lab/anim_lab_tools.gd") as GDScript).new()
	var d1: String = tool._describe_take_usage("melee__sword and shield slash")
	_check(d1.contains("attack_light_1") and d1.contains("legacy") and d1.contains("attack_start"), "usage-legacy")
	var d2: String = tool._describe_take_usage("female__walking")
	_check(d2.contains("walk") and d2.contains("female"), "usage-variant")
	var d3: String = tool._describe_take_usage("nope__nothing")
	_check(d3.contains("not used"), "usage-unused")

	# 9. Assign pre-fill follows the previewed take (legacy / variant / reset).
	var tool2 = (load("res://scenes/anim_lab/anim_lab_tools.gd") as GDScript).new()
	tool2._prefill_assign("melee__sword and shield slash")
	_check(tool2.assign_slot == "attack_light_1" and tool2.assign_body == "any" and tool2.assign_stance == "any", "prefill-legacy-coords")
	_check(abs(tool2.assign_attack_start - 0.4416) < 0.0001 and abs(tool2.assign_release_start - 0.803) < 0.0001, "prefill-legacy-phases")
	_check(tool2.assign_loop == 0, "prefill-legacy-loop")
	tool2._prefill_assign("female__walking")
	_check(tool2.assign_slot == "walk" and tool2.assign_body == "female" and tool2.assign_stance == "any", "prefill-variant-coords")
	_check(tool2.assign_loop == 1, "prefill-variant-loop")
	tool2._prefill_assign("nope__nothing")
	_check(tool2.assign_slot == "" and tool2.assign_body == "any" and tool2.assign_stance == "any" and tool2.assign_loop == -1 and tool2.assign_attack_start < 0.0, "prefill-reset")
	tool.free()

	# 10. Entry picker across several usages of one take.
	var tool3 = (load("res://scenes/anim_lab/anim_lab_tools.gd") as GDScript).new()
	var keys: PackedStringArray = tool3._usage_keys("melee__sword and shield walk backward")
	_check(keys == PackedStringArray(["walk_back", "walk_back · female/any"]), "picker-keys-multi", str(keys))
	var single: PackedStringArray = tool3._usage_keys("melee__sword and shield slash")
	_check(single == PackedStringArray(["attack_light_1"]), "picker-keys-single", str(single))
	tool3._prefill_assign("melee__sword and shield walk backward")
	_check(String(tool3.assign_entry) == "walk_back" and tool3.assign_slot == "walk_back" and tool3.assign_body == "any", "picker-first")
	tool3.assign_entry = "walk_back · female/any"
	_check(tool3.assign_slot == "walk_back" and tool3.assign_body == "female" and tool3.assign_stance == "any", "picker-switch")
	var d4: String = tool3._describe_take_usage("melee__sword and shield walk backward", "walk_back · female/any")
	_check(d4.contains("► slot walk_back — variant"), "picker-mark")
	var slot_before: String = tool3.assign_slot
	tool3.assign_entry = "bogus"
	_check(tool3.assign_slot == slot_before, "picker-bogus-ignored")
	var p := {"name": "assign_entry", "hint": 0, "hint_string": ""}
	tool3._last_take = "melee__sword and shield walk backward"
	tool3._validate_property(p)
	_check(int(p["hint"]) == PROPERTY_HINT_ENUM and String(p["hint_string"]) == "walk_back,walk_back · female/any", "picker-hint", String(p["hint_string"]))
	tool2.free()
	tool3.free()

	# 11. Overwrite diff: no-change/creation = "", tweaks/clip-swap = listed.
	var tool4 = (load("res://scenes/anim_lab/anim_lab_tools.gd") as GDScript).new()
	var o7: Dictionary = Moveset.load_object()
	tool4._reset_assign()
	_check(String(tool4._assign_diff(o7, "attack_light_1", "any", "any", "melee__sword and shield slash")) == "", "diff-nochange")
	tool4.assign_attack_start = 0.9
	var d5: String = tool4._assign_diff(o7, "attack_light_1", "any", "any", "melee__sword and shield slash")
	_check(d5.contains("attack_start") and d5.contains("0.4416") and d5.contains("0.9"), "diff-phase", d5)
	tool4._reset_assign()
	_check(String(tool4._assign_diff(o7, "roll", "female", "two_hand", "ual1__Sprint")) == "", "diff-create-variant")
	_check(String(tool4._assign_diff(o7, "attack_light_9", "any", "any", "ual1__Sprint")) == "", "diff-create-slot")
	_check(String(tool4._assign_diff(o7, "walk", "any", "any", "ual1__Walk")).contains("clips"), "diff-clips")
	tool4.assign_loop = 0
	_check(String(tool4._assign_diff(o7, "walk", "any", "any", "adventure__walking")).contains("loop"), "diff-loop")
	tool4._reset_assign()
	var o8 := {"slots": {"walk": {"clips": ["adventure__walking"], "active": 2, "loop": true}}}
	_check(String(tool4._assign_diff(o8, "walk", "any", "any", "adventure__walking")).contains("active"), "diff-active")
	tool4.free()

	print("[Assign] %d/%d PASS" % [_count - _fail, _count])
	quit(1 if _fail > 0 else 0)


## The assign_slot @export_enum in the lab tool must list exactly
## Moveset.KNOWN_SLOTS (minus the "" empty entry): S5 slot additions touch
## both files, this fails loudly on drift.
func _check_slot_enum() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/anim_lab/anim_lab_tools.gd")
	var want: PackedStringArray = []
	for s in Moveset.KNOWN_SLOTS:
		want.append(String(s))
	var ok := true
	for s in want:
		if not src.contains("\"%s\"" % s):
			ok = false
			print("[Assign] FAIL slot-enum-missing '%s'" % s)
	var line := ""
	for l in src.split("\n"):
		if "assign_slot" in l and "export_enum" in l:
			line = l
	var count := 0
	for s in want:
		if line.contains("\"%s\"" % s):
			count += 1
	_check(ok and count == want.size(), "slot-enum-in-sync", "want %d" % want.size())
