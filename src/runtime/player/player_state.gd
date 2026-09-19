class_name PlayerState
extends RefCounted

## Nodess locomotion state (P2): same enter/exit/step protocol as the old
## node-based controller, minus the nodes. Transitions are returned as
## PlayerStateMachine IDs (local returns — no NodePath wiring to maintain).
## Instances live in the machine, so member vars (air timers, roll clocks)
## persist across frames exactly like the old node states.
var ctrl: PlayerController
var intent: PlayerIntent


func setup(c: PlayerController, i: PlayerIntent) -> void:
	ctrl = c
	intent = i


func enter() -> void:
	pass


func exit() -> void:
	pass


## One physics tick. Return a PlayerStateMachine state ID to transition,
## or PlayerStateMachine.KEEP to stay.
func step(_delta: float) -> int:
	return PlayerStateMachine.KEEP
