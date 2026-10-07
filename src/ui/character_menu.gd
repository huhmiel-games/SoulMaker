class_name CharacterMenu
extends GenericMenu

## Left-panel menu of the character editor (swapped in place so the
## mannequin stays dressed): root = Gender value row + Outfits/Outfits Colors/
## Physics/Hair/Eyebrows/Eyes/Beard/Face/Skin submenus + Back to hub; outfit level = one value
## row per slot; outfit-colors level = one color entry per outfit slot;
## physics level = one value row per morph slider; hair/eyebrows/eyes/beard
## levels = style + color; face level = one value row per form slider (Head
## XZ/Y multipliers over the Physics Head size); skin level = color only
## (room for more later).
## (menu grammar, no B). Value rows cycle live on L/R (tab_prev/tab_next)
## and reset on A/E; navigation is explicit rows only (B is inert in menus,
## same as MapMenu). The menu's own HUD is hidden (it would squash into the
## 360px strip); hints and toasts go to the editor's fullscreen HUD instead.
## While the dresser panel is open, menu input is gated (both read the same
## InputManager actions — otherwise Up/Down would move the cursor behind
## the panel).

const HUB_SCENE := "res://scenes/main.tscn"

const LEVEL_ROOT := 0
const LEVEL_OUTFITS := 1
const LEVEL_COLORS := 2
const LEVEL_PHYSICS := 3
const LEVEL_HAIR := 4
const LEVEL_EYEBROWS := 5
const LEVEL_SKIN := 6
const LEVEL_EYES := 7
const LEVEL_BEARD := 8
const LEVEL_FACE := 9

var _level := LEVEL_ROOT # 0 root, 1 outfits, 2 outfit colors, 3 physics, 4 hair, 5 brows, 6 skin, 7 eyes, 8 beard, 9 face
var _host: CharacterEditor = null


func _ready() -> void:
	super._ready()
	if hud != null:
		hud.visible = false


## Called by the host after boot (GenericMenu._ready runs before the host
## exists, so the first _load_entries is empty and this refresh fills it).
func enter_root(host: CharacterEditor) -> void:
	_host = host
	_level = 0
	_refresh_list()


func _menu_title() -> String:
	match _level:
		LEVEL_OUTFITS:
			return "OUTFIT"
		LEVEL_COLORS:
			return "OUTFITS COLORS"
		LEVEL_PHYSICS:
			return "PHYSICS"
		LEVEL_HAIR:
			return "HAIR"
		LEVEL_EYEBROWS:
			return "EYEBROWS"
		LEVEL_SKIN:
			return "SKIN"
		LEVEL_EYES:
			return "EYES"
		LEVEL_BEARD:
			return "BEARD"
		LEVEL_FACE:
			return "FACE"
	return "CHARACTER"


func _menu_hint() -> String:
	if _level == LEVEL_COLORS or _level == LEVEL_SKIN:
		return "Up/Down select · A/E edit color"
	return "Up/Down select · L/R change · A/E reset"


