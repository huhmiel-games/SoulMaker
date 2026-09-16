extends Node3D

## Runtime validation of the GameState autoload.
## Autoload singletons only exist in a project run (headless --script does not
## load them) — this scene proves the registration and gives a visual + print
## round-trip against a disposable save under user://.

const SAVE_NAME := "run.json"

@onready var _label: Label = $UI/StatusLabel


func _ready() -> void:
	GameState.base_dir = "user://test_game_state/"
	GameState.reset()

	var steps: PackedStringArray = []
	steps.append("GameState test")
	steps.append("base_dir: %s" % GameState.base_dir)

	GameState.set_value("run", "ironman")
	GameState.set_value("currency", 1234)
	GameState.set_value("slots.weapon", "longsword")
	var err := GameState.save(SAVE_NAME)
	steps.append("save: %s (%s)" % [SAVE_NAME, error_string(err)])

	GameState.reset()
	var loaded := GameState.load_save(SAVE_NAME)
	steps.append("loaded keys: %d" % loaded.size())
	steps.append("run=%s currency=%s weapon=%s" % [
		str(GameState.get_value("run")),
		str(GameState.get_value("currency")),
		str(GameState.get_value("slots.weapon")),
	])
	steps.append("current_path: %s" % GameState.current_path)

	var ok: bool = err == OK and loaded.size() == 3 \
		and GameState.get_value("run") == "ironman"
	steps.append(("ROUND-TRIP " + ("OK" if ok else "FAILED")))
	_label.text = "\n".join(steps)
	for line: String in steps:
		print("[game_state_test] ", line)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if ok else 1)
