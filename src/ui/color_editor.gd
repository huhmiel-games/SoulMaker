extends Control
class_name ColorEditor

## Autonomous color-slot editor (character_editor + any asset: outfit parts,
## map walls, props...). Menu flow: host calls edit(slot_name, target_root)
## -> this panel appears with 3 sliders (Color/Intensity/Brightness) driving
## the target live. Shadow + ambient are baked shader consts (shadow 0,
## ambient 0.5, validated 29/09) — not exposed per slot. E (interact) = OK
## (keep), Space (dodge) = Cancel (restore entry values). Up/Down = select row, Left/Right (hold) = sweep,
## mouse drag on a row works too. Emits closed(applied) once; the host
## suspends its own input while visible and restores the mouse after.
## Owns per-surface ShaderMaterials for its target: created from the
## StandardMaterial3D albedo on first edit (ToonKit.white_tex() backs
## albedo-less surfaces), reused with adopted values on re-edit. Dressing is
## idempotent; cancel restores values, never tears materials down.

signal closed(applied: bool)

const ROW_KEYS: Array[StringName] = [&"hue", &"sat", &"val"]
const DEFAULTS := {"hue": 0.0, "sat": 1.0, "val": 1.0}
const SAT_MAX := 3.0
const VAL_MAX := 2.5
const HUE_RATE := 90.0 # deg/sec while Left/Right held
const SAT_RATE := 1.2 # /sec
const VAL_RATE := 1.0 # /sec
const BASE_TOON: Shader = preload("res://src/shaders/base_toon.gdshader")

var _mats: Array[ShaderMaterial] = []
var _params := DEFAULTS.duplicate()
var _entry := DEFAULTS.duplicate() # values at open() — cancel restores these
var _row := 0
var _rows: Array[SliderRow] = []
var _armed := false
var _title: Label = null
## Test-only (--nonormalmap capture flag): dress with vertex normals to
## isolate normal-map path issues. Never set by the game.
var no_normal_map := false


func _ready() -> void:
	_title = get_node_or_null("Title") as Label
	_rows = [get_node("RowColor") as SliderRow, get_node("RowIntensity") as SliderRow, get_node("RowBrightness") as SliderRow]
	_rows[0].setup("Color", 0.0, 360.0, 0)
	_rows[1].setup("Intensity", 0.0, SAT_MAX, 2)
	_rows[2].setup("Brightness", 0.0, VAL_MAX, 2)
	for i in _rows.size():
		_rows[i].value_changed.connect(_on_row_changed.bind(i))
	_sync_rows(false)
	_sync_row_select()
	hide()


## Open the editor on a named slot (any node subtree with meshes).
func edit(slot_name: String, target: Node) -> void:
	if visible:
		push_warning("[ColorEditor] already open, ignoring edit('%s')" % slot_name)
		return
	_mats = []
	# Fresh targets must dress at defaults: _dress_surface() builds new
	# materials from the CURRENT _params, so reset first — otherwise a new
	# slot inherits the previous slot's values. Re-edit is unaffected (live
	# materials are returned as-is, then adopted below).
	_params = DEFAULTS.duplicate()
	_mats = _dress(target)
	_params = _adopted_params()
	_entry = (_params as Dictionary).duplicate()
	_row = 0
	_sync_rows(false)
	_sync_row_select()
	if _title != null:
		_title.text = "Edit color — %s" % slot_name
	_armed = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	print("[ColorEditor] open '%s' (%d surfaces)" % [slot_name, _mats.size()])


## Dress (if needed) + restore defaults without opening the panel.
func reset_target(target: Node) -> void:
	_mats = _dress(target)
	_params = DEFAULTS.duplicate()
	_entry = DEFAULTS.duplicate()
	_apply()
	_sync_rows(false)


func current_params() -> Dictionary:
	return (_params as Dictionary).duplicate()


func _process(delta: float) -> void:
	if not visible:
		return
	if not _armed:
		if not InputManager.is_pressed(&"interact") and not InputManager.is_pressed(&"dodge"):
			_armed = true
		return
	if InputManager.is_just_pressed(&"cycle_spell"):
		_row = posmod(_row - 1, _rows.size())
		_sync_row_select()
	elif InputManager.is_just_pressed(&"cycle_item"):
		_row = posmod(_row + 1, _rows.size())
		_sync_row_select()
	var dir := 0.0
	if InputManager.is_pressed(&"cycle_lhand"):
		dir -= 1.0
	if InputManager.is_pressed(&"cycle_rhand"):
		dir += 1.0
	if dir != 0.0:
		_nudge(ROW_KEYS[_row], dir * delta)
		_rows[_row].set_value(float(_params[ROW_KEYS[_row]]), false)
	if InputManager.is_just_pressed(&"interact"):
		_confirm()
	elif InputManager.is_just_pressed(&"dodge"):
		_cancel()


## OK: keep live values. Also called by the headless self-test (--huetest).
func _confirm() -> void:
	hide()
	print("[ColorEditor] OK %s" % _fmt())
	closed.emit(true)


## Cancel: restore entry values. Also called by the headless self-test.
func _cancel() -> void:
	_params = (_entry as Dictionary).duplicate()
	_apply()
	hide()
	print("[ColorEditor] cancel, restored %s" % _fmt())
	closed.emit(false)


