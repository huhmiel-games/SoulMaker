# Reference copy from rpg-base (Godot 3.x-era pattern). Normalized for this
# repo: class renamed to RefState (no global collision), types Player/Movement
# de-referenced (they do not exist here). Logic is unchanged.

class_name RefState extends Node

# Hold a reference to the parent so that it can be controlled by the state
var parent
var anims: AnimationTree
var movement
var is_active: bool = false

func enter() -> void:
	parent.state = name
	is_active = true
	if parent.state_machine.debug:
		print("{parent} enters state {state} from {previous_state}".format({"parent": parent.name, "state": name, "previous_state": parent.state_machine.get_previous_state().name}))


func exit() -> void:
	is_active = false


#func process_frame(_delta: float) -> RefState:
	#return null


func process_physics(_delta: float) -> RefState:
	return null
