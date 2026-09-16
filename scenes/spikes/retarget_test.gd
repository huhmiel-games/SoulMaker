extends Node3D

const MALE_SCENE := preload("res://assets/meshes/characters/Superhero_Male_FullBody.gltf")

const ANIM_LIBRARIES := {
	"adventure": "res://assets/animations/adventure.glb",
	"aerial": "res://assets/animations/aerial.glb",
	"female": "res://assets/animations/female.glb",
	"great_sword": "res://assets/animations/great_sword_anim.glb",
	"idle_torch": "res://assets/animations/idle_torch.glb",
	"sword_and_shield": "res://assets/animations/sword_and_shield_anims.glb",
	"various": "res://assets/animations/various.glb",
	"various2": "res://assets/animations/various2.glb",
}

const PLAYLIST := [
	"sword_and_shield::sword and shield idle",
	"sword_and_shield::sword and shield walk",
	"sword_and_shield::sword and shield run",
	"sword_and_shield::sword and shield attack",
	"sword_and_shield::sword and shield slash",
	"sword_and_shield::sword and shield block idle",
	"great_sword::great sword idle",
	"great_sword::great sword attack",
	"great_sword::great sword high spin attack",
	"various::Falling",
	"various::Heavy Weapon Swing",
	"idle_torch::Standing Torch Idle 01 (1)",
	"female::idle",
	"female::walking",
]

var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _cur: int = -1
var _time: float = 0.0
var _duration: float = 3.0
var _label: Label
var _sun: DirectionalLight3D
var _camera: Camera3D


func _ready() -> void:
	_build_lighting()
	_build_floor()
	_build_camera()
	_build_character()
	_build_ui()
	_next()


func _build_lighting() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(_sun)

	var ambient := DirectionalLight3D.new()
	ambient.name = "Fill"
	ambient.light_energy = 0.35
	ambient.rotation_degrees = Vector3(-20, 145, 0)
	add_child(ambient)


func _build_floor() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	var box := BoxMesh.new()
	box.size = Vector3(12, 0.1, 12)
	mi.mesh = box
	mi.position.y = -0.05
	add_child(mi)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.position = Vector3(2.2, 1.6, 3.4)
	_camera.look_at_from_position(_camera.position, Vector3(0, 1.0, 0))
	add_child(_camera)


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
	var ok: int = 0
	var bad: int = 0
	for lib_name in ANIM_LIBRARIES:
		var lib: AnimationLibrary = load(ANIM_LIBRARIES[lib_name])
		if lib == null:
			push_warning("library missing: ", ANIM_LIBRARIES[lib_name])
			continue
		for anim_name in lib.get_animation_list():
			var copy: Animation = _retarget_animation(lib.get_animation(anim_name))
			if copy == null:
				bad += 1
				continue
			libs.add_animation("%s__%s" % [lib_name, anim_name], copy)
			ok += 1
	_player.add_animation_library("retarget", libs)
	print("[retarget_test] loaded ", ok, " animations, ", bad, " skipped")
	print("[retarget_test] skeleton bone[1] = ", _skeleton.get_bone_name(1),
		", bone[2] = ", _skeleton.get_bone_name(2))


func _retarget_animation(source: Animation) -> Animation:
	var copy: Animation = source.duplicate()
	var skeleton_path: String = _player.get_parent().get_path_to(_skeleton)
	for i in copy.get_track_count() - 1:
		var path: NodePath = copy.track_get_path(i)
		var sub: String = String(path.get_subname(0)) if path.get_subname_count() > 0 else ""
		if sub.is_empty():
			continue
		copy.track_set_path(i, NodePath(skeleton_path + ":" + sub))
	return copy


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)
	_label = Label.new()
	_label.name = "StatusLabel"
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(_label)


func _process(delta: float) -> void:
	_time += delta
	if _duration > 0.0 and _time >= _duration:
		_next()


func _next() -> void:
	_cur = (_cur + 1) % PLAYLIST.size()
	_pick()


func _prev() -> void:
	_cur = (_cur - 1 + PLAYLIST.size()) % PLAYLIST.size()
	_pick()


func _pick() -> void:
	var anim_key: String = PLAYLIST[_cur].replace("::", "__")
	var anim_name: String = "retarget/" + anim_key
	if _player.has_animation(anim_name):
		_player.play(anim_name)
		var source: Animation = _player.get_animation(anim_name)
		_duration = source.length
		print("[retarget_test] playing: ", anim_name, " (", "%.2f" % _duration,
			"s, ", source.get_track_count(), " tracks)")
		_label.text = "PLAYLIST @" + str(_cur) + " — " + PLAYLIST[_cur]
	else:
		push_warning("animation not found: ", anim_name)
		_duration = 1.0
	_time = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_RIGHT:
				_next()
			KEY_SPACE:
				_cur = -1
				_next()
