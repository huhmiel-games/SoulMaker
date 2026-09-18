extends Node

## Unified input layer for the maker tooling: translates raw keyboard and
## gamepad events into named actions via a data-driven mapping. Rebinding is a
## matter of editing this mapping (future: JSON override from the Options
## screen), never scattered across editor scripts.
##
## Souls-mirror convention (see concepts_and_docs/editor_input_mapping.md):
## the gamepad and the keyboard are the same device, mirroring the Elden Ring
## PC defaults as the shared layout:
##   gamepad    ──  keyboard
##   left stick ──  WASD        (editor: camera pan / edit translate)
##   right stick──  mouse       (editor: camera orbit / edit rotate)
##   d-pad      ──  arrows      (panel: tab + list navigation)
##   R1 (shift) ──  Shift held   (shifted chords; editor only)
##   A          ──  E           (place / confirm / select)
##   B          ──  Q           (back / deselect)
##   Y          ──  P           (playtest)
##   X          ──  Delete      (delete)
##   Start      ──  S           (quick-save)
##   R1+Start   ──  F2          (rename — dedicated key, no chord)
##   Guide      ──  Esc         (menu)
##
## Profiles let one action mean different things per context (editor vs
## playtest). Shift chords exist on both devices (R1-pad, Shift-key in the
## editor); the gamepad's limited set is the source of truth, the keyboard
## mirrors it 1:1 — no keyboard-only actions.

signal action_pressed(action: StringName)
signal action_released(action: StringName)

const DEVICE := 0
const DEADZONE := 0.2
## Mouse motion -> stick-units scale. Mouse is the right-stick parity but a
## per-frame delta, not an absolute -1..1 axis: this constant converts pixels
## into the same units the stick contributes, so both flow through the same
## analog path. Preserves the old per-event MOUSE_ORBIT_SENS=0.5 feel at 60fps.
const MOUSE_SCALE := 0.14
## Gamepad shift: Right Shoulder (R1).
const SHIFT_BUTTON := JOY_BUTTON_RIGHT_SHOULDER
## Keyboard shift mirror: physical Shift, editor profile only (playtest uses
## Shift to descend — profile-gating keeps that pristine). E is NOT a shift:
## E is the A-equivalent (pure confirm); doubling it as a modifier made it
## unusable (press confirms before hold can shift).
const KEYBOARD_SHIFT_MOD := KEY_SHIFT

const PROFILES := {
	"editor": {
		"cam_pan_left": {"key": KEY_A, "stick": JOY_AXIS_LEFT_X, "stick_sign": -1.0},
		"cam_pan_right": {"key": KEY_D, "stick": JOY_AXIS_LEFT_X, "stick_sign": 1.0},
		"cam_pan_fwd": {"key": KEY_W, "stick": JOY_AXIS_LEFT_Y, "stick_sign": -1.0},
		"cam_pan_back": {"key": KEY_S, "stick": JOY_AXIS_LEFT_Y, "stick_sign": 1.0},
		"cam_orbit_x": {"stick": JOY_AXIS_RIGHT_X, "mouse_x": true},
		"cam_orbit_y": {"stick": JOY_AXIS_RIGHT_Y, "mouse_y": true},
		"catalog_next": {"btn": JOY_BUTTON_DPAD_DOWN, "key": KEY_DOWN},
		"catalog_prev": {"btn": JOY_BUTTON_DPAD_UP, "key": KEY_UP},
		"tab_next": {"btn": JOY_BUTTON_DPAD_RIGHT, "key": KEY_RIGHT},
		"tab_prev": {"btn": JOY_BUTTON_DPAD_LEFT, "key": KEY_LEFT},
		"place_select": {"btn": JOY_BUTTON_A, "key": KEY_E},
		"deselect": {"btn": JOY_BUTTON_B, "key": KEY_Q},
		"delete_shifted": {"btn": JOY_BUTTON_B, "shifted": true},
		"delete_file": {"btn": JOY_BUTTON_X, "key": KEY_DELETE},
		"snap_toggle": {"btn": JOY_BUTTON_LEFT_SHOULDER, "key": KEY_TAB},
		"playtest": {"btn": JOY_BUTTON_Y, "key": KEY_P},
		"quick_save": {"btn": JOY_BUTTON_START, "key": KEY_S},
		"rename": {"btn": JOY_BUTTON_START, "shifted": true, "key": KEY_F2},
		"menu": {"btn": JOY_BUTTON_GUIDE, "key": KEY_ESCAPE},
	},
	"playtest": {
		"move_forward": {"key": KEY_W, "stick": JOY_AXIS_LEFT_Y, "stick_sign": -1.0},
		"move_back": {"key": KEY_S, "stick": JOY_AXIS_LEFT_Y, "stick_sign": 1.0},
		"move_left": {"key": KEY_A, "stick": JOY_AXIS_LEFT_X, "stick_sign": -1.0},
		"move_right": {"key": KEY_D, "stick": JOY_AXIS_LEFT_X, "stick_sign": 1.0},
		"move_up": {"key": KEY_SPACE},
		"move_down": {"key": KEY_SHIFT},
		"playtest": {"btn": JOY_BUTTON_Y, "key": KEY_P},
	},
}

