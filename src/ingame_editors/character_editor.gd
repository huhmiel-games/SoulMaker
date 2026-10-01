class_name CharacterEditor
extends Node3D

## Character editor v0 (base): gender + per-slot outfit picker with a live
## mannequin preview. Session-only (defaults Male/Peasant every boot;
## GameState persistence comes later when the game reads the config).
## Six slots (Body/Arms/Legs/Feet/Head/Accessories), two outfits
## (Peasant/Ranger — extend OUTFITS plus part_file for more). Parts are
## Modular-Parts glTF conformed in memory by FitKit, the nude is amputated
## to visible skin only (cut rim tucked under the cloth) with a runtime
## cloth-on-cloth order pass, and everything fuses into ONE skeleton + TWO
## meshes (Skin / Cloths, X-ray toggle) under the Avatar holder (memory
## cache per gender/outfit key). The left panel is a CharacterMenu
## (GenericMenu subclass): value rows cycle live on L/R, A/E resets to
## default, explicit Back rows only (menu grammar, no B).
## Run: Godot --path . scenes/ingame_editors/character_editor.tscn

const PART_DIR := "res://assets/meshes/outfits/universal_outfit_free/Exports/glTF (Godot-Unreal)/Modular Parts/"
const NUDE_DIR := "res://assets/meshes/characters/"
const GENDERS: Array[String] = ["Male", "Female"]
const OUTFITS: Array[String] = ["Peasant", "Ranger"]
const SLOTS: Array[StringName] = [&"Body", &"Arms", &"Legs", &"Feet", &"Head", &"Accessories"]
## Face meshes (push must stay OFF: eyes sit millimeters above the face and
## a pushed face would swallow them). Node names, identical in both fullbodies.
const FACE_NODES: Array[StringName] = [&"Eyebrows", &"Eyes"]
## Anim-fit probe pack (take names inside are already "lib__clip", e.g.
## "ual1__Walk"; the "rig/" prefix is the player library name, same as game).
const ANIM_PACK := "res://scenes/anim_lab/player_pack.res"
const ANIM_DEFAULT_TAKE := "rig/ual1__Walk"

## Editor trigger for the anim-fit probe (inspector tick + F5): CLI flags do
## not survive an editor launch, so the probe also starts on this export.
## Local-only: do NOT commit the scene with this ticked.
@export var animtest := false
## Runtime fit switch (merge-avatar phase 1): when ON (default, male +
## female), slots load the RAW vendor part and FitKit conforms it in memory.
## The old fitted/ bake routing is removed — raw + FitKit is the only path.
@export var use_fitkit := true
var _nude_snap := {"ok": false}

var _gender := 0
var _outfit := {} # StringName slot -> int index into OUTFITS
var _avatar_cache := {} # build key -> {skin: ArrayMesh, cloth: ArrayMesh, skin_srcs, cloth_srcs}
var _avatar_skin_src := PackedStringArray()
var _avatar_cloth_src := PackedStringArray()
## X-ray debug (TEMP, N key / L3 pad): 0 fused, 1 skin only, 2 cloth only.
var _xray := 0
const XRAY_NAMES := ["Fused", "Skin", "Cloths"]
var _dresser: ColorEditor = null
var _menu: CharacterMenu = null
var _anim_active := false
var _anim_player: AnimationPlayer = null
var _anim_master: Skeleton3D = null
var _anim_targets: Array[Skeleton3D] = []
var _anim_pairs: Array = [] # per target: Array of [master_idx, target_idx]
var _anim_frame := 0


