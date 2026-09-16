extends SceneTree

const TEST_SCENE := "res://scenes/spikes/retarget_test.tscn"

var _scene: Node
var _frame: int = 0
var _results: Array[String] = []
var _checked: int = 0
var _ok: int = 0


func _initialize() -> void:
	_scene = load(TEST_SCENE).instantiate()
	root.add_child.call_deferred(_scene)


func _process_frame() -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _scene != null:
		_check_animations()
		return true
	return false


func _check_animations() -> void:
	var player: AnimationPlayer = _scene.get_node("Superhero_Male_FullBody/Armature/AnimationPlayer")
	var playable: Array[String] = []
	for anim in player.get_animation_list():
		playable.append(anim)
	playable.sort()
	for anim in playable:
		_checked += 1
		if _probe_animation(player, anim):
			_ok += 1
			_results.append("OK   %s" % anim)
		else:
			_results.append("FAIL %s" % anim)
	print_results()
	quit()


func _probe_animation(player: AnimationPlayer, anim_name: String) -> bool:
	player.play(anim_name)
	player.advance(0.5)
	var skel := _scene.get_node("Superhero_Male_FullBody/Armature/GeneralSkeleton") as Skeleton3D
	var moved := false
	for i in skel.get_bone_count():
		if not skel.get_bone_pose(i).is_equal_approx(Transform3D.IDENTITY):
			moved = true
			break
	return moved


func print_results() -> void:
	print()
	print("=== retarget validation: ", _checked, " animations ===")
	for line in _results:
		print(line)
	print("--- result: ", _ok, "/", _checked, " OK ---")