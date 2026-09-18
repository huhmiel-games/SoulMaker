class_name MapMenu
extends Control

## Map library menu (P1 map editor): lists user://maps with Load / New /
## Delete. Full keyboard/gamepad parity, no mouse: arrows/D-pad move the
## highlight, A/E confirms (Load, or New on the first row), X arms then
## confirms delete, B cancels the arm. Rename deferred. Boots the editor via
## GameState "editor/pending_map" + scene change; the editor returns here
## through ESC (menu action, auto-saves first).

const MAPS_DIR := "user://maps"
const EDITOR_SCENE := "res://scenes/editors/map_editor.tscn"
const PENDING_KEY := "editor/pending_map"

## Attach points — must exist in the scene scaffold.
@onready var map_list: VBoxContainer = get_node("MapList")
@onready var status_label: Label = get_node("StatusLabel")

## Bare map names, sorted (row 0 is always "[ + New map ]").
var _names: PackedStringArray = []
## Highlighted row (0 = New).
var _cursor := 0
var _rows: Array[Label] = []
## Name with a pending delete-arm ("" = none).
var _delete_armed := ""


func _ready() -> void:
	# No cursor: rows are display-only, everything is arrows/D-pad + A/E.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	InputManager.action_pressed.connect(_on_input_action)
	InputManager.set_profile(&"editor")
	_refresh_list()
	_set_status("arrows move · A load · X delete · ESC nothing here yet")


func _refresh_list() -> void:
	for child in map_list.get_children():
		child.queue_free()
	_rows.clear()
	_names = MapIO.list_map_names(MAPS_DIR)
	_add_row("[ + New map ]")
	for name in _names:
		_add_row(name)
	_cursor = clampi(_cursor, 0, _rows.size() - 1)
	_highlight_current()


func _add_row(text: String) -> void:
	var row := Label.new()
	row.text = text
	row.focus_mode = Control.FOCUS_NONE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_list.add_child(row)
	_rows.append(row)


func _highlight_current() -> void:
	for row in _rows:
		row.modulate = Color(1.0, 1.0, 1.0, 0.6)
	if _cursor >= 0 and _cursor < _rows.size():
		var current := _rows[_cursor]
		if _cursor > 0 and _names[_cursor - 1] == _delete_armed:
			current.modulate = Color(1.0, 0.35, 0.35)
		else:
			current.modulate = Color.WHITE


func _cycle(direction: int) -> void:
	if _rows.is_empty():
		return
	_delete_armed = ""
	_cursor = posmod(_cursor + direction, _rows.size())
	_highlight_current()


func _on_input_action(action: StringName) -> void:
	match action:
		&"catalog_next":
			_cycle(1)
		&"catalog_prev":
			_cycle(-1)
		&"place_select":
			_confirm_current()
		&"delete_file":
			_delete_pressed()
		&"deselect":
			if _delete_armed != "":
				_delete_armed = ""
				_highlight_current()
				_set_status("delete cancelled")


func _confirm_current() -> void:
	if _cursor == 0:
		_new_map()
		return
	_load_map(_names[_cursor - 1])


func _new_map() -> void:
	var name := MapIO.first_free_name(_names)
	var err := JsonFile.save_atomic(_map_path(name), MapIO.serialize(name, []))
	if err != OK:
		_set_status("new map FAILED (%d)" % err)
		return
	_enter_editor(name)


func _load_map(name: String) -> void:
	_enter_editor(name)


func _enter_editor(name: String) -> void:
	GameState.set_value(PENDING_KEY, name)
	get_tree().change_scene_to_file(EDITOR_SCENE)


func _delete_pressed() -> void:
	if _cursor == 0:
		_set_status("nothing to delete on the New row")
		return
	var name := _names[_cursor - 1]
	if _delete_armed != name:
		_delete_armed = name
		_highlight_current()
		_set_status("DELETE %s? X again to confirm · B cancels" % name)
		return
	_delete_armed = ""
	var err := MapIO.delete_map_file(MAPS_DIR, name)
	if err != OK:
		_set_status("delete FAILED (%d)" % err)
		return
	_set_status("deleted %s" % name)
	_refresh_list()


func _map_path(name: String) -> String:
	return MAPS_DIR.path_join("%s.json" % name)


func _set_status(msg: String) -> void:
	print("[MapMenu] %s" % msg)
	status_label.text = msg
