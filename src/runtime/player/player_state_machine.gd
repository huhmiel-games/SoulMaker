class_name PlayerStateMachine
extends RefCounted

## Nodess state machine (P2): owns PlayerState instances keyed by enum ID,
## runs enter/exit around transitions, logs every change (old debug habit).
## Created and stepped by PlayerController — never a scene node.
enum { IDLE, LOCOMOTION, FALL, ROLL, BACKSTEP, LOCKON, ATTACK, HURT, KEEP }

const NAMES := {IDLE: "Idle", LOCOMOTION: "Locomotion", FALL: "Fall", ROLL: "Roll", BACKSTEP: "Backstep", LOCKON: "LockOn", ATTACK: "Attack", HURT: "Hurt"}

var _states: Dictionary = {}
var _current_id := -1
var current: PlayerState = null
var previous_id := -1


func add_state(id: int, state: PlayerState) -> void:
	_states[id] = state


func start(id: int) -> void:
	_change(id)


func state_id() -> int:
	return _current_id


func state_name() -> String:
	return str(NAMES.get(_current_id, "?"))


func step(delta: float) -> void:
	if current == null:
		return
	var nxt: int = current.step(delta)
	if nxt != KEEP and nxt != _current_id and _states.has(nxt):
		_change(nxt)


func _change(id: int) -> void:
	if current != null:
		current.exit()
		previous_id = _current_id
		print("[SM] %s -> %s" % [NAMES.get(_current_id, "?"), NAMES.get(id, "?")])
	_current_id = id
	current = _states[id]
	current.enter()
