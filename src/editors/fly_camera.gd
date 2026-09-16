class_name FlyCamera
extends Camera3D

## Playtest free-fly camera (P1 map editor): WASD to move in the horizontal
## plane of the view, Space/Shift up/down, mouse look while captured. Enough to
## walk through a built map until the real player controller lands (P2).

const MOVE_SPEED := 8.0
const LOOK_SPEED := 0.003
const MOUSE_SENS_Y := 1.0

var captured := false


func _ready() -> void:
	set_capture(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			set_capture(true)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if captured:
			_rotate(mm.relative)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		set_capture(false)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if InputManager.is_pressed(&"move_forward"):
		dir.z -= 1.0
	if InputManager.is_pressed(&"move_back"):
		dir.z += 1.0
	if InputManager.is_pressed(&"move_left"):
		dir.x -= 1.0
	if InputManager.is_pressed(&"move_right"):
		dir.x += 1.0
	if InputManager.is_pressed(&"move_up"):
		dir.y += 1.0
	if InputManager.is_pressed(&"move_down"):
		dir.y -= 1.0
	if dir == Vector3.ZERO:
		return
	var basis_local := global_basis
	var move := basis_local * dir.normalized()
	global_position += move * MOVE_SPEED * delta


func set_capture(enabled: bool) -> void:
	captured = enabled
	if captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _rotate(relative: Vector2) -> void:
	rotate_object_local(Vector3.UP, -relative.x * LOOK_SPEED)
	rotate_object_local(Vector3.RIGHT, -relative.y * LOOK_SPEED * MOUSE_SENS_Y)