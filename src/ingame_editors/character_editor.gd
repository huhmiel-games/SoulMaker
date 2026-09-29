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
const GENDERS: Array[String] = ["Male", "Female"]
const OUTFITS: Array[String] = ["Peasant", "Ranger"]
const SLOTS: Array[StringName] = [&"Body", &"Arms", &"Legs", &"Feet", &"Head", &"Accessories"]

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
	print("[Character] ready (gender %s, all slots %s)" % [GENDERS[_gender], OUTFITS[0]])
	_menu.enter_root(self)
	if "--chartest" in OS.get_cmdline_user_args() or "--chartest" in OS.get_cmdline_args():
		_run_headless_test()


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
func _apply_slot(slot: StringName) -> void:
	var holder := get_node_or_null(String(slot)) as Node3D
	if holder == null:
		push_error("[Character] missing slot node %s" % slot)
		return
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	var path := part_file(GENDERS[_gender], OUTFITS[int(_outfit[slot])], slot)
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


## Menu verbs (GenericMenu value rows: get = display, adjust(L/R) = cycle,
## reset(A/E) = default). Adjust ignores its return; the row re-renders.
func gender_display() -> String:
	return GENDERS[_gender]


func adjust_gender(dir: int) -> void:
	_gender = posmod(_gender + dir, GENDERS.size())
	_apply_all()
	print("[Character] gender %s" % GENDERS[_gender])


func reset_gender() -> void:
	_gender = 0
	_apply_all()


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
	reset_gender()
	reset_slot(&"Body")
	fails += _expect("back to male peasant", gender_display() == "Male" and slot_display(&"Body") == "Peasant")
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
