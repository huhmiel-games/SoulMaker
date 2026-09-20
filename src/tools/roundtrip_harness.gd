extends Node

## Scene-context round-trip harness (autoloads available here, unlike
## --script mode): builds the fixture map, hands it to the run scene through
## GameState, instances the run as a child, then asserts ground, placement,
## spawn and handover consumption. Prints ROUNDTRIP PASS/FAIL, quits.
var _frames := 0


func _ready() -> void:
	var ground := {Vector2i(50, 50): 1.0, Vector2i(51, 50): 0.5}
	var placements := [{
		"prefab_id": "dungeon_floor_small_01", "instance_id": "inst_0000",
		"transform": {"position": Vector3(5, 0, 5), "rotation": Vector3.ZERO, "scale": Vector3.ONE},
	}]
	var spawn := {"position": Vector3(0, 0, 8), "yaw": 0.0}
	var data := MapIO.serialize("roundtrip_fixture", placements, ground, {}, spawn)
	var issues := MapIO.validate_map(data)
	if not issues.is_empty():
		print("ROUNDTRIP FAIL fixture invalid: %s" % ", ".join(issues))
		get_tree().quit(1)
		return
	var back := MapIO.spawn_from_data(data)
	if (back.get("position", Vector3.ZERO) as Vector3).distance_to(Vector3(0, 0, 8)) > 0.001:
		print("ROUNDTRIP FAIL spawn round-trip lost")
		get_tree().quit(1)
		return
	if (MapIO.ground_from_data(data) as Dictionary).size() != 2:
		print("ROUNDTRIP FAIL ground round-trip lost")
		get_tree().quit(1)
		return
	GameState.set_value("game/pending_map", {"name": "roundtrip_fixture", "map": data})
	var packed: PackedScene = load("res://scenes/game/run.tscn")
	add_child(packed.instantiate())


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 30:
		return
	var run := get_node_or_null("Run")
	var fails := PackedStringArray()
	if run == null:
		fails.append("no Run node")
	else:
		if run.get_node_or_null("MapRoot/Ground") == null:
			fails.append("no built ground")
		var placement_found := false
		for child in run.get_node("MapRoot").get_children():
			if String(child.name).begins_with("Placement_"):
				placement_found = true
		if not placement_found:
			fails.append("no built placement")
		var player := run.get_node_or_null("Player") as Node3D
		if player == null:
			fails.append("no player")
		else:
			var p := player.position
			if absf(p.x) > 0.5 or absf(p.z - 8.0) > 0.5 or p.y < -1.0 or p.y > 2.5:
				fails.append("player off spawn: %s" % str(p))
		if str(GameState.get_value("game/pending_map", "x")) != "":
			fails.append("handover key not consumed")
	if fails.is_empty():
		print("ROUNDTRIP PASS: ground + placement + spawn + handover consumed")
	else:
		print("ROUNDTRIP FAIL: %s" % ", ".join(fails))
	get_tree().quit(0 if fails.is_empty() else 1)
