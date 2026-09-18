class_name ModalDialog
extends Control

## Reusable modal container (P1 map editor pause, quit-confirm, later
## editors' dialogs). Zero business logic: a dim backdrop + a centered panel
## hosting one GenericMenu content at a time. The content owns its entries and
## signals; the caller owns open/close and the semantics (see MapEditor).
## B/Q handling lives in the content (pause = cancel, confirm = back), never
## here — close() is explicit.

signal closed

@onready var content_host: Control = get_node("Center/Panel/ContentHost")

var _content: GenericMenu = null


func _ready() -> void:
	visible = false


func is_open() -> bool:
	return visible


## Shows content (takes ownership — freed on close/swap). Caller connects the
## content signals before/after open; both work (no emission happens here).
func open(content: GenericMenu) -> void:
	if _content != null and _content != content:
		content_host.remove_child(_content)
		_content.queue_free()
		_content = null
	_content = content
	if _content.get_parent() != content_host:
		content_host.add_child(_content)
	visible = true


func close() -> void:
	if _content != null:
		content_host.remove_child(_content)
		_content.queue_free()
		_content = null
	visible = false
	closed.emit()
