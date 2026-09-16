extends Node

## Unified input layer for the maker tooling: translates raw keyboard and
## gamepad events into named actions via a data-driven mapping. Rebinding is a
## matter of editing this mapping (future: JSON override from the Options
## screen), never scattered across editor scripts.
##
## Gamepad convention (Souls gesture pattern): R1 acts as a shift modifier —
## while held, the face buttons / d-pad switch to the "shifted" action set
## (transform ops). On keyboard the shifted actions simply carry their own
## dedicated keys, so no keyboard modifier is needed.
##
## Profiles let one action name mean different things per context
## (editor vs playtest vs menu later).

signal action_pressed(action: StringName)
signal action_released(action: StringName)

const DEVICE := 0
const DEADZONE := 0.2
const SHIFT_BUTTON := JOY_BUTTON_RIGHT_SHOULDER

const PROFILES := {
	"editor": {
		# Default set (gamepad: R1 released, keyboard: direct keys).
		"place_select": {"btn": JOY_BUTTON_A, "key": KEY_NONE},
		"deselect": {"btn": JOY_BUTTON_B, "key": KEY_NONE},
		"delete": {"btn": JOY_BUTTON_X, "key": KEY_DELETE},
		"playtest": {"btn": JOY_BUTTON_Y, "key": KEY_P},
		"catalog_next": {"btn": JOY_BUTTON_RIGHT_SHOULDER, "key": KEY_NONE},
		"catalog_prev": {"btn": JOY_BUTTON_LEFT_SHOULDER, "key": KEY_NONE},
		"nudge_x_neg": {"btn": JOY_BUTTON_DPAD_LEFT, "key": KEY_LEFT},
		"nudge_x_pos": {"btn": JOY_BUTTON_DPAD_RIGHT, "key": KEY_RIGHT},
		"nudge_z_neg": {"btn": JOY_BUTTON_DPAD_UP, "key": KEY_UP},
		"nudge_z_pos": {"btn": JOY_BUTTON_DPAD_DOWN, "key": KEY_DOWN},
		"fine_mode": {"btn": JOY_BUTTON_LEFT_STICK, "key": KEY_SHIFT},
		"quick_save": {"btn": JOY_BUTTON_START, "key": KEY_S},
		"load_map": {"btn": JOY_BUTTON_BACK, "key": KEY_L},
		"menu": {"btn": JOY_BUTTON_GUIDE, "key": KEY_ESCAPE},
		# Shifted set (gamepad: R1 held, keyboard: dedicated keys).
		"nudge_y_pos": {"btn": JOY_BUTTON_DPAD_UP, "shifted": true, "key": KEY_PAGEUP},
		"nudge_y_neg": {"btn": JOY_BUTTON_DPAD_DOWN, "shifted": true, "key": KEY_PAGEDOWN},
		"cycle_xform": {"btn": JOY_BUTTON_A, "shifted": true, "key": KEY_TAB},
		"reset_xform": {"btn": JOY_BUTTON_B, "shifted": true, "key": KEY_NONE},
		"toggle_snap": {"btn": JOY_BUTTON_Y, "shifted": true, "key": KEY_NONE},
		"duplicate": {"btn": JOY_BUTTON_X, "shifted": true, "key": KEY_NONE},
		"delete_all": {"btn": JOY_BUTTON_BACK, "shifted": true, "key": KEY_NONE},
	},
	"playtest": {
		"move_forward": {"axis": JOY_AXIS_LEFT_Y, "axis_sign": -1.0, "key": KEY_W},
		"move_back": {"axis": JOY_AXIS_LEFT_Y, "axis_sign": 1.0, "key": KEY_S},
		"move_left": {"axis": JOY_AXIS_LEFT_X, "axis_sign": -1.0, "key": KEY_A},
		"move_right": {"axis": JOY_AXIS_LEFT_X, "axis_sign": 1.0, "key": KEY_D},
		"move_up": {"key": KEY_SPACE},
		"move_down": {"key": KEY_SHIFT},
		"playtest": {"btn": JOY_BUTTON_Y, "key": KEY_P},
	},
}

