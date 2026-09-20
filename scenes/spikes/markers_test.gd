extends Node3D

const AnimPrepScript := preload("res://src/tools/spikes/anim_prep.gd")
const MALE_SCENE := preload("res://assets/meshes/characters/Superhero_Male_FullBody.gltf")

const LIBRARIES := {
	"great_sword": "res://assets/animations/great_sword_anim.glb",
	"sword_and_shield": "res://assets/animations/sword_and_shield_anims.glb",
}

# Combat clips used to demonstrate marker sections.
# [library_key, clip_name, windup_end_ratio, attack_end_ratio]
# First entry = the P2 light-attack candidate (grounded swing, 1.03 s).
const PLAY_LIST := [
	["sword_and_shield", "sword and shield attack (4)", 0.32, 0.58],
	["sword_and_shield", "sword and shield attack (2)", 0.32, 0.58],
	["sword_and_shield", "sword and shield slash", 0.30, 0.60],
	["great_sword", "great sword attack", 0.30, 0.60],
	["great_sword", "great sword high spin attack", 0.33, 0.55],
	["great_sword", "great sword jump attack", 0.35, 0.50],
	["great_sword", "great sword slash", 0.28, 0.62],
]

enum Mode { WHOLE, WINDUP, PUNCH, RECOVERY, BACKWARDS }

const MODE_NAMES := ["whole", "windup", "punch", "recovery", "backwards"]

var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _cur: int = 0
var _mode: Mode = Mode.WHOLE
var _label: Label
var _time: float = 0.0


func _ready() -> void:
	_build_lighting()
	_build_floor()
	_build_camera()
	_build_character()
	_build_ui()
	_switch_clip(0)


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-20, 145, 0)
	add_child(fill)


func _build_floor() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	var box := BoxMesh.new()
	box.size = Vector3(12, 0.1, 12)
	mi.mesh = box
	mi.position.y = -0.05
	add_child(mi)


func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(2.2, 1.6, 3.4)
	camera.look_at_from_position(camera.position, Vector3(0, 1.0, 0))
	add_child(camera)


func _build_character() -> void:
	var scene_root: Node3D = MALE_SCENE.instantiate()
	add_child(scene_root)
	_skeleton = scene_root.get_node_or_null("Armature/GeneralSkeleton") as Skeleton3D
	if _skeleton == null:
		push_error("GeneralSkeleton not found under character instance")
		return

	var armature: Node3D = scene_root.get_node("Armature")
	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	_player.root_node = NodePath("..")
	armature.add_child(_player)

	var libs := AnimationLibrary.new()
	for lib_key in LIBRARIES:
		var lib: AnimationLibrary = load(LIBRARIES[lib_key])
		if lib == null:
			push_warning("library missing: ", LIBRARIES[lib_key])
			continue
		for anim_name in lib.get_animation_list():
			var copy: Animation = AnimPrepScript.retarget_copy(lib.get_animation(anim_name), _player, _skeleton)
			libs.add_animation("%s__%s" % [lib_key, anim_name], copy)
	_player.add_animation_library("markers", libs)


func _add_markers(anim_name: String, windup_ratio: float, attack_ratio: float) -> void:
	var anim: Animation = _player.get_animation(anim_name)
	AnimPrepScript.add_combat_markers(anim, windup_ratio, attack_ratio)
	var markers := anim.get_marker_names()
	var names := []
	for m in markers:
		names.append("%s=%.3f" % [m, anim.get_marker_time(m)])
	print("[markers_test] ", anim_name, " markers: ", " ".join(names))


func _play_clip() -> void:
	var entry: Array = PLAY_LIST[_cur]
	var anim_key: String = "markers/" + entry[0] + "__" + entry[1]
	_add_markers(anim_key, entry[2], entry[3])
	_apply_mode(anim_key)


func _apply_mode(anim_key: String) -> void:
	var anim: Animation = _player.get_animation(anim_key)
	match _mode:
		Mode.WHOLE:
			_player.play(anim_key)
			_label.text = "whole (%d:%s) len=%.2f" % [_cur, _short(anim_key), anim.length]
		Mode.WINDUP:
			_player.play_section_with_markers(anim_key, &"windup_start", &"attack_start")
			_label.text = "windup   (%d:%s) %.2f→%.2f" % [
				_cur, _short(anim_key),
				_player.get_section_start_time(), _player.get_section_end_time(),
			]
		Mode.PUNCH:
			_player.play_section_with_markers(anim_key, &"attack_start", &"release_start")
			_label.text = "punch    (%d:%s) %.2f→%.2f" % [
				_cur, _short(anim_key),
				_player.get_section_start_time(), _player.get_section_end_time(),
			]
		Mode.RECOVERY:
			_player.play_section_with_markers(anim_key, &"release_start", &"anim_end")
			_label.text = "recovery (%d:%s) %.2f→%.2f" % [
				_cur, _short(anim_key),
				_player.get_section_start_time(), _player.get_section_end_time(),
			]
		Mode.BACKWARDS:
			_player.play_section_with_markers_backwards(anim_key, &"release_start", &"windup_start")
			_label.text = "backwards(%d:%s)" % [_cur, _short(anim_key)]
	_time = 0.0


func _switch_clip(delta: int) -> void:
	_cur = wrapi(_cur + delta, 0, PLAY_LIST.size())
	_play_clip()


func _switch_mode(delta: int) -> void:
	_mode = wrapi(int(_mode) + delta, 0, Mode.size())
	_apply_mode(_anim_key())


func _anim_key() -> String:
	var entry: Array = PLAY_LIST[_cur]
	return "markers/" + entry[0] + "__" + entry[1]


func _section_duration() -> float:
	var anim: Animation = _player.get_animation(_anim_key())
	match _mode:
		Mode.WHOLE:
			return anim.length
		Mode.WINDUP:
			return anim.get_marker_time(&"attack_start") - anim.get_marker_time(&"windup_start")
		Mode.PUNCH:
			return anim.get_marker_time(&"release_start") - anim.get_marker_time(&"attack_start")
		Mode.RECOVERY:
			return anim.get_marker_time(&"anim_end") - anim.get_marker_time(&"release_start")
		Mode.BACKWARDS:
			return anim.get_marker_time(&"release_start") - anim.get_marker_time(&"windup_start")
	return anim.length


func _short(anim_key: String) -> String:
	var parts := anim_key.split("__")
	return parts[1] if parts.size() > 1 else anim_key


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)
	_label = Label.new()
	_label.name = "StatusLabel"
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override("font_size", 14)
	canvas.add_child(_label)


func _process(delta: float) -> void:
	_time += delta
	if not _player.is_playing() and _time < _section_duration():
		return
	if _time >= _section_duration():
		if _mode == Mode.BACKWARDS or _mode == Mode.WHOLE:
			_switch_clip(1)
		else:
			_switch_mode(1)
	if _player.is_playing():
		_label.text += "  t=%.2f" % _player.current_animation_position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_RIGHT:
				_switch_clip(1)
			KEY_LEFT:
				_switch_clip(-1)
			KEY_UP:
				_switch_mode(1)
			KEY_DOWN:
				_switch_mode(-1)
			KEY_SPACE:
				_player.stop()
				_label.text = "stopped"
