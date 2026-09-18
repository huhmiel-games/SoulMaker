extends Control
class_name EditorHUD
## Shared editor overlay: three zones with three lifetimes.
## - PERSISTENT (status line): facts that must always be visible (snap state
##   today, grid/layer/… tomorrow). A keyed registry: set_persistent(key,
##   text) / clear_persistent(key); the line renders the values joined by
##   " · " in insertion order. Adding a new permanent fact is one editor-side
##   line — never a HUD change.
## - TRANSIENT (toast line): flash(msg, duration) shows a temporary note
##   (save confirmations) then clears itself. Never overwrites persistent.
## - COMMANDS (hint line): set_hint/clear_hint, what the inputs do right now.
## Display-only: the whole subtree ignores the mouse, identically on every
## device (parity — hints never capture clicks). Wording stays with the
## editors; this node only shows text.

const FLASH_DEFAULT := 5.0

@onready var status_label: Label = get_node("StatusLabel")
@onready var toast_label: Label = get_node("ToastLabel")
@onready var hint_label: Label = get_node("HintLabel")

var _persistent: Dictionary = {}
var _flash_seq := 0


func set_persistent(key: StringName, text: String) -> void:
	_persistent[key] = text
	_render_persistent()


func clear_persistent(key: StringName) -> void:
	_persistent.erase(key)
	_render_persistent()


func _render_persistent() -> void:
	if status_label != null:
		status_label.text = " · ".join(_persistent.values())


func flash(msg: String, duration: float = FLASH_DEFAULT) -> void:
	if toast_label == null:
		return
	_flash_seq += 1
	var seq := _flash_seq
	toast_label.text = msg
	await get_tree().create_timer(duration).timeout
	if seq == _flash_seq and toast_label != null:
		toast_label.text = ""


func set_hint(text: String) -> void:
	if hint_label != null:
		hint_label.text = text


func clear_hint() -> void:
	if hint_label != null:
		hint_label.text = ""
