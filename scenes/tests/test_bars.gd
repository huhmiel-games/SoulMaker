extends CanvasLayer

## Graybox combat bars (P3 testability): thin HP / stamina / enemy-HP bars
## under the debug labels — bars read in combat where flickering numbers
## don't. Test scenes only; the real HUD is P7 (screens/HUD). Polls the
## pools every frame, no input, nothing gameplay.
const BAR_W := 300.0

@onready var _hp: ColorRect = $HP
@onready var _st: ColorRect = $ST
@onready var _en: ColorRect = $EN
@onready var _en_bg: ColorRect = $ENBg


func _process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p != null:
		_hp.size.x = BAR_W * clampf(float(p.get("hp")) / PlayerController.HP_MAX, 0.0, 1.0)
		_st.size.x = BAR_W * clampf(float(p.get("stamina")) / PlayerController.STAMINA_MAX, 0.0, 1.0)
	var e := get_tree().get_first_node_in_group("lockable")
	var ehp: Variant = e.get("hp") if e != null else null
	if ehp == null:
		_en.visible = false
		_en_bg.visible = false
		return
	_en.visible = true
	_en_bg.visible = true
	var emax := 60.0
	var cfgv: Variant = e.get("cfg")
	if cfgv is Dictionary:
		emax = maxf(float((cfgv.get("stats", {}) as Dictionary).get("hp", 60.0)), 1.0)
	_en.size.x = BAR_W * clampf(float(ehp) / emax, 0.0, 1.0)
