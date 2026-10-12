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
const PHYS_KEYS: Array[StringName] = [&"Height", &"Legs", &"Shoulders", &"Waist", &"Hips", &"Head", &"Neck", &"BreastDroop", &"BreastFirmness"]
const PHYS_STEP := 0.01
## Bounds per row (07/10, eye-tuned): limbs/height stay near the authored
## body (90-110); Waist is tighter (95-105, the nude is already muscular —
## 90 puts hands inside the torso, 110+ reads non-human). BreastDroop 70-140
## (140 = heavy/low, 70 = lifted), BreastFirmness 50-150 (soft..firm). The
## old scale rows (Breast/Width/Depth) were cut 12/10: homothety only made
## weird shapes, Projection sculpts better.
const PHYS_LIMITS := {
	&"Height": [0.9, 1.1], &"Legs": [0.9, 1.1], &"Shoulders": [0.9, 1.1],
	&"Waist": [0.95, 1.05], &"Hips": [0.9, 1.1], &"Head": [0.9, 1.1],
	&"Neck": [0.6, 1.0],
	&"BreastDroop": [0.7, 1.4], &"BreastFirmness": [0.5, 2.5],
}
const PHYS_BONES := {
	&"Height": {"bones": [&"Root"], "axes": Vector3(1, 1, 1)},
	&"Legs": {"bones": [&"LeftUpperLeg", &"RightUpperLeg", &"LeftLowerLeg", &"RightLowerLeg"], "axes": Vector3(1, 0, 1)},
	&"Shoulders": {"bones": [&"LeftShoulder", &"RightShoulder"], "axes": Vector3(1, 0, 0)},
	&"Waist": {"bones": [&"Spine", &"Chest"], "axes": Vector3(1, 0, 1)},
	&"Hips": {"bones": [&"Hips"], "axes": Vector3(1, 0, 1)},
	&"Head": {"bones": [&"Head"], "axes": Vector3(1, 1, 1)},
	&"Neck": {"bones": [&"Neck"], "axes": Vector3(1, 1, 1)},
	## Droop is a rigid Y offset (not a scale) and Firmness drives the wiggle
	## — both list the bones with zero axes so the scale pass is a no-op.
	&"BreastDroop": {"bones": [&"LeftBreast", &"RightBreast"], "axes": Vector3(0, 0, 0)},
	&"BreastFirmness": {"bones": [], "axes": Vector3(0, 0, 0)},
}
## BreastDroop mapping: rigid Y offset (m) at v=1.4/0.7. Higher value =
## heavier (down); below 100% lifts up.
const BREAST_SAG_RANGE := 0.05
## Displayed firmness reads 50 points soft: the effective factor adds 0.5
## (100% behaves like the old 150% = held, 200% like the old 250% = welded).
static func _firm_eff(v: float) -> float:
	return v + 0.5


## Firmness -> wiggle output weight on the EFFECTIVE factor (pure, pinnable):
## full jiggle at/below effective 1.0, near-rigid at 2.5+. Stiffness caps at
## 1.0 (the solver oscillates above), so rigidity comes from the output.
static func _firm_force(firm_v: float) -> float:
	return clampf(1.85 - 0.85 * firm_v, 0.1, 1.0)
## BreastFirmness mapping (factor on the .tres reference: stiffness 0.8,
## max_distance 0.04, damping 0.5 at 100% — damping climbs to 0.95 and the
## excursion falls quadratically, that is what kills the run-cycle bounce).
const BREAST_FIRM_STIFF := 0.8
const BREAST_FIRM_MAXD := 0.04
## Pivot set back/down from the skin apex (m): near-nipple so XYZ growth
## stays centered (round, never projectile); the slight down offset keeps the
## up/forward bias. Pushing BACK out again re-makes obus (12/10 live).
const BREAST_PIVOT_BACK := 0.01
const BREAST_PIVOT_DOWN := 0.02
## Procedural breast bones (female only, appended END of the vendor order so
## the 65-bone prefix keeps its indices for parts + animtest pairing).
const BREAST_BONES: Array[StringName] = [&"LeftBreast", &"RightBreast"]
const BREAST_PARENT := &"Chest"
const BREAST_FALLOFF_R := 0.11 # weight zone radius around each apex (m, live-tuned)
static var BREAST_WIGGLE := preload("res://data/characters/wiggle_breast.tres")

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
var _eyelash := 0 # index into EYELASH_STYLES (single Default for now)
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
		_outfit[slot] = outfit_none(slot)
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
	_breast_finalize()
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
## order as the retained fields); _glue_ns = their Head-local normals (same
## order; empty when the skin carries none); _glue_fields = per-key combined
## offsets of the current bake; _glue_grid maps 10mm cells to combined indices
## (rebuilt when the skin mesh changes); _glue_map caches hair-mesh rid ->
## nearest skin index per hair vert (both sides pristine, so static);
## _glue_depth caches rid -> signed rest burial depth per shell vert (meters,
## negative = under the skin, signed on the anchor normal). Beard roots
## (deep) skip the follow so expression never drags them out (11/10).
const GLUE_CELL := 0.01
const GLUE_SKIN_M := 0.002 # shallower than this: full follow (surface shell)
const GLUE_ROOT_M := 0.003 # deeper than this: frozen root (never dragged out)
var _glue_qs := PackedVector3Array()
var _glue_ns := PackedVector3Array()
var _glue_fields := {}
## Retained TOTAL skin offset (twin-equalized, combined take_glue order):
## total-glue slots (brows/lashes) copy it at their nearest skin vert, so the
## rest gap survives every key, driving or not. Reset every bake below.
var _glue_total := PackedVector3Array()
var _glue_grid := {}
var _glue_grid_rid := -1
var _glue_map := {}
var _glue_depth := {}


func _snap_pristine() -> void:
	_skin_pristine = null
	_adj_cache.clear() # keys are mesh rids: rebuild = new meshes
	_koff_cache.clear() # kval-bound fields: new meshes = new fields
	_fsmart_cache.clear() # geometry-only t-fields: same reason
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
	_outfit[slot] = outfit_none(slot)
	full_rebuild()


## glTF file for a (gender, outfit, slot) combo, "" when the combo ships no
## part (Peasant has no Head/Accessories; male ships no Arms files at all —
## bare nude arms; pauldrons live unwired under armor/ until the armor pass).
## Ranger side names stay irregular (Feet_Boots, Head_Hood) until the user
## rename pass; a final existence guard keeps deleted files loud-free.
func part_file(gender: String, outfit: String, slot: StringName) -> String:
	if outfit == "None":
		return "" # explicit nude slot (cycled last, shows "--")
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


## Outfit choices for a slot: base OUTFITS + test extras (variant files) +
## "None" last (explicit nude — indices of the real outfits never shift).
func _slot_outfits(slot: StringName) -> Array:
	return OUTFITS + SLOT_EXTRA.get(slot, []) + ["None"]


