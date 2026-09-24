extends SceneTree

const TEST_SCENE := "res://scenes/spikes/markers_test.tscn"

var _scene: Node
var _frame: int = 0
var _fail: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_scene = load(TEST_SCENE).instantiate()
	root.add_child.call_deferred(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _scene != null:
		_run()
		return true
	return false


func _probe(player: AnimationPlayer, anim: String) -> void:
	var animation: Animation = player.get_animation(anim)
	for marker in [&"windup_start", &"attack_start", &"release_start", &"anim_end"]:
		_checks += 1
		if not animation.has_marker(marker):
			_fail.append("missing marker %s in %s" % [marker, anim])
			continue
		var t: float = animation.get_marker_time(marker)
		if t < 0.0 or t > animation.length + 0.001:
			_fail.append("marker %s=%f out of range in %s" % [marker, t, anim])

	var sections := [
		[&"windup_start", &"attack_start"],
		[&"attack_start", &"release_start"],
		[&"release_start", &"anim_end"],
	]
	for sec in sections:
		player.play_section_with_markers(anim, sec[0], sec[1])
		var start: float = player.get_section_start_time()
		var end: float = player.get_section_end_time()
		if end <= start:
			_fail.append("bad section %f->%f for %s" % [start, end, anim])
		player.advance((end - start) / 2.0)
		var pos: float = player.current_animation_position
		if pos < start - 0.01 or pos > end + 0.01:
			_fail.append("pos %.2f outside section %.2f->%.2f for %s" % [pos, start, end, anim])
		_checks += 2

	player.play_section_with_markers_backwards(anim, &"windup_start", &"release_start")
	player.advance(player.speed_scale * 0.1)
	var bpos: float = player.current_animation_position
	var bstart: float = player.get_section_start_time()
	var bend: float = player.get_section_end_time()
	if bpos < bstart - 0.01 or bpos > bend + 0.01:
		_fail.append("backwards pos %.2f outside section %.2f->%.2f for %s" % [bpos, bstart, bend, anim])
	_checks += 1


func _run() -> void:
	_scene.set_process(false)
	var player: AnimationPlayer = _scene.get_node("Superhero_Male_FullBody/Armature/AnimationPlayer")
	var total: int = _scene.PLAY_LIST.size()
	for i in total:
		_scene._cur = i
		_scene._play_clip()
		var anim: String = _scene._anim_key()
		_probe(player, anim)
	print("=== markers validation ===")
	if _fail.is_empty():
		print("RESULT: ALL OK (%d checks) across %d clips" % [_checks, total])
	else:
		for line in _fail:
			print("FAIL: ", line)
		print("RESULT: ", _fail.size(), " FAILURES / ", _checks, " checks")
	quit()