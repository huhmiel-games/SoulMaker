class_name CharacterEditor
extends Node3D

## Character editor v0 (base): gender + per-slot outfit picker with a live
## mannequin preview. Session-only (defaults every boot; GameState
## persistence comes later when the game reads the config).
## Thin editor shell over CharacterAvatar (runtime): menus, dresser, camera,
## preview/probe animation, self-tests. Build state (gender/outfits/hair/
## colors/physics) lives in the avatar so the game can drive the same node.
## Run: Godot --path . scenes/ingame_editors/character_editor.tscn

var _avatar: CharacterAvatar = null
## Idle preview (06/10): the mannequin plays this instead of the T-pose.
## Single-take remap (cheap per rebuild) on the fused master skeleton.
const IDLE_TAKE := "rig/ual1__Idle"
## Anim-fit probe pack (take names inside are already "lib__clip", e.g.
## "ual1__Walk"; the "rig/" prefix is the player library name, same as game).
const ANIM_PACK := "res://scenes/anim_lab/player_pack.res"
const ANIM_DEFAULT_TAKE := "rig/ual1__Walk"

## Editor trigger for the anim-fit probe (inspector tick + F5): CLI flags do
## not survive an editor launch, so the probe also starts on this export.
## Local-only: do NOT commit the scene with this ticked.
@export var animtest := false
## Runtime fit switch (merge-avatar phase 1): when ON (default, male +
## female), slots load the RAW vendor part and FitKit conforms it in memory.
## The old fitted/ bake routing is removed — raw + FitKit is the only path.
@export var use_fitkit := true
## Stage isolation flag (inspector tick + F5, or CLI override): --nosuppress
## (intact nude under fitted cloth). Eye-recipe matrix, see WORKLOG.
## Local-only: do NOT commit the scene with this ticked.
@export var no_suppress := false
## Pass-1 volume debug (inspector tick or --showvol at boot, N at runtime):
## draws the garment suppression volumes (limb cylinders + torso/boot boxes,
## one color per chain, semi-transparent) over the mannequin. Read-only
## overlay, zero behavior change when unticked. Local-only: do NOT commit
## the scene with this ticked.
@export var show_volumes := false
## X-ray debug (TEMP, N key / L3 pad): 0 fused, 1 skin only, 2 volumes.
var _xray := 0
const XRAY_NAMES := ["Fused", "Skin", "Volumes", "Wire"]
var _wire := false # wireframe requested (dummy viewport drops debug_draw headless)
var _dresser: ColorEditor = null
var _menu: CharacterMenu = null
var _anim_active := false
var _anim_player: AnimationPlayer = null
var _anim_paused := false # still preview on the Face submenu (sculpt judging)
var _anim_master: Skeleton3D = null
var _anim_targets: Array[Skeleton3D] = []
var _anim_pairs: Array = [] # per target: Array of [master_idx, target_idx]
var _anim_frame := 0
var _idle_only := false # idle preview mode (vs full animtest probe)
var _color_slot := &"" # slot currently open in the dresser


func _ready() -> void:
	_dresser = get_node_or_null("MenuLayer/Dresser") as ColorEditor
	_menu = get_node_or_null("MenuLayer/Menu") as CharacterMenu
	if _dresser == null or _menu == null:
		push_error("[Character] missing Dresser or Menu node")
		return
	if "--fitprobe" in OS.get_cmdline_user_args() or "--fitprobe" in OS.get_cmdline_args():
		use_fitkit = true
	# A/B measurement only: skip FitKit conform, suppress raw vendor parts.
	if "--nofit" in OS.get_cmdline_user_args() or "--nofit" in OS.get_cmdline_args():
		use_fitkit = false
	if "--nosuppress" in OS.get_cmdline_user_args() or "--nosuppress" in OS.get_cmdline_args():
		no_suppress = true
	if "--showvol" in OS.get_cmdline_user_args() or "--showvol" in OS.get_cmdline_args():
		show_volumes = true
	if show_volumes:
		_xray = 2
	_avatar = CharacterAvatar.new()
	_avatar.name = "Avatar"
	var w := _world()
	if w != null:
		w.add_child(_avatar)
	else:
		add_child(_avatar)
	_fit_world_viewport()
	get_tree().root.size_changed.connect(_fit_world_viewport)
	_avatar.use_fitkit = use_fitkit
	_avatar.no_suppress = no_suppress
	_avatar.setup(_dresser, get_node_or_null("MenuLayer/HUD"))
	_avatar.rebuilt.connect(_on_avatar_rebuilt)
	_dresser.closed.connect(_on_color_closed)
	_avatar.full_rebuild()
	print("[Character] ready (gender %s, all slots %s)" % [_avatar.gender_display(), CharacterAvatar.OUTFITS[0]])
	_menu.enter_root(self)
	if "--chartest" in OS.get_cmdline_user_args() or "--chartest" in OS.get_cmdline_args():
		_run_headless_test()
	if "--capturetest" in OS.get_cmdline_user_args() or "--capturetest" in OS.get_cmdline_args():
		_run_capture_test()
	if "--browprobe" in OS.get_cmdline_user_args() or "--browprobe" in OS.get_cmdline_args():
		_run_brow_probe()
	if "--facesweep" in OS.get_cmdline_user_args() or "--facesweep" in OS.get_cmdline_args():
		_run_face_sweep()
	if _animtest_wanted():
		_animtest_setup()
	else:
		_idle_setup()


## Preview world (10/10): the mannequin + orbit camera live inside a
## SubViewport covering the window right of the 360px menu, so the camera
## centers on the visible area by construction (no h_offset hacks fighting
## the orbit/face math at other aspect ratios). Same pattern as map_editor.
const WORLD_MENU_WIDTH := 360.0


## The SubViewport everything 3D lives in (avatar, orbit pivot, sun, ground,
## volume overlay). Paths under it move together; use this, not literals.
func _world() -> SubViewport:
	return get_node_or_null("ViewportContainer/WorldViewport") as SubViewport


## Tracks the visible area 1:1 (no stretch upscale blur, no aspect skew):
## right-of-menu window pixels. Re-run on every window resize; headless the
## root size is constant so one call in _ready suffices.
func _fit_world_viewport() -> void:
	var w := _world()
	if w == null:
		return
	var win := get_tree().root.size
	w.size = Vector2i(maxi(win.x - int(WORLD_MENU_WIDTH), 320), maxi(win.y, 240))


## glTF part lookup (avatar-owned table). Delegated: chartest calls it here.
func part_file(gender: String, outfit: String, slot: StringName) -> String:
	return _avatar.part_file(gender, outfit, slot)


## Rebuild follow-up (avatar signal): the preview animation attaches to the
## new master (face re-anchor + colors/physics already handled avatar-side).
func _on_avatar_rebuilt() -> void:
	if face_active():
		face_reanchor() # the new head moved (height/gender); keep user zoom
	_apply_xray() # new MIs default visible; restore the xray state
	_restart_preview_anim()


func _restart_preview_anim() -> void:
	if _animtest_wanted():
		_animtest_setup()
	else:
		_idle_setup()


## Colors menu: fused materials whose source belongs to the slot (Skin =
## skin src list, slots = cloth src list). Empty = no part, toast only.
func open_color(slot: StringName) -> void:
	var mats := _slot_mats(slot)
	if mats.is_empty():
		_menu._notice("no part for %s" % String(slot))
		return
	_color_slot = slot
	_dresser.edit_mats(String(slot), mats, slot in CharacterAvatar.ALBEDO_SLOTS)


func is_color_open() -> bool:
	return _dresser != null and _dresser.visible


func _on_color_closed(applied: bool) -> void:
	if applied and _color_slot != &"":
		_avatar.store_color(_color_slot, _dresser.current_params())
	_color_slot = &""


## Idle preview: same manual-advance player as the probe, but the opening
## pose HOLDS (live request 10/10: rest pose reads T-pose, the idle take
## reads natural — frozen, no sway). _process only advances the probe.
func _idle_setup() -> void:
	_animtest_teardown()
	_anim_frame = 0
	var master := _avatar_skeleton()
	if master == null:
		master = _slot_skeleton(&"Nude")
	if master == null:
		push_error("[Idle] no avatar/nude skeleton")
		return
	var pack := load(ANIM_PACK) as AnimationLibrary
	if pack == null:
		push_error("[Idle] cannot load %s" % ANIM_PACK)
		return
	_anim_player = AnimationPlayer.new()
	_anim_player.name = "IdlePlayer"
	add_child(_anim_player)
	_anim_player.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
	var libs := AnimationLibrary.new()
	# Library-level names are bare ("ual1__Idle"); the "rig/" prefix only
	# exists at player level once the library is mounted.
	var bare := IDLE_TAKE.trim_prefix("rig/")
	if not pack.has_animation(bare):
		bare = ANIM_DEFAULT_TAKE.trim_prefix("rig/")
		print("[Idle] %s missing, fallback %s" % [IDLE_TAKE, bare])
	libs.add_animation(bare, _animtest_remap(pack.get_animation(bare), master))
	_anim_player.add_animation_library("rig", libs)
	_anim_player.play(IDLE_TAKE, -1, 0.5)
	_anim_player.seek(0.0, true) # opening pose; _process never advances it
	print("[Idle] %s held at opening pose on %s" % [IDLE_TAKE, master.get_path()])
	_anim_master = master
	_anim_active = true
	_idle_only = true


## Volume overlay colors (one per chain, alpha applied at draw time).
const VOL_COLORS := {
	"ArmL": Color(1.0, 0.25, 0.25),
	"ArmR": Color(1.0, 0.6, 0.15),
	"LegL": Color(0.3, 0.5, 1.0),
	"LegR": Color(0.3, 0.9, 0.9),
	"FootL": Color(1.0, 0.9, 0.3),
	"FootR": Color(1.0, 0.45, 0.9),
	"Torso": Color(0.35, 1.0, 0.4),
}
const VOL_ALPHA := 0.25


## Frees the pass-1 volume overlay (rebuilt on demand by _draw_volumes).
func _clear_volumes() -> void:
	var w := _world()
	var old := (w.get_node_or_null("Volumes") if w != null else null)
	if old != null:
		w.remove_child(old)
		old.queue_free()


## Draws the pass-1 suppression volumes returned by FitKit.suppress_covered:
## limb cylinders (axis segment + VOL_REACH both ends, rmax + VOL_REACH) and
## the torso/boot boxes (+ reach), one semi-transparent color per chain. Same
## math as the cut — what you see is what gets deleted. Read-only overlay (no
## scene state to commit).
func _draw_volumes(vols: Dictionary, cdata: Dictionary) -> void:
	_clear_volumes()
	if vols.is_empty():
		return
	var root := Node3D.new()
	root.name = "Volumes"
	var w := _world()
	if w != null:
		w.add_child(root)
	else:
		add_child(root)
	for chain in vols:
		var v: Dictionary = vols[chain]
		var col: Color = VOL_COLORS.get(String(chain), Color(1.0, 1.0, 1.0))
		col.a = VOL_ALPHA
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = col
		var mi := MeshInstance3D.new()
		mi.name = "Vol_%s" % String(chain)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not bool(v["limb"]):
			var bmin: Vector3 = (v["bmin"] as Vector3) - Vector3.ONE * FitKit.VOL_REACH
			var bmax: Vector3 = (v["bmax"] as Vector3) + Vector3.ONE * FitKit.VOL_REACH
			var box := BoxMesh.new()
			box.size = bmax - bmin
			mi.mesh = box
			mi.position = (bmin + bmax) * 0.5
		else:
			if not cdata.has(chain):
				continue
			var start: Vector3 = (cdata[chain] as Dictionary)["start"]
			var dir: Vector3 = ((cdata[chain] as Dictionary)["dir"] as Vector3).normalized()
			var a := start + dir * (float(v["tmin"]) - FitKit.VOL_REACH)
			var b := start + dir * (float(v["tmax"]) + FitKit.VOL_REACH)
			var radius := float(v["rmax"]) + FitKit.VOL_REACH
			var cyl := CylinderMesh.new()
			cyl.top_radius = radius
			cyl.bottom_radius = radius
			cyl.height = a.distance_to(b)
			mi.mesh = cyl
			mi.position = (a + b) * 0.5
			if dir.dot(Vector3.UP) < -0.999:
				mi.rotation = Vector3(PI, 0.0, 0.0)
			elif dir.dot(Vector3.UP) < 0.999:
				mi.rotation = (Quaternion(Vector3.UP, dir)).get_euler()
		mi.material_override = mat
		root.add_child(mi)
	print("[Merge] volumes drawn: %d" % root.get_child_count())


## Fused-avatar accessors (delegated, see the delegates block above).


## Fused-avatar accessors (delegated, see the delegates block above).


## Nude base body (delegated, see the delegates block above).


## Nude base body (delegated, see the delegates block above).


## Menu verbs (delegated, see the delegates block above).


## Hair (delegated, see the delegates block above).


## Eyebrows (delegated, see the delegates block above).


## Face close-up (Hair/Eyebrows submenus): the orbit pivot + arm are saved on
## FIRST entry, the pivot moves to the face (Head bone + FACE_AIM_UP: the bone
## origin sits at the skull base, aiming there frames the neck) and the arm
## shortens. Navigating inside Face (hub <-> subs) never touches the view
## (09/10: re-push reset the user's zoom on every submenu hop); leaving
## restores both. Yaw/pitch untouched — the user keeps orbiting the face.
## Rebuilds re-aim the pivot via face_reanchor (height/gender move the head)
## but keep the user's arm (zoom).
const FACE_ARM := 0.9
const FACE_AIM_UP := 0.10 # Head origin -> mid-face (nose/eyes zone)
var _face_saved := {} # empty, or {pos: Vector3, arm: float}


func on_menu_level(level: int) -> void:
	if level == CharacterMenu.LEVEL_HAIR or level == CharacterMenu.LEVEL_EYEBROWS or level == CharacterMenu.LEVEL_EYES or level == CharacterMenu.LEVEL_BEARD or CharacterMenu.is_face_level(level):
		face_push()
	else:
		face_pop()
	# Sculpt judging needs a still face: pause the preview advance on the Face
	# hub and subs (idle preview only — the animtest probe keeps running), snap to
	# take start on entry, resume on leave. The flag survives rebuilds
	# (_restart_preview_anim only replays; _anim_paused still gates advance).
	var want_pause := CharacterMenu.is_face_level(level) and _idle_only
	if want_pause and not _anim_paused and _anim_player != null:
		_anim_player.seek(0.0, true)
	_anim_paused = want_pause


func face_active() -> bool:
	return not _face_saved.is_empty()


func _head_world() -> Vector3:
	return _avatar.head_world()


func _face_pivot() -> Node3D:
	var w := _world()
	if w == null:
		return null
	return w.get_node_or_null("CamPivot") as Node3D


func face_push() -> void:
	var pivot := _face_pivot()
	if pivot == null:
		return
	var arm := pivot.get_node_or_null("SpringArm3D") as SpringArm3D
	if arm == null:
		return
	if not _face_saved.is_empty():
		return # already inside Face: never move the user's view
	_face_saved = {"pos": pivot.position, "arm": arm.spring_length}
	pivot.position = _head_world() + Vector3.UP * FACE_AIM_UP
	arm.spring_length = FACE_ARM


## Re-aims the pivot at the moved head after a rebuild while Face stays
## active. Keeps the user's arm (zoom); no-op outside Face.
func face_reanchor() -> void:
	if _face_saved.is_empty():
		return
	var pivot := _face_pivot()
	if pivot == null:
		return
	pivot.position = _head_world() + Vector3.UP * FACE_AIM_UP


func face_pop() -> void:
	if _face_saved.is_empty():
		return
	var pivot := _face_pivot()
	var arm := (pivot.get_node_or_null("SpringArm3D") as SpringArm3D) if pivot != null else null
	if pivot != null:
		pivot.position = _face_saved["pos"]
	if arm != null:
		arm.spring_length = float(_face_saved["arm"])
	_face_saved.clear()


## Menu verbs (GenericMenu value rows: get = display, adjust(L/R) = cycle,
## reset(A/E) = default). Thin delegates: state + build live in the avatar.
func gender_display() -> String:
	return _avatar.gender_display()


func adjust_gender(dir: int) -> void:
	_avatar.adjust_gender(dir)
	print("[Character] gender %s" % _avatar.gender_display())


func reset_gender() -> void:
	_avatar.reset_gender()


func slot_display(slot: StringName) -> String:
	return _avatar.slot_display(slot)


func adjust_slot(slot: StringName, dir: int) -> void:
	_avatar.adjust_slot(slot, dir)


func reset_slot(slot: StringName) -> void:
	_avatar.reset_slot(slot)


func hair_display() -> String:
	return _avatar.hair_display()


func hair_file(gender: String, style: StringName) -> String:
	return _avatar.hair_file(gender, style)


func adjust_hair(dir: int) -> void:
	_avatar.adjust_hair(dir)


func reset_hair() -> void:
	_avatar.reset_hair()


func beard_display() -> String:
	return _avatar.beard_display()


func beard_file(gender: String, style: StringName) -> String:
	return _avatar.beard_file(gender, style)


func adjust_beard(dir: int) -> void:
	_avatar.adjust_beard(dir)


func reset_beard() -> void:
	_avatar.reset_beard()


func eyebrow_display() -> String:
	return _avatar.eyebrow_display()


func eyebrow_file(gender: String, style: StringName) -> String:
	return _avatar.eyebrow_file(gender, style)


func adjust_eyebrow(dir: int) -> void:
	_avatar.adjust_eyebrow(dir)


func reset_eyebrow() -> void:
	_avatar.reset_eyebrow()


func eye_display() -> String:
	return _avatar.eye_display()


func eye_file(gender: String, style: StringName) -> String:
	return _avatar.eye_file(gender, style)


func eyelash_file(gender: String, style: StringName) -> String:
	return _avatar.eyelash_file(gender, style)


func adjust_eye(dir: int) -> void:
	_avatar.adjust_eye(dir)


func reset_eye() -> void:
	_avatar.reset_eye()


func eyelash_display() -> String:
	return _avatar.eyelash_display()


func adjust_eyelash(dir: int) -> void:
	_avatar.adjust_eyelash(dir)


func reset_eyelash() -> void:
	_avatar.reset_eyelash()


func face_shape_display(key: StringName) -> String:
	return _avatar.face_display(key)


func adjust_face_shape(key: StringName, dir: int) -> void:
	_avatar.adjust_face(key, dir)


func reset_face_shape(key: StringName) -> void:
	_avatar.reset_face(key)


func face_sculpt_display(key: StringName) -> String:
	return _avatar.sculpt_display(key)


func adjust_face_sculpt(key: StringName, dir: int) -> void:
	_avatar.adjust_sculpt(key, dir)


func reset_face_sculpt(key: StringName) -> void:
	_avatar.reset_sculpt(key)


## TEMP debug (male/female test parity, removed once character_editor lands):
## random full-face draws, sculpt keys only (global Width/Length
## untouched — they drive hair fit, not the face). Absolute sets never stack;
## seed logged for report-back repro.
var _coupling := {} # StringName key -> Array of [StringName other, float factor] (lazy, face_correlations.json)


## Coherence table for the Random draw (frozen once user presets pick seeds:
## any change reshuffles preset faces). Invalid entries dropped, never fatal.
func _face_coupling() -> Dictionary:
	if not _coupling.is_empty():
		return _coupling
	var out := {}
	var path := "res://data/characters/face_correlations.json"
	if FileAccess.file_exists(path):
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if doc is Dictionary:
			for p in (doc as Dictionary).get("pairs", []):
				var d: Dictionary = p
				var a := StringName(String(d.get("a", "")))
				var b := StringName(String(d.get("b", "")))
				var f := clampf(float(d.get("factor", 0.0)), -1.0, 1.0)
				if CharacterAvatar.SCULPT_SPEC.has(a) and CharacterAvatar.SCULPT_SPEC.has(b) and a != b and f != 0.0:
					if not out.has(a):
						out[a] = []
					if not out.has(b):
						out[b] = []
					(out[a] as Array).append([b, f])
					(out[b] as Array).append([a, f])
	_coupling = out
	return out


func _face_max_cm(key: StringName) -> float:
	return float((CharacterAvatar.SCULPT_SPEC.get(key, {}) as Dictionary).get("max_cm", 1.0))


## Sparse-draw window (12/10, user-tuned): a Random face touches COUNT keys,
## COUNT uniform in [RANDOM_MIN_KEYS, RANDOM_MAX_KEYS]. Fewer simultaneous
## rows = fewer freak combos; coupling still whispers between chosen keys.
const RANDOM_MIN_KEYS := 6
const RANDOM_MAX_KEYS := 14


func randomize_face(seed := 0) -> void:
	var rng := RandomNumberGenerator.new()
	if seed == 0:
		rng.randomize()
	else:
		rng.seed = seed
	var use_seed: int = rng.seed
	# Sparse uniform subset: one priority draw per key (fixed order), top
	# count wins. Unchosen keys stay exactly 0 (coupling only flows between
	# chosen keys, never wakes a zero).
	var count := rng.randi_range(RANDOM_MIN_KEYS, RANDOM_MAX_KEYS)
	var prio := {}
	for key in CharacterAvatar.SCULPT_KEYS:
		prio[key] = rng.randf()
	var order := CharacterAvatar.SCULPT_KEYS.duplicate()
	order.sort_custom(func(a: StringName, b: StringName) -> bool: return float(prio[a]) < float(prio[b]))
	var chosen := {}
	for i in mini(count, order.size()):
		chosen[order[order.size() - 1 - i]] = true
	# Independent bases (fixed order: one draw per key), then one
	# non-recursive coupling pass (neighbor bases normalized to this key's
	# range), clamped to the draw range. Deterministic per seed.
	var coup := _face_coupling()
	var base := {}
	for key in CharacterAvatar.SCULPT_KEYS:
		base[key] = rng.randf_range(-_face_max_cm(key) * 0.6, _face_max_cm(key) * 0.6)
	for key in CharacterAvatar.SCULPT_KEYS:
		if not chosen.has(key):
			base[key] = 0.0
	for key in CharacterAvatar.SCULPT_KEYS:
		if not chosen.has(key):
			_avatar.set_sculpt(key, 0.0, false)
			continue
		var maxv := _face_max_cm(key)
		var v: float = base[key]
		for pair in (coup.get(key, []) as Array):
			var ok: StringName = pair[0]
			var omax := maxf(_face_max_cm(ok), 1e-9)
			v += float(pair[1]) * float(base.get(ok, 0.0)) / omax * maxv
		_avatar.set_sculpt(key, clampf(v, -maxv * 0.6, maxv * 0.6), false)
	_avatar.fuse_sculpt()
	print("[Face] random seed %d (%s)" % [use_seed, _avatar.gender_display()])


func reset_face_all() -> void:
	for key in CharacterAvatar.SCULPT_KEYS:
		_avatar.set_sculpt(key, 0.0, false)
	_avatar.fuse_sculpt()


func phys_display(key: StringName) -> String:
	return _avatar.phys_display(key)


func adjust_phys(key: StringName, dir: int) -> void:
	_avatar.adjust_phys(key, dir)


func reset_phys(key: StringName) -> void:
	_avatar.reset_phys(key)


func bproj_display() -> String:
	return _avatar.bproj_display()


func adjust_bproj(dir: int) -> void:
	_avatar.adjust_bproj(dir)


func reset_bproj() -> void:
	_avatar.reset_bproj()


func bangle_display() -> String:
	return _avatar.bangle_display()


func adjust_bangle(dir: int) -> void:
	_avatar.adjust_bangle(dir)


func reset_bangle() -> void:
	_avatar.reset_bangle()


func bcurve_display() -> String:
	return _avatar.bcurve_display()


func adjust_bcurve(dir: int) -> void:
	_avatar.adjust_bcurve(dir)


func reset_bcurve() -> void:
	_avatar.reset_bcurve()


## Avatar data access for the probe/overlay/capture tools + chartest.
func _avatar_skeleton() -> Skeleton3D:
	return _avatar.master_skeleton()


func _avatar_mis() -> Array:
	return _avatar.avatar_mis()


func _avatar_mi() -> MeshInstance3D:
	return _avatar_skin_mi() if _avatar_skin_mi() != null else _avatar_cloth_mi()


func _avatar_skin_mi() -> MeshInstance3D:
	return _avatar.get_node_or_null("Fused/Skin") as MeshInstance3D


func _avatar_cloth_mi() -> MeshInstance3D:
	return _avatar.get_node_or_null("Fused/Cloths") as MeshInstance3D


func _avatar_surf_count() -> int:
	var n := 0
	for mi in _avatar_mis():
		if (mi as MeshInstance3D).mesh != null:
			n += (mi as MeshInstance3D).mesh.get_surface_count()
	return n


func _avatar_src_has(substr: String) -> bool:
	return _avatar._avatar_src_has(substr)


func _avatar_push(src_substr: String) -> float:
	return _avatar._avatar_push(src_substr)


func _avatar_finger_verts() -> int:
	return _avatar._avatar_finger_verts()


## Head-dominated verts of the fused Skin MI (model space): sculpt probe
## (nose tip = max z, symmetry = min/max x mirror).
func _head_dom_verts() -> PackedVector3Array:
	var out := PackedVector3Array()
	var sk := _avatar_skeleton()
	if sk == null:
		return out
	var head := sk.find_bone(&"Head")
	for mi in _avatar_mis():
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.mesh == null or mmi.name != &"Skin":
			continue
		for s in mmi.mesh.get_surface_count():
			var a := mmi.mesh.surface_get_arrays(s)
			if a[Mesh.ARRAY_BONES] == null or a[Mesh.ARRAY_WEIGHTS] == null:
				continue
			var bv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var bi: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var bw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			for i in bv.size():
				var bb := -1
				var ww := 0.0
				for k in 4:
					if bw[i * 4 + k] > ww:
						ww = bw[i * 4 + k]
						bb = bi[i * 4 + k]
				if bb == head:
					out.append(bv[i])
	return out


func _nose_tip_z() -> float:
	var mz := -1e9
	for p in _head_dom_verts():
		mz = maxf(mz, p.z)
	return mz


## Foremost vert in the chin band (model y 1.565-1.605: lower lip above is
## excluded — the outline the eye reads, not the interior mean).
func _chin_front_z() -> float:
	var mz := -1e9
	for p in _head_dom_verts():
		if p.y > 1.565 and p.y < 1.605:
			mz = maxf(mz, p.z)
	return mz


## Core width on a FIXED set (mask members from before-positions): proves the
## outline-adjacent verts follow, not just the interior mean.
func _core_widths(before: PackedVector3Array, after: PackedVector3Array, region: String) -> Array:
	if before.size() != after.size():
		return []
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1:
		return []
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var mn0 := 1e9
	var mx0 := -1e9
	var mn1 := 1e9
	var mx1 := -1e9
	var n := 0
	for i in before.size():
		if _avatar.sculpt_in_region(region, inv * before[i]):
			mn0 = minf(mn0, before[i].x)
			mx0 = maxf(mx0, before[i].x)
			mn1 = minf(mn1, after[i].x)
			mx1 = maxf(mx1, after[i].x)
			n += 1
	if n == 0:
		return []
	return [mx0 - mn0, mx1 - mn1]


## Lowest model-Y of a region's mask members, before/after paired by index
## (membership tested on BEFORE Head-frame positions: moved verts would no
## longer match the pristine mask — same fixed-set rule as _core_widths).
## Returns [floor_before, floor_after].
func _region_floors(before: PackedVector3Array, after: PackedVector3Array, region: String) -> Array:
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1 or before.size() != after.size():
		return []
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var mn0 := 1e9
	var mn1 := 1e9
	for i in before.size():
		if _avatar.sculpt_in_region(region, inv * before[i]):
			mn0 = minf(mn0, before[i].y)
			mn1 = minf(mn1, after[i].y)
	return [mn0, mn1]