func _nudge(key: StringName, amount: float) -> void:
	if key == &"hue":
		_params["hue"] = wrapf(float(_params["hue"]) + HUE_RATE * amount, 0.0, 360.0)
	elif key == &"sat":
		_params["sat"] = clampf(float(_params["sat"]) + SAT_RATE * amount, 0.0, SAT_MAX)
	elif key == &"val":
		_params["val"] = clampf(float(_params["val"]) + VAL_RATE * amount, 0.0, VAL_MAX)
	_apply()


func _fmt() -> String:
	return "(Color %.0f Intensity %.2f Brightness %.2f)" % [float(_params["hue"]), float(_params["sat"]), float(_params["val"])]


func _apply() -> void:
	for m in _mats:
		m.set_shader_parameter("hue_shift_deg", float(_params["hue"]))
		m.set_shader_parameter("sat_mult", float(_params["sat"]))
		m.set_shader_parameter("val_mult", float(_params["val"]))


func _sync_rows(emit_signal := true) -> void:
	for i in _rows.size():
		_rows[i].set_value(float(_params[ROW_KEYS[i]]), emit_signal)


func _sync_row_select() -> void:
	for i in _rows.size():
		_rows[i].selected = (i == _row)
		_rows[i].queue_redraw()


func _on_row_changed(v: float, i: int) -> void:
	_row = posmod(i, _rows.size())
	_sync_row_select()
	_params[ROW_KEYS[_row]] = v
	_apply()


## Dress every mesh surface under target with an owned ShaderMaterial.
## Re-edit reuses the live materials (values adopted); first edit builds them
## from the StandardMaterial3D albedo (+tint) at DEFAULTS (edit() resets
## _params before dressing), white-backed if texture-less.
func _dress(target: Node) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	if target == null:
		push_warning("[ColorEditor] edit called with null target")
		return out
	for mi in _meshes_under(target):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			out.append(_dress_surface(mi as MeshInstance3D, s))
	return out


func _dress_surface(mi: MeshInstance3D, s: int) -> ShaderMaterial:
	var original: Material = mi.get_surface_override_material(s)
	if original == null:
		original = mi.mesh.surface_get_material(s)
	if original is ShaderMaterial and (original as ShaderMaterial).shader == BASE_TOON:
		return original as ShaderMaterial
	var tex: Texture2D = null
	var tint := Color.WHITE
	var normal_tex: Texture2D = null
	var normal_scale := 1.0
	var orm_tex: Texture2D = null
	var orm_metallic := 1.0
	if original is StandardMaterial3D:
		tex = (original as StandardMaterial3D).albedo_texture
		tint = (original as StandardMaterial3D).albedo_color
		normal_tex = (original as StandardMaterial3D).normal_texture
		normal_scale = (original as StandardMaterial3D).normal_scale
		orm_tex = (original as StandardMaterial3D).metallic_texture
		orm_metallic = (original as StandardMaterial3D).metallic
	if tex == null:
		tex = ToonKit.white_tex()
		print("[ColorEditor] %s surface %d: NO texture, flat tint %s" % [mi.name, s, str(tint)])
	else:
		print("[ColorEditor] %s surface %d: %s" % [mi.name, s, (tex as Texture2D).resource_path])
	var mat := ShaderMaterial.new()
	mat.shader = BASE_TOON
	mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("albedo", Color(tint.r, tint.g, tint.b, 1.0))
	mat.set_shader_parameter("hue_shift_deg", float(_params["hue"]))
	mat.set_shader_parameter("sat_mult", float(_params["sat"]))
	mat.set_shader_parameter("val_mult", float(_params["val"]))
	mat.set_shader_parameter("use_normal_map", normal_tex != null and not no_normal_map)
	if normal_tex != null and not no_normal_map:
		mat.set_shader_parameter("texture_normal", normal_tex)
		mat.set_shader_parameter("normal_scale", normal_scale)
		print("[ColorEditor] %s surface %d: normal %s (scale %.2f)" % [mi.name, s, (normal_tex as Texture2D).resource_path, normal_scale])
	# Specular reserved for metal pixels: ORM present = spec on + masked by
	# the ORM blue channel; no ORM = matte (never plastic). Source is the
	# imported StandardMaterial3D.metallic_texture.
	mat.set_shader_parameter("use_specular", orm_tex != null)
	mat.set_shader_parameter("use_orm_mask", orm_tex != null)
	if orm_tex != null:
		mat.set_shader_parameter("orm_texture", orm_tex)
		mat.set_shader_parameter("orm_metallic", orm_metallic)
		print("[ColorEditor] %s surface %d: orm %s (metallic %.2f, spec masked)" % [mi.name, s, (orm_tex as Texture2D).resource_path, orm_metallic])
	# Depth-push: skin (non-metal) writes depth 12mm back so buried cloth
	# wins; garments keep true depth. Same rule as ToonKit.
	ToonKit.set_skin_push(mat, orm_metallic)
	mi.set_surface_override_material(s, mat)
	return mat


## Re-edit starts from the live values (first edit: current _params).
func _adopted_params() -> Dictionary:
	if _mats.is_empty():
		return DEFAULTS.duplicate()
	var first := _mats[0]
	return {
		"hue": float(first.get_shader_parameter("hue_shift_deg")),
		"sat": float(first.get_shader_parameter("sat_mult")),
		"val": float(first.get_shader_parameter("val_mult")),
	}


static func _meshes_under(root: Node) -> Array:
	var out: Array = []
	_collect(root, out)
	return out


static func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect(child, out)
