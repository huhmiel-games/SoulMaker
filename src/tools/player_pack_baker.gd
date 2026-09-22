class_name PlayerPackBaker
extends RefCounted

## Shared animation-pack baking (lab library + player pack): merges the
## moveset packs with the lab-only packs from anim_lab_packs.json, retargets
## via RigKit, removes the takes hidden in anim_lab_hidden.json, saves one
## AnimationLibrary .res. Called headless (bake_anim_lab.gd,
## bake_player_pack.gd) and from the lab's Export button (no subprocess).
## Take names stay "pack__take" so moveset slots resolve unchanged.
const RIG_PATH := "res://assets/meshes/characters/Superhero_Male_FullBody.gltf"
const LAB_PACKS_PATH := "res://scenes/anim_lab/anim_lab_packs.json"
const HIDDEN_PATH := "res://scenes/anim_lab/anim_lab_hidden.json"
const LAB_LIB_OUT := "res://scenes/anim_lab/anim_lab_lib.res"
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
	for h in hidden:
		if libs.has_animation(h):
			libs.remove_animation(h)
			skipped += 1
	if skipped > 0:
		print("[%s] hidden: skipped %d" % [tag, skipped])
	_warn_hidden_slots(ms, hidden)
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
	var slots: Dictionary = ms.get("slots", {})
	for slot_name in slots:
		var clips: Array = (slots[slot_name] as Dictionary).get("clips", [])
		for c in clips:
			if hidden.has(str(c)):
				push_warning("[Pack] hidden: slot '%s' references hidden take '%s' (game falls back)" % [slot_name, c])


## Per-pack take counts after hidden filtering (triage overview).
static func _print_pack_tally(libs: AnimationLibrary, tag: String) -> void:
	var tally := {}
	for full in libs.get_animation_list():
		var pid := str(full).get_slice("__", 0)
		tally[pid] = int(tally.get(pid, 0)) + 1
	print("[%s] packs: %s" % [tag, str(tally)])