## Foremost model-Z of a region's mask members, before/after paired by index
## (same fixed-set rule: membership on BEFORE positions).
## Returns [front_before, front_after].
## Mean model-space position of a mounted face part's verts (Vector3.ZERO
## when nothing mounted): proves sculpt follow moves the part with its socket.
func _face_part_mean(slot: String) -> Vector3:
	var holder := _avatar.get_node_or_null("" + slot) as Node3D
	if holder == null:
		return Vector3.ZERO
	var m := Vector3.ZERO
	var n := 0
	for ch in holder.get_children():
		var mi := ch as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var vv: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in vv:
				m += v
				n += 1
	return m / float(n) if n > 0 else Vector3.ZERO


## Per-side mean X of a mounted face part, split at the part's own mean x
## (symmetric parts: left ball vs right ball). Returns [left, right], ZERO
## pair when nothing mounted — proves side-split follow (EyeSpacing).
func _face_part_side_x(slot: String) -> Array:
	var all := _face_part_verts(slot)
	if all.is_empty():
		return [0.0, 0.0]
	var m := 0.0
	for v in all:
		m += v.x
	m /= float(all.size())
	var l := 0.0
	var ln := 0
	var r := 0.0
	var rn := 0
	for v in all:
		if v.x < m:
			l += v.x
			ln += 1
		else:
			r += v.x
			rn += 1
	if ln == 0 or rn == 0:
		return [0.0, 0.0]
	return [l / float(ln), r / float(rn)]


## Per-side mean radius of a mounted face part about its own side means
## (split at the part's mean x). Returns [left_r, right_r], ZERO pair when
## unmounted — proves rigid parts dilate with the socket (EyeSize).
func _face_part_side_radii(slot: String) -> Array:
	var all := _face_part_verts(slot)
	if all.is_empty():
		return [0.0, 0.0]
	var m := 0.0
	for v in all:
		m += v.x
	m /= float(all.size())
	var cl := Vector3.ZERO
	var cr := Vector3.ZERO
	var ln := 0
	var rn := 0
	for v in all:
		if v.x < m:
			cl += v
			ln += 1
		else:
			cr += v
			rn += 1
	if ln == 0 or rn == 0:
		return [0.0, 0.0]
	cl /= float(ln)
	cr /= float(rn)
	var rl := 0.0
	var rr := 0.0
	for v in all:
		if v.x < m:
			rl += v.distance_to(cl)
		else:
			rr += v.distance_to(cr)
	return [rl / float(ln), rr / float(rn)]


## Mean Y motion of a part's outer verts (past the side mean, away from the
## center), paired before/after. Returns [mean_dy, n] — proves lashes ride
## the lid tilt (EyeAngle).
func _face_part_outer_dy(before: PackedVector3Array, after: PackedVector3Array) -> Array:
	if before.size() != after.size() or before.is_empty():
		return [0.0, 0]
	var m := 0.0
	for v in before:
		m += v.x
	m /= float(before.size())
	var cl := Vector3.ZERO
	var cr := Vector3.ZERO
	var ln := 0
	var rn := 0
	for v in before:
		if v.x < m:
			cl += v
			ln += 1
		else:
			cr += v
			rn += 1
	if ln == 0 or rn == 0:
		return [0.0, 0]
	cl /= float(ln)
	cr /= float(rn)
	var dy := 0.0
	var n := 0
	for i in before.size():
		var q: Vector3 = before[i]
		if (q.x < m and q.x < cl.x) or (q.x >= m and q.x > cr.x):
			dy += after[i].y - before[i].y
			n += 1
	return [dy / float(maxi(n, 1)), n]


