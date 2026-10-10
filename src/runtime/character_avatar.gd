class_name CharacterAvatar
extends Node3D

## Shared character body (runtime, NOT editor): owns the holder scaffold
## (Nude/slot scratch holders, Fused result, Hair) plus the whole build
## pipeline — nude/outfit/hair load, FitKit conform, pass-1 suppression,
## fusion into ONE skeleton + TWO meshes, toon dressing, per-slot colors,
## physics morphs. The character editor previews this node (driven by its
## menus); the game instances it (driven by GameState/config). One path, no
## drift. Emits rebuilt after every (re)build so hosts can re-anchor cameras
## and preview animations.
## Push policy (07/10, uniform): EVERYTHING skin-side writes depth_push —
## no face exemption. Mixed push (true-depth eyes vs pushed lids) let the
## eyeballs swallow millimeter-close lid skin (exorbités, both eyes).

signal rebuilt

const OUTFIT_DIR := "res://assets/meshes/outfits/"
const ARMOR_DIR := "res://assets/meshes/armor/"
## Slot -> subdir under the gender dir (user layout, kept as-is).
const SLOT_DIRS := {&"Body": "bodies", &"Arms": "hands", &"Legs": "legs", &"Feet": "feets", &"Head": "heads", &"Accessories": "accessories"}
const NUDE_DIR := "res://assets/meshes/characters/"
const GENDERS: Array[String] = ["Male", "Female"]
const OUTFITS: Array[String] = ["Peasant", "Ranger"]
## Extra test variants per slot (Blender-edited files): cycled after OUTFITS
## for that slot only. part_file returns "" when the combo ships no file.
const SLOT_EXTRA := {&"Body": ["PeasantB"], &"Accessories": ["RangerG"]}
const SLOTS: Array[StringName] = [&"Body", &"Arms", &"Legs", &"Feet", &"Head", &"Accessories"]
## Outfit color entries: outfits only (Skin/Hair/Eyebrows have their own
## submenus — no duplicates). Skin color lives in the Skin submenu.
const OUTFIT_COLOR_SLOTS: Array[StringName] = [&"Body", &"Arms", &"Legs", &"Feet", &"Head", &"Accessories"]
## Slots edited in albedo mode (quasi-white vendor textures with nothing to
## hue-shift: Hair + Eyebrows share the T_Hair set).
const ALBEDO_SLOTS: Array[StringName] = [&"Hair", &"Eyebrows", &"Beard", &"Eyelashes"]
## Hair styles (07/10, user-attributed): rigged-to-HeadBone vendor files,
## one mesh each, all verts 100% Head (verified headless). Beard ignored.
const HAIR_PART_DIR := "res://assets/meshes/characters/parts/"
const HAIR_FILES := {
	"Male": [&"Buzzed", &"SimpleParted"],
	"Female": [&"Buns", &"Long", &"BuzzedFemale"],
}
## Beard styles (07/10): same vendor pack/dir as hair, mounted the same way
## (rigid head-follow, albedo color). Male only for now — more files later,
## same plumbing as eyebrows (single vendor style prepared).
const BEARD_FILES := {"Male": [&"Beard"]}
## Fused-surface source substrings per color slot (src = source node name,
## recorded per surface at fusion). Skin reads the skin src list, slots read
## the cloth src list — a nude head can never leak into the Head slot.
const SLOT_SRC_KEYS := {
	&"Body": ["Body"], &"Arms": ["Arms"], &"Legs": ["Legs"],
	&"Feet": ["Feet", "Boot"], &"Head": ["Head", "Hood"],
	&"Accessories": ["Acc", "Gauntlet"],
	&"Skin": ["SuperHero", "Eye"],
	&"Eyebrows": ["Eyebrow"],
	&"Eyes": ["Eyes"],
}
## Physics silhouette pack (v1): slider key -> bones + scaled axes (Standard
## bone names). Applied as absolute bone-pose scale on the fused master
## skeleton, reapplied after every rebuild (new skeleton each time).
const PHYS_KEYS: Array[StringName] = [&"Height", &"Legs", &"Shoulders", &"Waist", &"Hips", &"Head"]
const PHYS_STEP := 0.01
## Bounds per row (07/10, eye-tuned): limbs/height stay near the authored
## body (90-110); Waist is tighter (95-105, the nude is already muscular —
## 90 puts hands inside the torso, 110+ reads non-human).
const PHYS_LIMITS := {
	&"Height": [0.9, 1.1], &"Legs": [0.9, 1.1], &"Shoulders": [0.9, 1.1],
	&"Waist": [0.95, 1.05], &"Hips": [0.9, 1.1], &"Head": [0.9, 1.1],
}
const PHYS_BONES := {
	&"Height": {"bones": [&"Root"], "axes": Vector3(1, 1, 1)},
	&"Legs": {"bones": [&"LeftUpperLeg", &"RightUpperLeg", &"LeftLowerLeg", &"RightLowerLeg"], "axes": Vector3(1, 0, 1)},
	&"Shoulders": {"bones": [&"LeftShoulder", &"RightShoulder"], "axes": Vector3(1, 0, 0)},
	&"Waist": {"bones": [&"Spine", &"Chest"], "axes": Vector3(1, 0, 1)},
	&"Hips": {"bones": [&"Hips"], "axes": Vector3(1, 0, 1)},
	&"Head": {"bones": [&"Head"], "axes": Vector3(1, 1, 1)},
}

## Build flags (set by the host before full_rebuild): FitKit conform on/off,
## pass-1 suppression on/off (--nosuppress eye recipe).
var use_fitkit := true
var no_suppress := false
## Avatar cache: OFF during the cut-detection dev phase (every switch must
## rebuild). Re-enable when the cuts are final.
const USE_CACHE := false
var _avatar_cache := {} # build key -> {skin: ArrayMesh, cloth: ArrayMesh, skin_srcs, cloth_srcs}

var _gender := 0
var _outfit := {} # StringName slot -> int index into OUTFITS
var _hair := 0 # index into hair_styles() (0 = None/bald)
var _beard := 0 # index into beard_styles() (0 = None/clean-shaven)
var _eyebrow := 0 # index into EYEBROW_STYLES (single Default for now)
var _eye := 0 # index into EYE_STYLES (single Default for now)
var _phys := {} # StringName phys key -> float scale (1.0 default)
## Face shape (Face submenu): global head form, Width = Head XZ, Length =
## Head Y. Multiplies with the Physics Head size row (uniform): final Head
## scale = (h*w, h*l, h*w). Independent resets either way.
var _face := {&"Width": 1.0, &"Length": 1.0}
const FACE_KEYS: Array[StringName] = [&"Width", &"Length"]
const FACE_LIMITS := [0.9, 1.1]
var _color_params := {} # StringName color slot -> {hue, sat, val}
var _crown_rest := 0.0 # rest crown height (fused mesh AABB, skeleton space)
var _nude_snap := {"ok": false}
var _avatar_skin_src := PackedStringArray()
var _avatar_cloth_src := PackedStringArray()
var _last_vols := {}
var _last_cdata := {}
var _dresser: ColorEditor = null # injected panel (editor) or headless fallback
var _hud = null # host HUD for the height readout (nullable, duck-typed)


func _ready() -> void:
	for h in ["Nude", "Fused", "Hair", "Beard"]:
		_add_holder(h)
	for slot in SLOTS:
		_add_holder(String(slot))
	for slot in SLOTS:
		_outfit[slot] = 0
	for key in PHYS_KEYS:
		_phys[key] = 1.0


func _add_holder(holder_name: String) -> void:
	if get_node_or_null(holder_name) != null:
		return
	var h := Node3D.new()
	h.name = holder_name
	add_child(h)


## Host wiring: live dresser panel (editor) or null (headless fallback
## created on demand); HUD for the height status line (nullable).
func setup(dresser: ColorEditor, hud) -> void:
	_dresser = dresser
	_hud = hud


func _reset_dress(holder: Node, albedo_mode := false) -> void:
	if _dresser == null:
		_dresser = ColorEditor.new()
	_dresser.reset_target(holder, albedo_mode)


## Full build: nude + slots + fusion. Hosts call this instead of reaching
## into _apply_nude/_rebuild_avatar (kept public for capture recipes).
func full_rebuild() -> void:
	_apply_nude()
	rebuild_avatar()


## Post-build session state: fused materials/skeleton are fresh every
## rebuild (sources freed), so stored colors + physics reapply here, then
## hosts re-anchor (signal below).
func _post_build() -> void:
	_apply_hair()
	_apply_beard()
	_apply_eyebrow()
	_apply_eye()
	_apply_eyelashes()
	_reapply_colors()
	_apply_physics()
	_snap_pristine()
	_sculpt_fused()
	rebuilt.emit()


