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

const PART_DIR := "res://assets/meshes/outfits/universal_outfit_free/Exports/glTF (Godot-Unreal)/Modular Parts/"
const NUDE_DIR := "res://assets/meshes/characters/"
const GENDERS: Array[String] = ["Male", "Female"]
const OUTFITS: Array[String] = ["Peasant", "Ranger"]
## Extra test variants per slot (Blender-edited files): cycled after OUTFITS
## for that slot only. part_file returns "" when the combo ships no file.
const SLOT_EXTRA := {&"Body": ["PeasantB", "PeasantF"], &"Accessories": ["RangerG"], &"Feet": ["PeasantF"], &"Legs": ["PeasantF"], &"Arms": ["PeasantF"]}
const SLOTS: Array[StringName] = [&"Body", &"Arms", &"Legs", &"Feet", &"Head", &"Accessories"]
## Outfit color entries: outfits only (Skin/Hair/Eyebrows have their own
## submenus — no duplicates). Skin color lives in the Skin submenu.
const OUTFIT_COLOR_SLOTS: Array[StringName] = [&"Body", &"Arms", &"Legs", &"Feet", &"Head", &"Accessories"]
## Slots edited in albedo mode (quasi-white vendor textures with nothing to
## hue-shift: Hair + Eyebrows share the T_Hair set).
const ALBEDO_SLOTS: Array[StringName] = [&"Hair", &"Eyebrows"]
## Hair styles (07/10, user-attributed): rigged-to-HeadBone vendor files,
## one mesh each, all verts 100% Head (verified headless). Beard ignored.
const HAIR_DIR := "res://assets/meshes/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/"
const HAIR_FILES := {
	"Male": [&"Buzzed", &"SimpleParted"],
	"Female": [&"Buns", &"Long", &"BuzzedFemale"],
}
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
var _eyebrow := 0 # index into EYEBROW_STYLES (single Default for now)
var _eye := 0 # index into EYE_STYLES (single Default for now)
var _phys := {} # StringName phys key -> float scale (1.0 default)
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
	for h in ["Nude", "Fused", "Hair"]:
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
	_reapply_colors()
	_apply_physics()
	rebuilt.emit()


## Menu verbs (GenericMenu value rows: get = display, adjust(L/R) = cycle,
## reset(A/E) = default). Adjust ignores its return; the row re-renders.
func gender_display() -> String:
	return GENDERS[_gender]


func adjust_gender(dir: int) -> void:
	_gender = posmod(_gender + dir, GENDERS.size())
	_hair = 0
	full_rebuild()
	print("[Character] gender %s" % GENDERS[_gender])


func reset_gender() -> void:
	_gender = 0
	_hair = 0
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
## part (Peasant has no Head/Accessories; Ranger side names are irregular:
## Feet_Boots on male, Head_Hood, Acc_Pauldron vs Acc_Pauldrons).
func part_file(gender: String, outfit: String, slot: StringName) -> String:
	match slot:
		&"Head":
			if outfit != "Ranger":
				return ""
			return "%s%s_%s_Head_Hood.gltf" % [PART_DIR, gender, outfit]
		&"Accessories":
			if outfit == "RangerG" and gender == "Female":
				return PART_DIR + "Female_Ranger_Gauntlets.gltf"
			if outfit != "Ranger":
				return ""
			if gender == "Male":
				return PART_DIR + "Male_Ranger_Acc_Pauldron.gltf"
			return PART_DIR + "Female_Ranger_Acc_Pauldrons.gltf"
		&"Feet":
			if gender == "Male" and outfit == "Ranger":
				return PART_DIR + "Male_Ranger_Feet_Boots.gltf"
			if gender == "Male" and outfit == "PeasantF":
				return PART_DIR + "Male_Peasant_Feet_Fix.gltf"
			if outfit == "PeasantF":
				return ""
			return "%s%s_%s_Feet.gltf" % [PART_DIR, gender, outfit]
		&"Body", &"Arms", &"Legs":
			if outfit == "PeasantB" and slot == &"Body" and gender == "Female":
				return PART_DIR + "Female_Peasant_Body_B.gltf"
			if slot == &"Arms" and outfit == "Peasant" and gender == "Male":
				return PART_DIR + "Male_Peasant_Arms_without_hands.gltf"
			if slot == &"Arms" and outfit == "Ranger" and gender == "Male":
				return PART_DIR + "Male_Ranger_Arms_without_hands.gltf"
			if slot == &"Arms" and outfit == "Ranger" and gender == "Female":
				return PART_DIR + "Female_Ranger_Arms_without_hands.gltf"
			if outfit == "PeasantF" and slot == &"Legs" and gender == "Male":
				return PART_DIR + "Male_Peasant_Legs_Fix.gltf"
			if outfit == "PeasantF" and slot == &"Body" and gender == "Male":
				return PART_DIR + "Male_Peasant_Body_Fix.gltf"
			if outfit == "PeasantF" and slot == &"Arms" and gender == "Male":
				return PART_DIR + "Male_Peasant_Arms_Fix.gltf"
			if outfit == "PeasantB" or outfit == "RangerG" or outfit == "PeasantF":
				return ""
			return "%s%s_%s_%s.gltf" % [PART_DIR, gender, outfit, String(slot)]
	return ""


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


## Colors menu: fused materials whose source belongs to the slot (Skin =
## skin src list, slots = cloth src list). Empty = no part, toast only.
func slot_mats(slot: StringName) -> Array:
	var out := []
	if slot == &"Hair":
		var holder := get_node_or_null("Hair")
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
## slots (Hair/Eyebrows): albedo from HSV, shift params neutral. Everything
## else is hue-shift mode.
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
	return "%sHair_%s.gltf" % [HAIR_DIR, String(style)]


func hair_display() -> String:
	return String(hair_styles()[_hair])


func adjust_hair(dir: int) -> void:
	_hair = posmod(_hair + dir, hair_styles().size())
	_apply_hair()
	_reapply_colors()


func reset_hair() -> void:
	_hair = 0
	_apply_hair()
	_reapply_colors()


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
	print("[Character] Hair -> %s" % path.get_file())


## Eyebrow menu verbs (same value-row contract; single vendor style for now,
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
