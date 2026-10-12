class_name ConfirmDialog
extends Control

## True OK/CANCEL dialog for ModalDialog (face-confirm, later editors').
## Layout lives in confirm_dialog.tscn (editable): centered title, static
## centered message (never a selectable row), OK / CANCEL on one centered
## line. Left/Right or Up/Down flips between the buttons, A/E confirms,
## B cancels. Cursor defaults to CANCEL (safe choice). Device parity comes
## free: every action resolves through the named InputManager action, like
## every other menu.
## Configure BEFORE add_child (same contract as GenericMenu.configure).

var _title := ""
var _message := ""
var _ok_label := "OK"
var _cancel_label := "CANCEL"
var _on_ok := Callable()
var _on_cancel := Callable()
var _cursor := 1 # CANCEL by default
var _buttons: Array[Label] = []

@onready var _title_label: Label = get_node("VBox/Title")
@onready var _message_label: Label = get_node("VBox/Message")
@onready var _ok_button: Label = get_node("VBox/Buttons/OK")
@onready var _cancel_button: Label = get_node("VBox/Buttons/Cancel")


func configure(title: String, message: String, on_ok: Callable, on_cancel: Callable, ok_label := "OK", cancel_label := "CANCEL") -> void:
	_title = title
	_message = message
	_on_ok = on_ok
	_on_cancel = on_cancel
	_ok_label = ok_label
	_cancel_label = cancel_label
	if is_node_ready():
		_apply_texts()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	InputManager.action_pressed.connect(_on_input_action)
	_apply_texts()
	_highlight_current()


func _apply_texts() -> void:
	_title_label.text = _title
	_message_label.text = _message
	_ok_button.text = _ok_label
	_cancel_button.text = _cancel_label
	_buttons = [_ok_button, _cancel_button]


func _highlight_current() -> void:
	for b in _buttons:
		b.modulate = Color(1.0, 1.0, 1.0, 0.6)
	if _cursor >= 0 and _cursor < _buttons.size():
		_buttons[_cursor].modulate = Color.WHITE


func _on_input_action(action: StringName) -> void:
	match action:
		&"catalog_next", &"catalog_prev", &"tab_next", &"tab_prev":
			_cursor = posmod(_cursor + 1, 2)
			_highlight_current()
		&"place_select":
			if _cursor == 0:
				if _on_ok.is_valid():
					_on_ok.call()
			else:
				if _on_cancel.is_valid():
					_on_cancel.call()
		&"deselect":
			if _on_cancel.is_valid():
				_on_cancel.call()