## Default outfit index: "None" (avatar starts nude; dress explicitly).
func outfit_none(slot: StringName) -> int:
	return _slot_outfits(slot).size() - 1


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
	_breast_bones_add(slot_skeleton(slot))
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
	_breast_bones_add(slot_skeleton(&"Nude"))
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
const SCULPT_KEYS: Array[StringName] = [&"NoseLength", &"NoseWidth", &"MouthW", &"NoseBridge", &"NostrilFlare", &"NosePosition", &"LipUpper", &"LipLower", &"MouthCorners", &"MouthPosition", &"MouthForward", &"NoseCurve", &"NoseTip", &"NoseTipLength", &"NoseTipSize", &"NoseTipAngle", &"MouthPout", &"EyelidHeavy", &"EyeDepth", &"EyeHeight", &"EyeSpacing", &"EyeSize", &"EyeAngle", &"BrowHeight", &"BrowThick", &"BrowAngle", &"BrowDepth", &"JawWidth", &"JawDefinition", &"JawAngle", &"ChinShift", &"ChinLength", &"ChinWidth", &"ChinProject", &"ChinCleft", &"CheekboneWidth", &"CheekboneHeight", &"CheekFullness", &"FaceFullness", &"ForeheadHeight", &"ForeheadWidth", &"BrowRidgeDepth", &"EarSize", &"EarRotation", &"EarlobeLength", &"EarPoint"]
const SCULPT_STEP := 0.1
const SCULPT_SPEC := {
	&"NoseLength": {"region": "Nose", "menu": "nose", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 1.0},
	&"NoseWidth": {"region": "Nose", "menu": "nose", "axis": Vector3(1, 0, 0), "mirror": true, "max_cm": 0.8},
	&"MouthW": {"region": "Mouth", "menu": "mouth", "axis": Vector3(1, 0, 0), "mirror": true, "max_cm": 0.8},
	&"ChinShift": {"region": "Chin", "menu": "jaw", "axis": Vector3(0, -0.55, 1), "mirror": false, "max_cm": 1.0},
	&"NoseBridge": {"region": "NoseBridge", "menu": "nose", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 1.0},
	&"NoseTip": {"region": "NoseTip", "menu": "nose", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 0.8},
	&"NostrilFlare": {"region": "NostrilFlare", "menu": "nose", "axis": Vector3(1, 0, 0), "mirror": true, "max_cm": 0.8},
	&"NoseTipLength": {"region": "NoseTip", "menu": "nose", "axis": Vector3(0, -1, 0), "mirror": false, "max_cm": 1.0},
	&"NosePosition": {"region": "Nose", "menu": "nose", "axis": Vector3(0, 1, 0), "mirror": false, "max_cm": 0.8},
	&"LipUpper": {"region": "UpperLip", "menu": "mouth", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 0.8},
	&"LipLower": {"region": "LowerLip", "menu": "mouth", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 0.8},
	&"MouthCorners": {"region": "MouthCorners", "menu": "mouth", "axis": Vector3(0, 1, 0), "mirror": false, "max_cm": 0.8},
	&"MouthPosition": {"region": "Mouth", "menu": "mouth", "axis": Vector3(0, 1, 0), "mirror": false, "max_cm": 0.8},
	&"MouthForward": {"region": "Mouth", "menu": "mouth", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 0.8},
	&"NoseTipSize": {"region": "NoseTip", "menu": "nose", "mode": "scale", "rate": 0.15, "mirror": false, "max_cm": 1.0},
	&"NoseTipAngle": {"region": "NoseTip", "menu": "nose", "mode": "rot", "axis": Vector3(1, 0, 0), "deg": 12.0, "mirror": false, "max_cm": 1.0},
	&"NoseCurve": {"region": "NoseBridge", "menu": "nose", "mode": "falloff_n", "axis": Vector3(0, 0, 1), "along": Vector3(0, 1, 0), "mirror": false, "max_cm": 1.0},
	&"MouthPout": {"region": "UpperLip", "menu": "mouth", "mode": "falloff", "axis": Vector3(0, 0, 1), "along": Vector3(1, 0, 0), "mirror": false, "max_cm": 0.8},
	&"EyelidHeavy": {"region": "UpperEyelid", "menu": "eyes", "axis": Vector3(0, -1, 0), "mirror": false, "max_cm": 0.4},
	&"EyeDepth": {"region": "Eyelids", "menu": "eyes", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 0.8},
	&"EyeHeight": {"region": "Eyelids", "menu": "eyes", "axis": Vector3(0, 1, 0), "mirror": false, "max_cm": 0.8},
	&"EyeSpacing": {"region": "Eyelids", "menu": "eyes", "mode": "sideshift", "mirror": false, "max_cm": 0.8},
	&"EyeSize": {"region": "Eyelids", "menu": "eyes", "mode": "sidescale", "rate": 0.15, "mirror": false, "max_cm": 0.8},
	&"EyeAngle": {"region": "Eyelids", "menu": "eyes", "mode": "siderot", "axis": Vector3(0, 0, 1), "deg": 10.0, "mirror": false, "max_cm": 0.8},
	&"BrowHeight": {"region": "Brows", "menu": "eyebrows", "axis": Vector3(0, 1, 0), "mirror": false, "max_cm": 0.8},
	&"BrowThick": {"region": "Brows", "menu": "eyebrows", "mode": "scale", "axis": Vector3(0, 1, 0), "rate": 0.15, "mirror": false, "max_cm": 1.0},
	&"BrowAngle": {"region": "Brows", "menu": "eyebrows", "mode": "siderot", "axis": Vector3(0, 0, 1), "deg": 10.0, "mirror": false, "max_cm": 0.8},
	&"BrowDepth": {"region": "BrowRidge", "menu": "eyebrows", "axis": Vector3(0, 0, 1), "mirror": false, "max_cm": 0.4},
	&"JawWidth": {"region": "Jaw", "menu": "jaw", "axis": Vector3(1, 0, 0), "mirror": true, "max_cm": 0.8},
	&"JawDefinition": {"region": "Jaw", "menu": "jaw", "mode": "siderot", "axis": Vector3(0, 0, 1), "deg": 7.0, "mirror": false, "max_cm": 0.8, "rings": 1},
	&"JawAngle": {"region": "Jaw", "menu": "jaw", "mode": "tip", "along": Vector3(0, 1, 0), "end": "min", "axis": Vector3(0, 1, 0), "rate": 1.0, "mirror": false, "max_cm": 0.8, "rings": 1},
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
	&"EarPoint": {"region": "EarTip", "menu": "ears", "mode": "tip", "along": Vector3(0, 1, 0), "end": "max", "axis": Vector3(0, 1, 0), "rate": 0.6, "mirror": false, "max_cm": 4.8, "min_cm": 1.0, "rings": 1},
}
## Face-part follow (09/10, site-mean 12/10): holder slot -> follow rule. Eyes
## stay analytic and rigid (compact balls must track the aperture, never
## deform with the socket): side-split translation by the socket's LOCAL
## motion (mean TOTAL offset over lid skin near the ball fronts — every key
## incl. spillover) + rigid rotation (EyeAngle) + dilation (EyeSize) on top.
## Brows + lashes are thin shells: each vert copies the TOTAL skin offset of
## its nearest skin vert ("total" glue, 12/10 — mask means lagged whenever
## non-driving keys moved the site via diffusion spillover, burying the parts
## ~2mm under multi-key randoms on both genders). Hair is a shell, not a lump
## (09/10 live: every proxy failed — z-ramp starved the temples at ~40%,
## full-width breathed the whole cap and dived inside the skin when
## narrowing, bbox-column starved verts just outside the paint): each hair
## vert copies the sculpt offset of its NEAREST skin vert ("glue"), so the cap
## preserves its rest gap exactly, both directions, for every driving key.
const SCULPT_FOLLOW := {
	&"Eyes": [&"EyeDepth", &"EyeHeight", &"EyeSpacing", &"EyeSize"],
	&"Eyelashes": {"keys": [&"EyeDepth", &"EyeHeight", &"EyelidHeavy", &"EyeSpacing", &"EyeSize", &"EyeAngle"], "glue": true, "total": true},
	&"Eyebrows": {"keys": [&"BrowDepth", &"BrowRidgeDepth", &"BrowHeight", &"BrowThick", &"BrowAngle"], "glue": true, "total": true},
	&"Hair": {"keys": [&"ForeheadHeight", &"ForeheadWidth"], "glue": true},
	&"Beard": {"keys": [&"JawWidth", &"JawDefinition", &"JawAngle", &"ChinShift", &"ChinLength", &"ChinWidth", &"ChinProject", &"ChinCleft", &"MouthW", &"LipUpper", &"LipLower", &"MouthCorners", &"MouthPosition", &"MouthForward", &"MouthPout"], "glue": true},
}
## Follow keys whose means split per side (EyeSpacing: one global mean would
## cancel to ~0 across the symmetric orbits). Split at the driving region's
## cx; each part vert takes its own side's mean.
const SCULPT_FOLLOW_SIDES := [&"EyeSpacing"]
## Follow keys applied as rigid per-side ROTATION (EyeAngle: the balls must
## not roll — a translation mean would read ~0). Same angle/pivot convention
## as the siderot skin mode. Eyes only (brows/lashes went total-glue 12/10).
const SCULPT_FOLLOW_ROT := [&"EyeAngle"]
## Follow keys applied as per-side DILATION about the socket centroid
## (EyeSize: balls track the aperture with the skin rate, so a shrinking
## socket never clips the globe — and growing sockets grow the balls).
## Eyes only (brows went total-glue 12/10).
const SCULPT_FOLLOW_SCALE := [&"EyeSize"]
## Shell-follow zoning (m, test contract only): the hairline column moves,
## everything past HAIR_HALO stays frozen.
const HAIR_HALO := 0.025
var _sculpt := {} # StringName sculpt key -> float cm (0.0 default)
var _sculpt_cache := {} # gender -> regions dict from SCULPT_PATH (lazy)


