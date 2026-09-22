@tool
extends Node

## Anim-lab take hider (scenes/anim_lab/anim_lab.tscn, LabTools node): while
## scrubbing takes in the editor Animation dock, press the inspector button
## "Hide current take" and the previewed take is appended to
## anim_lab_hidden.json + removed live + the baked .res re-saved — never
## shown again until restored (remove its line from the JSON + re-bake with
## src/tools/bake_anim_lab.gd; the source .glb files are never touched).
## Dev only, nothing in the game reads this file.
## Note: LabPlayer lives under the RigRoot instance, so the editor hides it
## in the scene dock unless RigRoot is set to Editable Children — the tool
## resolves it dynamically, nothing to configure.
const HIDDEN_PATH := "res://scenes/anim_lab/anim_lab_hidden.json"
const LAB_LIB := "res://scenes/anim_lab/anim_lab_lib.res"

@export_tool_button("Hide current take") var hide_action: Callable = hide_current_take
@export_tool_button("Export player pack") var export_action: Callable = export_player_pack


## Curated runtime library for the game (same merge+filter as the lab):
## export on demand, whenever the triage moves. The game mounts it directly
## when present and silently rebuilds from the .glb packs when absent.
func export_player_pack() -> void:
	var err := PlayerPackBaker.bake_to(get_tree().root, PlayerPackBaker.PLAYER_PACK_OUT, "Pack")
	if err == OK:
		print("[AnimLab] player pack exported — game uses it on next boot")
	else:
		push_warning("[AnimLab] player pack export failed")


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	var player := _find_lab_player()
	if player == null:
		print("[AnimLab] LabTools ready — LabPlayer NOT resolved (reopen the scene / check the RigRoot instance)")
		return
	var lib: AnimationLibrary = player.get_animation_library(&"rig")
	var count := lib.get_animation_list().size() if lib != null else 0
	print("[AnimLab] LabTools ready — player OK, %d takes" % count)


func hide_current_take() -> void:
	var player := _find_lab_player()
	if player == null:
		push_warning("[AnimLab] LabPlayer not found (reopen scenes/anim_lab/anim_lab.tscn / check the RigRoot instance)")
		return
	var take: StringName = player.current_animation
	if take == &"":
		take = player.assigned_animation
	if not str(take).begins_with("rig/"):
		print("[AnimLab] nothing to hide — preview a take in the Animation dock first (current='%s')" % str(take))
		return
	var short := str(take).trim_prefix("rig/")
	_append_hidden(short)
	_warn_slot_use(short)
	var lib: AnimationLibrary = player.get_animation_library(&"rig")
	if lib == null:
		print("[AnimLab] hidden '%s' in JSON (no live library)" % short)
		return
	var next_short := _next_take(lib, short)
	if lib.has_animation(short):
		lib.remove_animation(short)
		if ResourceSaver.save(lib, LAB_LIB) == OK:
			print("[AnimLab] hidden '%s' (%d takes left)" % [short, lib.get_animation_list().size()])
		else:
			push_warning("[AnimLab] hidden '%s' in JSON but .res re-save failed" % short)
	else:
		print("[AnimLab] hidden '%s' in JSON (already absent live)" % short)
	if next_short != "" and lib.has_animation(next_short):
		var full := StringName("rig/" + next_short)
		player.assigned_animation = full
		player.play(full)
		print("[AnimLab] now showing '%s'" % next_short)


## The take right after [param short] in the library list (previous one when
## hiding the last, "" when alone) — the dock is moved there after a hide
## instead of falling back to the top of the list.
func _next_take(lib: AnimationLibrary, short: String) -> String:
	var names: Array = lib.get_animation_list()
	var idx := -1
	for i in names.size():
		if str(names[i]) == short:
			idx = i
			break
	if idx == -1 or names.size() < 2:
		return ""
	if idx + 1 < names.size():
		return str(names[idx + 1])
	return str(names[idx - 1])


## The AnimationPlayer carrying the baked "rig" library, searched from the
## edited scene root — no configured path to go stale.
func _find_lab_player() -> AnimationPlayer:
	var scope := get_owner() if get_owner() != null else get_parent()
	if scope == null:
		return null
	for n in scope.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		if ap != null and ap.has_animation_library(&"rig"):
			return ap
	var any: Array = scope.find_children("*", "AnimationPlayer", true, false)
	if not any.is_empty():
		return any[0] as AnimationPlayer
	return null


func _append_hidden(short: String) -> void:
	var obj := JsonFile.load_object(HIDDEN_PATH)
	var hidden: Array = obj.get("hidden", [])
	if not hidden.has(short):
		hidden.append(short)
	obj["hidden"] = hidden
	JsonFile.save_atomic(HIDDEN_PATH, obj)


## Loud warning (not a block — restore is one JSON line away) when the take
## is referenced by a moveset slot: the game would silently fall back.
func _warn_slot_use(short: String) -> void:
	var slots: Dictionary = (Moveset.load_object()).get("slots", {})
	for slot_name in slots:
		var clips: Array = (slots[slot_name] as Dictionary).get("clips", [])
		if clips.has(short):
			push_warning("[AnimLab] '%s' is used by slot '%s' (game falls back)" % [short, slot_name])
