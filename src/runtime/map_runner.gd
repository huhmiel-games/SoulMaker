class_name MapRunner
extends Node3D

## Game side of the editor ⇄ game round-trip (P2): builds the live map from
## GameState "game/pending_map" ({name, map} dict, else a bare name loading
## the file), spawns the player prefab at the map spawn (+ drop), Esc/menu
## returns to the editor via "editor/pending_map". No enemies, no run state
## yet (P6/P7) — this proves the maker loop, not the game.
const RUN_PENDING_KEY := "game/pending_map"
const EDITOR_PENDING_KEY := "editor/pending_map"
const EDITOR_SCENE := "res://scenes/ingame_editors/map_editor.tscn"
const MAPS_DIR := "user://maps"
const SPAWN_DROP := 2.0

@onready var world_env: WorldEnvironment = get_node("WorldEnvironment")
@onready var sun: DirectionalLight3D = get_node("Sun")
@onready var map_root: Node3D = get_node("MapRoot")
@onready var player: PlayerController = get_node("Player")

var map_name := ""
var _returned := false


func _ready() -> void:
	var data := _resolve_map()
	if data.is_empty():
		push_error("[Run] no map handed over, back to editor")
		_to_editor()
		return
	var issues := MapIO.validate_map(data)
	if not issues.is_empty():
		push_warning("[Run] map issues: %s" % ", ".join(issues))
	# Own environment copy (the tres is shared with the editor scene).
	world_env.environment = (world_env.environment as Environment).duplicate()
	var amb := (MapIO.AMBIANCE_DEFAULTS as Dictionary).duplicate()
	var over := MapIO.ambiance_from_data(data)
	for key in over:
		amb[key] = over[key]
	MapBuilder.apply_ambiance(world_env.environment as Environment, sun, amb, 0.0)
	map_root.add_child(MapBuilder.ground_node(MapIO.ground_from_data(data)))
	var catalog := Catalog.new()
	if catalog.load() != OK:
		push_warning("[Run] catalog unavailable — placements skipped")
	else:
		var placed := 0
		for placement in MapIO.deserialize(data):
			if _place(placement, catalog):
				placed += 1
		print("[Run] map %s — placed %d" % [map_name, placed])
	var spawn := MapIO.spawn_from_data(data)
	var pos: Vector3 = spawn.get("position", Vector3.ZERO)
	player.position = pos + Vector3(0.0, SPAWN_DROP, 0.0)
	player.rotation.y = float(spawn.get("yaw", 0.0))
	print("[Run] spawned at %s" % str(player.position))


func _process(_delta: float) -> void:
	# P2 test-loop exit (no in-game pause by souls convention — the bonfire
	# menu owns this from P7): Esc/Start hands back to the editor, whose
	# boot path reopens the map by name.
	if _returned:
		return
	if InputManager.is_just_pressed(&"menu"):
		_to_editor()


## One catalog placement under MapRoot (tolerant: unknown prefab or unloadable
## scene warns + skips — never breaks the run).
func _place(placement: Dictionary, catalog: Catalog) -> bool:
	var id := str(placement.get("prefab_id", ""))
	var scene_path := catalog.resolve_scene_path(id)
	if scene_path.is_empty():
		push_warning("[Run] no scene file for %s — skipped" % id)
		return false
	var packed: PackedScene = ResourceLoader.load(scene_path)
	if packed == null:
		push_warning("[Run] cannot load %s — skipped" % scene_path)
		return false
	var node := MapBuilder.instantiate_prefab(packed, id, str(placement.get("instance_id", "")))
	MapBuilder.apply_node_transform(node, placement.get("transform", {}))
	map_root.add_child(node)
	return true


## Live dict first ({name, map}), else a bare map name → file. Consumes the key.
func _resolve_map() -> Dictionary:
	var pending: Variant = GameState.get_value(RUN_PENDING_KEY, null)
	GameState.set_value(RUN_PENDING_KEY, "")
	if pending is Dictionary:
		map_name = str((pending as Dictionary).get("name", ""))
		var m: Variant = (pending as Dictionary).get("map", {})
		if m is Dictionary and not (m as Dictionary).is_empty():
			return m
		return {}
	if pending is String and not (pending as String).is_empty():
		map_name = pending
		return JsonFile.load_object(MAPS_DIR.path_join("%s.json" % map_name))
	return {}


func _to_editor() -> void:
	_returned = true
	GameState.set_value(EDITOR_PENDING_KEY, map_name)
	# Deferred: _ready runs mid-tree-setup (change_scene is illegal here).
	get_tree().call_deferred("change_scene_to_file", EDITOR_SCENE)
