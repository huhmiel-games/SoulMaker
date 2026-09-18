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
	if not runtime_title.is_empty():
		return runtime_title
	return "MENU"


func _menu_hint() -> String:
	if not runtime_hint.is_empty():
		return runtime_hint
	return "Up/Down select · A/E confirm"

## Attach points — must exist in the scene scaffold.
@onready var title_label: Label = get_node("Title")
@onready var entry_list: VBoxContainer = get_node("EntryList")
@onready var hud: EditorHUD = get_node("HUD")

var _entries: Array = []
var _cursor := 0
var _rows: Array[Label] = []
var _delete_armed := -1

## Runtime content (param-driven menus, no subclass): the caller fills these
## via configure() BEFORE add_child (so _ready builds the list first try).
## - entries: one dict per row, {"label": "…"} + either a verb the subclass
##   understands or "call": Callable (executed on confirm — bind args at build
##   time). Deletable rows add "can_delete": true + "delete_call": Callable
##   (same contract as _delete_entry(index) -> String; success auto-drops the
##   row from runtime_entries, "" keeps it with a failure toast).
## - on_cancel: executed on B/Q when no delete-arm is pending (pause CANCEL,
##   confirm BACK, …).
var runtime_title := ""
var runtime_hint := ""
var runtime_entries: Array = []
var runtime_cancel: Callable


func configure(title: String, hint: String, entries: Array, on_cancel: Callable = Callable()) -> void:
	runtime_title = title
	runtime_hint = hint
	runtime_entries = entries
	runtime_cancel = on_cancel


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
		# Runtime contents live in a small modal panel — their inner HUD
		# would overflow it (offsets are fullscreen-sized). The caller's HUD
		# behind the dim stays the single toast surface; notices stay log.
		if not runtime_entries.is_empty():
			hud.visible = false


func _refresh_list() -> void:
	for child in entry_list.get_children():
		child.queue_free()
	_rows.clear()
	_entries = _load_entries()
	for e in _entries:
		var row := Label.new()
		row.text = _row_text(e)
		row.focus_mode = Control.FOCUS_NONE
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_list.add_child(row)
		_rows.append(row)
	_delete_armed = -1
	_cursor = clampi(_cursor, 0, _rows.size() - 1)
	_highlight_current()


## Row text: value-kind rows (settings pages) show "label: value", refreshed
## after every adjust. Entries: {"label", "kind": "value", "get": Callable
## (-> String display), "adjust": Callable (dir int -> String display),
## "reset": Callable (-> String display, A/E)}.
func _row_text(e: Dictionary) -> String:
	if str(e.get("kind", "")) == "value":
		var get: Callable = e.get("get", Callable())
		var display := str(get.call()) if get.is_valid() else "?"
		return "%s: %s" % [String(e.get("label", "?")), display]
	return String(e.get("label", "?"))


func _refresh_current() -> void:
	if _cursor >= 0 and _cursor < _rows.size() and _cursor < _entries.size():
		_rows[_cursor].text = _row_text(_entries[_cursor])


## Entry source, one dict per row (see class doc). Subclasses override; the
## runtime path returns the configured entries.
func _load_entries() -> Array:
	if not runtime_entries.is_empty():
		return runtime_entries
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
			elif runtime_cancel.is_valid():
				runtime_cancel.call()
		&"tab_next":
			_adjust_current(1)
		&"tab_prev":
			_adjust_current(-1)


func _confirm_current() -> void:
	if _cursor < 0 or _cursor >= _entries.size():
		return
	var e: Dictionary = _entries[_cursor]
	_delete_armed = -1
	if str(e.get("kind", "")) == "value":
		# A/E on a setting resets it (caller-owned default); plain rows below.
		var reset: Callable = e.get("reset", Callable())
		if reset.is_valid():
			reset.call()
			_refresh_current()
		return
	if e.get("quit", false):
		print("[Menu] quit from %s" % _menu_title())
		get_tree().quit()
		return
	if e.has("open"):
		get_tree().change_scene_to_file(String(e["open"]))
		return
	_confirm_verb(e)
	_highlight_current()


## Left/Right on a value row: the caller's adjust applies (clamp + side
## effects + dirty) and returns the new display; the row re-renders. Plain
## rows ignore these (catalog tabs live outside modals).
func _adjust_current(direction: int) -> void:
	_delete_armed = -1
	if _cursor < 0 or _cursor >= _entries.size():
		return
	var e: Dictionary = _entries[_cursor]
	if str(e.get("kind", "")) != "value":
		return
	var adjust: Callable = e.get("adjust", Callable())
	if adjust.is_valid():
		adjust.call(direction)
		_refresh_current()
		_highlight_current()


## Non-open verbs (new/load/…). Handled by the subclass; default is inert —
## except the runtime "call" verb (see configure), executed here.
func _confirm_verb(_e: Dictionary) -> void:
	var call: Callable = _e.get("call", Callable())
	if call.is_valid():
		call.call()


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
	# Runtime path first (param-driven menus): the caller's delete_call owns
	# the disk/file work; on success the row drops itself. Subclasses keep
	# their _delete_entry override (MapMenu files, …).
	var delete_call: Callable = e.get("delete_call", Callable())
	if delete_call.is_valid():
		var out := str(delete_call.call(_cursor))
		if out.is_empty():
			_notice("cannot delete %s" % e.get("label", "?"))
			return
		_notice(out)
		var idx := _entries.find(e)
		if idx != -1:
			runtime_entries.remove_at(idx)
		_refresh_list()
		return
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
