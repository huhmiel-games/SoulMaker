extends Control
class_name ColorEditor

## Autonomous color-slot editor (character_editor + any asset: outfit parts,
## map walls, props...). Menu flow: host calls edit(slot_name, target_root)
## -> this panel appears with 3 sliders (Color/Intensity/Brightness) driving
## the target live. Shadow + ambient are baked shader consts (shadow 0,
## ambient 0.5, validated 29/09) — not exposed per slot. E (interact) = OK
## (keep), Space (dodge) = Cancel (restore entry values). Up/Down = select row, Left/Right (hold) = sweep,
## mouse drag on a row works too. Emits closed(applied) once; the host
## suspends its own input while visible. Opens in VISIBLE (rows are mouse-
## draggable) and restores the prior mode on close — the menu runs CAPTURED,
## so without this the cursor would stay visible and leave the window.
## Owns per-surface ShaderMaterials for its target: created from the
## StandardMaterial3D albedo on first edit (ToonKit.white_tex() backs
## albedo-less surfaces), reused with adopted values on re-edit. Dressing is
## idempotent; cancel restores values, never tears materials down.

signal closed(applied: bool)

const ROW_KEYS: Array[StringName] = [&"hue", &"sat", &"val"]
const DEFAULTS := {"hue": 0.0, "sat": 1.0, "val": 1.0}
## Albedo mode (Hair, 07/10): vendor hair is quasi-white (nothing to hue-shift),
## so the same 3 rows drive the material `albedo` (Color.from_hsv) over the
## untouched source texture. Defaults = mid grey-red starting point (user tune
## 07/10: sat/val 0.5 so the Color row answers from the first step); sat/val
## clamp to 0-1.
const SAT_MAX := 3.0
const VAL_MAX := 2.5
const HUE_RATE := 90.0 # deg/sec while Left/Right held
const SAT_RATE := 1.2 # /sec
const VAL_RATE := 1.0 # /sec
const ALBEDO_DEFAULTS := {"hue": 0.0, "sat": 0.5, "val": 0.5}
## Typematic repeat (06/10): a tap steps once, holding repeats by steps,
## then accelerates to the full sweep rates. Tune by eye.
const STEP := {&"hue": 1.0, &"sat": 0.05, &"val": 0.05}
const REPEAT_DELAY := 0.4 # sec held before repeat starts
const REPEAT_PER_SEC := 12.0 # steps/sec during the repeat phase
const ACCEL_AFTER := 2.5 # sec held when the full sweep rate is reached
const BASE_TOON: Shader = preload("res://src/shaders/base_toon.gdshader")

var _mats: Array[ShaderMaterial] = []
var _albedo := false # albedo mode for the current target (Hair only)
var _params := DEFAULTS.duplicate()
var _entry := DEFAULTS.duplicate() # values at open() — cancel restores these
var _raw := DEFAULTS.duplicate() # precise pre-snap accumulation (07/10:
# the grid snap froze slow phases — per-frame increments smaller than half
# a step rounded back to the start every frame. Raw accumulates, params show
# the snapped value)
var _row := 0
var _rows: Array[SliderRow] = []
var _armed := false
var _prior_mouse := 0 # Input.mouse_mode before open() — restored on close
var _title: Label = null
## Test-only (--nonormalmap capture flag): dress with vertex normals to
## isolate normal-map path issues. Never set by the game.
var no_normal_map := false


func _ready() -> void:
	_title = get_node_or_null("Title") as Label
	_rows = [get_node("RowColor") as SliderRow, get_node("RowIntensity") as SliderRow, get_node("RowBrightness") as SliderRow]
	_setup_rows()
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
	_albedo = false
	_setup_rows()
	_params = DEFAULTS.duplicate()
	_mats = _dress(target)
	_params = _adopted_params()
	_raw = (_params as Dictionary).duplicate()
	_entry = (_params as Dictionary).duplicate()
	_row = 0
	_sync_rows(false)
	_sync_row_select()
	if _title != null:
		_title.text = "Edit color — %s" % slot_name
	_armed = false
	_prior_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	print("[ColorEditor] open '%s' (%d surfaces)" % [slot_name, _mats.size()])


## Row ranges follow the mode: Color is always 0-360; Intensity/Brightness
## drive multipliers (hue-shift mode) or HSV sat/val 0-1 (albedo mode).
func _setup_rows() -> void:
	if _rows.is_empty():
		return # headless fallback (no panel): dress/apply need no rows
	_rows[0].setup("Color", 0.0, 360.0, 0)
	if _albedo:
		_rows[1].setup("Intensity", 0.0, 1.0, 2)
		_rows[2].setup("Brightness", 0.0, 1.0, 2)
	else:
		_rows[1].setup("Intensity", 0.0, SAT_MAX, 2)
		_rows[2].setup("Brightness", 0.0, VAL_MAX, 2)


