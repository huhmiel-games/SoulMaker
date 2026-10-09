class_name CharacterMenu
extends GenericMenu

## Left-panel menu of the character editor (swapped in place so the
## mannequin stays dressed): root = Gender value row + Outfits/Outfits Colors/
## Physics/Hair/Eyebrows/Eyes/Beard/Face/Skin submenus + Back to hub; outfit level = one value
## row per slot; outfit-colors level = one color entry per outfit slot;
## physics level = one value row per morph slider; hair/eyebrows/eyes/beard
## levels = style + color; face hub = 7 submenus (Global = Width/Length head
## multipliers, Nose/Mouth/Eyes/Jaw/Cheeks/Forehead = sculpt rows on
## SCULPT_SPEC.menu, mm); skin level = color only (room for more).
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
const LEVEL_FACE_GLOBAL := 10
const LEVEL_FACE_NOSE := 11
const LEVEL_FACE_MOUTH := 12
const LEVEL_FACE_EYES := 13
const LEVEL_FACE_JAW := 14
const LEVEL_FACE_CHEEKS := 15
const LEVEL_FACE_FOREHEAD := 16

## Face hub submenus (label + sculpt-spec group; global = FACE_KEYS Width/
## Length, the rest filter SCULPT_KEYS on spec.menu — a new spec row lands in
## its submenu with no menu change). Eyes/Cheeks/Forehead hold Back only
## until their rows are authored (same room-for-more as Skin).
const FACE_SUBS := [
	{"level": LEVEL_FACE_GLOBAL, "label": "Global >", "group": "global"},
	{"level": LEVEL_FACE_NOSE, "label": "Nose >", "group": "nose"},
	{"level": LEVEL_FACE_MOUTH, "label": "Mouth >", "group": "mouth"},
	{"level": LEVEL_FACE_EYES, "label": "Eyes >", "group": "eyes"},
	{"level": LEVEL_FACE_JAW, "label": "Jaw & Chin >", "group": "jaw"},
	{"level": LEVEL_FACE_CHEEKS, "label": "Cheeks >", "group": "cheeks"},
	{"level": LEVEL_FACE_FOREHEAD, "label": "Forehead & Ears >", "group": "forehead"},
]

var _level := LEVEL_ROOT # 0 root, 1 outfits, 2 outfit colors, 3 physics, 4 hair, 5 brows, 6 skin, 7 eyes, 8 beard, 9 face hub, 10-16 face subs
var _host: CharacterEditor = null
## Cursor memory (09/10): level -> cursor, restored on Back. Entering a level
## always starts at the top; Back returns to the previously chosen entry
## (Face->Mouth->Back lands on Face with Mouth highlighted).


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
		LEVEL_FACE_GLOBAL:
			return "FACE · GLOBAL"
		LEVEL_FACE_NOSE:
			return "FACE · NOSE"
		LEVEL_FACE_MOUTH:
			return "FACE · MOUTH"
		LEVEL_FACE_EYES:
			return "FACE · EYES"
		LEVEL_FACE_JAW:
			return "FACE · JAW & CHIN"
		LEVEL_FACE_CHEEKS:
			return "FACE · CHEEKS"
		LEVEL_FACE_FOREHEAD:
			return "FACE · FOREHEAD & EARS"
	return "CHARACTER"


## Face hub + submenus share the close-up (whole face needs it).
static func is_face_level(level: int) -> bool:
	return level == LEVEL_FACE or level == LEVEL_FACE_GLOBAL or level == LEVEL_FACE_NOSE or level == LEVEL_FACE_MOUTH or level == LEVEL_FACE_EYES or level == LEVEL_FACE_JAW or level == LEVEL_FACE_CHEEKS or level == LEVEL_FACE_FOREHEAD


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
		for sub in FACE_SUBS:
			fout.append({"label": String(sub["label"]), "call": _push.bind(int(sub["level"]))})
		fout.append({"label": "[ ← Back ]", "call": _pop})
		return fout
	for sub in FACE_SUBS:
		if _level == int(sub["level"]):
			return _face_rows(String(sub["group"]))
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


## Rows of one face submenu: Global = FACE_KEYS (head multipliers), the rest =
## SCULPT_KEYS filtered on spec.menu. Back closes every level.
func _face_rows(group: String) -> Array:
	var fout := []
	if group == "global":
		for key in CharacterAvatar.FACE_KEYS:
			var k := key
			fout.append({"label": String(k), "kind": "value",
				"get": _host.face_shape_display.bind(k),
				"adjust": func(dir: int) -> void: _host.adjust_face_shape(k, dir),
				"reset": _host.reset_face_shape.bind(k)})
	else:
		for key in CharacterAvatar.SCULPT_KEYS:
			var k := key
			if String((CharacterAvatar.SCULPT_SPEC.get(k, {}) as Dictionary).get("menu", "")) == group:
				fout.append({"label": String(k), "kind": "value",
					"get": _host.face_sculpt_display.bind(k),
					"adjust": func(dir: int) -> void: _host.adjust_face_sculpt(k, dir),
					"reset": _host.reset_face_sculpt.bind(k)})
	fout.append({"label": "[ ← Back ]", "call": _pop})
	return fout


var _cursor_mem := {}


func _push(level: int = LEVEL_OUTFITS) -> void:
	_cursor_mem[_level] = _cursor
	_level = level
	_cursor = 0
	_refresh_list()
	title_label.text = _menu_title()
	if _host != null:
		_host.on_menu_level(_level)


func _pop() -> void:
	# Face subs return to the hub (two-level Back); everything else to root.
	_cursor_mem[_level] = _cursor
	_level = LEVEL_FACE if is_face_level(_level) and _level != LEVEL_FACE else LEVEL_ROOT
	_cursor = int(_cursor_mem.get(_level, 0))
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