func _ready() -> void:
	_dresser = get_node_or_null("MenuLayer/Dresser") as ColorEditor
	_menu = get_node_or_null("MenuLayer/Menu") as CharacterMenu
	if _dresser == null or _menu == null:
		push_error("[Character] missing Dresser or Menu node")
		return
	if "--fitprobe" in OS.get_cmdline_user_args() or "--fitprobe" in OS.get_cmdline_args():
		use_fitkit = true
	for slot in SLOTS:
		_outfit[slot] = 0
	_apply_nude()
	_rebuild_avatar()
	print("[Character] ready (gender %s, all slots %s)" % [GENDERS[_gender], OUTFITS[0]])
	_menu.enter_root(self)
	if "--chartest" in OS.get_cmdline_user_args() or "--chartest" in OS.get_cmdline_args():
		_run_headless_test()
	if "--capturetest" in OS.get_cmdline_user_args() or "--capturetest" in OS.get_cmdline_args():
		_run_capture_test()
	if _animtest_wanted():
		_animtest_setup()


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
			if outfit != "Ranger":
				return ""
			if gender == "Male":
				return PART_DIR + "Male_Ranger_Acc_Pauldron.gltf"
			return PART_DIR + "Female_Ranger_Acc_Pauldrons.gltf"
		&"Feet":
			if gender == "Male" and outfit == "Ranger":
				return PART_DIR + "Male_Ranger_Feet_Boots.gltf"
			return "%s%s_%s_Feet.gltf" % [PART_DIR, gender, outfit]
		&"Body", &"Arms", &"Legs":
			return "%s%s_%s_%s.gltf" % [PART_DIR, gender, outfit, String(slot)]
	return ""


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
	var path := part_file(GENDERS[_gender], OUTFITS[int(_outfit[slot])], slot)
	var want_fit := use_fitkit and not path.is_empty()
	if path.is_empty():
		print("[Character] %s: no part (%s %s)" % [String(slot), GENDERS[_gender], OUTFITS[int(_outfit[slot])]])
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("[Character] cannot load %s" % path)
		return
	holder.add_child(packed.instantiate())
	if want_fit:
		if _nude_snap.get("ok", false):
			FitKit.fit_holder(holder, _nude_snap, slot, _gender)
		else:
			push_error("[Character] FitKit without nude snapshot")
	_dresser.reset_target(holder)
	print("[Character] %s -> %s" % [String(slot), path.get_file()])


func _apply_all() -> void:
	for slot in SLOTS:
		_apply_slot(slot)


## Build key: gender + per-slot outfit (only combos with parts matter, the
## full key is cheaper to reason about).
func _avatar_key() -> String:
	var k := [GENDERS[_gender]]
	for slot in SLOTS:
		k.append(str(int(_outfit[slot])))
	return "|".join(k)


func _clear_holder(h: Node) -> void:
	if h == null:
		return
	for c in h.get_children():
		h.remove_child(c)
		c.queue_free()


## The fused skeleton + fused mesh (null/empty before the first rebuild).
func _avatar_skeleton() -> Skeleton3D:
	var avatar := get_node_or_null("Avatar")
	if avatar == null:
		return null
	var found := avatar.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D


func _avatar_mi() -> MeshInstance3D:
	return _avatar_skin_mi() if _avatar_skin_mi() != null else _avatar_cloth_mi()


func _avatar_mis() -> Array:
	var avatar := get_node_or_null("Avatar")
	var out := []
	if avatar == null:
		return out
	for c in avatar.get_children():
		if c is MeshInstance3D:
			out.append(c)
	return out


func _avatar_skin_mi() -> MeshInstance3D:
	var avatar := get_node_or_null("Avatar")
	if avatar == null:
		return null
	return avatar.get_node_or_null("Skin") as MeshInstance3D


func _avatar_cloth_mi() -> MeshInstance3D:
	var avatar := get_node_or_null("Avatar")
	if avatar == null:
		return null
	return avatar.get_node_or_null("Cloths") as MeshInstance3D


## Moves the master skeleton under Avatar and hangs the two fused
## MeshInstances on it (Skin + Cloths share the one skeleton so the X-ray
## toggle can show each side). Sources are freed by the caller.
func _mount_avatar(master: Skeleton3D, skin: ArrayMesh, cloth: ArrayMesh, skin_srcs: PackedStringArray, cloth_srcs: PackedStringArray) -> void:
	var avatar := get_node_or_null("Avatar")
	if avatar == null or master == null:
		push_error("[Merge] cannot mount (missing avatar/master)")
		return
	_clear_holder(avatar)
	var mp := master.get_parent()
	if mp != null:
		mp.remove_child(master)
	avatar.add_child(master)
	for entry in [["Skin", skin], ["Cloths", cloth]]:
		if entry[1] == null or (entry[1] as ArrayMesh).get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = String(entry[0])
		mi.mesh = entry[1] as ArrayMesh
		avatar.add_child(mi)
		mi.skeleton = mi.get_path_to(master)
	_avatar_skin_src = skin_srcs
	_avatar_cloth_src = cloth_srcs
	_apply_xray()


