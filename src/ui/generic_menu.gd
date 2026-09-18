class_name GenericMenu
extends Control

## Generic menu behavior, shared by every menu (hub, map library, later
## editors' menus). Display-only rows, full parity: arrows/D-pad move the
## highlight, A/E confirms, X arms/confirms delete on deletable rows, B
## cancels the arm. ESC is inert (nothing above a menu handles it).
##
## Entries are data (built by _load_entries, one dict per row):
## - {"label": "…", "open": "res://…tscn"}: change scene.
## - {"label": "…", "quit": true}: quit the game.
## - {"label": "…", "new": true} / {"label": "…", "load": name}: library
##   verbs, interpreted by the subclass (see MapMenu).
## - "can_delete": true: X arms (1st press) then _delete_entry (2nd press).
## Subclasses override _menu_title / _menu_hint / _load_entries /
## _delete_entry (virtual funcs — consts don't dispatch polymorphically).
## Their .tscn is a thin shell instancing generic_menu.tscn with the
## subclass script on the instance root (must call super._ready()).
## Feedback is unified: log line + HUD toast (transient, never persistent).

## Title + hint source. Subclasses override.
func _menu_title() -> String:
	return "MENU"


func _menu_hint() -> String:
	return "Up/Down select · A/E confirm"

## Attach points — must exist in the scene scaffold.
@onready var title_label: Label = get_node("Title")
@onready var entry_list: VBoxContainer = get_node("EntryList")
@onready var hud: EditorHUD = get_node("HUD")

var _entries: Array = []
var _cursor := 0
var _rows: Array[Label] = []
var _delete_armed := -1


func _ready() -> void:
	# No cursor: rows are display-only, everything is arrows/D-pad + A/E.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	InputManager.action_pressed.connect(_on_input_action)
	InputManager.set_profile(&"editor")
	title_label.text = _menu_title()
	_refresh_list()
	# Command hint is persistent (HintLabel), not a toast: it must survive.
	print("[Menu] %s" % _menu_hint())
	if hud != null:
		hud.set_hint(_menu_hint())


func _refresh_list() -> void:
	for child in entry_list.get_children():
		child.queue_free()
	_rows.clear()
	_entries = _load_entries()
	for e in _entries:
		var row := Label.new()
		row.text = String(e.get("label", "?"))
		row.focus_mode = Control.FOCUS_NONE
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_list.add_child(row)
		_rows.append(row)
	_delete_armed = -1
	_cursor = clampi(_cursor, 0, _rows.size() - 1)
	_highlight_current()


## Entry source, one dict per row (see class doc). Subclasses override.
func _load_entries() -> Array:
	return []


## Deletes entries[i] (2nd X press). Returns a user-facing message, or ""
## if the row is not deletable. Subclasses override.
func _delete_entry(_i: int) -> String:
	return ""


func _highlight_current() -> void:
	for row in _rows:
		row.modulate = Color(1.0, 1.0, 1.0, 0.6)
	if _cursor >= 0 and _cursor < _rows.size():
		var current := _rows[_cursor]
		if _cursor == _delete_armed:
			current.modulate = Color(1.0, 0.35, 0.35)
		else:
			current.modulate = Color.WHITE


func _cycle(direction: int) -> void:
	if _rows.is_empty():
		return
	_delete_armed = -1
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
			if _delete_armed != -1:
				_delete_armed = -1
				_highlight_current()
				_notice("delete cancelled")


func _confirm_current() -> void:
	if _cursor < 0 or _cursor >= _entries.size():
		return
	var e: Dictionary = _entries[_cursor]
	_delete_armed = -1
	if e.get("quit", false):
		print("[Menu] quit from %s" % _menu_title())
		get_tree().quit()
		return
	if e.has("open"):
		get_tree().change_scene_to_file(String(e["open"]))
		return
	_confirm_verb(e)
	_highlight_current()


## Non-open verbs (new/load/…). Handled by the subclass; default is inert.
func _confirm_verb(_e: Dictionary) -> void:
	pass


func _delete_pressed() -> void:
	if _cursor < 0 or _cursor >= _entries.size():
		return
	var e: Dictionary = _entries[_cursor]
	if not bool(e.get("can_delete", false)):
		_notice("nothing to delete here")
		return
	if _delete_armed != _cursor:
		_delete_armed = _cursor
		_highlight_current()
		_notice("DELETE %s? X again to confirm · B cancels" % e.get("label", "?"))
		return
	_delete_armed = -1
	var msg := _delete_entry(_cursor)
	if msg.is_empty():
		_notice("cannot delete %s" % e.get("label", "?"))
		return
	_notice(msg)
	_refresh_list()


func _notice(msg: String) -> void:
	print("[Menu] %s" % msg)
	if hud != null:
		hud.flash(msg)
