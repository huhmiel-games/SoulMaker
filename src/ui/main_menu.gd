class_name MainMenu
extends GenericMenu

## Game hub: entry list to the editors. One entry today (Map editor → map
## library); more append to the array in _load_entries, one line each. EXIT
## quits the game directly (nothing sits above the hub).

const HUB_ENTRIES: Array = [
	{"label": "Map editor", "open": "res://scenes/editors/map_editor_menu.tscn"},
	{"label": "EXIT", "quit": true},
]


func _ready() -> void:
	super._ready()


func _menu_title() -> String:
	return "SOULMAKER"


func _load_entries() -> Array:
	return HUB_ENTRIES.duplicate()