## Full rebuild: cache hit = nude skeleton + cached meshes only (garments are
## never reloaded); miss = load + FitKit fit + order pass + nude suppression
## (cut rim tucked under the cloth) + fusion. Sources (Nude/slot holders)
## are freed — the Avatar is the only body left.
func _rebuild_avatar() -> void:
	var t0 := Time.get_ticks_msec()
	var key := _avatar_key()
	var nude_holder := get_node_or_null("Nude")
	if _avatar_cache.has(key):
		var e: Dictionary = _avatar_cache[key]
		var master := _slot_skeleton(&"Nude")
		_mount_avatar(master, e["skin"] as ArrayMesh, e["cloth"] as ArrayMesh, e["skin_srcs"] as PackedStringArray, e["cloth_srcs"] as PackedStringArray)
		_clear_holder(nude_holder)
		for slot in SLOTS:
			_clear_holder(get_node_or_null(String(slot)))
		print("[Merge] cache hit %s (%dms)" % [key, Time.get_ticks_msec() - t0])
		return
	_apply_all()
	var master := _slot_skeleton(&"Nude")
	if master == null:
		push_error("[Merge] no nude skeleton, avatar skipped")
		return
	var holders := {}
	for slot in SLOTS:
		holders[slot] = get_node_or_null(String(slot))
	FitKit.order_pass(holders)
	var gholders: Array = []
	for slot in SLOTS:
		gholders.append(holders[slot])
	FitKit.suppress_covered(nude_holder, gholders, master)
	var parts: Array = []
	for mi in FitKit.meshes_under(nude_holder):
		parts.append({"mi": mi, "skeleton": master, "kind": "skin"})
	for slot in SLOTS:
		var sk := _slot_skeleton(slot)
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
	print("[Merge] built %s (%dms, cached keys=%d)" % [key, Time.get_ticks_msec() - t0, _avatar_cache.size()])


## Nude base body (Superhero fullbody: skin everywhere but underwear, head
## included) under every outfit — the depth-push skin side. Garments cover
## it; bare parts (head, hands, gaps) show through. Reloaded on gender swap.
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
	_dresser.reset_target(holder)
	# The nude never casts shadows: buried cloth would otherwise sit in the
	# torso's shadow and render near-black (dark pack textures + filmic).
	# Ground/body shadows still come from the garments; bare head/hands
	# lose their cast shadow (editor-preview tradeoff, documented).
	for mi in ColorEditor._meshes_under(holder):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Face meshes keep the push OFF (see FACE_NODES): the hood covers them
	# by plain depth test, no bias needed.
	for mi in ColorEditor._meshes_under(holder):
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.mesh == null:
			continue
		if not (StringName(mmi.name) in FACE_NODES):
			continue
		for s in mmi.mesh.get_surface_count():
			var mat := mmi.get_surface_override_material(s) as ShaderMaterial
			if mat != null:
				ToonKit.set_skin_push(mat, 1.0, 0.0)
	print("[Character] Nude -> %s" % nude_file(GENDERS[_gender]).get_file())
	_nude_snap = FitKit.snapshot_nude(holder)


## Menu verbs (GenericMenu value rows: get = display, adjust(L/R) = cycle,
## reset(A/E) = default). Adjust ignores its return; the row re-renders.
func gender_display() -> String:
	return GENDERS[_gender]


func adjust_gender(dir: int) -> void:
	_gender = posmod(_gender + dir, GENDERS.size())
	_apply_nude()
	_rebuild_avatar()
	print("[Character] gender %s" % GENDERS[_gender])
	if _anim_active:
		_animtest_setup()