func sculpt_display(key: StringName) -> String:
	return "%+dmm" % int(round(float(_sculpt.get(key, 0.0)) * 10.0))


## Sculpt range (lo, hi) in cm for a key. Symmetric ±max_cm unless the spec
## carries min_cm (EarPoint 12/10: -10mm floor, user-tuned — deep negatives
## fold the tip into the skull).
static func sculpt_limits(key: StringName) -> Vector2:
	var spec: Dictionary = SCULPT_SPEC.get(key, {})
	var hi := float(spec.get("max_cm", 1.0))
	return Vector2(-float(spec.get("min_cm", hi)), hi)


func adjust_sculpt(key: StringName, dir: int) -> void:
	var lim := sculpt_limits(key)
	_sculpt[key] = clampf(float(_sculpt.get(key, 0.0)) + float(dir) * SCULPT_STEP, lim.x, lim.y)
	_sculpt_fused() # live on the fused mesh, no rebuild (reapplied in _post_build)


func reset_sculpt(key: StringName) -> void:
	_sculpt[key] = 0.0
	_sculpt_fused()


## Absolute sculpt set (TEMP debug random face row): clamped to the
## key's max like adjust_sculpt. live=false poses the value without fusing —
## batch loops then call fuse_sculpt() once (one full-mesh bake instead of N).
## Removed with the debug rows.
func set_sculpt(key: StringName, val_cm: float, live := true) -> void:
	var lim := sculpt_limits(key)
	_sculpt[key] = clampf(val_cm, lim.x, lim.y)
	if live:
		_sculpt_fused()


func fuse_sculpt() -> void:
	_sculpt_fused()


## Sum of live Skin verts (TEMP debug pin: proves the per-key field cache
## bakes bit-identical results to a fresh full recompute).
func sculpt_checksum() -> Vector3:
	var sum := Vector3.ZERO
	for mi in _avatar_mis():
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.mesh == null or mmi.name != &"Skin":
			continue
		for s in mmi.mesh.get_surface_count():
			var vv: PackedVector3Array = mmi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in vv:
				sum += v
	return sum


## Drops the per-key field cache (test-only: forces a fresh full recompute
## on the next fuse).
func sculpt_drop_cache() -> void:
	_koff_cache.clear()
	_fsmart_cache.clear()


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
var _koff_cache := {} # "rid:surface:key" -> {kval, koff, kwmax} (mask geometry-static, field kval-bound)
var _fsmart_cache := {} # "rid:surface:" -> {falloff key: smoothed t} (geometry-only)
## Fills missing smoothed falloff t-fields (geometry-only: cached per mesh
## surface, recomputed only for newly activated falloff keys).
func _sculpt_fsmart_fill(fsmart: Dictionary, active: Array, regions: Dictionary, n: int, verts: PackedVector3Array, head_inv: Transform3D, adj: Array) -> void:
	for fkey in active:
		if fsmart.has(fkey):
			continue
		var fspec: Dictionary = SCULPT_SPEC[fkey]
		if not String(fspec.get("mode", "")).begins_with("falloff"):
			continue
		var fr: Dictionary = regions.get(String(fspec["region"]), {})
		if fr.is_empty():
			continue
		var fmn: Vector3 = fr["mn"]
		var fmx: Vector3 = fr["mx"]
		var fa: Vector3 = (fspec["along"] as Vector3).normalized()
		var fspan := (fmx - fmn).dot(fa)
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
				var nb := (adj[i] as Array)
				if nb.is_empty():
					continue
				var m0 := 0.0
				for j in nb:
					m0 += tt[int(j)]
				nx[i] = (tt[i] + m0 / float(nb.size())) * 0.5
			tt = nx
		fsmart[fkey] = tt


## Per-key offset field (mask + mode + diffusion). Pure w.r.t. (mesh,
## surface, key, kval): the caller caches the result and recomputes only
## on kval change. Cached arrays are NEVER mutated in place (read-only
## downstream: CoW detach in _twin_eq protects them).
func _sculpt_key_field(key: StringName, kval: float, spec: Dictionary, r: Dictionary, n: int, qs: PackedVector3Array, an: PackedVector3Array, fsmart: Dictionary, adj: Array, head_inv: Transform3D) -> Array:
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
			elif mode == "falloff_n":
				# Normal-following bend (NoseCurve, live 11/10:
				# clearly better than fixed-axis at the tip):
				# same sin profile, but the push rotates with the surface —
				# straight wall goes `axis` like today, the tip
				# kick-up inflates instead of shearing. Facing-
				# weighted (flanks keep the rigid axis, so no
				# lateral step opens at the mask sides). Normals
				# missing = plain-axis fallback (never guess).
				var adir: Vector3 = (spec["axis"] as Vector3).normalized()
				var tn := 0.5
				if fsmart.has(key):
					tn = (fsmart[key] as PackedFloat32Array)[i]
				var push := adir
				var an2: PackedVector3Array = an
				if an2.size() == n:
					var nh: Vector3 = (head_inv.basis * an2[i]).normalized()
					var facing := clampf(nh.dot(adir), 0.0, 1.0)
					push = (adir * (1.0 - facing) + nh * facing).normalized()
				koff[i] += push * v * sin(PI * tn)
			else:
				koff[i] += (spec["axis"] as Vector3).normalized() * v
	_sculpt_diffuse(koff, kwmax, adj, int(spec.get("rings", SCULPT_RINGS)))
	return [koff, kwmax]



func _sculpt_fused() -> void:
	var regions := _sculpt_regions()
	if regions.is_empty():
		_breast_sculpt()
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
		_breast_sculpt()
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
	var total_wanted := false
	for fslot_g in SCULPT_FOLLOW:
		var e_g = SCULPT_FOLLOW[fslot_g]
		if e_g is Dictionary and bool((e_g as Dictionary).get("glue", false)):
			for gk in _follow_keys(e_g):
				glue_keys[gk] = true
		if e_g is Dictionary and bool((e_g as Dictionary).get("total", false)):
			total_wanted = true
	var glue_fields := {} # key -> combined PackedVector3Array (this bake)
	_glue_total = PackedVector3Array() # reset: stale totals never survive a bake
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
			var cprefix := "%d:%d:" % [src_mesh.get_rid().get_id(), s]
			var adj: Array = _sculpt_adj(src_mesh, s, verts, a[Mesh.ARRAY_INDEX])
			var an: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var fsmart: Dictionary = _fsmart_cache.get(cprefix, {})
			_sculpt_fsmart_fill(fsmart, active, regions, n, verts, head_inv, adj)
			_fsmart_cache[cprefix] = fsmart
			var used_fields := {}
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
			# their diffused offset back to ~0 — one NoseWidth step visibly
			# flattened NoseCurve. Rows now superpose without interaction.
			for key in active:
				var spec: Dictionary = SCULPT_SPEC[key]
				var r: Dictionary = regions.get(String(spec["region"]), {})
				if r.is_empty():
					continue
				var kval: float = float(_sculpt.get(key, 0.0))
				var ck := cprefix + String(key)
				var ce: Dictionary = _koff_cache.get(ck, {})
				var koff := PackedVector3Array()
				var kwmax := PackedFloat32Array()
				if (ce.get("koff", PackedVector3Array()) as PackedVector3Array).size() == n and float(ce.get("kval", INF)) == kval:
					koff = ce["koff"] as PackedVector3Array
					kwmax = ce["kwmax"] as PackedFloat32Array
				else:
					var f: Array = _sculpt_key_field(key, kval, spec, r, n, qs, an, fsmart, adj, head_inv)
					if f.is_empty():
						continue
					koff = f[0] as PackedVector3Array
					kwmax = f[1] as PackedFloat32Array
					_koff_cache[ck] = {"kval": kval, "koff": koff, "kwmax": kwmax}
				used_fields[ck] = true
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
			for ck2 in _koff_cache.keys():
				if String(ck2).begins_with(cprefix) and not used_fields.has(ck2):
					_koff_cache.erase(ck2)
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
				if total_wanted:
					_glue_total.append_array(off)
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
		var e2 = SCULPT_FOLLOW[fslot2]
		if e2 is Dictionary and bool((e2 as Dictionary).get("total", false)):
			# Total glue (brows/lashes): ride the full skin offset at the
			# nearest skin vert for EVERY active key, driving or not. Marker
			# only — the bake gathers the retained total field.
			if not active.is_empty():
				flist.append({"total": true})
		else:
			var site_skip := false
			if fslot2 == &"Eyes":
				var em := _eyes_site_mean(head_inv)
				if bool(em[0]):
					flist.append({"sides": true, "cx": em[1], "meanL": em[2], "meanR": em[3]})
					site_skip = true
			for fkey2 in _follow_keys(SCULPT_FOLLOW[fslot2]):
				if SCULPT_FOLLOW_ROT.has(fkey2) and active.has(fkey2):
					# Rigid per-side rotation (EyeAngle: the balls must not
					# roll): analytic angle/pivot, same convention as the
					# siderot skin mode.
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
				elif follow_acc.has(fkey2) and not site_skip:
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
	_breast_sculpt()


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
## identically). "total" entries (brows/lashes) route to _face_glue_total_bake
## instead (full skin offset at the nearest skin vert, every active key).
## Shell entries ("glue") route to _face_glue_bake. No driving keys = restore
## pristine. Skips holders with nothing mounted.
func _face_follow_bake(slot: String, flist: Array, head_world: Transform3D, head_inv: Transform3D, head_idx: int, regions: Dictionary) -> void:
	var entry0 = SCULPT_FOLLOW.get(slot, [])
	if entry0 is Dictionary and bool((entry0 as Dictionary).get("total", false)):
		_face_glue_total_bake(slot, head_world, head_inv, head_idx)
		return
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
	_glue_ns = PackedVector3Array()
	_glue_map = {}
	_glue_depth = {}
	var idx := 0
	for s in src_mesh.get_surface_count():
		var src := String(_avatar_src_for(mmi, s)).to_lower()
		if src.contains("eye") and not src.contains("brow"):
			continue
		var vv: PackedVector3Array = src_mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = src_mesh.surface_get_arrays(s)[Mesh.ARRAY_NORMAL]
		var has_n := nn.size() == vv.size()
		for i in vv.size():
			var q: Vector3 = head_inv * vv[i]
			_glue_qs.append(q)
			if has_n:
				_glue_ns.append((head_inv.basis * nn[i]).normalized())
			var cell := Vector3i(floori(q.x / GLUE_CELL), floori(q.y / GLUE_CELL), floori(q.z / GLUE_CELL))
			if not _glue_grid.has(cell):
				_glue_grid[cell] = []
			(_glue_grid[cell] as Array).append(idx)
			idx += 1
	if _glue_ns.size() != idx:
		_glue_ns = PackedVector3Array() # partial normals = unusable order
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


