class_name CatalogPanel
extends ScrollContainer

## Editor catalog panel (P1 map editor): one button per catalog entry, sorted
## by manifest order. The `asset_selected` signal carries the catalog id.
## `current_id` tracks the focused entry so the gamepad can cycle (LB/RB) and
## place (A) without a mouse.

signal asset_selected(id: String)

## Attach point for the entry list — must exist in the scene scaffold.
@onready var entry_list: VBoxContainer = get_node("EntryList")

## Catalog id currently highlighted as the gamepad "current entry".
var current_id: String = ""

var _buttons: Dictionary = {}


func _ready() -> void:
	pass


## Rebuilds the buttons from the loaded catalog. Keeps existing rows if the
## catalog contents match (cheap refresh during the same session).
func populate(catalog: Catalog) -> void:
	for child in entry_list.get_children():
		child.queue_free()
	_buttons.clear()
	current_id = ""
	if not catalog.order.is_empty():
		current_id = catalog.order[0]
	for id in catalog.order:
		var entry: Dictionary = catalog.entry(id)
		var name: String = str(entry.get("name", id))
		var button := Button.new()
		button.text = "%s\n%s" % [name, id]
		button.tooltip_text = "%s — %s" % [str(entry.get("category", "?")), str(entry.get("source", ""))]
		button.custom_minimum_size = Vector2(0.0, 54.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: asset_selected.emit(id))
		_buttons[id] = button
		entry_list.add_child(button)
	_highlight_current()


func cycle_next() -> void:
	_cycle(1)


func cycle_prev() -> void:
	_cycle(-1)


func _cycle(direction: int) -> void:
	var ids := _buttons.keys()
	if ids.is_empty():
		return
	var idx := ids.find(current_id)
	if idx < 0:
		idx = 0
	idx = posmod(idx + direction, ids.size())
	current_id = String(ids[idx])
	_highlight_current()
	_scroll_to_current()


func _highlight_current() -> void:
	for id in _buttons:
		(_buttons[id] as Button).modulate = Color(1.0, 1.0, 1.0, 0.6)
	if current_id != "" and _buttons.has(current_id):
		(_buttons[current_id] as Button).modulate = Color.WHITE


func _scroll_to_current() -> void:
	if current_id == "" or not _buttons.has(current_id):
		return
	var vscroll := get_v_scroll_bar()
	var target := (_buttons[current_id] as Button).position.y
	vscroll.value = clampf(target, vscroll.min_value, vscroll.max_value)