func reset_gender() -> void:
	_gender = 0
	_apply_nude()
	_rebuild_avatar()
	if _anim_active:
		_animtest_setup()


func slot_display(slot: StringName) -> String:
	if part_file(GENDERS[_gender], OUTFITS[int(_outfit[slot])], slot).is_empty():
		return "--"
	return OUTFITS[int(_outfit[slot])]


func adjust_slot(slot: StringName, dir: int) -> void:
	_outfit[slot] = posmod(int(_outfit[slot]) + dir, OUTFITS.size())
	_apply_nude()
	_rebuild_avatar()
	if _anim_active:
		_animtest_setup()


func reset_slot(slot: StringName) -> void:
	_outfit[slot] = 0
	_apply_nude()
	_rebuild_avatar()
	if _anim_active:
		_animtest_setup()


## Headless self-test (--chartest): table lookups, live swap dressing, gender
## swap keeping per-slot outfits. Run: Godot --headless --path . <scene> -- --chartest
func _run_headless_test() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var fails := 0
	fails += _expect("peasant head absent", part_file("Male", "Peasant", &"Head").is_empty())
	fails += _expect("peasant acc absent", part_file("Female", "Peasant", &"Accessories").is_empty())
	fails += _expect("ranger hood male", part_file("Male", "Ranger", &"Head").ends_with("Male_Ranger_Head_Hood.gltf"))
	fails += _expect("ranger boots male", part_file("Male", "Ranger", &"Feet").ends_with("Male_Ranger_Feet_Boots.gltf"))
	fails += _expect("ranger pauldrons female", part_file("Female", "Ranger", &"Accessories").ends_with("Female_Ranger_Acc_Pauldrons.gltf"))
	# Fused avatar: one skeleton + two meshes (Skin / Cloths, X-ray toggle).
	fails += _expect("avatar skeleton", _avatar_skeleton() != null)
	fails += _expect("avatar two meshes", _avatar_skin_mi() != null and _avatar_cloth_mi() != null)
	fails += _expect("avatar surfaces", _avatar_surf_count() > 1)
	fails += _expect("avatar skin inside", _avatar_src_has("SuperHero"))
	fails += _expect("avatar bones 65", _avatar_skeleton() != null and _avatar_skeleton().get_bone_count() == 65)
	adjust_slot(&"Body", 1)
	fails += _expect("body ranger shown", slot_display(&"Body") == "Ranger")
	fails += _expect("body ranger fused", _avatar_mi() != null and _avatar_surf_count() > 1)
	adjust_gender(1)
	fails += _expect("gender female", gender_display() == "Female")
	fails += _expect("body outfit kept", slot_display(&"Body") == "Ranger")
	fails += _expect("female avatar fused", _avatar_mi() != null and _avatar_src_has("SuperHero"))
	fails += _expect("female hands kept", _avatar_finger_verts() > 100)
	reset_gender()
	reset_slot(&"Body")
	fails += _expect("back to male peasant", gender_display() == "Male" and slot_display(&"Body") == "Peasant")
	fails += _expect("male avatar fused", _avatar_mi() != null and _avatar_surf_count() > 1)
	fails += _expect("male hands kept", _avatar_finger_verts() > 100)
	fails += _expect("skin push on", _avatar_push("SuperHero") > 0.01)
	fails += _expect("eyes push off", _avatar_push("Eyes") < 0.001)
	fails += _expect("fitkit default on", use_fitkit)
	fails += _expect("fitkit cfg male legs", not FitKit.cfg_for(&"Legs", 0).is_empty())
	fails += _expect("fitkit cfg female legs", not FitKit.cfg_for(&"Legs", 1).is_empty())
	fails += _expect("fitkit cfg female arms", not FitKit.cfg_for(&"Arms", 1).is_empty())
	fails += _expect("avatar albedo wired", _avatar_tex() != null)
	fails += _expect("cache reused", _avatar_cache.has(_avatar_key()))
	_cycle_xray()
	fails += _expect("xray skin only", _avatar_skin_mi().visible and not _avatar_cloth_mi().visible)
	_cycle_xray()
	fails += _expect("xray cloth only", _avatar_cloth_mi().visible and not _avatar_skin_mi().visible)
	_cycle_xray()
	fails += _expect("xray back to fused", _avatar_skin_mi().visible and _avatar_cloth_mi().visible)
	adjust_slot(&"Head", 1)
	fails += _expect("hood shown", slot_display(&"Head") == "Ranger")
	fails += _expect("hood fused", _avatar_mi() != null and _avatar_surf_count() > 1)
	reset_slot(&"Head")
	# 4. Real menu Callable path (L/R = adjust.call(dir), A/E = reset.call()):
	# the bound slot must survive the int arg (regression: bind order crash).
	_menu._push()
	var body_entry := {}
	for e in _menu._entries:
		if e is Dictionary and String(e.get("label", "")) == "Body":
			body_entry = e
	fails += _expect("menu body row found", not body_entry.is_empty())
	if not body_entry.is_empty():
		(body_entry["adjust"] as Callable).call(1)
		fails += _expect("menu L/R cycles outfit", slot_display(&"Body") == "Ranger")
		(body_entry["reset"] as Callable).call()
		fails += _expect("menu A/E resets outfit", slot_display(&"Body") == "Peasant")
	_menu._pop()
	print("[CharTest] %d FAIL" % fails)
	get_tree().quit()


