extends Node

## Persistent state manager — the single point for all saves.
## Infrastructure only: run/world buckets arrive in P6, progression in P7.
## Save path resolution: absolute or "user://"/"res://" used as-is;
## plain filenames are joined under [member base_dir].

const VERSION: int = 1
const SAVE_KEY: String = "soulmaker_save"

## Base directory for relative save paths. Defaults to "user://".
## Inject /tmp/... path for deterministic headless tests.
var base_dir: String = "user://"

## JSON-serializable game state — the canonical runtime data.
var state: Dictionary = {}

## Last successfully used save/load path (display / logging).
var current_path: String = ""


func reset() -> void:
	state = {}
	current_path = ""


func has_value(path: String) -> bool:
	var cursor: Variant = state
	for key in path.split("."):
		if not cursor is Dictionary or not (cursor as Dictionary).has(key):
			return false
		cursor = (cursor as Dictionary)[key]
	return true


func get_value(path: String, default: Variant = null) -> Variant:
	var cursor: Variant = state
	for key in path.split("."):
		if not cursor is Dictionary or not (cursor as Dictionary).has(key):
			return default
		cursor = (cursor as Dictionary)[key]
	return cursor


func set_value(path: String, value: Variant) -> void:
	var keys := path.split(".")
	if keys.is_empty():
		return
	var cursor: Dictionary = state
	for i in keys.size() - 1:
		var key := keys[i] as String
		if not cursor.has(key) or not cursor[key] is Dictionary:
			cursor[key] = {}
		cursor = cursor[key] as Dictionary
	cursor[keys[keys.size() - 1]] = value


func save(path: String) -> Error:
	var final := _resolve(path)
	DirAccess.make_dir_recursive_absolute(final.get_base_dir())
	var payload := {SAVE_KEY: true, "version": VERSION, "state": state}
	var text := JSON.stringify(payload, "\t") + "\n"
	var err := _atomic_write(final, text)
	if err == OK:
		current_path = final
		print("[GameState] saved %s (%d top keys)" % [final, state.size()])
	else:
		push_error("[GameState] save failed: %s error=%d" % [final, err])
	return err


func load_save(path: String) -> Dictionary:
	var final := _resolve(path)
	if not FileAccess.file_exists(final):
		push_warning("[GameState] no save at %s" % final)
		return {}
	var fa := FileAccess.open(final, FileAccess.READ)
	if fa == null:
		push_warning("[GameState] cannot open %s (error %d)" % [final, FileAccess.get_open_error()])
		return {}
	var text := fa.get_as_text()
	fa = null
	if not text.strip_edges().begins_with("{"):
		_quarantine(final)
		state = {}
		current_path = ""
		push_warning("[GameState] not a JSON object save, quarantined: %s" % final)
		return {}
	var obj: Variant = JSON.parse_string(text)
	if obj is Dictionary and (obj as Dictionary).get(SAVE_KEY) == true \
		and (obj as Dictionary).get("version") == VERSION \
		and (obj as Dictionary).get("state") is Dictionary:
		state = (obj as Dictionary)["state"] as Dictionary
		current_path = final
		print("[GameState] loaded %s (%d top keys)" % [final, state.size()])
		return state
	_quarantine(final)
	state = {}
	current_path = ""
	push_warning("[GameState] corrupt/incompatible save quarantined: %s" % final)
	return {}


## ── internal ──────────────────────────────────────────────────────────


func _resolve(path: String) -> String:
	if path.contains("://") or path.begins_with("/"):
		return path
	return base_dir.path_join(path)


func _atomic_write(final_path: String, text: String) -> Error:
	var tmp := final_path + ".tmp"
	var fa := FileAccess.open(tmp, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_string(text)
	fa = null
	return DirAccess.rename_absolute(tmp, final_path)


func _quarantine(path: String) -> void:
	var dir := path.get_base_dir()
	var fname := path.get_file()
	var dest := dir.path_join(fname + ".corrupt")
	var n := 1
	while FileAccess.file_exists(dest):
		dest = dir.path_join(fname + ".corrupt.%d" % n)
		n += 1
	var err := DirAccess.rename_absolute(path, dest)
	if err != OK:
		push_warning("[GameState] quarantine rename failed (%d): %s" % [err, path])