func _load_entries() -> Array:
	if _host == null:
		return []
	if _level == LEVEL_OUTFITS:
		var out: Array = []
		for slot in CharacterAvatar.SLOTS:
			var s := slot
			# Note: Callable.bind() appends bound args AFTER call-time args,
			# but GenericMenu calls adjust.call(dir) — so lambdas keep the
			# (slot, dir) host order instead of bind().
			out.append({"label": String(s), "kind": "value",
				"get": _host.slot_display.bind(s),
				"adjust": func(dir: int) -> void: _host.adjust_slot(s, dir),
				"reset": _host.reset_slot.bind(s)})
		out.append({"label": "[ ← Back ]", "call": _pop})
		return out
	if _level == LEVEL_COLORS:
		var cout: Array = []
		for slot in CharacterAvatar.OUTFIT_COLOR_SLOTS:
			var s := slot
			cout.append({"label": String(s), "call": _host.open_color.bind(s)})
		cout.append({"label": "[ ← Back ]", "call": _pop})
		return cout
	if _level == LEVEL_PHYSICS:
		var pout: Array = []
		for key in CharacterAvatar.PHYS_KEYS:
			var k := key
			pout.append({"label": String(k), "kind": "value",
				"get": _host.phys_display.bind(k),
				"adjust": func(dir: int) -> void: _host.adjust_phys(k, dir),
				"reset": _host.reset_phys.bind(k)})
		pout.append({"label": "[ ← Back ]", "call": _pop})
		return pout
	if _level == LEVEL_HAIR:
		return [
			{"label": "Style", "kind": "value",
				"get": _host.hair_display,
				"adjust": _host.adjust_hair,
				"reset": _host.reset_hair},
			{"label": "Color", "call": _host.open_color.bind(&"Hair")},
			{"label": "[ ← Back ]", "call": _pop},
		]
	if _level == LEVEL_EYEBROWS:
		return [
			{"label": "Style", "kind": "value",
				"get": _host.eyebrow_display,
				"adjust": _host.adjust_eyebrow,
				"reset": _host.reset_eyebrow},
			{"label": "Color", "call": _host.open_color.bind(&"Eyebrows")},
			{"label": "[ ← Back ]", "call": _pop},
		]
	if _level == LEVEL_SKIN:
		return [
			{"label": "Color", "call": _host.open_color.bind(&"Skin")},
			{"label": "[ ← Back ]", "call": _pop},
		]
	if _level == LEVEL_EYES:
		return [
			{"label": "Style", "kind": "value",
				"get": _host.eye_display,
				"adjust": _host.adjust_eye,
				"reset": _host.reset_eye},
			{"label": "Color", "call": _host.open_color.bind(&"Eyes")},
			{"label": "[ ← Back ]", "call": _pop},
		]
	if _level == LEVEL_BEARD:
		return [
			{"label": "Style", "kind": "value",
				"get": _host.beard_display,
				"adjust": _host.adjust_beard,
				"reset": _host.reset_beard},
			{"label": "Color", "call": _host.open_color.bind(&"Beard")},
			{"label": "[ ← Back ]", "call": _pop},
		]
	if _level == LEVEL_FACE:
		var fout := []
		for k in CharacterAvatar.FACE_KEYS:
			fout.append({"label": String(k), "kind": "value",
				"get": _host.face_shape_display.bind(k),
				"adjust": func(dir: int) -> void: _host.adjust_face_shape(k, dir),
				"reset": _host.reset_face_shape.bind(k)})
		fout.append({"label": "[ ← Back ]", "call": _pop})
		return fout
	return [
		{"label": "Gender", "kind": "value",
			"get": _host.gender_display,
			"adjust": _host.adjust_gender,
			"reset": _host.reset_gender},
		{"label": "Outfits >", "call": _push.bind(LEVEL_OUTFITS)},
		{"label": "Outfits Colors >", "call": _push.bind(LEVEL_COLORS)},
		{"label": "Physics >", "call": _push.bind(LEVEL_PHYSICS)},
		{"label": "Hair >", "call": _push.bind(LEVEL_HAIR)},
		{"label": "Eyebrows >", "call": _push.bind(LEVEL_EYEBROWS)},
		{"label": "Eyes >", "call": _push.bind(LEVEL_EYES)},
		{"label": "Beard >", "call": _push.bind(LEVEL_BEARD)},
		{"label": "Face >", "call": _push.bind(LEVEL_FACE)},
		{"label": "Skin >", "call": _push.bind(LEVEL_SKIN)},
		{"label": "[ ← Back ]", "open": HUB_SCENE},
	]


func _push(level: int = LEVEL_OUTFITS) -> void:
	_level = level
	_refresh_list()
	title_label.text = _menu_title()
	if _host != null:
		_host.on_menu_level(_level)


func _pop() -> void:
	_level = LEVEL_ROOT
	_refresh_list()
	title_label.text = _menu_title()
	if _host != null:
		_host.on_menu_level(_level)


## Gate: the dresser panel reads the same InputManager actions — while it
## is open the menu stays out of the way (preview remains visible behind).
func _on_input_action(action: StringName) -> void:
	if _host != null and _host.is_color_open():
		return
	super._on_input_action(action)


func _notice(msg: String) -> void:
	print("[CharacterMenu] %s" % msg)
	var outer := get_tree().current_scene.get_node_or_null("MenuLayer/HUD")
	if outer != null and outer.has_method("flash"):
		(outer as EditorHUD).flash(msg)