## Open the editor on an explicit material list (fused avatar: per-slot
## surfaces whose source mesh belongs to the slot). Live values are adopted
## as-is (the host reapplies stored params after every rebuild, so there is
## no fresh/default distinction here unlike edit()). Same panel, same flow.
## Albedo white kick: near-white hair adopts sat ~0, which makes the Color row
## look dead (hue of white is invisible). The working copy then starts at sat
## 1.0 (applied at once, so the panel stays truthful); _entry keeps the true
## values so Cancel restores the white. Re-open on an already colored style
## never kicks (sat is already up).
func edit_mats(slot_name: String, mats: Array, albedo_mode := false) -> void:
	if visible:
		push_warning("[ColorEditor] already open, ignoring edit('%s')" % slot_name)
		return
	_albedo = albedo_mode
	_setup_rows()
	_mats.clear()
	for m in mats:
		if m is ShaderMaterial:
			_mats.append(m)
	_params = _adopted_params()
	_raw = (_params as Dictionary).duplicate()
	_entry = (_params as Dictionary).duplicate()
	if _albedo and float(_params["sat"]) < 0.05 and float(_params["val"]) > 0.95:
		_params["sat"] = 1.0
		_raw["sat"] = 1.0
		_apply()
	_row = 0
	_sync_rows(false)
	_sync_row_select()
	if _title != null:
		_title.text = "Edit color — %s" % slot_name
	_armed = false
	_prior_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	print("[ColorEditor] open '%s' (%d surfaces)" % [slot_name, _mats.size()])


## Dress (if needed) + restore defaults without opening the panel.
func reset_target(target: Node, albedo_mode := false) -> void:
	_albedo = albedo_mode
	_setup_rows()
	_mats = _dress(target)
	_params = (ALBEDO_DEFAULTS.duplicate() if albedo_mode else DEFAULTS.duplicate())
	_raw = DEFAULTS.duplicate()
	_entry = DEFAULTS.duplicate()
	_apply()
	_sync_rows(false)


func current_params() -> Dictionary:
	return (_params as Dictionary).duplicate()


func _process(delta: float) -> void:
	if not visible:
		return
	if not _armed:
		if not (_held(&"interact", &"place_select") or _held(&"dodge", &"deselect")):
			_armed = true
		return
	if _hit(&"cycle_spell", &"catalog_prev"):
		_row = posmod(_row - 1, _rows.size())
		_sync_row_select()
	elif _hit(&"cycle_item", &"catalog_next"):
		_row = posmod(_row + 1, _rows.size())
		_sync_row_select()
	var dir := 0.0
	if _hit(&"cycle_lhand", &"tab_prev"):
		dir -= 1.0
	if _hit(&"cycle_rhand", &"tab_next"):
		dir += 1.0
	if dir != 0.0:
		# Tap = exactly one step (no sweep on the press frame).
		_step_key(ROW_KEYS[_row], dir)
		_rows[_row].set_value(float(_params[ROW_KEYS[_row]]), false)
	else:
		var hdir := 0.0
		var held_t := 0.0
		if _held(&"cycle_lhand", &"tab_prev"):
			hdir -= 1.0
			held_t = _held_time(&"cycle_lhand", &"tab_prev")
		if _held(&"cycle_rhand", &"tab_next"):
			hdir += 1.0
			held_t = maxf(held_t, _held_time(&"cycle_rhand", &"tab_next"))
		if hdir != 0.0 and held_t > REPEAT_DELAY:
			var k := clampf((held_t - REPEAT_DELAY) / maxf(ACCEL_AFTER - REPEAT_DELAY, 0.01), 0.0, 1.0)
			var rate := lerpf(REPEAT_PER_SEC * float(STEP[ROW_KEYS[_row]]), _full_rate(ROW_KEYS[_row]), k)
			_nudge(ROW_KEYS[_row], hdir * rate * delta)
			_rows[_row].set_value(float(_params[ROW_KEYS[_row]]), false)
	if _hit(&"interact", &"place_select"):
		_confirm()
	elif _hit(&"dodge", &"deselect"):
		_cancel()


## Dual-vocabulary reads (06/10): the dresser lives in editor hosts (editor
## profile: tab/catalog/place/deselect) and game-profile test scenes (cycle/
## interact/dodge). Same capability, both names — no table/profile change,
## keyboard and gamepad stay the same logical device either way.
static func _held(game_action: StringName, editor_action: StringName) -> bool:
	return InputManager.is_pressed(game_action) or InputManager.is_pressed(editor_action)


