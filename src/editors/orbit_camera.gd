class_name OrbitCamera
extends Camera3D

## Editor orbiting camera (P1 map editor). Camera input is device-identical and
## needs no click or drag: arrows / left-stick pan, mouse motion / right-stick
## orbit in place, wheel / triggers zoom. The camera pivots around a focus
## point; vertical orbit is clamped so the ground stays readable. Left click is
## left for placement/selection (handled by the editor controller).

const DEFAULT_FOCUS := Vector3(0.0, 0.0, 0.0)
const MIN_DISTANCE := 0.5
const MAX_DISTANCE := 120.0
const MIN_PITCH := -80.0
const MAX_PITCH := 80.0
const MOUSE_ORBIT_SENS := 0.5

## Current distance from the focus point.
var distance: float = 18.0
## Focus point the camera orbits around.
var focus: Vector3 = DEFAULT_FOCUS

var _orbit_angle := 45.0
var _pitch_angle := 35.0


func _ready() -> void:
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# Mouse motion is the right-stick analogue: same non-inverted mapping,
		# same in-place orbit, no button required.
		_orbit_mouse(mm.relative)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(-1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.0)


func _process(delta: float) -> void:
	if not current:
		return
	# Pan input: arrows fill a left-stick-like vector, the analog stick adds on
	# top — a single shared pan path, identical across devices. The keyboard
	# steps are scaled down (full deflection would match a lashed-in stick).
	var pan := Vector2.ZERO
	if InputManager.is_pressed(&"cam_pan_right"):
		pan.x += 1.0
	if InputManager.is_pressed(&"cam_pan_left"):
		pan.x -= 1.0
	if InputManager.is_pressed(&"cam_pan_back"):
		pan.y += 1.0
	if InputManager.is_pressed(&"cam_pan_fwd"):
		pan.y -= 1.0
	pan = pan * 0.5 + InputManager.left_stick()
	_pan_analog(pan, delta)
	_orbit_analog(InputManager.right_stick(), delta)
	_zoom_analog(InputManager.triggers(), delta)


func _pan_analog(stick: Vector2, delta: float) -> void:
	if stick == Vector2.ZERO:
		return
	# Camera-relative movement along the real view vector (pitch included):
	# up follows exactly where the camera looks, even toward the ground.
	var right := global_basis.x
	var fwd := -global_basis.z
	focus += (right * stick.x + fwd * -stick.y) * distance * 0.8 * delta
	_apply_transform()


func _orbit_analog(stick: Vector2, delta: float) -> void:
	if stick == Vector2.ZERO:
		return
	# Gamepad orbit pivots the camera around ITSELF (turret-like): the focus is
	# re-glued ahead of the view so the camera stays in place while turning.
	# Yaw and pitch are non-inverted (RS right = turn right, RS up = turn up);
	# the option to invert arrives with Options (feature 11).
	_orbit(Vector2(-stick.x, -stick.y) * 220.0 * delta, true)


func _zoom_analog(triggers: Vector2, delta: float) -> void:
	var amount := triggers.y - triggers.x
	if absf(amount) < 0.001:
		return
	_zoom(-amount * 2.0 * delta)


func _orbit_mouse(relative: Vector2) -> void:
	# Mirrors the right-stick mapping (stick is negated before `_orbit`), so the
	# mouse and the stick always turn the camera the same way.
	_orbit(-relative * MOUSE_ORBIT_SENS, true)


func _zoom(steps: float) -> void:
	distance = clampf(distance * pow(0.85, steps), MIN_DISTANCE, MAX_DISTANCE)
	_apply_transform()


func _orbit(relative: Vector2, in_place := false) -> void:
	_orbit_angle -= relative.x * 0.25
	_pitch_angle = clampf(_pitch_angle - relative.y * 0.25, MIN_PITCH, MAX_PITCH)
	if in_place:
		focus = global_position - _view_offset()
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