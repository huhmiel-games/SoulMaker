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
## Impact shake (P2): trauma 0..1, offset ∝ trauma² (tiny on light, violent
## on heavy — features/01), decayed in real time so hitstop never stretches
## the shake. All rotation writes go through _apply().
const TRAUMA_DECAY := 1.8
const SHAKE_MAX := 0.06 # radians at trauma 1

var _yaw := 0.0
var _pitch := -12.0
var _trauma := 0.0

## Body-relative contract: free states leave yaw follow on (orbit bends the
## run — the body turns toward the camera-relative wish instead), LockOn
## turns it off (the body tracks the enemy, the pivot eases behind it).
var yaw_enabled := true


func _ready() -> void:
	_apply()


## Aft snap after reset_camera: pivot yaw already zeroed by the caller.
func snap_aft() -> void:
	_yaw = 0.0
	_apply()


## World-yaw preservation when the BODY snaps by d_body radians: the pivot
## is a body child, so local yaw shifts opposite to keep the camera frozen
## in the world. _yaw is tracked in DEGREES (rates are °/s) — convert.
## Applied immediately (_process early-outs on zero input and would not
## reapply it). Used by lock-on facing snaps (free rolls never touch the
## body heading — reset_camera convention).
func shift_yaw(d_body: float) -> void:
	_yaw -= rad_to_deg(d_body)
	_apply()


## Lock-on follow: ease local yaw back behind the body. The body itself
## tracks the enemy (StateLockOn), so yaw 0 = the camera looks at the
## target. Pitch stays manual — only _yaw is touched here.
func track_aft(delta: float, rate := 8.0) -> void:
	_yaw = lerpf(_yaw, 0.0, minf(rate * delta, 1.0))
	_apply()


## Impact trauma add (0..1 clamped). The hitstop contract: the camera stays
## alive while the world freezes, so orbit + decay below consume UNSCALED
## delta (raw = delta / time_scale = real seconds).
func add_trauma(x: float) -> void:
	_trauma = minf(_trauma + x, 1.0)


## Single rotation writer: base orbit + trauma² shake noise.
func _apply() -> void:
	var s := _trauma * _trauma * SHAKE_MAX
	rotation = Vector3(
		deg_to_rad(_pitch) + randf_range(-s, s),
		deg_to_rad(_yaw) + randf_range(-s, s),
		randf_range(-s, s))


func _process(delta: float) -> void:
	var raw := delta / maxf(Engine.time_scale, 0.001)
	if _trauma > 0.0:
		_trauma = maxf(_trauma - TRAUMA_DECAY * raw, 0.0)
		_apply()
	var orbit := Vector2(
		InputManager.analog(&"cam_orbit_x"),
		InputManager.analog(&"cam_orbit_y")
	)
	if orbit == Vector2.ZERO:
		return
	if yaw_enabled:
		_yaw -= orbit.x * YAW_RATE * raw
	_pitch = clampf(_pitch - orbit.y * PITCH_RATE * raw, MIN_PITCH, MAX_PITCH)
	_apply()
