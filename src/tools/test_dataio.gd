extends SceneTree

const BASE := "/tmp/opencode/dataio_test"
const CATALOG_SCRIPT = preload("res://src/dataio/catalog.gd")
const MAPIO_SCRIPT = preload("res://src/dataio/map_io.gd")
var _fails: int = 0
var _pass: int = 0


func _init() -> void:
	print("[test_dataio] start")
	_wipe(BASE)
	DirAccess.make_dir_recursive_absolute(BASE)
	_test_manifest()
	_test_sha256()
	_test_validate_rejects()
	_test_map_round_trip()
	_test_map_validate()
	_test_corrupt()
	_wipe(BASE)
	print("[test_dataio] done — %d pass, %d fail" % [_pass, _fails])
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS ", label)
	else:
		_fails += 1
		print("  FAIL ", label)


func _test_manifest() -> void:
	print("[test] manifest load")
	var cat: Catalog = CATALOG_SCRIPT.new()
	_check(cat.load() == OK, "load default manifest returns OK")
	_check(cat.order.size() == 6, "6 entries indexed")
	_check(cat.has("dungeon_floor_small_01"), "known id present")
	_check(not cat.has("bogus_id"), "unknown id absent")
	var issues := cat.validate()
	_check(issues.is_empty(), "validate() clean, got: %s" % issues + ", count=%d" % issues.size())
	var p := cat.resolve_scene_path("dungeon_floor_small_01")
	_check(p.ends_with("floor_small_01.glb"), "scene path resolves: %s" % p)
	_check(FileAccess.file_exists(p), "scene file exists on disk")
	_check(cat.names().size() == 6, "names() lists 6 entries")
	cat = null


func _test_sha256() -> void:
	print("[test] sha256 verification")
	var cat: Catalog = CATALOG_SCRIPT.new()
	cat.load()
	for id in cat.order:
		var res := cat.verify_sha256(id)
		_check(res.get("ok", false), "sha256 matches: %s (%s)" % [id, res.get("reason", "")])
	cat = null


func _test_validate_rejects() -> void:
	print("[test] validator rejects bad input")
	var bad := BASE.path_join("manifest_bad.json")
	var payload := {
		"format_version": "0.1",
		"entries": [
			{"id": "UPPER_case", "name": "N", "category": "nope", "license": "CC0",
			 "files": [{"path": "missing.glb", "sha256": "zz"}]},
			{"id": "good_id", "name": "G", "category": "architecture", "license": "CC0",
			 "files": [{"path": "assets/meshes/dongeon/floor_small_01.glb",
				"sha256": "cc0aee718e78c1823c47e3affa56f212d8aa44c07ee3e601c6f29b83f0774e1b"}]},
		],
	}
	JsonFile.save_atomic(bad, payload)
	var cat: Catalog = CATALOG_SCRIPT.new(bad)
	cat.load()
	var issues := cat.validate()
	var text := "\n".join(issues)
	_check(issues.size() >= 4, "bad manifest yields issues (%d): %s" % [issues.size(), text])
	_check(text.contains("bad id") or text.contains("UPPER_case"), "catches bad id pattern")
	_check(text.contains("nope"), "catches unknown category")
	_check(text.contains("missing.glb"), "catches missing file")
	_check(text.contains("zz"), "catches bad sha256")
	_check(cat.order.size() == 2, "indexes both entries regardless")
	cat = null