var _active_profile := &"editor"

## Per-action edge/timing state, rebuilt every rendered frame from the active
## profile (see _process). Keyed by "<profile>/<action>" so switching profiles
## never leaks stale edges between them.
var _action_track: Dictionary = {}

## Mouse motion and wheel accumulated during the frame (filled in
## _unhandled_input, snapshot to the *_pub buffers in _process so consumers
## read a stable value per frame). Keyed to PROFILES entries via the mouse_x /
## mouse_y / wheel flags: motion is the right-stick parity, wheel the triggers
## parity.
var _mouse_buf := Vector2.ZERO
var _wheel_buf := 0.0
var _mouse_pub := Vector2.ZERO
var _wheel_pub := 0.0


func set_profile(profile: StringName) -> void:
	if not PROFILES.has(profile):
		push_warning("InputManager: unknown profile '%s'" % profile)
		return
	_active_profile = profile


func get_profile() -> StringName:
	return _active_profile


## Updates the per-action track once per rendered frame, before downstream
## nodes run their own _process. Read with is_just_pressed / is_just_released
## / time_held within the same frame. The mouse/wheel frame snapshot is
## published here too, then the accumulators reset for the next frame.
func _process(_delta: float) -> void:
	_mouse_pub = _mouse_buf
	_wheel_pub = _wheel_buf
	_mouse_buf = Vector2.ZERO
	_wheel_buf = 0.0
	var entries: Dictionary = PROFILES[_active_profile]
	var prefix := String(_active_profile) + "/"
	var now := Time.get_ticks_msec()
	for action_name in entries:
		var key := prefix + String(action_name)
		var track: Dictionary = _action_track.get(key, {})
		var was_pressed: bool = bool(track.get("pressed", false))
		var is_now_pressed := is_pressed(action_name)
		track["pressed"] = is_now_pressed
		track["just_pressed"] = is_now_pressed and not was_pressed
		track["just_released"] = not is_now_pressed and was_pressed
		if is_now_pressed and not was_pressed:
			track["t0"] = now
		_action_track[key] = track


## True only during the single frame in which an action became pressed
## (keyboard, gamepad button or bone-stick crossing the deadzone).
func is_just_pressed(action: StringName, profile := &"") -> bool:
	var t := _track_for(action, profile)
	return bool(t.get("just_pressed", false))


## True only during the single frame in which an action became unpressed.
func is_just_released(action: StringName, profile := &"") -> bool:
	var t := _track_for(action, profile)
	return bool(t.get("just_released", false))


## Seconds an action has been held down since its press frame; 0.0 while up.
func time_held(action: StringName, profile := &"") -> float:
	var t := _track_for(action, profile)
	if not bool(t.get("pressed", false)):
		return 0.0
	return float(Time.get_ticks_msec() - int(t.get("t0", 0))) / 1000.0


func _track_for(action: StringName, profile := &"") -> Dictionary:
	var prof := String(profile)
	if prof.is_empty():
		prof = String(_active_profile)
	return _action_track.get("%s/%s" % [prof, String(action)], {})


