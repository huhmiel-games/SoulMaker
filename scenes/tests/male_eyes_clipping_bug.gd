@tool
extends Node3D
## Repro male eye clipping (09/10): nude + separate eyes, BOTH skeletons play
## the same idle take in sync (editor pattern: remapped take per skeleton,
## manual-advance players). Tool-built players stay owner-less: invisible in
## the Scene dock AND never saved into the .tscn (no baked-take bloat). Drive
## them from the root Inspector instead: `playing` toggles autoplay in the
## editor viewport, `scrub` seeks both to the same take fraction (frame-exact
## clipping inspection). Headless proof: run --headless, both bones move.

const ANIM_PACK := "res://scenes/anim_lab/player_pack.res"
const IDLE_TAKE := "rig/ual1__Idle"
const FALLBACK_TAKE := "rig/ual1__Walk"

@export var playing := true:
	set(v):
		playing = v
		_sync()
@export_range(0.0, 1.0, 0.001) var scrub := 0.0:
	set(v):
		scrub = v
		_sync()

var _players: Array[AnimationPlayer] = []
var _frames := 0
var _heads: Array[Skeleton3D] = []
var _head0: Array[Vector3] = []


func _ready() -> void:
	# Rebuild-safe (tool reloads re-run _ready): drop previous players first.
	# No owner set -> ephemeral, never saved into the .tscn.
	for inst_path in ["Superhero_Male_FullBody", "Male_Eyes2"]:
		var old := get_node_or_null("IdlePlayer_" + inst_path)
		if old != null:
			remove_child(old)
			old.queue_free()
	_players.clear()
	var pack := load(ANIM_PACK) as AnimationLibrary
	if pack == null:
		push_error("[EyeClip] cannot load %s" % ANIM_PACK)
		return
	var bare := IDLE_TAKE.trim_prefix("rig/")
	if not pack.has_animation(bare):
		bare = FALLBACK_TAKE.trim_prefix("rig/")
		print("[EyeClip] idle missing, fallback %s" % bare)
	for inst_path in ["Superhero_Male_FullBody", "Male_Eyes2"]:
		var inst := get_node_or_null(inst_path)
		if inst == null:
			push_error("[EyeClip] missing %s" % inst_path)
			continue
		var sks := inst.find_children("*", "Skeleton3D", true, false)
		if sks.is_empty():
			push_error("[EyeClip] no skeleton under %s" % inst_path)
			continue
		var sk := sks[0] as Skeleton3D
		var player := AnimationPlayer.new()
		player.name = "IdlePlayer_" + inst_path
		add_child(player)
		player.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
		var libs := AnimationLibrary.new()
		libs.add_animation(bare, _remap(pack.get_animation(bare), player, sk))
		player.add_animation_library("rig", libs)
		player.play("rig/" + bare)
		_players.append(player)
		_heads.append(sk)
		_head0.append(sk.get_bone_global_pose(sk.find_bone(&"Head")).origin)
		print("[EyeClip] playing rig/%s on %s (%d bones)" % [bare, sk.get_path(), sk.get_bone_count()])
	_sync()


## Applies the Inspector state to both players (play/stop + seek to the same
## take fraction). Safe before _ready (empty player list = no-op).
func _sync() -> void:
	if _players.is_empty():
		return
	var length := 1.0
	if _players[0].has_animation(_players[0].current_animation):
		length = maxf(_players[0].current_animation_length, 0.001)
	for p in _players:
		if playing:
			if not p.is_playing():
				p.play()
		else:
			p.pause()
		p.seek(scrub * length, true)


## Copy of a pack take with bone tracks rebound to the given skeleton
## (same call as CharacterEditor._animtest_remap). Paths are root-relative:
## AnimationPlayer resolves tracks against root_node (".." = this root), NOT
## against the player itself — a player-relative base ("../...") resolves
## above the root and every track fails (silent clock, warning spam).
func _remap(anim: Animation, _player: AnimationPlayer, master: Skeleton3D) -> Animation:
	var out := anim.duplicate()
	out.set_loop_mode(Animation.LOOP_LINEAR)
	var base := str(get_path_to(master))
	for i in range(anim.get_track_count() - 1, -1, -1):
		var t := anim.track_get_type(i)
		var p: NodePath = anim.track_get_path(i)
		if (t == Animation.TYPE_POSITION_3D or t == Animation.TYPE_ROTATION_3D or t == Animation.TYPE_SCALE_3D) and p.get_subname_count() > 0:
			var dst := str(p.get_subname(0))
			if master.find_bone(dst) == -1:
				out.remove_track(i)
				continue
			out.track_set_path(i, NodePath(base + ":" + dst))
		else:
			out.remove_track(i)
	return out


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		if playing: # autoplay in the editor viewport (the dock can't see
			for p in _players: # the owner-less players, the Inspector drives)
				if not p.is_playing():
					p.play()
				p.advance(delta)
		_frames += 1
		return
	for p in _players:
		if p.is_playing():
			p.advance(delta)
	_frames += 1
	if _frames == 60:
		for p in _players:
			print("[EyeClip] f60 %s playing=%s pos=%.2f" % [p.name, str(p.is_playing()), p.current_animation_position])
		for h in _heads.size():
			var sk := _heads[h]
			var moved := sk.get_bone_global_pose(sk.find_bone(&"Head")).origin.distance_to(_head0[h])
			print("[EyeClip] f60 Head moved %.4fm on %s" % [moved, sk.get_path()])
