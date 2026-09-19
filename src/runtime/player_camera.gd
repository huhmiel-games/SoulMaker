class_name PlayerCamera
extends Node3D

## Follow-orbit pivot behind the player (P2): yaw + clamped pitch from the
## unified RS/mouse analog feed (game profile, zero device branches). The
## SpringArm3D child shortens on walls by itself; this script never casts.
## Non-inverted (RS right = turn right); inversion arrives with Options.

## Rates are degrees per second on the unified analog velocity (stick
## deflection + mouse px/sec — see InputManager): one × delta below stays
## frame-rate independent on both devices.
const YAW_RATE := 168.0
const PITCH_RATE := 132.0
const MIN_PITCH := -55.0
const MAX_PITCH := 35.0

var _yaw := 0.0
var _pitch := -12.0

## Body-relative contract: Idle leaves yaw follow on (free orbit),
## Locomotion turns it off (the body turns with the same feed instead).
var yaw_enabled := true


func _ready() -> void:
	rotation = Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0)


## Aft snap after reset_camera: pivot yaw already zeroed by the caller.
func snap_aft() -> void:
	_yaw = 0.0
	rotation = Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0)


## World-yaw preservation when the BODY snaps by d_body radians: the pivot
## is a body child, so local yaw shifts opposite to keep the camera frozen
## in the world. _yaw is tracked in DEGREES (rates are °/s) — convert.
## Applied immediately (_process early-outs on zero input and would not
## reapply it). Reserved for lock-on facing snaps (free rolls never touch
## the body heading — reset_camera convention).
func shift_yaw(d_body: float) -> void:
	_yaw -= rad_to_deg(d_body)
	rotation = Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0)


func _process(delta: float) -> void:
	var orbit := Vector2(
		InputManager.analog(&"cam_orbit_x"),
		InputManager.analog(&"cam_orbit_y")
	)
	if orbit == Vector2.ZERO:
		return
	if yaw_enabled:
		_yaw -= orbit.x * YAW_RATE * delta
	_pitch = clampf(_pitch - orbit.y * PITCH_RATE * delta, MIN_PITCH, MAX_PITCH)
	rotation = Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0)
