class_name PlayerPackBaker
extends RefCounted

## Single animation-pack baking (scenes/anim_lab/player_pack.res): merges the
## moveset packs with the lab-only packs from anim_lab_packs.json, retargets
## via RigKit, replays the curated aliases from anim_lab_renames.json, removes
## the takes hidden in anim_lab_hidden.json, saves one AnimationLibrary .res.
## One file shared by the lab dock and the game — no duplication, no sync
## step. Called headless (bake_player_pack.gd).
## Raw take names stay "pack__take"; curated aliases follow
## action__body__stance__NN (__ = field boundary, _ = word separator) and
## moveset slots resolve the post-rename names.
const RIG_PATH := "res://assets/meshes/characters/Superhero_Male_FullBody.gltf"
const LAB_PACKS_PATH := "res://scenes/anim_lab/anim_lab_packs.json"
const HIDDEN_PATH := "res://scenes/anim_lab/anim_lab_hidden.json"
const RENAMES_PATH := "res://scenes/anim_lab/anim_lab_renames.json"
const PLAYER_PACK_OUT := "res://scenes/anim_lab/player_pack.res"


## Bakes the merged+filtered library to [param out_path]. [param tree_root]
## hosts the throwaway rig holder (get_root() headless, get_tree().root in
## the editor). Returns OK + prints a per-pack tally, or an Error.
static func bake_to(tree_root: Node, out_path: String, tag: String) -> Error:
	var ms := Moveset.load_object()
	var holder := Node3D.new()
	holder.name = "PackBakeHolder"
	tree_root.add_child(holder)
	var rig: Node3D = (load(RIG_PATH) as PackedScene).instantiate()
	rig.name = "RigRoot"
	holder.add_child(rig)
	var player := RigKit.build_player(rig, all_packs(ms))
	if player == null:
		push_error("[%s] FAIL: RigKit returned null" % tag)
		holder.free()
		return ERR_CANT_CREATE
	var libs: AnimationLibrary = player.get_animation_library("rig")
	if libs == null or libs.get_animation_list().is_empty():
		push_error("[%s] FAIL: empty library" % tag)
		holder.free()
		return ERR_CANT_CREATE
	var hidden := hidden_takes()
	var skipped := 0
	var renames := renames_map()
	var renamed := 0
	for old in renames:
		var new := str(renames[old])
		if not libs.has_animation(old):
			push_warning("[%s] rename: '%s' not in the baked library (stale entry?)" % [tag, old])
			continue
		if libs.has_animation(new):
			push_warning("[%s] rename: target '%s' already exists (skipped)" % [tag, new])
			continue
		if "/" in new or "\\" in new:
			push_warning("[%s] rename: target '%s' must not contain a path separator (skipped)" % [tag, new])
			continue
		if new.get_slice("__", 0) != str(old).get_slice("__", 0):
			push_warning("[%s] rename: pack prefix changes '%s' -> '%s'" % [tag, old, new])
		libs.rename_animation(old, new)
		renamed += 1
	if renamed > 0:
		print("[%s] renames: applied %d" % [tag, renamed])
	for h in hidden:
		if libs.has_animation(h):
			libs.remove_animation(h)
			skipped += 1
		elif renames.has(h):
			push_warning("[%s] hidden: '%s' is a pre-rename name (renamed to '%s' — hide the new name instead)" % [tag, h, str(renames[h])])
	if skipped > 0:
		print("[%s] hidden: skipped %d" % [tag, skipped])
	_warn_hidden_slots(ms, hidden)
	_warn_missing_slots(ms, libs, tag)
	_print_pack_tally(libs, tag)
	var err := ResourceSaver.save(libs, out_path)
	holder.free()
	if err != OK:
		push_error("[%s] FAIL: save failed" % tag)
		return err
	print("[%s] OK: %s (%d anims)" % [tag, out_path, libs.get_animation_list().size()])
	return OK


## Moveset packs + lab-only extra packs (lab ids never override moveset ids).
static func all_packs(ms: Dictionary) -> Dictionary:
	var packs: Dictionary = Moveset.packs_of(ms)
	var lab := _lab_packs()
	for id in lab:
		if packs.has(id):
			push_warning("[Pack] lab pack id '%s' collides with a moveset pack (moveset wins)" % id)
		else:
			packs[id] = str(lab[id])
	return packs


static func hidden_takes() -> Dictionary:
	var obj := JsonFile.load_object(HIDDEN_PATH)
	var set := {}
	for h in obj.get("hidden", []):
		set[str(h)] = true
	return set


## Curated aliases {old pack__take: new action__body__stance__NN} (flat
## dict under "renames" — written by the lab rename button, hand-editable).
static func renames_map() -> Dictionary:
	var obj := JsonFile.load_object(RENAMES_PATH)
	var raw: Variant = obj.get("renames", {})
	var out := {}
	if raw is Dictionary:
		for old in (raw as Dictionary):
			out[str(old)] = str((raw as Dictionary)[old])
	return out


## Lab-only extra packs (never read by the game): {lib_id: .glb path}.
static func _lab_packs() -> Dictionary:
	var obj := JsonFile.load_object(LAB_PACKS_PATH)
	var packs: Variant = obj.get("packs", {})
	if packs is Dictionary:
		return (packs as Dictionary).duplicate()
	return {}


## Warns when a hidden take is referenced by a moveset slot: the game would
## silently fall back (ADR-009) instead of playing it.
static func _warn_hidden_slots(ms: Dictionary, hidden: Dictionary) -> void:
	for key in _all_slot_clips(ms):
		if hidden.has(key):
			push_warning("[Pack] hidden: slot clip '%s' is hidden (game falls back)" % key)


## Every clip name referenced by moveset slots (legacy clips + variant
## clips): {clip_name: true}. Shared by the hidden/rename warnings.
static func _all_slot_clips(ms: Dictionary) -> Dictionary:
	var set := {}
	var slots: Variant = ms.get("slots", {})
	if not slots is Dictionary:
		return set
	for slot_name in (slots as Dictionary):
		var slot: Variant = (slots as Dictionary)[slot_name]
		if not slot is Dictionary:
			continue
		for c in (slot as Dictionary).get("clips", []):
			set[str(c)] = true
		for v in (slot as Dictionary).get("variants", []):
			if v is Dictionary:
				for c in (v as Dictionary).get("clips", []):
					set[str(c)] = true
	return set


## Warns when a moveset-referenced clip is absent from the baked library
## (post-rename, post-hidden): the game falls back at boot (ADR-009).
static func _warn_missing_slots(ms: Dictionary, libs: AnimationLibrary, tag: String) -> void:
	for key in _all_slot_clips(ms):
		if not libs.has_animation(key):
			push_warning("[%s] slot clip '%s' missing from the baked library (game falls back)" % [tag, key])


## Per-pack take counts after hidden filtering (triage overview).
static func _print_pack_tally(libs: AnimationLibrary, tag: String) -> void:
	var tally := {}
	for full in libs.get_animation_list():
		var pid := str(full).get_slice("__", 0)
		tally[pid] = int(tally.get(pid, 0)) + 1
	print("[%s] packs: %s" % [tag, str(tally)])