## Signed rest burial depth per shell vert (meters; negative = under the skin,
## signed on the anchor normal). Same flat order as _glue_build_map. Empty
## when the skin carries no normals (caller falls back to full follow).
func _glue_build_depth(pristine: ArrayMesh, gmap: PackedInt32Array, head_inv: Transform3D) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if _glue_ns.is_empty():
		return out
	for s in pristine.get_surface_count():
		var vv: PackedVector3Array = pristine.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for i in vv.size():
			var gi: int = gmap[mini(out.size(), gmap.size() - 1)]
			var q: Vector3 = head_inv * vv[i]
			out.append((q - _glue_qs[gi]).dot(_glue_ns[gi]))
	return out


## Rest burial depths for a mounted shell slot (empty when unmeasurable).
## Chartest probe for the root-freeze gate below.
func glue_depth(slot: String) -> PackedFloat32Array:
	var pristine := _face_pristine.get(slot) as ArrayMesh
	if pristine == null:
		return PackedFloat32Array()
	return _glue_depth.get(pristine.get_rid().get_id(), PackedFloat32Array())


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
		_glue_depth[rid] = _glue_build_depth(pristine, _glue_map[rid], head_inv)
	var gmap: PackedInt32Array = _glue_map[rid]
	var gdep: PackedFloat32Array = _glue_depth.get(rid, PackedFloat32Array())
	# Beard-only root freeze (11/10, key-scoped 12/10): buried verts must
	# stay buried under MOUTH keys — the expression offset would drag them
	# through the skin where the stretch gradient is steep (mouth corner).
	# Jaw/chin keys ride full: their field is smooth at the chin front, and
	# freezing it opened a 10mm shear cliff inside the shell (live clip at
	# ChinShift+10 + ChinProject, centershear 10mm, no penetration). Hair
	# is a surface cap: its roots riding the skull is correct, so it keeps
	# full follow.
	var gated := slot == &"Beard" and gdep.size() == gmap.size()
	var keys: Array = [] # ride keys (jaw/chin: full follow, gate or not)
	var mkeys: Array = [] # mouth keys (freeze applies when gated)
	for fd in flist:
		var fk: StringName = (fd as Dictionary)["key"]
		if (_glue_fields as Dictionary).has(fk):
			var fks := String(fk)
			if fks.begins_with("Mouth") or fks.begins_with("Lip"):
				mkeys.append(fk)
			else:
				keys.append(fk)
	if keys.is_empty() and mkeys.is_empty():
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
					if gated and not mkeys.is_empty():
						var fz := clampf((gdep[gi] + GLUE_ROOT_M) / (GLUE_ROOT_M - GLUE_SKIN_M), 0.0, 1.0)
						for mk in mkeys:
							off += ((_glue_fields as Dictionary)[mk] as PackedVector3Array)[sk] * fz
					else:
						for mk in mkeys:
							off += ((_glue_fields as Dictionary)[mk] as PackedVector3Array)[sk]
				pverts[i] = head_world * (head_inv * pverts[i] + off)
				gi += 1
			a[Mesh.ARRAY_VERTEX] = pverts
			pout.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			pout.surface_set_material(s, pristine.surface_get_material(s))
		mi.mesh = pout


## Total-glue follow (12/10, brows/lashes): each vert copies the RETAINED
## TOTAL skin offset of its nearest skin vert — the rest gap survives every
## active key, driving or not (means lagged whenever diffusion spillover from
## other keys moved the site). Same static pristine<->skin correspondence as
## _face_glue_bake (map/depth caches shared); no mouth gating (brows/lashes
## ride everything). Empty total = leave pristine alone (never guess).
func _face_glue_total_bake(slot: String, head_world: Transform3D, head_inv: Transform3D, head_idx: int) -> void:
	var holder := get_node_or_null(slot) as Node3D
	if holder == null:
		return
	var pristine := _face_pristine.get(slot) as ArrayMesh
	if pristine == null:
		return
	if _glue_total.is_empty() or _glue_qs.is_empty() or _glue_grid.is_empty():
		for ch0 in holder.get_children():
			var mi0 := ch0 as MeshInstance3D
			if mi0 != null and mi0.mesh != null and mi0.mesh != pristine:
				mi0.mesh = pristine
		return
	var rid := pristine.get_rid().get_id()
	if not _glue_map.has(rid):
		_glue_map[rid] = _glue_build_map(pristine, head_inv)
		_glue_depth[rid] = _glue_build_depth(pristine, _glue_map[rid], head_inv)
	var gmap: PackedInt32Array = _glue_map[rid]
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
					if sk >= 0 and sk < _glue_total.size():
						off = _glue_total[sk]
				pverts[i] = head_world * (head_inv * pverts[i] + off)
				gi += 1
			a[Mesh.ARRAY_VERTEX] = pverts
			pout.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			pout.surface_set_material(s, pristine.surface_get_material(s))
		mi.mesh = pout


## Site translation for the Eyes (12/10): side-split mean of the retained
## TOTAL skin offset over lid skin near the FRONT of the balls (fixed rest
## set) — the globes ride the aperture's local motion for every key, driving
## or not. Whole-mask means lagged (spillover blind spots); whole-socket
## means were polluted by far-field spillover (brow diffusion at the upper
## rim). Front-only avoids diluting with deep-socket anchors behind the
## balls. Rotation (EyeAngle) and dilation (EyeSize) stay analytic on top
## (their site means read ~0, motion about the side centroids).
## Returns [ok, cx, meanL, meanR].
func _eyes_site_mean(head_inv: Transform3D) -> Array:
	var pristine := _face_pristine.get("Eyes") as ArrayMesh
	if pristine == null or _glue_qs.is_empty() or _glue_grid.is_empty() or _glue_total.is_empty():
		return [false]
	var rid := pristine.get_rid().get_id()
	if not _glue_map.has(rid):
		_glue_map[rid] = _glue_build_map(pristine, head_inv)
	var emap: PackedInt32Array = _glue_map[rid]
	var cx := float(sculpt_region_stats("Eyelids").get("cx", 0.0))
	var tL := Vector3.ZERO
	var tR := Vector3.ZERO
	var nL := 0
	var nR := 0
	var gi := 0
	for s in pristine.get_surface_count():
		var a := pristine.surface_get_arrays(s)
		var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var has_n := pn.size() == pv.size()
		for i in pv.size():
			var keep := true
			if has_n:
				var fn: Vector3 = (head_inv.basis * pn[i]).normalized()
				keep = fn.z > 0.3
			if keep and gi < emap.size():
				var sk: int = emap[gi]
				if sk >= 0 and sk < _glue_total.size():
					if _glue_qs[sk].x >= cx:
						tR += _glue_total[sk]
						nR += 1
					else:
						tL += _glue_total[sk]
						nL += 1
			gi += 1
	if nL == 0 or nR == 0:
		return [false]
	return [true, cx, tL / float(nL), tR / float(nR)]


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


