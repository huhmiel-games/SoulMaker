class_name CharacterMenu
extends GenericMenu

## Left-panel menu of the character editor (two levels, swapped in place so
## the mannequin stays dressed): root = Gender value row + Outfit submenu +
## Back to hub; outfit level = one value row per slot + Back. Value rows
## cycle live on L/R (tab_prev/tab_next) and reset on A/E; navigation is
## explicit rows only (B is inert in menus, same as MapMenu). The menu's own
## HUD is hidden (it would squash into the 360px strip); hints and toasts go
## to the editor's fullscreen HUD instead.

const HUB_SCENE := "res://scenes/main.tscn"

var _level := 0 # 0 root, 1 outfit slots
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
	return "OUTFIT" if _level == 1 else "CHARACTER"


func _menu_hint() -> String:
	return "Up/Down select · L/R change · A/E reset"


func _load_entries() -> Array:
	if _host == null:
		return []
	if _level == 1:
		var out: Array = []
		for slot in CharacterEditor.SLOTS:
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
	return [
		{"label": "Gender", "kind": "value",
			"get": _host.gender_display,
			"adjust": _host.adjust_gender,
			"reset": _host.reset_gender},
		{"label": "Outfit >", "call": _push},
		{"label": "[ ← Back ]", "open": HUB_SCENE},
	]


func _push() -> void:
	_level = 1
	_refresh_list()
	title_label.text = _menu_title()


func _pop() -> void:
	_level = 0
	_refresh_list()
	title_label.text = _menu_title()


func _notice(msg: String) -> void:
	print("[CharacterMenu] %s" % msg)
	var outer := get_tree().current_scene.get_node_or_null("MenuLayer/HUD")
	if outer != null and outer.has_method("flash"):
		(outer as EditorHUD).flash(msg)