## True while the shift parity is active: R1 held on the gamepad, or Shift
## held on the keyboard in the editor profile. Gamepad shifted actions
## resolve only when this is true and R1 matches. The keyboard Shift is
## profile-gated so playtest (Shift = descend) stays pristine.
func is_shifted() -> bool:
	if Input.is_joy_button_pressed(DEVICE, SHIFT_BUTTON):
		return true
	return _active_profile == &"editor" and Input.is_physical_key_pressed(KEYBOARD_SHIFT_MOD)


## Polled check whether an action is currently down (keyboard, gamepad button
## or analog stick). Continuous actions (camera pan/orbit, playtest movement)
## are read with this.
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
	if int(e.get("stick", JOY_AXIS_INVALID)) != JOY_AXIS_INVALID:
		var sign: float = float(e.get("stick_sign", 1.0))
		if Input.get_joy_axis(DEVICE, int(e["stick"])) * sign > DEADZONE:
			return true
	var btn: int = int(e.get("btn", JOY_BUTTON_INVALID))
	if btn != JOY_BUTTON_INVALID:
		var shifted: bool = bool(e.get("shifted", false))
		if shifted == is_shifted() and Input.is_joy_button_pressed(DEVICE, btn):
			return true
	return false


## Continuous value of an action, in stick-like units (-1..1 for a full
## stick). All sources mapped on the entry sum up, with the same deadzone
## policy as the boolean reads:
##   "stick"    → raw axis × stick_sign, deadzone applied
##   "mouse_x"  → this frame's mouse motion X × MOUSE_SCALE (RS parity)
##   "mouse_y"  → this frame's mouse motion Y × MOUSE_SCALE
##   "triggers" → right minus left trigger (each deadzone applied)
## Camera orbit consumes this instead of polling devices directly.
func analog(action: StringName, profile := &"") -> float:
	var prof := String(profile)
	if prof.is_empty():
		prof = String(_active_profile)
	var entries: Dictionary = PROFILES.get(prof, {})
	if not entries.has(action):
		return 0.0
	var e: Dictionary = entries[action]
	var out := 0.0
	var stick := int(e.get("stick", JOY_AXIS_INVALID))
	if stick != JOY_AXIS_INVALID:
		out += _deadzone(
			Input.get_joy_axis(DEVICE, stick) * float(e.get("stick_sign", 1.0))
		)
	if bool(e.get("mouse_x", false)):
		out += _mouse_pub.x * MOUSE_SCALE
	if bool(e.get("mouse_y", false)):
		out += _mouse_pub.y * MOUSE_SCALE
	if bool(e.get("triggers", false)):
		out += triggers().y - triggers().x
	return out


## Signed wheel-notch count accumulated during this frame for an action mapped
## with "wheel": true (up = +1, down = -1 per notch). Wheel is a per-frame
## discrete feed, unlike the continuous analog() sources: the consumer applies
## each notch as one step instead of scaling it by delta.
func wheel_ticks(action: StringName, profile := &"") -> int:
	var prof := String(profile)
	if prof.is_empty():
		prof = String(_active_profile)
	var entries: Dictionary = PROFILES.get(prof, {})
	if not entries.has(action) or not bool(entries[action].get("wheel", false)):
		return 0
	return int(_wheel_pub)


## Left stick, deadzone applied. (Editor: camera pan / edit translate.)
func left_stick() -> Vector2:
	return _deadzone_vec(
		Input.get_joy_axis(DEVICE, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(DEVICE, JOY_AXIS_LEFT_Y),
	)


## Right stick, deadzone applied. (Editor: camera orbit / edit rotate.)
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


## Mouse motion is captured in _input, before GUI handling and SubViewports
## consume it: the editor camera lives inside a SubViewport whose ViewportContainer
## grabs motion (mouse_filter STOP), so _unhandled_input at the root would never
## see it. _input sees every event no matter the consumer. Wheel and buttons stay
## on _unhandled_input so UI consumption is respected.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_buf += (event as InputEventMouseMotion).relative


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
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_wheel_buf += 1.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_wheel_buf -= 1.0


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


## Keyboard keys map straight to their action. Because shifted actions carry
## their own dedicated keys on the keyboard (rename = F2), no shift chord is
## consulted here — parity lives on the gamepad buttons only.
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