## Mean sculpt displacement (parity metric): mean |live - pristine| over Skin
## verts, 0 when the authored mesh is active. Deterministic per gender+key —
## the chartest records it on female, then ratios it on male (§17).
func sculpt_mean_push() -> float:
	var pris := _skin_pristine
	if pris == null:
		return 0.0
	var sum := 0.0
	var n := 0
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
			for i in cv.size():
				sum += (cv[i] - pv[i]).length()
				n += 1
	return sum / float(maxi(n, 1))


## Procedural breast bones (female only). Added END of the vendor order in
## _apply_nude (master) + _apply_slot (parts, keeps the 67/67 animtest index
## pairing); rests + skin weights land in _breast_finalize post-build, once
## the fused apex is known. Rests/weights are absolute (idempotent across
## rebuilds); the weighted-mesh set below skips cache-hit re-application.
var _breast_weighted := {}


## Adds LeftBreast/RightBreast parented to Chest (no-op when present).
func _breast_bones_add(sk: Skeleton3D) -> void:
	if sk == null or GENDERS[_gender] != "Female":
		return
	var parent := sk.find_bone(BREAST_PARENT)
	if parent == -1:
		return
	for bn in BREAST_BONES:
		if sk.find_bone(bn) != -1:
			continue
		sk.set_bone_parent(sk.add_bone(String(bn)), parent)


## Painted breast landmarks (breast.json v2, Female only): Nipple clusters give
## the per-side apexes, the Breast footprint gives the falloff radius — the
## data-driven answer to the Width-outward issue (12/10: the blind 11cm
## sphere moved the chest rim instead of growing the mound). Chest-frame
## meters, converted to skin-mesh-local via the Chest rest world (same
## convention as the sculpt masks: suppression deletes, never moves).
## Returns {} when unpainted (caller falls back to auto apex + radius).
## Test injection: _breast_override = {"apex": [L, R] skin-local, "radius": f,
## "foot": y skin-local (default: min apex y - 3cm)}.
const BREAST_JSON := "res://data/characters/breast.json"
var _breast_cache := {} # gender -> doc dict (lazy)
var _breast_override := {}
var _breast_last_gate := {} # skin-mesh gate of the last finalize (pins)


func _breast_landmarks() -> Dictionary:
	var smi := _avatar_skin_mi()
	var master := master_skeleton()
	if smi == null or smi.mesh == null or master == null:
		return {}
	var chest := master.find_bone(BREAST_PARENT)
	if chest == -1:
		return {}
	var chest_w := _bone_rest_world(master, chest)
	var sinv: Transform3D = (smi as Node3D).global_transform.affine_inverse()
	var m2c: Transform3D = chest_w.affine_inverse() * (smi as Node3D).global_transform
	if not _breast_override.is_empty():
		var oapex: Array = (_breast_override.get("apex", []) as Array).duplicate()
		if oapex.size() < 2:
			return {}
		var ofoot := float(_breast_override.get("foot", minf((oapex[0] as Vector3).y, (oapex[1] as Vector3).y) - 0.03))
		var ocny := [(m2c * (oapex[0] as Vector3)).y, (m2c * (oapex[1] as Vector3)).y]
		return {"apex": oapex, "radius": float(_breast_override.get("radius", BREAST_FALLOFF_R)), "cny": ocny, "cfoot": (m2c * Vector3(0.0, ofoot, 0.0)).y, "cnip": [m2c * (oapex[0] as Vector3), m2c * (oapex[1] as Vector3)], "source": "override"}
	if GENDERS[_gender] != "Female":
		return {}
	if not _breast_cache.has("doc"):
		_breast_cache["doc"] = JsonFile.load_object(BREAST_JSON)
	var doc: Dictionary = _breast_cache["doc"]
	var sec: Dictionary = (doc.get("Female", {}) as Dictionary).get("regions", {})
	var nip := ((sec.get("Nipple", {}) as Dictionary).get("points", []) as Array)
	var foot := ((sec.get("Breast", {}) as Dictionary).get("points", []) as Array)
	if nip.is_empty() and foot.is_empty():
		return {}
	# Painted footprint bottom (chest-frame min y): the gate floor under the
	# nipple. Nipple-only paint falls back to 3cm under the nipples.
	var foot_c := 1e9
	var apex_c := [Vector3.ZERO, Vector3.ZERO]
	var radius := BREAST_FALLOFF_R
	if not nip.is_empty():
		var pts := []
		var cx := 0.0
		for p in nip:
			var pa: Array = p
			var fp := Vector3(float(pa[0]), float(pa[1]), float(pa[2]))
			pts.append(fp)
			cx += fp.x
		cx /= float(pts.size())
		var cl := Vector3.ZERO
		var cr := Vector3.ZERO
		var nl := 0
		var nr := 0
		var spread := 0.0
		for fp in pts:
			if (fp as Vector3).x < cx:
				cl += fp
				nl += 1
			else:
				cr += fp
				nr += 1
		if nl == 0 or nr == 0:
			cl = (cl + cr) / float(maxi(nl + nr, 1))
			cr = cl
		else:
			cl /= float(nl)
			cr /= float(nr)
		for fp in pts:
			spread = maxf(spread, (fp as Vector3).distance_to(cl if (fp as Vector3).x < cx else cr))
		apex_c = [cl, cr]
		if foot.is_empty():
			radius = clampf(4.0 * spread, 0.04, 0.11)
	if not foot.is_empty():
		var fpts := []
		for p in foot:
			var pa2: Array = p
			fpts.append(Vector3(float(pa2[0]), float(pa2[1]), float(pa2[2])))
		for fp in fpts:
			foot_c = minf(foot_c, (fp as Vector3).y)
		if nip.is_empty():
			# No nipples: per-side front-most mean of the footprint itself.
			var lz := []
			var rz := []
			for fp in fpts:
				((lz if (fp as Vector3).x < 0.0 else rz) as Array).append(fp)
			for side in [lz, rz]:
				(side as Array).sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z > b.z)
			var take_side := func(arr: Array) -> Vector3:
				if arr.is_empty():
					return Vector3.ZERO
				var take := mini(maxi(8, arr.size() / 100), arr.size())
				var c := Vector3.ZERO
				for i in take:
					c += arr[i]
				return c / float(take)
			var al: Vector3 = take_side.call(lz)
			var ar: Vector3 = take_side.call(rz)
			if lz.is_empty():
				al = ar
			if rz.is_empty():
				ar = al
			apex_c = [al, ar]
		var r := 0.0
		for fp in fpts:
			var side_apex: Vector3 = apex_c[0] if (fp as Vector3).x < (apex_c[0] as Vector3).x + ((apex_c[1] as Vector3).x - (apex_c[0] as Vector3).x) * 0.5 else apex_c[1]
			r = maxf(r, (fp as Vector3).distance_to(side_apex))
		radius = clampf(r, 0.04, 0.15)
	else:
		foot_c = minf((apex_c[0] as Vector3).y, (apex_c[1] as Vector3).y) - 0.03
	var to_local := func(q: Vector3) -> Vector3:
		return sinv * (chest_w * q)
	return {"apex": [to_local.call(apex_c[0]), to_local.call(apex_c[1])], "radius": radius, "cny": [(apex_c[0] as Vector3).y, (apex_c[1] as Vector3).y], "cfoot": foot_c, "cnip": [apex_c[0], apex_c[1]], "source": "painted"}
