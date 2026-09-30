class_name CharacterEditor
extends Node3D

## Character editor v0 (base): gender + per-slot outfit picker with a live
## mannequin preview. Session-only (defaults Male/Peasant every boot;
## GameState persistence comes later when the game reads the config).
## Six slots (Body/Arms/Legs/Feet/Head/Accessories), two outfits
## (Peasant/Ranger — extend OUTFITS plus part_file for more). Parts are
## Modular-Parts glTF dressed toon by a hidden ColorEditor (normals +
## ORM-metal specular, the validated look). The left panel is a
## CharacterMenu (GenericMenu subclass): value rows cycle live on L/R,
## A/E resets to default, explicit Back rows only (menu grammar, no B).
## Run: Godot --path . scenes/ingame_editors/character_editor.tscn

const PART_DIR := "res://assets/meshes/outfits/universal_outfit_free/Exports/glTF (Godot-Unreal)/Modular Parts/"
const FITTED_DIR := "res://assets/meshes/outfits/fitted/"
const NUDE_DIR := "res://assets/meshes/characters/"
const GENDERS: Array[String] = ["Male", "Female"]
const OUTFITS: Array[String] = ["Peasant", "Ranger"]
const SLOTS: Array[StringName] = [&"Body", &"Arms", &"Legs", &"Feet", &"Head", &"Accessories"]
## Face meshes (push must stay OFF: eyes sit millimeters above the face and
## a pushed face would swallow them). Node names, identical in both fullbodies.
const FACE_NODES: Array[StringName] = [&"Eyebrows", &"Eyes"]
## Fitted parts (route A, 30/09 — replaces shader inflate passes 1+2,
## REVERTED: uniform size-up ballooned rigid pieces and cracked hard folds
## open; per-vertex conforming preserves the authored style instead).
## _fitted_or_raw() loads the `_Fitted.glb` conformed variant from FITTED_DIR
## (garment pushed to nude + margin, scripted bake in
## src/cli_tools/conform_garments.py + conform_manifest.json)
## when present, else the raw vendor part. Skin embedded in garment parts
## (bare forearms in Arms) is cleaned asset-side by the human.

var _gender := 0
var _outfit := {} # StringName slot -> int index into OUTFITS
var _dresser: ColorEditor = null
var _menu: CharacterMenu = null


func _ready() -> void:
	_dresser = get_node_or_null("MenuLayer/Dresser") as ColorEditor
	_menu = get_node_or_null("MenuLayer/Menu") as CharacterMenu
	if _dresser == null or _menu == null:
		push_error("[Character] missing Dresser or Menu node")
		return
	for slot in SLOTS:
		_outfit[slot] = 0
		_apply_slot(slot)
	_apply_nude()
	print("[Character] ready (gender %s, all slots %s)" % [GENDERS[_gender], OUTFITS[0]])
	_menu.enter_root(self)
	if "--chartest" in OS.get_cmdline_user_args() or "--chartest" in OS.get_cmdline_args():
		_run_headless_test()
	if "--capturetest" in OS.get_cmdline_user_args() or "--capturetest" in OS.get_cmdline_args():
		_run_capture_test()


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


## Conformed variant of a vendor part path: `fitted/` bake dir first, then
## the legacy alongside-vendor location (transition), else the raw path
## unchanged (empty in = empty out). Keeps the editor working before/during
## baking and on clones without the local bake (vendor pack is
## redistribution-forbidden: fitted files are local rebuilds, never versioned).
func _fitted_or_raw(path: String) -> String:
	if path.is_empty():
		return ""
	var fitted := FITTED_DIR + path.get_file().get_basename() + "_Fitted.glb"
	if FileAccess.file_exists(fitted):
		return fitted
	var legacy := path.get_basename() + "_Fitted.glb"
	if FileAccess.file_exists(legacy):
		return legacy
	return path


## Swap one slot to its current (gender, outfit) combo, dressed toon.
func _apply_slot(slot: StringName) -> void:
	var holder := get_node_or_null(String(slot)) as Node3D
	if holder == null:
		push_error("[Character] missing slot node %s" % slot)
		return
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	var path := _fitted_or_raw(part_file(GENDERS[_gender], OUTFITS[int(_outfit[slot])], slot))
	if path.is_empty():
		print("[Character] %s: no part (%s %s)" % [String(slot), GENDERS[_gender], OUTFITS[int(_outfit[slot])]])
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("[Character] cannot load %s" % path)
		return
	holder.add_child(packed.instantiate())
	_dresser.reset_target(holder)
	print("[Character] %s -> %s" % [String(slot), path.get_file()])


func _apply_all() -> void:
	for slot in SLOTS:
		_apply_slot(slot)


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


## Menu verbs (GenericMenu value rows: get = display, adjust(L/R) = cycle,
## reset(A/E) = default). Adjust ignores its return; the row re-renders.
func gender_display() -> String:
	return GENDERS[_gender]


func adjust_gender(dir: int) -> void:
	_gender = posmod(_gender + dir, GENDERS.size())
	_apply_all()
	_apply_nude()
	print("[Character] gender %s" % GENDERS[_gender])


func reset_gender() -> void:
	_gender = 0
	_apply_all()
	_apply_nude()


func slot_display(slot: StringName) -> String:
	if part_file(GENDERS[_gender], OUTFITS[int(_outfit[slot])], slot).is_empty():
		return "--"
	return OUTFITS[int(_outfit[slot])]


