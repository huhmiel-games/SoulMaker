class_name Catalog
extends RefCounted

## Catalog manifest loader (schema v0.1, ADR-010/017). Source of truth for
## every asset id → 3D file. Files resolve under res:// + entry path.

const DEFAULT_PATH := "res://data/catalog/manifest_v0.1.json"
const format_version := "0.1"
const CATEGORIES := [
	"prop_natural", "architecture", "light", "enemy_character",
	"clothing", "equipment", "animation", "prefab", "material",
]

var manifest_path: String = DEFAULT_PATH
var entries: Dictionary = {}
var order: PackedStringArray = []


func _init(path: String = DEFAULT_PATH) -> void:
	manifest_path = path


## Loads and indexes the manifest. Returns OK, or an Error on unreadable file.
func load() -> Error:
	var obj := JsonFile.load_object(manifest_path)
	if obj.is_empty():
		push_error("[Catalog] cannot load manifest: %s" % manifest_path)
		return ERR_FILE_CANT_OPEN
	entries.clear()
	order.clear()
	for entry in obj.get("entries", []):
		if entry is Dictionary and entry.has("id"):
			var id: String = entry["id"]
			entries[id] = entry
			order.append(id)
	return OK


## Structural validation against schema v0.1 essentials. Returns the list of
## problems (empty = OK). Tolerates unknown fields (ADR-009).
func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	var seen := {}
	var obj := JsonFile.load_object(manifest_path)
	if obj.is_empty():
		issues.append("manifest not readable")
		return issues
	if obj.get("format_version") != format_version:
		issues.append("format_version must be '%s'" % format_version)
	var list: Array = obj.get("entries", [])
	if not list is Array or list.is_empty():
		issues.append("entries missing or empty")
	for entry in list:
		if not entry is Dictionary:
			issues.append("entry is not an object")
			continue
		var id: Variant = entry.get("id")
		if not id is String or not SchemaUtil.matches_id(id as String):
			issues.append("bad id: %s" % id)
		else:
			seen[id] = int(seen.get(id, 0)) + 1
			if int(seen[id]) > 1:
				issues.append("duplicate id: %s" % id)
		var name: Variant = entry.get("name")
		if not name is String or (name as String).is_empty():
			issues.append("missing name (%s)" % id)
		var cat: Variant = entry.get("category")
		if not cat is String or not CATEGORIES.has(cat):
			issues.append("missing/unknown category (%s)" % id)
		if not entry.get("license") is String or (entry.get("license") as String).is_empty():
			issues.append("missing license (%s)" % id)
		var files: Variant = entry.get("files")
		if not files is Array or (files as Array).is_empty():
			issues.append("missing files (%s)" % id)
			continue
		for f in files:
			if not f is Dictionary:
				issues.append("bad file entry (%s)" % id)
				continue
			if not f.has("path"):
				issues.append("file missing path (%s)" % id)
				continue
			if not FileAccess.file_exists("res://" + str(f["path"])):
				issues.append("missing file: %s" % f["path"])
			var sha: Variant = f.get("sha256")
			if not sha is String or not SchemaUtil.matches_sha256(sha as String):
				issues.append("bad sha256 (%s)" % id)
	return issues


func has(id: String) -> bool:
	return entries.has(id)


func entry(id: String) -> Dictionary:
	return entries.get(id, {})


func resolve_scene_path(id: String) -> String:
	var e: Dictionary = entries.get(id, {})
	var files: Variant = e.get("files", [])
	if files is Array and not (files as Array).is_empty():
		var first: Dictionary = (files as Array)[0]
		if first.has("path"):
			return "res://" + str(first["path"])
	return ""


## Re-computes the sha256 of the entry's first file and compares it to the
## manifest. Returns {"ok": bool, "reason": String} — the manifest is only
## trustworthy if every listed file still matches.
func verify_sha256(id: String) -> Dictionary:
	var path := resolve_scene_path(id)
	if path.is_empty():
		return {"ok": false, "reason": "no file path for %s" % id}
	var e: Dictionary = entries.get(id, {})
	var files: Variant = e.get("files", [])
	var expected := ""
	if files is Array and not (files as Array).is_empty():
		expected = str((files as Array)[0].get("sha256", ""))
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "missing %s" % path}
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		ctx = null
		return {"ok": false, "reason": "cannot open %s" % path}
	while not fa.eof_reached():
		ctx.update(fa.get_buffer(65536))
	fa = null
	var actual := ctx.finish().hex_encode()
	if actual != expected:
		return {"ok": false, "reason": "sha256 mismatch for %s (expected %s, got %s)" % [id, expected, actual]}
	return {"ok": true, "reason": ""}


func names() -> Array:
	var out := []
	for id in order:
		out.append({"id": id, "name": str(entries[id].get("name", id))})
	return out