func _breast_apex(mesh: ArrayMesh) -> Array:
	var allv := PackedVector3Array()
	for s in mesh.get_surface_count():
		allv.append_array((mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array))
	if allv.is_empty():
		return []
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for v in allv:
		mn = mn.min(v)
		mx = mx.max(v)
	var y0: float = mn.y + (mx.y - mn.y) * 0.5
	var y1: float = mn.y + (mx.y - mn.y) * 0.78
	var sides := [[], []]
	for v in allv:
		if v.y > y0 and v.y < y1:
			(sides[0] if v.x < 0.0 else sides[1] as Array).append(v)
	var out := []
	for side in sides:
		var verts: Array = side
		if verts.is_empty():
			return []
		verts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z > b.z)
		var take := maxi(8, verts.size() / 100)
		var c := Vector3.ZERO
		for i in mini(take, verts.size()):
			c += verts[i]
		out.append(c / float(mini(take, verts.size())))
	return out


## Assigns breast weights on one fused mesh (apex pair in that mesh's LOCAL
## frame): smoothstep falloff steals proportionally from the vendor weights,
## weakest slot takes the breast bone, sums renormalized to 1.0. The vertical
## gate (chest frame: full at/above the nipple, zero at the painted footprint
## bottom) keeps the under-breast skin on the torso bones — the mound grows
## up/forward, never balloons underneath. Direct
## PackedArray surgery + ordered rebuild: MeshDataTool.commit_to_surface
## APPENDS a duplicate instead of updating in place (proven 12/10: 3->4
## surfaces), and the fused meshes carry no morphs (probed: 0 everywhere —
## loud guard below if that ever changes).
func _breast_weight_mesh(mi: MeshInstance3D, local_apex: Array, bi_l: int, bi_r: int, falloff_r: float, gate: Dictionary) -> void:
	var mesh := mi.mesh as ArrayMesh
	if mesh == null or local_apex.size() < 2:
		return
	if mesh.get_blend_shape_count() > 0:
		push_error("[Breast] blend shapes present, weights skipped (rebuild would drop morphs)")
		return
	var r := maxf(falloff_r, 0.01)
	var r2 := r * r
	var m2c: Transform3D = gate.get("m2c", Transform3D.IDENTITY)
	var gfoot := float(gate.get("foot", -1e9))
	var gny: Array = gate.get("ny", [])
	var rebuilt := []
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var mat := mesh.surface_get_material(s)
		var prim := mesh.surface_get_primitive_type(s)
		var sname := mesh.surface_get_name(s)
		var bb: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var ww: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var stride := 0
		if not bb.is_empty() and not ww.is_empty() and not vv.is_empty():
			stride = bb.size() / vv.size()
		if stride < 1 or bb.size() != vv.size() * stride or ww.size() != vv.size() * stride:
			rebuilt.append([a, mat, prim, sname]) # unexpected layout: keep verbatim
			continue
		for i in vv.size():
			var v: Vector3 = vv[i]
			var dl2: float = v.distance_squared_to(local_apex[0])
			var dr2: float = v.distance_squared_to(local_apex[1])
			var d2: float = minf(dl2, dr2)
			if d2 >= r2:
				continue
			var t := 1.0 - sqrt(d2) / r
			var w: float = t * t * (3.0 - 2.0 * t)
			# Vertical gate (per side, chest frame): full weight at/above
			# the nipple, smooth to zero at the footprint bottom.
			if gny.size() == 2:
				var ny := float(gny[0] if dl2 <= dr2 else gny[1])
				var qy := (m2c * v).y
				if qy < ny:
					if qy <= gfoot:
						continue
					var denom := ny - gfoot
					if denom > 0.0001:
						var gt := (qy - gfoot) / denom
						w *= gt * gt * (3.0 - 2.0 * gt)
			var weakest := 0
			for k in range(1, stride):
				if ww[i * stride + k] < ww[i * stride + weakest]:
					weakest = k
			var bidx := bi_l if dl2 <= dr2 else bi_r
			var tot := 0.0
			for k in stride:
				var o := i * stride + k
				if k == weakest:
					ww[o] = w
					bb[o] = bidx
				else:
					ww[o] = ww[o] * (1.0 - w)
				tot += ww[o]
			if tot > 0.0:
				for k in stride:
					ww[i * stride + k] = ww[i * stride + k] / tot
		a[Mesh.ARRAY_BONES] = bb
		a[Mesh.ARRAY_WEIGHTS] = ww
		rebuilt.append([a, mat, prim, sname])
	mesh.clear_surfaces()
	for e in rebuilt:
		var arr: Array = e[0]
		mesh.add_surface_from_arrays(e[2], arr)
		var si := mesh.get_surface_count() - 1
		mesh.surface_set_material(si, e[1])
		mesh.surface_set_name(si, String(e[3]))


## Post-build breast pass (female only): apex + radius from the painted
## landmarks (breast.json) or the legacy auto sphere when unpainted; rests at
## the apexes (scale + wiggle pivot), weights on fused Skin + Cloths, then
## WiggleBone attach (live only — headless stays deterministic for pins).
func _breast_finalize() -> void:
	if GENDERS[_gender] != "Female":
		return
	var master := master_skeleton()
	var smi := _avatar_skin_mi()
	if master == null or smi == null or smi.mesh == null:
		return
	var bi_l := master.find_bone(BREAST_BONES[0])
	var bi_r := master.find_bone(BREAST_BONES[1])
	if bi_l == -1 or bi_r == -1:
		return
	var chest := master.find_bone(BREAST_PARENT)
	if chest == -1:
		return
	var chest_w := _bone_rest_world(master, chest)
	var m2c_skin: Transform3D = chest_w.affine_inverse() * (smi as Node3D).global_transform
	# Painted landmarks win (nipple apexes + footprint radius + gate floor);
	# unpainted = legacy auto apex + blind radius + 3cm gate.
	var apex := []
	var radius := BREAST_FALLOFF_R
	var cny := []
	var cfoot := 0.0
	var lm := _breast_landmarks()
	if lm.is_empty():
		apex = _breast_apex(smi.mesh)
		if (apex as Array).size() == 2:
			cny = [(m2c_skin * ((apex as Array)[0] as Vector3)).y, (m2c_skin * ((apex as Array)[1] as Vector3)).y]
			cfoot = minf(float(cny[0]), float(cny[1])) - 0.03
	else:
		apex = lm["apex"]
		radius = float(lm["radius"])
		cny = lm["cny"]
		cfoot = float(lm["cfoot"])
	if (apex as Array).size() < 2 or (cny as Array).size() < 2:
		return
	var aw := [(smi as Node3D).global_transform * ((apex as Array)[0] as Vector3), (smi as Node3D).global_transform * ((apex as Array)[1] as Vector3)]
	# Pivot set back/down from the skin apex (chest-wall side): uniform
	# growth pushes forward/outward instead of climbing. Weights untouched.
	var ap := [(aw[0] as Vector3) + Vector3(0.0, -BREAST_PIVOT_DOWN, -BREAST_PIVOT_BACK), (aw[1] as Vector3) + Vector3(0.0, -BREAST_PIVOT_DOWN, -BREAST_PIVOT_BACK)]
	master.set_bone_rest(bi_l, Transform3D(Basis(), chest_w.affine_inverse() * (ap[0] as Vector3)))
	master.set_bone_rest(bi_r, Transform3D(Basis(), chest_w.affine_inverse() * (ap[1] as Vector3)))
	var gate_skin := {"m2c": m2c_skin, "foot": cfoot, "ny": cny}
	_breast_last_gate = gate_skin
	var cmi := _avatar_cloth_mi()
	var key := "%d:%d" % [(smi.mesh as ArrayMesh).get_rid().get_id(), (cmi.mesh as ArrayMesh).get_rid().get_id() if cmi != null and cmi.mesh != null else 0]
	if not _breast_weighted.has(key):
		_breast_weight_mesh(smi, apex, bi_l, bi_r, radius, gate_skin)
		if cmi != null and cmi.mesh != null:
			var cinv: Transform3D = (cmi as Node3D).global_transform.affine_inverse()
			var m2c_cloth: Transform3D = chest_w.affine_inverse() * (cmi as Node3D).global_transform
			_breast_weight_mesh(cmi, [cinv * (aw[0] as Vector3), cinv * (aw[1] as Vector3)], bi_l, bi_r, radius, {"m2c": m2c_cloth, "foot": cfoot, "ny": cny})
		_breast_weighted[key] = true
	if DisplayServer.get_name() != "headless":
		for bn in BREAST_BONES:
			var wb := WiggleBone.new()
			wb.bone_name = String(bn)
			wb.properties = BREAST_WIGGLE
			wb.force = _firm_force(_firm_eff(float(_phys.get(&"BreastFirmness", 1.0))))
			master.add_child(wb)


