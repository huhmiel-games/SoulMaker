class_name PlayerIntent
extends RefCounted

## Movement intent reader (P2): the old Movement node rewritten as a plain
## object. Reads ONLY InputManager actions (device parity — zero raw Input
## polling), so the frozen tables + audit keep enforcing the gel.
## Body-relative (old feel): forward = body -Z (Godot convention), D strafes
## screen-right when the camera sits behind. No per-state wiring here.
const SNEAK_TRIGGER := 0.3
const RUN_TRIGGER := 0.75

var ctrl: PlayerController


func setup(c: PlayerController) -> void:
	ctrl = c


## Camera-free raw mix: keyboard faces are digital (saturate to run), the
## left stick stays analog (tilt walks). Clamped to unit length.
func move_raw() -> Vector2:
	var v := Vector2(_axis(&"move_right", &"move_left"), _axis(&"move_back", &"move_forward"))
	return v.limit_length(1.0)


func force() -> float:
	return move_raw().length()


## Wish direction in world space from body basis (never euler angles — no
## sign traps). Flattened: the body never pitches.
func wish_direction(raw: Vector2) -> Vector3:
	if raw == Vector2.ZERO:
		return Vector3.ZERO
	var b := ctrl.global_transform.basis
	var fwd := -b.z
	fwd.y = 0.0
	var right := b.x
	right.y = 0.0
	if fwd.length_squared() < 0.0001 or right.length_squared() < 0.0001:
		return Vector3.ZERO
	return (right.normalized() * raw.x + fwd.normalized() * -raw.y).normalized()


## Dodge tap (Space / B per frozen game table): just-pressed edge, read by
## the grounded states — the DODGE state itself never re-reads it.
func dodge_pressed() -> bool:
	return InputManager.is_just_pressed(&"dodge")


## Lock-on tap (MMB / R3 per frozen game table): toggles StateLockOn.
func lock_pressed() -> bool:
	return InputManager.is_just_pressed(&"lock_on")


## Light attack tap (LMB / R1 per frozen game table): enters StateAttack.
func attack_light_pressed() -> bool:
	return InputManager.is_just_pressed(&"attack_light")


## Turn feed shared with the camera (same analog value, same units): Idle
## lets the camera orbit with it, Locomotion turns the body instead.
func turn_axis() -> float:
	return InputManager.analog(&"cam_orbit_x")


func _axis(pos: StringName, neg: StringName) -> float:
	var out := 0.0
	if InputManager.is_pressed(pos):
		out += 1.0
	if InputManager.is_pressed(neg):
		out -= 1.0
	var stick := InputManager.left_stick()
	if pos == &"move_right":
		out += stick.x
	elif pos == &"move_back":
		out += stick.y
	return out