func adjust_slot(slot: StringName, dir: int) -> void:
	_outfit[slot] = posmod(int(_outfit[slot]) + dir, OUTFITS.size())
	_apply_slot(slot)


func reset_slot(slot: StringName) -> void:
	_outfit[slot] = 0
	_apply_slot(slot)


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
	fails += _expect("body dressed", _dressed_count(&"Body") > 0)
	fails += _expect("arms dressed", _dressed_count(&"Arms") > 0)
	fails += _expect("legs dressed", _dressed_count(&"Legs") > 0)
	fails += _expect("feet dressed", _dressed_count(&"Feet") > 0)
	fails += _expect("head empty", _dressed_count(&"Head") == 0)
	adjust_slot(&"Body", 1)
	fails += _expect("body ranger shown", slot_display(&"Body") == "Ranger")
	fails += _expect("body redressed", _dressed_count(&"Body") > 0)
	adjust_gender(1)
	fails += _expect("gender female", gender_display() == "Female")
	fails += _expect("body outfit kept", slot_display(&"Body") == "Ranger")
	fails += _expect("female body dressed", _dressed_count(&"Body") > 0)
	fails += _expect("female nude dressed", _dressed_count(&"Nude") > 0)
	reset_gender()
	reset_slot(&"Body")
	fails += _expect("back to male peasant", gender_display() == "Male" and slot_display(&"Body") == "Peasant")
	fails += _expect("male nude dressed", _dressed_count(&"Nude") > 0)
	fails += _expect("nude body push on", _nude_push(&"SuperHero_Male") > 0.01)
	fails += _expect("nude eyes push off", _nude_push(&"Eyes") < 0.001)
	fails += _expect("fitted fallback empty", _fitted_or_raw("") == "")
	fails += _expect("fitted fallback raw", _fitted_or_raw(PART_DIR + "Nope.gltf") == PART_DIR + "Nope.gltf")
	var _legs_path := _fitted_or_raw(part_file("Male", "Peasant", &"Legs"))
	fails += _expect("legs fitted or raw fallback", _legs_path.ends_with("_Fitted.glb") or _legs_path.ends_with("Male_Peasant_Legs.gltf"))
	if not _legs_path.ends_with("_Fitted.glb"):
		print("[CharTest] NOTICE raw fallback (no local fitted bake — rebuild: conform_manifest.json)")
	fails += _expect("body albedo wired", _slot_tex(&"Body") != null)
	adjust_slot(&"Head", 1)
	fails += _expect("hood shown", slot_display(&"Head") == "Ranger")
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


## Dressed = meshes under the slot holder carrying a toon override material.
func _dressed_count(slot: StringName) -> int:
	var n := 0
	var holder := get_node_or_null(String(slot))
	if holder == null:
		return 0
	for mi in ColorEditor._meshes_under(holder):
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.mesh == null:
			continue
		for s in mmi.mesh.get_surface_count():
			if mmi.get_surface_override_material(s) is ShaderMaterial:
				n += 1
	return n


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
		for slot in SLOTS:
			var holder := get_node_or_null(String(slot))
			if holder != null:
				(holder as Node3D).visible = false
	if "--noshadownude" in args:
		var nude_holder := get_node_or_null("Nude")
		if nude_holder != null:
			for mi in ColorEditor._meshes_under(nude_holder):
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if "--nonormalmap" in args:
		_dresser.no_normal_map = true
		_apply_all()
		_apply_nude()
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


## Override depth-push on every dressed surface (nude + slots).
func _set_push_all(v: float) -> void:
	var holders: Array[String] = ["Nude"]
	for slot in SLOTS:
		holders.append(String(slot))
	for h in holders:
		var holder := get_node_or_null(h)
		if holder == null:
			continue
		for mi in ColorEditor._meshes_under(holder):
			var mmi := mi as MeshInstance3D
			if mmi == null or mmi.mesh == null:
				continue
			for s in mmi.mesh.get_surface_count():
				var mat := mmi.get_surface_override_material(s) as ShaderMaterial
				if mat != null:
					mat.set_shader_parameter("depth_push", v)


## First dressed override material under a slot holder (null when the
## holder is missing/empty/undressed).
func _first_mat(slot: StringName) -> ShaderMaterial:
	var holder := get_node_or_null(String(slot))
	if holder == null:
		return null
	for mi in ColorEditor._meshes_under(holder):
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.mesh == null:
			continue
		for s in mmi.mesh.get_surface_count():
			var mat := mmi.get_surface_override_material(s) as ShaderMaterial
			if mat != null:
				return mat
	return null


## albedo_texture on the first override material under a slot holder (null
## when missing/unwired — the white-material regression, 30/09: fitted .glb
## moved folders without its texture URIs).
func _slot_tex(slot: StringName) -> Texture2D:
	var mat := _first_mat(slot)
	if mat == null:
		return null
	return mat.get_shader_parameter("albedo_texture") as Texture2D


## depth_push value on the first override material of a nude mesh node
## (-1 when the node/material is missing, which fails the caller).
func _nude_push(node_name: StringName) -> float:
	var holder := get_node_or_null("Nude")
	if holder == null:
		return -1.0
	for mi in ColorEditor._meshes_under(holder):
		var mmi := mi as MeshInstance3D
		if mmi == null or StringName(mmi.name) != node_name or mmi.mesh == null:
			continue
		for s in mmi.mesh.get_surface_count():
			var mat := mmi.get_surface_override_material(s) as ShaderMaterial
			if mat != null:
				return float(mat.get_shader_parameter("depth_push"))
	return -1.0
