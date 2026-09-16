# Reference copy from rpg-base (Godot 3.x-era pattern). Normalized for this
# repo: class renamed to RefStateMachine (no global collision), Movement type
# de-referenced (does not exist here). Logic is unchanged.

class_name RefStateMachine extends Node

@export var starting_state: RefState
@export var debug = true

var current_state: RefState
var previous_state: RefState

# Initialize the state machine by giving each child state a reference to the
# parent object it belongs to and enter the default starting_state.
func init(parent: CharacterBody3D, movement) -> void:
	for child in get_children():
		child.parent = parent
		child.anims = parent.anims
		child.movement = movement
	# Initialize to the default state
	change_state(starting_state)


# Change to the new state by first calling any exit logic on the current state.
func change_state(new_state: RefState) -> void:
	if current_state:
		current_state.exit()

	previous_state = current_state
	current_state = new_state
	current_state.enter()


# Pass through functions for the Player to call,
# handling state changes as needed.
func process_physics(delta: float) -> void:
	var new_state = current_state.process_physics(delta)
	if new_state:
		change_state(new_state)


#func process_frame(delta: float) -> void:
	#var new_state = current_state.process_frame(delta)
	#if new_state:
		#change_state(new_state)


func get_state(_name) -> RefState:
	return find_child(_name)


func get_previous_state() -> RefState:
	if previous_state:
		return previous_state
	return starting_state
