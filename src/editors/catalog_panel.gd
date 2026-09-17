class_name CatalogPanel
extends VBoxContainer

## Editor catalog panel (P1 map editor): category tabs at the top, one button
## per catalog entry in the selected category. The `asset_selected` signal
## carries the catalog id. `current_id` tracks the focused entry so the gamepad
## can cycle (D-pad up/down within tab, left/right across tabs) and place (A)
## without a mouse.

signal asset_selected(id: String)

## Attach points — must exist in the scene scaffold.
@onready var tab_bar: HBoxContainer = get_node("TabBar")
@onready var scroll: ScrollContainer = get_node("ScrollContainer")
@onready var entry_list: VBoxContainer = get_node("ScrollContainer/EntryList")

## Catalog id currently highlighted as the gamepad "current entry".
var current_id: String = ""
## Currently selected category tab (empty = "All").
var current_category: String = ""

var _buttons: Dictionary = {}
## Maps asset id → its catalog entry dict (for category lookup).
var _entry_data: Dictionary = {}
## Maps category name → Button node (for tab bar).
var _tab_buttons: Dictionary = {}
## Ordered list of available categories (only those with assets).
var _categories: PackedStringArray = []
## Asset ids in the current tab's display order.
var _filtered_ids: PackedStringArray = []


func _ready() -> void:
	pass


## Rebuilds tabs and buttons from the loaded catalog.
func populate(catalog: Catalog) -> void:
	# Wipe previous state.
	for child in entry_list.get_children():
		child.queue_free()
	for child in tab_bar.get_children():
		child.queue_free()
	_buttons.clear()
	_entry_data.clear()
	_tab_buttons.clear()
	_filtered_ids.clear()
	current_id = ""
	current_category = ""

	# Tab order = the full schema taxonomy (empty tabs are kept so tab
	# navigation stays testable while the catalog is single-category), plus
	# any extra category discovered in the data (defensive, schema rejects
	# unknowns anyway).
	_categories.clear()
	for cat in Catalog.CATEGORIES:
		_categories.append(cat)
	var cat_seen: Dictionary = {}
	for id in catalog.order:
		var cat: String = str(catalog.entry(id).get("category", "other"))
		cat_seen[cat] = true
		if not _categories.has(cat):
			_categories.append(cat)

	# Build tab bar.
	_build_tabs()

	# Build all buttons (hidden initially, shown by _apply_tab_filter).
	for id in catalog.order:
		var entry: Dictionary = catalog.entry(id)
		var name: String = str(entry.get("name", id))
		var button := Button.new()
		button.text = "%s\n%s" % [name, id]
		button.tooltip_text = "%s — %s" % [str(entry.get("category", "?")), str(entry.get("source", ""))]
		button.custom_minimum_size = Vector2(0.0, 54.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: asset_selected.emit(id))
		_buttons[id] = button
		_entry_data[id] = entry
		entry_list.add_child(button)

	# Default tab = the first category that has assets (a fresh launch lands
	# on a usable tab); fall back to the first tab when the catalog is empty.
	current_category = ""
	for cat in _categories:
		if cat_seen.has(cat):
			current_category = cat
			break
	if current_category.is_empty() and _categories.size() > 0:
		current_category = _categories[0]
	if current_category != "" and _tab_buttons.has(current_category):
		_tab_buttons[current_category].button_pressed = true
	_apply_tab_filter()
	# Pick the first filtered asset as current.
	if not _filtered_ids.is_empty():
		current_id = _filtered_ids[0]
	_highlight_current()


## ── tabs ───────────────────────────────────────────────────────────────


func _build_tabs() -> void:
	for cat in _categories:
		var btn := Button.new()
		btn.text = _category_label(cat)
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0.0, 28.0)
		var cat_copy: String = cat
		btn.pressed.connect(func() -> void: _select_tab(cat_copy))
		_tab_buttons[cat] = btn
		tab_bar.add_child(btn)


## Human-readable label for a category key.
func _category_label(cat: String) -> String:
	match cat:
		"prop_natural": return "Nature"
		"architecture": return "Arch"
		"light": return "Light"
		"enemy_character": return "Enemy"
		"clothing": return "Cloth"
		"equipment": return "Equip"
		"animation": return "Anim"
		"prefab": return "Prefab"
		"material": return "Mat"
		_: return cat


func next_tab() -> void:
	if _categories.size() <= 1:
		return
	var idx := _categories.find(current_category)
	idx = posmod(idx + 1, _categories.size())
	_select_tab(_categories[idx])


func prev_tab() -> void:
	if _categories.size() <= 1:
		return
	var idx := _categories.find(current_category)
	idx = posmod(idx - 1, _categories.size())
	_select_tab(_categories[idx])


func _select_tab(cat: String) -> void:
	if cat == current_category:
		return
	# Unpress the old tab button.
	if _tab_buttons.has(current_category):
		_tab_buttons[current_category].button_pressed = false
	current_category = cat
	_tab_buttons[cat].button_pressed = true
	_apply_tab_filter()
	# Pick the first filtered asset as the new current.
	if not _filtered_ids.is_empty():
		current_id = _filtered_ids[0]
	else:
		current_id = ""
	_highlight_current()
	_scroll_to_current()


func _apply_tab_filter() -> void:
	_filtered_ids.clear()
	for id in _buttons:
		var btn := _buttons[id] as Button
		var cat: String = str(_entry_data.get(id, {}).get("category", "other"))
		var visible: bool = cat == current_category
		btn.visible = visible
		if visible:
			_filtered_ids.append(id)


## ── asset cycling (within current tab) ────────────────────────────────


func cycle_next() -> void:
	_cycle(1)


func cycle_prev() -> void:
	_cycle(-1)


func _cycle(direction: int) -> void:
	if _filtered_ids.is_empty():
		return
	var idx := _filtered_ids.find(current_id)
	if idx < 0:
		idx = 0
	idx = posmod(idx + direction, _filtered_ids.size())
	current_id = _filtered_ids[idx]
	_highlight_current()
	_scroll_to_current()


## ── highlight & scroll ────────────────────────────────────────────────


func _highlight_current() -> void:
	for id in _buttons:
		(_buttons[id] as Button).modulate = Color(1.0, 1.0, 1.0, 0.6)
	if current_id != "" and _buttons.has(current_id):
		(_buttons[current_id] as Button).modulate = Color.WHITE


func _scroll_to_current() -> void:
	if current_id == "" or not _buttons.has(current_id):
		return
	var btn := _buttons[current_id] as Button
	var vscroll := scroll.get_v_scroll_bar()
	var target := btn.position.y + btn.size.y * 0.5
	vscroll.value = clampf(target - vscroll.size.y * 0.5, vscroll.min_value, vscroll.max_value)