func _test_map_round_trip() -> void:
	print("[test] map serialize → save → load → deserialize")
	var placements := [
		{"prefab_id": "dungeon_floor_small_01", "instance_id": "inst_0",
		 "transform": {"position": Vector3(0, 0, 0), "rotation": Vector3.ZERO, "scale": Vector3.ONE}},
		{"prefab_id": "dungeon_wall_small_01", "instance_id": "inst_1",
		 "transform": {"position": Vector3(0, 0, -3), "rotation": Vector3(0, 90, 0), "scale": Vector3.ONE}},
		{"prefab_id": "dungeon_pillar_01",
		 "transform": {"position": Vector3(2.5, 0, -1), "rotation": Vector3.ZERO, "scale": Vector3(0.5, 2, 0.5)}},
	]
	var map: Dictionary = MAPIO_SCRIPT.serialize("test_corridor", placements)
	_check(map.get("format_version") == "0.1", "map carries format_version")
	_check(map.get("name") == "test_corridor", "map name kept")
	_check((map["prefabs"] as Array).size() == 3, "3 prefabs serialized")
	var path := BASE.path_join("corridor.json")
	_check(JsonFile.save_atomic(path, map) == OK, "map saved")
	_check(not FileAccess.file_exists(path + ".tmp"), "no .tmp leftover")
	var loaded := JsonFile.load_object(path)
	_check(loaded.get("name") == "test_corridor", "map reloaded from disk")
	var back: Array = MAPIO_SCRIPT.deserialize(loaded)
	_check(back.size() == 3, "deserializes back 3 placements")
	_check(back[0]["prefab_id"] == "dungeon_floor_small_01", "prefab_id kept")
	_check(back[0]["instance_id"] == "inst_0", "instance_id kept when present")
	_check(back[2]["instance_id"] == "inst_2", "instance_id generated when missing")
	var t0: Dictionary = back[0]["transform"]
	_check(t0["position"] == Vector3(0, 0, 0), "position kept")
	var t1: Dictionary = back[1]["transform"]
	_check(t1["position"] == Vector3(0, 0, -3) and t1["rotation"] == Vector3(0, 90, 0), "rot+pos kept")
	var t2: Dictionary = back[2]["transform"]
	_check(t2["scale"] == Vector3(0.5, 2, 0.5), "non-trivial scale kept")


func _test_map_validate() -> void:
	print("[test] map validator")
	var cat: Catalog = CATALOG_SCRIPT.new()
	cat.load()
	var good: Dictionary = MAPIO_SCRIPT.serialize("good", [
		{"prefab_id": "dungeon_floor_small_01", "transform": {"position": Vector3(1, 2, 3)}},
	])
	var issues := MAPIO_SCRIPT.validate_map(good)
	_check(issues.is_empty(), "valid map passes structural checks: %s" % issues)
	var refs := MAPIO_SCRIPT.validate_refs(good, cat)
	_check(refs.is_empty(), "valid refs resolve in catalog")
	var bad_map := MAPIO_SCRIPT.serialize("bad", [
		{"prefab_id": "does_not_exist", "transform": {"position": Vector3.ONE}},
	])
	_check(MAPIO_SCRIPT.validate_map(bad_map).is_empty(), "structure OK for unknown id (ref check only)")
	_check(not MAPIO_SCRIPT.validate_refs(bad_map, cat).is_empty(), "catches unknown prefab_id")
	var broken := {
		"format_version": "0.1", "name": "broken",
		"prefabs": [
			{"prefab_id": "DASH-case", "transform": {"position": [1, 2]}},
		],
	}
	var bissues := MAPIO_SCRIPT.validate_map(broken)
	_check(not bissues.is_empty(), "catches bad prefab_id + wrong position arity: %s" % bissues)
	cat = null


func _test_corrupt() -> void:
	print("[test] corrupt map file → quarantine")
	var path := BASE.path_join("torn.json")
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string("{definitely not json")
	fa = null
	var obj := JsonFile.load_object(path)
	_check(obj.is_empty(), "corrupt file loads as empty")
	_check(not FileAccess.file_exists(path), "original removed")
	var quarantined := false
	for f in DirAccess.get_files_at(BASE):
		if f.begins_with("torn.json.corrupt"):
			quarantined = true
	_check(quarantined, "corrupt file quarantined")


func _wipe(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var f = da.get_next()
	while f != "":
		if f == "." or f == "..":
			f = da.get_next()
			continue
		var p = dir.path_join(f)
		if da.current_is_dir():
			_wipe(p)
			DirAccess.remove_absolute(p)
		else:
			DirAccess.remove_absolute(p)
		f = da.get_next()
	da.list_dir_end()