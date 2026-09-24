class_name OrbitCamera
extends Camera3D

## Editor orbiting camera (P1 map editor). Camera input is device-identical and
## needs no click or drag: arrows / left-stick pan, mouse motion / right-stick
## orbit in place. The camera pivots around a focus point; vertical orbit is
## clamped so the ground stays readable. The mouse selects nothing (parity):
## clicks are unhandled, A/E confirms at the editor crosshair instead.

const DEFAULT_FOCUS := Vector3(0.0, 0.0, 0.0)
## Fixed orbit distance — no zoom: advancing toward the view direction serves
## the same purpose without redundant controls.
const DISTANCE := 18.0
const MIN_PITCH := -80.0
const MAX_PITCH := 80.0
## Orbit feel knob: applied to the unified right-stick + mouse analog vector.
const ORBIT_SENS := 220.0

## Focus point the camera orbits around.
var focus: Vector3 = DEFAULT_FOCUS

## When true the camera accepts no input at all (pan/orbit). The editor sets
## this while an edit-placement interaction or the menu is active, so the view
## stays exactly where the user left it.
var frozen := false

var _orbit_angle := 45.0
var _pitch_angle := 35.0


func _ready() -> void:
	_apply_transform()


## Camera input is polled in _process through InputManager: mouse is the
## right-stick parity (orbit), no raw event handling lives here anymore.
func _process(delta: float) -> void:
	if not current or frozen:
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
	# Orbit: right-stick + mouse-motion summed by InputManager. Both resolve
	# through PROFILES, so keyboard/mouse/gamepad are the same device from the
	# camera's point of view.
	_orbit_analog(
		Vector2(
			InputManager.analog(&"cam_orbit_x"),
			InputManager.analog(&"cam_orbit_y"),
		),
		delta,
	)


func _pan_analog(stick: Vector2, delta: float) -> void:
	if stick == Vector2.ZERO:
		return
	# Camera-relative movement along the real view vector (pitch included):
	# up follows exactly where the camera looks, even toward the ground.
	var right := global_basis.x
	var fwd := -global_basis.z
	focus += (right * stick.x + fwd * -stick.y) * DISTANCE * 0.8 * delta
	_apply_transform()


func _orbit_analog(stick: Vector2, delta: float) -> void:
	if stick == Vector2.ZERO:
		return
	# Orbit pivots the camera around ITSELF (turret-like): the focus is
	# re-glued ahead of the view so the camera stays in place while turning.
	# Yaw and pitch are non-inverted (RS right = turn right, RS up = turn up);
	# the option to invert arrives with Options (feature 11).
	_orbit(Vector2(-stick.x, -stick.y) * ORBIT_SENS * delta, true)


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
	) * DISTANCE


func _apply_transform() -> void:
	global_position = focus + _view_offset()
	look_at(focus, Vector3.UP)