static func _hit(game_action: StringName, editor_action: StringName) -> bool:
	return InputManager.is_just_pressed(game_action) or InputManager.is_just_pressed(editor_action)


## Longest hold time of either vocabulary (typematic repeat staging).
static func _held_time(game_action: StringName, editor_action: StringName) -> float:
	return maxf(InputManager.time_held(game_action), InputManager.time_held(editor_action))


## OK: keep live values. Also called by the headless self-test (--huetest).
func _confirm() -> void:
	hide()
	Input.mouse_mode = _prior_mouse
	print("[ColorEditor] OK %s" % _fmt())
	closed.emit(true)


## Cancel: restore entry values. Also called by the headless self-test.
func _cancel() -> void:
	_params = (_entry as Dictionary).duplicate()
	_raw = (_params as Dictionary).duplicate()
	_apply()
	hide()
	Input.mouse_mode = _prior_mouse
	print("[ColorEditor] cancel, restored %s" % _fmt())
	closed.emit(false)


func _nudge(key: StringName, amount: float) -> void:
	# amount is an absolute parameter delta (rates applied by the caller).
	# Raw accumulates unwrapped precision; only the published value snaps,
	# so sub-step phases (repeat) advance instead of freezing.
	var smax := 1.0 if _albedo else SAT_MAX
	var vmax := 1.0 if _albedo else VAL_MAX
	if key == &"hue":
		_raw[key] = wrapf(float(_raw[key]) + amount, 0.0, 360.0)
	elif key == &"sat":
		_raw[key] = clampf(float(_raw[key]) + amount, 0.0, smax)
	elif key == &"val":
		_raw[key] = clampf(float(_raw[key]) + amount, 0.0, vmax)
	_params[key] = _snap_in(key, float(_raw[key]))
	_apply()


## Grid snap (07/10): published values stop on standard step multiples
## (1.50, never 1.52). Defaults and maxes are on-grid, so values never
## leave it.
func _snap_in(key: StringName, v: float) -> float:
	var st := float(STEP[key])
	if key == &"hue":
		return wrapf(snappedf(v, st), 0.0, 360.0)
	if key == &"sat":
		return clampf(snappedf(v, st), 0.0, 1.0 if _albedo else SAT_MAX)
	return clampf(snappedf(v, st), 0.0, 1.0 if _albedo else VAL_MAX)


## One discrete step (tap response).
func _step_key(key: StringName, dir: float) -> void:
	_nudge(key, dir * float(STEP[key]))


func _full_rate(key: StringName) -> float:
	if key == &"sat":
		return SAT_RATE
	if key == &"val":
		return VAL_RATE
	return HUE_RATE


func _fmt() -> String:
	return "(Color %.0f Intensity %.2f Brightness %.2f)" % [float(_params["hue"]), float(_params["sat"]), float(_params["val"])]


func _apply() -> void:
	if _albedo:
		var c := Color.from_hsv(float(_params["hue"]) / 360.0, float(_params["sat"]), float(_params["val"]))
		for m in _mats:
			m.set_shader_parameter("albedo", c)
			m.set_shader_parameter("hue_shift_deg", 0.0)
			m.set_shader_parameter("sat_mult", 1.0)
			m.set_shader_parameter("val_mult", 1.0)
		return
	for m in _mats:
		m.set_shader_parameter("hue_shift_deg", float(_params["hue"]))
		m.set_shader_parameter("sat_mult", float(_params["sat"]))
		m.set_shader_parameter("val_mult", float(_params["val"]))


func _sync_rows(emit_signal := true) -> void:
	if _rows.is_empty():
		return
	for i in _rows.size():
		_rows[i].set_value(float(_params[ROW_KEYS[i]]), emit_signal)


func _sync_row_select() -> void:
	if _rows.is_empty():
		return
	for i in _rows.size():
		_rows[i].selected = (i == _row)
		_rows[i].queue_redraw()


func _on_row_changed(v: float, i: int) -> void:
	_row = posmod(i, _rows.size())
	_sync_row_select()
	var sv := _snap_in(ROW_KEYS[_row], v)
	_params[ROW_KEYS[_row]] = sv
	_raw[ROW_KEYS[_row]] = sv
	_rows[_row].set_value(sv, false)
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
		return (ALBEDO_DEFAULTS.duplicate() if _albedo else DEFAULTS.duplicate())
	if _albedo:
		var c := Color(_mats[0].get_shader_parameter("albedo"))
		return {"hue": float(c.h) * 360.0, "sat": float(c.s), "val": float(c.v)}
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
