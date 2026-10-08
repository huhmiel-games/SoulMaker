class_name OrbitCameraWithZoom
extends PlayerCamera

## Test-scene orbit pivot (hue_shift_test): PlayerCamera orbit/shake verbatim
## plus zoom on the SpringArm3D child. One "zoom in" capability, two units —
## mouse-wheel notches (wheel_ticks steps) and L2/R2 (triggers analog) resolve
## through the same cam_zoom action, no device branch (parity standing rule).
## Wheel up / R2 = zoom in (the arm shortens).

const MIN_ARM := 0.2
const MAX_ARM := 6.0
const WHEEL_FACTOR := 0.92 # arm multiplier per wheel notch (08/10: absolute
# 0.35 then 0.15 steps stayed too coarse up close; relative steps stay fine
# at every distance. Shared with hue_shift_test.)
const TRIGGER_RATE := 2.5 # arm units/sec at full single-trigger pull

var _arm: SpringArm3D = null


func _ready() -> void:
	super._ready()
	_arm = get_node_or_null("SpringArm3D") as SpringArm3D
	if _arm == null:
		push_warning("[OrbitZoom] no SpringArm3D child, zoom disabled")


func _process(delta: float) -> void:
	super._process(delta)
	if _arm == null:
		return
	var wt := float(InputManager.wheel_ticks(&"cam_zoom"))
	if wt != 0.0:
		_arm.spring_length = clampf(_arm.spring_length * pow(WHEEL_FACTOR, wt), MIN_ARM, MAX_ARM)
	var tri := InputManager.analog(&"cam_zoom") * TRIGGER_RATE * delta
	if tri != 0.0:
		_arm.spring_length = clampf(_arm.spring_length - tri, MIN_ARM, MAX_ARM)