## Rest-pose world transform of a bone (pose-independent: identical at build
## and mid-animation, and identical to the exporter frame — live poses from
## the preview animation or physics scales must never move the sculpt boxes).
func _bone_rest_world(sk: Skeleton3D, bi: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur := bi
	while cur != -1:
		t = sk.get_bone_rest(cur) * t
		cur = sk.get_bone_parent(cur)
	return sk.global_transform * t


## Pristine fused Skin mesh (sculpt source of truth: every sculpt pass starts
## from here, so repeated adjusts never accumulate). Refreshed each build.
var _skin_pristine: ArrayMesh = null
## Pristine mounted face-part meshes (follow-sculpt source of truth, same
## role as _skin_pristine): slot -> ArrayMesh, stored at mount time.
var _face_pristine := {}
## Shell-follow glue (09/10): nearest-skin correspondence. _glue_qs = combined
## Head-local pristine Skin verts (first Skin MI, eye surfaces excluded, same
## order as the retained fields); _glue_fields = per-key combined offsets of
## the current bake; _glue_grid maps 10mm cells to combined indices (rebuilt
## when the skin mesh changes); _glue_map caches hair-mesh rid -> nearest
## skin index per hair vert (both sides pristine, so static).
const GLUE_CELL := 0.01
var _glue_qs := PackedVector3Array()
var _glue_fields := {}
var _glue_grid := {}
var _glue_grid_rid := -1
var _glue_map := {}


func _snap_pristine() -> void:
	_skin_pristine = null
	_adj_cache.clear() # keys are mesh rids: rebuild = new meshes
	_glue_grid_rid = -1 # skin rebuilt: grid + maps rebuilt lazily
	for mi in _avatar_mis():
		var mmi := mi as MeshInstance3D
		if mmi != null and mmi.name == &"Skin" and mmi.mesh != null:
			_skin_pristine = mmi.mesh as ArrayMesh


## Menu verbs (GenericMenu value rows: get = display, adjust(L/R) = cycle,
## reset(A/E) = default). Adjust ignores its return; the row re-renders.
func gender_display() -> String:
	return GENDERS[_gender]


func adjust_gender(dir: int) -> void:
	_gender = posmod(_gender + dir, GENDERS.size())
	_hair = 0
	_beard = 0
	full_rebuild()
	print("[Character] gender %s" % GENDERS[_gender])


func reset_gender() -> void:
	_gender = 0
	_hair = 0
	_beard = 0
	full_rebuild()


func slot_display(slot: StringName) -> String:
	var opts := _slot_outfits(slot)
	if part_file(GENDERS[_gender], opts[int(_outfit[slot])], slot).is_empty():
		return "--"
	return opts[int(_outfit[slot])]


func adjust_slot(slot: StringName, dir: int) -> void:
	_outfit[slot] = posmod(int(_outfit[slot]) + dir, _slot_outfits(slot).size())
	full_rebuild()


func reset_slot(slot: StringName) -> void:
	_outfit[slot] = 0
	full_rebuild()


## glTF file for a (gender, outfit, slot) combo, "" when the combo ships no
## part (Peasant has no Head/Accessories; male ships no Arms files at all —
## bare nude arms; pauldrons live unwired under armor/ until the armor pass).
## Ranger side names stay irregular (Feet_Boots, Head_Hood) until the user
## rename pass; a final existence guard keeps deleted files loud-free.
func part_file(gender: String, outfit: String, slot: StringName) -> String:
	var dir := "%s%s/%s/" % [OUTFIT_DIR, gender.to_lower(), String(SLOT_DIRS.get(slot, "bodies"))]
	var path := ""
	match slot:
		&"Head":
			if outfit != "Ranger":
				return ""
			path = "%s%s_%s_Head_Hood.gltf" % [dir, gender, outfit]
		&"Accessories":
			if outfit == "RangerG" and gender == "Female":
				path = "%sfemale/gauntlets/Female_Ranger_Gauntlets.gltf" % ARMOR_DIR
			else:
				return ""
		&"Feet":
			if gender == "Male" and outfit == "Ranger":
				path = "%s%s_%s_Feet_Boots.gltf" % [dir, gender, outfit]
			else:
				path = "%s%s_%s_%s.gltf" % [dir, gender, outfit, String(slot)]
		&"Body", &"Arms", &"Legs":
			if outfit == "PeasantB" and slot == &"Body" and gender == "Female":
				path = "%s%s_%s_Body_B.gltf" % [dir, gender, outfit.trim_suffix("B")]
			else:
				path = "%s%s_%s_%s.gltf" % [dir, gender, outfit, String(slot)]
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	return path


## Outfit choices for a slot: base OUTFITS + test extras (variant files).
func _slot_outfits(slot: StringName) -> Array:
	return OUTFITS + SLOT_EXTRA.get(slot, [])


func _clear_holder(h: Node) -> void:
	if h == null:
		return
	for c in h.get_children():
		h.remove_child(c)
		c.queue_free()


## Swap one slot to its current (gender, outfit) combo, dressed toon.
## Raw vendor part + in-memory FitKit conform (both genders) — no files.
func _apply_slot(slot: StringName) -> void:
	var holder := get_node_or_null(String(slot)) as Node3D
	if holder == null:
		push_error("[Character] missing slot node %s" % slot)
		return
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	var path := part_file(GENDERS[_gender], _slot_outfits(slot)[int(_outfit[slot])], slot)
	var want_fit := use_fitkit and not path.is_empty()
	if path.is_empty():
		print("[Character] %s: no part (%s %s)" % [String(slot), GENDERS[_gender], String(_slot_outfits(slot)[int(_outfit[slot])])])
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("[Character] cannot load %s" % path)
		return
	holder.add_child(packed.instantiate())
	if want_fit:
		if _nude_snap.get("ok", false):
			# Cloth is kept 100% authored (03/10: fit_pushout removed — it
			# deformed glove fingers via wrong-finger nearest pushes, and
			# the inward cover tier handles buried cloth instead).
			# Vendor skin: conformed snug (skin-tight registration witness).
			FitKit.fit_holder(holder, _nude_snap, slot, _gender, true)
		else:
			push_error("[Character] FitKit without nude snapshot")
	_reset_dress(holder)
	print("[Character] %s -> %s" % [String(slot), path.get_file()])


func _apply_all() -> void:
	for slot in SLOTS:
		_apply_slot(slot)


## Nude base body (Superhero fullbody: skin everywhere but underwear, head
## included) under every outfit — the depth-push skin side. Garments cover
## it; bare parts (head, hands, gaps) show through. Reloaded on gender swap.
## Uniform push (07/10): the old FACE_NODES exemption is gone — mixed push
## (true-depth eyes vs pushed lids) let the eyeballs swallow lid skin.
func nude_file(gender: String) -> String:
	return "%sSuperhero_%s_FullBody.gltf" % [NUDE_DIR, gender]


func _apply_nude() -> void:
	var holder := get_node_or_null("Nude") as Node3D
	if holder == null:
		push_error("[Character] missing Nude slot node")
		return
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	var packed := load(nude_file(GENDERS[_gender])) as PackedScene
	if packed == null:
		push_error("[Character] cannot load %s" % nude_file(GENDERS[_gender]))
		return
	holder.add_child(packed.instantiate())
	_reset_dress(holder)
	# The nude never casts shadows: buried cloth would otherwise sit in the
	# torso's shadow and render near-black (dark pack textures + filmic).
	# Ground/body shadows still come from the garments; bare head/hands
	# lose their cast shadow (editor-preview tradeoff, documented).
	for mi in ColorEditor._meshes_under(holder):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("[Character] Nude -> %s" % nude_file(GENDERS[_gender]).get_file())
	_nude_snap = FitKit.snapshot_nude(holder)


func slot_skeleton(slot: StringName) -> Skeleton3D:
	var holder := get_node_or_null(String(slot))
	if holder == null:
		return null
	var found := holder.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D


## Build key: gender + per-slot outfit (only combos with parts matter, the
## full key is cheaper to reason about).
## TODO cache: when re-enabling, include no_suppress (and
## use_fitkit) in the key, or a --nosuppress run will be served cut geometry.
func _avatar_key() -> String:
	var k := [GENDERS[_gender]]
	for slot in SLOTS:
		k.append(str(int(_outfit[slot])))
	return "|".join(k)


## The fused skeleton + fused mesh (null/empty before the first rebuild).
func _avatar_skeleton() -> Skeleton3D:
	return master_skeleton()


func master_skeleton() -> Skeleton3D:
	var fused := get_node_or_null("Fused")
	if fused == null:
		return null
	var found := fused.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D


func _avatar_mis() -> Array:
	var fused := get_node_or_null("Fused")
	var out := []
	if fused == null:
		return out
	for c in fused.get_children():
		if c is MeshInstance3D:
			out.append(c)
	return out


func avatar_mis() -> Array:
	return _avatar_mis()


func _avatar_mi() -> MeshInstance3D:
	return _avatar_skin_mi() if _avatar_skin_mi() != null else _avatar_cloth_mi()


func _avatar_skin_mi() -> MeshInstance3D:
	var fused := get_node_or_null("Fused")
	if fused == null:
		return null
	return fused.get_node_or_null("Skin") as MeshInstance3D


func _avatar_cloth_mi() -> MeshInstance3D:
	var fused := get_node_or_null("Fused")
	if fused == null:
		return null
	return fused.get_node_or_null("Cloths") as MeshInstance3D


## Moves the master skeleton under Fused and hangs the two fused
## MeshInstances on it (Skin + Cloths share the one skeleton so the X-ray
## toggle can show each side). Sources are freed by the caller.
func _mount_avatar(master: Skeleton3D, skin: ArrayMesh, cloth: ArrayMesh, skin_srcs: PackedStringArray, cloth_srcs: PackedStringArray) -> void:
	var fused := get_node_or_null("Fused")
	if fused == null or master == null:
		push_error("[Merge] cannot mount (missing fused/master)")
		return
	_clear_holder(fused)
	var mp := master.get_parent()
	if mp != null:
		mp.remove_child(master)
	fused.add_child(master)
	# Stowaways (ghost found 08/10 via wireframe): the nude MeshInstance3Ds
	# are children of the master skeleton node, so reparenting it drags the
	# authored body along — rendered over the fused copy, masking every
	# recession (protrusions poke past it, recessions sink behind it, per the
	# depth test). All nude surfaces are baked into Skin/Cloths (eyes and
	# brows included — their slots read fused materials), so free them here.
	for stow in master.find_children("*", "MeshInstance3D", true, false):
		(stow as Node).queue_free()
	for entry in [["Skin", skin], ["Cloths", cloth]]:
		if entry[1] == null or (entry[1] as ArrayMesh).get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = String(entry[0])
		mi.mesh = entry[1] as ArrayMesh
		fused.add_child(mi)
		mi.skeleton = mi.get_path_to(master)
	_avatar_skin_src = skin_srcs
	_avatar_cloth_src = cloth_srcs


## Full rebuild: cache hit = nude skeleton + cached meshes only (garments are
## never reloaded); miss = load + FitKit fit + pass-1 volume suppression +
## fusion. Sources (Nude/slot holders) are freed — Fused is the only body
## left.
func rebuild_avatar() -> void:
	var t0 := Time.get_ticks_msec()
	var key := _avatar_key()
	var nude_holder := get_node_or_null("Nude")
	if USE_CACHE and _avatar_cache.has(key):
		var e: Dictionary = _avatar_cache[key]
		var master := slot_skeleton(&"Nude")
		_mount_avatar(master, e["skin"] as ArrayMesh, e["cloth"] as ArrayMesh, e["skin_srcs"] as PackedStringArray, e["cloth_srcs"] as PackedStringArray)
		_clear_holder(nude_holder)
		for slot in SLOTS:
			_clear_holder(get_node_or_null(String(slot)))
		_post_build()
		print("[Merge] cache hit %s (%dms)" % [key, Time.get_ticks_msec() - t0])
		return
	_apply_all()
	var master := slot_skeleton(&"Nude")
	if master == null:
		push_error("[Merge] no nude skeleton, avatar skipped")
		return
	var holders := {}
	for slot in SLOTS:
		holders[slot] = get_node_or_null(String(slot))
	var gholders: Array = []
	for slot in SLOTS:
		gholders.append(holders[slot])
	if not no_suppress:
		var sup := FitKit.suppress_covered(nude_holder, gholders, master)
		if bool(sup.get("ok", false)):
			_last_vols = sup.get("vols", {})
			_last_cdata = sup.get("cdata", {})
		else:
			_last_vols = {}
			_last_cdata = {}
	var parts: Array = []
	for mi in FitKit.meshes_under(nude_holder):
		parts.append({"mi": mi, "skeleton": master, "kind": "skin"})
	for slot in SLOTS:
		var sk := slot_skeleton(slot)
		if sk == null:
			continue
		for mi in FitKit.meshes_under(holders[slot]):
			parts.append({"mi": mi, "skeleton": sk, "kind": "cloth"})
	var res := FitKit.fuse_avatar(master, parts)
	if not res.get("ok", false):
		push_error("[Merge] fusion failed, sources kept")
		return
	_mount_avatar(master, res["skin_mesh"] as ArrayMesh, res["cloth_mesh"] as ArrayMesh, res["skin_srcs"] as PackedStringArray, res["cloth_srcs"] as PackedStringArray)
	_clear_holder(nude_holder)
	for slot in SLOTS:
		_clear_holder(get_node_or_null(String(slot)))
	_avatar_cache[key] = {"skin": res["skin_mesh"], "cloth": res["cloth_mesh"], "skin_srcs": res["skin_srcs"], "cloth_srcs": res["cloth_srcs"]}
	if not USE_CACHE:
		_avatar_cache.clear()
	_post_build()
	print("[Merge] built %s (%dms, cached keys=%d, suppress=%s)" % [key, Time.get_ticks_msec() - t0, _avatar_cache.size(), str(not no_suppress)])


## Pass-1 volume data for the editor overlay (empty when suppressed off).
func last_volumes() -> Dictionary:
	return _last_vols


func last_cdata() -> Dictionary:
	return _last_cdata


## Holder-dressed materials (Hair/Beard/face parts): the mounted MI surfaces,
## override (toon) preferred over base. Empty when nothing mounted.
func _holder_mats(slot: StringName) -> Array:
	var out := []
	var holder := get_node_or_null(String(slot))
	if holder == null:
		return out
	for mi in ColorEditor._meshes_under(holder):
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.mesh == null:
			continue
		for s in mmi.mesh.get_surface_count():
			var om := mmi.get_surface_override_material(s) as ShaderMaterial
			if om != null:
				out.append(om)
				continue
			var base := mmi.mesh.surface_get_material(s) as ShaderMaterial
			if base != null:
				out.append(base)
	return out


## Colors menu: fused materials whose source belongs to the slot (Skin =
## skin src list, slots = cloth src list). Empty = no part, toast only.
func slot_mats(slot: StringName) -> Array:
	var out := []
	if slot == &"Hair" or slot == &"Beard" or slot == &"Eyelashes":
		return _holder_mats(slot)
	if slot == &"Eyebrows" or slot == &"Eyes":
		# Mounted part wins (male); empty holder = fused nude carries them
		# (female until its export pass) — fall through to the fused lookup.
		var hm := _holder_mats(slot)
		if not hm.is_empty():
			return hm
	var keys: Array = SLOT_SRC_KEYS.get(slot, [])
	var skin_side := slot == &"Skin" or slot == &"Eyebrows" or slot == &"Eyes" # face bits live on the nude
	for e in _avatar_each_mat():
		var src := String(e["src"])
		var from_skin := _avatar_skin_src.has(src)
		if from_skin != skin_side:
			continue
		var low := src.to_lower()
		if slot == &"Skin" and (low.contains("eyebrow") or low.contains("eyes")):
			continue # brows + eyes have their own slots
		for k in keys:
			if low.contains(String(k).to_lower()):
				out.append(e["mat"])
				break
	return out


## Stored per-slot colors reapplied to the fresh fused materials. Albedo-mode
## slots (Hair/Eyebrows/Beard): albedo from HSV, shift params neutral. Albedo slots
## with no stored color get ALBEDO_DEFAULTS (Hair already mounts dressed at
## defaults; Eyebrows are born inside the hue-shift-dressed nude, so without
## this they would open white with a dead Color row).
func _reapply_colors() -> void:
	for slot in _color_params:
		var p: Dictionary = _color_params[slot]
		if slot in ALBEDO_SLOTS:
			var c := Color.from_hsv(float(p.get("hue", 0.0)) / 360.0, float(p.get("sat", 0.0)), float(p.get("val", 1.0)))
			for m in slot_mats(slot):
				(m as ShaderMaterial).set_shader_parameter("albedo", c)
				(m as ShaderMaterial).set_shader_parameter("hue_shift_deg", 0.0)
				(m as ShaderMaterial).set_shader_parameter("sat_mult", 1.0)
				(m as ShaderMaterial).set_shader_parameter("val_mult", 1.0)
			continue
		for m in slot_mats(slot):
			(m as ShaderMaterial).set_shader_parameter("hue_shift_deg", float(p.get("hue", 0.0)))
			(m as ShaderMaterial).set_shader_parameter("sat_mult", float(p.get("sat", 1.0)))
			(m as ShaderMaterial).set_shader_parameter("val_mult", float(p.get("val", 1.0)))
	for slot in ALBEDO_SLOTS:
		if _color_params.has(slot):
			continue
		var d: Dictionary = ColorEditor.ALBEDO_DEFAULTS
		var c := Color.from_hsv(float(d.get("hue", 0.0)) / 360.0, float(d.get("sat", 0.5)), float(d.get("val", 0.5)))
		for m in slot_mats(slot):
			(m as ShaderMaterial).set_shader_parameter("albedo", c)
			(m as ShaderMaterial).set_shader_parameter("hue_shift_deg", 0.0)
			(m as ShaderMaterial).set_shader_parameter("sat_mult", 1.0)
			(m as ShaderMaterial).set_shader_parameter("val_mult", 1.0)


func store_color(slot: StringName, params: Dictionary) -> void:
	_color_params[slot] = params
	print("[Character] color %s %s" % [String(slot), str(_color_params[slot])])


## Physics menu verbs (GenericMenu value rows, same contract as outfits).
func phys_display(key: StringName) -> String:
	return "%d%%" % int(round(float(_phys.get(key, 1.0)) * 100.0))


func adjust_phys(key: StringName, dir: int) -> void:
	var lim: Array = PHYS_LIMITS.get(key, [0.8, 1.3])
	_phys[key] = clampf(float(_phys.get(key, 1.0)) + float(dir) * PHYS_STEP, float(lim[0]), float(lim[1]))
	_apply_physics()


func reset_phys(key: StringName) -> void:
	_phys[key] = 1.0
	_apply_physics()


## Face menu verbs (same value-row contract as physics). Width scales Head
## XZ, Length scales Head Y; both multiply the Head size row.
func face_display(key: StringName) -> String:
	return "%d%%" % int(round(float(_face.get(key, 1.0)) * 100.0))


func adjust_face(key: StringName, dir: int) -> void:
	_face[key] = clampf(float(_face.get(key, 1.0)) + float(dir) * PHYS_STEP, float(FACE_LIMITS[0]), float(FACE_LIMITS[1]))
	_apply_physics()


func reset_face(key: StringName) -> void:
	_face[key] = 1.0
	_apply_physics()


## Face-sculpt rows (nose/mouth/chin): key -> painted REGION (face_sculpt.json
## v2, Head-local meter points), head-local axis, symmetric widen or direct
## push, range. Values are cm (displayed mm); defaults 0 = authored mesh
## untouched. Mirror rows scale about the region centroid (flanks move most,
## center fixed — no bunching, no fold); the X half-extent comes from the
## baked points.
const SCULPT_PATH := "res://data/characters/face_sculpt.json"
const SCULPT_KEYS: Array[StringName] = [&"NoseL", &"NoseW", &"MouthW", &"Chin", &"NoseBridge", &"NoseTip", &"NostrilFlare", &"NoseLength", &"NosePosition", &"LipUpper", &"LipLower", &"MouthCorners", &"MouthPosition", &"MouthForward", &"NoseTipSize", &"NoseTipAngle", &"NoseCurve", &"MouthPout", &"EyelidHeavy", &"EyeDepth", &"EyeHeight", &"EyeSpacing", &"EyeSize", &"EyeAngle", &"BrowHeight", &"BrowThick", &"BrowAngle", &"BrowDepth", &"JawWidth", &"ChinLength", &"ChinWidth", &"ChinProject", &"ChinCleft", &"CheekboneWidth", &"CheekboneHeight", &"CheekFullness", &"FaceFullness", &"ForeheadHeight", &"ForeheadWidth", &"BrowRidgeDepth", &"EarSize", &"EarRotation", &"EarlobeLength", &"EarPoint"]
const SCULPT_STEP := 0.1
const SCULPT_SPEC := {
	&"NoseL": {"region": "Nose", "menu": "nose", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 1.0},
	&"NoseW": {"region": "Nose", "menu": "nose", "axis": Vector3(1, 0, 0), "mirror": true, "max_cm": 0.8},
	&"MouthW": {"region": "Mouth", "menu": "mouth", "axis": Vector3(1, 0, 0), "mirror": true, "max_cm": 0.8},
	&"Chin": {"region": "Chin", "menu": "jaw", "axis": Vector3(0, -0.55, 1), "mirror": false, "max_cm": 1.0},
	&"NoseBridge": {"region": "NoseBridge", "menu": "nose", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 1.0},
	&"NoseTip": {"region": "NoseTip", "menu": "nose", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 0.8},
	&"NostrilFlare": {"region": "NostrilFlare", "menu": "nose", "axis": Vector3(1, 0, 0), "mirror": true, "max_cm": 0.8},
	&"NoseLength": {"region": "NoseTip", "menu": "nose", "axis": Vector3(0, -1, 0), "mirror": false, "max_cm": 1.0},
	&"NosePosition": {"region": "Nose", "menu": "nose", "axis": Vector3(0, 1, 0), "mirror": false, "max_cm": 0.8},
	&"LipUpper": {"region": "UpperLip", "menu": "mouth", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 0.8},
	&"LipLower": {"region": "LowerLip", "menu": "mouth", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 0.8},
	&"MouthCorners": {"region": "MouthCorners", "menu": "mouth", "axis": Vector3(0, 1, 0), "mirror": false, "max_cm": 0.8},
	&"MouthPosition": {"region": "Mouth", "menu": "mouth", "axis": Vector3(0, 1, 0), "mirror": false, "max_cm": 0.8},
	&"MouthForward": {"region": "Mouth", "menu": "mouth", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 0.8},
	&"NoseTipSize": {"region": "NoseTip", "menu": "nose", "mode": "scale", "rate": 0.15, "mirror": false, "max_cm": 1.0},
	&"NoseTipAngle": {"region": "NoseTip", "menu": "nose", "mode": "rot", "axis": Vector3(1, 0, 0), "deg": 12.0, "mirror": false, "max_cm": 1.0},
	&"NoseCurve": {"region": "NoseBridge", "menu": "nose", "mode": "falloff", "axis": Vector3(0, 0, 1), "along": Vector3(0, 1, 0), "mirror": false, "max_cm": 1.0},
	&"MouthPout": {"region": "UpperLip", "menu": "mouth", "mode": "falloff", "axis": Vector3(0, 0, 1), "along": Vector3(1, 0, 0), "mirror": false, "max_cm": 0.8},
	&"EyelidHeavy": {"region": "UpperEyelid", "menu": "eyes", "axis": Vector3(0, -1, 0), "mirror": false, "max_cm": 0.4},
	&"EyeDepth": {"region": "Eyelids", "menu": "eyes", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 0.8},
	&"EyeHeight": {"region": "Eyelids", "menu": "eyes", "axis": Vector3(0, 1, 0), "mirror": false, "max_cm": 0.8},
	&"EyeSpacing": {"region": "Eyelids", "menu": "eyes", "mode": "sideshift", "mirror": false, "max_cm": 0.8},
	&"EyeSize": {"region": "Eyelids", "menu": "eyes", "mode": "sidescale", "rate": 0.15, "mirror": false, "max_cm": 0.8},
	&"EyeAngle": {"region": "Eyelids", "menu": "eyes", "mode": "siderot", "axis": Vector3(0, 0, 1), "deg": 10.0, "mirror": false, "max_cm": 0.8},
	&"BrowHeight": {"region": "Brows", "menu": "eyes", "axis": Vector3(0, 1, 0), "mirror": false, "max_cm": 0.8},
	&"BrowThick": {"region": "Brows", "menu": "eyes", "mode": "scale", "axis": Vector3(0, 1, 0), "rate": 0.15, "mirror": false, "max_cm": 1.0},
	&"BrowAngle": {"region": "Brows", "menu": "eyes", "mode": "siderot", "axis": Vector3(0, 0, 1), "deg": 10.0, "mirror": false, "max_cm": 0.8},
	&"BrowDepth": {"region": "BrowRidge", "menu": "eyes", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 0.4},
	&"JawWidth": {"region": "Jaw", "menu": "jaw", "axis": Vector3(1, 0, 0), "mirror": true, "max_cm": 0.8},
	&"ChinLength": {"region": "Chin", "menu": "jaw", "axis": Vector3(0, -1, 0), "mirror": false, "max_cm": 1.0},
	&"ChinWidth": {"region": "Chin", "menu": "jaw", "axis": Vector3(1, 0, 0), "mirror": true, "max_cm": 0.8},
	&"ChinProject": {"region": "Chin", "menu": "jaw", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 1.0},
	&"ChinCleft": {"region": "ChinCleft", "menu": "jaw", "axis": Vector3(0, 0, -1), "mirror": false, "max_cm": 0.5},
	&"CheekboneWidth": {"region": "Cheekbones", "menu": "cheeks", "axis": Vector3(1, 0, 0), "mirror": true, "max_cm": 0.8},
	&"CheekboneHeight": {"region": "Cheekbones", "menu": "cheeks", "axis": Vector3(0, 1, 0), "mirror": false, "max_cm": 0.8},
	&"CheekFullness": {"region": "Cheeks", "menu": "cheeks", "mode": "scale", "rate": 0.15, "mirror": false, "max_cm": 0.8},
	&"FaceFullness": {"region": "LowerFace", "menu": "cheeks", "mode": "scale", "rate": 0.15, "mirror": false, "max_cm": 0.8},
	&"ForeheadHeight": {"region": "Forehead", "menu": "forehead", "axis": Vector3(0, 1, 0), "mirror": false, "max_cm": 0.8},
	&"ForeheadWidth": {"region": "Forehead", "menu": "forehead", "axis": Vector3(1, 0, 0), "mirror": true, "max_cm": 0.8},
	&"BrowRidgeDepth": {"region": "BrowRidge", "menu": "forehead", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 0.4},
	&"EarSize": {"region": "Ears", "menu": "ears", "mode": "root", "rate": 0.45, "orate": 0.09, "mirror": false, "max_cm": 0.8, "rings": 1},
	&"EarRotation": {"region": "Ears", "menu": "ears", "mode": "rootrot", "axis": Vector3(0, 1, 0), "deg": 15.0, "mirror": false, "max_cm": 0.8, "rings": 1},
	&"EarlobeLength": {"region": "Lobe", "menu": "ears", "mode": "tip", "along": Vector3(0, 1, 0), "end": "min", "axis": Vector3(0, -1, 0), "rate": 0.6, "mirror": false, "max_cm": 0.8, "rings": 1},
	&"EarPoint": {"region": "EarTip", "menu": "ears", "mode": "tip", "along": Vector3(0, 1, 0), "end": "max", "axis": Vector3(0, 1, 0), "rate": 0.6, "mirror": false, "max_cm": 4.8, "rings": 1},
}
## Face-part follow (09/10): holder slot -> driving sculpt keys. Compact rigid
## parts (eyes, lashes, brows — 100% Head) bake the SUM of per-key mask means
## into their verts (same Head-frame math as the skin), so socket rows never
## strand them and rows superpose without diluting each other. Eyes track the
## socket (Depth/Height) but NOT lid weight; lashes ride the lids; brows
## ride the ridge (both menus' depth rows). Hair is a shell, not a lump
## (09/10 live: every proxy failed — z-ramp starved the temples at ~40%,
## full-width breathed the whole cap and dived inside the skin when
## narrowing, bbox-column starved verts just outside the paint): each hair
## vert copies the sculpt offset of its NEAREST skin vert ("glue"), so the cap
## preserves its rest gap exactly, both directions, for every driving key.
const SCULPT_FOLLOW := {
	&"Eyes": [&"EyeDepth", &"EyeHeight", &"EyeSpacing", &"EyeSize"],
	&"Eyelashes": [&"EyeDepth", &"EyeHeight", &"EyelidHeavy", &"EyeSpacing", &"EyeSize", &"EyeAngle"],
	&"Eyebrows": [&"BrowDepth", &"BrowRidgeDepth", &"BrowHeight", &"BrowThick", &"BrowAngle"],
	&"Hair": {"keys": [&"ForeheadHeight", &"ForeheadWidth"], "glue": true},
}
## Follow keys whose means split per side (EyeSpacing: one global mean would
## cancel to ~0 across the symmetric orbits). Split at the driving region's
## cx; each part vert takes its own side's mean.
const SCULPT_FOLLOW_SIDES := [&"EyeSpacing"]
## Follow keys applied as rigid per-side ROTATION (EyeAngle: lashes ride the
## lid tilt — a translation mean would read ~0). Same angle/pivot convention
## as the siderot skin mode. Balls stay out: the globe must not roll.
const SCULPT_FOLLOW_ROT := [&"EyeAngle", &"BrowAngle"]
## Follow keys applied as per-side DILATION about the socket centroid
## (EyeSize: balls track the aperture with the skin rate, so a shrinking
## socket never clips the globe — and growing sockets grow the balls).
const SCULPT_FOLLOW_SCALE := [&"EyeSize", &"BrowThick"]
## Shell-follow zoning (m, test contract only): the hairline column moves,
## everything past HAIR_HALO stays frozen.
const HAIR_HALO := 0.025
var _sculpt := {} # StringName sculpt key -> float cm (0.0 default)
var _sculpt_cache := {} # gender -> regions dict from SCULPT_PATH (lazy)


func sculpt_display(key: StringName) -> String:
	return "%+dmm" % int(round(float(_sculpt.get(key, 0.0)) * 10.0))


func adjust_sculpt(key: StringName, dir: int) -> void:
	var spec: Dictionary = SCULPT_SPEC.get(key, {})
	_sculpt[key] = clampf(float(_sculpt.get(key, 0.0)) + float(dir) * SCULPT_STEP, -float(spec.get("max_cm", 1.0)), float(spec.get("max_cm", 1.0)))
	_sculpt_fused() # live on the fused mesh, no rebuild (reapplied in _post_build)


func reset_sculpt(key: StringName) -> void:
	_sculpt[key] = 0.0
	_sculpt_fused()


## Sculpt regions for a gender (face_sculpt.json v2): region -> {pts (0.01mm
## Vector3i set), cx (centroid x), hx (x half-extent), n, c (centroid), cL/cR
## (per-side centroids split at cx, one-sided masks = c)}. Missing file or
## gender section = no sculpt (Female until its authoring pass). Lazy cache.
## Positions are nude-asset Head-frame meters: the fused Skin keeps them
## bit-exact (suppression deletes, never moves; push is shader-depth only),
## so exact quantized keys match. Deleted (suppressed) mask points simply
## never match — coverage asserts pin the hit rate instead of failing silent.
const SCULPT_QUANT := 100000.0
func _sculpt_regions() -> Dictionary:
	if _sculpt_cache.has(GENDERS[_gender]):
		return _sculpt_cache[GENDERS[_gender]]
	var out := {}
	var doc: Dictionary = JsonFile.load_object(SCULPT_PATH)
	var sec: Dictionary = (doc.get(GENDERS[_gender], {}) as Dictionary).get("regions", {})
	for region in sec:
		var pts := {}
		var c := Vector3.ZERO
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		var minax := 1e9
		var n := 0
		for p in ((sec[region] as Dictionary).get("points", []) as Array):
			var pa: Array = p
			var key := Vector3i(int(round(float(pa[0]) * SCULPT_QUANT)), int(round(float(pa[1]) * SCULPT_QUANT)), int(round(float(pa[2]) * SCULPT_QUANT)))
			if pts.has(key):
				continue
			pts[key] = true
			var fp := Vector3(float(pa[0]), float(pa[1]), float(pa[2]))
			c += fp
			mn = mn.min(fp)
			mx = mx.max(fp)
			minax = minf(minax, absf(fp.x))
			n += 1
		if n > 0:
			c /= float(n)
			# Per-side centroids (per-side socket math: EyeSpacing/Size/
			# Angle). Split at the centroid x; one-sided masks fall back
			# to the global centroid so the modes stay total.
			var cl := Vector3.ZERO
			var cr := Vector3.ZERO
			var nl := 0
			var nr := 0
			for p in ((sec[region] as Dictionary).get("points", []) as Array):
				var pa2: Array = p
				var fp := Vector3(float(pa2[0]), float(pa2[1]), float(pa2[2]))
				if fp.x < c.x:
					cl += fp
					nl += 1
				else:
					cr += fp
					nr += 1
			if nl == 0:
				cl = c
			else:
				cl /= float(nl)
			if nr == 0:
				cr = c
			else:
				cr /= float(nr)
			out[String(region)] = {"pts": pts, "cx": c.x, "hx": maxf(mx.x - c.x, c.x - mn.x), "ix": minax, "c": c, "cL": cl, "cR": cr, "mn": mn, "mx": mx, "n": n}
	_sculpt_cache[GENDERS[_gender]] = out
	return out


## Mask membership of a Head-local point (chartest gating + paint validation).
static func sculpt_key(q: Vector3) -> Vector3i:
	return Vector3i(int(round(q.x * SCULPT_QUANT)), int(round(q.y * SCULPT_QUANT)), int(round(q.z * SCULPT_QUANT)))


func sculpt_in_region(region: String, q: Vector3) -> bool:
	var r: Dictionary = _sculpt_regions().get(region, {})
	if r.is_empty():
		return false
	return (r["pts"] as Dictionary).has(sculpt_key(q))


## Region centroid x + x half-extent (mirror/flank math), {} when missing.
func sculpt_region_stats(region: String) -> Dictionary:
	var r: Dictionary = _sculpt_regions().get(region, {})
	if r.is_empty():
		return {}
	return {"cx": float(r["cx"]), "hx": float(r["hx"])}


## Region centroid (follow weights, test planes), ZERO when missing.
func sculpt_region_center(region: String) -> Vector3:
	var r: Dictionary = _sculpt_regions().get(region, {})
	if r.is_empty():
		return Vector3.ZERO
	return r["c"] as Vector3


## Region bbox (follow column math, test zoning), {} when missing.
func sculpt_region_bounds(region: String) -> Dictionary:
	var r: Dictionary = _sculpt_regions().get(region, {})
	if r.is_empty():
		return {}
	return {"mn": r["mn"], "mx": r["mx"]}


## Mask point hit rate vs the live pristine Skin: [matched, total] per region.
## Guards asset drift (reimport moving verts kills matches — loud, not silent).
func sculpt_mask_coverage() -> Dictionary:
	var out := {}
	if _skin_pristine == null:
		return out
	var live := {}
	var sk := master_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1:
		return out
	var inv: Transform3D = _bone_rest_world(sk, bi).affine_inverse()
	for s in _skin_pristine.get_surface_count():
		var pa: Array = _skin_pristine.surface_get_arrays(s)
		for v in (pa[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			live[sculpt_key(inv * v)] = true
	for region in _sculpt_regions():
		var r: Dictionary = _sculpt_regions()[region]
		var m := 0
		for key in (r["pts"] as Dictionary):
			if live.has(key):
				m += 1
		out[region] = [m, int(r["n"])]
	return out


## Applies stored sculpt values to the FUSED Skin MI (model space via the live
## Head frame, so physics scales compose). Skin side only, eyeball surfaces
## skipped by src name. Membership is mask-binary (baked Head-frame points),
## then DIFFUSED outward over RINGS neighbor rings (x0.6 each) on EVERY
## computed surface (brows included: a mask edge on an undiffused surface is
## a hard cliff; diffusion only spreads in-surface displacement, it never
## drags brows along the nose — with no brow verts in-mask, brows stay put).
## untouched (authored stylized — 07/10 revert). All-zero = early-out,
## authored mesh byte-identical.
const SCULPT_RINGS := 3
const SCULPT_DECAY := 0.6
var _adj_cache := {} # pristine mesh rid -> Array per surface of neighbor index Arrays
func _sculpt_fused() -> void:
	var regions := _sculpt_regions()
	if regions.is_empty():
		return
	var active := []
	for key in SCULPT_KEYS:
		if not is_zero_approx(float(_sculpt.get(key, 0.0))):
			active.append(key)
	if active.is_empty():
		for mi in _avatar_mis(): # all-zero = authored mesh: restore pristine
			var mmi := mi as MeshInstance3D
			if mmi != null and mmi.name == &"Skin" and _skin_pristine != null and mmi.mesh != _skin_pristine:
				mmi.mesh = _skin_pristine
		_face_follow_restore()
		return
	var sk := master_skeleton()
	if sk == null:
		return
	var bi := sk.find_bone(&"Head")
	if bi == -1:
		return
	var head_world: Transform3D = _bone_rest_world(sk, bi)
	var head_inv: Transform3D = head_world.affine_inverse()
	# Follow accumulators: driving key -> {parts, sum, count} over mask
	# members (halo excluded: exact socket motion). Survives all surfaces.
	# SCULPT_FOLLOW_SIDES keys also carry {sides, cx, sumL/countL, sumR/
	# countR}: one global mean would cancel across symmetric orbits.
	var follow_acc := {}
	for fslot in SCULPT_FOLLOW:
		for fkey in _follow_keys(SCULPT_FOLLOW[fslot]):
			if active.has(fkey) and not follow_acc.has(fkey):
				var facc := {"parts": [], "sum": Vector3.ZERO, "count": 0}
				if SCULPT_FOLLOW_SIDES.has(fkey):
					var fr: Dictionary = regions.get(String((SCULPT_SPEC.get(fkey, {}) as Dictionary).get("region", "")), {})
					facc["sides"] = true
					facc["cx"] = float(fr.get("cx", 0.0))
					facc["sumL"] = Vector3.ZERO
					facc["countL"] = 0
					facc["sumR"] = Vector3.ZERO
					facc["countR"] = 0
				follow_acc[fkey] = facc
	for fslot in SCULPT_FOLLOW:
		for fkey in _follow_keys(SCULPT_FOLLOW[fslot]):
			if follow_acc.has(fkey) and not (follow_acc[fkey] as Dictionary)["parts"].has(fslot):
				((follow_acc[fkey] as Dictionary)["parts"] as Array).append(fslot)
	# Glue keys: driving rows of shell entries (hair) — their per-vert skin
	# fields are retained (combined across Skin surfaces, twin-equalized like
	# the bake) so each shell vert can copy its nearest skin vert's offset.
	var glue_keys := {}
	for fslot_g in SCULPT_FOLLOW:
		var e_g = SCULPT_FOLLOW[fslot_g]
		if e_g is Dictionary and bool((e_g as Dictionary).get("glue", false)):
			for gk in _follow_keys(e_g):
				glue_keys[gk] = true
	var glue_fields := {} # key -> combined PackedVector3Array (this bake)
	var glue_owner: MeshInstance3D = null # first Skin MI owns the glue order
	for mi in _avatar_mis():
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.name != &"Skin":
			continue
		var src_mesh: ArrayMesh = _skin_pristine
		if src_mesh == null:
			src_mesh = mmi.mesh as ArrayMesh
		if src_mesh == null:
			continue
		var take_glue := glue_owner == null
		if take_glue:
			glue_owner = mmi
			_glue_ensure(src_mesh, mmi, head_inv)
		var out := ArrayMesh.new()
		for s in src_mesh.get_surface_count():
			var src := String(_avatar_src_for(mmi, s)).to_lower()
			var a := src_mesh.surface_get_arrays(s)
			if src.contains("eye") and not src.contains("brow"):
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
				out.surface_set_material(s, src_mesh.surface_get_material(s))
				continue
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n := verts.size()
			var qs := PackedVector3Array()
			qs.resize(n)
			var off := PackedVector3Array()
			off.resize(n)
			var wmax := PackedFloat32Array()
			wmax.resize(n)
			# Falloff t-field smoothing (coarse-mesh guard, 08/10: a 12mm
			# edge jumps t by 0.3 -> 8mm cliff, and diffusion can't help a
			# masked vert). Laplacian passes equilibrate local gaps while
			# the 40mm profile stands (diffusion length ~3 verts).
			var fsmart := {} # falloff key -> smoothed t per vert
			for fkey in active:
				var fspec: Dictionary = SCULPT_SPEC[fkey]
				if String(fspec.get("mode", "")) != "falloff":
					continue
				var fr: Dictionary = regions.get(String(fspec["region"]), {})
				if fr.is_empty():
					continue
				var fmn: Vector3 = fr["mn"]
				var fmx: Vector3 = fr["mx"]
				var fa: Vector3 = (fspec["along"] as Vector3).normalized()
				var fspan := (fmx - fmn).dot(fa)
				var adj0 := _sculpt_adj(src_mesh, s, verts, a[Mesh.ARRAY_INDEX])
				var tt := PackedFloat32Array()
				tt.resize(n)
				for i in n:
					var qq: Vector3 = head_inv * verts[i]
					var t0 := 0.5
					if fspan > 1e-9:
						t0 = clampf((qq - fmn).dot(fa) / fspan, 0.0, 1.0)
					tt[i] = t0
				for _p in 6:
					var nx := tt.duplicate()
					for i in n:
						var nb := (adj0[i] as Array)
						if nb.is_empty():
							continue
						var m0 := 0.0
						for j in nb:
							m0 += tt[int(j)]
						nx[i] = (tt[i] + m0 / float(nb.size())) * 0.5
					tt = nx
				fsmart[fkey] = tt
			for i in n:
				qs[i] = head_inv * verts[i]
			var total := PackedVector3Array()
			total.resize(n)
			var surf_koffs := {} # glue-driving key -> post-diffusion field
			var ear_mask: PackedFloat32Array = PackedFloat32Array() # EarSize mask (twin-eq exclusion)
			# Per-key fields (08/10 halo-erasure fix): each row computes its
			# own off + mask, diffuses through verts masked for NOBODY ELSE,
			# then adds in. The old shared wmax let any overlapping region
			# (Nose over the bridge halo) flip halo verts to mask and snap
			# their diffused offset back to ~0 — one NoseW step visibly
			# flattened NoseCurve. Rows now superpose without interaction.
			for key in active:
				var spec: Dictionary = SCULPT_SPEC[key]
				var r: Dictionary = regions.get(String(spec["region"]), {})
				if r.is_empty():
					continue
				var kval: float = float(_sculpt.get(key, 0.0))
				var koff := PackedVector3Array()
				koff.resize(n)
				var kwmax := PackedFloat32Array()
				kwmax.resize(n)
				for i in n:
					var q: Vector3 = qs[i]
					if not (r["pts"] as Dictionary).has(sculpt_key(q)):
						continue
					kwmax[i] = 1.0
					var v: float = kval / 100.0
					if bool(spec["mirror"]):
						# Proportional widen/narrow about the region centroid
						# (no bunching, no fold: center fixed, flanks move most).
						var hx := maxf(float(r["hx"]), 1e-9)
						koff[i].x += (q.x - float(r["cx"])) / hx * kval / 100.0
					else:
						var mode := String(spec.get("mode", "shift"))
						if mode == "scale":
							# Centroid scale (TipSize...): the ball grows,
							# rate per cm, optionally masked to `axis`
							# (BrowThick = Y only).
							var c: Vector3 = r["c"]
							var sax: Vector3 = spec.get("axis", Vector3.ONE)
							var dd: Vector3 = (q - c) * (kval * float(spec.get("rate", 0.15)))
							koff[i] += Vector3(dd.x * sax.x, dd.y * sax.y, dd.z * sax.z)
						elif mode == "rot":
							# Pivot rotation about the centroid (+ = tip up for
							# a +X axis on a +Z nose: angle negated below).
							var c2: Vector3 = r["c"]
							var ang := -deg_to_rad(float(spec.get("deg", 8.0)) * kval)
							koff[i] += Basis((spec["axis"] as Vector3).normalized(), ang) * (q - c2) + c2 - q
						elif mode == "root":
							# Per-side ear growth (EarSize): X grows outward from
							# the mask inner edge (the root stays, the rim moves
							# most — the skull never grows with the ear) while
							# Y/Z grow in place about the centroid (free axes,
							# "orate"). Symmetric masks only.
							var ix := maxf(float(r.get("ix", 0.0)), 1e-9)
							var rc: Vector3 = r["c"]
							var side := signf(q.x - float(r["cx"]))
							if side == 0.0:
								side = 1.0
							var rspan := maxf(maxf(absf((r["mn"] as Vector3).x), absf((r["mx"] as Vector3).x)) - ix, 1e-9)
							var rover := maxf(absf(q.x - float(r["cx"])) - ix, 0.0)
							var rrate := float(spec.get("rate", 0.45))
							var orate := float(spec.get("orate", 0.09))
							koff[i].x += side * rover * rover / rspan * kval * rrate
							koff[i].y += (q.y - rc.y) * kval * orate
							koff[i].z += (q.z - rc.z) * kval * orate
						elif mode == "rootrot":
							# Per-side rotation about the mask inner-edge root
							# (EarRotation): each ear swings about its own
							# (±ix, cy, cz) pivot with mirrored angles, so both
							# sides stay symmetric. "axis" + "deg" per cm.
							var rix := maxf(float(r.get("ix", 0.0)), 1e-9)
							var rc3: Vector3 = r["c"]
							var rside := signf(q.x - float(r["cx"]))
							if rside == 0.0:
								rside = 1.0
							var rp := Vector3(rside * rix, rc3.y, rc3.z)
							# Sign fixed live 09/10 (+ = décolle).
							var rang := -rside * deg_to_rad(float(spec.get("deg", 15.0)) * kval)
							koff[i] += Basis((spec["axis"] as Vector3).normalized(), rang) * (q - rp) + rp - q
						elif mode == "sideshift":
							# Per-side uniform X translation (EyeSpacing): each
							# orbit moves out/in as a block, mirrored — the
							# bridge gap holds no mask, so no step diffuses
							# across the center. Symmetric masks only.
							var sside := signf(q.x - float(r["cx"]))
							if sside == 0.0:
								sside = 1.0
							koff[i].x += sside * v
						elif mode == "sidescale":
							# Per-side centroid dilation (EyeSize): each orbit
							# grows about its own center, rate per cm —
							# symmetric by construction.
							var sc: Vector3 = r["cL"] if q.x < float(r["cx"]) else r["cR"]
							koff[i] += (q - sc) * (kval * float(spec.get("rate", 0.15)))
						elif mode == "siderot":
							# Per-side rotation about the side centroid
							# (EyeAngle): mirrored angles keep symmetry
							# (mirror flips Z-rotation sense, hence the sign).
							# + = outer corners drop (tombant).
							var tside := signf(q.x - float(r["cx"]))
							if tside == 0.0:
								tside = 1.0
							var pc: Vector3 = r["cL"] if tside < 0.0 else r["cR"]
							var tang := -tside * deg_to_rad(float(spec.get("deg", 10.0)) * kval)
							koff[i] += Basis((spec["axis"] as Vector3).normalized(), tang) * (q - pc) + pc - q
						elif mode == "tip":							# Linear ramp along `along` (EarlobeLength/EarPoint):
							# 0 at one bbox end, 1 at the other ("end": "min" /
							# "max" selects the peak end), pushing `axis`.
							var tla: Vector3 = (spec["along"] as Vector3).normalized()
							var td0: float = (r["mn"] as Vector3).dot(tla)
							var td1: float = (r["mx"] as Vector3).dot(tla)
							var tw := 0.5
							if absf(td1 - td0) > 1e-9:
								tw = clampf((q.dot(tla) - td0) / (td1 - td0), 0.0, 1.0)
							if String(spec.get("end", "max")) == "min":
								tw = 1.0 - tw
							koff[i] += (spec["axis"] as Vector3).normalized() * v * tw * float(spec.get("rate", 1.0))
						elif mode == "falloff":
							# Axial falloff bend (Curve, Pout...): sin peak
							# mid-region along `along`, ends fixed, pushes `axis`.
							# t comes from the smoothed field (coarse-mesh guard).
							var t := 0.5
							if fsmart.has(key):
								t = (fsmart[key] as PackedFloat32Array)[i]
							koff[i] += (spec["axis"] as Vector3).normalized() * v * sin(PI * t)
						else:
							koff[i] += (spec["axis"] as Vector3).normalized() * v
				_sculpt_diffuse(koff, kwmax, _sculpt_adj(src_mesh, s, verts, a[Mesh.ARRAY_INDEX]), int(spec.get("rings", SCULPT_RINGS)))
				for i in n:
					total[i] += koff[i]
				if follow_acc.has(key):
					var fa: Dictionary = follow_acc[key]
					var fcx := float(fa.get("cx", 0.0))
					var fside := bool(fa.get("sides", false))
					for i in n:
						if kwmax[i] > 0.0:
							if fside and qs[i].x >= fcx:
								fa["sumR"] = (fa["sumR"] as Vector3) + koff[i]
								fa["countR"] = int(fa["countR"]) + 1
							elif fside:
								fa["sumL"] = (fa["sumL"] as Vector3) + koff[i]
								fa["countL"] = int(fa["countL"]) + 1
							else:
								fa["sum"] = (fa["sum"] as Vector3) + koff[i]
								fa["count"] = int(fa["count"]) + 1
				if take_glue and glue_keys.has(key):
					surf_koffs[key] = koff
				if String((SCULPT_SPEC.get(key, {}) as Dictionary).get("region", "")) == "Ears":
					# Ear/skull seam set (twin-eq exclusion below): the max
					# rule would yank skull twins to the full ear offset.
					ear_mask = kwmax
			off = total
			# Twin equalization (seam guard): bit-identical verts share the
			# strongest offset — a section seam can never crack open even
			# when twin neighborhoods differ (weld shares neighbors, this
			# shares the result). EXCEPT across the ear seam (09/10): an ear
			# twin at full offset would drag its static skull twin along —
			# mixed groups keep their natural (halo-smoothed) offsets, so
			# growing the ear never grows the skull.
			var tgroups := {}
			for i in n:
				if not tgroups.has(verts[i]):
					tgroups[verts[i]] = []
				(tgroups[verts[i]] as Array).append(i)
			if ear_mask.is_empty():
				off = _twin_eq(off, tgroups)
			else:
				for pos in tgroups:
					var ml: Array = tgroups[pos]
					if ml.size() < 2:
						continue
					var has_ear := false
					var has_out := false
					for m in ml:
						if ear_mask[int(m)] > 0.0:
							has_ear = true
						else:
							has_out = true
					if has_ear and has_out:
						continue
					var best := Vector3.ZERO
					var bestl := -1.0
					for m in ml:
						var l: float = off[int(m)].length_squared()
						if l > bestl:
							bestl = l
							best = off[int(m)]
					for m in ml:
						off[int(m)] = best
			if take_glue:
				for gk in surf_koffs:
					# Same seam rule as the bake, then CoW-safe append
					# (never append to a packed array read out of a container).
					var gcomb: PackedVector3Array = glue_fields.get(gk, PackedVector3Array())
					gcomb.append_array(_twin_eq(surf_koffs[gk], tgroups))
					glue_fields[gk] = gcomb
			for i in n:
				if off[i] != Vector3.ZERO:
					verts[i] = head_world * (qs[i] + off[i])
			a[Mesh.ARRAY_VERTEX] = verts
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			out.surface_set_material(s, src_mesh.surface_get_material(s))
		mmi.mesh = out
	# Part follow (09/10 dilution fix: SUM of per-key means, never a pooled
	# average). Shell entries ("glue") skip means entirely: each shell vert
	# copies its nearest skin vert's offset from the retained per-key fields.
	_glue_fields = glue_fields
	var fdrive := {}
	for fslot2 in SCULPT_FOLLOW:
		var flist: Array = []
		for fkey2 in _follow_keys(SCULPT_FOLLOW[fslot2]):
			if SCULPT_FOLLOW_ROT.has(fkey2) and active.has(fkey2):
				# Rigid per-side rotation (lashes ride the tilt): analytic
				# angle/pivot, same convention as the siderot skin mode.
				var rspec: Dictionary = SCULPT_SPEC.get(fkey2, {})
				var rreg: Dictionary = regions.get(String(rspec.get("region", "")), {})
				if rreg.is_empty():
					continue
				var rkd := deg_to_rad(float(rspec.get("deg", 10.0)) * float(_sculpt.get(fkey2, 0.0)))
				flist.append({"key": fkey2, "rot": true, "cx": float(rreg["cx"]), "axis": (rspec.get("axis", Vector3(0, 0, 1)) as Vector3).normalized(), "angL": rkd, "angR": -rkd, "pivL": rreg["cL"], "pivR": rreg["cR"]})
			elif SCULPT_FOLLOW_SCALE.has(fkey2) and active.has(fkey2):
				# Rigid per-side dilation (balls track the aperture): same
				# pivot/rate as the sidescale skin mode, both directions.
				# The spec axis masks the growth (BrowThick = Y only, like
				# the skin "scale" mode) so part and skin stay consistent.
				var sspec: Dictionary = SCULPT_SPEC.get(fkey2, {})
				var sreg: Dictionary = regions.get(String(sspec.get("region", "")), {})
				if sreg.is_empty():
					continue
				flist.append({"key": fkey2, "scale": true, "cx": float(sreg["cx"]), "factor": float(_sculpt.get(fkey2, 0.0)) * float(sspec.get("rate", 0.15)), "axis": sspec.get("axis", Vector3.ONE), "pivL": sreg["cL"], "pivR": sreg["cR"]})
			elif follow_acc.has(fkey2):
				var fa2: Dictionary = follow_acc[fkey2]
				if bool(fa2.get("sides", false)):
					if int(fa2["countL"]) > 0 and int(fa2["countR"]) > 0:
						flist.append({"key": fkey2, "sides": true, "cx": float(fa2["cx"]), "meanL": (fa2["sumL"] as Vector3) / float(fa2["countL"]), "meanR": (fa2["sumR"] as Vector3) / float(fa2["countR"])})
				elif int(fa2["count"]) > 0:
					flist.append({"key": fkey2, "mean": (fa2["sum"] as Vector3) / float(fa2["count"])})
		if not flist.is_empty():
			fdrive[fslot2] = flist
	for fslot2 in SCULPT_FOLLOW:
		_face_follow_bake(String(fslot2), fdrive.get(fslot2, []), head_world, head_inv, bi, regions)


## Driving keys of a follow entry (plain Array, or Dict with a "keys" list
## plus a "glue" flag for shell entries like hair).
static func _follow_keys(entry) -> Array:
	if entry is Dictionary:
		return (entry as Dictionary).get("keys", [])
	return entry as Array


## Column weight of a Head-local point around a region bbox (test zoning
## contract for shell follow): 1 inside and anywhere in front of the column
## (z+), decaying to 0 at `halo` behind, beside or above. Bounds are live
## region stats, repaint-proof.
static func follow_halo_w(q: Vector3, mn: Vector3, mx: Vector3, halo: float) -> float:
	var dx := maxf(mn.x - q.x, 0.0) + maxf(q.x - mx.x, 0.0)
	var dy := maxf(mn.y - q.y, 0.0) + maxf(q.y - mx.y, 0.0)
	var dz := maxf(mn.z - q.z, 0.0) # front free
	var d := sqrt(dx * dx + dy * dy + dz * dz)
	return 1.0 - smoothstep(0.0, halo, d)


## Bakes the SUM of per-key mask means into a mounted compact part's verts
## (same Head-frame math as the skin, so probe/idle poses carry it
## identically). Shell entries ("glue") route to _face_glue_bake instead.
## No driving keys = restore pristine. Skips holders with nothing mounted.
func _face_follow_bake(slot: String, flist: Array, head_world: Transform3D, head_inv: Transform3D, head_idx: int, regions: Dictionary) -> void:
	var entry0 = SCULPT_FOLLOW.get(slot, [])
	if entry0 is Dictionary and bool((entry0 as Dictionary).get("glue", false)):
		_face_glue_bake(slot, flist, head_world, head_inv, head_idx)
		return
	var holder := get_node_or_null(slot) as Node3D
	if holder == null:
		return
	var pristine := _face_pristine.get(slot) as ArrayMesh
	for ch in holder.get_children():
		var mi := ch as MeshInstance3D
		if mi == null or mi.mesh == null or pristine == null:
			continue
		if flist.is_empty():
			if mi.mesh != pristine:
				mi.mesh = pristine
			continue
		if not _face_mi_all_head(mi, pristine, head_idx):
			print("[Character] follow skipped %s (non-Head weights)" % slot)
			continue
		var pout := ArrayMesh.new()
		for s in pristine.get_surface_count():
			var a := pristine.surface_get_arrays(s)
			var pverts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			for i in pverts.size():
				var q: Vector3 = head_inv * pverts[i]
				var off := Vector3.ZERO
				for fd in flist:
					var fdd: Dictionary = fd
					var fside_r := q.x >= float(fdd.get("cx", 0.0))
					if bool(fdd.get("rot", false)):
						# Side-split rigid rotation about the socket pivot.
						var rpiv: Vector3 = (fdd["pivR"] as Vector3) if fside_r else (fdd["pivL"] as Vector3)
						var rang: float = float(fdd["angR"]) if fside_r else float(fdd["angL"])
						off += Basis(fdd["axis"] as Vector3, rang) * (q - rpiv) + rpiv - q
					elif bool(fdd.get("scale", false)):
						# Side-split dilation about the socket centroid,
						# masked to the spec axis (EyeSize = all, Thick = Y).
						var spiv: Vector3 = (fdd["pivR"] as Vector3) if fside_r else (fdd["pivL"] as Vector3)
						var sgr: Vector3 = (q - spiv) * float(fdd["factor"])
						var sax: Vector3 = fdd.get("axis", Vector3.ONE)
						off += Vector3(sgr.x * sax.x, sgr.y * sax.y, sgr.z * sax.z)
					elif bool(fdd.get("sides", false)):
						# Side-split drive (EyeSpacing): each ball/lash takes
						# its own orbit's mean — a global mean would cancel.
						off += (fdd["meanR"] as Vector3) if fside_r else (fdd["meanL"] as Vector3)
					else:
						off += fdd["mean"] as Vector3
				pverts[i] = head_world * (q + off)
			a[Mesh.ARRAY_VERTEX] = pverts
			pout.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			pout.surface_set_material(s, pristine.surface_get_material(s))
		mi.mesh = pout


## Shell-follow grid (09/10): Head-local pristine Skin verts in 10mm cells
## (eye surfaces excluded, same order as the retained fields). Rebuilt when
## the skin mesh changes; stale hair maps are dropped with it.
func _glue_ensure(src_mesh: ArrayMesh, mmi: MeshInstance3D, head_inv: Transform3D) -> void:
	var rid := src_mesh.get_rid().get_id()
	if _glue_grid_rid == rid and not _glue_grid.is_empty():
		return
	_glue_grid = {}
	_glue_qs = PackedVector3Array()
	_glue_map = {}
	var idx := 0
	for s in src_mesh.get_surface_count():
		var src := String(_avatar_src_for(mmi, s)).to_lower()
		if src.contains("eye") and not src.contains("brow"):
			continue
		var vv: PackedVector3Array = src_mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for i in vv.size():
			var q: Vector3 = head_inv * vv[i]
			_glue_qs.append(q)
			var cell := Vector3i(floori(q.x / GLUE_CELL), floori(q.y / GLUE_CELL), floori(q.z / GLUE_CELL))
			if not _glue_grid.has(cell):
				_glue_grid[cell] = []
			(_glue_grid[cell] as Array).append(idx)
			idx += 1
	_glue_grid_rid = rid


## Nearest-skin index per shell vert (pristine both sides, so static per hair
## mesh). Expanding-shell search: exact while the best hit beats the next
## shell's reach; capped at 15 cells (head fits in a 300mm cube).
func _glue_build_map(pristine: ArrayMesh, head_inv: Transform3D) -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in pristine.get_surface_count():
		var vv: PackedVector3Array = pristine.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for i in vv.size():
			var q: Vector3 = head_inv * vv[i]
			var qc := Vector3i(floori(q.x / GLUE_CELL), floori(q.y / GLUE_CELL), floori(q.z / GLUE_CELL))
			var bd := 1e18
			var bi2 := -1
			var r2 := 0
			while r2 <= 15:
				for dx in range(-r2, r2 + 1):
					for dy in range(-r2, r2 + 1):
						for dz in range(-r2, r2 + 1):
							if maxi(maxi(absi(dx), absi(dy)), absi(dz)) != r2:
								continue
							var lst: Array = _glue_grid.get(qc + Vector3i(dx, dy, dz), [])
							for cand in lst:
								var dd: float = _glue_qs[int(cand)].distance_squared_to(q)
								if dd < bd:
									bd = dd
									bi2 = int(cand)
				# Unscanned cells sit past r2 * CELL: stop once the best hit
				# beats that reach (head fits in a 300mm cube either way).
				if bi2 != -1 and sqrt(bd) <= float(r2) * GLUE_CELL:
					break
				r2 += 1
			out.append(maxi(bi2, 0))
	return out


## Shell-part follow ("glue", 09/10): each vert copies the sculpt offset of
## its NEAREST skin vert (retained per-key fields of this bake), so the shell
## preserves its rest gap exactly — both directions, every driving key, no
## proxy ramp/clamp/column. Correspondence is static (both meshes pristine),
## cached per hair mesh; the per-bake cost is one indexed gather per vert.
## Missing glue data = leave pristine alone (never guess).
func _face_glue_bake(slot: String, flist: Array, head_world: Transform3D, head_inv: Transform3D, head_idx: int) -> void:
	var holder := get_node_or_null(slot) as Node3D
	if holder == null:
		return
	var pristine := _face_pristine.get(slot) as ArrayMesh
	if pristine == null:
		return
	if flist.is_empty():
		for ch0 in holder.get_children():
			var mi0 := ch0 as MeshInstance3D
			if mi0 != null and mi0.mesh != null and mi0.mesh != pristine:
				mi0.mesh = pristine
		return
	if _glue_fields.is_empty() or _glue_qs.is_empty() or _glue_grid.is_empty():
		return
	var rid := pristine.get_rid().get_id()
	if not _glue_map.has(rid):
		_glue_map[rid] = _glue_build_map(pristine, head_inv)
	var gmap: PackedInt32Array = _glue_map[rid]
	var keys: Array = []
	for fd in flist:
		var fk: StringName = (fd as Dictionary)["key"]
		if (_glue_fields as Dictionary).has(fk):
			keys.append(fk)
	if keys.is_empty():
		return
	for ch in holder.get_children():
		var mi := ch as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if not _face_mi_all_head(mi, pristine, head_idx):
			print("[Character] follow skipped %s (non-Head weights)" % slot)
			continue
		var pout := ArrayMesh.new()
		var gi := 0
		for s in pristine.get_surface_count():
			var a := pristine.surface_get_arrays(s)
			var pverts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			for i in pverts.size():
				var off := Vector3.ZERO
				if gi < gmap.size():
					var sk: int = gmap[gi]
					for k in keys:
						off += ((_glue_fields as Dictionary)[k] as PackedVector3Array)[sk]
				pverts[i] = head_world * (head_inv * pverts[i] + off)
				gi += 1
			a[Mesh.ARRAY_VERTEX] = pverts
			pout.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			pout.surface_set_material(s, pristine.surface_get_material(s))
		mi.mesh = pout


## Restores every mounted part to its pristine mesh (all-zero sculpt path).
func _face_follow_restore() -> void:
	for slot in _face_pristine:
		var holder := get_node_or_null(String(slot)) as Node3D
		if holder == null:
			continue
		var pristine := _face_pristine[slot] as ArrayMesh
		for ch in holder.get_children():
			var mi := ch as MeshInstance3D
			if mi != null and mi.mesh != null and pristine != null and mi.mesh != pristine:
				mi.mesh = pristine


## 100% Head guard for follow baking (the Head-frame conversion is only
## exact for Head-bound verts): every weighted bone must be the Head.
func _face_mi_all_head(mi: MeshInstance3D, pristine: ArrayMesh, head_idx: int) -> bool:
	for s in pristine.get_surface_count():
		var a := pristine.surface_get_arrays(s)
		var bix: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var bw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		for i in bw.size():
			if bw[i] > 0.0 and bix[i] != head_idx:
				return false
	return true


## Neighbor lists per vert (shared triangles; position-welded when the
## surface is not indexed). Built once per pristine mesh (topology never
## changes under sculpt) and cached by mesh rid + surface. Plain Arrays, NOT
## Packed*Array: appending to a packed array read out of a container mutates
## a CoW copy (proven 08/10: dict/array-packed size stays 0, plain Array sticks).
func _sculpt_adj(mesh: ArrayMesh, s: int, verts: PackedVector3Array, idx: PackedInt32Array) -> Array:
	var key := "%d:%d" % [mesh.get_rid().get_id(), s]
	if _adj_cache.has(key):
		return _adj_cache[key]
	var n := verts.size()
	var adj := []
	adj.resize(n)
	for i in n:
		adj[i] = []
	var link := func(a: int, b: int) -> void:
		if a == b or a < 0 or b < 0 or a >= n or b >= n:
			return
		if not (adj[a] as Array).has(b):
			(adj[a] as Array).append(b)
		if not (adj[b] as Array).has(a):
			(adj[b] as Array).append(a)
	if idx != null and idx.size() >= 3:
		for t in idx.size() / 3:
			link.call(idx[t * 3], idx[t * 3 + 1])
			link.call(idx[t * 3 + 1], idx[t * 3 + 2])
			link.call(idx[t * 3 + 2], idx[t * 3])
		# Weld splits back together (08/10 cheek slit: bit-identical twins
		# on either side of a section seam share no triangle, so diffusion
		# gave each its own halo and the seam cracked open). Exact match
		# only — near-twins (lips) stay independent. Full clique per position
		# (chaining is not enough: twins must share ALL neighbors).
		var twins := {}
		for i in n:
			if not twins.has(verts[i]):
				twins[verts[i]] = []
			(twins[verts[i]] as Array).append(i)
		for pos in twins:
			var ml: Array = twins[pos]
			for a in ml.size():
				for b in range(a + 1, ml.size()):
					link.call(int(ml[a]), int(ml[b]))
	else:
		var vid := {}
		var vids := PackedInt32Array()
		vids.resize(n)
		for i in n:
			if not vid.has(verts[i]):
				vid[verts[i]] = vid.size()
			vids[i] = int(vid[verts[i]])
		for t in n / 3:
			link.call(vids[t * 3], vids[t * 3 + 1])
			link.call(vids[t * 3 + 1], vids[t * 3 + 2])
			link.call(vids[t * 3 + 2], vids[t * 3])
		# Weld splits back together: verts sharing a weld id are neighbors.
		var members := {}
		for i in n:
			if not members.has(vids[i]):
				members[vids[i]] = []
			(members[vids[i]] as Array).append(i)
		for i in n:
			for j in (members[vids[i]] as Array):
				link.call(i, j)
	_adj_cache[key] = adj
	return adj


## Diffuses the offset field outward over `rings` topology rings
## (xSCULPT_DECAY each, default SCULPT_RINGS; per-key "rings" override for
## tight rows like EarSize whose halo must not reach the head): mask verts
## keep their exact offset (boundary condition), others take the STRONGEST
## neighbor offset x decay. Max (not mean): a lone core neighbor among k
## still verts would dilute to ~1/k and leave a 9mm spike step; max follows
## the slope (4/2.4/1.4/2.2mm steps at 10mm core — under the 5mm anti-cliff
## bar). Jacobi, deterministic.
func _sculpt_diffuse(off: PackedVector3Array, wmax: PackedFloat32Array, adj: Array, rings: int = SCULPT_RINGS) -> void:
	var n := off.size()
	if adj.size() != n:
		return
	var cur := off.duplicate()
	var nxt := off.duplicate()
	for _r in rings:
		nxt = cur.duplicate()
		for i in n:
			if wmax[i] > 0.0:
				continue
			var best := Vector3.ZERO
			var best_l := 0.0
			for j in (adj[i] as Array):
				var l: float = cur[int(j)].length_squared()
				if l > best_l:
					best_l = l
					best = cur[int(j)]
			nxt[i] = best * SCULPT_DECAY
		cur = nxt
	for i in n:
		off[i] = cur[i]


## Twin equalization (seam guard): bit-identical verts share the strongest
## offset — a section seam can never crack open even when twin neighborhoods
## differ (weld shares neighbors, this shares the result). Returns the
## equalized copy (CoW: no extra copy until the first twin write).
static func _twin_eq(arr: PackedVector3Array, tgroups: Dictionary) -> PackedVector3Array:
	var out := arr
	for pos in tgroups:
		var ml: Array = tgroups[pos]
		if ml.size() < 2:
			continue
		var best := Vector3.ZERO
		var bestl := -1.0
		for m in ml:
			var l: float = out[int(m)].length_squared()
			if l > bestl:
				bestl = l
				best = out[int(m)]
		for m in ml:
			out[int(m)] = best
	return out


## Max displacement step between topology neighbors on the current fused
## Skin (vs pristine, same topology): the anti-crevasse metric. Small =
## the rim follows instead of cliffing at the box edge.
func sculpt_max_cliff() -> float:
	var pris := _skin_pristine
	if pris == null:
		return 0.0
	var m := 0.0
	for mi in _avatar_mis():
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.mesh == null or mmi.name != &"Skin":
			continue
		for s in mini(mmi.mesh.get_surface_count(), pris.get_surface_count()):
			var ca: Array = mmi.mesh.surface_get_arrays(s)
			var pa: Array = pris.surface_get_arrays(s)
			var cv: PackedVector3Array = ca[Mesh.ARRAY_VERTEX]
			var pv: PackedVector3Array = pa[Mesh.ARRAY_VERTEX]
			if cv.size() != pv.size() or cv.is_empty():
				continue
			var adj := _sculpt_adj(pris, s, pv, pa[Mesh.ARRAY_INDEX])
			if adj.size() != cv.size():
				continue
			for i in cv.size():
				var di: Vector3 = cv[i] - pv[i]
				for j in (adj[i] as Array):
					m = maxf(m, (di - (cv[j] - pv[j])).length())
	return m


## Absolute bone-pose scale on the fused master (single skeleton). Bones
## missing from the rig are skipped with one line (chartest pins the v1 set).
func _apply_physics() -> void:
	var sk := master_skeleton()
	if sk == null:
		return
	for key in PHYS_KEYS:
		var spec: Dictionary = PHYS_BONES[key]
		var v := float(_phys.get(key, 1.0))
		var axes: Vector3 = spec["axes"]
		var sc := Vector3(1.0 + (v - 1.0) * axes.x, 1.0 + (v - 1.0) * axes.y, 1.0 + (v - 1.0) * axes.z)
		for bn in spec["bones"]:
			var bi := sk.find_bone(StringName(bn))
			if bi == -1:
				print("[Phys] bone missing: %s" % String(bn))
				continue
			sk.set_bone_pose_scale(bi, sc)
	# Head stays out of Waist/Hips: bone scale inherits down the chain, so
	# the neck counter-scales the ancestor XZ product (arms still inherit —
	# known approximation until arm-local rows exist).
	var torso_xz := float(_phys.get(&"Waist", 1.0)) * float(_phys.get(&"Hips", 1.0))
	var neck := sk.find_bone(&"Neck")
	if neck != -1:
		var inv := 1.0 / maxf(torso_xz, 0.01)
		sk.set_bone_pose_scale(neck, Vector3(inv, 1.0, inv))
	# Face shape multiplies the Physics Head size (uniform h): final Head =
	# (h*w, h*l, h*w). Defaults neutral — Head-only asserts unaffected.
	var head := sk.find_bone(&"Head")
	if head != -1:
		var h := float(_phys.get(&"Head", 1.0))
		sk.set_bone_pose_scale(head, Vector3(h * float(_face.get(&"Width", 1.0)), h * float(_face.get(&"Length", 1.0)), h * float(_face.get(&"Width", 1.0))))
	# Height readout (host status line): rest crown from the fused
	# bind-pose AABBs times the Root scale.
	_crown_rest = 0.0
	for mi in _avatar_mis():
		var mmi := mi as MeshInstance3D
		if mmi != null and mmi.mesh != null:
			_crown_rest = maxf(_crown_rest, mmi.mesh.get_aabb().end.y)
	if _hud != null and _hud.has_method("set_persistent"):
		_hud.set_persistent(&"height", "HEIGHT: %.2fm" % (_crown_rest * float(_phys.get(&"Height", 1.0))))


## Hair menu verbs (same value-row contract as outfits). Style persists
## across outfit swaps; gender swap resets to None (lists differ).
func hair_styles() -> Array:
	return [&"None"] + HAIR_FILES.get(GENDERS[_gender], [])


func hair_file(gender: String, style: StringName) -> String:
	if style == &"None":
		return ""
	var path := "%s%s/hairs/Hair_%s.gltf" % [HAIR_PART_DIR, gender.to_lower(), String(style)]
	return path if FileAccess.file_exists(path) else ""


func hair_display() -> String:
	return String(hair_styles()[_hair])


func adjust_hair(dir: int) -> void:
	_hair = posmod(_hair + dir, hair_styles().size())
	_apply_hair()
	_reapply_colors()
	_sculpt_fused() # forehead follow re-bakes onto the fresh mount


func reset_hair() -> void:
	_hair = 0
	_apply_hair()
	_reapply_colors()
	_sculpt_fused()


## Runtime Hair holder (created, never saved). Mounts the style mesh on the
## fused master skeleton with bone indices remapped by name (missing ->
## Head, the only used bone). No FitKit: rigid head-follow, follows Head
## scale + idle/probe for free. Hood overlap documented, not handled v1.
func _hair_holder() -> Node3D:
	var h := get_node_or_null("Hair") as Node3D
	if h == null:
		h = Node3D.new()
		h.name = "Hair"
		add_child(h)
	return h


func _apply_hair() -> void:
	var holder := _hair_holder()
	_clear_holder(holder)
	var styles := hair_styles()
	if _hair >= styles.size():
		_hair = 0
	var path := hair_file(GENDERS[_gender], styles[_hair])
	if path.is_empty():
		_face_pristine.erase("Hair")
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("[Character] cannot load %s" % path)
		return
	var inst := packed.instantiate()
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		push_error("[Character] no hair mesh in %s" % path)
		inst.queue_free()
		return
	var src := found[0] as MeshInstance3D
	var sks := inst.find_children("*", "Skeleton3D", true, false)
	var src_sk := sks[0] as Skeleton3D if not sks.is_empty() else null
	var master := master_skeleton()
	if master == null or src_sk == null or src.mesh == null:
		push_error("[Character] hair mount failed (%s)" % path)
		inst.queue_free()
		return
	var head := master.find_bone(&"Head")
	var mesh := src.mesh
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var bi: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var nb := PackedInt32Array()
		nb.resize(bi.size())
		for i in bi.size():
			var ti := master.find_bone(src_sk.get_bone_name(bi[i]))
			nb[i] = ti if ti != -1 else head
		a[Mesh.ARRAY_BONES] = nb
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		out.surface_set_material(s, mesh.surface_get_material(s))
	inst.queue_free()
	var mi := MeshInstance3D.new()
	mi.name = String(styles[_hair])
	mi.mesh = out
	holder.add_child(mi)
	mi.skeleton = mi.get_path_to(master)
	_reset_dress(holder, true)
	_face_pristine["Hair"] = out
	print("[Character] Hair -> %s" % path.get_file())


## Beard menu verbs (same value-row contract as hair). Default None
## (clean-shaven); gender swap resets (lists differ — female has no entry).
func beard_styles() -> Array:
	return [&"None"] + BEARD_FILES.get(GENDERS[_gender], [])


func beard_file(gender: String, style: StringName) -> String:
	if style == &"None":
		return ""
	var path := "%s%s/beards/Hair_%s.gltf" % [HAIR_PART_DIR, gender.to_lower(), String(style)]
	return path if FileAccess.file_exists(path) else ""


func beard_display() -> String:
	return String(beard_styles()[_beard])


func adjust_beard(dir: int) -> void:
	_beard = posmod(_beard + dir, beard_styles().size())
	_apply_beard()
	_reapply_colors()


func reset_beard() -> void:
	_beard = 0
	_apply_beard()
	_reapply_colors()


## Runtime Beard holder (created, never saved). Same mount as hair: style
## mesh on the fused master skeleton, bone indices remapped by name
## (missing -> Head). No FitKit: rigid head-follow, follows Head scale +
## idle/probe for free.
func _beard_holder() -> Node3D:
	var h := get_node_or_null("Beard") as Node3D
	if h == null:
		h = Node3D.new()
		h.name = "Beard"
		add_child(h)
	return h


func _apply_beard() -> void:
	var holder := _beard_holder()
	_clear_holder(holder)
	var styles := beard_styles()
	if _beard >= styles.size():
		_beard = 0
	var path := beard_file(GENDERS[_gender], styles[_beard])
	if path.is_empty():
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("[Character] cannot load %s" % path)
		return
	var inst := packed.instantiate()
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		push_error("[Character] no beard mesh in %s" % path)
		inst.queue_free()
		return
	var src := found[0] as MeshInstance3D
	var sks := inst.find_children("*", "Skeleton3D", true, false)
	var src_sk := sks[0] as Skeleton3D if not sks.is_empty() else null
	var master := master_skeleton()
	if master == null or src_sk == null or src.mesh == null:
		push_error("[Character] beard mount failed (%s)" % path)
		inst.queue_free()
		return
	var head := master.find_bone(&"Head")
	var mesh := src.mesh
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var bi: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var nb := PackedInt32Array()
		nb.resize(bi.size())
		for i in bi.size():
			var ti := master.find_bone(src_sk.get_bone_name(bi[i]))
			nb[i] = ti if ti != -1 else head
		a[Mesh.ARRAY_BONES] = nb
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		out.surface_set_material(s, mesh.surface_get_material(s))
	inst.queue_free()
	var mi := MeshInstance3D.new()
	mi.name = String(styles[_beard])
	mi.mesh = out
	holder.add_child(mi)
	mi.skeleton = mi.get_path_to(master)
	_reset_dress(holder, true)
	print("[Character] Beard -> %s" % path.get_file())


## Face parts (09/10, user-exported Blender files): mounted rigid head-follow
## like hair (bone remap by name, missing -> Head). Empty path = the gender
## ships no file yet (female until its export pass): no-op, and the fused
## nude carries brows/eyes (male nude skips them at import). Eyelashes have
## no nude counterpart and no menu: auto-mounted when the file exists, albedo
## color defaults like hair.
const FACE_PART_DIR := "res://assets/meshes/characters/parts/"
const EYEBROW_FILES := {"Male": [&"Default"]}
const EYE_FILES := {"Male": [&"Default"]}
const EYELASH_FILES := {"Male": [&"Default"]}


func eyebrow_file(gender: String, style: StringName) -> String:
	if style != &"Default" or not (EYEBROW_FILES.get(gender, []) as Array).has(style):
		return ""
	return "%s%s/eyebrows/%s_Eyebrows.gltf" % [FACE_PART_DIR, gender.to_lower(), gender]


func eye_file(gender: String, style: StringName) -> String:
	if style != &"Default" or not (EYE_FILES.get(gender, []) as Array).has(style):
		return ""
	return "%s%s/eyes/%s_Eyes.gltf" % [FACE_PART_DIR, gender.to_lower(), gender]


func eyelash_file(gender: String, style: StringName) -> String:
	if style != &"Default" or not (EYELASH_FILES.get(gender, []) as Array).has(style):
		return ""
	return "%s%s/eyelashes/%s_Eyelashes.gltf" % [FACE_PART_DIR, gender.to_lower(), gender]


## Runtime face-part holder (created, never saved). Same mount as hair.
func _face_holder(slot: String) -> Node3D:
	var h := get_node_or_null(slot) as Node3D
	if h == null:
		h = Node3D.new()
		h.name = slot
		add_child(h)
	return h


func _mount_face_part(slot: String, path: String, albedo: bool) -> void:
	var holder := _face_holder(slot)
	_clear_holder(holder)
	if path.is_empty():
		_face_pristine.erase(slot)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("[Character] cannot load %s" % path)
		return
	var inst := packed.instantiate()
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		push_error("[Character] no face mesh in %s" % path)
		inst.queue_free()
		return
	var src := found[0] as MeshInstance3D
	var sks := inst.find_children("*", "Skeleton3D", true, false)
	var src_sk := sks[0] as Skeleton3D if not sks.is_empty() else null
	var master := master_skeleton()
	if master == null or src_sk == null or src.mesh == null:
		push_error("[Character] face mount failed (%s)" % path)
		inst.queue_free()
		return
	var head := master.find_bone(&"Head")
	var mesh := src.mesh
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var bi: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var nb := PackedInt32Array()
		nb.resize(bi.size())
		for i in bi.size():
			var ti := master.find_bone(src_sk.get_bone_name(bi[i]))
			nb[i] = ti if ti != -1 else head
		a[Mesh.ARRAY_BONES] = nb
		FitKit._strip_custom(a) # importer customs (COLOR_1...) round-trip
		# rejected by add_surface_from_arrays; the toon shader never reads them
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		out.surface_set_material(s, mesh.surface_get_material(s))
	inst.queue_free()
	var mi := MeshInstance3D.new()
	mi.name = path.get_file().get_basename()
	mi.mesh = out
	holder.add_child(mi)
	mi.skeleton = mi.get_path_to(master)
	_reset_dress(holder, albedo)
	_face_pristine[slot] = out
	print("[Character] %s -> %s" % [slot, path.get_file()])


func _apply_eyebrow() -> void:
	_mount_face_part("Eyebrows", eyebrow_file(GENDERS[_gender], EYEBROW_STYLES[_eyebrow]), true)
	# Gender without a file (female) falls back to the fused nude brows:
	# clamp the index so a future multi-style list cannot stick out of range.
	if _eyebrow >= EYEBROW_STYLES.size():
		_eyebrow = 0


func _apply_eye() -> void:
	_mount_face_part("Eyes", eye_file(GENDERS[_gender], EYE_STYLES[_eye]), false)
	if _eye >= EYE_STYLES.size():
		_eye = 0


func _apply_eyelashes() -> void:
	_mount_face_part("Eyelashes", eyelash_file(GENDERS[_gender], &"Default"), true)


## Eyebrow menu verbs (same value-row contract; single style for now,
## more files later — the cycle/reset plumbing is ready).
const EYEBROW_STYLES: Array[StringName] = [&"Default"]


func eyebrow_display() -> String:
	return String(EYEBROW_STYLES[_eyebrow])


func adjust_eyebrow(dir: int) -> void:
	_eyebrow = posmod(_eyebrow + dir, EYEBROW_STYLES.size())


func reset_eyebrow() -> void:
	_eyebrow = 0


## Eye menu verbs (same value-row contract; single vendor pair for now,
## more files later — the cycle/reset plumbing is ready).
const EYE_STYLES: Array[StringName] = [&"Default"]


func eye_display() -> String:
	return String(EYE_STYLES[_eye])


func adjust_eye(dir: int) -> void:
	_eye = posmod(_eye + dir, EYE_STYLES.size())


func reset_eye() -> void:
	_eye = 0


## Face anchor for host close-ups: Head bone world position.
func head_world() -> Vector3:
	var sk := master_skeleton()
	if sk != null:
		var bi := sk.find_bone(&"Head")
		if bi != -1:
			return sk.global_transform * sk.get_bone_global_pose(bi).origin
	return Vector3(0.0, 1.6, 0.0)


## Fused-avatar helpers (sources are freed after the build — measure Fused,
## whose per-surface source node names live in the skin/cloth src lists).
func _avatar_surf_count() -> int:
	var n := 0
	for mi in _avatar_mis():
		if (mi as MeshInstance3D).mesh != null:
			n += (mi as MeshInstance3D).mesh.get_surface_count()
	return n


func _avatar_src_has(substr: String) -> bool:
	var low := substr.to_lower()
	for n in _avatar_skin_src + _avatar_cloth_src:
		if String(n).to_lower().contains(low):
			return true
	return false


func _avatar_each_mat() -> Array:
	var out := []
	for mi in _avatar_mis():
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.mesh == null:
			continue
		for s in mmi.mesh.get_surface_count():
			var om := mmi.get_surface_override_material(s) as ShaderMaterial
			if om != null:
				out.append({"mat": om, "src": _avatar_src_for(mmi, s)})
				continue
			var base := mmi.mesh.surface_get_material(s) as ShaderMaterial
			if base != null:
				out.append({"mat": base, "src": _avatar_src_for(mmi, s)})
	return out


func _avatar_src_for(mmi: MeshInstance3D, s: int) -> String:
	var lst := _avatar_skin_src if mmi.name == &"Skin" else _avatar_cloth_src
	if s < lst.size():
		return String(lst[s])
	return ""


func _avatar_surf_mat(s: int) -> ShaderMaterial:
	var all := _avatar_each_mat()
	if s < all.size():
		return all[s]["mat"] as ShaderMaterial
	return null


## depth_push on the first fused surface from a given source mesh (-1 when
## missing, which fails the caller). Materials are carried at fusion.
func _avatar_push(src_substr: String) -> float:
	var low := src_substr.to_lower()
	for e in _avatar_each_mat():
		if String(e["src"]).to_lower().contains(low):
			return float((e["mat"] as ShaderMaterial).get_shader_parameter("depth_push"))
	return -1.0


## Fused verts dominated by finger bones (proves hands exist post-fusion,
## whether from kept nude skin or garment gloves — guards over-suppression).
func _avatar_finger_verts() -> int:
	var sk := master_skeleton()
	if sk == null or _avatar_mis().is_empty():
		return -1
	var fingers := []
	for b in sk.get_bone_count():
		var bn := String(sk.get_bone_name(b))
		for f in ["Thumb", "Index", "Middle", "Ring", "Little"]:
			if bn.contains(f):
				fingers.append(b)
	var n := 0
	for mi in _avatar_mis():
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.mesh == null:
			continue
		for s in mmi.mesh.get_surface_count():
			var a := mmi.mesh.surface_get_arrays(s)
			if a[Mesh.ARRAY_BONES] == null or a[Mesh.ARRAY_WEIGHTS] == null:
				continue
			var bi: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var bw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			for i in bw.size() / 4:
				var bb := -1
				var ww := 0.0
				for k in 4:
					if bw[i * 4 + k] > ww:
						ww = bw[i * 4 + k]
						bb = bi[i * 4 + k]
				if bb != -1 and fingers.has(bb):
					n += 1
	return n


## albedo_texture on the first fused surface (null when missing/unwired).
func _avatar_tex() -> Texture2D:
	var mat := _avatar_surf_mat(0)
	if mat == null:
		return null
	return mat.get_shader_parameter("albedo_texture") as Texture2D


## Override depth-push on every fused surface (materials are carried at
## fusion, base or override, both MIs).
func set_push_all(v: float) -> void:
	for e in _avatar_each_mat():
		(e["mat"] as ShaderMaterial).set_shader_parameter("depth_push", v)
