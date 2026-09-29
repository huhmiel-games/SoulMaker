extends Node3D

## Demo menu host for the autonomous ColorEditor panel (proves the menu flow
## for any asset: outfit parts here, map walls tomorrow): Up/Down selects a
## slot, E opens "edit color" on it, R resets it. OK/Cancel inside the panel
## returns here. The editor owns sliders + materials; this host only picks
## targets and mirrors values.
## Controls (game profile, keyboard+gamepad parity, existing actions only):
## mouse/right-stick = orbit (OrbitCameraWithZoom rig), wheel/L2-R2 = zoom
## (same cam_zoom action), Up/Down = select part, E = edit color, R = reset
## part, N/L3 = NMAP on/off (TEMP normal-map debug, removed once validated),
## Esc = release mouse.
## Run: Godot --path . scenes/tests/hue_shift_test.tscn

const PART_ORDER: Array[StringName] = [&"Body", &"Arms", &"Legs", &"Feet"]

var _sel := 0
var _values := {} # StringName -> Dictionary (last applied params per part)
var _nmap := true # TEMP debug: normal-map on/off across all parts
var _label: Label = null
var _editor: ColorEditor = null


func _ready() -> void:
	InputManager.set_profile(&"game")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_label = get_node_or_null("HUD/State") as Label
	for part in PART_ORDER:
		_values[part] = {"hue": 0.0, "sat": 1.0, "val": 1.0}
	_editor = get_node_or_null("HUD/ColorEditor") as ColorEditor
	if _editor == null:
		push_error("[HueShift] missing ColorEditor node")
	else:
		_editor.closed.connect(_on_editor_closed)
		# Boot fully dressed (toon, defaults, no panel): look tests judge the
		# real shader on every slot, never a PBR/toon mix. E reuses the live
		# materials and adopts their values — the menu flow is unchanged.
		for part in PART_ORDER:
			_editor.reset_target(get_node_or_null(String(part)))
		print("[HueShift] all parts dressed (toon defaults)")
	_update_label()
	print("[HueShift] ready (orbit mouse/RS, Up/Down part, E edit color, R reset, Esc mouse)")
	if "--huetest" in OS.get_cmdline_user_args() or "--huetest" in OS.get_cmdline_args():
		_run_headless_test()