## All model-space verts of a mounted face part (empty when none mounted).
func _face_part_verts(slot: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var holder := _avatar.get_node_or_null("" + slot) as Node3D
	if holder == null:
		return out
	for ch in holder.get_children():
		var mi := ch as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			out.append_array(mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	return out


## Min model-space distance between the mounted eyeballs and the Eyelids
## skin (rest sculpt). -1 when unmeasurable (no parts, female).
func _eye_lid_clearance() -> float:
	var holder := _avatar.get_node_or_null("Eyes") as Node3D
	var sk := _avatar_skeleton()
	var smi := _avatar_skin_mi()
	if holder == null or sk == null or smi == null or smi.mesh == null:
		return -1.0
	var bi := sk.find_bone(&"Head")
	if bi == -1:
		return -1.0
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var eye_pts := PackedVector3Array()
	for ch in holder.get_children():
		var mi := ch as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			eye_pts.append_array(mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	if eye_pts.is_empty():
		return -1.0
	var lid_pts := PackedVector3Array()
	for s in smi.mesh.get_surface_count():
		var vv: PackedVector3Array = smi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in vv:
			if _avatar.sculpt_in_region("Eyelids", inv * v):
				lid_pts.append(v)
	if lid_pts.is_empty():
		return -1.0
	var best := 1e9
	var stride := maxi(1, lid_pts.size() / 800)
	var li := 0
	while li < lid_pts.size():
		for e in eye_pts:
			best = minf(best, e.distance_squared_to(lid_pts[li]))
		li += stride
	return sqrt(best)


func _region_fronts(before: PackedVector3Array, after: PackedVector3Array, region: String) -> Array:
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1 or before.size() != after.size():
		return []
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var mz0 := -1e9
	var mz1 := -1e9
	for i in before.size():
		if _avatar.sculpt_in_region(region, inv * before[i]):
			mz0 = maxf(mz0, before[i].z)
			mz1 = maxf(mz1, after[i].z)
	return [mz0, mz1]


## Mean model-Y of a region's front band (members within 2mm of max-Z,
## fixed set on BEFORE positions): proves tip rotation lifts/drops the front.
## Returns [y_before, y_after].
func _region_front_lift(before: PackedVector3Array, after: PackedVector3Array, region: String) -> Array:
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1 or before.size() != after.size():
		return []
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var mz := -1e9
	for p in before:
		if _avatar.sculpt_in_region(region, inv * p):
			mz = maxf(mz, p.z)
	var y0 := 0.0
	var y1 := 0.0
	var n := 0
	for i in before.size():
		if _avatar.sculpt_in_region(region, inv * before[i]) and before[i].z > mz - 0.002:
			y0 += before[i].y
			y1 += after[i].y
			n += 1
	if n == 0:
		return []
	return [y0 / float(n), y1 / float(n)]


## Max model-Z of a region's MID band (|t-0.5|<0.2 along the region Y span,
## fixed set on BEFORE positions): the falloff peak readout (the absolute
## front sits at the pinned ends by design — probing it reads ~0).
## Returns [z_before, z_after].
func _region_midfront(before: PackedVector3Array, after: PackedVector3Array, region: String) -> Array:
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1 or before.size() != after.size():
		return []
	var r: Dictionary = _avatar._sculpt_regions().get(region, {})
	if r.is_empty():
		return []
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var mn: Vector3 = r["mn"]
	var span := float((r["mx"] as Vector3).y) - mn.y
	if span < 1e-9:
		return []
	var mz0 := -1e9
	var mz1 := -1e9
	for i in before.size():
		if _avatar.sculpt_in_region(region, inv * before[i]):
			var t := clampf(((inv * before[i]).y - mn.y) / span, 0.0, 1.0)
			if absf(t - 0.5) < 0.2:
				mz0 = maxf(mz0, before[i].z)
				mz1 = maxf(mz1, after[i].z)
	if mz0 < -1e8:
		return []
	return [mz0, mz1]


## Mean displacement length over a region's mask members (fixed set):
## magnitude readout for rigid motions (rotation moves the ball ~1mm at
## full although the front band only lifts ~0.4mm).
func _region_mean_disp(before: PackedVector3Array, after: PackedVector3Array, region: String) -> float:
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1 or before.size() != after.size():
		return 0.0
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var acc := 0.0
	var n := 0
	for i in before.size():
		if _avatar.sculpt_in_region(region, inv * before[i]):
			acc += (after[i] - before[i]).length()
			n += 1
	return acc / float(maxi(n, 1))


## Pout differential: max-Z advance of the region CENTER band vs the EDGE
## band (fixed set). A pout pushes the middle forward and holds the
## corners; a uniform push advances both equally.
## Returns [center_dz, edge_dz].
func _region_pout(before: PackedVector3Array, after: PackedVector3Array, region: String) -> Array:
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1 or before.size() != after.size():
		return []
	var r: Dictionary = _avatar._sculpt_regions().get(region, {})
	if r.is_empty():
		return []
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var cx := float(r["cx"])
	var hx := maxf(float(r["hx"]), 1e-9)
	var c0 := -1e9
	var c1 := -1e9
	var e0 := -1e9
	var e1 := -1e9
	for i in before.size():
		if _avatar.sculpt_in_region(region, inv * before[i]):
			if absf((inv * before[i]).x - cx) < hx * 0.4:
				c0 = maxf(c0, before[i].z)
				c1 = maxf(c1, after[i].z)
			else:
				e0 = maxf(e0, before[i].z)
				e1 = maxf(e1, after[i].z)
	if c0 < -1e8 or e0 < -1e8:
		return []
	return [c1 - c0, e1 - e0]


## Y extent (max-min model-Y) of a region's mask members, before/after
## paired on BEFORE positions: thickness readout (BrowThick grows Y).
## Returns [h_before, h_after].
func _region_yextent(before: PackedVector3Array, after: PackedVector3Array, region: String) -> Array:
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1 or before.size() != after.size():
		return []
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var mn0 := 1e9
	var mx0 := -1e9
	var mn1 := 1e9
	var mx1 := -1e9
	for i in before.size():
		if _avatar.sculpt_in_region(region, inv * before[i]):
			mn0 = minf(mn0, before[i].y)
			mx0 = maxf(mx0, before[i].y)
			mn1 = minf(mn1, after[i].y)
			mx1 = maxf(mx1, after[i].y)
	if mn0 > 1e8:
		return []
	return [mx0 - mn0, mx1 - mn1]


func _head_verts_symmetric() -> bool:
	var verts := _head_dom_verts()
	if verts.size() < 100:
		return false
	return absf(_width_min(verts) + _width_max(verts)) < 0.002


func _width_min(verts: PackedVector3Array) -> float:
	var mn := 1e9
	for p in verts:
		mn = minf(mn, p.x)
	return mn


func _width_max(verts: PackedVector3Array) -> float:
	var mx := -1e9
	for p in verts:
		mx = maxf(mx, p.x)
	return mx


## Sculpt deltas for one row: reset (pristine), capture, adjust, capture,
## reset. Same topology throughout, so before/after pair up per index.
func _sculpt_deltas(key: StringName, steps: int) -> Array:
	reset_face_sculpt(key)
	var before := _head_dom_verts()
	adjust_face_sculpt(key, steps)
	var after := _head_dom_verts()
	reset_face_sculpt(key)
	return [before, after]


## No vert crosses the center plane (mirror rows must scale, never fold).
func _no_center_cross(before: PackedVector3Array, after: PackedVector3Array) -> bool:
	if before.size() != after.size() or before.is_empty():
		return false
	for i in before.size():
		if absf(before[i].x) > 0.0005 and signf(after[i].x) != signf(before[i].x):
			return false
	return true


## Flanks (|ux| in 0.6-1.0 about the region centroid) move more on average
## than the center strip (|ux| < 0.3) — widening must read at the base, not
## the bridge.
func _flank_moves_most(region: String, before: PackedVector3Array, after: PackedVector3Array) -> bool:
	if before.size() != after.size():
		return false
	var st: Dictionary = _avatar.sculpt_region_stats(region)
	if st.is_empty():
		return false
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1:
		return false
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var cx := float(st["cx"])
	var hx := maxf(float(st["hx"]), 1e-9)
	var flank_sum := 0.0
	var flank_n := 0
	var center_sum := 0.0
	var center_n := 0
	for i in before.size():
		var q: Vector3 = inv * before[i]
		if not _avatar.sculpt_in_region(region, q):
			continue
		var ux: float = absf((q.x - cx) / hx)
		var d: float = absf(after[i].x - before[i].x)
		if ux > 0.6:
			flank_sum += d
			flank_n += 1
		elif ux < 0.3:
			center_sum += d
			center_n += 1
	if flank_n == 0 or center_n == 0:
		return false
	return flank_sum / flank_n > center_sum / center_n + 0.0005


## Mouth narrowing check: mean |x| over the BEFORE mask set (fixed verts, so
## the fringe cannot swap in/out). Core verts carry full weight and move mm.
func _gated_narrow(before: PackedVector3Array, after: PackedVector3Array, region: String) -> bool:
	if before.size() != after.size() or before.is_empty():
		return false
	if _avatar.sculpt_region_stats(region).is_empty():
		return false
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1:
		return false
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var sum := 0.0
	var n := 0
	for i in before.size():
		if _avatar.sculpt_in_region(region, inv * before[i]):
			sum += absf(after[i].x) - absf(before[i].x)
			n += 1
	if n == 0:
		return false
	return sum / n < -0.0008


## Chin-region mask verts must drop AND project on Chin+ (dir=+1),
## rise AND recede on Chin- (dir=-1).
func _chin_moved(before: PackedVector3Array, after: PackedVector3Array, dir: float) -> bool:
	if before.size() != after.size():
		return false
	if _avatar.sculpt_region_stats("Chin").is_empty():
		return false
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1:
		return false
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var dy := 0.0
	var dz := 0.0
	var n := 0
	for i in before.size():
		if _avatar.sculpt_in_region("Chin", inv * before[i]):
			dy += after[i].y - before[i].y
			dz += after[i].z - before[i].z
			n += 1
	if n == 0:
		return false
	return dy / n * dir < -0.001 and dz / n * dir > 0.002


## Permanent guard: no visible MeshInstance3D may hide under a Skeleton3D.
## All rendered avatar meshes hang directly under Fused or the Hair/Beard
## holders; anything parented under a skeleton is an unbaked stowaway double
## (masks sculpt recessions while letting protrusions through).
func _no_stowaway_mis() -> bool:
	var stack: Array = [_avatar]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null:
			continue
		for c in n.get_children():
			stack.push_back(c)
		var mmi := n as MeshInstance3D
		if mmi == null or not mmi.visible:
			continue
		var p := mmi.get_parent()
		while p != null and p != _avatar:
			if p is Skeleton3D:
				return false
			p = p.get_parent()
	return true


func _avatar_tex() -> Texture2D:
	return _avatar._avatar_tex()


func _slot_mats(slot: StringName) -> Array:
	return _avatar.slot_mats(slot)


func _reapply_colors() -> void:
	_avatar._reapply_colors()


func _apply_nude() -> void:
	_avatar._apply_nude()


func _rebuild_avatar() -> void:
	_clear_volumes()
	_avatar.rebuild_avatar()


func _slot_skeleton(slot: StringName) -> Skeleton3D:
	return _avatar.slot_skeleton(slot)


func _set_push_all(v: float) -> void:
	_avatar.set_push_all(v)


## Headless self-test (--chartest): table lookups, live swap dressing, gender
## swap keeping per-slot outfits. Run: Godot --headless --path . <scene> -- --chartest
func _run_headless_test() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var fails := 0
	var parity_f := {} # StringName sculpt key -> female mean push (ratioed in §17)
	fails += _expect("peasant head absent", part_file("Male", "Peasant", &"Head").is_empty())
	fails += _expect("peasant acc absent", part_file("Female", "Peasant", &"Accessories").is_empty())
	fails += _expect("ranger hood male", part_file("Male", "Ranger", &"Head").ends_with("Male_Ranger_Head_Hood.gltf"))
	fails += _expect("ranger boots male", part_file("Male", "Ranger", &"Feet").ends_with("Male_Ranger_Feet_Boots.gltf"))
	fails += _expect("ranger pauldron unwired", part_file("Female", "Ranger", &"Accessories").is_empty())
	fails += _expect("male arms bare", part_file("Male", "Peasant", &"Arms").is_empty())
	fails += _expect("male ranger arms bare", part_file("Male", "Ranger", &"Arms").is_empty())
	fails += _expect("female ranger arms", part_file("Female", "Ranger", &"Arms").ends_with("Female_Ranger_Arms.gltf"))
	fails += _expect("female gauntlets", part_file("Female", "RangerG", &"Accessories").ends_with("Female_Ranger_Gauntlets.gltf"))
	fails += _expect("male gauntlets absent", part_file("Male", "RangerG", &"Accessories").is_empty())
	fails += _expect("female body B", part_file("Female", "PeasantB", &"Body").ends_with("Female_Peasant_Body_B.gltf"))
	fails += _expect("male body B absent", part_file("Male", "PeasantB", &"Body").is_empty())
	# Default slots are nude ("--" everywhere until dressed explicitly).
	var nude_ok := true
	for sl in CharacterAvatar.SLOTS:
		if slot_display(sl) != "--":
			nude_ok = false
	fails += _expect("default nude", nude_ok)
	for sl in CharacterAvatar.SLOTS:
		_avatar._outfit[sl] = 0
	_avatar.full_rebuild()
	fails += _expect("dressed peasant", slot_display(&"Body") == "Peasant")
	# Fused avatar: one skeleton + two meshes (Skin / Cloths, X-ray toggle).
	fails += _expect("avatar skeleton", _avatar_skeleton() != null)
	fails += _expect("avatar two meshes", _avatar_skin_mi() != null and _avatar_cloth_mi() != null)
	fails += _expect("avatar surfaces", _avatar_surf_count() > 1)
	fails += _expect("avatar skin inside", _avatar_src_has("SuperHero"))
	fails += _expect("avatar bones 65", _avatar_skeleton() != null and _avatar_skeleton().get_bone_count() == 65)
	adjust_slot(&"Body", 1)
	fails += _expect("body ranger shown", slot_display(&"Body") == "Ranger")
	fails += _expect("body ranger fused", _avatar_mi() != null and _avatar_surf_count() > 1)
	adjust_gender(1)
	fails += _expect("gender female", gender_display() == "Female")
	fails += _expect("body outfit kept", slot_display(&"Body") == "Ranger")
	fails += _expect("female avatar fused", _avatar_mi() != null and _avatar_src_has("SuperHero"))
	fails += _expect("female hands kept", _avatar_finger_verts() > 100)
	# Female face parts ship (Blender exports wired to shared/): mounted
	# holders win over the fused nude fallback (holder child = real mount,
	# mats alone can't tell them apart).
	fails += _expect("female brow file", eyebrow_file("Female", &"Default").ends_with("Female_Eyebrows.gltf"))
	fails += _expect("female eyes file", eye_file("Female", &"Default").ends_with("Female_Eyes.gltf"))
	fails += _expect("female lashes file", eyelash_file("Female", &"Default").ends_with("Female_Eyelashes.gltf"))
	for fslot in ["Eyebrows", "Eyes", "Eyelashes"]:
		var fhold := _avatar.get_node_or_null(fslot)
		fails += _expect("female %s mounted" % fslot.to_lower(), fhold != null and (fhold as Node).get_child_count() > 0)
	# Breast bones (procedural, female only, appended end of vendor order).
	var fsk := _avatar_skeleton()
	fails += _expect("female bones 67", fsk != null and fsk.get_bone_count() == 67)
	var fbl := fsk.find_bone(&"LeftBreast") if fsk != null else -1
	var fbr := fsk.find_bone(&"RightBreast") if fsk != null else -1
	fails += _expect("breast bones appended", fbl == 65 and fbr == 66)
	fails += _expect("breast vendor prefix", fsk.get_bone_name(0) == &"Root" and fsk.get_bone_name(64) == &"ball_leaf_r")
	var fch := fsk.find_bone(&"Chest")
	fails += _expect("breast parent chest", fch != -1 and fsk.get_bone_parent(fbl) == fch and fsk.get_bone_parent(fbr) == fch)
	var frl: Vector3 = fsk.get_bone_rest(fbl).origin
	var frr: Vector3 = fsk.get_bone_rest(fbr).origin
	fails += _expect("breast rests mirrored", frl.x < -0.01 and absf(frl.x + frr.x) < 0.001 and absf(frl.y - frr.y) < 0.001 and absf(frl.z - frr.z) < 0.001)
	# Weights on the fused skin: sums 1.0, apex strongly held, L/R symmetric.
	var bw_dev := 0.0
	var bw_max := 0.0
	var bw_l := 0.0
	var bw_r := 0.0
	var bw_n := 0
	var bsmi := _avatar_skin_mi()
	if bsmi != null and bsmi.mesh != null:
		for bws in (bsmi.mesh as ArrayMesh).get_surface_count():
			var btool := MeshDataTool.new()
			if btool.create_from_surface(bsmi.mesh, bws) != OK:
				continue
			for bwi in btool.get_vertex_count():
				var bbb := btool.get_vertex_bones(bwi)
				var bww := btool.get_vertex_weights(bwi)
				var btot := 0.0
				var bpart := 0.0
				for bwk in bbb.size():
					btot += bww[bwk]
					if bbb[bwk] == fbl or bbb[bwk] == fbr:
						bpart += bww[bwk]
				bw_dev = maxf(bw_dev, absf(btot - 1.0))
				bw_max = maxf(bw_max, bpart)
				if bpart > 0.01:
					bw_n += 1
					if (btool.get_vertex(bwi)).x < 0.0:
						bw_l += bpart
					else:
						bw_r += bpart
	fails += _expect("breast weights sum", bw_n > 50 and bw_dev < 0.001)
	fails += _expect("breast apex weighted", bw_max > 0.5)
	fails += _expect("breast weights symmetric", bw_n > 0 and absf(bw_l - bw_r) / float(bw_n) < 0.05)
	# Cloth follows (Ranger body covers the chest): apex verts weighted there too.
	var bcmi := _avatar_cloth_mi()
	var bcli_max := 0.0
	if bcmi != null and bcmi.mesh != null:
		for bcs in (bcmi.mesh as ArrayMesh).get_surface_count():
			var bctool := MeshDataTool.new()
			if bctool.create_from_surface(bcmi.mesh, bcs) != OK:
				continue
			for bci in bctool.get_vertex_count():
				var bcb := bctool.get_vertex_bones(bci)
				var bcw := bctool.get_vertex_weights(bci)
				for bck in bcb.size():
					if bcb[bck] == fbl or bcb[bck] == fbr:
						bcli_max = maxf(bcli_max, bcw[bck])
	fails += _expect("breast cloth weighted", bcli_max > 0.2)
	# Fusion rigs parts (index-prefix fallback): cloth spans many bones,
	# not Root-bound (12/10: 52/65 unmapped froze UE garments at Root).
	var br_used := {}
	var brcmi := _avatar_cloth_mi()
	if brcmi != null and brcmi.mesh != null:
		for brs in (brcmi.mesh as ArrayMesh).get_surface_count():
			var brb: PackedInt32Array = (brcmi.mesh as ArrayMesh).surface_get_arrays(brs)[Mesh.ARRAY_BONES]
			for brk in brb.size():
				br_used[brb[brk]] = true
	fails += _expect("female cloth rigged", br_used.size() >= 10)
	# Breast rows: Droop rigid offset + Firmness wiggle (scale rows cut 12/10).
	adjust_phys(&"BreastDroop", 10)
	fails += _expect("breastdroop display", phys_display(&"BreastDroop") == "110%")
	fails += _expect("breastdroop offset", fsk.get_bone_pose_position(fbl).is_equal_approx(Vector3(0.0, -0.005, 0.0)) and fsk.get_bone_pose_position(fbr).is_equal_approx(Vector3(0.0, -0.005, 0.0)))
	reset_phys(&"BreastDroop")
	fails += _expect("breastdroop reset", fsk.get_bone_pose_position(fbl).is_equal_approx(Vector3.ZERO))
	adjust_phys(&"BreastFirmness", 10)
	fails += _expect("breastfirmness display", phys_display(&"BreastFirmness") == "110%")
	fails += _expect("breastfirmness mapped", absf(CharacterAvatar.BREAST_WIGGLE.stiffness - 1.0) < 0.001 and absf(CharacterAvatar.BREAST_WIGGLE.damping - 0.95) < 0.001 and absf(CharacterAvatar.BREAST_WIGGLE.max_distance - 0.01563) < 0.002)
	reset_phys(&"BreastFirmness")
	fails += _expect("breastfirmness reset", absf(CharacterAvatar.BREAST_WIGGLE.stiffness - 1.0) < 0.001 and absf(CharacterAvatar.BREAST_WIGGLE.damping - 0.95) < 0.001 and absf(CharacterAvatar.BREAST_WIGGLE.max_distance - 0.01778) < 0.002)
	fails += _expect("firmforce curve", is_equal_approx(CharacterAvatar._firm_eff(1.0), 1.5) and is_equal_approx(CharacterAvatar._firm_force(1.0), 1.0) and absf(CharacterAvatar._firm_force(1.5) - 0.575) < 0.001 and absf(CharacterAvatar._firm_force(2.0) - 0.15) < 0.001)
	# Pivot sits back/down from the painted skin apex (anti-obus, 12/10).
	var lm0 := _avatar._breast_landmarks()
	var pa0: Array = lm0.get("apex", [])
	var gsmi0 := _avatar_skin_mi()
	if pa0.size() == 2 and gsmi0 != null and gsmi0.mesh != null:
		var aw0: Vector3 = (gsmi0 as Node3D).global_transform * (pa0[0] as Vector3)
		var rw0: Vector3 = fsk.get_bone_global_rest(fbl).origin
		fails += _expect("breast pivot backdown", rw0.y < aw0.y and rw0.z < aw0.z)
		fails += _expect("breast pivot near", rw0.distance_to(aw0) < 0.035)
		fails += _expect("breast gravity light", CharacterAvatar.BREAST_WIGGLE.gravity.is_equal_approx(Vector3(0.0, -0.4, 0.0)))
	else:
		fails += _expect("breast pivot backdown", false)
		fails += _expect("breast pivot near", false)
		fails += _expect("breast gravity light", CharacterAvatar.BREAST_WIGGLE.gravity.is_equal_approx(Vector3(0.0, -0.4, 0.0)))
	# Painted landmarks (override injection): rests follow the painted apex,
	# radius comes from the mask (not the blind sphere).
	var auto_apex: Array = _avatar._breast_apex(bsmi.mesh) if bsmi != null and bsmi.mesh != null else []
	if auto_apex.size() == 2:
		var ov := [(auto_apex[0] as Vector3) + Vector3(0.0, 0.0, 0.02), (auto_apex[1] as Vector3) + Vector3(0.0, 0.0, 0.02)]
		var rw0: Vector3 = fsk.get_bone_global_rest(fbl).origin
		var ovfoot := minf((ov[0] as Vector3).y, (ov[1] as Vector3).y) - 0.02
		_avatar._breast_override = {"apex": ov, "radius": 0.06, "foot": ovfoot}
		_avatar.full_rebuild()
		var fsk2 := _avatar_skeleton()
		var fbl2 := fsk2.find_bone(&"LeftBreast") if fsk2 != null else -1
		var fbr2 := fsk2.find_bone(&"RightBreast") if fsk2 != null else -1
		var rw1: Vector3 = fsk2.get_bone_global_rest(fbl2).origin
		var gsmi2 := _avatar_skin_mi()
		var exp1: Vector3 = (gsmi2 as Node3D).global_transform * (ov[0] as Vector3) + Vector3(0.0, -CharacterAvatar.BREAST_PIVOT_DOWN, -CharacterAvatar.BREAST_PIVOT_BACK)
		fails += _expect("breast override apex", rw1.distance_to(exp1) < 0.002)
		var lm2 := _avatar._breast_landmarks()
		fails += _expect("breast override radius", absf(float(lm2.get("radius", 0.0)) - 0.06) < 0.0001 and String(lm2.get("source", "")) == "override")
		fails += _expect("breast override mirrored", fsk2.get_bone_rest(fbl2).origin.x < -0.01 and fsk2.get_bone_rest(fbr2).origin.x > 0.01)
		fails += _expect("breast override gatevals", lm2.has("cny") and lm2.has("cfoot"))
		_avatar._breast_override = {}
		_avatar.full_rebuild()
		# Live paint is the source now (user painted 12/10): JSON read pinned
		# permanently — a wiped paint trips this on purpose.
		var lm3 := _avatar._breast_landmarks()
		fails += _expect("breast painted live", String(lm3.get("source", "")) == "painted")
		fails += _expect("breast painted radius", float(lm3.get("radius", 0.0)) >= 0.04 and float(lm3.get("radius", 0.0)) <= 0.15)
		var pa3: Array = lm3.get("apex", [])
		fails += _expect("breast painted apex", pa3.size() == 2 and (pa3[0] as Vector3).x < -0.01 and absf((pa3[0] as Vector3).x + (pa3[1] as Vector3).x) < 0.01)
	else:
		fails += _expect("breast override apex", false)
		fails += _expect("breast override radius", false)
		fails += _expect("breast override mirrored", false)
		fails += _expect("breast override gatevals", false)
		fails += _expect("breast painted live", false)
		fails += _expect("breast painted radius", false)
		fails += _expect("breast painted apex", false)
	# Vertical gate: no breast weight below the footprint bottom (under-breast
	# skin stays on the torso bones — no balloon underneath).
	var bgate := _avatar._breast_last_gate
	var bviol := 0
	var bwtot := 0
	var gsmi := _avatar_skin_mi()
	var gsk := _avatar_skeleton()
	var gfbl := gsk.find_bone(&"LeftBreast") if gsk != null else -1
	var gfbr := gsk.find_bone(&"RightBreast") if gsk != null else -1
	var gm2c: Transform3D = bgate.get("m2c", Transform3D.IDENTITY)
	var gfoot := float(bgate.get("foot", -1e9))
	if gsmi != null and gsmi.mesh != null and not bgate.is_empty():
		for bgs in (gsmi.mesh as ArrayMesh).get_surface_count():
			var bgtool := MeshDataTool.new()
			if bgtool.create_from_surface(gsmi.mesh, bgs) != OK:
				continue
			for bgi in bgtool.get_vertex_count():
				var bgb := bgtool.get_vertex_bones(bgi)
				var bgw := bgtool.get_vertex_weights(bgi)
				var bpart := 0.0
				for bgk in bgb.size():
					if bgb[bgk] == gfbl or bgb[bgk] == gfbr:
						bpart += bgw[bgk]
				if bpart > 0.01:
					bwtot += 1
					if (gm2c * bgtool.get_vertex(bgi)).y < gfoot - 0.001:
						bviol += 1
	fails += _expect("breast gate floor", bviol == 0 and bwtot > 50)
	# Breast sculpt (Projection): normal push through the painted field on
	# Skin + Cloths, gated below the footprint floor, exact restore on reset.
	var lm4 := _avatar._breast_landmarks()
	var pa4: Array = lm4.get("apex", [])
	var gsmi4 := _avatar_skin_mi()
	var gcmi4 := _avatar_cloth_mi()
	if pa4.size() == 2 and gsmi4 != null and gsmi4.mesh != null:
		var smesh := gsmi4.mesh as ArrayMesh
		var ni_si := -1
		var ni_vi := -1
		var nd := 1e9
		for ssi in smesh.get_surface_count():
			var svv: PackedVector3Array = smesh.surface_get_arrays(ssi)[Mesh.ARRAY_VERTEX]
			for vvi in svv.size():
				var dd: float = svv[vvi].distance_squared_to(pa4[0])
				if dd < nd:
					nd = dd
					ni_si = ssi
					ni_vi = vvi
		var gate4 := _avatar._breast_last_gate
		var m2c4: Transform3D = gate4.get("m2c", Transform3D.IDENTITY)
		var foot4 := float(gate4.get("foot", -1e9))
		var pre := []
		for ssi in smesh.get_surface_count():
			pre.append((smesh.surface_get_arrays(ssi)[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate())
		var ci_si := -1
		var ci_vi := -1
		var cpre := []
		if gcmi4 != null and gcmi4.mesh != null:
			var cmesh := gcmi4.mesh as ArrayMesh
			var capex: Vector3 = (gcmi4 as Node3D).global_transform.affine_inverse() * ((gsmi4 as Node3D).global_transform * (pa4[0] as Vector3))
			var cd := 1e9
			for csi in cmesh.get_surface_count():
				var cvv: PackedVector3Array = cmesh.surface_get_arrays(csi)[Mesh.ARRAY_VERTEX]
				for cvi in cvv.size():
					var dd2: float = cvv[cvi].distance_squared_to(capex)
					if dd2 < cd:
						cd = dd2
						ci_si = csi
						ci_vi = cvi
			for csi in cmesh.get_surface_count():
				cpre.append((cmesh.surface_get_arrays(csi)[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate())
		adjust_bproj(5)
		fails += _expect("bproj display", bproj_display() == "+5mm")
		var spost: PackedVector3Array = (smesh.surface_get_arrays(ni_si)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		fails += _expect("bproj nipple push", ni_vi >= 0 and spost[ni_vi].distance_to((pre[ni_si] as PackedVector3Array)[ni_vi]) > 0.003)
		var bmax := 0.0
		for ssi in smesh.get_surface_count():
			var svv2: PackedVector3Array = smesh.surface_get_arrays(ssi)[Mesh.ARRAY_VERTEX]
			for vvi in svv2.size():
				if (m2c4 * (pre[ssi] as PackedVector3Array)[vvi]).y < foot4 - 0.005:
					bmax = maxf(bmax, svv2[vvi].distance_to((pre[ssi] as PackedVector3Array)[vvi]))
		fails += _expect("bproj floor still", bmax < 1e-9)
		if ci_vi >= 0 and gcmi4 != null and gcmi4.mesh != null:
			var cvv2: PackedVector3Array = ((gcmi4.mesh as ArrayMesh).surface_get_arrays(ci_si)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			fails += _expect("bproj cloth follows", cvv2[ci_vi].distance_to((cpre[ci_si] as PackedVector3Array)[ci_vi]) > 0.001)
		else:
			fails += _expect("bproj cloth follows", false)
		reset_bproj()
		fails += _expect("bproj reset display", bproj_display() == "+0mm")
		var rmax := 0.0
		for ssi in smesh.get_surface_count():
			var svv3: PackedVector3Array = smesh.surface_get_arrays(ssi)[Mesh.ARRAY_VERTEX]
			for vvi in svv3.size():
				rmax = maxf(rmax, svv3[vvi].distance_to((pre[ssi] as PackedVector3Array)[vvi]))
		fails += _expect("bproj restore exact", rmax < 1e-9)
		adjust_bproj(50)
		fails += _expect("bproj clamp max", bproj_display() == "+%dmm" % int(round(CharacterAvatar.BPROJ_MAX_CM * 10.0)))
		adjust_bproj(-50)
		adjust_bproj(-50)
		fails += _expect("bproj clamp min", bproj_display() == "-%dmm" % int(round(CharacterAvatar.BPROJ_MIN_CM * 10.0)))
		reset_bproj()
	else:
		for bname in ["bproj display", "bproj nipple push", "bproj floor still", "bproj cloth follows", "bproj reset display", "bproj restore exact", "bproj clamp max", "bproj clamp min"]:
			fails += _expect(bname, false)
	# BreastAngle: rigid mirrored yaw (+ = inward), exact identity on reset.
	adjust_bangle(10)
	fails += _expect("bangle display", bangle_display() == "+10°")
	var fsk3 := _avatar_skeleton()
	var fbl3 := fsk3.find_bone(&"LeftBreast") if fsk3 != null else -1
	var fbr3 := fsk3.find_bone(&"RightBreast") if fsk3 != null else -1
	var gql: Quaternion = fsk3.get_bone_pose_rotation(fbl3)
	var gqr: Quaternion = fsk3.get_bone_pose_rotation(fbr3)
	var eul := gql.get_euler()
	var eur := gqr.get_euler()
	fails += _expect("bangle mirrored", absf(rad_to_deg(eul.y) - 10.0) < 0.01 and absf(rad_to_deg(eur.y) + 10.0) < 0.01)
	reset_bangle()
	fails += _expect("bangle reset", bangle_display() == "+0°" and fsk3.get_bone_pose_rotation(fbl3).is_equal_approx(Quaternion.IDENTITY))
	# BreastCurve: display/clamp/reset in absolute mm.
	reset_bproj()
	reset_bcurve()
	fails += _expect("bcurve display", bcurve_display() == "+0mm")
	adjust_bcurve(10)
	fails += _expect("bcurve plus", bcurve_display() == "+10mm")
	adjust_bcurve(50)
	fails += _expect("bcurve clamp", bcurve_display() == "+%dmm" % int(round(CharacterAvatar.BCURVE_MAX_CM * 10.0)))
	reset_bcurve()
	fails += _expect("bcurve reset", bcurve_display() == "+0mm")
	var lm5 := _avatar._breast_landmarks()
	var cnip5: Array = lm5.get("cnip", [])
	var cny5: Array = lm5.get("cny", [0.0, 0.0])
	var rad5 := float(lm5.get("radius", 0.11))
	var foot5 := float(lm5.get("cfoot", 0.0))
	var gate5 := _avatar._breast_last_gate
	var m2c5: Transform3D = gate5.get("m2c", Transform3D.IDENTITY)
	var gsmi5 := _avatar_skin_mi()
	if cnip5.size() == 2 and gsmi5 != null and gsmi5.mesh != null:
		var smesh5 := gsmi5.mesh as ArrayMesh
		var mid_best := [-1, -1, 1e9]
		var low_best := [-1, -1, 1e9]
		var tip_best := [-1, -1, 1e9]
		var high_best := [-1, -1, 1e9]
		for ssi in smesh5.get_surface_count():
			var svv: PackedVector3Array = smesh5.surface_get_arrays(ssi)[Mesh.ARRAY_VERTEX]
			for vvi in svv.size():
				var qq: Vector3 = m2c5 * svv[vvi]
				var dd: float = minf(qq.distance_to(cnip5[0]), qq.distance_to(cnip5[1]))
				var ny: float = float(cny5[0] if qq.x < 0.0 else cny5[1])
				if qq.y > ny + 0.055 and dd > 0.3 * rad5 and dd < 0.7 * rad5 and absf(dd - 0.5 * rad5) < float(mid_best[2]):
					mid_best = [ssi, vvi, absf(dd - 0.5 * rad5)]
				if qq.y > ny + 0.002 and dd < float(tip_best[2]):
					tip_best = [ssi, vvi, dd]
				if qq.y > ny + 0.01 and dd >= rad5 and dd < 1.3 * rad5 and absf(dd - 1.15 * rad5) < float(high_best[2]):
					high_best = [ssi, vvi, absf(dd - 1.15 * rad5)]
				if qq.y > foot5 + 0.005 and qq.y < ny - 0.005 and dd < 0.8 * rad5 and absf(dd - 0.5 * rad5) < float(low_best[2]):
					low_best = [ssi, vvi, absf(dd - 0.5 * rad5)]
		if int(mid_best[0]) >= 0 and int(low_best[0]) >= 0 and int(tip_best[0]) >= 0 and int(high_best[0]) >= 0:
			var pre5 := []
			var nrm5 := []
			for ssi in smesh5.get_surface_count():
				pre5.append((smesh5.surface_get_arrays(ssi)[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate())
				nrm5.append((smesh5.surface_get_arrays(ssi)[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate())
			# Standalone: Projection stays 0 while Curve works.
			adjust_bcurve(10)
			fails += _expect("bcurve standalone", bproj_display() == "+0mm")
			var p0t: Vector3 = (smesh5.surface_get_arrays(int(tip_best[0]))[Mesh.ARRAY_VERTEX] as PackedVector3Array)[int(tip_best[1])]
			var nt0: Vector3 = (nrm5[int(tip_best[0])] as PackedVector3Array)[int(tip_best[1])].normalized()
			fails += _expect("bcurve pointy", (p0t - (pre5[int(tip_best[0])] as PackedVector3Array)[int(tip_best[1])]).dot(nt0) > 0.005)
			var ppm: Vector3 = (smesh5.surface_get_arrays(int(mid_best[0]))[Mesh.ARRAY_VERTEX] as PackedVector3Array)[int(mid_best[1])]
			fails += _expect("bcurve pointy tight", ppm.distance_to((pre5[int(mid_best[0])] as PackedVector3Array)[int(mid_best[1])]) < 0.001)
			adjust_bcurve(-20)
			var pmt: Vector3 = (smesh5.surface_get_arrays(int(mid_best[0]))[Mesh.ARRAY_VERTEX] as PackedVector3Array)[int(mid_best[1])]
			var nm0: Vector3 = (nrm5[int(mid_best[0])] as PackedVector3Array)[int(mid_best[1])].normalized()
			fails += _expect("bcurve scoop", (pmt - (pre5[int(mid_best[0])] as PackedVector3Array)[int(mid_best[1])]).dot(nm0) < -0.002)
			var lmax := 0.0
			for ssi in smesh5.get_surface_count():
				var svv4: PackedVector3Array = smesh5.surface_get_arrays(ssi)[Mesh.ARRAY_VERTEX]
				for vvi in svv4.size():
					if (m2c5 * (pre5[ssi] as PackedVector3Array)[vvi]).y < foot5 - 0.001:
						lmax = maxf(lmax, svv4[vvi].distance_to((pre5[ssi] as PackedVector3Array)[vvi]))
			fails += _expect("bcurve lower identical", lmax < 1e-9)
			reset_bcurve()
		else:
			fails += _expect("bcurve pointy", false)
			fails += _expect("bcurve pointy tight", false)
			fails += _expect("bcurve standalone", false)
			fails += _expect("bcurve scoop", false)
			fails += _expect("bcurve lower identical", false)
	else:
		for bname in ["bcurve display", "bcurve plus", "bcurve clamp", "bcurve reset", "bcurve pointy", "bcurve pointy tight", "bcurve standalone", "bcurve scoop", "bcurve lower identical"]:
			fails += _expect(bname, false)
	_menu._push(CharacterMenu.LEVEL_PHYSICS)
	fails += _expect("female physics breast rows", _menu._entries.size() == 12)
	_menu._pop()
	# Wiggle attaches live only — headless stays deterministic.
	var wig_n := 0
	for wch in fsk.get_children():
		if wch is WiggleBone:
			wig_n += 1
	fails += _expect("no wiggle headless", wig_n == 0)
	# No duplicated surfaces (12/10: MeshDataTool.commit appended a copy).
	var dup_n := 0
	for fmi in [_avatar_skin_mi(), _avatar_cloth_mi()]:
		if fmi == null or (fmi as MeshInstance3D).mesh == null:
			continue
		var seen := {}
		var fm := (fmi as MeshInstance3D).mesh as ArrayMesh
		for fsdup in fm.get_surface_count():
			var fv: PackedVector3Array = fm.surface_get_arrays(fsdup)[Mesh.ARRAY_VERTEX]
			var fk := "%d:%s" % [fv.size(), str(fv[0]) if not fv.is_empty() else "e"]
			if seen.has(fk):
				dup_n += 1
			else:
				seen[fk] = true
	fails += _expect("breast no surface dup", dup_n == 0)
	# Female parity (male-tuned rows must actuate on female): mask coverage,
	# moves/restores, and mean-push recorded for the male-side ratio in §17
	# (same key list — keep in sync).
	var fcov := _avatar.sculpt_mask_coverage()
	for region in ["Nose", "Mouth", "Chin", "NoseBridge", "NoseTip", "NostrilFlare", "UpperLip", "LowerLip", "MouthCorners", "Eyelids", "UpperEyelid", "Brows", "BrowRidge", "Jaw", "ChinCleft", "Cheekbones", "Cheeks", "LowerFace", "Forehead", "Ears", "Lobe", "EarTip"]:
		var cc: Array = fcov.get(region, [0, 0])
		fails += _expect("female mask %s resolves" % region, int(cc[1]) > 0 and float(cc[0]) / float(cc[1]) > 0.9)
	for nk in [&"NoseBridge", &"NoseTip", &"NostrilFlare", &"NoseTipLength", &"NosePosition", &"LipUpper", &"LipLower", &"MouthCorners", &"MouthPosition", &"MouthForward", &"NoseTipSize", &"NoseTipAngle", &"NoseCurve", &"MouthPout", &"EyelidHeavy", &"EyeDepth", &"EyeHeight", &"EyeSpacing", &"EyeSize", &"EyeAngle", &"BrowAngle", &"BrowHeight", &"BrowThick", &"BrowDepth", &"JawWidth", &"JawDefinition", &"JawAngle", &"ChinLength", &"ChinWidth", &"ChinProject", &"ChinCleft", &"CheekboneWidth", &"CheekboneHeight", &"CheekFullness", &"FaceFullness", &"ForeheadHeight", &"ForeheadWidth", &"BrowRidgeDepth", &"EarSize", &"EarRotation", &"EarlobeLength", &"EarPoint"]:
		reset_face_sculpt(nk)
		adjust_face_sculpt(nk, 10)
		fails += _expect("female sculpt %s moves" % String(nk), _avatar.sculpt_max_cliff() > 1e-9)
		parity_f[nk] = _avatar.sculpt_mean_push()
		reset_face_sculpt(nk)
		fails += _expect("female sculpt %s restores" % String(nk), _avatar.sculpt_max_cliff() < 1e-9)
	_avatar._outfit[&"Body"] = 2
	_apply_nude()
	_rebuild_avatar()
	fails += _expect("body B shown", slot_display(&"Body") == "PeasantB")
	fails += _expect("body B fused", _avatar_mi() != null and _avatar_surf_count() > 1)
	reset_slot(&"Body")
	reset_gender()
	reset_slot(&"Body")
	fails += _expect("back to male nude", gender_display() == "Male" and slot_display(&"Body") == "--")
	fails += _expect("male stays 65", _avatar_skeleton() != null and _avatar_skeleton().get_bone_count() == 65)
	fails += _expect("male avatar fused", _avatar_mi() != null and _avatar_surf_count() > 1)
	fails += _expect("male hands kept", _avatar_finger_verts() > 100)
	fails += _expect("skin push on", _avatar_push("SuperHero") > 0.01)
	# Explicit nude slot ("None" cycles last, shows "--", nude shows through).
	_avatar._outfit[&"Body"] = _avatar._slot_outfits(&"Body").size() - 1
	_avatar.full_rebuild()
	fails += _expect("body none shows", slot_display(&"Body") == "--")
	fails += _expect("body none fused", _avatar_mi() != null and _avatar_surf_count() > 1)
	reset_slot(&"Body")
	fails += _expect("body none restored", slot_display(&"Body") == "--")
	for sl in CharacterAvatar.SLOTS:
		_avatar._outfit[sl] = 0
	_avatar.full_rebuild()
	fails += _expect("peasant redressed", slot_display(&"Body") == "Peasant" and _avatar_cloth_mi() != null)
	# Male nude skips brows/eyes at import: the mounted parts stand in.
	fails += _expect("male brows mounted", _avatar.get_node_or_null("Eyebrows/Male_Eyebrows") != null)
	fails += _expect("male eyes mounted", _avatar.get_node_or_null("Eyes/Male_Eyes") != null)
	fails += _expect("male lashes mounted", _avatar.get_node_or_null("Eyelashes/Male_Eyelashes") != null)
	fails += _expect("fitkit default on", use_fitkit or "--nofit" in OS.get_cmdline_user_args() or "--nofit" in OS.get_cmdline_args())
	fails += _expect("stages default on", (not no_suppress) or "--nosuppress" in OS.get_cmdline_user_args() or "--nosuppress" in OS.get_cmdline_args())
	fails += _expect("fitkit cfg male legs", not FitKit.cfg_for(&"Legs", 0).is_empty())
	fails += _expect("fitkit cfg female legs", not FitKit.cfg_for(&"Legs", 1).is_empty())
	fails += _expect("fitkit cfg female arms", not FitKit.cfg_for(&"Arms", 1).is_empty())
	fails += _expect("fitkit regular clamp", FitKit.REGULAR_CLAMP < FitKit.MAX_PUSH)
	fails += _expect("avatar albedo wired", _avatar_tex() != null)
	fails += _expect("cache bypassed dev", not CharacterAvatar.USE_CACHE and _avatar._avatar_cache.is_empty())
	_xray = 0
	_apply_xray()
	_cycle_xray()
	fails += _expect("xray skin only", _avatar_skin_mi().visible and not _avatar_cloth_mi().visible)
	_cycle_xray()
	fails += _expect("xray volumes", _avatar_skin_mi().visible and _avatar_cloth_mi().visible and _world().get_node_or_null("Volumes") != null)
	_cycle_xray()
	fails += _expect("xray wire", _wire and XRAY_NAMES[_xray] == "Wire" and _avatar_skin_mi().visible and _avatar_cloth_mi().visible)
	_cycle_xray()
	fails += _expect("xray back to fused", not _wire and _xray == 0 and _avatar_skin_mi().visible and _avatar_cloth_mi().visible and _world().get_node_or_null("Volumes") == null)
	adjust_slot(&"Head", 1)
	fails += _expect("hood shown", slot_display(&"Head") == "Ranger")
	fails += _expect("hood fused", _avatar_mi() != null and _avatar_surf_count() > 1)
	reset_slot(&"Head")
	# 4. Real menu Callable path (L/R = adjust.call(dir), A/E = reset.call()):
	# the bound slot must survive the int arg (regression: bind order crash).
	_menu._push()
	var body_entry := {}
	for e in _menu._entries:
		if e is Dictionary and String(e.get("label", "")) == "Body":
			body_entry = e
	fails += _expect("menu body row found", not body_entry.is_empty())
	if not body_entry.is_empty():
		(body_entry["adjust"] as Callable).call(1)
		fails += _expect("menu L/R cycles outfit", slot_display(&"Body") == "Ranger")
		(body_entry["reset"] as Callable).call()
		fails += _expect("menu A/E resets outfit", slot_display(&"Body") == "--")
	_menu._pop()
	# 5. Four-level menu (root/outfits/colors/physics) + idle preview.
	var root_labels := []
	for e in _menu._entries:
		root_labels.append(String((e as Dictionary).get("label", "")))
	fails += _expect("menu root outfits", root_labels.has("Outfits >"))
	fails += _expect("menu root outfit colors", root_labels.has("Outfits Colors >"))
	fails += _expect("menu root physics", root_labels.has("Physics >"))
	fails += _expect("menu root face", root_labels.has("Face >"))
	fails += _expect("menu root skin", root_labels.has("Skin >"))
	fails += _expect("menu root head grouped", not root_labels.has("Hair >") and not root_labels.has("Eyebrows >") and not root_labels.has("Eyes >") and not root_labels.has("Beard >"))
	_menu._push(CharacterMenu.LEVEL_COLORS)
	fails += _expect("menu outfit colors 6+back", _menu._entries.size() == 7)
	_menu._push(CharacterMenu.LEVEL_PHYSICS)
	fails += _expect("menu physics 6+back", _menu._entries.size() == 7)
	_menu._pop()
	var want_take := _animtest_take() if _animtest_wanted() else IDLE_TAKE
	fails += _expect("preview anim playing", _anim_player != null and _anim_player.current_animation == want_take)
	# Color rows need a dressed slot (default is nude since -- None).
	for sl in CharacterAvatar.SLOTS:
		_avatar._outfit[sl] = 0
	_avatar.full_rebuild()
	fails += _expect("color body mapped", not _slot_mats(&"Body").is_empty())
	fails += _expect("color skin mapped", not _slot_mats(&"Skin").is_empty())
	open_color(&"Head")
	fails += _expect("color empty slot no-op", not is_color_open())
	open_color(&"Body")
	fails += _expect("color panel opens", is_color_open())
	var cur0 := _menu._cursor
	_menu._on_input_action(&"catalog_next")
	fails += _expect("menu gated while color open", _menu._cursor == cur0)
	_dresser._confirm()
	fails += _expect("color stored on OK", _avatar._color_params.has(&"Body"))
	_menu._on_input_action(&"catalog_next")
	fails += _expect("menu resumes after close", _menu._cursor != cur0)
	# 6. Keyboard in editor profile (Right = tab_next, E = place OK).
	# Tap = exactly one step (typematic).
	open_color(&"Body")
	for f in 2:
		await get_tree().process_frame
	_chartest_key(KEY_RIGHT, true)
	await get_tree().process_frame
	_chartest_key(KEY_RIGHT, false)
	for f in 2:
		await get_tree().process_frame
	fails += _expect("color tap one step", is_equal_approx(float(_dresser.current_params()["hue"]), 1.0))
	_chartest_key(KEY_RIGHT, true)
	for f in 30:
		await get_tree().process_frame
	_chartest_key(KEY_RIGHT, false)
	fails += _expect("color keyboard sweep", float(_dresser.current_params()["hue"]) > 0.0)
	fails += _expect("color sweep on grid", is_equal_approx(fmod(float(_dresser.current_params()["hue"]), 1.0), 0.0))
	_chartest_key(KEY_E, true)
	for f in 2:
		await get_tree().process_frame
	_chartest_key(KEY_E, false)
	for f in 2:
		await get_tree().process_frame
	fails += _expect("color keyboard OK", not is_color_open())
	open_color(&"Body")
	for f in 2:
		await get_tree().process_frame
	_chartest_key(KEY_Q, true)
	for f in 2:
		await get_tree().process_frame
	_chartest_key(KEY_Q, false)
	for f in 2:
		await get_tree().process_frame
	fails += _expect("color keyboard cancel", not is_color_open())
	_avatar._color_params[&"Body"] = {"hue": 90.0, "sat": 1.5, "val": 1.0}
	_reapply_colors()
	var body_mat := (_slot_mats(&"Body")[0] as ShaderMaterial)
	fails += _expect("color reapply hue", is_equal_approx(float(body_mat.get_shader_parameter("hue_shift_deg")), 90.0))
	adjust_phys(&"Legs", 1)
	var sk := _avatar_skeleton()
	var thigh := sk.find_bone(&"LeftUpperLeg")
	fails += _expect("phys thigh found", thigh != -1)
	fails += _expect("phys display", phys_display(&"Legs") == "101%")
	for f in 5:
		await get_tree().process_frame
	fails += _expect("phys scale survives idle", sk.get_bone_pose_scale(thigh).is_equal_approx(Vector3(1.01, 1.0, 1.01)))
	reset_phys(&"Legs")
	fails += _expect("phys reset", sk.get_bone_pose_scale(thigh).is_equal_approx(Vector3.ONE))
	adjust_phys(&"Height", 5)
	fails += _expect("phys height uniform", sk.get_bone_pose_scale(sk.find_bone(&"Root")).is_equal_approx(Vector3(1.05, 1.05, 1.05)))
	adjust_phys(&"Height", 50)
	fails += _expect("phys height clamped", phys_display(&"Height") == "110%")
	adjust_phys(&"Height", -50)
	fails += _expect("phys height clamped low", phys_display(&"Height") == "90%")
	reset_phys(&"Height")
	adjust_phys(&"Waist", 2)
	adjust_phys(&"Hips", 2)
	var want_inv := 1.0 / 1.0404
	fails += _expect("phys head untouched", sk.get_bone_pose_scale(sk.find_bone(&"Head")).is_equal_approx(Vector3.ONE))
	fails += _expect("phys neck counters", sk.get_bone_pose_scale(sk.find_bone(&"Neck")).is_equal_approx(Vector3(want_inv, 1.0, want_inv)))
	reset_phys(&"Waist")
	reset_phys(&"Hips")
	fails += _expect("phys neck reset", sk.get_bone_pose_scale(sk.find_bone(&"Neck")).is_equal_approx(Vector3.ONE))
	adjust_phys(&"Waist", 50)
	fails += _expect("phys waist clamped", phys_display(&"Waist") == "105%")
	reset_phys(&"Waist")
	adjust_phys(&"Legs", 50)
	fails += _expect("phys legs clamped", phys_display(&"Legs") == "110%")
	reset_phys(&"Legs")
	adjust_phys(&"Head", 2)
	fails += _expect("phys head uniform", sk.get_bone_pose_scale(sk.find_bone(&"Head")).is_equal_approx(Vector3(1.02, 1.02, 1.02)))
	reset_phys(&"Head")
	fails += _expect("phys head reset", sk.get_bone_pose_scale(sk.find_bone(&"Head")).is_equal_approx(Vector3.ONE))
	var hud := get_node_or_null("MenuLayer/HUD")
	fails += _expect("phys height shown", hud != null and String(hud.get("_persistent").get(&"height", "")).begins_with("HEIGHT: 1."))
	# 6. Hair menu (style cycle, master mount, color).
	fails += _expect("hair none default", hair_display() == "None" and hair_file("Male", &"None").is_empty())
	fails += _expect("hair buzzed male", hair_file("Male", &"Buzzed").ends_with("Hair_Buzzed.gltf"))
	fails += _expect("hair buns female", hair_file("Female", &"Buns").ends_with("Hair_Buns.gltf"))
	adjust_hair(1)
	fails += _expect("hair style shown", hair_display() == "Buzzed")
	var hmi := _avatar.get_node_or_null("Hair/Buzzed") as MeshInstance3D
	fails += _expect("hair mounted", hmi != null and hmi.mesh != null)
	var hmaster := _avatar_skeleton()
	fails += _expect("hair on master", hmi != null and hmaster != null and hmi.get_node_or_null(hmi.skeleton) == hmaster)
	var hidx := hmaster.find_bone(&"Head") if hmaster != null else -1
	var allhead := true
	if hmi != null and hmi.mesh != null:
		for s in hmi.mesh.get_surface_count():
			var arr := hmi.mesh.surface_get_arrays(s)
			var bi: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var bw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			for i in bw.size():
				if bw[i] > 0.0 and bi[i] != hidx:
					allhead = false
	fails += _expect("hair 100pct head", hidx != -1 and allhead)
	open_color(&"Hair")
	fails += _expect("hair color opens", is_color_open())
	_dresser._params = {"hue": 30.0, "sat": 0.8, "val": 0.4}
	_dresser._apply()
	var hair_mat := (_slot_mats(&"Hair")[0] as ShaderMaterial)
	var want_hair := Color.from_hsv(30.0 / 360.0, 0.8, 0.4)
	fails += _expect("hair albedo written", (hair_mat.get_shader_parameter("albedo") as Color).is_equal_approx(want_hair))
	fails += _expect("hair shift neutral", is_equal_approx(float(hair_mat.get_shader_parameter("hue_shift_deg")), 0.0))
	fails += _expect("hair texture kept", hair_mat.get_shader_parameter("albedo_texture") != null)
	_dresser._confirm()
	fails += _expect("hair albedo stored", _avatar._color_params.has(&"Hair"))
	adjust_hair(1) # remount (SimpleParted) must reapply the stored albedo
	var hair_mat2 := (_slot_mats(&"Hair")[0] as ShaderMaterial)
	fails += _expect("hair albedo survives remount", hair_mat2 != null and (hair_mat2.get_shader_parameter("albedo") as Color).is_equal_approx(want_hair))
	adjust_hair(-1)
	_avatar._color_params.erase(&"Hair")
	adjust_hair(1)
	adjust_hair(-1) # fresh default mount (sat/val 0.5), nothing stored
	open_color(&"Hair")
	fails += _expect("hair defaults mid", is_equal_approx(float(_dresser.current_params()["sat"]), 0.5) and is_equal_approx(float(_dresser.current_params()["val"]), 0.5))
	_dresser._params = {"hue": 0.0, "sat": 0.0, "val": 1.0}
	_dresser._apply()
	_dresser._confirm() # store white...
	open_color(&"Hair") # ...reopen kicks sat to 1.0 so Color answers at once
	fails += _expect("hair kick sat up", is_equal_approx(float(_dresser.current_params()["sat"]), 1.0))
	fails += _expect("hair kick vivid", Color((_slot_mats(&"Hair")[0] as ShaderMaterial).get_shader_parameter("albedo")).s > 0.9)
	_dresser._cancel()
	# Cursor mode is never touched (keyboard/gamepad-only dresser, 07/10) —
	# nothing observable headless; eye recipe covers orbit control.
	fails += _expect("hair cancel restores white", Color((_slot_mats(&"Hair")[0] as ShaderMaterial).get_shader_parameter("albedo")).s < 0.1)
	_avatar._color_params.erase(&"Hair")
	reset_hair()
	fails += _expect("hair reset bald", hair_display() == "None" and _avatar.get_node_or_null("Hair/Buzzed") == null)
	open_color(&"Hair")
	fails += _expect("hair color empty no-op", not is_color_open())
	_menu._push(CharacterMenu.LEVEL_HAIR)
	fails += _expect("menu hair rows", _menu._entries.size() == 3)
	fails += _expect("face cam on hair", face_active())
	fails += _expect("face parts pause idle", _anim_paused == _idle_only)
	_menu._pop()
	fails += _expect("face hair back to hub", _menu._level == CharacterMenu.LEVEL_FACE and face_active())
	_menu._pop()
	fails += _expect("face cam off hair", not face_active())
	# 7. Eyebrows (mounted male part, fused female fallback, own color slot, face cam).
	fails += _expect("brow style default", eyebrow_display() == "Default")
	adjust_eyebrow(1)
	fails += _expect("brow style single", eyebrow_display() == "Default")
	reset_eyebrow()
	fails += _expect("brow file male", eyebrow_file("Male", &"Default").ends_with("Male_Eyebrows.gltf"))
	var bmi2 := _avatar.get_node_or_null("Eyebrows/Male_Eyebrows") as MeshInstance3D
	fails += _expect("brow mounted", bmi2 != null and bmi2.mesh != null)
	fails += _expect("brow on master", bmi2 != null and hmaster != null and bmi2.get_node_or_null(bmi2.skeleton) == hmaster)
	var browhead := true
	if bmi2 != null and bmi2.mesh != null:
		for s in bmi2.mesh.get_surface_count():
			var barr := bmi2.mesh.surface_get_arrays(s)
			var bbi: PackedInt32Array = barr[Mesh.ARRAY_BONES]
			var bbw: PackedFloat32Array = barr[Mesh.ARRAY_WEIGHTS]
			for i in bbw.size():
				if bbw[i] > 0.0 and bbi[i] != hidx:
					browhead = false
	fails += _expect("brow 100pct head", hidx != -1 and browhead)
	var brow_mats := _slot_mats(&"Eyebrows")
	var shared := false
	for m in brow_mats:
		if _slot_mats(&"Skin").has(m):
			shared = true
	fails += _expect("brow split from skin", not brow_mats.is_empty() and not shared)
	open_color(&"Eyebrows")
	fails += _expect("brow color opens", is_color_open())
	fails += _expect("brow defaults mid", is_equal_approx(float(_dresser.current_params()["sat"]), 0.5) and is_equal_approx(float(_dresser.current_params()["val"]), 0.5))
	_dresser._params = {"hue": 20.0, "sat": 0.8, "val": 0.6}
	_dresser._apply()
	var want_brow := Color.from_hsv(20.0 / 360.0, 0.8, 0.6)
	fails += _expect("brow albedo written", ((brow_mats[0] as ShaderMaterial).get_shader_parameter("albedo") as Color).is_equal_approx(want_brow))
	fails += _expect("brow shift neutral", is_equal_approx(float((brow_mats[0] as ShaderMaterial).get_shader_parameter("hue_shift_deg")), 0.0))
	_dresser._confirm()
	fails += _expect("brow color stored", _avatar._color_params.has(&"Eyebrows"))
	_menu._push(CharacterMenu.LEVEL_EYEBROWS)
	fails += _expect("menu brow rows", _menu._entries.size() == 2 + 4 + 1)
	var pivot := _face_pivot()
	var arm := (pivot.get_node_or_null("SpringArm3D") as SpringArm3D) if pivot != null else null
	fails += _expect("face cam close", face_active() and arm != null and is_equal_approx(arm.spring_length, FACE_ARM))
	fails += _expect("face cam at head", pivot != null and pivot.position.y > _head_world().y)
	_menu._pop()
	fails += _expect("face brow back to hub", _menu._level == CharacterMenu.LEVEL_FACE and face_active())
	_menu._pop()
	fails += _expect("face cam restored", not face_active() and arm != null and is_equal_approx(arm.spring_length, 3.2) and is_equal_approx(pivot.position.y, 1.0))
	# 8. Skin submenu (color only, room for more).
	_menu._push(CharacterMenu.LEVEL_SKIN)
	fails += _expect("menu skin rows", _menu._entries.size() == 2)
	_menu._pop()
	open_color(&"Skin")
	fails += _expect("skin color opens", is_color_open())
	_dresser._params = {"hue": 40.0, "sat": 1.2, "val": 1.0}
	_dresser._apply()
	fails += _expect("skin hue written", is_equal_approx(float((_slot_mats(&"Skin")[0] as ShaderMaterial).get_shader_parameter("hue_shift_deg")), 40.0))
	_dresser._confirm()
	fails += _expect("skin color stored", _avatar._color_params.has(&"Skin"))
	# 9. Eyes submenu (mounted male part, fused female fallback, hue-shift).
	fails += _expect("eye style default", eye_display() == "Default")
	adjust_eye(1)
	fails += _expect("eye style single", eye_display() == "Default")
	reset_eye()
	fails += _expect("eye file male", eye_file("Male", &"Default").ends_with("Male_Eyes.gltf"))
	var emi := _avatar.get_node_or_null("Eyes/Male_Eyes") as MeshInstance3D
	fails += _expect("eyes mounted", emi != null and emi.mesh != null)
	fails += _expect("eyes on master", emi != null and hmaster != null and emi.get_node_or_null(emi.skeleton) == hmaster)
	var eyehead := true
	if emi != null and emi.mesh != null:
		for s in emi.mesh.get_surface_count():
			var earr := emi.mesh.surface_get_arrays(s)
			var ebi: PackedInt32Array = earr[Mesh.ARRAY_BONES]
			var ebw: PackedFloat32Array = earr[Mesh.ARRAY_WEIGHTS]
			for i in ebw.size():
				if ebw[i] > 0.0 and ebi[i] != hidx:
					eyehead = false
	fails += _expect("eyes 100pct head", hidx != -1 and eyehead)
	var eye_mats := _slot_mats(&"Eyes")
	var eye_shared := false
	for m in eye_mats:
		if _slot_mats(&"Skin").has(m):
			eye_shared = true
	fails += _expect("eyes split from skin", not eye_mats.is_empty() and not eye_shared)
	open_color(&"Eyes")
	fails += _expect("eyes color opens", is_color_open())
	_dresser._params = {"hue": 120.0, "sat": 1.2, "val": 1.0}
	_dresser._apply()
	fails += _expect("eyes hue written", is_equal_approx(float((eye_mats[0] as ShaderMaterial).get_shader_parameter("hue_shift_deg")), 120.0))
	_dresser._confirm()
	fails += _expect("eyes color stored", _avatar._color_params.has(&"Eyes"))
	_menu._push(CharacterMenu.LEVEL_EYES)
	fails += _expect("menu eyes rows", _menu._entries.size() == 2 + 6 + 1)
	fails += _expect("face cam on eyes", face_active())
	_menu._pop()
	fails += _expect("face eyes back to hub", _menu._level == CharacterMenu.LEVEL_FACE and face_active())
	_menu._pop()
	fails += _expect("face cam off eyes", not face_active())
	# 9b. Eyelashes (mounted part both genders, no nude counterpart: albedo
	# defaults like hair; Face hub submenu = Style + Color, single style).
	fails += _expect("lash style default", eyelash_display() == "Default")
	adjust_eyelash(1)
	fails += _expect("lash style single", eyelash_display() == "Default")
	reset_eyelash()
	fails += _expect("lash file male", eyelash_file("Male", &"Default").ends_with("Male_Eyelashes.gltf"))
	var lmi := _avatar.get_node_or_null("Eyelashes/Male_Eyelashes") as MeshInstance3D
	fails += _expect("lashes mounted", lmi != null and lmi.mesh != null)
	fails += _expect("lashes on master", lmi != null and hmaster != null and lmi.get_node_or_null(lmi.skeleton) == hmaster)
	var lashhead := true
	if lmi != null and lmi.mesh != null:
		for s in lmi.mesh.get_surface_count():
			var larr := lmi.mesh.surface_get_arrays(s)
			var lbi: PackedInt32Array = larr[Mesh.ARRAY_BONES]
			var lbw: PackedFloat32Array = larr[Mesh.ARRAY_WEIGHTS]
			for i in lbw.size():
				if lbw[i] > 0.0 and lbi[i] != hidx:
					lashhead = false
	fails += _expect("lashes 100pct head", hidx != -1 and lashhead)
	var lash_mats := _slot_mats(&"Eyelashes")
	fails += _expect("lashes albedo slot", not lash_mats.is_empty())
	var lash_shared := false
	for m in lash_mats:
		if _slot_mats(&"Skin").has(m):
			lash_shared = true
	fails += _expect("lashes split from skin", not lash_shared)
	open_color(&"Eyelashes")
	fails += _expect("lashes color opens", is_color_open())
	_dresser._params = {"hue": 300.0, "sat": 0.8, "val": 0.6}
	_dresser._apply()
	var want_lash := Color.from_hsv(300.0 / 360.0, 0.8, 0.6)
	fails += _expect("lashes albedo written", ((lash_mats[0] as ShaderMaterial).get_shader_parameter("albedo") as Color).is_equal_approx(want_lash))
	_dresser._confirm()
	fails += _expect("lashes color stored", _avatar._color_params.has(&"Eyelashes"))
	_menu._push(CharacterMenu.LEVEL_FACE_EYELASHES)
	fails += _expect("menu lashes rows", _menu._entries.size() == 3)
	fails += _expect("face cam on lashes", face_active())
	_menu._pop()
	fails += _expect("face lashes back to hub", _menu._level == CharacterMenu.LEVEL_FACE and face_active())
	# 9c. Face-part follow (09/10, site-mean 12/10): socket rows move the rigid
	# parts with the socket's local motion (mesh space, anim-exact); rest
	# restores pristine. Balls ride lids/tilt/socket spillover, shape held.
	var eyes0 := _face_part_mean("Eyes")
	adjust_face_sculpt(&"EyeDepth", 8)
	var eyes1 := _face_part_mean("Eyes")
	fails += _expect("eyes follow out", eyes1.z > eyes0.z + 0.006)
	fails += _expect("eyes follow baked", _avatar._face_pristine.has("Eyes") and _avatar.get_node_or_null("Eyes/Male_Eyes") != null and (_avatar.get_node_or_null("Eyes/Male_Eyes") as MeshInstance3D).mesh != _avatar._face_pristine["Eyes"])
	reset_face_sculpt(&"EyeDepth")
	fails += _expect("eyes follow restores", (_avatar.get_node_or_null("Eyes/Male_Eyes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyes"])
	var lash0 := _face_part_mean("Eyelashes")
	var ey0 := _face_part_mean("Eyes")
	adjust_face_sculpt(&"EyelidHeavy", 8)
	var lash1 := _face_part_mean("Eyelashes")
	var ey1 := _face_part_mean("Eyes")
	fails += _expect("lashes follow lid", lash1.y < lash0.y - 0.003)
	fails += _expect("eyes ride lid", ey1.y < ey0.y - 0.002)
	reset_face_sculpt(&"EyelidHeavy")
	fails += _expect("eyes lid restores", (_avatar.get_node_or_null("Eyes/Male_Eyes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyes"])
	fails += _expect("lashes follow restores", (_avatar.get_node_or_null("Eyelashes/Male_Eyelashes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyelashes"])
	var brow0 := _face_part_mean("Eyebrows")
	adjust_face_sculpt(&"BrowRidgeDepth", 8)
	var brow1 := _face_part_mean("Eyebrows")
	fails += _expect("brows follow ridge", brow1.z > brow0.z + 0.003)
	reset_face_sculpt(&"BrowRidgeDepth")
	fails += _expect("brows follow restores", (_avatar.get_node_or_null("Eyebrows/Male_Eyebrows") as MeshInstance3D).mesh == _avatar._face_pristine["Eyebrows"])
	# Authored clearance pin (09/10, 1mm Blender fix): min distance between
	# the eyeballs and the Eyelids skin at rest. A future export that touches
	# the lids again fails here instead of in the viewport.
	for sk3 in CharacterAvatar.SCULPT_KEYS:
		reset_face_sculpt(sk3)
	var clear := _eye_lid_clearance()
	print("[CharTest] eye clearance %.4f" % clear)
	fails += _expect("eyes clear lids", clear > 0.0003)
	# Follow superposition (09/10 dilution fix: Depth -4 then Height +1 must
	# leave Z untouched while adding Y — pooled averaging dragged Z +2mm).
	adjust_face_sculpt(&"EyeDepth", -4)
	var ez0 := _face_part_mean("Eyes")
	adjust_face_sculpt(&"EyeHeight", 1)
	var ez1 := _face_part_mean("Eyes")
	fails += _expect("follow no dilute z", absf(ez1.z - ez0.z) < 0.0005)
	fails += _expect("follow height adds", ez1.y > ez0.y + 0.0005)
	reset_face_sculpt(&"EyeDepth")
	reset_face_sculpt(&"EyeHeight")
	# EyeSpacing drags the balls + lashes per side (side-split means — a
	# global mean would cancel to ~0); Size/Angle are centroid-neutral so
	# the rigid parts correctly keep their pristine mesh.
	var esp0 := _face_part_side_x("Eyes")
	var espl0 := _face_part_side_x("Eyelashes")
	adjust_face_sculpt(&"EyeSpacing", 8)
	var esp1 := _face_part_side_x("Eyes")
	var espl1 := _face_part_side_x("Eyelashes")
	fails += _expect("eyes space out", esp1[0] < esp0[0] - 0.005 and esp1[1] > esp0[1] + 0.005)
	fails += _expect("lashes space out", espl1[0] < espl0[0] - 0.004 and espl1[1] > espl0[1] + 0.004)
	reset_face_sculpt(&"EyeSpacing")
	fails += _expect("eyes space restores", (_avatar.get_node_or_null("Eyes/Male_Eyes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyes"])
	fails += _expect("lashes space restores", (_avatar.get_node_or_null("Eyelashes/Male_Eyelashes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyelashes"])
	var esz0 := _face_part_side_radii("Eyes")
	var eslz0 := _face_part_side_radii("Eyelashes")
	adjust_face_sculpt(&"EyeSize", 8)
	var esz1 := _face_part_side_radii("Eyes")
	var eslz1 := _face_part_side_radii("Eyelashes")
	fails += _expect("eyes scale with size", esz1[0] > esz0[0] + 0.0008 and esz1[1] > esz0[1] + 0.0008)
	fails += _expect("lashes scale with size", eslz1[0] > eslz0[0] + 0.0005 and eslz1[1] > eslz0[1] + 0.0005)
	reset_face_sculpt(&"EyeSize")
	# Negative size (live clip report 10/10): the socket shrinks AND the
	# balls shrink with it — the aperture never gets smaller than the globe.
	adjust_face_sculpt(&"EyeSize", -8)
	var esz2 := _face_part_side_radii("Eyes")
	var eslz2 := _face_part_side_radii("Eyelashes")
	fails += _expect("eyes shrink with socket", esz2[0] < esz0[0] - 0.0008 and esz2[1] < esz0[1] - 0.0008)
	fails += _expect("lashes shrink with socket", eslz2[0] < eslz0[0] - 0.0005 and eslz2[1] < eslz0[1] - 0.0005)
	reset_face_sculpt(&"EyeSize")
	# Lashes ride the tilt (live report 10/10: they stayed straight): outer
	# lash verts drop with the lid margin.
	var lan0 := _face_part_verts("Eyelashes")
	var esr0 := _face_part_side_radii("Eyes")
	adjust_face_sculpt(&"EyeAngle", 8)
	fails += _expect("eyes tilt bakes", (_avatar.get_node_or_null("Eyes/Male_Eyes") as MeshInstance3D).mesh != _avatar._face_pristine["Eyes"])
	var esr1 := _face_part_side_radii("Eyes")
	fails += _expect("eyes tilt keeps shape", is_equal_approx(esr1[0], esr0[0]) and is_equal_approx(esr1[1], esr0[1]))
	var lan1 := _face_part_verts("Eyelashes")
	var lod := _face_part_outer_dy(lan0, lan1)
	fails += _expect("lashes ride tilt", int(lod[1]) > 0 and float(lod[0]) < -0.0005)
	reset_face_sculpt(&"EyeAngle")
	fails += _expect("lashes tilt restores", (_avatar.get_node_or_null("Eyelashes/Male_Eyelashes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyelashes"])
	# Brows ride their own tilt via total glue (same site-tracking as lashes).
	var brw0 := _face_part_verts("Eyebrows")
	adjust_face_sculpt(&"BrowAngle", 8)
	var brw1 := _face_part_verts("Eyebrows")
	var brd := _face_part_outer_dy(brw0, brw1)
	fails += _expect("brows ride tilt", int(brd[1]) > 0 and float(brd[0]) < -0.0005)
	reset_face_sculpt(&"BrowAngle")
	fails += _expect("brows tilt restores", (_avatar.get_node_or_null("Eyebrows/Male_Eyebrows") as MeshInstance3D).mesh == _avatar._face_pristine["Eyebrows"])
	# BrowThick dilates the mesh itself (live report 10/10: the skin-only
	# motion hid under the rigid part — mean ≈ 0 so nothing followed).
	var bth_before := _face_part_verts("Eyebrows")
	adjust_face_sculpt(&"BrowThick", 10)
	var bth_after := _face_part_verts("Eyebrows")
	var bth_grows := false
	if bth_before.size() == bth_after.size() and not bth_before.is_empty():
		var bmn0 := 1e9
		var bmx0 := -1e9
		var bmn1 := 1e9
		var bmx1 := -1e9
		for v in bth_before:
			bmn0 = minf(bmn0, v.y)
			bmx0 = maxf(bmx0, v.y)
		for v in bth_after:
			bmn1 = minf(bmn1, v.y)
			bmx1 = maxf(bmx1, v.y)
		bth_grows = (bmx1 - bmn1) > (bmx0 - bmn0) + 0.001
	fails += _expect("brows thicken", bth_grows)
	reset_face_sculpt(&"BrowThick")
	fails += _expect("brows thick restores", (_avatar.get_node_or_null("Eyebrows/Male_Eyebrows") as MeshInstance3D).mesh == _avatar._face_pristine["Eyebrows"])
	# Spacing superposes with depth (side-split + global bakes add without
	# touching each other's axis).
	adjust_face_sculpt(&"EyeDepth", -4)
	var ezs0 := _face_part_mean("Eyes")
	adjust_face_sculpt(&"EyeSpacing", 8)
	var ezs1 := _face_part_mean("Eyes")
	fails += _expect("follow spacing spares z", absf(ezs1.z - ezs0.z) < 0.0005)
	reset_face_sculpt(&"EyeDepth")
	reset_face_sculpt(&"EyeSpacing")
	# 9d. Hair follow (09/10 step 3): the hairline rides ForeheadHeight so
	# the skin never slides under the cards; unrelated parts stay pristine.
	adjust_hair(1) # mount Buzzed (male) for a measurable follow target
	var hbefore := _face_part_verts("Hair")
	var eyf0 := _face_part_mean("Eyes")
	var skf0 := _head_dom_verts()
	adjust_face_sculpt(&"ForeheadHeight", 8)
	var hafter := _face_part_verts("Hair")
	var eyf1 := _face_part_mean("Eyes")
	var skf1 := _head_dom_verts()
	# Weighted zone rises (front band past the ears plane; the global mean
	# is diluted by the frozen back mass, so measure the band, not the cap).
	var hsk := _avatar_skeleton()
	var hbi := hsk.find_bone(&"Head") if hsk != null else -1
	var front0 := 0.0
	var front1 := 0.0
	var frontn := 0
	var backmax := 0.0
	if hbi != -1 and hbefore.size() == hafter.size():
		var hinv: Transform3D = _avatar._bone_rest_world(hsk, hbi).affine_inverse()
		var earsz := _avatar.sculpt_region_center("Ears").z
		for i in hbefore.size():
			if (hinv * hbefore[i]).z > earsz:
				front0 += hbefore[i].y
				front1 += hafter[i].y
				frontn += 1
			else:
				backmax = maxf(backmax, hbefore[i].distance_to(hafter[i]))
	fails += _expect("hair follows forehead", frontn > 0 and (front1 - front0) / float(frontn) > 0.002)
	var sockv := _browprobe_region_vec(skf0, skf1, "Eyelids")
	var eyebv := eyf1 - eyf0
	fails += _expect("eyes ride forehead", sockv.length() < 1e-7 or eyebv.dot(sockv) > 0.0)
	reset_face_sculpt(&"ForeheadHeight")
	fails += _expect("eyes forehead restores", (_avatar.get_node_or_null("Eyes/Male_Eyes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyes"])
	fails += _expect("hair follow restores", (_avatar.get_node_or_null("Hair/Buzzed") as MeshInstance3D).mesh == _avatar._face_pristine["Hair"])
	reset_hair()
	# 9e. Width follow (09/10 live: temples clipped the hair sides): shell
	# vert copies its nearest skin vert's offset ("glue"), so the cap keeps
	# its rest gap both directions (ramp/full-width/column proxies all
	# failed live: starved temples, breathing cap, narrowing dive).
	adjust_hair(1)
	var wbefore := _face_part_verts("Hair")
	adjust_face_sculpt(&"ForeheadWidth", 8)
	var wafter := _face_part_verts("Hair")
	var wsk := _avatar_skeleton()
	var wbi := wsk.find_bone(&"Head") if wsk != null else -1
	var wb: Dictionary = _avatar.sculpt_region_bounds("Forehead")
	var near := 0.0
	var nearn := 0
	# Glue integrity (guards index/order drift between grid, fields and map):
	# far hair moves no more than its own skin does (old proxies breathed
	# 6mm over static skin), and the rest gap is small (mapping is sane).
	var over := 0.0
	var gap := 0.0
	var gapn := 0
	var gapmax := 0.0
	if wbi != -1 and wbefore.size() == wafter.size() and not wb.is_empty():
		var winv: Transform3D = _avatar._bone_rest_world(wsk, wbi).affine_inverse()
		var gqs: PackedVector3Array = _avatar._glue_qs
		var gfields: Dictionary = _avatar._glue_fields
		var hpris := _avatar._face_pristine.get("Hair") as ArrayMesh
		var gmap: PackedInt32Array = (_avatar._glue_map.get(hpris.get_rid().get_id(), PackedInt32Array()) as PackedInt32Array) if hpris != null else PackedInt32Array()
		for i in wbefore.size():
			var wq: Vector3 = winv * wbefore[i]
			var ww: float = _avatar.follow_halo_w(wq, wb["mn"], wb["mx"], _avatar.HAIR_HALO)
			if ww > 0.5:
				near += absf((winv * wafter[i]).x) - absf(wq.x)
				nearn += 1
			elif ww < 0.05 and i < gmap.size() and gmap[i] < gqs.size():
				var skoff := Vector3.ZERO
				for gk in gfields:
					skoff += (gfields[gk] as PackedVector3Array)[gmap[i]]
				over = maxf(over, wbefore[i].distance_to(wafter[i]) - skoff.length() - 0.001)
			if i % 5 == 0 and i < gmap.size() and gmap[i] < gqs.size():
				gap += wq.distance_to(gqs[gmap[i]])
				gapn += 1
				gapmax = maxf(gapmax, wq.distance_to(gqs[gmap[i]]))
	fails += _expect("hair column spreads", nearn > 0 and near / float(nearn) > 0.004)
	fails += _expect("hair never overshoots skin", over <= 0.0)
	fails += _expect("hair rest gap sane", gapn > 0 and gap / float(gapn) < 0.012 and gapmax < 0.025)
	# Negative Width (09/10 live: + fixed, - still clipped): the column must
	# narrow symmetric to the positive spread, never dive past the skin.
	adjust_face_sculpt(&"ForeheadWidth", -16)
	var wafter_neg := _face_part_verts("Hair")
	var spread_neg := 0.0
	var spreadn_neg := 0
	if wbi != -1 and wbefore.size() == wafter_neg.size() and not wb.is_empty():
		var winv2: Transform3D = _avatar._bone_rest_world(wsk, wbi).affine_inverse()
		for i in wbefore.size():
			var wq2: Vector3 = winv2 * wbefore[i]
			if _avatar.follow_halo_w(wq2, wb["mn"], wb["mx"], _avatar.HAIR_HALO) > 0.5:
				spread_neg += absf((winv2 * wafter_neg[i]).x) - absf(wq2.x)
				spreadn_neg += 1
	fails += _expect("hair column narrows", spreadn_neg > 0 and spread_neg / float(spreadn_neg) < -0.004)
	reset_face_sculpt(&"ForeheadWidth")
	fails += _expect("hair width restores", (_avatar.get_node_or_null("Hair/Buzzed") as MeshInstance3D).mesh == _avatar._face_pristine["Hair"])
	reset_hair()
	# 9f. Beard glue (jaw/chin rows drag the beard shell via nearest-skin
	# offsets, same path as hair — mouth/cheek rows stay out for now).
	adjust_beard(1)
	var bbefore := _face_part_verts("Beard")
	adjust_face_sculpt(&"JawWidth", 8)
	var bafter := _face_part_verts("Beard")
	var bspread := 0.0
	var bspreadn := 0
	if bbefore.size() == bafter.size():
		for i in bbefore.size():
			bspread += absf(bafter[i].x) - absf(bbefore[i].x)
			bspreadn += 1
	fails += _expect("beard follows jaw", bspreadn > 0 and bspread / float(bspreadn) > 0.002)
	reset_face_sculpt(&"JawWidth")
	adjust_face_sculpt(&"ChinProject", 10)
	var bafterp := _face_part_verts("Beard")
	var bpush := 0.0
	var bpushn := 0
	if bbefore.size() == bafterp.size():
		for i in bbefore.size():
			bpush += bafterp[i].z - bbefore[i].z
			bpushn += 1
	fails += _expect("beard follows chin out", bpushn > 0 and bpush / float(bpushn) > 0.0025)
	reset_face_sculpt(&"ChinProject")
	adjust_face_sculpt(&"ChinLength", 10)
	var bafterl := _face_part_verts("Beard")
	var bdrop := 0.0
	var bdropn := 0
	if bbefore.size() == bafterl.size():
		for i in bbefore.size():
			bdrop += bafterl[i].y - bbefore[i].y
			bdropn += 1
	fails += _expect("beard follows chin down", bdropn > 0 and bdrop / float(bdropn) < -0.0025)
	reset_face_sculpt(&"ChinLength")
	for bk in [&"JawWidth", &"JawDefinition", &"JawAngle", &"ChinShift", &"ChinLength", &"ChinWidth", &"ChinProject", &"ChinCleft", &"MouthW", &"LipUpper", &"LipLower", &"MouthCorners", &"MouthPosition", &"MouthForward", &"MouthPout"]:
		adjust_face_sculpt(bk, 8)
		fails += _expect("beard wired %s" % String(bk), (_avatar.get_node_or_null("Beard/Beard") as MeshInstance3D).mesh != _avatar._face_pristine["Beard"])
		reset_face_sculpt(bk)
	# Mustache rides the lips (live report: it stayed put): the moved set
	# (upper beard verts) advances with the pout.
	adjust_face_sculpt(&"MouthPout", 8)
	var bafterm := _face_part_verts("Beard")
	var mmove := 0.0
	var mmoven := 0
	if bbefore.size() == bafterm.size():
		for i in bbefore.size():
			var dzz: float = bafterm[i].z - bbefore[i].z
			if dzz > 0.001:
				mmove += dzz
				mmoven += 1
	fails += _expect("mustache follows mouth", mmoven > 0 and mmove / float(mmoven) > 0.003)
	# 9g. Root freeze (live theory 11/10: buried verts must stay buried —
	# glue dragged them through the skin where the stretch gradient is steep).
	# Signed rest depths: deep roots exist AND surface shell exists; under the
	# same Pout the deep set holds still while the surface rides the lips.
	var bdep := _avatar.glue_depth("Beard")
	var bdeepn := 0
	var bsurfn := 0
	for bd in bdep:
		if bd <= -_avatar.GLUE_ROOT_M:
			bdeepn += 1
		elif bd > -_avatar.GLUE_SKIN_M:
			bsurfn += 1
	fails += _expect("beard roots exist", bdeepn > 0 and bsurfn > 0)
	var bstalk := 0.0
	var bstalkn := 0
	if bdep.size() == bbefore.size() and bbefore.size() == bafterm.size():
		for i in bbefore.size():
			if bdep[i] <= -_avatar.GLUE_ROOT_M:
				bstalk += bbefore[i].distance_to(bafterm[i])
				bstalkn += 1
	fails += _expect("beard roots stay buried", bstalkn > 0 and bstalk / float(bstalkn) < 0.0002)
	reset_face_sculpt(&"MouthPout")
	fails += _expect("beard jaw restores", (_avatar.get_node_or_null("Beard/Beard") as MeshInstance3D).mesh == _avatar._face_pristine["Beard"])
	adjust_face_sculpt(&"EyeDepth", 8)
	fails += _expect("beard ignores eyes", (_avatar.get_node_or_null("Beard/Beard") as MeshInstance3D).mesh == _avatar._face_pristine["Beard"])
	reset_face_sculpt(&"EyeDepth")
	reset_beard()
	# 9h. Beard combo pins (live: ChinShift+10 + ChinProject clipped at the
	# chin front). Key-scoped gate: mouth keys freeze buried roots, jaw/chin
	# keys ride full. Bars: center-band shell shear in singles < 8mm (was a
	# 10mm gate cliff), zero fresh skin penetration in singles. The double
	# extreme combo keeps a known mask-boundary residual (accepted live).
	adjust_beard(1)
	reset_face_sculpt(&"ChinShift")
	reset_face_sculpt(&"ChinProject")
	var csk := _avatar_skeleton()
	var cbi := csk.find_bone(&"Head") if csk != null else -1
	var crest := _face_part_verts("Beard")
	var cpris := _avatar._face_pristine.get("Beard") as ArrayMesh
	if cbi != -1 and not crest.is_empty() and cpris != null:
		var cinv: Transform3D = _avatar._bone_rest_world(csk, cbi).affine_inverse()
		var bcp_proj := 0.0
		var bcs_shift := 0.0
		var bks_sp := 0
		for cfg in [&"combo", &"shift", &"project"]:
			if cfg == &"combo" or cfg == &"shift":
				adjust_face_sculpt(&"ChinShift", 10)
			if cfg == &"combo" or cfg == &"project":
				adjust_face_sculpt(&"ChinProject", 10)
			var cbaked := _face_part_verts("Beard")
			# Re-fetch after the bake: fusion drops grid+map on every skin
			# rebuild (new rid), the glue bake rebuilds them lazily.
			var cgmap: PackedInt32Array = (_avatar._glue_map.get(cpris.get_rid().get_id(), PackedInt32Array()) as PackedInt32Array)
			var cdep: PackedFloat32Array = _avatar.glue_depth("Beard")
			var cqs: PackedVector3Array = _avatar._glue_qs
			var cns: PackedVector3Array = _avatar._glue_ns
			var cf: Dictionary = _avatar._glue_fields
			var pn := 0
			var pworst := 0.0
			var pdeep := 0
			var pramp := 0
			var psurf := 0
			var pax := Vector3.ZERO
			var askn := 0.0
			var btr := 0.0
			var tdeep := 0
			var tramp := 0
			var tsurf := 0
			var ldeep := 0
			var lramp := 0
			var lsurf := 0
			var wdeep := 0.0
			var wramp := 0.0
			var wsurf := 0.0
			var sax := Vector3.ZERO
			var sn := 0
			var qrest := PackedVector3Array()
			var coffs := PackedVector3Array()
			if cbaked.size() == crest.size() and cgmap.size() == crest.size() and cdep.size() == crest.size() and cns.size() == cqs.size() and not cqs.is_empty():
				# Anchor-gap map (no pin: feeds qrest/coffs for the shear pass
				# below; zone/loss tallies kept as diagnostic scaffolding).
				for i in crest.size():
					if cdep[i] <= -_avatar.GLUE_ROOT_M:
						tdeep += 1
					elif cdep[i] <= -_avatar.GLUE_SKIN_M:
						tramp += 1
					else:
						tsurf += 1
					var ski: int = cgmap[i]
					var q: Vector3 = cinv * crest[i]
					var offb: Vector3 = (cinv * cbaked[i]) - q
					qrest.append(q)
					coffs.append(offb)
					if ski < 0 or ski >= cqs.size():
						continue
					var offs := Vector3.ZERO
					for gk in cf:
						offs += (cf[gk] as PackedVector3Array)[ski]
					var gapb: float = cdep[i] + (offb - offs).dot(cns[ski])
					var loss: float = (offb - offs).dot(cns[ski])
					if loss < -0.001:
						if cdep[i] <= -_avatar.GLUE_ROOT_M:
							ldeep += 1
							wdeep = minf(wdeep, loss)
						elif cdep[i] <= -_avatar.GLUE_SKIN_M:
							lramp += 1
							wramp = minf(wramp, loss)
						else:
							lsurf += 1
							wsurf = minf(wsurf, loss)
							sax += cqs[ski]
							sn += 1
					if gapb < -0.001:
						pn += 1
						pworst = minf(pworst, gapb)
						pax += cqs[ski]
						askn += offs.length()
						btr += offb.length()
						if cdep[i] <= -_avatar.GLUE_ROOT_M:
							pdeep += 1
						elif cdep[i] <= -_avatar.GLUE_SKIN_M:
							pramp += 1
						else:
							psurf += 1
				if pn > 0:
					pax /= float(pn)
				# Intra-shell shear + flipped tris (what the anchor gap can't
				# see: the shell tearing between static and dragged verts).
				var fliptot := 0
				var shearmax := 0.0
				var shearat := Vector3.ZERO
				var flipat := Vector3.ZERO
				var cshmax := 0.0
				var cshat := Vector3.ZERO
				var fbase := 0
				for fs in cpris.get_surface_count():
					var fsa: Array = cpris.surface_get_arrays(fs)
					var fsv: PackedVector3Array = fsa[Mesh.ARRAY_VERTEX]
					var fidx: PackedInt32Array = fsa[Mesh.ARRAY_INDEX]
					var ftris := PackedInt32Array()
					if fidx.is_empty():
						for fvv in fsv.size():
							ftris.append(fbase + fvv)
					else:
						for fvv in fidx.size():
							ftris.append(fbase + fidx[fvv])
					var ft := 0
					while ft + 2 < ftris.size():
						var fa := ftris[ft]
						var fb := ftris[ft + 1]
						var fc2 := ftris[ft + 2]
						if fa < qrest.size() and fb < qrest.size() and fc2 < qrest.size():
							var ab0: Vector3 = qrest[fb] - qrest[fa]
							var ac0: Vector3 = qrest[fc2] - qrest[fa]
							var ab1: Vector3 = ab0 + coffs[fb] - coffs[fa]
							var ac1: Vector3 = ac0 + coffs[fc2] - coffs[fa]
							var fn0: Vector3 = ab0.cross(ac0)
							var fn1: Vector3 = ab1.cross(ac1)
							if fn0.length_squared() > 0.0 and fn1.length_squared() > 0.0 and fn0.normalized().dot(fn1.normalized()) < 0.0:
								if fliptot == 0:
									flipat = (qrest[fa] + qrest[fb] + qrest[fc2]) / 3.0
								fliptot += 1
							var fsh: float = maxf((coffs[fa] - coffs[fb]).length(), maxf((coffs[fb] - coffs[fc2]).length(), (coffs[fc2] - coffs[fa]).length()))
							if fsh > shearmax:
								shearmax = fsh
								shearat = (qrest[fa] + qrest[fb] + qrest[fc2]) / 3.0
							var fmid: Vector3 = (qrest[fa] + qrest[fb] + qrest[fc2]) / 3.0
							if absf(fmid.x) < 0.015 and fsh > cshmax:
								cshmax = fsh
								cshat = fmid
						ft += 3
					fbase += fsv.size()
				# True clip test: surface beard verts vs NEAREST baked skin
				# (catches anchor mismatch — static fringe over moved skin).
				var kmi := _avatar_skin_mi()
				var kpr := _avatar._skin_pristine as ArrayMesh
				var kclipn := 0
				var kclipw := 0.0
				var kclipat := Vector3.ZERO
				var kdone := false
				if kmi != null and kmi.mesh != null and kpr != null and kmi.mesh.get_surface_count() == kpr.get_surface_count():
					var kbb := PackedVector3Array()
					var kbn := PackedVector3Array()
					var kok := true
					for ks in kmi.mesh.get_surface_count():
						var kba: Array = kmi.mesh.surface_get_arrays(ks)
						var kpa: Array = kpr.surface_get_arrays(ks)
						var kbv: PackedVector3Array = kba[Mesh.ARRAY_VERTEX]
						var kbn2: PackedVector3Array = kba[Mesh.ARRAY_NORMAL]
						if kbv.size() != (kpa[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() or kbn2.size() != kbv.size():
							kok = false
							break
						kbb.append_array(kbv)
						kbn.append_array(kbn2)
					if kok and not kbb.is_empty():
						kdone = true
						var kgrid := {}
						for kgi in kbb.size():
							var kcell := Vector3i(floori(kbb[kgi].x / 0.01), floori(kbb[kgi].y / 0.01), floori(kbb[kgi].z / 0.01))
							if not kgrid.has(kcell):
								kgrid[kcell] = []
							(kgrid[kcell] as Array).append(kgi)
						for ki in crest.size():
							if cdep[ki] <= -0.001:
								continue # buried at rest: not movement-caused
							var kbq: Vector3 = cbaked[ki]
							var kbc := Vector3i(floori(kbq.x / 0.01), floori(kbq.y / 0.01), floori(kbq.z / 0.01))
							var kbd := 1e18
							var kbi := -1
							var kr := 0
							while kr <= 15:
								for kdx in range(-kr, kr + 1):
									for kdy in range(-kr, kr + 1):
										for kdz in range(-kr, kr + 1):
											if maxi(maxi(absi(kdx), absi(kdy)), absi(kdz)) != kr:
												continue
											var klst: Array = kgrid.get(kbc + Vector3i(kdx, kdy, kdz), [])
											for kcand in klst:
												var kdd: float = kbb[int(kcand)].distance_squared_to(kbq)
												if kdd < kbd:
													kbd = kdd
													kbi = int(kcand)
								if kbi != -1 and sqrt(kbd) <= float(kr) * 0.01:
									break
								kr += 1
							if kbi != -1:
								var kgap: float = (kbq - kbb[kbi]).dot(kbn[kbi].normalized())
								if kgap < -0.001:
									kclipn += 1
									kclipw = minf(kclipw, kgap)
									kclipat += kbq
						if kclipn > 0:
							kclipat = cinv * (kclipat / float(kclipn))
				if not kdone:
					print("[CharTest] beard skinclip %s: unmeasurable" % String(cfg))
				if cfg == &"project":
					bcp_proj = cshmax
				if cfg == &"shift":
					bcs_shift = cshmax
				if cfg == &"shift" or cfg == &"project":
					bks_sp += kclipn
			else:
				print("[CharTest] beard %s: unmeasurable" % String(cfg))
			reset_face_sculpt(&"ChinShift")
			reset_face_sculpt(&"ChinProject")
		fails += _expect("beard chin rides project", bcp_proj < 0.008)
		fails += _expect("beard chin rides shift", bcs_shift < 0.008)
		fails += _expect("beard singles no clip", bks_sp == 0)
	else:
		print("[CharTest] beard combo: unmeasurable (no beard/head)")
	reset_beard()
	# 17c. EarSize spares the head (09/10 live: growing the ears grew the
	# skull side and clipped the hair). Tight Ears mask (flap only) + 1
	# diffusion ring: the skull (|x| < 65mm) barely moves, the flap does.
	adjust_face_sculpt(&"EarSize", 8)
	var esmax := 0.0
	var eflap := 0.0
	var esk := _avatar_skeleton()
	var ebi := esk.find_bone(&"Head") if esk != null else -1
	if ebi != -1:
		var einv: Transform3D = _avatar._bone_rest_world(esk, ebi).affine_inverse()
		var esmi := _avatar_skin_mi()
		var epris := _avatar._skin_pristine
		for _s in mini(esmi.mesh.get_surface_count(), epris.get_surface_count()):
			var ecv: PackedVector3Array = esmi.mesh.surface_get_arrays(_s)[Mesh.ARRAY_VERTEX]
			var epv: PackedVector3Array = epris.surface_get_arrays(_s)[Mesh.ARRAY_VERTEX]
			if ecv.size() != epv.size():
				continue
			for _i in ecv.size():
				var dd: float = ecv[_i].distance_to(epv[_i])
				if dd < 0.0005:
					continue
				var ax: float = absf((einv * epv[_i]).x)
				if ax < 0.065:
					esmax = maxf(esmax, dd)
				elif ax > 0.08:
					eflap = maxf(eflap, dd)
	fails += _expect("earsize spares skull", esmax < 0.002)
	fails += _expect("earsize grows flap", eflap > 0.004)
	reset_face_sculpt(&"EarSize")
	# 17d. Ear rows (rotation pivots per side, lobe/point ramp along Y):
	# symmetric swing, gradient bottom (lobe) / top (point), and motion
	# outside the mask confined to a 20mm transition band (halo smoothing,
	# not skull growth — the old bug dragged 9-11mm with the ear).
	var ecy: float = _avatar.sculpt_region_center("Ears").y
	var ebb: Dictionary = _avatar.sculpt_region_bounds("Ears")
	for ek in [&"EarRotation", &"EarlobeLength", &"EarPoint"]:
		adjust_face_sculpt(ek, 8)
		var emaxl := 0.0
		var emaxr := 0.0
		var eskull := 0.0
		var ebot := 0.0
		var ebotn := 0
		var etop := 0.0
		var etopn := 0
		var elob := 0.0
		var elobn := 0
		var etip := 0.0
		var etipn := 0
		var eband := 0.0
		if ebi != -1 and not ebb.is_empty():
			var einv3: Transform3D = _avatar._bone_rest_world(esk, ebi).affine_inverse()
			var emn: Vector3 = ebb["mn"]
			var emx: Vector3 = ebb["mx"]
			var esmi3 := _avatar_skin_mi()
			var epris3 := _avatar._skin_pristine
			for _s3 in mini(esmi3.mesh.get_surface_count(), epris3.get_surface_count()):
				var ecv3: PackedVector3Array = esmi3.mesh.surface_get_arrays(_s3)[Mesh.ARRAY_VERTEX]
				var epv3: PackedVector3Array = epris3.surface_get_arrays(_s3)[Mesh.ARRAY_VERTEX]
				if ecv3.size() != epv3.size():
					continue
				for _i3 in ecv3.size():
					var eq3: Vector3 = einv3 * epv3[_i3]
					var ed3: Vector3 = ecv3[_i3] - epv3[_i3]
					if ek == &"EarlobeLength" and _avatar.sculpt_in_region("Lobe", eq3):
						elob += ed3.y
						elobn += 1
					if ek == &"EarPoint" and _avatar.sculpt_in_region("EarTip", eq3):
						etip += ed3.y
						etipn += 1
					if absf(eq3.x) < 0.065:
						eskull = maxf(eskull, ed3.length())
						continue
					if absf(eq3.x) < 0.07 or eq3.y < 0.045 or eq3.y > 0.12:
						continue
					if eq3.x < 0.0:
						emaxl = maxf(emaxl, ed3.length())
					else:
						emaxr = maxf(emaxr, ed3.length())
					if eq3.y < ecy:
						ebot += ed3.y
						ebotn += 1
					else:
						etop += ed3.y
						etopn += 1
			for _s4 in mini(esmi3.mesh.get_surface_count(), epris3.get_surface_count()):
				var ecv4: PackedVector3Array = esmi3.mesh.surface_get_arrays(_s4)[Mesh.ARRAY_VERTEX]
				var epv4: PackedVector3Array = epris3.surface_get_arrays(_s4)[Mesh.ARRAY_VERTEX]
				if ecv4.size() != epv4.size():
					continue
				for _i4 in ecv4.size():
					if ecv4[_i4].distance_to(epv4[_i4]) < 0.001:
						continue
					var eq4: Vector3 = einv3 * epv4[_i4]
					var edd := Vector3(maxf(emn.x - eq4.x, 0.0) + maxf(eq4.x - emx.x, 0.0), maxf(emn.y - eq4.y, 0.0) + maxf(eq4.y - emx.y, 0.0), maxf(emn.z - eq4.z, 0.0) + maxf(eq4.z - emx.z, 0.0))
					eband = maxf(eband, edd.length())
		if ek == &"EarRotation":
			fails += _expect("ear rotation swings", emaxl > 0.002 and emaxr > 0.002)
			fails += _expect("ear rotation symmetric", absf(emaxl - emaxr) / maxf(maxf(emaxl, emaxr), 1e-9) < 0.25)
		elif ek == &"EarlobeLength":
			fails += _expect("earlobe drops", elobn > 0 and elob / float(elobn) < -0.0015)
			fails += _expect("earlobe gradient", etopn == 0 or absf(etop / float(etopn)) < 0.0008)
		else:
			fails += _expect("earpoint rises", etipn > 0 and etip / float(etipn) > 0.0015)
			fails += _expect("earpoint gradient", ebotn == 0 or absf(ebot / float(ebotn)) < 0.0008)
		fails += _expect("ear row transition band", eband < 0.020)
		reset_face_sculpt(ek)
	# 17e. Eye rows (per-side socket math on the Eyelids islands): spacing
	# shifts each orbit as a block, size dilates about the side centroid,
	# angle tilts about it mirrored (+ = outer corners drop). Halo confined
	# to a 20mm band, symmetric both sides.
	var lidx: float = _avatar.sculpt_region_center("Eyelids").x
	var lb5: Dictionary = _avatar.sculpt_region_bounds("Eyelids")
	for ek2 in [&"EyeSpacing", &"EyeSize", &"EyeAngle"]:
		adjust_face_sculpt(ek2, 8)
		var ldx := 0.0
		var ldxn := 0
		var rdx := 0.0
		var rdxn := 0
		var cl5 := Vector3.ZERO
		var cln5 := 0
		var cr5 := Vector3.ZERO
		var crn5 := 0
		var emaxl5 := 0.0
		var emaxr5 := 0.0
		var rl0 := 0.0
		var rl1 := 0.0
		var rln := 0
		var ody := 0.0
		var odyn := 0
		var eband5 := 0.0
		if ebi != -1 and not lb5.is_empty():
			var einv5: Transform3D = _avatar._bone_rest_world(esk, ebi).affine_inverse()
			var lmn5: Vector3 = lb5["mn"]
			var lmx5: Vector3 = lb5["mx"]
			var esmi5 := _avatar_skin_mi()
			var epris5 := _avatar._skin_pristine
			for _s5 in mini(esmi5.mesh.get_surface_count(), epris5.get_surface_count()):
				var ecv5: PackedVector3Array = esmi5.mesh.surface_get_arrays(_s5)[Mesh.ARRAY_VERTEX]
				var epv5: PackedVector3Array = epris5.surface_get_arrays(_s5)[Mesh.ARRAY_VERTEX]
				if ecv5.size() != epv5.size():
					continue
				for _i5 in ecv5.size():
					var eq5: Vector3 = einv5 * epv5[_i5]
					if not _avatar.sculpt_in_region("Eyelids", eq5):
						continue
					var ed5: Vector3 = ecv5[_i5] - epv5[_i5]
					if eq5.x < lidx:
						cl5 += eq5
						cln5 += 1
						ldx += ed5.x
						ldxn += 1
						emaxl5 = maxf(emaxl5, ed5.length())
					else:
						cr5 += eq5
						crn5 += 1
						rdx += ed5.x
						rdxn += 1
						emaxr5 = maxf(emaxr5, ed5.length())
			if cln5 > 0:
				cl5 /= float(cln5)
			if crn5 > 0:
				cr5 /= float(crn5)
			if ek2 != &"EyeSpacing":
				for _s6 in mini(esmi5.mesh.get_surface_count(), epris5.get_surface_count()):
					var ecv6: PackedVector3Array = esmi5.mesh.surface_get_arrays(_s6)[Mesh.ARRAY_VERTEX]
					var epv6: PackedVector3Array = epris5.surface_get_arrays(_s6)[Mesh.ARRAY_VERTEX]
					if ecv6.size() != epv6.size():
						continue
					for _i6 in ecv6.size():
						var eq6: Vector3 = einv5 * epv6[_i6]
						if not _avatar.sculpt_in_region("Eyelids", eq6):
							continue
						var ed6: Vector3 = ecv6[_i6] - epv6[_i6]
						if ek2 == &"EyeSize":
							var sc6: Vector3 = cl5 if eq6.x < lidx else cr5
							rl0 += eq6.distance_to(sc6)
							rl1 += (eq6 + ed6).distance_to(sc6)
							rln += 1
						elif (eq6.x < lidx and eq6.x < cl5.x) or (eq6.x >= lidx and eq6.x > cr5.x):
							ody += ed6.y
							odyn += 1
			for _s7 in mini(esmi5.mesh.get_surface_count(), epris5.get_surface_count()):
				var ecv7: PackedVector3Array = esmi5.mesh.surface_get_arrays(_s7)[Mesh.ARRAY_VERTEX]
				var epv7: PackedVector3Array = epris5.surface_get_arrays(_s7)[Mesh.ARRAY_VERTEX]
				if ecv7.size() != epv7.size():
					continue
				for _i7 in ecv7.size():
					if ecv7[_i7].distance_to(epv7[_i7]) < 0.001:
						continue
					var eq7: Vector3 = einv5 * epv7[_i7]
					var edd7 := Vector3(maxf(lmn5.x - eq7.x, 0.0) + maxf(eq7.x - lmx5.x, 0.0), maxf(lmn5.y - eq7.y, 0.0) + maxf(eq7.y - lmx5.y, 0.0), maxf(lmn5.z - eq7.z, 0.0) + maxf(eq7.z - lmx5.z, 0.0))
					eband5 = maxf(eband5, edd7.length())
		if ek2 == &"EyeSpacing":
			fails += _expect("eyespace spreads", ldxn > 0 and rdxn > 0 and ldx / float(ldxn) < -0.005 and rdx / float(rdxn) > 0.005)
			fails += _expect("eyespace symmetric", absf(emaxl5 - emaxr5) / maxf(maxf(emaxl5, emaxr5), 1e-9) < 0.25)
		elif ek2 == &"EyeSize":
			fails += _expect("eyesize dilates", rln > 0 and (rl1 - rl0) / float(rln) > 0.001)
			fails += _expect("eyesize symmetric", absf(emaxl5 - emaxr5) / maxf(maxf(emaxl5, emaxr5), 1e-9) < 0.25)
		else:
			fails += _expect("eyeangle drops outer", odyn > 0 and ody / float(odyn) < -0.0008)
			fails += _expect("eyeangle symmetric", absf(emaxl5 - emaxr5) / maxf(maxf(emaxl5, emaxr5), 1e-9) < 0.25)
		# rings:3 rows (like Depth/Height) carry a ~21mm halo by design;
		# the pin guards skull-dragging, not the designed falloff.
		var band5 := 0.025 if ek2 == &"EyeSpacing" else 0.020
		fails += _expect("eye row transition band", eband5 < band5)
		reset_face_sculpt(ek2)
	# 17f. BrowAngle (siderot on the Brows islands, same convention as
	# EyeAngle: + = outer corners drop). Symmetric swing, halo band.
	var brcx: float = _avatar.sculpt_region_center("Brows").x
	var brb: Dictionary = _avatar.sculpt_region_bounds("Brows")
	adjust_face_sculpt(&"BrowAngle", 8)
	var brmaxl := 0.0
	var brmaxr := 0.0
	var brody := 0.0
	var brodyn := 0
	var brband := 0.0
	if ebi != -1 and not brb.is_empty():
		var brinv: Transform3D = _avatar._bone_rest_world(esk, ebi).affine_inverse()
		var brmn: Vector3 = brb["mn"]
		var brmx: Vector3 = brb["mx"]
		var brmi := _avatar_skin_mi()
		var brpris := _avatar._skin_pristine
		var brcl := Vector3.ZERO
		var brcr := Vector3.ZERO
		var brcln := 0
		var brcrn := 0
		for _s8 in mini(brmi.mesh.get_surface_count(), brpris.get_surface_count()):
			var bcv8: PackedVector3Array = brmi.mesh.surface_get_arrays(_s8)[Mesh.ARRAY_VERTEX]
			var bpv8: PackedVector3Array = brpris.surface_get_arrays(_s8)[Mesh.ARRAY_VERTEX]
			if bcv8.size() != bpv8.size():
				continue
			for _i8 in bcv8.size():
				var bq8: Vector3 = brinv * bpv8[_i8]
				if not _avatar.sculpt_in_region("Brows", bq8):
					continue
				var bd8: Vector3 = bcv8[_i8] - bpv8[_i8]
				if bq8.x < brcx:
					brcl += bq8
					brcln += 1
					brmaxl = maxf(brmaxl, bd8.length())
				else:
					brcr += bq8
					brcrn += 1
					brmaxr = maxf(brmaxr, bd8.length())
		if brcln > 0:
			brcl /= float(brcln)
		if brcrn > 0:
			brcr /= float(brcrn)
		for _s9 in mini(brmi.mesh.get_surface_count(), brpris.get_surface_count()):
			var bcv9: PackedVector3Array = brmi.mesh.surface_get_arrays(_s9)[Mesh.ARRAY_VERTEX]
			var bpv9: PackedVector3Array = brpris.surface_get_arrays(_s9)[Mesh.ARRAY_VERTEX]
			if bcv9.size() != bpv9.size():
				continue
			for _i9 in bcv9.size():
				var bq9: Vector3 = brinv * bpv9[_i9]
				if not _avatar.sculpt_in_region("Brows", bq9):
					continue
				var bd9: Vector3 = bcv9[_i9] - bpv9[_i9]
				if (bq9.x < brcx and bq9.x < brcl.x) or (bq9.x >= brcx and bq9.x > brcr.x):
					brody += bd9.y
					brodyn += 1
		for _sA in mini(brmi.mesh.get_surface_count(), brpris.get_surface_count()):
			var bcvA: PackedVector3Array = brmi.mesh.surface_get_arrays(_sA)[Mesh.ARRAY_VERTEX]
			var bpvA: PackedVector3Array = brpris.surface_get_arrays(_sA)[Mesh.ARRAY_VERTEX]
			if bcvA.size() != bpvA.size():
				continue
			for _iA in bcvA.size():
				if bcvA[_iA].distance_to(bpvA[_iA]) < 0.001:
					continue
				var bqA: Vector3 = brinv * bpvA[_iA]
				var bddA := Vector3(maxf(brmn.x - bqA.x, 0.0) + maxf(bqA.x - brmx.x, 0.0), maxf(brmn.y - bqA.y, 0.0) + maxf(bqA.y - brmx.y, 0.0), maxf(brmn.z - bqA.z, 0.0) + maxf(bqA.z - brmx.z, 0.0))
				brband = maxf(brband, bddA.length())
	fails += _expect("browangle drops outer", brodyn > 0 and brody / float(brodyn) < -0.0008)
	fails += _expect("browangle symmetric", absf(brmaxl - brmaxr) / maxf(maxf(brmaxl, brmaxr), 1e-9) < 0.25)
	# Coarse brow mesh (~8mm edges): the rings:3 halo reaches 25.4mm by
	# design (smooth — the cliff pin guards the visible crease, not this).
	fails += _expect("brow row transition band", brband < 0.030)
	reset_face_sculpt(&"BrowAngle")
	# 17g. Jaw rows (same corner, two reads): Definition swings it (siderot,
	# + = corner drops/tucks), Angle lifts it (tip on the lower band, + =
	# gonions rise = steep jawline). Symmetric, halo band.
	var jcx: float = _avatar.sculpt_region_center("Jaw").x
	var jcb: Dictionary = _avatar.sculpt_region_bounds("Jaw")
	for ek3 in [&"JawDefinition", &"JawAngle"]:
		adjust_face_sculpt(ek3, 8)
		var jcl := Vector3.ZERO
		var jcln := 0
		var jcr := Vector3.ZERO
		var jcrn := 0
		var jmaxl := 0.0
		var jmaxr := 0.0
		var jlow := 0.0
		var jlown := 0
		var jband := 0.0
		if ebi != -1 and not jcb.is_empty():
			var jinv: Transform3D = _avatar._bone_rest_world(esk, ebi).affine_inverse()
			var jmn: Vector3 = jcb["mn"]
			var jmx: Vector3 = jcb["mx"]
			var jsmi := _avatar_skin_mi()
			var jpris := _avatar._skin_pristine
			for _sB in mini(jsmi.mesh.get_surface_count(), jpris.get_surface_count()):
				var jcvB: PackedVector3Array = jsmi.mesh.surface_get_arrays(_sB)[Mesh.ARRAY_VERTEX]
				var jpvB: PackedVector3Array = jpris.surface_get_arrays(_sB)[Mesh.ARRAY_VERTEX]
				if jcvB.size() != jpvB.size():
					continue
				for _iB in jcvB.size():
					var jqB: Vector3 = jinv * jpvB[_iB]
					if not _avatar.sculpt_in_region("Jaw", jqB):
						continue
					var jdB: Vector3 = jcvB[_iB] - jpvB[_iB]
					if jqB.x < jcx:
						jcl += jqB
						jcln += 1
						jmaxl = maxf(jmaxl, jdB.length())
					else:
						jcr += jqB
						jcrn += 1
						jmaxr = maxf(jmaxr, jdB.length())
			if jcln > 0:
				jcl /= float(jcln)
			if jcrn > 0:
				jcr /= float(jcrn)
			for _sC in mini(jsmi.mesh.get_surface_count(), jpris.get_surface_count()):
				var jcvC: PackedVector3Array = jsmi.mesh.surface_get_arrays(_sC)[Mesh.ARRAY_VERTEX]
				var jpvC: PackedVector3Array = jpris.surface_get_arrays(_sC)[Mesh.ARRAY_VERTEX]
				if jcvC.size() != jpvC.size():
					continue
				for _iC in jcvC.size():
					var jqC: Vector3 = jinv * jpvC[_iC]
					if not _avatar.sculpt_in_region("Jaw", jqC):
						continue
					var jdC: Vector3 = jcvC[_iC] - jpvC[_iC]
					if ek3 == &"JawDefinition":
						# Rotation drops the OUTER corner (past the side
						# centroid, like eyes/brows) — the lower band
						# mixes rising inner verts, mean would cancel.
						if (jqC.x < jcx and jqC.x < jcl.x) or (jqC.x >= jcx and jqC.x > jcr.x):
							jlow += jdC.y
							jlown += 1
					else:
						var jsc: Vector3 = jcl if jqC.x < jcx else jcr
						if jqC.y < jsc.y:
							jlow += jdC.y
							jlown += 1
			for _sD in mini(jsmi.mesh.get_surface_count(), jpris.get_surface_count()):
				var jcvD: PackedVector3Array = jsmi.mesh.surface_get_arrays(_sD)[Mesh.ARRAY_VERTEX]
				var jpvD: PackedVector3Array = jpris.surface_get_arrays(_sD)[Mesh.ARRAY_VERTEX]
				if jcvD.size() != jpvD.size():
					continue
				for _iD in jcvD.size():
					if jcvD[_iD].distance_to(jpvD[_iD]) < 0.001:
						continue
					var jqD: Vector3 = jinv * jpvD[_iD]
					var jddD := Vector3(maxf(jmn.x - jqD.x, 0.0) + maxf(jqD.x - jmx.x, 0.0), maxf(jmn.y - jqD.y, 0.0) + maxf(jqD.y - jmx.y, 0.0), maxf(jmn.z - jqD.z, 0.0) + maxf(jqD.z - jmx.z, 0.0))
					jband = maxf(jband, jddD.length())
		if ek3 == &"JawDefinition":
			fails += _expect("jawdef drops corner", jlown > 0 and jlow / float(jlown) < -0.0008)
			fails += _expect("jawdef symmetric", absf(jmaxl - jmaxr) / maxf(maxf(jmaxl, jmaxr), 1e-9) < 0.25)
		else:
			fails += _expect("jawangle lifts corner", jlown > 0 and jlow / float(jlown) > 0.003)
			fails += _expect("jawangle symmetric", absf(jmaxl - jmaxr) / maxf(maxf(jmaxl, jmaxr), 1e-9) < 0.25)
		fails += _expect("jaw row transition band", jband < 0.020)
		reset_face_sculpt(ek3)
	# 10. Beard submenu (single vendor file now, more later — albedo like hair).
	fails += _expect("beard none default", beard_display() == "None" and beard_file("Male", &"None").is_empty())
	fails += _expect("beard file male", beard_file("Male", &"Beard").ends_with("Hair_Beard.gltf"))
	open_color(&"Beard")
	fails += _expect("beard color empty no-op", not is_color_open())
	adjust_beard(1)
	fails += _expect("beard style shown", beard_display() == "Beard")
	var bmi := _avatar.get_node_or_null("Beard/Beard") as MeshInstance3D
	fails += _expect("beard mounted", bmi != null and bmi.mesh != null)
	fails += _expect("beard on master", bmi != null and hmaster != null and bmi.get_node_or_null(bmi.skeleton) == hmaster)
	open_color(&"Beard")
	fails += _expect("beard color opens", is_color_open())
	fails += _expect("beard defaults mid", is_equal_approx(float(_dresser.current_params()["sat"]), 0.5) and is_equal_approx(float(_dresser.current_params()["val"]), 0.5))
	_dresser._params = {"hue": 10.0, "sat": 0.7, "val": 0.5}
	_dresser._apply()
	var want_beard := Color.from_hsv(10.0 / 360.0, 0.7, 0.5)
	fails += _expect("beard albedo written", ((bmi.mesh as ArrayMesh) != null and ((_slot_mats(&"Beard")[0] as ShaderMaterial).get_shader_parameter("albedo") as Color).is_equal_approx(want_beard)))
	fails += _expect("beard shift neutral", is_equal_approx(float((_slot_mats(&"Beard")[0] as ShaderMaterial).get_shader_parameter("hue_shift_deg")), 0.0))
	_dresser._confirm()
	fails += _expect("beard color stored", _avatar._color_params.has(&"Beard"))
	reset_beard()
	fails += _expect("beard reset clean", beard_display() == "None" and _avatar.get_node_or_null("Beard/Beard") == null)
	_menu._push(CharacterMenu.LEVEL_BEARD)
	fails += _expect("menu beard rows", _menu._entries.size() == 3)
	fails += _expect("face cam on beard", face_active())
	_menu._pop()
	fails += _expect("face beard back to hub", _menu._level == CharacterMenu.LEVEL_FACE and face_active())
	_menu._pop()
	fails += _expect("face cam off beard", not face_active())
	# 11. Face submenu (global head form over the Head size row).
	fails += _expect("face width default", face_shape_display(&"Width") == "100%")
	fails += _expect("face length default", face_shape_display(&"Length") == "100%")
	adjust_face_shape(&"Width", 2)
	fails += _expect("face width shown", face_shape_display(&"Width") == "102%")
	fails += _expect("face width XZ only", sk.get_bone_pose_scale(sk.find_bone(&"Head")).is_equal_approx(Vector3(1.02, 1.0, 1.02)))
	adjust_face_shape(&"Length", 3)
	fails += _expect("face length Y only", sk.get_bone_pose_scale(sk.find_bone(&"Head")).is_equal_approx(Vector3(1.02, 1.03, 1.02)))
	reset_face_shape(&"Length")
	adjust_phys(&"Head", 2) # size row multiplies: X = 1.02 * 1.02
	fails += _expect("face over head size", sk.get_bone_pose_scale(sk.find_bone(&"Head")).is_equal_approx(Vector3(1.0404, 1.02, 1.0404)))
	reset_phys(&"Head")
	reset_face_shape(&"Width")
	fails += _expect("face reset neutral", sk.get_bone_pose_scale(sk.find_bone(&"Head")).is_equal_approx(Vector3.ONE))
	adjust_face_shape(&"Width", 50)
	fails += _expect("face width clamped", face_shape_display(&"Width") == "110%")
	reset_face_shape(&"Width")
	adjust_face_shape(&"Length", -50)
	fails += _expect("face length clamped", face_shape_display(&"Length") == "90%")
	reset_face_shape(&"Length")
	# 11b. Cursor memory (09/10): entering tops, Back restores the parent pick.
	_menu._cursor = 5
	_menu._push(CharacterMenu.LEVEL_FACE)
	fails += _expect("menu push tops", _menu._cursor == 0)
	_menu._cursor = 2
	_menu._push(CharacterMenu.LEVEL_FACE_MOUTH)
	fails += _expect("menu sub tops", _menu._cursor == 0)
	_menu._pop()
	fails += _expect("menu back restores", _menu._level == CharacterMenu.LEVEL_FACE and _menu._cursor == 2)
	_menu._pop()
	fails += _expect("menu root restores", _menu._level == CharacterMenu.LEVEL_ROOT and _menu._cursor == 5)
	# 11c. Face view stability (09/10): submenu hops never move the camera;
	# rebuilds re-aim the pivot but keep the user's zoom; leaving restores.
	var cam := _world().get_node_or_null("CamPivot/SpringArm3D/Camera3D") as Camera3D
	fails += _expect("editor camera centered", cam != null and is_zero_approx(cam.position.x))
	# 11d. Preview world (10/10): mannequin + camera live in the right-of-menu
	# SubViewport, sized to the visible area (crisp 1:1, no stretch skew).
	var w := _world()
	var cont := get_node_or_null("ViewportContainer") as SubViewportContainer
	fails += _expect("world right of menu", w != null and cont != null and is_equal_approx(cont.offset_left, WORLD_MENU_WIDTH))
	fails += _expect("world sized visible", w != null and w.size.x >= 320 and w.size.y >= 240)
	fails += _expect("avatar in world", _avatar != null and _avatar.get_parent() == w)
	fails += _expect("camera in world", cam != null and cam.get_viewport() == w)
	_menu._push(CharacterMenu.LEVEL_FACE)
	var arm2 := (pivot.get_node_or_null("SpringArm3D") as SpringArm3D) if pivot != null else null
	if arm2 != null:
		arm2.spring_length = 1.5 # user zoom while inside Face
	var piv0: Vector3 = pivot.position if pivot != null else Vector3.ZERO
	_menu._push(CharacterMenu.LEVEL_FACE_MOUTH)
	fails += _expect("face hop keeps zoom", arm2 != null and is_equal_approx(arm2.spring_length, 1.5))
	fails += _expect("face hop keeps pivot", pivot != null and pivot.position.is_equal_approx(piv0))
	_menu._pop()
	fails += _expect("face hub keeps zoom", arm2 != null and is_equal_approx(arm2.spring_length, 1.5))
	if pivot != null:
		pivot.position = Vector3.ZERO
	face_reanchor()
	fails += _expect("rebuild re-aims pivot", pivot != null and pivot.position.is_equal_approx(_head_world() + Vector3.UP * FACE_AIM_UP))
	fails += _expect("reanchor keeps zoom", arm2 != null and is_equal_approx(arm2.spring_length, 1.5))
	_menu._pop()
	fails += _expect("face exit restores zoom", arm2 != null and is_equal_approx(arm2.spring_length, 3.2))
	_menu._push(CharacterMenu.LEVEL_FACE)
	fails += _expect("menu face hub 11+2debug+back", _menu._entries.size() == CharacterMenu.FACE_SUBS.size() + CharacterMenu.FACE_PARTS.size() + 2 + 1)
	fails += _expect("face cam on hub", face_active())
	fails += _expect("face pauses idle", _anim_paused == _idle_only)
	var hub_labels := []
	for e in _menu._entries:
		hub_labels.append(String((e as Dictionary).get("label", "")))
	fails += _expect("menu hub head grouped", hub_labels.has("Hair >") and hub_labels.has("Eyebrows >") and hub_labels.has("Eyelashes >") and hub_labels.has("Eyes >") and hub_labels.has("Beard >"))
	fails += _expect("menu hub debug rows", hub_labels.has("Random Face") and hub_labels.has("Reset Face"))
	# TEMP debug rows: draw moves the mesh, full reset restores it (both
	# genders already covered — here male, female parity ratios in §17).
	randomize_face()
	fails += _expect("random face moves", _avatar.sculpt_max_cliff() > 1e-9)
	reset_face_all()
	fails += _expect("face debug restores", _avatar.sculpt_max_cliff() < 1e-9)
	# Field-cache exactness: a cached bake must equal a fresh full recompute.
	randomize_face()
	var csum := _avatar.sculpt_checksum()
	_avatar.sculpt_drop_cache()
	_avatar.fuse_sculpt()
	fails += _expect("field cache exact", _avatar.sculpt_checksum().is_equal_approx(csum))
	reset_face_all()
	# Correlated draw: deterministic per seed (RNG order + coupling math),
	# clamped to the draw range, coupling table valid.
	randomize_face(12345)
	var snap0 := (_avatar.get("_sculpt") as Dictionary).duplicate()
	var inrange := true
	for key in CharacterAvatar.SCULPT_KEYS:
		if absf(float(snap0.get(key, 0.0))) > _face_max_cm(key) * 0.6 + 1e-6:
			inrange = false
	reset_face_all()
	randomize_face(12345)
	var snap1 := (_avatar.get("_sculpt") as Dictionary).duplicate()
	var same := true
	for key in CharacterAvatar.SCULPT_KEYS:
		if float(snap0.get(key, 0.0)) != float(snap1.get(key, 0.0)):
			same = false
	reset_face_all()
	fails += _expect("random deterministic", same)
	fails += _expect("random in range", inrange)
	var nactive := 0
	for key in CharacterAvatar.SCULPT_KEYS:
		if absf(float(snap1.get(key, 0.0))) > 1e-9:
			nactive += 1
	fails += _expect("random sparse count", nactive >= RANDOM_MIN_KEYS and nactive <= RANDOM_MAX_KEYS)
	var coup_ok := not _face_coupling().is_empty()
	for ck in _face_coupling():
		for pair in (_face_coupling()[ck] as Array):
			if not CharacterAvatar.SCULPT_KEYS.has(ck) or not CharacterAvatar.SCULPT_KEYS.has(pair[0] as StringName) or absf(float(pair[1])) > 1.0:
				coup_ok = false
	fails += _expect("coupling table valid", coup_ok)
	# Each sub: its rows + Back; Back returns to the hub (two-level Back).
	_menu._push(CharacterMenu.LEVEL_FACE_GLOBAL)
	fails += _expect("menu face global rows", _menu._entries.size() == CharacterAvatar.FACE_KEYS.size() + 1)
	fails += _expect("face cam on sub", face_active())
	_menu._pop()
	fails += _expect("menu back to hub", _menu._level == CharacterMenu.LEVEL_FACE and _menu._entries.size() == CharacterMenu.FACE_SUBS.size() + CharacterMenu.FACE_PARTS.size() + 2 + 1)
	fails += _expect("face cam stays on hub", face_active())
	_menu._push(CharacterMenu.LEVEL_FACE_NOSE)
	fails += _expect("menu face nose rows", _menu._entries.size() == 10 + 1)
	# 11b. Menu wiring (live report 08/10: a row seemingly driving another).
	# Drives EVERY nose row through its own entry callables: the row's own
	# key must read +1mm, all others +0mm, then reset restores.
	reset_face_sculpt(&"NoseWidth")
	reset_face_sculpt(&"NoseCurve")
	var wrow := {}
	for e in _menu._entries:
		if String((e as Dictionary).get("label", "")) == "NoseWidth":
			wrow = e
	if wrow.is_empty():
		fails += _expect("menu noseW row present", false)
	else:
		(wrow["adjust"] as Callable).call(1)
		fails += _expect("menu noseW drives noseW", face_sculpt_display(&"NoseWidth") == "+1mm")
		fails += _expect("menu noseW spares curve", face_sculpt_display(&"NoseCurve") == "+0mm")
		(wrow["reset"] as Callable).call()
		fails += _expect("menu noseW reset", face_sculpt_display(&"NoseWidth") == "+0mm")
	for e in _menu._entries:
		var ed := e as Dictionary
		if String(ed.get("kind", "")) != "value":
			continue
		var lbl := String(ed.get("label", ""))
		for k in CharacterAvatar.SCULPT_KEYS:
			reset_face_sculpt(k)
		(ed["adjust"] as Callable).call(1)
		fails += _expect("menu %s drives itself" % lbl, face_sculpt_display(StringName(lbl)) == "+1mm")
		var others := 0
		for k in CharacterAvatar.SCULPT_KEYS:
			if String(k) != lbl and face_sculpt_display(k) != "+0mm":
				others += 1
		fails += _expect("menu %s spares others" % lbl, others == 0)
		(ed["reset"] as Callable).call()
	_menu._pop()
	_menu._push(CharacterMenu.LEVEL_FACE_MOUTH)
	fails += _expect("menu face mouth rows", _menu._entries.size() == 7 + 1)
	_menu._pop()
	_menu._push(CharacterMenu.LEVEL_FACE_EYES)
	fails += _expect("menu face eyes rows", _menu._entries.size() == 8 + 1)
	_menu._pop()
	_menu._push(CharacterMenu.LEVEL_EYEBROWS)
	fails += _expect("menu face brows rows", _menu._entries.size() == 6 + 1)
	_menu._pop()
	_menu._push(CharacterMenu.LEVEL_FACE_JAW)
	fails += _expect("menu face jaw rows", _menu._entries.size() == 8 + 1)
	_menu._pop()
	_menu._push(CharacterMenu.LEVEL_FACE_CHEEKS)
	fails += _expect("menu face cheeks rows", _menu._entries.size() == 4 + 1)
	_menu._pop()
	_menu._push(CharacterMenu.LEVEL_FACE_FOREHEAD)
	fails += _expect("menu face forehead rows", _menu._entries.size() == 3 + 1)
	fails += _expect("face cam on forehead", face_active())
	_menu._pop()
	_menu._push(CharacterMenu.LEVEL_FACE_EARS)
	fails += _expect("menu face ears rows", _menu._entries.size() == 4 + 1)
	fails += _expect("face cam on ears", face_active())
	_menu._pop()
	_menu._push(CharacterMenu.LEVEL_FACE_EYELASHES)
	fails += _expect("menu face lashes rows", _menu._entries.size() == 2 + 1)
	fails += _expect("face cam on lashes hub", face_active())
	_menu._pop()
	fails += _expect("menu back to hub forehead", _menu._level == CharacterMenu.LEVEL_FACE)
	_menu._pop()
	fails += _expect("face cam off face", not face_active())
	fails += _expect("face resumes", not _anim_paused)
	# 12. Face sculpt (JSON regions, live on fused Skin, defaults no-op).
	fails += _expect("sculpt json male", not (_avatar._sculpt_regions() as Dictionary).is_empty())
	fails += _expect("sculpt nose mask", int(((_avatar._sculpt_regions() as Dictionary).get("Nose", {}) as Dictionary).get("n", 0)) > 0)
	fails += _expect("sculpt defaults zero", face_sculpt_display(&"NoseLength") == "+0mm" and face_sculpt_display(&"ChinShift") == "+0mm")
	var tip0 := _nose_tip_z()
	adjust_face_sculpt(&"NoseLength", 5) # +5mm forward, tip rides at full weight
	fails += _expect("sculpt nose shown", face_sculpt_display(&"NoseLength") == "+5mm")
	fails += _expect("sculpt nose grows", _nose_tip_z() > tip0 + 0.003 and _nose_tip_z() < tip0 + 0.007)
	adjust_face_sculpt(&"NoseLength", 3) # total +8mm from pristine (no accumulation)
	fails += _expect("sculpt no accumulate", _nose_tip_z() > tip0 + 0.006 and _nose_tip_z() < tip0 + 0.010)
	adjust_face_sculpt(&"NoseWidth", 5)
	fails += _expect("sculpt width symmetric", _head_verts_symmetric())
	reset_face_sculpt(&"NoseLength")
	reset_face_sculpt(&"NoseWidth")
	fails += _expect("sculpt reset restores", is_equal_approx(_nose_tip_z(), tip0))
	adjust_face_sculpt(&"ChinShift", 200) # clamp to +10mm
	fails += _expect("sculpt chin clamped", face_sculpt_display(&"ChinShift") == "+10mm")
	reset_face_sculpt(&"ChinShift")
	adjust_face_sculpt(&"MouthW", -200) # clamp to -8mm
	fails += _expect("sculpt mouth clamped", face_sculpt_display(&"MouthW") == "-8mm")
	reset_face_sculpt(&"MouthW")
	adjust_face_sculpt(&"EarPoint", -200) # asymmetric floor -10mm (user-tuned)
	fails += _expect("sculpt earpoint floored", face_sculpt_display(&"EarPoint") == "-10mm")
	reset_face_sculpt(&"EarPoint")
	# 13. Sculpt round 2 (user eye-tune 07/10: negatives, base-vs-bridge, chin drop).
	adjust_face_sculpt(&"NoseLength", -5) # front pad catches the tip: retracts
	fails += _expect("sculpt nose back", _nose_tip_z() < tip0 - 0.002)
	reset_face_sculpt(&"NoseLength")
	var nose_pair := _sculpt_deltas(&"NoseWidth", 8)
	fails += _expect("sculpt nose base most", _flank_moves_most("Nose", nose_pair[0], nose_pair[1]))
	fails += _expect("sculpt nose no cross", _no_center_cross(nose_pair[0], nose_pair[1]))
	var mouth_pair := _sculpt_deltas(&"MouthW", -5)
	fails += _expect("sculpt mouth narrows", _gated_narrow(mouth_pair[0], mouth_pair[1], "Mouth"))
	fails += _expect("sculpt mouth no cross", _no_center_cross(mouth_pair[0], mouth_pair[1]))
	var chin_back_pair := _sculpt_deltas(&"ChinShift", -5) # weak chin recedes+rises
	fails += _expect("sculpt chin back", _chin_moved(chin_back_pair[0], chin_back_pair[1], -1.0))
	var chin_pair := _sculpt_deltas(&"ChinShift", 10)
	fails += _expect("sculpt chin drops", _chin_moved(chin_pair[0], chin_pair[1], 1.0))
	# 14. Sculpt round 3: outline follows (live Chin plateau 07/10 — the old
	# mean-based asserts passed while the contour froze at -2).
	var chin_f0 := _chin_front_z()
	adjust_face_sculpt(&"ChinShift", -2)
	var chin_f2 := _chin_front_z()
	adjust_face_sculpt(&"ChinShift", -3) # total -5 from pristine (single pass, no path)
	var chin_f5 := _chin_front_z()
	reset_face_sculpt(&"ChinShift")
	fails += _expect("sculpt chin no plateau", chin_f5 < chin_f2 - 0.001 and chin_f2 < chin_f0 - 0.0005)
	var nose_f0 := _nose_tip_z()
	adjust_face_sculpt(&"NoseLength", -8)
	fails += _expect("sculpt nose follows neg", _nose_tip_z() < nose_f0 - 0.006)
	reset_face_sculpt(&"NoseLength")
	var nose_w_neg := _sculpt_deltas(&"NoseWidth", -8)
	var nose_core := _core_widths(nose_w_neg[0], nose_w_neg[1], "Nose")
	fails += _expect("sculpt nose core narrows", nose_core.size() == 2 and nose_core[1] < nose_core[0] - 0.001)
	var mouth_w_pos := _sculpt_deltas(&"MouthW", 5)
	var mouth_core := _core_widths(mouth_w_pos[0], mouth_w_pos[1], "Mouth")
	fails += _expect("sculpt mouth core widens", mouth_core.size() == 2 and mouth_core[1] > mouth_core[0] + 0.001)
	# 15. Sculpt diffusion (08/10: crevasses at extremes — the rim must
	# follow instead of cliffing at the box edge).
	for ce in [[&"NoseLength", -10], [&"NoseWidth", 8], [&"ChinShift", -10], [&"MouthW", -8], [&"MouthW", 8], [&"NoseTipLength", 10], [&"NosePosition", 8], [&"LipUpper", 8], [&"LipLower", 8], [&"MouthCorners", 8], [&"MouthPosition", 8], [&"MouthForward", 8], [&"NoseTipSize", 10], [&"NoseTipAngle", 10], [&"NoseCurve", 10], [&"MouthPout", 8], [&"EyelidHeavy", 8], [&"EyeDepth", 8], [&"EyeHeight", 8], [&"EyeSpacing", 8], [&"EyeSize", 8], [&"EyeAngle", 8], [&"BrowAngle", 8], [&"BrowDepth", 8], [&"JawWidth", 8], [&"JawDefinition", 8], [&"JawAngle", 8], [&"ChinLength", 10], [&"ChinWidth", 8], [&"ChinProject", 10], [&"ChinCleft", 5], [&"CheekboneWidth", 8], [&"CheekboneHeight", 8], [&"CheekFullness", 8], [&"FaceFullness", 8], [&"ForeheadHeight", 8], [&"ForeheadWidth", 8], [&"BrowRidgeDepth", 8], [&"EarSize", 8], [&"EarRotation", 8], [&"EarlobeLength", 8], [&"EarPoint", 8]]:
		reset_face_sculpt(ce[0])
		adjust_face_sculpt(ce[0], ce[1])
		var cl := _avatar.sculpt_max_cliff()
		# EarSize bar is 6mm, not 5 (10/10 live: invisible on the coarse
		# helix edge, user-validated OK — the 5mm bar stands everywhere else).
		var bar := 0.006 if ce[0] == &"EarSize" else 0.005
		fails += _expect("sculpt no cliff %s" % String(ce[0]), cl < bar)
		reset_face_sculpt(ce[0])
	# 16. Mask migration (08/10, regions v2): every baked point resolves on the
	# live pristine (asset-drift guard — a reimport moving verts fails loud).
	var cov := _avatar.sculpt_mask_coverage()
	for region in ["Nose", "Mouth", "Chin", "NoseBridge", "NoseTip", "NostrilFlare", "UpperLip", "LowerLip", "MouthCorners", "Eyelids", "UpperEyelid", "Brows", "BrowRidge", "Jaw", "ChinCleft", "Cheekbones", "Cheeks", "LowerFace", "Forehead", "Ears", "Lobe", "EarTip"]:
		var cc: Array = cov.get(region, [0, 0])
		fails += _expect("sculpt mask %s resolves" % region, int(cc[1]) > 0 and float(cc[0]) / float(cc[1]) > 0.9)
	# 17. Painted detail rows move their mask and restore to zero.
	for nk in [&"NoseBridge", &"NoseTip", &"NostrilFlare", &"NoseTipLength", &"NosePosition", &"LipUpper", &"LipLower", &"MouthCorners", &"MouthPosition", &"MouthForward", &"NoseTipSize", &"NoseTipAngle", &"NoseCurve", &"MouthPout", &"EyelidHeavy", &"EyeDepth", &"EyeHeight", &"EyeSpacing", &"EyeSize", &"EyeAngle", &"BrowAngle", &"BrowHeight", &"BrowThick", &"BrowDepth", &"JawWidth", &"JawDefinition", &"JawAngle", &"ChinLength", &"ChinWidth", &"ChinProject", &"ChinCleft", &"CheekboneWidth", &"CheekboneHeight", &"CheekFullness", &"FaceFullness", &"ForeheadHeight", &"ForeheadWidth", &"BrowRidgeDepth", &"EarSize", &"EarRotation", &"EarlobeLength", &"EarPoint"]:
		reset_face_sculpt(nk)
		adjust_face_sculpt(nk, 10)
		fails += _expect("sculpt %s moves" % String(nk), _avatar.sculpt_max_cliff() > 1e-9)
		var fm := _avatar.sculpt_mean_push()
		var ff := float(parity_f.get(nk, -1.0))
		fails += _expect("parity %s" % String(nk), ff >= 0.0 and fm > 1e-9 and ff / fm >= 0.4 and ff / fm <= 2.5)
		reset_face_sculpt(nk)
		fails += _expect("sculpt %s restores" % String(nk), _avatar.sculpt_max_cliff() < 1e-9)
	# 17b. Seam guard (08/10 live slit near the ear: bit-identical twins on
	# a section seam took different diffusion halos and cracked open).
	# Zero coincident splits at full for every cheek row.
	for sk2 in [&"CheekboneWidth", &"CheekFullness", &"FaceFullness"]:
		reset_face_sculpt(sk2)
		adjust_face_sculpt(sk2, 8)
		var seam_n2 := 0
		var smi2 := _avatar_skin_mi()
		for s in smi2.mesh.get_surface_count():
			var ca2: Array = smi2.mesh.surface_get_arrays(s)
			var pa2: Array = _avatar._skin_pristine.surface_get_arrays(s)
			var cv2: PackedVector3Array = ca2[Mesh.ARRAY_VERTEX]
			var pv2: PackedVector3Array = pa2[Mesh.ARRAY_VERTEX]
			if cv2.size() != pv2.size():
				continue
			var grid2 := {}
			for i in pv2.size():
				var cell := Vector3i(int(round(pv2[i].x * 2000.0)), int(round(pv2[i].y * 2000.0)), int(round(pv2[i].z * 2000.0)))
				if not grid2.has(cell):
					grid2[cell] = []
				(grid2[cell] as Array).append(i)
			for cell in grid2:
				var lst: Array = grid2[cell]
				for a in lst.size():
					for b in range(a + 1, lst.size()):
						var i: int = lst[a]
						var j: int = lst[b]
						if pv2[i].distance_to(pv2[j]) > 0.0005:
							continue
						if cv2[i].distance_to(cv2[j]) > 0.001:
							seam_n2 += 1
		fails += _expect("sculpt no seam %s" % String(sk2), seam_n2 == 0)
		reset_face_sculpt(sk2)
	# 17b. Row superposition (08/10 live bug: one NoseWidth step visibly
	# flattened NoseCurve — the shared wmax let the Nose mask flip the
	# bridge halo verts to mask and snap their 6mm halo back to ~0).
	# Per-key diffusion: adding an X/Y row must not move any Z.
	for combo in [[&"NoseWidth", 1], [&"NosePosition", 1]]:
		for k in [&"NoseCurve", combo[0]]:
			reset_face_sculpt(k)
		adjust_face_sculpt(&"NoseCurve", -10)
		var lone := _head_dom_verts()
		adjust_face_sculpt(combo[0], combo[1])
		var both := _head_dom_verts()
		var dzmax := 0.0
		for i in mini(lone.size(), both.size()):
			dzmax = maxf(dzmax, absf(both[i].z - lone[i].z))
		fails += _expect("sculpt %s spares curve Z" % String(combo[0]), dzmax < 1e-6)
		for k in [&"NoseCurve", combo[0]]:
			reset_face_sculpt(k)
	# 18. Vertical nose rows (08/10): Length+ drops the tip, Position+ lifts
	# the nose band; both restore.
	var len_pair := _sculpt_deltas(&"NoseTipLength", 10)
	var len_f := _region_floors(len_pair[0], len_pair[1], "NoseTip")
	fails += _expect("sculpt length drops tip", len_f.size() == 2 and len_f[1] < len_f[0] - 0.008)
	var pos_pair := _sculpt_deltas(&"NosePosition", 8)
	var pos_f := _region_floors(pos_pair[0], pos_pair[1], "Nose")
	fails += _expect("sculpt position lifts nose", pos_f.size() == 2 and pos_f[1] > pos_f[0] + 0.006)
	# 19. Mouth rows (08/10): lips push forward, corners/position lift, the
	# whole mouth advances; all restore (in the moves loop above).
	var lu_pair := _sculpt_deltas(&"LipUpper", 8)
	var lu_f := _region_fronts(lu_pair[0], lu_pair[1], "UpperLip")
	fails += _expect("sculpt lip upper pushes", lu_f.size() == 2 and lu_f[1] > lu_f[0] + 0.006)
	var ll_pair := _sculpt_deltas(&"LipLower", 8)
	var ll_f := _region_fronts(ll_pair[0], ll_pair[1], "LowerLip")
	fails += _expect("sculpt lip lower pushes", ll_f.size() == 2 and ll_f[1] > ll_f[0] + 0.006)
	var mc_pair := _sculpt_deltas(&"MouthCorners", 8)
	var mc_f := _region_floors(mc_pair[0], mc_pair[1], "MouthCorners")
	fails += _expect("sculpt corners lift", mc_f.size() == 2 and mc_f[1] > mc_f[0] + 0.006)
	var mp_pair := _sculpt_deltas(&"MouthPosition", 8)
	var mp_f := _region_floors(mp_pair[0], mp_pair[1], "Mouth")
	fails += _expect("sculpt mouth lifts", mp_f.size() == 2 and mp_f[1] > mp_f[0] + 0.006)
	var mf_pair := _sculpt_deltas(&"MouthForward", 8)
	var mf_f := _region_fronts(mf_pair[0], mf_pair[1], "Mouth")
	fails += _expect("sculpt mouth advances", mf_f.size() == 2 and mf_f[1] > mf_f[0] + 0.006)
	# 19b. MouthPout (falloff across the lip): center pushes ~full, edges
	# hold — unlike LipUpper which advances both equally.
	var mpout_pair := _sculpt_deltas(&"MouthPout", 8)
	var mpout := _region_pout(mpout_pair[0], mpout_pair[1], "UpperLip")
	fails += _expect("sculpt pout pushes center", mpout.size() == 2 and mpout[0] > 0.005)
	fails += _expect("sculpt pout holds edges", mpout.size() == 2 and mpout[0] > mpout[1] + 0.002)
	# 21. Eyes & brows (08/10, ranges 09/10): lid drops (±4), globe pushes
	# out (+ = out, flipped 09/10), eye band lifts, ridge pushes (±4).
	var eh_pair := _sculpt_deltas(&"EyelidHeavy", 8)
	var eh_f := _region_floors(eh_pair[0], eh_pair[1], "UpperEyelid")
	fails += _expect("sculpt lid drops", eh_f.size() == 2 and eh_f[1] < eh_f[0] - 0.003)
	var ed_pair := _sculpt_deltas(&"EyeDepth", 8)
	var ed_f := _region_fronts(ed_pair[0], ed_pair[1], "Eyelids")
	fails += _expect("sculpt eye out", ed_f.size() == 2 and ed_f[1] > ed_f[0] + 0.006)
	var ey_pair := _sculpt_deltas(&"EyeHeight", 8)
	var ey_f := _region_floors(ey_pair[0], ey_pair[1], "Eyelids")
	fails += _expect("sculpt eye lifts", ey_f.size() == 2 and ey_f[1] > ey_f[0] + 0.006)
	var esp_pair := _sculpt_deltas(&"EyeSpacing", 8)
	var esp_w := _core_widths(esp_pair[0], esp_pair[1], "Eyelids")
	fails += _expect("sculpt eyes spread", esp_w.size() == 2 and esp_w[1] > esp_w[0] + 0.010)
	fails += _expect("sculpt eyes no cross", _no_center_cross(esp_pair[0], esp_pair[1]))
	# Brow mesh rows (Height/Thick) activate when the Brows region is painted
	# (inert asserts in section 16 until then).
	var bd_pair := _sculpt_deltas(&"BrowDepth", 8)
	var bd_f := _region_fronts(bd_pair[0], bd_pair[1], "BrowRidge")
	fails += _expect("sculpt ridge pushes", bd_f.size() == 2 and bd_f[1] > bd_f[0] + 0.003)
	# 22. Jaw & chin (08/10): gonions widen symmetric, chin drops/widens/
	# projects, cleft sinks.
	var jw_pair := _sculpt_deltas(&"JawWidth", 8)
	var jw_w := _core_widths(jw_pair[0], jw_pair[1], "Jaw")
	fails += _expect("sculpt jaw widens", jw_w.size() == 2 and jw_w[1] > jw_w[0] + 0.001)
	fails += _expect("sculpt jaw no cross", _no_center_cross(jw_pair[0], jw_pair[1]))
	var cl_pair := _sculpt_deltas(&"ChinLength", 10)
	var cl_f := _region_floors(cl_pair[0], cl_pair[1], "Chin")
	fails += _expect("sculpt chin drops", cl_f.size() == 2 and cl_f[1] < cl_f[0] - 0.008)
	var cw_pair := _sculpt_deltas(&"ChinWidth", 8)
	var cw_w := _core_widths(cw_pair[0], cw_pair[1], "Chin")
	fails += _expect("sculpt chin widens", cw_w.size() == 2 and cw_w[1] > cw_w[0] + 0.001)
	fails += _expect("sculpt chin no cross", _no_center_cross(cw_pair[0], cw_pair[1]))
	var cp_pair := _sculpt_deltas(&"ChinProject", 10)
	var cp_f := _region_fronts(cp_pair[0], cp_pair[1], "Chin")
	fails += _expect("sculpt chin projects", cp_f.size() == 2 and cp_f[1] > cp_f[0] + 0.008)
	var cc_pair := _sculpt_deltas(&"ChinCleft", 5)
	var cc_f := _region_fronts(cc_pair[0], cc_pair[1], "ChinCleft")
	fails += _expect("sculpt cleft sinks", cc_f.size() == 2 and cc_f[1] < cc_f[0] - 0.003)
	# 23. Cheeks (08/10): bones widen/lift symmetric, cheeks + lower face
	# fill out (uniform centroid scale).
	var cbw_pair := _sculpt_deltas(&"CheekboneWidth", 8)
	var cbw_w := _core_widths(cbw_pair[0], cbw_pair[1], "Cheekbones")
	fails += _expect("sculpt bones widen", cbw_w.size() == 2 and cbw_w[1] > cbw_w[0] + 0.001)
	fails += _expect("sculpt bones no cross", _no_center_cross(cbw_pair[0], cbw_pair[1]))
	var cbh_pair := _sculpt_deltas(&"CheekboneHeight", 8)
	var cbh_f := _region_floors(cbh_pair[0], cbh_pair[1], "Cheekbones")
	fails += _expect("sculpt bones lift", cbh_f.size() == 2 and cbh_f[1] > cbh_f[0] + 0.006)
	var cf_pair := _sculpt_deltas(&"CheekFullness", 8)
	var cf_h := _region_yextent(cf_pair[0], cf_pair[1], "Cheeks")
	fails += _expect("sculpt cheeks fill", cf_h.size() == 2 and cf_h[1] > cf_h[0] + 0.0008)
	var ff_pair := _sculpt_deltas(&"FaceFullness", 8)
	var ff_h := _region_yextent(ff_pair[0], ff_pair[1], "LowerFace")
	fails += _expect("sculpt face fills", ff_h.size() == 2 and ff_h[1] > ff_h[0] + 0.0008)
	# 24. Forehead & ears (08/10): forehead lifts/widens, ridge pushes,
	# ears grow from the root (09/10: centroid scale grew the skull side).
	var fh_pair := _sculpt_deltas(&"ForeheadHeight", 8)
	var fh_f := _region_floors(fh_pair[0], fh_pair[1], "Forehead")
	fails += _expect("sculpt forehead lifts", fh_f.size() == 2 and fh_f[1] > fh_f[0] + 0.006)
	var fw_pair := _sculpt_deltas(&"ForeheadWidth", 8)
	var fw_w := _core_widths(fw_pair[0], fw_pair[1], "Forehead")
	fails += _expect("sculpt forehead widens", fw_w.size() == 2 and fw_w[1] > fw_w[0] + 0.001)
	fails += _expect("sculpt forehead no cross", _no_center_cross(fw_pair[0], fw_pair[1]))
	var br_pair := _sculpt_deltas(&"BrowRidgeDepth", 8)
	var br_f := _region_fronts(br_pair[0], br_pair[1], "BrowRidge")
	fails += _expect("sculpt ridge juts", br_f.size() == 2 and br_f[1] > br_f[0] + 0.003)
	var es_pair := _sculpt_deltas(&"EarSize", 8)
	var es_h := _region_yextent(es_pair[0], es_pair[1], "Ears")
	fails += _expect("sculpt ears grow", es_h.size() == 2 and es_h[1] > es_h[0] + 0.0008)
	# 20. New nose mechanics (08/10): centroid scale, pivot rotation, falloff.
	var ts_pair := _sculpt_deltas(&"NoseTipSize", 10)
	var ts_w := _core_widths(ts_pair[0], ts_pair[1], "NoseTip")
	fails += _expect("sculpt tip grows", ts_w.size() == 2 and ts_w[1] > ts_w[0] + 0.001)
	var ta_pair := _sculpt_deltas(&"NoseTipAngle", 10)
	var ta_l := _region_front_lift(ta_pair[0], ta_pair[1], "NoseTip")
	fails += _expect("sculpt tip lifts", ta_l.size() == 2 and ta_l[1] > ta_l[0] + 0.0002)
	fails += _expect("sculpt tip turns", _region_mean_disp(ta_pair[0], ta_pair[1], "NoseTip") > 0.0008)
	var cu_pair := _sculpt_deltas(&"NoseCurve", 10)
	var cu_f := _region_midfront(cu_pair[0], cu_pair[1], "NoseBridge")
	fails += _expect("sculpt bridge bows", cu_f.size() == 2 and cu_f[1] > cu_f[0] + 0.006)
	# No stowaway meshes: every visible MI lives directly under Fused
	# (Skin/Cloths) or a Hair/Beard holder — never under a skeleton (the
	# 08/10 ghost: nude MIs dragged along with the reparented master).
	fails += _expect("no stowaway mis", _no_stowaway_mis())
	print("[CharTest] %d FAIL" % fails)
	get_tree().quit()


## TEMP brow-burial probe (female brows sink under random sculpt, male does
## not — live report 12/10). Compares skin motion at the brow site vs part
## motion, at rest and with the reported seed replayed, then isolates each
## brow-driving key. Removed once diagnosed.
func _run_brow_probe() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var brow_keys := [&"BrowHeight", &"BrowThick", &"BrowAngle", &"BrowDepth", &"BrowRidgeDepth"]
	var eye_keys := [&"EyelidHeavy", &"EyeDepth", &"EyeHeight", &"EyeSpacing", &"EyeSize", &"EyeAngle"]
	for g in [0, 1]:
		if g == 0:
			reset_gender()
		else:
			adjust_gender(1)
		reset_face_all()
		var n0 := _browprobe_skin_pn()
		var r0: PackedVector3Array = n0[0]
		var sn0: PackedVector3Array = n0[1]
		var p0 := _browprobe_part_verts()
		var e0 := _browprobe_part_verts("Eyes")
		var pair := _browprobe_pair(p0, r0)
		var site := _browprobe_eye_site()
		var paire := _browprobe_pair(e0, site[0])
		print("[BrowProbe] %s eye site skin=%d ballpair=%d" % [gender_display(), (site[0] as PackedVector3Array).size(), paire.size()])
		var lid := _browprobe_eye_site("Eyelids", 0.005)
		print("[BrowProbe] %s lid verts=%d" % [gender_display(), (lid[0] as PackedVector3Array).size()])
		var rg := _browprobe_sink(p0, r0, sn0, p0, r0, pair)
		print("[BrowProbe] %s rest sink mean=%+.2fmm min=%+.2fmm buried=%d (part %d)" % [gender_display(), rg[0], rg[1], rg[2], p0.size()])
		_browprobe_apply_seed()
		var kvals := []
		for bk in brow_keys:
			kvals.append("%s=%+.2f" % [String(bk), float(_avatar.get("_sculpt").get(bk, 0.0)) * 10.0])
		print("[BrowProbe] %s seed kvals(mm): %s" % [gender_display(), " ".join(kvals)])
		var sg := _browprobe_sink(p0, r0, sn0, _browprobe_part_verts(), _browprobe_skin_pn()[0], pair)
		print("[BrowProbe] %s seed sink mean=%+.2fmm min=%+.2fmm buried=%d" % [gender_display(), sg[0], sg[1], sg[2]])
		var ekvals := []
		for ek in eye_keys:
			ekvals.append("%s=%+.2f" % [String(ek), float(_avatar.get("_sculpt").get(ek, 0.0)) * 10.0])
		print("[BrowProbe] %s seed eyekvals(mm): %s" % [gender_display(), " ".join(ekvals)])
		var s1 := _browprobe_eye_site_pos(site[2])
		var e1 := _browprobe_part_verts("Eyes")
		var se := _browprobe_sink(e0, site[0], site[1], e1, s1[0], paire)
		print("[BrowProbe] %s seed eyes sink mean=%+.2fmm min=%+.2fmm buried=%d paired=%d (balls %d)" % [gender_display(), se[0], se[1], se[2], se[3], e0.size()])
		var ap0 := _browprobe_aperture(e0, lid[0])
		var l1 := _browprobe_eye_site_pos(lid[2])
		var ap1 := _browprobe_aperture(e1, l1[0])
		print("[BrowProbe] %s aperture rest lidU=%+.2f lidL=%+.2f ballU=%+.2f ballL=%+.2f vs seed lidU=%+.2f lidL=%+.2f ballU=%+.2f ballL=%+.2f" % [gender_display(), ap0[0], ap0[1], ap0[2], ap0[3], ap1[0], ap1[1], ap1[2], ap1[3]])
		var inv := _browprobe_headinv()
		var cx := float(_avatar.sculpt_region_stats("Eyelids").get("cx", 0.0))
		var he0 := PackedVector3Array()
		var he1 := PackedVector3Array()
		for v in e0:
			he0.append(inv * v)
		for v in e1:
			he1.append(inv * v)
		var hl0 := PackedVector3Array()
		var hl1 := PackedVector3Array()
		for v in (lid[0] as PackedVector3Array):
			hl0.append(inv * v)
		for v in (l1[0] as PackedVector3Array):
			hl1.append(inv * v)
		var hc0 := PackedVector3Array()
		var hc1 := PackedVector3Array()
		for i in hl0.size():
			if absf(hl0[i].x - cx) < 0.02:
				hc0.append(hl0[i])
				hc1.append(hl1[i])
		var sb := _browprobe_sidemeans(he0, he1, cx)
		var sl := _browprobe_sidemeans(hl0, hl1, cx)
		var sc := _browprobe_sidemeans(hc0, hc1, cx)
		print("[BrowProbe] %s lateral ball L=%s R=%s | lids L=%s R=%s | canthi L=%s R=%s (mm x1000)" % [gender_display(), str(sb[0] * 1000.0), str(sb[1] * 1000.0), str(sl[0] * 1000.0), str(sl[1] * 1000.0), str(sc[0] * 1000.0), str(sc[1] * 1000.0)])
		var pen0 := _browprobe_pen(e0, site[0], site[1])
		var pen1 := _browprobe_pen(_browprobe_part_verts("Eyes"), s1[0], s1[1])
		print("[BrowProbe] %s eyes pen rest min=%+.2fmm bad=%d/balls=%d vs seed min=%+.2fmm bad=%d y=%+.1fmm" % [gender_display(), pen0[0], pen0[1], e0.size(), pen1[0], pen1[1], pen1[2]])
		# Attribution: seed minus the eye keys (cross-talk suspects).
		for ek in eye_keys:
			_avatar.set_sculpt(ek, 0.0, false)
		_avatar.fuse_sculpt()
		var ng := _browprobe_sink(p0, r0, sn0, _browprobe_part_verts(), _browprobe_skin_pn()[0], pair)
		print("[BrowProbe] %s seed-noeye sink mean=%+.2fmm min=%+.2fmm buried=%d" % [gender_display(), ng[0], ng[1], ng[2]])
		# Attribution: brow keys alone at their seed values.
		reset_face_all()
		_browprobe_apply_seed()
		for key in CharacterAvatar.SCULPT_KEYS:
			if not brow_keys.has(key):
				_avatar.set_sculpt(key, 0.0, false)
		_avatar.fuse_sculpt()
		var bg := _browprobe_sink(p0, r0, sn0, _browprobe_part_verts(), _browprobe_skin_pn()[0], pair)
		print("[BrowProbe] %s seed-browsonly sink mean=%+.2fmm min=%+.2fmm buried=%d" % [gender_display(), bg[0], bg[1], bg[2]])
		reset_face_all()
		var iso := []
		for bk in brow_keys:
			iso.append([bk, "Brows", "Eyebrows"])
		for ek2 in eye_keys:
			iso.append([ek2, "Eyelids", "Eyes"])
		for entry in iso:
			var ik: StringName = entry[0]
			var ireg: String = entry[1]
			var islot: String = entry[2]
			reset_face_sculpt(ik)
			var b0 := _head_dom_verts()
			var pn0 := _browprobe_skin_pn()
			var q0 := _browprobe_part_verts(islot)
			adjust_face_sculpt(ik, 10)
			var b1 := _head_dom_verts()
			var pn1 := _browprobe_skin_pn()
			var q1 := _browprobe_part_verts(islot)
			var skv := _browprobe_region_vec(b0, b1, ireg)
			var pkv := _browprobe_mean_vec(q0, q1)
			var isk := [0.0, 0.0, 0, 0]
			if islot == "Eyes":
				var st1 := _browprobe_eye_site_pos(site[2])
				var pair0e := _browprobe_pair(q0, site[0])
				isk = _browprobe_sink(q0, site[0], site[1], q1, st1[0], pair0e)
				var pe0 := _browprobe_pen(q0, site[0], site[1])
				var pe1 := _browprobe_pen(q1, st1[0], st1[1])
				print("[BrowProbe] %s %s pen rest min=%+.2fmm bad=%d vs state min=%+.2fmm bad=%d y=%+.1fmm" % [gender_display(), String(ik), pe0[0], pe0[1], pe1[0], pe1[1], pe1[2]])
			else:
				var pair0b := _browprobe_pair(q0, pn0[0])
				isk = _browprobe_sink(q0, pn0[0], pn0[1], q1, pn1[0], pair0b)
			print("[BrowProbe] %s %s skin=%s part=%s sink=%+.2f/%+.2f/%d/%d" % [gender_display(), String(ik), str(skv * 1000.0), str(pkv * 1000.0), isk[0], isk[1], isk[2], isk[3]])
			reset_face_sculpt(ik)
	print("[BrowProbe] done")
	get_tree().quit()


## TEMP clearance sweep (face acceptance landscape): 20 FIXED seeds (bit
## reproducible) x both genders, full-face ±60% draws. Per seed: brow sink
## min (paired set), lid-vs-ball aperture upper/lower, lateral ball-vs-canthi
## outrun. Reporting thresholds only (no pins yet): brow < -1.0 burial,
## aperture < +1.0 tight, lateral > +1.0 strain. Worst seed's full kvals print
## for manual repro. Removed once the bar is set.
func _run_face_sweep() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var n := 20
	var worst_brow := [1e9, -1, ""]
	var worst_apu := [1e9, -1, ""]
	var worst_apl := [1e9, -1, ""]
	var worst_lat := [-1e9, -1, ""]
	var worst_kvals := {}
	var nbad_brow := 0
	var nbad_ap := 0
	var nbad_lat := 0
	for g in [0, 1]:
		if g == 0:
			reset_gender()
		else:
			adjust_gender(1)
		reset_face_all()
		var n0 := _browprobe_skin_pn()
		var r0: PackedVector3Array = n0[0]
		var sn0: PackedVector3Array = n0[1]
		var p0 := _browprobe_part_verts()
		var pair := _browprobe_pair(p0, r0)
		var e0 := _browprobe_part_verts("Eyes")
		var lid := _browprobe_eye_site("Eyelids", 0.005)
		var inv := _browprobe_headinv()
		var cx := float(_avatar.sculpt_region_stats("Eyelids").get("cx", 0.0))
		var hc_idx := PackedInt32Array()
		var hl0rest := PackedVector3Array()
		for v in (lid[0] as PackedVector3Array):
			hl0rest.append(inv * v)
		for i in hl0rest.size():
			if absf(hl0rest[i].x - cx) < 0.02:
				hc_idx.append(i)
		for i in n:
			var seed := 7000 + i
			_browprobe_apply_seed(seed)
			var p1 := _browprobe_part_verts()
			var sg := _browprobe_sink(p0, r0, sn0, p1, _browprobe_skin_pn()[0], pair)
			var e1 := _browprobe_part_verts("Eyes")
			var l1 := _browprobe_eye_site_pos(lid[2])
			var ap := _browprobe_aperture(e1, l1[0])
			var apu: float = ap[0] - ap[2]
			var apl: float = ap[1] - ap[3]
			var he0 := PackedVector3Array()
			var he1 := PackedVector3Array()
			for v in e0:
				he0.append(inv * v)
			for v in e1:
				he1.append(inv * v)
			var hl1 := PackedVector3Array()
			for v in (l1[0] as PackedVector3Array):
				hl1.append(inv * v)
			var hc0 := PackedVector3Array()
			var hc1 := PackedVector3Array()
			for ci in hc_idx:
				hc0.append(hl0rest[int(ci)])
				hc1.append(hl1[int(ci)])
			var sb := _browprobe_sidemeans(he0, he1, cx)
			var sc := _browprobe_sidemeans(hc0, hc1, cx)
			var lat := maxf(absf((sb[0] as Vector3).x) - absf((sc[0] as Vector3).x), absf((sb[1] as Vector3).x) - absf((sc[1] as Vector3).x))
			var tag := "%d %s" % [seed, gender_display()]
			print("[FaceSweep] seed=%d %s brow=%+.2f apU=%+.2f apL=%+.2f lat=%+.2f sp=%+.2f" % [seed, gender_display(), sg[1], apu, apl, lat, float(_avatar.get("_sculpt").get(&"EyeSpacing", 0.0)) * 10.0])
			if sg[1] < worst_brow[0]:
				worst_brow = [sg[1], seed, gender_display()]
				worst_kvals = (_avatar.get("_sculpt") as Dictionary).duplicate()
			if apu < worst_apu[0]:
				worst_apu = [apu, seed, gender_display()]
			if apl < worst_apl[0]:
				worst_apl = [apl, seed, gender_display()]
			if lat > worst_lat[0]:
				worst_lat = [lat, seed, gender_display()]
			if sg[1] < -1.0:
				nbad_brow += 1
			if minf(apu, apl) < 1.0:
				nbad_ap += 1
			if lat > 1.0:
				nbad_lat += 1
		reset_face_all()
	print("[FaceSweep] worst brow=%+.2f (seed %d %s) apU=%+.2f (%d %s) apL=%+.2f (%d %s) lat=%+.2f (%d %s)" % [worst_brow[0], worst_brow[1], worst_brow[2], worst_apu[0], worst_apu[1], worst_apu[2], worst_apl[0], worst_apl[1], worst_apl[2], worst_lat[0], worst_lat[1], worst_lat[2]])
	print("[FaceSweep] over bar: brow %d/40 aperture %d/40 lateral %d/40" % [nbad_brow, nbad_ap, nbad_lat])
	var wline := []
	for key in CharacterAvatar.SCULPT_KEYS:
		wline.append("%s=%+.1f" % [String(key), float(worst_kvals.get(key, 0.0)) * 10.0])
	print("[FaceSweep] worst-brow kvals(mm): %s" % " ".join(wline))
	print("[FaceSweep] done")
	get_tree().quit()


## Replays the reported seed exactly (fresh RNG + same call order as
## randomize_face: one randf_range per SCULPT_KEYS entry).
func _browprobe_apply_seed(seed := -4760453800869451545) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for key in CharacterAvatar.SCULPT_KEYS:
		var maxv := float((CharacterAvatar.SCULPT_SPEC.get(key, {}) as Dictionary).get("max_cm", 1.0))
		_avatar.set_sculpt(key, rng.randf_range(-maxv * 0.6, maxv * 0.6), false)
	_avatar.fuse_sculpt()


## Rest pairing: nearest rest-skin index per part vert (stride 1 — the head
## patch is small). Fixed set for all later sink measurements. Verts pairing
## farther than 1.5mm (deep-socket ball backs with no true skin neighbor)
## get -1 and are excluded: their relative motion is meaningless.
func _browprobe_pair(p0: PackedVector3Array, r0: PackedVector3Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(p0.size())
	for i in p0.size():
		var best := 1e18
		var bi := -1
		for j in r0.size():
			var d2 := p0[i].distance_squared_to(r0[j])
			if d2 < best:
				best = d2
				bi = j
		out[i] = bi if best <= 0.0015 * 0.0015 else -1
	return out


## Per-vert sink depth: part motion minus paired-skin motion, signed on the
## REST skin normal. Negative = the part dove under the skin there.
## Returns [mean_mm, min_mm, buried_count(< -0.2mm), paired_count].
func _browprobe_sink(p0: PackedVector3Array, r0: PackedVector3Array, sn0: PackedVector3Array, p1: PackedVector3Array, r1: PackedVector3Array, pair: PackedInt32Array) -> Array:
	if p0.size() != p1.size() or r0.size() != r1.size() or p0.size() != pair.size() or sn0.size() != r0.size():
		return [9999.0, 9999.0, 0, 0]
	var sum := 0.0
	var mn := 1e9
	var buried := 0
	var n := 0
	for i in p0.size():
		var j := pair[i]
		if j < 0:
			continue
		var rel: Vector3 = (p1[i] - p0[i]) - (r1[j] - r0[j])
		var sd := rel.dot(sn0[j])
		sum += sd
		mn = minf(mn, sd)
		if sd < -0.0002:
			buried += 1
		n += 1
	if n == 0:
		return [0.0, 0.0, 0, 0]
	return [sum / float(n) * 1000.0, mn * 1000.0, buried, n]


## All holder verts of a face slot in Skin-model space (relative transform
## applied, no equal-transform assumption).
func _browprobe_part_verts(slot := "Eyebrows") -> PackedVector3Array:
	var out := PackedVector3Array()
	var holder := _avatar.get_node_or_null(slot)
	var skin_mi := _avatar_skin_mi()
	if holder == null or skin_mi == null:
		return out
	var rel: Transform3D = skin_mi.global_transform.affine_inverse()
	for mi in (holder as Node).find_children("*", "MeshInstance3D", true, false):
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.mesh == null:
			continue
		var xf: Transform3D = rel * mmi.global_transform
		var mesh := mmi.mesh as ArrayMesh
		for s in mesh.get_surface_count():
			var vv: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in vv:
				out.append(xf * v)
	return out


func _browprobe_mean_vec(before: PackedVector3Array, after: PackedVector3Array) -> Vector3:
	if before.size() != after.size() or before.is_empty():
		return Vector3.ZERO
	var acc := Vector3.ZERO
	for i in before.size():
		acc += after[i] - before[i]
	return acc / float(before.size())


## Mean displacement VECTOR of a region's mask members (fixed set, membership
## on BEFORE Head-frame positions).
func _browprobe_region_vec(before: PackedVector3Array, after: PackedVector3Array, region: String) -> Vector3:
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1 or before.size() != after.size():
		return Vector3.ZERO
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var acc := Vector3.ZERO
	var n := 0
	for i in before.size():
		if _avatar.sculpt_in_region(region, inv * before[i]):
			acc += after[i] - before[i]
			n += 1
	return acc / float(maxi(n, 1))


## Eye-site skin: head-local Eyelids bbox (±30mm) filter over ALL Skin verts
## (no Head-dominance filter — the lids themselves are barely Head-weighted,
## which is why the head-dom set saw nothing near the balls). Topology never
## changes under sculpt, so a rest-computed flat index set stays valid all
## bake long. Returns [pos, nrm, idx] (model space + flat counters).
func _browprobe_eye_site(region := "Eyelids", margin := 0.03) -> Array:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1:
		return [pos, nrm, idx]
	var inv: Transform3D = _avatar._bone_rest_world(sk, bi).affine_inverse()
	var r: Dictionary = _avatar._sculpt_regions().get(region, {})
	if r.is_empty():
		return [pos, nrm, idx]
	var mn: Vector3 = (r["mn"] as Vector3) - Vector3(margin, margin, margin)
	var mx: Vector3 = (r["mx"] as Vector3) + Vector3(margin, margin, margin)
	var k := 0
	for mi in _avatar_mis():
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.mesh == null or mmi.name != &"Skin":
			continue
		for s in mmi.mesh.get_surface_count():
			var a := mmi.mesh.surface_get_arrays(s)
			var bv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var an: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			if an.size() != bv.size():
				k += bv.size()
				continue
			for i in bv.size():
				var q: Vector3 = inv * bv[i]
				if q.x >= mn.x and q.x <= mx.x and q.y >= mn.y and q.y <= mx.y and q.z >= mn.z and q.z <= mx.z:
					pos.append(bv[i])
					nrm.append(an[i].normalized())
					idx.append(k)
				k += 1
	return [pos, nrm, idx]


## Current positions/normals for a rest-computed eye-site index set.
func _browprobe_eye_site_pos(idxs: PackedInt32Array) -> Array:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var want := {}
	for v in idxs:
		want[int(v)] = true
	var k := 0
	for mi in _avatar_mis():
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.mesh == null or mmi.name != &"Skin":
			continue
		for s in mmi.mesh.get_surface_count():
			var a := mmi.mesh.surface_get_arrays(s)
			var bv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var an: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			if an.size() != bv.size():
				k += bv.size()
				continue
			for i in bv.size():
				if want.has(k):
					pos.append(bv[i])
					nrm.append(an[i].normalized())
				k += 1
	return [pos, nrm]


## True interpenetration probe (no rest pairing): per ball vert, signed
## distance to the nearest CURRENT site-skin vert (4mm cap). Returns
## [min_mm, bad_count(< -0.3mm), bad_meany_minus_centery_mm, paired].
## Compare rest vs sculpted: NEW deep negatives = real penetration. The Y
## tells superior (+) from inferior (−).
func _browprobe_pen(pv: PackedVector3Array, sp: PackedVector3Array, sn: PackedVector3Array) -> Array:
	if pv.is_empty() or sp.is_empty() or sp.size() != sn.size():
		return [0.0, 0.0, 0.0, 0]
	var cy := 0.0
	for v in pv:
		cy += v.y
	cy /= float(pv.size())
	var mn := 1e9
	var bad := 0
	var by := 0.0
	var n := 0
	for p in pv:
		var best := 1e18
		var bi := 0
		for j in sp.size():
			var d2 := p.distance_squared_to(sp[j])
			if d2 < best:
				best = d2
				bi = j
		if best > 0.004 * 0.004:
			continue
		n += 1
		var d: Vector3 = p - sp[bi]
		var sd := d.length()
		if sd > 1e-9:
			sd = signf(d.dot(sn[bi])) * sd
		else:
			sd = 0.0
		mn = minf(mn, sd)
		if sd < -0.0003:
			bad += 1
			by += p.y
	var rel := 0.0
	if bad > 0:
		rel = (by / float(bad) - cy) * 1000.0
	if n == 0:
		return [0.0, 0.0, 0.0, 0]
	return [mn * 1000.0, bad, rel, n]


## Head-inverse (IDENTITY when no skeleton): puts probe verts in Head frame.
func _browprobe_headinv() -> Transform3D:
	var sk := _avatar_skeleton()
	var bi := sk.find_bone(&"Head") if sk != null else -1
	if bi == -1:
		return Transform3D.IDENTITY
	return _avatar._bone_rest_world(sk, bi).affine_inverse()


## Side-split mean motions in Head frame (x >= cx = R): [meanL, meanR].
func _browprobe_sidemeans(r0: PackedVector3Array, r1: PackedVector3Array, cx: float) -> Array:
	var sL := Vector3.ZERO
	var sR := Vector3.ZERO
	var nL := 0
	var nR := 0
	for i in mini(r0.size(), r1.size()):
		if r0[i].x >= cx:
			sR += r1[i] - r0[i]
			nR += 1
		else:
			sL += r1[i] - r0[i]
			nL += 1
	if nL == 0 or nR == 0:
		return [Vector3.ZERO, Vector3.ZERO]
	return [sL / float(nL), sR / float(nR)]


## Lid-vs-ball aperture (model +z = face-forward): max z of site skin and of
## balls, split upper/lower by ball-center y. Poke-through = ballmax passing
## lidmax vs the rest baseline. Returns [lid_up, lid_lo, ball_up, ball_lo].
func _browprobe_aperture(balls: PackedVector3Array, skin: PackedVector3Array) -> Array:
	if balls.is_empty() or skin.is_empty():
		return [0.0, 0.0, 0.0, 0.0]
	var cy := 0.0
	for v in balls:
		cy += v.y
	cy /= float(balls.size())
	var lu := -1e9
	var ll := -1e9
	for v in skin:
		if v.y >= cy:
			lu = maxf(lu, v.z)
		else:
			ll = maxf(ll, v.z)
	var bu := -1e9
	var bl := -1e9
	for v in balls:
		if v.y >= cy:
			bu = maxf(bu, v.z)
		else:
			bl = maxf(bl, v.z)
	return [lu * 1000.0, ll * 1000.0, bu * 1000.0, bl * 1000.0]


## Head-dominated skin positions + normals (model space), for the signed
## burial gap (sign via skin normal: + = outside, - = buried).
func _browprobe_skin_pn() -> Array:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var sk := _avatar_skeleton()
	if sk == null:
		return [pos, nrm]
	var head := sk.find_bone(&"Head")
	for mi in _avatar_mis():
		var mmi := mi as MeshInstance3D
		if mmi == null or mmi.mesh == null or mmi.name != &"Skin":
			continue
		for s in mmi.mesh.get_surface_count():
			var a := mmi.mesh.surface_get_arrays(s)
			if a[Mesh.ARRAY_BONES] == null or a[Mesh.ARRAY_WEIGHTS] == null:
				continue
			var an: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			if an.size() != (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
				continue
			var bv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var bi: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var bw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			for i in bv.size():
				var bb := -1
				var ww := 0.0
				for k in 4:
					if bw[i * 4 + k] > ww:
						ww = bw[i * 4 + k]
						bb = bi[i * 4 + k]
				if bb == head:
					pos.append(bv[i])
					nrm.append(an[i].normalized())
	return [pos, nrm]


## Signed burial gap: mean/min over part verts of (signed distance to the
## nearest skin vert). Also counts buried verts (< -0.2mm).
func _browprobe_gap(part: PackedVector3Array, skin_pn: Array) -> Array:
	# Returns [mean_mm, min_mm, buried_count]. Signed on the nearest skin
	# normal: a part vert just inside the surface reads negative.
	var skin: PackedVector3Array = skin_pn[0]
	var snrm: PackedVector3Array = skin_pn[1]
	if part.is_empty() or skin.is_empty():
		return [9999.0, 9999.0, 0]
	var sum := 0.0
	var mn := 1e9
	var buried := 0
	for pv in part:
		var best := 1e18
		var bi := 0
		var k := 0
		while k < skin.size():
			var d2 := pv.distance_squared_to(skin[k])
			if d2 < best:
				best = d2
				bi = k
			k += 4
		var d: Vector3 = pv - skin[bi]
		var sd := d.length()
		if sd > 1e-9:
			sd = signf(d.dot(snrm[bi])) * sd
		else:
			sd = 0.0
		sum += sd
		mn = minf(mn, sd)
		if sd < -0.0002:
			buried += 1
	return [sum / float(part.size()) * 1000.0, mn * 1000.0, buried]


## X-ray debug (TEMP, N / L3): 0 fused, 1 skin only, 2 fused + volumes,
## 3 wireframe (bare geometry — sculpt troubleshooting).
func _cycle_xray() -> void:
	_xray = posmod(_xray + 1, 4)
	_apply_xray()
	print("[XRay] %s" % XRAY_NAMES[_xray])


func _apply_xray() -> void:
	var skin := _avatar_skin_mi()
	var cloth := _avatar_cloth_mi()
	if skin != null:
		skin.visible = true
	if cloth != null:
		cloth.visible = _xray != 1
	if _xray == 2 and not _avatar.last_volumes().is_empty():
		_draw_volumes(_avatar.last_volumes(), _avatar.last_cdata())
	else:
		_clear_volumes()
	var vp := _world()
	_wire = _xray == 3
	if vp != null:
		vp.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if _wire else Viewport.DEBUG_DRAW_DISABLED
	var hud := get_node_or_null("MenuLayer/HUD")
	if hud != null and hud.has_method("set_persistent"):
		hud.set_persistent(&"xray", "XRAY: %s" % XRAY_NAMES[_xray])


## Fused-avatar measurement helpers (delegated, see the delegates block above).


## Fused finger-verts probe (delegated, see the delegates block above).


func _expect(test_name: String, cond: bool) -> int:
	print("[CharTest] %s %s" % ["PASS" if cond else "FAIL", test_name])
	return 0 if cond else 1


## Synthetic key press for headless input tests (real Input state, so the
## InputManager tracks and both vocabularies behave as in-game). The raw
## event construction lives in InputManager.inject_test_key (audit-exempt).
func _chartest_key(code: Key, down: bool) -> void:
	InputManager.inject_test_key(code, down)


## Render capture for headless pixel analysis (--capturetest <path>
## [--nopush] [--nogarments]): lets the AI measure brightness/coverage
## without image input (screenshots are unreadable to it). Needs a real
## renderer: xvfb-run ... --rendering-driver opengl3 <scene> -- <flags>.
func _run_capture_test() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "/tmp/opencode/capture.png"
	var i := args.find("--capturetest")
	if i >= 0 and i + 1 < args.size() and not str(args[i + 1]).begins_with("--"):
		path = str(args[i + 1])
	if "--nopush" in args:
		_set_push_all(0.0)
	if "--nogarments" in args:
		var cloth := _avatar_cloth_mi()
		if cloth != null:
			(cloth as MeshInstance3D).visible = false
	if "--noshadownude" in args:
		var mi := _avatar_mi()
		if mi != null:
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if "--nonormalmap" in args:
		_dresser.no_normal_map = true
		_apply_nude()
		_rebuild_avatar()
	if "--sunflip" in args:
		var sun := _world().get_node_or_null("Sun") as DirectionalLight3D
		if sun != null:
			sun.rotation.y += PI
	if "--noground" in args:
		var ground := _world().get_node_or_null("Ground")
		if ground != null:
			(ground as Node3D).visible = false
	for f in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _world().get_texture().get_image()
	var err := img.save_png(path)
	print("[CaptureTest] saved %s (%dx%d err=%s)" % [path, img.get_width(), img.get_height(), str(err)])
	get_tree().quit()


## Depth-push override (delegated, see the delegates block above).


## Anim-fit probe (--animtest [--animtake=rig/...]): plays a game take on the
## mannequin so the fit can be judged IN MOTION. No retarget: pack and parts
## share the same Standard bones (imports aligned per rig vendor 01/10), so
## one master player on the nude skeleton drives all — part skeletons receive
## copied local poses per frame (manual advance first: zero lag,
## deterministic, pausable).
## Other anims: Remote debugger -> CharacterEditor -> anim_player() -> play().
func anim_player() -> AnimationPlayer:
	return _anim_player


func _animtest_wanted() -> bool:
	if animtest:
		return true
	return "--animtest" in OS.get_cmdline_user_args() or "--animtest" in OS.get_cmdline_args()


func _animtest_take() -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if str(a).begins_with("--animtake="):
			return str(a).trim_prefix("--animtake=")
	return ANIM_DEFAULT_TAKE


## Nude-holder skeleton lookup (delegated, see the delegates block above).


func _animtest_teardown() -> void:
	_anim_active = false
	_anim_master = null
	_anim_targets.clear()
	_anim_pairs.clear()
	if _anim_player != null and is_instance_valid(_anim_player):
		_anim_player.queue_free()
	_anim_player = null


func _animtest_setup() -> void:
	_animtest_teardown()
	_anim_frame = 0
	# Fused avatar: the single skeleton IS the master, part skeletons are
	# gone (freed at fusion) so targets stay empty and nothing is copied.
	var master := _avatar_skeleton()
	if master == null:
		master = _slot_skeleton(&"Nude")
	if master == null:
		push_error("[AnimTest] no avatar/nude skeleton")
		return
	var pack := load(ANIM_PACK) as AnimationLibrary
	if pack == null:
		push_error("[AnimTest] cannot load %s" % ANIM_PACK)
		return
	_anim_player = AnimationPlayer.new()
	_anim_player.name = "AnimTestPlayer"
	add_child(_anim_player)
	_anim_player.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
	var libs := AnimationLibrary.new()
	for anim_name in pack.get_animation_list():
		libs.add_animation(anim_name, _animtest_remap(pack.get_animation(anim_name), master))
	_anim_player.add_animation_library("rig", libs)
	var take := _animtest_take()
	if not _anim_player.has_animation(take):
		take = RigKit.pick(_anim_player, "ual1", ["Walk"])
		print("[AnimTest] take missing, fallback %s" % take)
	if take == &"" or not _anim_player.has_animation(take):
		push_error("[AnimTest] no playable take")
		return
	_anim_master = master
	var holders: Array[String] = ["Nude"]
	for slot in CharacterAvatar.SLOTS:
		holders.append(String(slot))
	var mcount := master.get_bone_count()
	for h in holders:
		var sk := _slot_skeleton(StringName(h))
		if sk == null or sk == master:
			continue
		var pairs := []
		# Vendor parts ship the same 65-bone hierarchy in the same ORDER as
		# the nude master, but under UE names (root/pelvis/spine_01...) while
		# the master speaks Standard (Root/Hips/Spine...) via its import
		# bonemap — name lookup yields zero pairs and frozen garments. When
		# counts match, drive by INDEX (probe 01/10: 65/65, order identical,
		# only the naming convention differs); else fall back to names with
		# a warning per unmapped bone (never silent).
		if sk.get_bone_count() == mcount:
			for mi in range(mcount):
				pairs.append([mi, mi])
			print("[AnimTest] pairs %s %d/%d (by index)" % [h, pairs.size(), mcount])
		else:
			var missing := []
			for mi in range(mcount):
				var ti := sk.find_bone(master.get_bone_name(mi))
				if ti != -1:
					pairs.append([mi, ti])
				else:
					missing.append(String(master.get_bone_name(mi)))
			print("[AnimTest] pairs %s %d/%d (by name, count mismatch %d vs %d)" % [h, pairs.size(), mcount, sk.get_bone_count(), mcount])
			if not missing.is_empty():
				push_warning("[AnimTest] %s unmapped: %s" % [h, ",".join(missing)])
		_anim_targets.append(sk)
		_anim_pairs.append(pairs)
	_anim_player.play(take)
	_anim_master = master
	_anim_active = true
	_idle_only = false
	if _anim_targets.is_empty():
		print("[AnimTest] playing %s on fused %s (0 part skeletons, nothing copied), player %s" % [take, master.get_path(), _anim_player.get_path()])
	else:
		print("[AnimTest] playing %s on %s (+%d part skeletons), player %s" % [take, master.get_path(), _anim_targets.size(), _anim_player.get_path()])
	print("[AnimTest] Remote: CharacterEditor.anim_player().play(\"rig/<take>\")")


## Copy of a pack take with every bone track rebound to the master skeleton.
## Identity mapping (01/10 rebake): pack and skeletons both speak Standard
## (imports re-aligned per rig vendor, leafs stripped at bake) — a take bone
## the master does not own is dropped + reported, never silent.
func _animtest_remap(anim: Animation, master: Skeleton3D) -> Animation:
	var out := anim.duplicate()
	out.set_loop_mode(Animation.LOOP_LINEAR)
	# Paths resolve against the player's root_node (default ".." = this
	# editor), NOT against the player itself: base is self->master.
	var base := str(get_path_to(master))
	var dropped := []
	for i in range(anim.get_track_count() - 1, -1, -1):
		var t := anim.track_get_type(i)
		var p: NodePath = anim.track_get_path(i)
		if (t == Animation.TYPE_POSITION_3D or t == Animation.TYPE_ROTATION_3D or t == Animation.TYPE_SCALE_3D) and p.get_subname_count() > 0:
			var dst := str(p.get_subname(0))
			if master.find_bone(dst) == -1:
				if not dropped.has(dst):
					dropped.append(dst)
				out.remove_track(i)
				continue
			out.track_set_path(i, NodePath(base + ":" + dst))
		else:
			out.remove_track(i)
	if not dropped.is_empty():
		dropped.erase("Root") # by design: Root stays fixed (same call as RigKit REV 31)
		if not dropped.is_empty():
			print("[AnimTest] unmapped bones dropped: %s" % ",".join(dropped))
	return out


func _process(delta: float) -> void:
	if InputManager.is_just_pressed(&"xray_toggle"):
		_cycle_xray()
	if InputManager.is_just_pressed(&"gender_toggle"):
		# TEMP debug (removed with xray_toggle): same path as the Gender
		# menu row, plus a menu refresh so value rows never show stale text.
		adjust_gender(1)
		if _menu != null:
			_menu._refresh_list()
	if not _anim_active or _anim_player == null or _anim_master == null:
		return
	if not is_instance_valid(_anim_master):
		return
	# Idle preview holds its opening pose (no sway, live request): only the
	# animtest probe advances here; the face-submenu pause still gates it.
	if _anim_player.is_playing() and not _anim_paused and _animtest_wanted():
		_anim_player.advance(delta)
	_anim_frame += 1
	if _anim_frame == 60:
		var moved := 0
		for b in _anim_master.get_bone_count():
			if not _anim_master.get_bone_pose(b).is_equal_approx(Transform3D.IDENTITY):
				moved += 1
		print("[AnimTest] motion check @f60: %d/%d master bones off rest" % [moved, _anim_master.get_bone_count()])
	for t in range(_anim_targets.size()):
		var tgt := _anim_targets[t]
		if not is_instance_valid(tgt):
			continue
		var pairs: Array = _anim_pairs[t]
		for p in pairs:
			var mi: int = p[0]
			var ti: int = p[1]
			tgt.set_bone_pose_position(ti, _anim_master.get_bone_pose_position(mi))
			tgt.set_bone_pose_rotation(ti, _anim_master.get_bone_pose_rotation(mi))
			tgt.set_bone_pose_scale(ti, _anim_master.get_bone_pose_scale(mi))
