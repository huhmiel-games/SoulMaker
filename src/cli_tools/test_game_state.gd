extends SceneTree

const BASE := "/tmp/opencode/gs_test"
const GS_SCRIPT = preload("res://src/autoloads/game_state.gd")
var _fails: int = 0
var _pass: int = 0


func _init() -> void:
	print("[test_game_state] start")
	_wipe(BASE)
	DirAccess.make_dir_recursive_absolute(BASE)
	_test_dotted()
	_test_round_trip()
	_test_load_missing()
	_test_corrupt()
	_test_version_mismatch()
	_wipe(BASE)
	print("[test_game_state] done — %d pass, %d fail" % [_pass, _fails])
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS ", label)
	else:
		_fails += 1
		print("  FAIL ", label)


func _test_dotted() -> void:
	print("[test] dotted get/set")
	var gs = GS_SCRIPT.new()
	gs.base_dir = BASE
	gs.set_value("player.hp", 100)
	gs.set_value("player.pos", Vector3(1, 2, 3))
	gs.set_value("flags.boss_defeated", true)
	_check(gs.get_value("player.hp") == 100, "get existing")
	_check(gs.get_value("player.pos") == Vector3(1, 2, 3), "get nested")
	_check(gs.get_value("flags.boss_defeated") == true, "get bool")
	_check(gs.get_value("missing.key", "default") == "default", "get missing default")
	_check(gs.has_value("player.hp"), "has_value true")
	_check(not gs.has_value("nope"), "has_value false")
	gs.reset()
	_check(gs.state.is_empty(), "reset clears state")
	gs.free()


func _test_round_trip() -> void:
	print("[test] round-trip save/load")
	var gs = GS_SCRIPT.new()
	gs.base_dir = BASE
	gs.set_value("run", "ironman")
	gs.set_value("currency", 1234)
	gs.set_value("slots.weapon", "longsword")
	_check(gs.save("run.json") == OK, "save returns OK")
	_check(not FileAccess.file_exists(gs.current_path + ".tmp"), "no .tmp leftover")
	var gs2 = GS_SCRIPT.new()
	gs2.base_dir = BASE
	var loaded = gs2.load_save("run.json")
	_check(not loaded.is_empty(), "load returns non-empty")
	_check(gs2.get_value("run") == "ironman", "loaded run")
	_check(gs2.get_value("currency") == 1234, "loaded currency")
	_check(gs2.get_value("slots.weapon") == "longsword", "loaded nested")
	_check(gs2.current_path == gs.current_path, "current_path set")
	gs2.free()
	gs.free()


func _test_load_missing() -> void:
	print("[test] load missing file")
	var gs = GS_SCRIPT.new()
	gs.base_dir = BASE
	var loaded = gs.load_save("nope.json")
	_check(loaded.is_empty(), "returns empty")
	_check(gs.state.is_empty(), "state remains empty")
	gs.free()


func _test_corrupt() -> void:
	print("[test] corrupt file → quarantine")
	var path = BASE.path_join("bad.json")
	var fa = FileAccess.open(path, FileAccess.WRITE)
	fa.store_string("not json at all - torn write")
	fa = null
	var gs = GS_SCRIPT.new()
	gs.base_dir = BASE
	var loaded = gs.load_save("bad.json")
	_check(loaded.is_empty(), "returns empty on corrupt")
	_check(not FileAccess.file_exists(path), "original removed")
	var quarantine_exists = false
	for f in DirAccess.get_files_at(BASE):
		if f.begins_with("bad.json.corrupt"):
			quarantine_exists = true
	_check(quarantine_exists, "corrupt file quarantined")
	gs.free()


func _test_version_mismatch() -> void:
	print("[test] version mismatch → quarantine")
	var path = BASE.path_join("old.json")
	var obj = {"soulmaker_save": true, "version": 999, "state": {}}
	var fa = FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify(obj))
	fa = null
	var gs = GS_SCRIPT.new()
	gs.base_dir = BASE
	var loaded = gs.load_save("old.json")
	_check(loaded.is_empty(), "returns empty on version mismatch")
	_check(not FileAccess.file_exists(path), "original removed")
	gs.free()


func _wipe(dir: String) -> void:
	var da = DirAccess.open(dir)
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