func _process(_delta: float) -> void:
	if InputManager.is_just_pressed(&"menu"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		print("[HueShift] mouse released (E recaptures)")
		return
	if _editor != null and _editor.visible:
		return # editor owns all input while open
	if InputManager.is_just_pressed(&"nmap_toggle"):
		_set_nmap(not _nmap)
		print("[HueShift] NMAP %s" % ("ON" if _nmap else "OFF"))
		return
	if InputManager.is_just_pressed(&"interact"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif _editor != null:
			_editor.edit(String(PART_ORDER[_sel]), get_node_or_null(String(PART_ORDER[_sel])))
		return
	if InputManager.is_just_pressed(&"cycle_spell"):
		_sel = posmod(_sel - 1, PART_ORDER.size())
		print("[HueShift] select %s" % PART_ORDER[_sel])
	elif InputManager.is_just_pressed(&"cycle_item"):
		_sel = posmod(_sel + 1, PART_ORDER.size())
		print("[HueShift] select %s" % PART_ORDER[_sel])
	if InputManager.is_just_pressed(&"use_item") and _editor != null:
		_editor.reset_target(get_node_or_null(String(PART_ORDER[_sel])))
		_values[PART_ORDER[_sel]] = _editor.current_params()
		print("[HueShift] %s reset" % PART_ORDER[_sel])
	_update_label()


func _on_editor_closed(applied: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var part: StringName = PART_ORDER[_sel]
	if applied and _editor != null:
		_values[part] = _editor.current_params()
		print("[HueShift] %s kept %s" % [part, _fmt(part)])
	else:
		print("[HueShift] %s edit cancelled" % part)
	_set_nmap(_nmap) # re-dress on open would re-enable normals; keep the flag


## TEMP debug: flip use_normal_map on every dressed toon surface of every
## part (materials without a normal texture stay off). Removed with the
## nmap_toggle action once the normal map is validated.
func _set_nmap(on: bool) -> void:
	_nmap = on
	for part in PART_ORDER:
		var root := get_node_or_null(String(part))
		if root == null:
			continue
		for mi in ColorEditor._meshes_under(root):
			var mmi := mi as MeshInstance3D
			var mesh := mmi.mesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				var mat: Material = mmi.get_surface_override_material(s)
				if mat == null:
					mat = mesh.surface_get_material(s)
				if mat is ShaderMaterial:
					var sm := mat as ShaderMaterial
					var has_n := sm.get_shader_parameter("texture_normal") != null
					sm.set_shader_parameter("use_normal_map", on and has_n)
	_update_label()


## Headless self-test (--huetest): drives the real panel paths (open, row
## drags, OK, cancel, target reset) with prints + summary, then quits.
## Run: Godot --headless --path . scenes/tests/hue_shift_test.tscn -- --huetest
func _run_headless_test() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var fails := 0
	# 1. Open on Body, drag the Color row (real value_changed path), confirm.
	_editor.edit("Body", get_node_or_null("Body"))
	fails += _expect("open visible", _editor.visible)
	(_editor.get_node("RowColor") as SliderRow).set_value(120.0)
	(_editor.get_node("RowIntensity") as SliderRow).set_value(2.0)
	var hue := float(_editor._mats[0].get_shader_parameter("hue_shift_deg"))
	var sat := float(_editor._mats[0].get_shader_parameter("sat_mult"))
	fails += _expect("live write hue", is_equal_approx(hue, 120.0))
	fails += _expect("live write sat", is_equal_approx(sat, 2.0))
	# 1b. Normal map carried through from the imported material.
	var body_mi := (_editor._meshes_under(get_node_or_null("Body"))[0] as MeshInstance3D)
	var src: Material = body_mi.mesh.surface_get_material(0)
	if src is StandardMaterial3D and (src as StandardMaterial3D).normal_texture != null:
		fails += _expect("normal enabled", bool(_editor._mats[0].get_shader_parameter("use_normal_map")))
		fails += _expect("normal texture", (_editor._mats[0].get_shader_parameter("texture_normal") as Texture2D) == (src as StandardMaterial3D).normal_texture)
		fails += _expect("normal scale", is_equal_approx(float(_editor._mats[0].get_shader_parameter("normal_scale")), float((src as StandardMaterial3D).normal_scale)))
	else:
		fails += _expect("body has imported normal", false)
	# 1b2. ORM mask carried through: specular on + masked iff the imported
	# material ships a metallic texture (also proves the importer mapping).
	if src is StandardMaterial3D and (src as StandardMaterial3D).metallic_texture != null:
		fails += _expect("spec on with orm", bool(_editor._mats[0].get_shader_parameter("use_specular")))
		fails += _expect("orm mask on", bool(_editor._mats[0].get_shader_parameter("use_orm_mask")))
		fails += _expect("orm texture", (_editor._mats[0].get_shader_parameter("orm_texture") as Texture2D) == (src as StandardMaterial3D).metallic_texture)
		fails += _expect("orm metallic", is_equal_approx(float(_editor._mats[0].get_shader_parameter("orm_metallic")), float((src as StandardMaterial3D).metallic)))
	elif src is StandardMaterial3D:
		fails += _expect("spec off without orm", not bool(_editor._mats[0].get_shader_parameter("use_specular")))
		fails += _expect("orm mask off", not bool(_editor._mats[0].get_shader_parameter("use_orm_mask")))
	else:
		fails += _expect("body has imported standard material", false)
	# 1b3. Skin regression (Arms surface 1 = MI_Regular_Male, metallic factor 0
	# with a roughness-only map whose blue channel is white filler): the
	# factor must kill the specular. Reads the boot-dressed live overrides.
	var skin_mat: ShaderMaterial = null
	for mi in _editor._meshes_under(get_node_or_null("Arms")):
		var mmi := mi as MeshInstance3D
		if mmi.mesh != null and mmi.mesh.get_surface_count() > 1:
			skin_mat = mmi.get_surface_override_material(1) as ShaderMaterial
	fails += _expect("skin surface found", skin_mat != null)
	if skin_mat != null:
		fails += _expect("skin orm metallic 0", is_equal_approx(float(skin_mat.get_shader_parameter("orm_metallic")), 0.0))
	# 1c. TEMP NMAP toggle flips the live materials both ways.
	_set_nmap(false)
	fails += _expect("nmap toggle off", not bool(_editor._mats[0].get_shader_parameter("use_normal_map")))
	_set_nmap(true)
	fails += _expect("nmap toggle on", bool(_editor._mats[0].get_shader_parameter("use_normal_map")))
	_editor._confirm()
	fails += _expect("confirm hides", not _editor.visible)
	fails += _expect("host stored", is_equal_approx(float((_values[&"Body"] as Dictionary)["hue"]), 120.0))
	# 2. Re-edit adopts live values (no reset to defaults).
	_editor.edit("Body", get_node_or_null("Body"))
	fails += _expect("re-edit adopts", is_equal_approx(float(_editor.current_params()["hue"]), 120.0))
	(_editor.get_node("RowColor") as SliderRow).set_value(240.0)
	_editor._cancel()
	fails += _expect("cancel hides", not _editor.visible)
	var back := float(_editor._mats[0].get_shader_parameter("hue_shift_deg"))
	fails += _expect("cancel restores", is_equal_approx(back, 120.0))
	# 2b. Fresh target starts at defaults (no leak from Body's 120).
	_editor.edit("Legs", get_node_or_null("Legs"))
	var fresh: Dictionary = _editor.current_params()
	fails += _expect("fresh target defaults", is_equal_approx(float(fresh["hue"]), 0.0) and is_equal_approx(float(fresh["sat"]), 1.0) and is_equal_approx(float(fresh["val"]), 1.0))
	_editor._cancel()
	# 3. Target reset without opening.
	_editor.reset_target(get_node_or_null("Legs"))
	var legs: Array = []
	for mi in _editor._meshes_under(get_node_or_null("Legs")):
		legs.append(mi)
	fails += _expect("reset dressed legs", not legs.is_empty())
	print("[HueTest] %d FAIL" % fails)
	get_tree().quit()


func _fmt(part: StringName) -> String:
	var p: Dictionary = _values[part]
	return "(Color %.0f Intensity %.2f Brightness %.2f)" % [float(p["hue"]), float(p["sat"]), float(p["val"])]


func _expect(name: String, cond: bool) -> int:
	print("[HueTest] %s %s" % ["PASS" if cond else "FAIL", name])
	return 0 if cond else 1


func _update_label() -> void:
	if _label == null:
		return
	var lines: PackedStringArray = []
	lines.append("NMAP: %s (N/L3, temp)" % ("ON" if _nmap else "OFF"))
	for i in PART_ORDER.size():
		var mark := ">" if i == _sel else " "
		lines.append("%s %s %s" % [mark, PART_ORDER[i], _fmt(PART_ORDER[i])])
	lines.append("Up/Down part | E edit color | R reset")
	lines.append("orbit: mouse / right stick, zoom: wheel / L2+R2, Esc frees mouse")
	_label.text = "\n".join(lines)
