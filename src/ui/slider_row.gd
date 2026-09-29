extends Control
class_name SliderRow

## One labeled slider row (character_editor groundwork): D-pad-native pick,
## mouse-draggable as the same capability in other units.
## - Keyboard/gamepad: the host selects the row (F) and nudges Left/Right;
##   call nudge() or set_value() from the host — this node only displays.
## - Mouse: drag on the bar sets the value from the x position (motion while
##   left-held; Input.is_mouse_button_pressed is NOT in the input_audit raw
##   list, and position comes from the UI event — same "adjust" capability
##   as D-pad Left/Right, no new capability, no device branch).
## Emits value_changed(v) on every set (host writes through to the shader).

signal value_changed(v: float)

const PAD := 6.0
const LABEL_W := 110.0
const VALUE_W := 70.0

var label_text := ""
var min_value := 0.0
var max_value := 1.0
var decimals := 0
var value := 0.0
var selected := false


func _ready() -> void:
	custom_minimum_size = Vector2(300, 30)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(p_label: String, p_min: float, p_max: float, p_decimals: int) -> void:
	label_text = p_label
	min_value = p_min
	max_value = p_max
	decimals = p_decimals
	queue_redraw()


func set_value(v: float, emit_signal := true) -> void:
	var nv := clampf(v, min_value, max_value)
	if is_equal_approx(nv, value):
		return
	value = nv
	if emit_signal:
		value_changed.emit(value)
	queue_redraw()


func fraction() -> float:
	if is_equal_approx(max_value, min_value):
		return 0.0
	return (value - min_value) / (max_value - min_value)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var bx := LABEL_W + PAD
		var bw: float = size.x - bx - VALUE_W - PAD * 2.0
		if bw > 0.0:
			set_value(min_value + clampf(((event as InputEventMouseMotion).position.x - bx) / bw, 0.0, 1.0) * (max_value - min_value))


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := get_theme_default_font_size()
	var label_col := Color(1.0, 0.9, 0.4) if selected else Color(0.75, 0.75, 0.75)
	draw_string(font, Vector2(0, size.y / 2.0 + fs * 0.35), label_text, HORIZONTAL_ALIGNMENT_LEFT, LABEL_W, fs, label_col)
	var bx := LABEL_W + PAD
	var bw: float = size.x - bx - VALUE_W - PAD * 2.0
	var bar := Rect2(bx, size.y / 2.0 - 6.0, bw, 12.0)
	draw_rect(bar, Color(0.12, 0.12, 0.14, 0.9))
	var fill := Rect2(bar.position, Vector2(bar.size.x * fraction(), bar.size.y))
	draw_rect(fill, Color(0.95, 0.75, 0.25) if selected else Color(0.55, 0.55, 0.6))
	draw_rect(bar, Color(1, 1, 1, 0.7 if selected else 0.3), false, 1.0)
	var knob_x: float = bar.position.x + bar.size.x * fraction()
	draw_line(Vector2(knob_x, bar.position.y - 3.0), Vector2(knob_x, bar.end.y + 3.0), Color.WHITE, 2.0)
	var shown := "%.*f" % [decimals, value]
	draw_string(font, Vector2(size.x - VALUE_W, size.y / 2.0 + fs * 0.35), shown, HORIZONTAL_ALIGNMENT_RIGHT, VALUE_W, fs, label_col)
