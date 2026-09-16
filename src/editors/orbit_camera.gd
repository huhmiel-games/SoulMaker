class_name OrbitCamera
extends Camera3D

## Editor orbiting camera (P1 map editor): orbit on right-drag, zoom on wheel,
## pan on middle-drag. The camera pivots around a focus point on a horizontal
## plane; vertical orbit is clamped so the ground stays readable. Left click is
## left for placement/selection (handled by the editor controller).

const DEFAULT_FOCUS := Vector3(0.0, 0.0, 0.0)
const MIN_DISTANCE := 0.5
const MAX_DISTANCE := 120.0
const MIN_PITCH := -80.0
const MAX_PITCH := 80.0

## Current distance from the focus point.
var distance: float = 18.0
## Focus point the camera orbits around.
var focus: Vector3 = DEFAULT_FOCUS

var _orbit_angle := 45.0
var _pitch_angle := 35.0
var _dragging_orbit := false
var _dragging_pan := false
var _orbit_moved := false


func _ready() -> void:
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging_orbit = mb.pressed
			if not mb.pressed:
				_orbit_moved = false
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_pan = mb.pressed
			if mb.pressed:
				Input.set_default_cursor_shape(Input.CURSOR_MOVE)
			else:
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(-1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.0)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging_orbit:
			_orbit(mm.relative)
			if mm.relative != Vector2.ZERO:
				_orbit_moved = true
		elif _dragging_pan:
			_pan(mm.relative)


func _process(delta: float) -> void:
	# Keyboard coarse pan (arrow keys) as a fallback for headless testing.
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if input != Vector2.ZERO:
		var right := _camera_right()
		var fwd := _camera_forward_flat()
		focus += right * input.x * distance * delta
		focus += fwd * input.y * distance * delta
		_apply_transform()

	# Gamepad (only while this camera is the live one): LS pans, RS orbits,
	# triggers zoom.
	if current:
		_pan_analog(InputManager.left_stick(), delta)
		_orbit_analog(InputManager.right_stick(), delta)
		_zoom_analog(InputManager.triggers(), delta)


func _pan_analog(stick: Vector2, delta: float) -> void:
	if stick == Vector2.ZERO:
		return
	# Camera-relative movement along the real view vector (pitch included):
	# LS up follows exactly where the camera looks, even toward the ground.
	var right := global_basis.x
	var fwd := -global_basis.z
	focus += (right * stick.x + fwd * -stick.y) * distance * 0.8 * delta
	_apply_transform()


func _orbit_analog(stick: Vector2, delta: float) -> void:
	if stick == Vector2.ZERO:
		return
	# Gamepad orbit pivots the camera around ITSELF (turret-like): the focus is
	# re-glued ahead of the view so the camera stays in place while turning.
	# Yaw and pitch are non-inverted (RS right = turn right, RS up = look up —
	# Souls convention); the option to invert arrives with Options (feature 11).
	_orbit(Vector2(-stick.x, -stick.y) * 220.0 * delta, true)


func _zoom_analog(triggers: Vector2, delta: float) -> void:
	var amount := triggers.y - triggers.x
	if absf(amount) < 0.001:
		return
	_zoom(-amount * 2.0 * delta)


func _zoom(steps: float) -> void:
	distance = clampf(distance * pow(0.85, steps), MIN_DISTANCE, MAX_DISTANCE)
	_apply_transform()


func _orbit(relative: Vector2, in_place := false) -> void:
	_orbit_angle -= relative.x * 0.25
	_pitch_angle = clampf(_pitch_angle - relative.y * 0.25, MIN_PITCH, MAX_PITCH)
	if in_place:
		focus = global_position - _view_offset()
	_apply_transform()


func _pan(relative: Vector2) -> void:
	var right := _camera_right()
	var up := _camera_up_flat()
	var scale := distance * 0.0012
	focus += (right * -relative.x + up * relative.y) * scale
	_apply_transform()


func _view_offset() -> Vector3:
	return Vector3(
		cos(deg_to_rad(_pitch_angle)) * cos(deg_to_rad(_orbit_angle)),
		sin(deg_to_rad(_pitch_angle)),
		cos(deg_to_rad(_pitch_angle)) * sin(deg_to_rad(_orbit_angle)),
	) * distance


func _apply_transform() -> void:
	global_position = focus + _view_offset()
	look_at(focus, Vector3.UP)


func _camera_right() -> Vector3:
	return Vector3(cos(deg_to_rad(_orbit_angle + 90.0)), 0.0, sin(deg_to_rad(_orbit_angle + 90.0)))


func _camera_forward_flat() -> Vector3:
	return Vector3(-cos(deg_to_rad(_orbit_angle)), 0.0, -sin(deg_to_rad(_orbit_angle))).normalized()


func _camera_up_flat() -> Vector3:
	return Vector3.UP


## True while an orbit drag happened this press-release cycle — the editor
## controller checks it to avoid treating the release as a plain click.
func had_orbit_drag() -> bool:
	return _orbit_moved