var _active_profile := &"editor"


func set_profile(profile: StringName) -> void:
	if not PROFILES.has(profile):
		push_warning("InputManager: unknown profile '%s'" % profile)
		return
	_active_profile = profile


func get_profile() -> StringName:
	return _active_profile


## True while the gamepad shift modifier (R1) is held.
func is_shifted() -> bool:
	return Input.is_joy_button_pressed(DEVICE, SHIFT_BUTTON)


## Polled check whether an action is currently down (keyboard, gamepad button
## or analog axis, honouring the shift modifier). Used for continuous actions
## (nudge, movement, fine mode).
func is_pressed(action: StringName, profile := &"") -> bool:
	var prof := String(profile)
	if prof.is_empty():
		prof = String(_active_profile)
	var entries: Dictionary = PROFILES.get(prof, {})
	if not entries.has(action):
		return false
	var e: Dictionary = entries[action]
	if int(e.get("key", KEY_NONE)) != KEY_NONE and Input.is_physical_key_pressed(int(e["key"])):
		return true
	if int(e.get("axis", JOY_AXIS_INVALID)) != JOY_AXIS_INVALID:
		var sign: float = float(e.get("axis_sign", 1.0))
		if Input.get_joy_axis(DEVICE, int(e["axis"])) * sign > DEADZONE:
			return true
	var btn: int = int(e.get("btn", JOY_BUTTON_INVALID))
	if btn != JOY_BUTTON_INVALID:
		var shifted: bool = bool(e.get("shifted", false))
		if shifted == is_shifted() and Input.is_joy_button_pressed(DEVICE, btn):
			return true
	return false


## Left stick, deadzone applied. (Unshifted: camera pan.)
func left_stick() -> Vector2:
	return _deadzone_vec(
		Input.get_joy_axis(DEVICE, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(DEVICE, JOY_AXIS_LEFT_Y),
	)


## Right stick, deadzone applied. (Unshifted: camera orbit.)
func right_stick() -> Vector2:
	return _deadzone_vec(
		Input.get_joy_axis(DEVICE, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(DEVICE, JOY_AXIS_RIGHT_Y),
	)


## Trigger values (left, right), deadzone applied per axis.
func triggers() -> Vector2:
	return Vector2(
		_deadzone(Input.get_joy_axis(DEVICE, JOY_AXIS_TRIGGER_LEFT)),
		_deadzone(Input.get_joy_axis(DEVICE, JOY_AXIS_TRIGGER_RIGHT)),
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		var action := _resolve_joy_button(button.button_index)
		if not action.is_empty():
			if button.pressed:
				action_pressed.emit(action)
			else:
				action_released.emit(action)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.echo:
			var action := _resolve_key(key.physical_keycode)
			if not action.is_empty():
				if key.pressed:
					action_pressed.emit(action)
				else:
					action_released.emit(action)


func _resolve_joy_button(button_index: int) -> StringName:
	var entries: Dictionary = PROFILES[_active_profile]
	var shift: bool = Input.is_joy_button_pressed(DEVICE, SHIFT_BUTTON)
	for action in entries:
		var e: Dictionary = entries[action]
		if int(e.get("btn", JOY_BUTTON_INVALID)) != button_index:
			continue
		if bool(e.get("shifted", false)) == shift:
			return action
	return &""


func _resolve_key(keycode: int) -> StringName:
	var entries: Dictionary = PROFILES[_active_profile]
	for action in entries:
		var e: Dictionary = entries[action]
		if int(e.get("key", KEY_NONE)) == keycode:
			return action
	return &""


func _deadzone(value: float) -> float:
	return value if absf(value) >= DEADZONE else 0.0


func _deadzone_vec(x: float, y: float) -> Vector2:
	var v := Vector2(_deadzone(x), _deadzone(y))
	return v if v.length() > DEADZONE else Vector2.ZERO