## X-ray debug (TEMP, N / L3): 0 fused, 1 skin only, 2 cloth only.
func _cycle_xray() -> void:
	_xray = posmod(_xray + 1, 3)
	_apply_xray()
	print("[XRay] %s" % XRAY_NAMES[_xray])


func _apply_xray() -> void:
	var skin := _avatar_skin_mi()
	var cloth := _avatar_cloth_mi()
	if skin != null:
		skin.visible = _xray != 2
	if cloth != null:
		cloth.visible = _xray != 1
	var hud := get_node_or_null("MenuLayer/HUD")
	if hud != null and hud.has_method("set_persistent"):
		hud.set_persistent(&"xray", "XRAY: %s" % XRAY_NAMES[_xray])


## Fused-avatar helpers (sources are freed after the build — measure the
## Avatar MIs, whose per-surface source node names live in the skin/cloth
## src lists).
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
## missing, which fails the caller). Materials are carried at fusion, so the
## nude dress rules (skin push ON, Eyes OFF) survive on the avatar.
func _avatar_push(src_substr: String) -> float:
	var low := src_substr.to_lower()
	for e in _avatar_each_mat():
		if String(e["src"]).to_lower().contains(low):
			return float((e["mat"] as ShaderMaterial).get_shader_parameter("depth_push"))
	return -1.0


## Fused verts dominated by finger bones (proves hands exist post-fusion,
## whether from kept nude skin or garment gloves — guards over-suppression).
func _avatar_finger_verts() -> int:
	var sk := _avatar_skeleton()
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


func _expect(test_name: String, cond: bool) -> int:
	print("[CharTest] %s %s" % ["PASS" if cond else "FAIL", test_name])
	return 0 if cond else 1


## Render capture for headless pixel analysis (--capturetest <path>
## [--nopush] [--nogarments]): lets the AI measure brightness/coverage
## without image input (screenshots are unreadable to it). Needs a real
## renderer: xvfb-run ... --rendering-driver opengl3 <scene> -- <flags>.
func _run_capture_test() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "/tmp/opencode/capture.png"
	var i := args.find("--capturetest")
	if i >= 0 and i + 1 < args.size() and not str(args[i + 1]).begins_with("--"):
		path = str(args[i + 1])
	if "--nopush" in args:
		_set_push_all(0.0)
	if "--nogarments" in args:
		var cloth := _avatar_cloth_mi()
		if cloth != null:
			(cloth as MeshInstance3D).visible = false
	if "--noshadownude" in args:
		var mi := _avatar_mi()
		if mi != null:
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if "--nonormalmap" in args:
		_dresser.no_normal_map = true
		_apply_nude()
		_rebuild_avatar()
	if "--sunflip" in args:
		var sun := get_node_or_null("Sun") as DirectionalLight3D
		if sun != null:
			sun.rotation.y += PI
	if "--noground" in args:
		var ground := get_node_or_null("Ground")
		if ground != null:
			(ground as Node3D).visible = false
	for f in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[CaptureTest] saved %s (%dx%d err=%s)" % [path, img.get_width(), img.get_height(), str(err)])
	get_tree().quit()


