extends Node

## Unified input layer: translates raw keyboard/mouse and gamepad events into
## named actions via a data-driven mapping. Rebinding is a matter of editing
## this mapping (future: JSON override from the Options screen), never
## scattered across scripts.
##
## Device parity is the standing rule (see AGENTS.md ## Input): the gamepad
## and keyboard/mouse are the same logical device. The gamepad defines the
## CAPABILITIES (source of truth); the keyboard mirrors them 1:1 — extra
## mirrors of an existing capability are allowed (Q = the d-pad pair,
## Shift+LMB = R2), new capabilities are not. No raw Input.* polling and no
## device-specific paths outside this file (enforced by input_audit.gd).
##
## Frozen keyboard layout (features/11 wins over DS3 PC where they conflict;
## DS3 fills the gaps — see concepts_and_docs/editor_input_mapping.md):
##   gamepad    ──  keyboard
##   left stick ──  WASD                 (move; no keyboard walk — Alt is offhand)
##   right stick──  mouse motion         (camera orbit)
##   d-pad      ──  arrows               (spells / items / weapons)
##   A / B      ──  E / Space            (interact / dodge — per-profile mirrors:
##                                       B is Q in editor/menus, Space in game)
##   X / Y      ──  R / F                (use item / two-hand)
##   R1 / R2    ──  LMB / RMB+Shift+LMB  (light / heavy)
##   L1         ──  Shift held           (guard)
##   L2         ──  Alt+RMB              (offhand skill / parry)
##   R3         ──  middle mouse         (lock-on, tap)
##   Start+Guide──  Esc                  (menu)
##   Select     ──  G                    (gestures, mapped-not-consumed)
##   Q          ──  (mirror-only)        (quickbar cycle, consumed at P8)
## Editor-only keys (frozen separately): Tab (snap), F2 (rename), P (floor),
## S (pause), Delete (menu delete). X sorts at P8.
##
## Resolution rules:
## - An action = a list of sources ({"key"}, {"btn"}, {"mouse"},
##   {"trigger"}, {"stick"}), OR-ed. Keys are shift-blind AND mod-blind: they
##   match the physical key alone — chords redirect consumer-side (Shift+Q
##   lands on deselect, the handler deletes; this is why delete_shifted needs
##   no key source). Buttons/mouse/triggers are shift-aware ("shifted" must
##   equal is_shifted()) and take an optional "mod" key (Alt+RMB skill).
## - Overlapping sources (RMB = heavy plain AND skill with Alt) both fire;
##   the consumer prioritizes by convention (mod wins).
## - Movement keys ignore Shift (pass-through): holding Shift to pre-arm a
##   strong attack never stops WASD.
##
## Profiles let one action mean different things per context (editor vs game).
## Shift chords exist on both devices in the editor (R1-pad, Shift-key); in
## game the pad has no shift role (R1 taps light attack) — only Shift-key
## chords remain (heavy).

signal action_pressed(action: StringName)
signal action_released(action: StringName)

const DEVICE := 0
const DEADZONE := 0.2
## Trigger-as-button threshold: R2/L2 only count pressed past half pull, so
## resting fingers never throw heavies or skills.
const TRIGGER_THRESHOLD := 0.5
## Mouse motion -> stick-units scale. Mouse is the right-stick parity but a
## per-frame delta, not an absolute -1..1 axis: this constant converts pixels
## into the same units the stick contributes, so both flow through the same
## analog path. Preserves the old per-event MOUSE_ORBIT_SENS=0.5 feel at 60fps.
const MOUSE_SCALE := 0.14
## Gamepad shift: Right Shoulder (R1), editor profile only — in game R1 taps
## light attack, there is no pad shift role. The keyboard Shift is the chord
## modifier in every profile (editor R1-mirror, game heavy-modifier).
const SHIFT_BUTTON := JOY_BUTTON_RIGHT_SHOULDER
const KEYBOARD_SHIFT_MOD := KEY_SHIFT