## Breast sculpt verbs (Physics menu, female only — same cm contract as the
## face rows: pushed along the authored normals, displayed in mm).
const BPROJ := &"BreastProjection"
const BPROJ_STEP := 0.1
const BPROJ_MIN_CM := 2.0
const BPROJ_MAX_CM := 3.0
var _bsculpt := {BPROJ: 0.0}
var _bsnap := {} # mi name -> {"rid": int, "verts": Array of PackedVector3Array}
var _bdirty := false


func bproj_display() -> String:
	return "%+dmm" % int(round(float(_bsculpt.get(BPROJ, 0.0)) * 10.0))


func adjust_bproj(dir: int) -> void:
	_bsculpt[BPROJ] = clampf(float(_bsculpt.get(BPROJ, 0.0)) + float(dir) * BPROJ_STEP, -BPROJ_MIN_CM, BPROJ_MAX_CM)
	_breast_sculpt()


func reset_bproj() -> void:
	_bsculpt[BPROJ] = 0.0
	_breast_sculpt()


## Breast curve (female only): ABSOLUTE signed sculpt, needs no Projection.
## + pushes the mound out along the normals, concentrated at the tip
## (perkier nipples); - pulls the UPPER slope inward (the authored upward
## bulge flattens toward the opposite curve, tip included by blend). Below
## the nipple nothing moves (bit-identical, same rule as the gate). Works on
## Skin + Cloths through the painted field. cm, displayed in mm.
const BCURVE := &"BreastCurve"
const BCURVE_STEP := 0.1
const BCURVE_MAX_CM := 4.0
const BCURVE_UP_BAND := 0.055
var _bcurve := 0.0


func bcurve_display() -> String:
	return "%+dmm" % int(round(float(_bcurve) * 10.0))


func adjust_bcurve(dir: int) -> void:
	_bcurve = clampf(float(_bcurve) + float(dir) * BCURVE_STEP, -BCURVE_MAX_CM, BCURVE_MAX_CM)
	_breast_sculpt()


func reset_bcurve() -> void:
	_bcurve = 0.0
	_breast_sculpt()


## Breast angle (female only): rigid mirrored yaw of the breast bones about
## their origin (near nipple, so the mound swings as a block and the nipple
## normal turns). Degrees, + = inward toward the midline, - = outward.
## Same block-motion contract as EyeAngle->lashes.
const BANGLE_STEP := 1.0
const BANGLE_MAX_DEG := 30.0
var _bangle := 0.0


func bangle_display() -> String:
	return "%+d°" % int(round(float(_bangle)))


func adjust_bangle(dir: int) -> void:
	_bangle = clampf(float(_bangle) + float(dir) * BANGLE_STEP, -BANGLE_MAX_DEG, BANGLE_MAX_DEG)
	_apply_physics()


func reset_bangle() -> void:
	_bangle = 0.0
	_apply_physics()


## Continuous breast field (mesh-independent chest-frame parameters): nipple
## centers + radius + gate floor. Painted wins; unpainted falls back to the
## auto apex (same fallbacks as the weights). {} when unusable or male.
func _breast_field() -> Dictionary:
	var lm := _breast_landmarks()
	if not lm.is_empty():
		return {"nip": (lm.get("cnip", []) as Array).duplicate(), "radius": float(lm.get("radius", BREAST_FALLOFF_R)), "cfoot": float(lm.get("cfoot", 0.0))}
	if GENDERS[_gender] != "Female":
		return {}
	var smi := _avatar_skin_mi()
	var master := master_skeleton()
	if smi == null or smi.mesh == null or master == null:
		return {}
	var chest := master.find_bone(BREAST_PARENT)
	if chest == -1:
		return {}
	var m2c: Transform3D = _bone_rest_world(master, chest).affine_inverse() * (smi as Node3D).global_transform
	var apex := _breast_apex(smi.mesh)
	if apex.size() < 2:
		return {}
	var nl: Vector3 = m2c * (apex[0] as Vector3)
	var nr: Vector3 = m2c * (apex[1] as Vector3)
	return {"nip": [nl, nr], "radius": BREAST_FALLOFF_R, "cfoot": minf(nl.y, nr.y) - 0.03}


## Breast sculpt (Projection): displaces Skin AND Cloths along the authored
## normals through the painted field (radial smoothstep about the nearer
## nipple × vertical gate to the footprint floor — the under-breast stays).
## Snapshots make live adjusts idempotent (restore-then-push); rebuilds bring
## fresh meshes so snapshots refresh by RID. Runs at the end of every
## _sculpt_fused path so face + breast compose.
func _breast_sculpt() -> void:
	var skin := _avatar_skin_mi()
	var cloth := _avatar_cloth_mi()
	var mis := []
	for mi in [skin, cloth]:
		if mi != null and (mi as MeshInstance3D).mesh != null:
			mis.append(mi)
			_bsnap_ensure(mi)
	var val := float(_bsculpt.get(BPROJ, 0.0))
	var cuv := float(_bcurve)
	if is_zero_approx(val) and is_zero_approx(cuv):
		if _bdirty:
			for mi in mis:
				_bsnap_restore(mi)
			_bdirty = false
		return
	if GENDERS[_gender] != "Female":
		return
	var field := _breast_field()
	if field.is_empty() or (field.get("nip", []) as Array).size() < 2:
		return
	var master := master_skeleton()
	if master == null:
		return
	var chest := master.find_bone(BREAST_PARENT)
	if chest == -1:
		return
	var chest_w := _bone_rest_world(master, chest)
	var nip: Array = field["nip"]
	var r := maxf(float(field["radius"]), 0.01)
	var r2 := r * r
	var foot := float(field["cfoot"])
	var v := val / 100.0
	var cv := float(_bcurve) / 100.0
	for mi in mis:
		_bsnap_restore(mi) # idempotent base (snapshot predates any push)
		var mesh := (mi as MeshInstance3D).mesh as ArrayMesh
		var m2c: Transform3D = chest_w.affine_inverse() * ((mi as MeshInstance3D) as Node3D).global_transform
		var rebuilt := []
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			var mat := mesh.surface_get_material(s)
			var prim := mesh.surface_get_primitive_type(s)
			var sname := mesh.surface_get_name(s)
			var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			if vv.is_empty() or nn.size() != vv.size():
				rebuilt.append([a, mat, prim, sname])
				continue
			for i in vv.size():
				var q: Vector3 = m2c * vv[i]
				var dl: float = q.distance_squared_to(nip[0])
				var dr: float = q.distance_squared_to(nip[1])
				var d2: float = minf(dl, dr)
				if d2 >= r2:
					continue
				var nc: Vector3 = nip[0] if dl <= dr else nip[1]
				var g := 1.0
				if q.y < nc.y:
					if q.y <= foot:
						continue
					var denom := nc.y - foot
					if denom > 0.0001:
						var gt := (q.y - foot) / denom
						g = gt * gt * (3.0 - 2.0 * gt)
				var t := 1.0 - sqrt(d2) / r
				var base_r := 0.0
				if t > 0.0:
					base_r = t * t * (3.0 - 2.0 * t)
				var push := v * base_r * g
				# Absolute signed curve (no Projection needed). + = tight tip
				# spike (gaussian: the tip perks with no forward growth);
				# - = wide upper ring sinking inward (opposite curve). Below
				# the nipple: exactly zero.
				if not is_zero_approx(cv):
					var dd := sqrt(d2)
					if cv > 0.0:
						push += cv * exp(-d2 / (0.09 * r2)) * g
					elif dd < 1.3 * r:
						var tu := 1.0 - dd / (1.3 * r)
						var ring: float = tu * tu * (3.0 - 2.0 * tu)
						var vu := clampf((q.y - nc.y) / BCURVE_UP_BAND, 0.0, 1.0)
						vu = vu * vu * (3.0 - 2.0 * vu)
						push += cv * ring * vu
				if push != 0.0:
					vv[i] = vv[i] + nn[i].normalized() * push
			a[Mesh.ARRAY_VERTEX] = vv
			rebuilt.append([a, mat, prim, sname])
		mesh.clear_surfaces()
		for e in rebuilt:
			var arr: Array = e[0]
			mesh.add_surface_from_arrays(e[2], arr)
			var si := mesh.get_surface_count() - 1
			mesh.surface_set_material(si, e[1])
			mesh.surface_set_name(si, String(e[3]))
	_bdirty = true


