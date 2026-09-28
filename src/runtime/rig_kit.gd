class_name RigKit
extends RefCounted

## Animation wiring for humanoid rigs (P2 player, future enemies): merges
## external .glb animation libraries onto the rig's own skeleton by rewriting
## track paths to bone subnames (proven by the retarget spike — same logic).
## Layout contract: rig_root/Armature/GeneralSkeleton (Superhero rigs).
## Textures/materials are ToonKit's job, not this file's.

## Builds an AnimationPlayer under Armature from {lib_id: res_path} packs.
## Animations land as "lib_id__anim_name". Returns the player (null + error
## when the skeleton is missing — the caller runs capsule-only).
static func build_player(rig_root: Node3D, packs: Dictionary) -> AnimationPlayer:
	var prepared := _armature_player(rig_root)
	if prepared.is_empty():
		return null
	var player: AnimationPlayer = prepared[0]
	var skeleton: Skeleton3D = prepared[1]
	var skeleton_path: String = (rig_root.get_node("Armature") as Node3D).get_path_to(skeleton)
	var libs := AnimationLibrary.new()
	var ok := 0
	for lib_id in packs:
		var lib: AnimationLibrary = load(str(packs[lib_id]))
		if lib == null:
			push_warning("RigKit: library missing: %s" % str(packs[lib_id]))
			continue
		for anim_name in lib.get_animation_list():
			var copy := _retarget(lib.get_animation(anim_name), skeleton_path)
			libs.add_animation("%s__%s" % [lib_id, anim_name], copy)
			ok += 1
	_normalize_coverage(libs, skeleton, skeleton_path)
	player.add_animation_library("rig", libs)
	print("[RigKit] %d animations on %s" % [ok, rig_root.name])
	_diagnose(player, skeleton)
	return player


## Mounts a pre-baked AnimationLibrary .res (player pack) under Armature.
## Same layout and take names as build_player ("lib_id__anim_name"), so
## moveset slots resolve unchanged — without re-reading the .glb packs.
## Returns the player (null + error when the skeleton is missing or the
## pack cannot load — the caller falls back to build_player).
static func mount_packed(rig_root: Node3D, pack_path: String) -> AnimationPlayer:
	var libs := load(pack_path) as AnimationLibrary
	if libs == null:
		push_error("RigKit: packed library not loadable: %s" % pack_path)
		return null
	var prepared := _armature_player(rig_root)
	if prepared.is_empty():
		return null
	var player: AnimationPlayer = prepared[0]
	var skeleton: Skeleton3D = prepared[1]
	player.add_animation_library("rig", libs)
	print("[RigKit] mounted %d packed animations on %s" % [libs.get_animation_list().size(), rig_root.name])
	_diagnose(player, skeleton)
	return player


## Shared scaffold: AnimationPlayer under Armature on the rig skeleton.
## Returns [player, skeleton], empty + error when the skeleton is missing.
static func _armature_player(rig_root: Node3D) -> Array:
	var skeleton := rig_root.get_node_or_null("Armature/GeneralSkeleton") as Skeleton3D
	if skeleton == null:
		push_error("RigKit: GeneralSkeleton not found under %s" % rig_root.name)
		return []
	# Unit space : NEVER touch motion_scale (REV 29 — the 1.0 force-in was a
	# regression: import value rules, shared by game/creator/lab).
	var armature: Node3D = rig_root.get_node("Armature")
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.root_node = NodePath("..")
	armature.add_child(player)
	return [player, skeleton]