const PROFILES := {
	"editor": {
		"cam_pan_left": {"sources": [{"key": KEY_A}, {"stick": JOY_AXIS_LEFT_X, "stick_sign": -1.0}]},
		"cam_pan_right": {"sources": [{"key": KEY_D}, {"stick": JOY_AXIS_LEFT_X, "stick_sign": 1.0}]},
		"cam_pan_fwd": {"sources": [{"key": KEY_W}, {"stick": JOY_AXIS_LEFT_Y, "stick_sign": -1.0}]},
		"cam_pan_back": {"sources": [{"key": KEY_S}, {"stick": JOY_AXIS_LEFT_Y, "stick_sign": 1.0}]},
		"cam_orbit_x": {"sources": [], "stick": JOY_AXIS_RIGHT_X, "mouse_x": true},
		"cam_orbit_y": {"sources": [], "stick": JOY_AXIS_RIGHT_Y, "mouse_y": true},
		"catalog_next": {"sources": [{"key": KEY_DOWN}, {"btn": JOY_BUTTON_DPAD_DOWN}]},
		"catalog_prev": {"sources": [{"key": KEY_UP}, {"btn": JOY_BUTTON_DPAD_UP}]},
		"tab_next": {"sources": [{"key": KEY_RIGHT}, {"btn": JOY_BUTTON_DPAD_RIGHT}]},
		"tab_prev": {"sources": [{"key": KEY_LEFT}, {"btn": JOY_BUTTON_DPAD_LEFT}]},
		"place_select": {"sources": [{"key": KEY_E}, {"btn": JOY_BUTTON_A}]},
		"deselect": {"sources": [{"key": KEY_Q}, {"btn": JOY_BUTTON_B}]},
		# No key source: Shift+Q lands shift-blind on deselect and the
		# handler redirects (same consumer-side chord pattern as E/confirm).
		"delete_shifted": {"sources": [{"btn": JOY_BUTTON_B, "shifted": true}]},
		"delete_file": {"sources": [{"key": KEY_DELETE}, {"btn": JOY_BUTTON_X}]},
		"snap_toggle": {"sources": [{"key": KEY_TAB}, {"btn": JOY_BUTTON_LEFT_SHOULDER}]},
		"floor_mode": {"sources": [{"key": KEY_P}, {"btn": JOY_BUTTON_Y}]},
		# No key source: S belongs to WASD (cam_pan_back) — sharing it made
		# every S press open the pause instead of panning. Keyboard pauses
		# with Esc (menu action), same gesture.
		"pause_menu": {"sources": [{"btn": JOY_BUTTON_START}]},
		"rename": {"sources": [{"key": KEY_F2}, {"btn": JOY_BUTTON_START, "shifted": true}]},
		"menu": {"sources": [{"key": KEY_ESCAPE}, {"btn": JOY_BUTTON_GUIDE}]},
	},
	# Frozen game table (features/11 + DS3 gaps). Defined but NOT consumed
	# until the P2 player controller — input_audit.gd still validates it.
	"game": {
		"move_forward": {"sources": [{"key": KEY_W}, {"stick": JOY_AXIS_LEFT_Y, "stick_sign": -1.0}]},
		"move_back": {"sources": [{"key": KEY_S}, {"stick": JOY_AXIS_LEFT_Y, "stick_sign": 1.0}]},
		"move_left": {"sources": [{"key": KEY_A}, {"stick": JOY_AXIS_LEFT_X, "stick_sign": -1.0}]},
		"move_right": {"sources": [{"key": KEY_D}, {"stick": JOY_AXIS_LEFT_X, "stick_sign": 1.0}]},
		"cam_orbit_x": {"sources": [], "stick": JOY_AXIS_RIGHT_X, "mouse_x": true},
		"cam_orbit_y": {"sources": [], "stick": JOY_AXIS_RIGHT_Y, "mouse_y": true},
		"dodge": {"sources": [{"key": KEY_SPACE}, {"btn": JOY_BUTTON_B}]},
		"attack_light": {"sources": [{"mouse": MOUSE_BUTTON_LEFT}, {"btn": JOY_BUTTON_RIGHT_SHOULDER}]},
		"attack_heavy": {"sources": [{"mouse": MOUSE_BUTTON_RIGHT}, {"mouse": MOUSE_BUTTON_LEFT, "shifted": true}, {"trigger": "right"}]},
		"guard": {"sources": [{"key": KEY_SHIFT}, {"btn": JOY_BUTTON_LEFT_SHOULDER}]},
		# Alt+RMB overlaps heavy's plain RMB: both fire, the consumer
		# prioritizes (mod wins) — see header.
		"offhand_skill": {"sources": [{"mouse": MOUSE_BUTTON_RIGHT, "mod": KEY_ALT}, {"trigger": "left"}]},
		"two_hand": {"sources": [{"key": KEY_F}, {"btn": JOY_BUTTON_Y}]},
		"use_item": {"sources": [{"key": KEY_R}, {"btn": JOY_BUTTON_X}]},
		"interact": {"sources": [{"key": KEY_E}, {"btn": JOY_BUTTON_A}]},
		"cycle_spell": {"sources": [{"key": KEY_UP}, {"btn": JOY_BUTTON_DPAD_UP}]},
		"cycle_item": {"sources": [{"key": KEY_DOWN}, {"btn": JOY_BUTTON_DPAD_DOWN}]},
		"cycle_rhand": {"sources": [{"key": KEY_RIGHT}, {"btn": JOY_BUTTON_DPAD_RIGHT}]},
		"cycle_lhand": {"sources": [{"key": KEY_LEFT}, {"btn": JOY_BUTTON_DPAD_LEFT}]},
		# Mirror-only: Q re-exposes the d-pad spell/item capability, no new
		# capability, consumed with the quickbar at P8.
		"quickbar_cycle": {"sources": [{"key": KEY_Q}], "mirror_only": true},
		"lock_on": {"sources": [{"mouse": MOUSE_BUTTON_MIDDLE}, {"btn": JOY_BUTTON_RIGHT_STICK}]},
		"menu": {"sources": [{"key": KEY_ESCAPE}, {"btn": JOY_BUTTON_START}, {"btn": JOY_BUTTON_GUIDE}]},
		"gestures": {"sources": [{"key": KEY_G}, {"btn": JOY_BUTTON_BACK}]},
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
## Mouse button held state ({button_index: bool}), filled in
## _unhandled_input so UI consumption is respected, polled per frame like
## every other source.
var _mouse_buttons := {}


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
		# Central edge emission: every source (key, pad, mouse, trigger)
		# flows through the same per-frame track, so signals stay unified
		# with the is_just_pressed reads. Autoloads process before scene
		# nodes, so consumers see signal and poll state in the same frame.
		if bool(track["just_pressed"]):
			action_pressed.emit(StringName(action_name))
		elif bool(track["just_released"]):
			action_released.emit(StringName(action_name))


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


## True while the shift parity is active: R1 held on the gamepad in the
## editor profile, or Shift held on the keyboard in any profile. E is NOT a
## shift: E is the A-equivalent (pure confirm); doubling it as a modifier
## made it unusable (press confirms before hold can shift).
func is_shifted() -> bool:
	if _active_profile == &"editor" and Input.is_joy_button_pressed(DEVICE, SHIFT_BUTTON):
		return true
	return Input.is_physical_key_pressed(KEYBOARD_SHIFT_MOD)


## Polled check whether an action is currently down: true if ANY of its
## sources is down (see header for the shift/mod rules per source kind).
func is_pressed(action: StringName, profile := &"") -> bool:
	var entries: Dictionary = _entries_for(profile)
	if not entries.has(action):
		return false
	var e: Dictionary = entries[action]
	for s in e.get("sources", []):
		if _source_pressed(s):
			return true
	return false


## One binding of an action (see header): keys match shift-blind and
## mod-blind (consumer-side chord redirect); buttons, mouse buttons and
## triggers require their "shifted" flag to equal is_shifted() plus their
## optional "mod" key held; sticks apply the deadzone.
func _source_pressed(s: Dictionary) -> bool:
	if s.has("key"):
		return Input.is_physical_key_pressed(int(s["key"]))
	if bool(s.get("shifted", false)) != is_shifted():
		return false
	var mod := int(s.get("mod", KEY_NONE))
	if mod != KEY_NONE and not Input.is_physical_key_pressed(mod):
		return false
	if s.has("btn"):
		return Input.is_joy_button_pressed(DEVICE, int(s["btn"]))
	if s.has("mouse"):
		return bool(_mouse_buttons.get(int(s["mouse"]), false))
	if s.has("trigger"):
		var axis := JOY_AXIS_TRIGGER_RIGHT if str(s["trigger"]) == "right" else JOY_AXIS_TRIGGER_LEFT
		return Input.get_joy_axis(DEVICE, axis) > TRIGGER_THRESHOLD
	if s.has("stick"):
		var sign: float = float(s.get("stick_sign", 1.0))
		return Input.get_joy_axis(DEVICE, int(s["stick"])) * sign > DEADZONE
	return false


func _entries_for(profile := &"") -> Dictionary:
	var prof := String(profile)
	if prof.is_empty():
		prof = String(_active_profile)
	return PROFILES.get(prof, {})


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
## on _unhandled_input so UI consumption is respected. Edges are NOT emitted
## here: _process polls every source (including this button state) and emits
## centrally, so keys, pad, mouse and triggers share one timing.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_buf += (event as InputEventMouseMotion).relative


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_wheel_buf += 1.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_wheel_buf -= 1.0
		else:
			_mouse_buttons[mb.button_index] = mb.pressed


func _deadzone(value: float) -> float:
	return value if absf(value) >= DEADZONE else 0.0


func _deadzone_vec(x: float, y: float) -> Vector2:
	var v := Vector2(_deadzone(x), _deadzone(y))
	return v if v.length() > DEADZONE else Vector2.ZERO
