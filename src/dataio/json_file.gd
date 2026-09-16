class_name JsonFile
extends RefCounted

## Minimal, tolerant JSON object persistence (ADR-009: unknown fields are kept,
## corrupt files are quarantined — never wiped in place). Shared by world/map IO.

## Writes [param payload] atomically to [param path] (.tmp + rename).
static func save_atomic(path: String, payload: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var text := JSON.stringify(payload, "\t") + "\n"
	var err := _atomic_write(path, text)
	if err != OK:
		push_error("[JsonFile] save failed: %s error=%d" % [path, err])
	return err


## Reads a JSON object from [param path]. Returns {} on missing or corrupt
## input; corrupt files are renamed to `<file>.corrupt` (never deleted).
static func load_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		push_warning("[JsonFile] cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var text := fa.get_as_text()
	fa = null
	if not text.strip_edges().begins_with("{"):
		_quarantine(path)
		push_warning("[JsonFile] not a JSON object, quarantined: %s" % path)
		return {}
	var obj: Variant = JSON.parse_string(text)
	if not obj is Dictionary:
		_quarantine(path)
		push_warning("[JsonFile] corrupt JSON, quarantined: %s" % path)
		return {}
	return obj as Dictionary


## ── internal ──────────────────────────────────────────────────────────

static func _atomic_write(final_path: String, text: String) -> Error:
	var tmp := final_path + ".tmp"
	var fa := FileAccess.open(tmp, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_string(text)
	fa = null
	return DirAccess.rename_absolute(tmp, final_path)


static func _quarantine(path: String) -> void:
	var dir := path.get_base_dir()
	var fname := path.get_file()
	var dest := dir.path_join(fname + ".corrupt")
	var n := 1
	while FileAccess.file_exists(dest):
		dest = dir.path_join(fname + ".corrupt.%d" % n)
		n += 1
	var err := DirAccess.rename_absolute(path, dest)
	if err != OK:
		push_warning("[JsonFile] quarantine rename failed (%d): %s" % [err, path])