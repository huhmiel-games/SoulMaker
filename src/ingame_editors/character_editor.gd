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
	add_child(_avatar)
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
	if _animtest_wanted():
		_animtest_setup()
	else:
		_idle_setup()


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


## Idle preview: same manual-advance player as the probe but a single take
## remapped (cheap per rebuild) instead of the whole 161-take pack.
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
	_anim_player.play(IDLE_TAKE)
	_anim_master = master
	_anim_active = true
	_idle_only = true
	print("[Idle] playing %s on %s" % [IDLE_TAKE, master.get_path()])


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
	var old := get_node_or_null("Volumes")
	if old != null:
		remove_child(old)
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
	return get_node_or_null("CamPivot") as Node3D


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


func phys_display(key: StringName) -> String:
	return _avatar.phys_display(key)


func adjust_phys(key: StringName, dir: int) -> void:
	_avatar.adjust_phys(key, dir)


func reset_phys(key: StringName) -> void:
	_avatar.reset_phys(key)


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
	var holder := get_node_or_null("Avatar/" + slot) as Node3D
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
	var holder := get_node_or_null("Avatar/" + slot) as Node3D
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
	var holder := get_node_or_null("Avatar/Eyes") as Node3D
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
	# Both nudes skip brows/eyes at import; only male ships part files yet:
	# female has no brows/eyes at all until its export pass (pinned gap).
	fails += _expect("female brow absent", _slot_mats(&"Eyebrows").is_empty())
	fails += _expect("female eyes absent", _slot_mats(&"Eyes").is_empty())
	fails += _expect("female lashes absent", _slot_mats(&"Eyelashes").is_empty())
	fails += _expect("female brow no file", eyebrow_file("Female", &"Default").is_empty())
	fails += _expect("female eyes no file", eye_file("Female", &"Default").is_empty())
	fails += _expect("female lashes no file", eyelash_file("Female", &"Default").is_empty())
	_avatar._outfit[&"Body"] = 2
	_apply_nude()
	_rebuild_avatar()
	fails += _expect("body B shown", slot_display(&"Body") == "PeasantB")
	fails += _expect("body B fused", _avatar_mi() != null and _avatar_surf_count() > 1)
	reset_slot(&"Body")
	reset_gender()
	reset_slot(&"Body")
	fails += _expect("back to male peasant", gender_display() == "Male" and slot_display(&"Body") == "Peasant")
	fails += _expect("male avatar fused", _avatar_mi() != null and _avatar_surf_count() > 1)
	fails += _expect("male hands kept", _avatar_finger_verts() > 100)
	fails += _expect("skin push on", _avatar_push("SuperHero") > 0.01)
	# Male nude skips brows/eyes at import: the mounted parts stand in.
	fails += _expect("male brows mounted", get_node_or_null("Avatar/Eyebrows/Male_Eyebrows") != null)
	fails += _expect("male eyes mounted", get_node_or_null("Avatar/Eyes/Male_Eyes") != null)
	fails += _expect("male lashes mounted", get_node_or_null("Avatar/Eyelashes/Male_Eyelashes") != null)
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
	fails += _expect("xray volumes", _avatar_skin_mi().visible and _avatar_cloth_mi().visible and get_node_or_null("Volumes") != null)
	_cycle_xray()
	fails += _expect("xray wire", _wire and XRAY_NAMES[_xray] == "Wire" and _avatar_skin_mi().visible and _avatar_cloth_mi().visible)
	_cycle_xray()
	fails += _expect("xray back to fused", not _wire and _xray == 0 and _avatar_skin_mi().visible and _avatar_cloth_mi().visible and get_node_or_null("Volumes") == null)
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
		fails += _expect("menu A/E resets outfit", slot_display(&"Body") == "Peasant")
	_menu._pop()
	# 5. Four-level menu (root/outfits/colors/physics) + idle preview.
	var root_labels := []
	for e in _menu._entries:
		root_labels.append(String((e as Dictionary).get("label", "")))
	fails += _expect("menu root outfits", root_labels.has("Outfits >"))
	fails += _expect("menu root outfit colors", root_labels.has("Outfits Colors >"))
	fails += _expect("menu root physics", root_labels.has("Physics >"))
	fails += _expect("menu root hair", root_labels.has("Hair >"))
	fails += _expect("menu root eyebrows", root_labels.has("Eyebrows >"))
	fails += _expect("menu root eyes", root_labels.has("Eyes >"))
	fails += _expect("menu root beard", root_labels.has("Beard >"))
	fails += _expect("menu root face", root_labels.has("Face >"))
	fails += _expect("menu root skin", root_labels.has("Skin >"))
	_menu._push(CharacterMenu.LEVEL_COLORS)
	fails += _expect("menu outfit colors 6+back", _menu._entries.size() == 7)
	_menu._push(CharacterMenu.LEVEL_PHYSICS)
	fails += _expect("menu physics 6+back", _menu._entries.size() == 7)
	_menu._pop()
	var want_take := _animtest_take() if _animtest_wanted() else IDLE_TAKE
	fails += _expect("preview anim playing", _anim_player != null and _anim_player.current_animation == want_take)
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
	var hmi := get_node_or_null("Avatar/Hair/Buzzed") as MeshInstance3D
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
	fails += _expect("hair reset bald", hair_display() == "None" and get_node_or_null("Avatar/Hair/Buzzed") == null)
	open_color(&"Hair")
	fails += _expect("hair color empty no-op", not is_color_open())
	_menu._push(CharacterMenu.LEVEL_HAIR)
	fails += _expect("menu hair rows", _menu._entries.size() == 3)
	fails += _expect("face cam on hair", face_active())
	_menu._pop()
	fails += _expect("face cam off hair", not face_active())
	# 7. Eyebrows (mounted male part, fused female fallback, own color slot, face cam).
	fails += _expect("brow style default", eyebrow_display() == "Default")
	adjust_eyebrow(1)
	fails += _expect("brow style single", eyebrow_display() == "Default")
	reset_eyebrow()
	fails += _expect("brow file male", eyebrow_file("Male", &"Default").ends_with("Male_Eyebrows.gltf"))
	var bmi2 := get_node_or_null("Avatar/Eyebrows/Male_Eyebrows") as MeshInstance3D
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
	fails += _expect("menu brow rows", _menu._entries.size() == 3)
	var pivot := get_node_or_null("CamPivot") as Node3D
	var arm := (pivot.get_node_or_null("SpringArm3D") as SpringArm3D) if pivot != null else null
	fails += _expect("face cam close", face_active() and arm != null and is_equal_approx(arm.spring_length, FACE_ARM))
	fails += _expect("face cam at head", pivot != null and pivot.position.y > _head_world().y)
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
	var emi := get_node_or_null("Avatar/Eyes/Male_Eyes") as MeshInstance3D
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
	fails += _expect("menu eyes rows", _menu._entries.size() == 3)
	fails += _expect("face cam on eyes", face_active())
	_menu._pop()
	fails += _expect("face cam off eyes", not face_active())
	# 9b. Eyelashes (mounted male part, no nude counterpart, no menu: albedo
	# defaults like hair; female ships no file yet).
	fails += _expect("lash file male", eyelash_file("Male", &"Default").ends_with("Male_Eyelashes.gltf"))
	var lmi := get_node_or_null("Avatar/Eyelashes/Male_Eyelashes") as MeshInstance3D
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
	# 9c. Face-part follow (09/10): socket rows bake the mask-mean into the
	# rigid parts (mesh space, anim-exact); unrelated rows leave them pristine.
	var eyes0 := _face_part_mean("Eyes")
	adjust_face_sculpt(&"EyeDepth", 8)
	var eyes1 := _face_part_mean("Eyes")
	fails += _expect("eyes follow out", eyes1.z > eyes0.z + 0.006)
	fails += _expect("eyes follow baked", _avatar._face_pristine.has("Eyes") and get_node_or_null("Avatar/Eyes/Male_Eyes") != null and (get_node_or_null("Avatar/Eyes/Male_Eyes") as MeshInstance3D).mesh != _avatar._face_pristine["Eyes"])
	reset_face_sculpt(&"EyeDepth")
	fails += _expect("eyes follow restores", (get_node_or_null("Avatar/Eyes/Male_Eyes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyes"])
	var lash0 := _face_part_mean("Eyelashes")
	adjust_face_sculpt(&"EyelidHeavy", 8)
	var lash1 := _face_part_mean("Eyelashes")
	fails += _expect("lashes follow lid", lash1.y < lash0.y - 0.003)
	fails += _expect("eyes ignore lid", (get_node_or_null("Avatar/Eyes/Male_Eyes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyes"])
	reset_face_sculpt(&"EyelidHeavy")
	fails += _expect("lashes follow restores", (get_node_or_null("Avatar/Eyelashes/Male_Eyelashes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyelashes"])
	var brow0 := _face_part_mean("Eyebrows")
	adjust_face_sculpt(&"BrowRidgeDepth", 8)
	var brow1 := _face_part_mean("Eyebrows")
	fails += _expect("brows follow ridge", brow1.z > brow0.z + 0.003)
	reset_face_sculpt(&"BrowRidgeDepth")
	fails += _expect("brows follow restores", (get_node_or_null("Avatar/Eyebrows/Male_Eyebrows") as MeshInstance3D).mesh == _avatar._face_pristine["Eyebrows"])
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
	fails += _expect("eyes space restores", (get_node_or_null("Avatar/Eyes/Male_Eyes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyes"])
	fails += _expect("lashes space restores", (get_node_or_null("Avatar/Eyelashes/Male_Eyelashes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyelashes"])
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
	adjust_face_sculpt(&"EyeAngle", 8)
	fails += _expect("eyes ignore angle", (get_node_or_null("Avatar/Eyes/Male_Eyes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyes"])
	var lan1 := _face_part_verts("Eyelashes")
	var lod := _face_part_outer_dy(lan0, lan1)
	fails += _expect("lashes ride tilt", int(lod[1]) > 0 and float(lod[0]) < -0.0005)
	reset_face_sculpt(&"EyeAngle")
	fails += _expect("lashes tilt restores", (get_node_or_null("Avatar/Eyelashes/Male_Eyelashes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyelashes"])
	# Brows ride their own tilt (same rigid-rotation follow as lashes).
	var brw0 := _face_part_verts("Eyebrows")
	adjust_face_sculpt(&"BrowAngle", 8)
	var brw1 := _face_part_verts("Eyebrows")
	var brd := _face_part_outer_dy(brw0, brw1)
	fails += _expect("brows ride tilt", int(brd[1]) > 0 and float(brd[0]) < -0.0005)
	reset_face_sculpt(&"BrowAngle")
	fails += _expect("brows tilt restores", (get_node_or_null("Avatar/Eyebrows/Male_Eyebrows") as MeshInstance3D).mesh == _avatar._face_pristine["Eyebrows"])
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
	fails += _expect("brows thick restores", (get_node_or_null("Avatar/Eyebrows/Male_Eyebrows") as MeshInstance3D).mesh == _avatar._face_pristine["Eyebrows"])
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
	adjust_face_sculpt(&"ForeheadHeight", 8)
	var hafter := _face_part_verts("Hair")
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
	fails += _expect("eyes ignore forehead", (get_node_or_null("Avatar/Eyes/Male_Eyes") as MeshInstance3D).mesh == _avatar._face_pristine["Eyes"])
	reset_face_sculpt(&"ForeheadHeight")
	fails += _expect("hair follow restores", (get_node_or_null("Avatar/Hair/Buzzed") as MeshInstance3D).mesh == _avatar._face_pristine["Hair"])
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
	fails += _expect("hair width restores", (get_node_or_null("Avatar/Hair/Buzzed") as MeshInstance3D).mesh == _avatar._face_pristine["Hair"])
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
	for bk in [&"JawWidth", &"JawDefinition", &"JawAngle", &"ChinLength", &"ChinWidth", &"ChinProject", &"ChinCleft"]:
		adjust_face_sculpt(bk, 8)
		fails += _expect("beard wired %s" % String(bk), (get_node_or_null("Avatar/Beard/Beard") as MeshInstance3D).mesh != _avatar._face_pristine["Beard"])
		reset_face_sculpt(bk)
	fails += _expect("beard jaw restores", (get_node_or_null("Avatar/Beard/Beard") as MeshInstance3D).mesh == _avatar._face_pristine["Beard"])
	adjust_face_sculpt(&"EyeDepth", 8)
	fails += _expect("beard ignores eyes", (get_node_or_null("Avatar/Beard/Beard") as MeshInstance3D).mesh == _avatar._face_pristine["Beard"])
	reset_face_sculpt(&"EyeDepth")
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
	var bmi := get_node_or_null("Avatar/Beard/Beard") as MeshInstance3D
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
	fails += _expect("beard reset clean", beard_display() == "None" and get_node_or_null("Avatar/Beard/Beard") == null)
	_menu._push(CharacterMenu.LEVEL_BEARD)
	fails += _expect("menu beard rows", _menu._entries.size() == 3)
	fails += _expect("face cam on beard", face_active())
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
	var cam := get_node_or_null("CamPivot/SpringArm3D/Camera3D") as Camera3D
	fails += _expect("editor camera centered", cam != null and is_zero_approx(cam.position.x))
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
	fails += _expect("menu face hub 7+back", _menu._entries.size() == CharacterMenu.FACE_SUBS.size() + 1)
	fails += _expect("face cam on hub", face_active())
	fails += _expect("face pauses idle", _anim_paused == _idle_only)
	# Each sub: its rows + Back; Back returns to the hub (two-level Back).
	_menu._push(CharacterMenu.LEVEL_FACE_GLOBAL)
	fails += _expect("menu face global rows", _menu._entries.size() == CharacterAvatar.FACE_KEYS.size() + 1)
	fails += _expect("face cam on sub", face_active())
	_menu._pop()
	fails += _expect("menu back to hub", _menu._level == CharacterMenu.LEVEL_FACE and _menu._entries.size() == CharacterMenu.FACE_SUBS.size() + 1)
	fails += _expect("face cam stays on hub", face_active())
	_menu._push(CharacterMenu.LEVEL_FACE_NOSE)
	fails += _expect("menu face nose rows", _menu._entries.size() == 10 + 1)
	# 11b. Menu wiring (live report 08/10: a row seemingly driving another).
	# Drives EVERY nose row through its own entry callables: the row's own
	# key must read +1mm, all others +0mm, then reset restores.
	reset_face_sculpt(&"NoseW")
	reset_face_sculpt(&"NoseCurve")
	var wrow := {}
	for e in _menu._entries:
		if String((e as Dictionary).get("label", "")) == "NoseW":
			wrow = e
	if wrow.is_empty():
		fails += _expect("menu noseW row present", false)
	else:
		(wrow["adjust"] as Callable).call(1)
		fails += _expect("menu noseW drives noseW", face_sculpt_display(&"NoseW") == "+1mm")
		fails += _expect("menu noseW spares curve", face_sculpt_display(&"NoseCurve") == "+0mm")
		(wrow["reset"] as Callable).call()
		fails += _expect("menu noseW reset", face_sculpt_display(&"NoseW") == "+0mm")
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
	fails += _expect("menu face eyes rows", _menu._entries.size() == 10 + 1)
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
	fails += _expect("menu back to hub forehead", _menu._level == CharacterMenu.LEVEL_FACE)
	_menu._pop()
	fails += _expect("face cam off face", not face_active())
	fails += _expect("face resumes", not _anim_paused)
	# 12. Face sculpt (JSON regions, live on fused Skin, defaults no-op).
	fails += _expect("sculpt json male", not (_avatar._sculpt_regions() as Dictionary).is_empty())
	fails += _expect("sculpt nose mask", int(((_avatar._sculpt_regions() as Dictionary).get("Nose", {}) as Dictionary).get("n", 0)) > 0)
	fails += _expect("sculpt defaults zero", face_sculpt_display(&"NoseL") == "+0mm" and face_sculpt_display(&"Chin") == "+0mm")
	var tip0 := _nose_tip_z()
	adjust_face_sculpt(&"NoseL", 5) # +5mm forward, tip rides at full weight
	fails += _expect("sculpt nose shown", face_sculpt_display(&"NoseL") == "+5mm")
	fails += _expect("sculpt nose grows", _nose_tip_z() > tip0 + 0.003 and _nose_tip_z() < tip0 + 0.007)
	adjust_face_sculpt(&"NoseL", 3) # total +8mm from pristine (no accumulation)
	fails += _expect("sculpt no accumulate", _nose_tip_z() > tip0 + 0.006 and _nose_tip_z() < tip0 + 0.010)
	adjust_face_sculpt(&"NoseW", 5)
	fails += _expect("sculpt width symmetric", _head_verts_symmetric())
	reset_face_sculpt(&"NoseL")
	reset_face_sculpt(&"NoseW")
	fails += _expect("sculpt reset restores", is_equal_approx(_nose_tip_z(), tip0))
	adjust_face_sculpt(&"Chin", 200) # clamp to +10mm
	fails += _expect("sculpt chin clamped", face_sculpt_display(&"Chin") == "+10mm")
	reset_face_sculpt(&"Chin")
	adjust_face_sculpt(&"MouthW", -200) # clamp to -8mm
	fails += _expect("sculpt mouth clamped", face_sculpt_display(&"MouthW") == "-8mm")
	reset_face_sculpt(&"MouthW")
	# 13. Sculpt round 2 (user eye-tune 07/10: negatives, base-vs-bridge, chin drop).
	adjust_face_sculpt(&"NoseL", -5) # front pad catches the tip: retracts
	fails += _expect("sculpt nose back", _nose_tip_z() < tip0 - 0.002)
	reset_face_sculpt(&"NoseL")
	var nose_pair := _sculpt_deltas(&"NoseW", 8)
	fails += _expect("sculpt nose base most", _flank_moves_most("Nose", nose_pair[0], nose_pair[1]))
	fails += _expect("sculpt nose no cross", _no_center_cross(nose_pair[0], nose_pair[1]))
	var mouth_pair := _sculpt_deltas(&"MouthW", -5)
	fails += _expect("sculpt mouth narrows", _gated_narrow(mouth_pair[0], mouth_pair[1], "Mouth"))
	fails += _expect("sculpt mouth no cross", _no_center_cross(mouth_pair[0], mouth_pair[1]))
	var chin_back_pair := _sculpt_deltas(&"Chin", -5) # weak chin recedes+rises
	fails += _expect("sculpt chin back", _chin_moved(chin_back_pair[0], chin_back_pair[1], -1.0))
	var chin_pair := _sculpt_deltas(&"Chin", 10)
	fails += _expect("sculpt chin drops", _chin_moved(chin_pair[0], chin_pair[1], 1.0))
	# 14. Sculpt round 3: outline follows (live Chin plateau 07/10 — the old
	# mean-based asserts passed while the contour froze at -2).
	var chin_f0 := _chin_front_z()
	adjust_face_sculpt(&"Chin", -2)
	var chin_f2 := _chin_front_z()
	adjust_face_sculpt(&"Chin", -3) # total -5 from pristine (single pass, no path)
	var chin_f5 := _chin_front_z()
	reset_face_sculpt(&"Chin")
	fails += _expect("sculpt chin no plateau", chin_f5 < chin_f2 - 0.001 and chin_f2 < chin_f0 - 0.0005)
	var nose_f0 := _nose_tip_z()
	adjust_face_sculpt(&"NoseL", -8)
	fails += _expect("sculpt nose follows neg", _nose_tip_z() < nose_f0 - 0.006)
	reset_face_sculpt(&"NoseL")
	var nose_w_neg := _sculpt_deltas(&"NoseW", -8)
	var nose_core := _core_widths(nose_w_neg[0], nose_w_neg[1], "Nose")
	fails += _expect("sculpt nose core narrows", nose_core.size() == 2 and nose_core[1] < nose_core[0] - 0.001)
	var mouth_w_pos := _sculpt_deltas(&"MouthW", 5)
	var mouth_core := _core_widths(mouth_w_pos[0], mouth_w_pos[1], "Mouth")
	fails += _expect("sculpt mouth core widens", mouth_core.size() == 2 and mouth_core[1] > mouth_core[0] + 0.001)
	# 15. Sculpt diffusion (08/10: crevasses at extremes — the rim must
	# follow instead of cliffing at the box edge).
	for ce in [[&"NoseL", -10], [&"NoseW", 8], [&"Chin", -10], [&"MouthW", -8], [&"MouthW", 8], [&"NoseLength", 10], [&"NosePosition", 8], [&"LipUpper", 8], [&"LipLower", 8], [&"MouthCorners", 8], [&"MouthPosition", 8], [&"MouthForward", 8], [&"NoseTipSize", 10], [&"NoseTipAngle", 10], [&"NoseCurve", 10], [&"MouthPout", 8], [&"EyelidHeavy", 8], [&"EyeDepth", 8], [&"EyeHeight", 8], [&"EyeSpacing", 8], [&"EyeSize", 8], [&"EyeAngle", 8], [&"BrowAngle", 8], [&"BrowDepth", 8], [&"JawWidth", 8], [&"JawDefinition", 8], [&"JawAngle", 8], [&"ChinLength", 10], [&"ChinWidth", 8], [&"ChinProject", 10], [&"ChinCleft", 5], [&"CheekboneWidth", 8], [&"CheekboneHeight", 8], [&"CheekFullness", 8], [&"FaceFullness", 8], [&"ForeheadHeight", 8], [&"ForeheadWidth", 8], [&"BrowRidgeDepth", 8], [&"EarSize", 8], [&"EarRotation", 8], [&"EarlobeLength", 8], [&"EarPoint", 8]]:
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
	for nk in [&"NoseBridge", &"NoseTip", &"NostrilFlare", &"NoseLength", &"NosePosition", &"LipUpper", &"LipLower", &"MouthCorners", &"MouthPosition", &"MouthForward", &"NoseTipSize", &"NoseTipAngle", &"NoseCurve", &"MouthPout", &"EyelidHeavy", &"EyeDepth", &"EyeHeight", &"EyeSpacing", &"EyeSize", &"EyeAngle", &"BrowAngle", &"BrowHeight", &"BrowThick", &"BrowDepth", &"JawWidth", &"JawDefinition", &"JawAngle", &"ChinLength", &"ChinWidth", &"ChinProject", &"ChinCleft", &"CheekboneWidth", &"CheekboneHeight", &"CheekFullness", &"FaceFullness", &"ForeheadHeight", &"ForeheadWidth", &"BrowRidgeDepth", &"EarSize", &"EarRotation", &"EarlobeLength", &"EarPoint"]:
		reset_face_sculpt(nk)
		adjust_face_sculpt(nk, 10)
		fails += _expect("sculpt %s moves" % String(nk), _avatar.sculpt_max_cliff() > 1e-9)
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
	# 17b. Row superposition (08/10 live bug: one NoseW step visibly
	# flattened NoseCurve — the shared wmax let the Nose mask flip the
	# bridge halo verts to mask and snap their 6mm halo back to ~0).
	# Per-key diffusion: adding an X/Y row must not move any Z.
	for combo in [[&"NoseW", 1], [&"NosePosition", 1]]:
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
	var len_pair := _sculpt_deltas(&"NoseLength", 10)
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
	var vp := get_viewport()
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
		var sun := get_node_or_null("Sun") as DirectionalLight3D
		if sun != null:
			sun.rotation.y += PI
	if "--noground" in args:
		var ground := get_node_or_null("Ground")
		if ground != null:
			(ground as Node3D).visible = false
	for f in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
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
	if not _anim_active or _anim_player == null or _anim_master == null:
		return
	if not is_instance_valid(_anim_master):
		return
	if _anim_player.is_playing() and not _anim_paused:
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
