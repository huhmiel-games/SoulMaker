@tool
extends Node

## Anim-lab take hider + renamer (scenes/anim_lab/anim_lab.tscn, LabTools
## node): while scrubbing takes in the editor Animation dock, "Hide current
## take" appends the previewed take to anim_lab_hidden.json + removes it live
## + re-saves the baked .res — never shown again until restored (remove its
## line from the JSON + re-bake with src/tools/bake_anim_lab.gd).
## "Rename current take" renames the previewed take to the curated alias in
## [member rename_to] (action__body__stance__NN, __ = field boundary): live
## rename + anim_lab_renames.json append (replayed on every bake BEFORE the
## hidden filter) + player_moveset.json clips updated when the take is used
## by a slot + .res re-save. The source .glb files are never touched.
## Dev only, nothing in the game reads the hidden/renames files.
## Note: LabPlayer lives under the RigRoot instance, so the editor hides it
## in the scene dock unless RigRoot is set to Editable Children — the tool
## resolves it dynamically, nothing to configure.
const HIDDEN_PATH := "res://scenes/anim_lab/anim_lab_hidden.json"
const RENAMES_PATH := "res://scenes/anim_lab/anim_lab_renames.json"
const LAB_LIB := "res://scenes/anim_lab/anim_lab_lib.res"

## Curated alias for the previewed take (see above): pre-filled with the
## previewed take name whenever the Animation dock selection changes — edit
## the take part, then press "Rename current take". Empty = the button
## no-ops with a hint.
@export var rename_to := ""

## Last previewed take (short name): the pre-fill watcher below writes
## [member rename_to] only on take switch, never while you edit.
var _last_take := ""

@export_tool_button("Hide current take") var hide_action: Callable = hide_current_take
@export_tool_button("Rename current take") var rename_action: Callable = rename_current_take
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
	_last_take = _previewed_short(player)


## Pre-fill watcher (editor only): whenever the dock preview moves to another
## take, [member rename_to] follows so rename is edit-not-type. Your edits
## are never overwritten — writes happen only on take switch, and only when
## the value actually differs.
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var player := _find_lab_player()
	if player == null:
		return
	var short := _previewed_short(player)
	if short != "" and short != _last_take:
		_last_take = short
		if rename_to != short:
			rename_to = short


## Short name of the dock-previewed take ("" when nothing previewed).
func _previewed_short(player: AnimationPlayer) -> String:
	var take: StringName = player.current_animation
	if take == &"":
		take = player.assigned_animation
	if not str(take).begins_with("rig/"):
		return ""
	return str(take).trim_prefix("rig/")


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


## Renames the previewed take to [member rename_to]: live rename + renames
## JSON append (chain-collapsed: A->B then B->C records A->C and B->C so a
## re-bake applies single hops) + moveset clips updated + .res re-save.
func rename_current_take() -> void:
	var player := _find_lab_player()
	if player == null:
		push_warning("[AnimLab] LabPlayer not found (reopen scenes/anim_lab/anim_lab.tscn / check the RigRoot instance)")
		return
	var take: StringName = player.current_animation
	if take == &"":
		take = player.assigned_animation
	if not str(take).begins_with("rig/"):
		print("[AnimLab] nothing to rename — preview a take in the Animation dock first (current='%s')" % str(take))
		return
	var short := str(take).trim_prefix("rig/")
	var new := rename_to.strip_edges()
	if new == "":
		print("[AnimLab] set 'rename_to' to the curated alias first (action__body__stance__NN)")
		return
	if "/" in new or "\\" in new:
		push_warning("[AnimLab] alias must not contain a path separator: '%s'" % new)
		return
	if new == short:
		print("[AnimLab] already named '%s'" % short)
		return
	var lib: AnimationLibrary = player.get_animation_library(&"rig")
	if lib == null:
		print("[AnimLab] no live library to rename in")
		return
	if not lib.has_animation(short):
		print("[AnimLab] '%s' absent from the live library (re-bake?)" % short)
		return
	if lib.has_animation(new):
		push_warning("[AnimLab] target '%s' already exists (pick another alias)" % new)
		return
	if new.get_slice("__", 0) != short.get_slice("__", 0):
		push_warning("[AnimLab] pack prefix changes '%s' -> '%s' (allowed, tally/slot fallbacks follow the new name)" % [short, new])
	lib.rename_animation(short, new)
	_append_rename(short, new)
	var updated := _update_slot_clips(short, new)
	if ResourceSaver.save(lib, LAB_LIB) == OK:
		print("[AnimLab] renamed '%s' -> '%s' (%s slots updated)" % [short, new, updated])
	else:
		push_warning("[AnimLab] renamed '%s' -> '%s' live but .res re-save failed" % [short, new])
	var full := StringName("rig/" + new)
	player.assigned_animation = full
	player.play(full)
	_last_take = new


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


## Records old -> new in the renames map, collapsing chains (values pointing
## at old are rewritten to new first) so the baker applies single hops.
func _append_rename(old: String, new: String) -> void:
	var obj := JsonFile.load_object(RENAMES_PATH)
	var raw: Variant = obj.get("renames", {})
	var renames := (raw as Dictionary).duplicate() if raw is Dictionary else {}
	for key in renames:
		if str(renames[key]) == old:
			renames[key] = new
	renames[old] = new
	obj["renames"] = renames
	JsonFile.save_atomic(RENAMES_PATH, obj)


## Rewrites old -> new in every moveset slot clip list (legacy + variants).
## Returns the updated slot count (0 = the take is lab-only, nothing to do).
func _update_slot_clips(old: String, new: String) -> int:
	var obj := Moveset.load_object()
	var slots: Variant = obj.get("slots", {})
	if not slots is Dictionary:
		return 0
	var updated := 0
	for slot_name in (slots as Dictionary):
		var slot: Variant = (slots as Dictionary)[slot_name]
		if not slot is Dictionary:
			continue
		var touched := false
		var clips: Array = (slot as Dictionary).get("clips", [])
		for i in clips.size():
			if str(clips[i]) == old:
				clips[i] = new
				touched = true
		for v in (slot as Dictionary).get("variants", []):
			if v is Dictionary:
				var vclips: Array = (v as Dictionary).get("clips", [])
				for i in vclips.size():
					if str(vclips[i]) == old:
						vclips[i] = new
						touched = true
		if touched:
			updated += 1
			print("[AnimLab] slot '%s': '%s' -> '%s'" % [slot_name, old, new])
	if updated > 0:
		JsonFile.save_atomic(Moveset.PATH, obj)
	return updated


## Loud warning (not a block — restore is one JSON line away) when the take
## is referenced by a moveset slot (legacy clips or variant clips): the game
## would silently fall back.
func _warn_slot_use(short: String) -> void:
	var slots: Variant = (Moveset.load_object()).get("slots", {})
	if not slots is Dictionary:
		return
	for slot_name in (slots as Dictionary):
		var slot: Variant = (slots as Dictionary)[slot_name]
		if not slot is Dictionary:
			continue
		var clips: Array = (slot as Dictionary).get("clips", [])
		if clips.has(short):
			push_warning("[AnimLab] '%s' is used by slot '%s' (game falls back)" % [short, slot_name])
		for v in (slot as Dictionary).get("variants", []):
			if v is Dictionary and ((v as Dictionary).get("clips", []) as Array).has(short):
				push_warning("[AnimLab] '%s' is used by slot '%s' variant %s (game falls back)" % [short, slot_name, str((v as Dictionary).get("match", {}))])
