extends Node3D

## Test-scene slow-mo hook (P3 testability, WORKLOG rule): an export var,
## no input — the frozen game profile and input_audit stay untouched. Set
## slow_mo = 0.3 in the editor to learn a timing humanly, 1.0 to validate
## at full speed. Resets on exit so a slow scene never leaks into the next.
@export var slow_mo := 1.0


func _ready() -> void:
	Engine.time_scale = maxf(slow_mo, 0.05)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
