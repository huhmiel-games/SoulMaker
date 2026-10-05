@tool
extends Node3D
## Anim clipping fixer (EDITOR-ONLY dev scene, never loaded by the game):
## previews a Blender-authored .blend (hero + all outfits) with any game take
## from player_pack, so clipping can be judged in motion without export.
## @tool: setup runs in the editor too — pick/scrub takes in the
## AnimationPlayer dock (ClipFixPlayer), no game launch needed.
## The .blend is instanced in the scene: outfits toggle in the editor tree
## (right-click instance > Editable Children, then eye icons, saved here).
## First import only: copy the retarget/bone_map _subresources block from the
## nude .gltf.import into the .blend.import (adjust PATH to the Blender
## armature object name) so the skeleton speaks Standard.
## Outfit toggling is done in the editor (MeshInstance3D visible). Take
## switching at runtime: Remote debugger -> root.play_take("rig/<take>").
## No track remap: the import names the skeleton node "GeneralSkeleton" like
## anim_lab's rig, so raw pack paths resolve with root_node on its parent.

const ANIM_PACK := "res://scenes/anim_lab/player_pack.res"
const DEFAULT_TAKE := "rig/ual1__Walk"

@export var take := DEFAULT_TAKE
@export var autoplay := true
## Toon preview (editor-only): dresses the blend instance via ToonKit
## (toon_kit.gd is untouched — called, not modified). Transient: never save
## the scene with use_toon on, the surface overrides would bloat the .tscn.
@export var use_toon := false:
	set(v):
		use_toon = v
		if is_node_ready():
			_apply_toon_flag()

var _player: AnimationPlayer
var _master: Skeleton3D
var _inst: Node

func _apply_toon_flag() -> void:
	# No cached _inst: @tool scripts hot-reload without _ready re-running,
	# so a stale/null cache makes the inspector toggle a silent no-op.
	var target := _blend_instance()
	if target == null:
		push_warning("[ClipFix] toon: no blend instance under Preview")
		return
	if use_toon:
		ToonKit.apply_to(target)
		print("[ClipFix] toon on")
	else:
		clear_toon(target)
		print("[ClipFix] toon off")


func _blend_instance() -> Node:
	var preview := get_node_or_null("Preview")
	if preview == null:
		return null
	for c in preview.get_children():
		return c
	return null


## Restores the imported Blender materials (nulls the transient overrides).
static func clear_toon(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			(mi as MeshInstance3D).set_surface_override_material(s, null)


func play_take(take_name: String) -> bool:
	if _player == null or not _player.has_animation(take_name):
		push_error("[ClipFix] no take %s" % take_name)
		return false
	_player.play(take_name)
	print("[ClipFix] playing %s" % take_name)
	return true


func _ready() -> void:
	_player = get_node_or_null("ClipFixPlayer") as AnimationPlayer
	if _player == null:
		push_error("[ClipFix] no ClipFixPlayer node")
		return
	var preview := get_node_or_null("Preview")
	if preview == null:
		push_error("[ClipFix] no Preview node")
		return
	# The .blend is instanced IN the scene (not at runtime) so outfits stay
	# visible/toggleable in the editor tree (Editable Children for per-mesh
	# visibility, saved with this dev scene).
	var inst: Node = null
	for c in preview.get_children():
		inst = c
		break
	if inst == null:
		push_warning("[ClipFix] no blend instance under Preview")
		return
	var found := inst.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_error("[ClipFix] no Skeleton3D in blend_scene (bonemap missing on import?)")
		return
	_master = found[0] as Skeleton3D
	_inst = inst
	_apply_toon_flag()
	var pack := load(ANIM_PACK) as AnimationLibrary
	if pack == null:
		push_error("[ClipFix] cannot load %s" % ANIM_PACK)
		return
	if _player.has_animation_library(&"rig"):
		_player.remove_animation_library(&"rig")
	# Lab pattern (anim_lab.tscn): NO track remap. The import names the
	# skeleton node "GeneralSkeleton", so raw pack paths resolve — point the
	# player root at the skeleton's parent and mount the pack shared.
	_player.root_node = _player.get_path_to(_master.get_parent())
	_player.add_animation_library(&"rig", pack)
	print("[ClipFix] takes: %d (raw pack, no remap)" % pack.get_animation_list().size())
	if autoplay and not play_take(take):
		push_warning("[ClipFix] autoplay take missing")