## Snapshot pristine verts per fused MI (refresh on mesh-object change, i.e.
## every rebuild or face-sculpt rewrite — never mid-adjust).
func _bsnap_ensure(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh as ArrayMesh
	if mesh == null:
		return
	var rid := mesh.get_rid().get_id()
	var e: Dictionary = _bsnap.get(String(mi.name), {})
	if int(e.get("rid", -1)) == rid:
		return
	var vl := []
	for s in mesh.get_surface_count():
		vl.append((mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate())
	_bsnap[String(mi.name)] = {"rid": rid, "verts": vl}


## Restores snapshot verts (ordered rebuild: materials/names preserved).
func _bsnap_restore(mi: MeshInstance3D) -> void:
	var e: Dictionary = _bsnap.get(String(mi.name), {})
	if e.is_empty():
		return
	var mesh := mi.mesh as ArrayMesh
	if mesh == null:
		return
	var vl: Array = e["verts"]
	if vl.size() != mesh.get_surface_count():
		return
	var rebuilt := []
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		a[Mesh.ARRAY_VERTEX] = (vl[s] as PackedVector3Array).duplicate()
		rebuilt.append([a, mesh.surface_get_material(s), mesh.surface_get_primitive_type(s), mesh.surface_get_name(s)])
	mesh.clear_surfaces()
	for e2 in rebuilt:
		var arr2: Array = e2[0]
		mesh.add_surface_from_arrays(e2[2], arr2)
		var si2 := mesh.get_surface_count() - 1
		mesh.surface_set_material(si2, e2[1])
		mesh.surface_set_name(si2, String(e2[3]))


## Absolute bone-pose scale on the fused master (single skeleton). Scale rows
## accumulate per bone (product); Droop adds a rigid Y offset; Firmness
## drives the shared wiggle resource live. Missing bones are skipped with
## one line (chartest pins the set).
func _apply_physics() -> void:
	var sk := master_skeleton()
	if sk == null:
		return
	var acc := {} # bone idx -> Vector3 scale product
	for key in PHYS_KEYS:
		var spec: Dictionary = PHYS_BONES[key]
		var v := float(_phys.get(key, 1.0))
		var axes: Vector3 = spec["axes"]
		if axes == Vector3.ZERO:
			continue # Sag/Firm: handled below, no scale
		for bn in spec["bones"]:
			var bi := sk.find_bone(StringName(bn))
			if bi == -1:
				# Breast bones exist on female builds only — silent there.
				if not (BREAST_BONES as Array).has(StringName(bn)):
					print("[Phys] bone missing: %s" % String(bn))
				continue
			var cur: Vector3 = acc.get(bi, Vector3.ONE)
			acc[bi] = Vector3(cur.x * (1.0 + (v - 1.0) * axes.x), cur.y * (1.0 + (v - 1.0) * axes.y), cur.z * (1.0 + (v - 1.0) * axes.z))
	for bi in acc.keys():
		sk.set_bone_pose_scale(bi, acc[bi])
	# Rigid bones never touched by scale rows keep identity (reset semantics
	# for the breast block: Width/Depth resets must clear their axis alone —
	# accumulation from 1.0 defaults handles it, but a bone left over from a
	# previous build (fresh skeleton each rebuild) starts at identity anyway).
	# BreastDroop: rigid vertical offset, same on both sides (symmetric).
	var sag_v := float(_phys.get(&"BreastDroop", 1.0))
	var sag_off := (1.0 - sag_v) * BREAST_SAG_RANGE
	for bn in BREAST_BONES:
		var sbi := sk.find_bone(bn)
		if sbi == -1:
			continue
		sk.set_bone_pose_position(sbi, Vector3(0.0, sag_off, 0.0))
	# BreastAngle: rigid mirrored yaw about each bone origin (near nipple).
	var bang := deg_to_rad(float(_bangle))
	var bli := sk.find_bone(BREAST_BONES[0])
	if bli != -1:
		sk.set_bone_pose_rotation(bli, Quaternion(Vector3.UP, bang))
	var bri := sk.find_bone(BREAST_BONES[1])
	if bri != -1:
		sk.set_bone_pose_rotation(bri, Quaternion(Vector3.UP, -bang))
	# BreastFirmness: stiffness + damping + max_distance on the shared wiggle
	# resource (live nodes reference it, so they follow; headless has no
	# nodes but the resource still records the value for the next live
	# attach). Damping climbs with firmness — that kills the run bounce.
	var firm_v := _firm_eff(float(_phys.get(&"BreastFirmness", 1.0)))
	BREAST_WIGGLE.stiffness = clampf(BREAST_FIRM_STIFF * firm_v, 0.05, 1.0)
	BREAST_WIGGLE.damping = clampf(firm_v - 0.5, 0.1, 0.95)
	BREAST_WIGGLE.max_distance = clampf(BREAST_FIRM_MAXD / (firm_v * firm_v), 0.01, 0.15)
	# Output weight on the live nodes (headless has none — attach path sets
	# it too, so rebuilds and adjusts agree).
	for ch in sk.get_children():
		if ch is WiggleBone:
			(ch as WiggleBone).force = _firm_force(firm_v)
	# Head stays out of Waist/Hips: bone scale inherits down the chain, so
	# the neck counter-scales the ancestor XZ product (arms still inherit —
	# known approximation until arm-local rows exist). The Neck row applies
	# first via the accumulation loop; here only XZ is counter-scaled, Y
	# (neck height) survives.
	var torso_xz := float(_phys.get(&"Waist", 1.0)) * float(_phys.get(&"Hips", 1.0))
	var neck := sk.find_bone(&"Neck")
	if neck != -1:
		var inv := 1.0 / maxf(torso_xz, 0.01)
		var cur: Vector3 = sk.get_bone_pose_scale(neck)
		sk.set_bone_pose_scale(neck, Vector3(cur.x * inv, cur.y, cur.z * inv))
	# Face shape multiplies the Physics Head size (uniform h): final Head =
	# (h*w, h*l, h*w). Defaults neutral — Head-only asserts unaffected.
	# Head-subtree isolation: Head inherits every ancestor scale (Root,
	# Hips, Spine/Chest, Neck), so its LOCAL scale divides the walked
	# ancestor product out — the head content (skull, eyes, hair…) keeps
	# its global size no matter what Neck/Waist/Hips do. No hierarchy
	# assumption: the walk multiplies whatever pose scales exist.
	var head := sk.find_bone(&"Head")
	if head != -1:
		var h := float(_phys.get(&"Head", 1.0))
		var anc := Vector3.ONE
		var p := sk.get_bone_parent(head)
		while p != -1:
			anc *= sk.get_bone_pose_scale(p)
			p = sk.get_bone_parent(p)
		sk.set_bone_pose_scale(head, Vector3(h * float(_face.get(&"Width", 1.0)) / maxf(anc.x, 0.01), h * float(_face.get(&"Length", 1.0)) / maxf(anc.y, 0.01), h * float(_face.get(&"Width", 1.0)) / maxf(anc.z, 0.01)))
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
		_face_pristine.erase("Beard")
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
	_face_pristine["Beard"] = out
	print("[Character] Beard -> %s" % path.get_file())


## Face parts (09/10, user-exported Blender files): mounted rigid head-follow
## like hair (bone remap by name, missing -> Head). Empty path = the gender
## ships no file yet (female until its export pass): no-op, and the fused
## nude carries brows/eyes (male nude skips them at import). Eyelashes have
## no nude counterpart: auto-mounted when the file exists, albedo color
## defaults like hair, Style + Color submenu under the Face hub.
const FACE_PART_DIR := "res://assets/meshes/characters/parts/"
const EYEBROW_FILES := {"Male": [&"Default"], "Female": [&"Default"]}
const EYE_FILES := {"Male": [&"Default"], "Female": [&"Default"]}
const EYELASH_FILES := {"Male": [&"Default"], "Female": [&"Default"]}


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
	_mount_face_part("Eyelashes", eyelash_file(GENDERS[_gender], EYELASH_STYLES[_eyelash]), true)
	if _eyelash >= EYELASH_STYLES.size():
		_eyelash = 0


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


## Eyelash menu verbs (same value-row contract; single Default for now,
## more files later — the cycle/reset plumbing is ready).
const EYELASH_STYLES: Array[StringName] = [&"Default"]


func eyelash_display() -> String:
	return String(EYELASH_STYLES[_eyelash])


func adjust_eyelash(dir: int) -> void:
	_eyelash = posmod(_eyelash + dir, EYELASH_STYLES.size())


func reset_eyelash() -> void:
	_eyelash = 0


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