## Boot diagnostic: do the retargeted bone tracks address THIS skeleton?
## Prints a summary; a silent mismatch = eternal T-pose, so any weak clip
## gets its own warning line.
static func _diagnose(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var weak := 0
	for name in player.get_animation_list():
		var anim: Animation = player.get_animation(name)
		var total := 0
		var matched := 0
		for i in anim.get_track_count():
			var t := anim.track_get_type(i)
			if t != Animation.TYPE_POSITION_3D and t != Animation.TYPE_ROTATION_3D and t != Animation.TYPE_SCALE_3D:
				continue
			total += 1
			var path: NodePath = anim.track_get_path(i)
			var bone := str(path.get_subname(0)) if path.get_subname_count() > 0 else "?"
			if skeleton.find_bone(bone) != -1:
				matched += 1
		if total < 10 or matched < total:
			weak += 1
			print("[RigKit] WEAK clip=%s tracks=%d matched=%d" % [name, total, matched])
	if weak == 0:
		var probe: Animation = player.get_animation(player.get_animation_list()[0])
		print("[RigKit] all clips drive the skeleton (sample %s tracks)" % probe.get_track_count())


## First "rig/<lib>__*<want>*" match, "" when absent. Exact basename match
## wins first (["idle"] must pick "idle", not "falling idle"), then substring.
static func pick(player: AnimationPlayer, lib_id: String, wants: Array) -> StringName:
	if player == null:
		return &""
	var prefix := "rig/%s__" % lib_id
	for want in wants:
		for anim in player.get_animation_list():
			if anim.begins_with(prefix) and anim.to_lower() == (prefix + str(want)).to_lower():
				return StringName(anim)
	for want in wants:
		for anim in player.get_animation_list():
			if anim.begins_with(prefix) and str(want).to_lower() in anim.to_lower():
				return StringName(anim)
	return &""


static func _retarget(source: Animation, skeleton_path: String) -> Animation:
	var copy: Animation = source.duplicate()
	for i in copy.get_track_count():
		var path: NodePath = copy.track_get_path(i)
		if path.get_subname_count() == 0:
			continue
		copy.track_set_path(i, NodePath(skeleton_path + ":" + String(path.get_subname(0))))
	return copy


## Coverage normalization (LEAN-001 root-cause fix, 28/09/2026): the .glb
## import drops rest-equal tracks (proven: raw UAL spine_01 is
## REST-constant in 86/86 takes, baked pack lacks Spine rot in 76 takes)
## and compresses other constants to 1 key. A take that drives no Spine
## therefore inherits the previous take's column = lean residue. Fill
## every missing bone rotation with a rest-valued key (solo playback is
## unchanged: from rest the bone already shows rest) and guard Hips
## position the same way. Root is excluded on purpose (REV 31: Root stays
## fixed, zero Root tracks by design). Read-only on motion_scale (REV 29).
static func _normalize_coverage(libs: AnimationLibrary, skeleton: Skeleton3D, skeleton_path: String) -> void:
	var injected := 0
	var takes_touched := 0
	for full in libs.get_animation_list():
		var anim: Animation = libs.get_animation(full)
		var rot := {}
		var hips_pos := false
		for i in anim.get_track_count():
			var t := anim.track_get_type(i)
			var p: NodePath = anim.track_get_path(i)
			if p.get_subname_count() == 0:
				continue
			var b := str(p.get_subname(0))
			if t == Animation.TYPE_ROTATION_3D:
				rot[b] = true
			elif t == Animation.TYPE_POSITION_3D and b == "Hips":
				hips_pos = true
		var added := 0
		for b in skeleton.get_bone_count():
			var bn := skeleton.get_bone_name(b)
			if bn == "Root":
				continue
			if rot.has(bn):
				continue
			var rest: Transform3D = skeleton.get_bone_rest(b)
			var ti := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(ti, NodePath(skeleton_path + ":" + bn))
			anim.track_insert_key(ti, 0.0, rest.basis.get_rotation_quaternion().normalized())
			added += 1
		if not hips_pos:
			var hb := skeleton.find_bone("Hips")
			if hb != -1:
				var rest: Transform3D = skeleton.get_bone_rest(hb)
				var ti := anim.add_track(Animation.TYPE_POSITION_3D)
				anim.track_set_path(ti, NodePath(skeleton_path + ":Hips"))
				anim.track_insert_key(ti, 0.0, rest.origin)
				added += 1
			else:
				push_error("RigKit: coverage: take '%s' lacks Hips position and the skeleton has no Hips" % full)
		if not rot.has("Hips"):
			push_error("RigKit: coverage: take '%s' arrived without Hips rotation (suspicious pack)" % full)
		if added > 0:
			injected += added
			takes_touched += 1
	if injected > 0:
		print("[RigKit] coverage: +%d rest tracks on %d takes (stripped-at-import bones reset-proofed)" % [injected, takes_touched])