## Override depth-push on every fused surface (materials are carried at
## fusion, base or override, both MIs).
func _set_push_all(v: float) -> void:
	for e in _avatar_each_mat():
		(e["mat"] as ShaderMaterial).set_shader_parameter("depth_push", v)


## Anim-fit probe (--animtest [--animtake=rig/...]): plays a game take on the
## mannequin so the fit can be judged IN MOTION. No retarget: pack and parts
## share the same Standard bones (imports aligned per rig vendor 01/10), so
## one master player on the nude skeleton drives all — part skeletons receive
## copied local poses per frame (manual advance first: zero lag,
## deterministic, pausable).
## Other anims: Remote debugger -> CharacterEditor -> anim_player() -> play().
func anim_player() -> AnimationPlayer:
	return _anim_player


func _animtest_wanted() -> bool:
	if animtest:
		return true
	return "--animtest" in OS.get_cmdline_user_args() or "--animtest" in OS.get_cmdline_args()


func _animtest_take() -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if str(a).begins_with("--animtake="):
			return str(a).trim_prefix("--animtake=")
	return ANIM_DEFAULT_TAKE


func _slot_skeleton(slot: StringName) -> Skeleton3D:
	var holder := get_node_or_null(String(slot))
	if holder == null:
		return null
	var found := holder.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D


func _animtest_teardown() -> void:
	_anim_active = false
	_anim_master = null
	_anim_targets.clear()
	_anim_pairs.clear()
	if _anim_player != null and is_instance_valid(_anim_player):
		_anim_player.queue_free()
	_anim_player = null


func _animtest_setup() -> void:
	_animtest_teardown()
	_anim_frame = 0
	# Fused avatar: the single skeleton IS the master, part skeletons are
	# gone (freed at fusion) so targets stay empty and nothing is copied.
	var master := _avatar_skeleton()
	if master == null:
		master = _slot_skeleton(&"Nude")
	if master == null:
		push_error("[AnimTest] no avatar/nude skeleton")
		return
	var pack := load(ANIM_PACK) as AnimationLibrary
	if pack == null:
		push_error("[AnimTest] cannot load %s" % ANIM_PACK)
		return
	_anim_player = AnimationPlayer.new()
	_anim_player.name = "AnimTestPlayer"
	add_child(_anim_player)
	_anim_player.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
	var libs := AnimationLibrary.new()
	for anim_name in pack.get_animation_list():
		libs.add_animation(anim_name, _animtest_remap(pack.get_animation(anim_name), master))
	_anim_player.add_animation_library("rig", libs)
	var take := _animtest_take()
	if not _anim_player.has_animation(take):
		take = RigKit.pick(_anim_player, "ual1", ["Walk"])
		print("[AnimTest] take missing, fallback %s" % take)
	if take == &"" or not _anim_player.has_animation(take):
		push_error("[AnimTest] no playable take")
		return
	_anim_master = master
	var holders: Array[String] = ["Nude"]
	for slot in SLOTS:
		holders.append(String(slot))
	var mcount := master.get_bone_count()
	for h in holders:
		var sk := _slot_skeleton(StringName(h))
		if sk == null or sk == master:
			continue
		var pairs := []
		# Vendor parts ship the same 65-bone hierarchy in the same ORDER as
		# the nude master, but under UE names (root/pelvis/spine_01...) while
		# the master speaks Standard (Root/Hips/Spine...) via its import
		# bonemap — name lookup yields zero pairs and frozen garments. When
		# counts match, drive by INDEX (probe 01/10: 65/65, order identical,
		# only the naming convention differs); else fall back to names with
		# a warning per unmapped bone (never silent).
		if sk.get_bone_count() == mcount:
			for mi in range(mcount):
				pairs.append([mi, mi])
			print("[AnimTest] pairs %s %d/%d (by index)" % [h, pairs.size(), mcount])
		else:
			var missing := []
			for mi in range(mcount):
				var ti := sk.find_bone(master.get_bone_name(mi))
				if ti != -1:
					pairs.append([mi, ti])
				else:
					missing.append(String(master.get_bone_name(mi)))
			print("[AnimTest] pairs %s %d/%d (by name, count mismatch %d vs %d)" % [h, pairs.size(), mcount, sk.get_bone_count(), mcount])
			if not missing.is_empty():
				push_warning("[AnimTest] %s unmapped: %s" % [h, ",".join(missing)])
		_anim_targets.append(sk)
		_anim_pairs.append(pairs)
	_anim_player.play(take)
	_anim_active = true
	if _anim_targets.is_empty():
		print("[AnimTest] playing %s on fused %s (0 part skeletons, nothing copied), player %s" % [take, master.get_path(), _anim_player.get_path()])
	else:
		print("[AnimTest] playing %s on %s (+%d part skeletons), player %s" % [take, master.get_path(), _anim_targets.size(), _anim_player.get_path()])
	print("[AnimTest] Remote: CharacterEditor.anim_player().play(\"rig/<take>\")")


