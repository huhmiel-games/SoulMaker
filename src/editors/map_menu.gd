class_name MapMenu
extends GenericMenu

## Map library menu (P1 map editor): lists user://maps with Load / New /
## Delete, plus a Back row to the hub. Row 0 is always "[ + New map ]", the
## last row is always "[ ← Back ]" — both inert to X. Boots the editor via
## GameState "editor/pending_map" + scene change; the editor returns here
## through ESC (menu action, auto-saves first). Rename deferred.

const MAPS_DIR := "user://maps"
const EDITOR_SCENE := "res://scenes/editors/map_editor.tscn"
const HUB_SCENE := "res://scenes/main.tscn"
const PENDING_KEY := "editor/pending_map"

const NEW_LABEL := "[ + New map ]"
const BACK_LABEL := "[ ← Back ]"

## Bare map names, sorted (row 0 is New, last row is Back).
var _names: PackedStringArray = []


func _ready() -> void:
	super._ready()


func _menu_title() -> String:
	return "MAPS"


func _menu_hint() -> String:
	return "arrows move · A load · X delete"


func _load_entries() -> Array:
	var out: Array = [{"label": NEW_LABEL, "new": true}]
	_names = MapIO.list_map_names(MAPS_DIR)
	for name in _names:
		out.append({"label": name, "load": name, "can_delete": true})
	out.append({"label": BACK_LABEL, "open": HUB_SCENE})
	return out


func _confirm_verb(e: Dictionary) -> void:
	if e.get("new", false):
		_new_map()
		return
	if e.has("load"):
		_enter_editor(String(e["load"]))


func _delete_entry(i: int) -> String:
	if i < 0 or i >= _entries.size():
		return ""
	var e: Dictionary = _entries[i]
	if not e.has("load"):
		return ""
	var name := String(e["load"])
	var err := MapIO.delete_map_file(MAPS_DIR, name)
	if err != OK:
		return "delete FAILED (%d)" % err
	return "deleted %s" % name


func _new_map() -> void:
	var name := MapIO.first_free_name(_names)
	var err := JsonFile.save_atomic(_map_path(name), MapIO.serialize(name, []))
	if err != OK:
		_notice("new map FAILED (%d)" % err)
		return
	_enter_editor(name)


func _enter_editor(name: String) -> void:
	GameState.set_value(PENDING_KEY, name)
	get_tree().change_scene_to_file(EDITOR_SCENE)


func _map_path(name: String) -> String:
	return MAPS_DIR.path_join("%s.json" % name)
