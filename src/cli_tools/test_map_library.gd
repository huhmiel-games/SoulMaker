extends SceneTree

## Headless deterministic check for the map-library file ops behind the map
## menu (MapIO.list_map_names / first_free_name / delete_map_file + a
## JsonFile round-trip). Scratch dir only, wiped before and after.

const BASE := "/tmp/opencode/maplib_test"
const MAPIO_SCRIPT = preload("res://src/dataio/map_io.gd")
const JSONFILE_SCRIPT = preload("res://src/dataio/json_file.gd")

var _fails: int = 0
var _pass: int = 0


func _init() -> void:
	print("[test_map_library] start")
	_wipe(BASE)
	var names := MAPIO_SCRIPT.list_map_names(BASE)
	_check(names.is_empty(), "empty scratch lists empty (dir created)")
	var n1: String = MAPIO_SCRIPT.first_free_name(names)
	_check(n1 == "untitled_01", "first free is untitled_01, got %s" % n1)
	var err := JSONFILE_SCRIPT.save_atomic(BASE.path_join(n1 + ".json"), MAPIO_SCRIPT.serialize(n1, []))
	_check(err == OK, "write empty map")
	names = MAPIO_SCRIPT.list_map_names(BASE)
	_check(names == PackedStringArray([n1]), "lists the written map")
	var back: Dictionary = JSONFILE_SCRIPT.load_object(BASE.path_join(n1 + ".json"))
	_check(str(back.get("name", "")) == n1, "round-trip name")
	_check(MAPIO_SCRIPT.validate_map(back).is_empty(), "round-trip validates")
	var n2: String = MAPIO_SCRIPT.first_free_name(names)
	_check(n2 == "untitled_02", "second free is untitled_02, got %s" % n2)
	err = MAPIO_SCRIPT.delete_map_file(BASE, n1)
	_check(err == OK, "delete file")
	names = MAPIO_SCRIPT.list_map_names(BASE)
	_check(names.is_empty(), "empty again after delete")
	err = MAPIO_SCRIPT.delete_map_file(BASE, "nope_missing")
	_check(err != OK, "delete missing fails")
	_wipe(BASE)
	print("[test_map_library] done — %d pass, %d fail" % [_pass, _fails])
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS ", label)
	else:
		_fails += 1
		print("  FAIL ", label)


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if not da.current_is_dir():
			da.remove(fname)
		fname = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(dir)