## Copy of a pack take with every bone track rebound to the master skeleton.
## Identity mapping (01/10 rebake): pack and skeletons both speak Standard
## (imports re-aligned per rig vendor, leafs stripped at bake) — a take bone
## the master does not own is dropped + reported, never silent.
func _animtest_remap(anim: Animation, master: Skeleton3D) -> Animation:
	var out := anim.duplicate()
	out.set_loop_mode(Animation.LOOP_LINEAR)
	# Paths resolve against the player's root_node (default ".." = this
	# editor), NOT against the player itself: base is self->master.
	var base := str(get_path_to(master))
	var dropped := []
	for i in range(anim.get_track_count() - 1, -1, -1):
		var t := anim.track_get_type(i)
		var p: NodePath = anim.track_get_path(i)
		if (t == Animation.TYPE_POSITION_3D or t == Animation.TYPE_ROTATION_3D or t == Animation.TYPE_SCALE_3D) and p.get_subname_count() > 0:
			var dst := str(p.get_subname(0))
			if master.find_bone(dst) == -1:
				if not dropped.has(dst):
					dropped.append(dst)
				out.remove_track(i)
				continue
			out.track_set_path(i, NodePath(base + ":" + dst))
		else:
			out.remove_track(i)
	if not dropped.is_empty():
		dropped.erase("Root") # by design: Root stays fixed (same call as RigKit REV 31)
		if not dropped.is_empty():
			print("[AnimTest] unmapped bones dropped: %s" % ",".join(dropped))
	return out


func _process(delta: float) -> void:
	if InputManager.is_just_pressed(&"xray_toggle"):
		_cycle_xray()
	if not _anim_active or _anim_player == null or _anim_master == null:
		return
	if not is_instance_valid(_anim_master):
		return
	if _anim_player.is_playing():
		_anim_player.advance(delta)
	_anim_frame += 1
	if _anim_frame == 60:
		var moved := 0
		for b in _anim_master.get_bone_count():
			if not _anim_master.get_bone_pose(b).is_equal_approx(Transform3D.IDENTITY):
				moved += 1
		print("[AnimTest] motion check @f60: %d/%d master bones off rest" % [moved, _anim_master.get_bone_count()])
	for t in range(_anim_targets.size()):
		var tgt := _anim_targets[t]
		if not is_instance_valid(tgt):
			continue
		var pairs: Array = _anim_pairs[t]
		for p in pairs:
			var mi: int = p[0]
			var ti: int = p[1]
			tgt.set_bone_pose_position(ti, _anim_master.get_bone_pose_position(mi))
			tgt.set_bone_pose_rotation(ti, _anim_master.get_bone_pose_rotation(mi))
			tgt.set_bone_pose_scale(ti, _anim_master.get_bone_pose_scale(mi))
