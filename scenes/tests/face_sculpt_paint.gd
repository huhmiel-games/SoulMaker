extends Node3D

## Face-sculpt region painter (DEV TOOL — lives in scenes/tests, outside src/,
## so the ingame input-parity rule and input_audit do not apply; raw mouse is
## intentional here). Run scenes/tests/face_sculpt_author.tscn live and paint
## triangles on the nude preview. The headless exporter resolves the painted
## tris to Head-frame points (shipped JSON); tri indices never leave this
## authoring-local work file.
## Controls:
##   L-click / L-drag = add triangle, R-click = delete triangle under cursor
##   Ctrl+Z = undo (add or delete), Middle-drag = orbit,
##   Shift+middle-drag = pan, wheel = dolly (x0.93 / x1.08)
##   1..9 = jump to region (first nine), Tab / Shift+Tab = cycle all regions
##   G = grow 1 topology ring, T = shrink (drop outer ring)
##   C = clear region, P = save work file
##   V = wireframe on/off, F = reframe camera on the head
## Diag: every click prints hit/miss + surf/tri; the HUD shows the camera
## target, the last pick result and the wireframe state.
## Work file: scenes/tests/face_sculpt_work.json (tri pairs, authoring-local).
## Surface enumeration is the exporter's static (byte-identical order both
## sides). No boxes: every region is hand-painted per-triangle.

const BakeLib = preload("res://src/cli_tools/export_face_sculpt.gd")

const WORK_PATH := "res://scenes/tests/face_sculpt_work.json"
const REGIONS: Array[String] = [
	"Nose", "NoseLength", "NoseBridge", "NoseTip", "NostrilFlare",
	"Mouth", "UpperLip", "LowerLip", "MouthCorners", "MouthPout",
	"Eyelids", "UpperEyelid", "Brows", "BrowRidge",
	"Jaw", "Chin", "ChinCleft",
	"Cheekbones", "Cheeks", "LowerFace",
	"Forehead", "Ears",
]
const GENDER := "Male"
## Paint guide per region (button tooltips, condensed from TODO.md).
const REGION_TIPS := {
	"Nose": "Tout le nez (région mère).
Prendre : ailes + arête + POINTE + narines, du haut
entre les yeux jusqu'en bas. La pointe avant est
OBLIGATOIRE (c'est elle que la row Longueur pousse).
Les sous-régions découpent le détail par-dessus.",
	"NoseLength": "Réserve (row Position future).
Même zone que Nose. Peindre les deux ou une seule,
l'export les garde séparées.",
	"NoseBridge": "La ligne du milieu (détail, chevauche Nose).
Prendre : bande étroite (2-3 tris) du haut entre
les yeux jusqu'au-dessus de la pointe.
Garder ces tris AUSSI dans Nose.",
	"NoseTip": "La boule du bout (détail, chevauche Nose).
Prendre : la boule + bas de la ligne du milieu
sur un demi-centimètre.
Garder ces tris AUSSI dans Nose.",
	"NostrilFlare": "Les renflements (détail, chevauche Nose).
Prendre : les 2 ailes (parties rondes qui gonflent
quand on respire fort).
Garder ces tris AUSSI dans Nose.",
	"Mouth": "Les 2 lèvres ensemble (région mère).
Prendre : lèvre du haut + lèvre du bas, d'un coin
de bouche à l'autre, coins inclus. Les sous-régions
(Upper/Lower/Corners) chevauchent, ne déménagent pas.",
	"UpperLip": "La lèvre du haut seule.\nPrendre : entre la fente de la bouche et le sillon sous le nez, d'un\ncoin à l'autre.\nNe pas prendre : la lèvre du bas.",
	"LowerLip": "La lèvre du bas seule.\nPrendre : entre la fente de la bouche et le haut du menton, d'un\ncoin à l'autre.\nNe pas prendre : la lèvre du haut.",
	"MouthCorners": "Les coins de la bouche.\nPrendre : les 2 coins + les 2-3 petits tris autour de chaque coin\n(c'est eux qui montent pour un sourire ou descendent pour une moue).\nZone minuscule.",
	"MouthPout": "La moue.\nPrendre : la lèvre du haut + le sillon sous le nez (philtrum) qui\navance avec.\nSert à avancer la bouche.",
	"Eyelids": "Le tour des yeux.\nPrendre : paupière du haut + paupière du bas + le pourtour (l'os\nautour de l'œil), des 2 côtés.\nNe JAMAIS prendre : les boules des yeux (blanc + iris) — ce sont\nd'autres meshes, elles bougent toutes seules.",
	"UpperEyelid": "La paupière du haut seule.\nPrendre : du ras des cils jusqu'au pli (la ligne où la paupière se\nplie), des 2 côtés.\nSert aux paupières lourdes ou tombantes.",
	"Brows": "Les sourcils.\nPrendre : tout le mesh des sourcils (c'est la 2e surface, facile à\nattraper en entier) puis rogner au clic droit ce qui dépasse.\nSert à monter, épaissir ou pencher.",
	"BrowRidge": "L'os sous le sourcil.\nPrendre : la bande de peau dure juste sous chaque sourcil\n(l'arcade), pas le sourcil lui-même (poils).\nSert à l'arcade saillante ou effacée.",
	"Jaw": "La mâchoire.\nPrendre : les 2 angles en bas près des oreilles (les coins durs\nqu'on sent sous les oreilles = gonions) + les branches qui remontent\nvers les oreilles.\nNe pas prendre : le menton devant ni les joues.",
	"Chin": "Le menton.\nPrendre : la boule du menton + sa pointe en bas.\nNe pas prendre : la lèvre du bas au-dessus ni la mâchoire sur les côtés.",
	"ChinCleft": "La fossette du menton.\nPrendre : les quelques tris pile au milieu du menton (symétrique :\nautant à gauche qu'à droite).\nZone minuscule — 1 clic + G suffit souvent.",
	"Cheekbones": "Les pommettes.\nPrendre : les reliefs durs sous le coin externe de chaque œil (l'os\nqu'on sent en souriant). Ne pas descendre vers la bouche ni vers le\nnez.",
	"Cheeks": "Les joues molles.\nPrendre : la partie qui se creuse quand on aspire les joues, entre\npommettes, nez et mâchoire.\nC'est la zone joues pleines / joues creuses.",
	"LowerFace": "Le bas du visage.\nPrendre : les joues basses + le contour entre le menton et les\nangles de mâchoire (la zone de la « graisse du bas du visage »).",
	"Forehead": "Le front.\nPrendre : la peau entre les sourcils et la racine des cheveux.\nNe pas prendre : les cheveux eux-mêmes (autre mesh) ni les sourcils\nen bas.",
	"Ears": "Les oreilles.\nPrendre : les 2 pavillons en entier, lobe (bout mou en bas) inclus.\nPour le lobe seul : ne garder que le bout mou du bas.",
}

var _surfs := [] # [{mi, verts, idx}] exporter enumeration on the live preview
var _head_inv := Transform3D.IDENTITY
var _head_pos := Vector3(0.0, 1.6, 0.1)
var _sel := {} # region -> {"set": Dictionary key->ring, "order": Array}
var _undo := [] # stack of {"region": r, "add": [[si,ti]..]} / {"region": r, "del": [[si,ti,ring]..]}
var _region := 0
var _adj := [] # per surf: Dictionary vertkey -> PackedInt32Array tris
var _overlays := {} # surf index -> MeshInstance3D
var _mat: StandardMaterial3D = null
var _label: Label = null
var _cam: Camera3D = null
var _target := Vector3(0.0, 1.6, 0.1)
var _yaw := 0.0
var _pitch := -0.08
var _dist := 0.34
var _l_held := false
var _r_down := Vector2.ZERO
var _r_moved := false
var _wire := false
var _wire_mode := 0 # 0 off, 1 edge overlay on skin, 2 full-viewport wireframe
var _wire_mat: StandardMaterial3D = null
var _wire_overlays := {} # surf index -> MeshInstance3D (all topology edges)
var _last_pick := "no click yet"
var _ui: CanvasLayer = null
var _region_btns := {} # region -> Button (side panel, radio behavior)


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_run_painttest()
		return
	for r in REGIONS:
		_sel[r] = {"set": {}, "order": []}
	_load_work()
	var preview := get_node_or_null("MalePreview")
	if preview == null:
		push_error("[Paint] MalePreview missing")
		return
	_surfs = BakeLib.paintable_surfaces(preview)
	if _surfs.is_empty():
		push_error("[Paint] no paintable surfaces")
		return
	_head_inv = _live_head_inv(preview)
	_build_rig()
	_build_panel()
	_build_pick()
	_build_overlays()
	_build_wire_overlays()
	_refresh_all_overlays()
	_update_hud()
	print("[Paint] ready: %d surfaces, region %s (keys 1-6, L paint, R remove, G/T grow/shrink, B box, C clear, P save)" % [_surfs.size(), REGIONS[_region]])


## Headless self-test: enumeration parity + box-rule sanity, no interaction.
func _run_painttest() -> void:
	var preview := get_node_or_null("MalePreview")
	var fails := 0
	if preview == null:
		push_error("[PaintTest] MalePreview missing")
		get_tree().quit(1)
		return
	var surfs := BakeLib.paintable_surfaces(preview)
	print("[PaintTest] surfaces=%d" % surfs.size())
	if surfs.is_empty():
		fails += 1
	var ntris := 0
	for e in surfs:
		var verts: PackedVector3Array = (e as Dictionary)["verts"]
		var idx: PackedInt32Array = (e as Dictionary)["idx"]
		ntris += idx.size() / 3 if not idx.is_empty() else verts.size() / 3
	print("[PaintTest] tris=%d" % ntris)
	if ntris < 1000:
		fails += 1
	var hw: Variant = BakeLib.head_world_of(preview)
	if hw == null:
		fails += 1
	else:
		print("[PaintTest] head frame ok")
	# Nearest-tri fallback: feed a known centroid back, expect its own tri.
	_surfs = surfs
	for r in REGIONS:
		_sel[r] = {"set": {}, "order": []}
	for e in surfs:
		var ed: Dictionary = e
		var ev: PackedVector3Array = ed["verts"]
		var ei: PackedInt32Array = ed["idx"]
		ed["ntris"] = ei.size() / 3 if not ei.is_empty() else ev.size() / 3
	_build_adj()
	var e0: Dictionary = surfs[0]
	var v0: PackedVector3Array = e0["verts"]
	var i0: PackedInt32Array = e0["idx"]
	var n0 := i0.size() / 3 if i0.size() == v0.size() else v0.size() / 3
	e0["centroids"] = centroids_of(v0, i0, n0)
	var back := _nearest_tri(0, (e0["centroids"] as PackedVector3Array)[0])
	print("[PaintTest] nearest=%d (want 0)" % back)
	if back != 0:
		fails += 1
	# Grow: seed tri 0, one ring must add neighbors (covers adj + overlay path).
	_add_tri(0, 0, 0)
	_push_undo({"add": [[0, 0]]})
	_grow()
	_grow()
	var grown := ((_sel[REGIONS[0]] as Dictionary)["order"] as Array).size()
	print("[PaintTest] grown=%d (want >1)" % grown)
	if grown <= 1:
		fails += 1
	# Undo: one pop shrinks, draining empties (add batches + seed).
	_undo_pop()
	var shrunk := ((_sel[REGIONS[0]] as Dictionary)["order"] as Array).size()
	print("[PaintTest] shrunk=%d (want <%d)" % [shrunk, grown])
	if shrunk >= grown:
		fails += 1
	while not _undo.is_empty():
		_undo_pop()
	var drained := ((_sel[REGIONS[0]] as Dictionary)["order"] as Array).size()
	print("[PaintTest] drained=%d (want 0)" % drained)
	if drained != 0:
		fails += 1
	# Wire overlay: segments come in pairs, at most 3 per tri (dedupe removes).
	var wseg := wire_segments(v0, i0, n0)
	print("[PaintTest] wiresegs=%d (ntris=%d)" % [wseg.size() / 2, n0])
	if wseg.size() % 2 != 0 or wseg.size() / 2 > 3 * n0 or wseg.size() == 0:
		fails += 1
	print("[PaintTest] %d FAIL" % fails)
	get_tree().quit(fails)


func _live_head_inv(preview: Node) -> Transform3D:
	var found := preview.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return Transform3D.IDENTITY
	var sk := found[0] as Skeleton3D
	var bi := sk.find_bone(&"Head")
	if bi == -1:
		return Transform3D.IDENTITY
	var t := Transform3D.IDENTITY
	var cur: Node = sk
	while cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	# In-tree walk already yields the GLOBAL frame (bind == rest here) — no
	# extra self transform (that double-counted the root).
	var head_world: Transform3D = t * sk.get_bone_global_pose(bi)
	_target = head_world.origin
	_head_pos = head_world.origin
	print("[Paint] head target=%s" % str(_target))
	return head_world.affine_inverse()


func _build_rig() -> void:
	_cam = Camera3D.new()
	_cam.near = 0.005 # close-up paint: default 0.05 slices the mesh (08/10)
	add_child(_cam)
	ProjectSettings.set_setting("gui/timers/tooltip_delay", 1.0) # run-local
	_update_cam()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -32, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.09, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_ui = layer
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 15)
	layer.add_child(_label)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(1.0, 0.45, 0.1, 0.45) # transparent + plain depth: skin occludes backfaces (08/10)
	_wire_mat = StandardMaterial3D.new()
	_wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wire_mat.albedo_color = Color(1.0, 0.1, 0.6) # flashy pink edges (08/10)
	# Depth test stays ON (default): hidden lines stay hidden, Blender-style.


## Side panel: clickable region list (scrolls to any count) + action buttons.
## The panel is the primary UI now; keyboard shortcuts stay as alternates.
func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -236.0
	panel.offset_right = -8.0
	panel.offset_top = 8.0
	panel.offset_bottom = -8.0
	_ui.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	margin.add_child(col)
	var title := Label.new()
	title.text = "Regions (click)"
	col.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var rbox := VBoxContainer.new()
	rbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rbox)
	var group := ButtonGroup.new()
	for i in REGIONS.size():
		var b := Button.new()
		b.text = REGIONS[i]
		b.tooltip_text = String(REGION_TIPS.get(REGIONS[i], ""))
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_region_btn.bind(i))
		rbox.add_child(b)
		_region_btns[REGIONS[i]] = b
	var sep := HSeparator.new()
	col.add_child(sep)
	for a in [["+ Grow", _grow], ["- Shrink", _shrink], ["Clear", _clear], ["Undo", _undo_pop], ["Save work", _save_work], ["Wireframe", _toggle_wire], ["Reframe", _reframe]]:
		var ab := Button.new()
		ab.text = String(a[0])
		ab.pressed.connect(a[1] as Callable)
		col.add_child(ab)
	_refresh_region_btns()


func _on_region_btn(i: int) -> void:
	if i >= 0 and i < REGIONS.size():
		_region = i
		_refresh_all_overlays()
		_update_hud()


func _toggle_wire() -> void:
	_wire_mode = posmod(_wire_mode + 1, 3)
	_wire = _wire_mode != 0
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if _wire_mode == 2 else Viewport.DEBUG_DRAW_DISABLED
	for si in _wire_overlays:
		(_wire_overlays[si] as MeshInstance3D).visible = _wire_mode == 1
	_update_hud()


## All topology edges of a surface as line soup (MI-local), shared edges
## deduped by vert-index pair (indexed) so internal lines draw once. Pure
## array math (painttest asserts segment consistency headless).
static func wire_segments(verts: PackedVector3Array, idx: PackedInt32Array, ntris: int) -> PackedVector3Array:
	var soup := PackedVector3Array()
	if idx.is_empty():
		for ti in ntris:
			for k in 3:
				soup.append(verts[ti * 3 + k])
				soup.append(verts[ti * 3 + (k + 1) % 3])
		return soup
	var seen := {}
	for ti in ntris:
		var v := [idx[ti * 3], idx[ti * 3 + 1], idx[ti * 3 + 2]]
		for k in 3:
			var a := int(v[k])
			var b := int(v[(k + 1) % 3])
			var key := "%d:%d" % [mini(a, b), maxi(a, b)]
			if seen.has(key):
				continue
			seen[key] = true
			soup.append(verts[a])
			soup.append(verts[b])
	return soup


func _build_wire_overlays() -> void:
	for si in _surfs.size():
		var e: Dictionary = _surfs[si]
		var verts: PackedVector3Array = e["verts"]
		var idx: PackedInt32Array = e["idx"]
		var mesh := ArrayMesh.new()
		var soup := wire_segments(verts, idx, int(e["ntris"]))
		if not soup.is_empty():
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = soup
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
		var ovl := MeshInstance3D.new()
		ovl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ovl.material_override = _wire_mat
		ovl.visible = false
		(e["mi"] as Node).add_child(ovl)
		ovl.mesh = mesh
		_wire_overlays[si] = ovl
	print("[Paint] %d wire overlays built" % _wire_overlays.size())


func _tri_count_of(region: String) -> int:
	return ((_sel.get(region, {}) as Dictionary).get("order", []) as Array).size()


func _refresh_region_btns() -> void:
	for r in REGIONS:
		var b := _region_btns.get(r) as Button
		if b == null:
			continue
		b.text = "%s (%d)" % [r, _tri_count_of(r)]
		b.button_pressed = (REGIONS[_region] == r)


func _update_cam() -> void:
	if _cam == null:
		return
	_pitch = clampf(_pitch, -1.2, 1.2)
	_dist = clampf(_dist, 0.03, 2.0)
	var off := Vector3(cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw)) * _dist
	_cam.position = _target + off
	_cam.look_at(_target)


func _build_pick() -> void:
	var body := StaticBody3D.new()
	body.name = "PickBody"
	add_child(body)
	for si in _surfs.size():
		var e: Dictionary = _surfs[si]
		var verts: PackedVector3Array = e["verts"]
		var idx: PackedInt32Array = e["idx"]
		var soup := PackedVector3Array()
		var ntris := verts.size() / 3
		if not idx.is_empty():
			ntris = idx.size() / 3
		for ti in ntris:
			for k in 3:
				var vi := ti * 3 + k
				if not idx.is_empty():
					vi = idx[ti * 3 + k]
				soup.append(verts[vi])
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(soup)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		cs.global_transform = (e["mi"] as Node3D).global_transform
		e["rid"] = shape.get_rid()
		e["ntris"] = ntris
		e["centroids"] = centroids_of(verts, idx, ntris)
		print("[Paint] pick surf=%d tris=%d" % [si, ntris])
	_build_adj()


## MI-local triangle centroids (pick prefilter + painttest).
static func centroids_of(verts: PackedVector3Array, idx: PackedInt32Array, ntris: int) -> PackedVector3Array:
	var cen := PackedVector3Array()
	for ti in ntris:
		var c := Vector3.ZERO
		for k in 3:
			var vi := ti * 3 + k
			if not idx.is_empty():
				vi = idx[ti * 3 + k]
			c += verts[vi]
		cen.append(c / 3.0)
	return cen


func _build_adj() -> void:
	_adj.clear()
	for si in _surfs.size():
		var e: Dictionary = _surfs[si]
		var verts: PackedVector3Array = e["verts"]
		var idx: PackedInt32Array = e["idx"]
		var ntris := int(e["ntris"])
		var per := {}
		for ti in ntris:
			for k in 3:
				var vi := ti * 3 + k
				if not idx.is_empty():
					vi = idx[ti * 3 + k]
				var key: Variant = verts[vi]
				if not idx.is_empty():
					key = vi
				if not per.has(key):
					per[key] = []
				if not (per[key] as Array).has(ti):
					(per[key] as Array).append(ti)
		_adj.append(per)


func _build_overlays() -> void:
	for si in _surfs.size():
		var e: Dictionary = _surfs[si]
		var ovl := MeshInstance3D.new()
		ovl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ovl.material_override = _mat # whole-MI override: survives mesh swaps
		(e["mi"] as Node).add_child(ovl)
		_overlays[si] = ovl
	print("[Paint] %d overlays built (material_override orange)" % _overlays.size())


func _key(si: int, ti: int) -> String:
	return "%d:%d" % [si, ti]


func _add_tri(si: int, ti: int, ring: int) -> bool:
	var st: Dictionary = _sel[REGIONS[_region]]
	var k := _key(si, ti)
	if (st["set"] as Dictionary).has(k):
		return false
	(st["set"] as Dictionary)[k] = ring
	(st["order"] as Array).append([si, ti])
	_refresh_overlay(si)
	return true


func _push_undo(e: Dictionary) -> void:
	if not e.has("region"):
		e["region"] = REGIONS[_region]
	_undo.append(e)
	while _undo.size() > 200:
		_undo.pop_front()


## Inverts the last selection change (add batch or delete batch), switching
## back to its region. Clear-all is one entry (restores everything).
func _undo_pop() -> void:
	if _undo.is_empty():
		print("[Paint] undo empty")
		return
	var e: Dictionary = _undo.pop_back()
	_region = REGIONS.find(String(e.get("region", REGIONS[_region])))
	if _region == -1:
		_region = 0
	var st: Dictionary = _sel[REGIONS[_region]]
	if e.has("add"):
		var gone := {}
		for t in (e["add"] as Array):
			gone[_key(int(t[0]), int(t[1]))] = true
		for k in gone:
			(st["set"] as Dictionary).erase(k)
		var kept := []
		for t in (st["order"] as Array):
			if not gone.has(_key(int(t[0]), int(t[1]))):
				kept.append(t)
		st["order"] = kept
	else:
		for t in (e["del"] as Array):
			var k := _key(int(t[0]), int(t[1]))
			if not (st["set"] as Dictionary).has(k):
				(st["set"] as Dictionary)[k] = int(t[2])
				(st["order"] as Array).append([int(t[0]), int(t[1])])
	_refresh_all_overlays()
	_update_hud()
	print("[Paint] undo (%d left)" % _undo.size())


## Deletes the triangle under the cursor (no-op + log when unselected).
func _delete_at(mp: Vector2) -> void:
	var h := _pick(mp)
	if h.is_empty():
		return
	var st: Dictionary = _sel[REGIONS[_region]]
	var k := _key(int(h[0]), int(h[1]))
	if not (st["set"] as Dictionary).has(k):
		print("[Paint] R-click on unselected tri")
		return
	var ring := int((st["set"] as Dictionary)[k])
	(st["set"] as Dictionary).erase(k)
	var order: Array = st["order"]
	for i in order.size():
		var ta: Array = order[i]
		if _key(int(ta[0]), int(ta[1])) == k:
			order.remove_at(i)
			break
	_push_undo({"del": [[int(h[0]), int(h[1]), ring]]})
	_refresh_overlay(int(h[0]))
	_update_hud()


func _max_ring() -> int:
	var m := -1
	for r in ((_sel[REGIONS[_region]] as Dictionary)["set"] as Dictionary).values():
		m = maxi(m, int(r))
	return m


func _grow() -> void:
	var st: Dictionary = _sel[REGIONS[_region]]
	if (st["order"] as Array).is_empty():
		return
	var ring := _max_ring() + 1
	var frontier: Array = (st["order"] as Array).duplicate()
	var added := []
	for t in frontier:
		var ta: Array = t
		var e: Dictionary = _surfs[int(ta[0])]
		var verts: PackedVector3Array = e["verts"]
		var idx: PackedInt32Array = e["idx"]
		for k in 3:
			var vi := int(ta[1]) * 3 + k
			if not idx.is_empty():
				vi = idx[int(ta[1]) * 3 + k]
			var key: Variant = verts[vi]
			if not idx.is_empty():
				key = vi
			for nb in ((_adj[int(ta[0])] as Dictionary).get(key, []) as Array):
				if _add_tri(int(ta[0]), nb, ring):
					added.append([int(ta[0]), nb])
	if not added.is_empty():
		_push_undo({"add": added})
		print("[Paint] grew +%d tris" % added.size())


func _shrink() -> void:
	var st: Dictionary = _sel[REGIONS[_region]]
	var m := _max_ring()
	if m <= 0:
		return
	var order: Array = st["order"]
	var kept := []
	var dropped := []
	for t in order:
		var ta: Array = t
		if int((st["set"] as Dictionary)[_key(int(ta[0]), int(ta[1]))]) == m:
			(st["set"] as Dictionary).erase(_key(int(ta[0]), int(ta[1])))
			dropped.append([int(ta[0]), int(ta[1]), m])
		else:
			kept.append(t)
	st["order"] = kept
	if not dropped.is_empty():
		_push_undo({"del": dropped})
	_refresh_all_overlays()


func _clear() -> void:
	var st: Dictionary = _sel[REGIONS[_region]]
	var gone := []
	for t in (st["order"] as Array):
		gone.append([int(t[0]), int(t[1]), int((st["set"] as Dictionary)[_key(int(t[0]), int(t[1]))])])
	if not gone.is_empty():
		_push_undo({"del": gone})
		print("[Paint] cleared %d tris (undo restores)" % gone.size())
	_sel[REGIONS[_region]] = {"set": {}, "order": []}
	_refresh_all_overlays()


func _refresh_overlay(si: int) -> void:
	var ovl := _overlays.get(si) as MeshInstance3D
	if ovl == null:
		return
	var e: Dictionary = _surfs[si]
	var verts: PackedVector3Array = e["verts"]
	var idx: PackedInt32Array = e["idx"]
	var nraw: Variant = e.get("normals", PackedVector3Array())
	var normals: PackedVector3Array = PackedVector3Array() if not (nraw is PackedVector3Array) else nraw
	var soup := PackedVector3Array()
	var region: String = REGIONS[_region]
	for t in ((_sel[region] as Dictionary)["order"] as Array):
		var ta: Array = t
		if int(ta[0]) != si:
			continue
		var vi := [0, 0, 0]
		if not idx.is_empty():
			vi = [idx[int(ta[1]) * 3], idx[int(ta[1]) * 3 + 1], idx[int(ta[1]) * 3 + 2]]
		else:
			vi = [int(ta[1]) * 3, int(ta[1]) * 3 + 1, int(ta[1]) * 3 + 2]
		for k in 3:
			# Offset along the AUTHORED vertex normal (points outward by
			# construction): the face-winding normal pointed inward and sank
			# the overlay under the skin.
			var off := Vector3.ZERO
			if int(vi[k]) < normals.size():
				off = normals[int(vi[k])] * 0.0004
			soup.append(verts[int(vi[k])] + off)
	var mesh := ArrayMesh.new()
	if not soup.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = soup
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	ovl.mesh = mesh
	_update_hud()


func _refresh_all_overlays() -> void:
	for si in _surfs.size():
		_refresh_overlay(si)


func _tri_count() -> int:
	return ((_sel[REGIONS[_region]] as Dictionary)["order"] as Array).size()


func _update_hud() -> void:
	_refresh_region_btns()
	if _label == null:
		return
	_label.text = "region %d/%d %s (%d tris) | target %s | last: %s | wire %s\nL add R del-at-cursor Ctrl+Z undo | Mid orbit Shift+Mid pan wheel zoom | G/T grow/shrink C clear P save | V wire F reframe" % [_region + 1, REGIONS.size(), REGIONS[_region], _tri_count(), str(_target), _last_pick, (["OFF", "WIRE", "FULL"] as Array)[_wire_mode]]


func _pick(mp: Vector2) -> Array:
	if _cam == null:
		return []
	var from := _cam.project_ray_origin(mp)
	var to := from + _cam.project_ray_normal(mp) * 5.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_last_pick = "miss (no collider)"
		print("[Paint] click miss")
		_update_hud()
		return []
	var fi := int(hit.get("face_index", -1))
	# Shape index within PickBody == surf index (shapes added in surf order).
	var si := int(hit.get("shape", -1))
	if si < 0 or si >= _surfs.size():
		_last_pick = "miss (bad shape)"
		print("[Paint] click hit, bad shape index")
		_update_hud()
		return []
	if fi >= 0 and fi < int((_surfs[si] as Dictionary)["ntris"]):
		_last_pick = "surf %d tri %d" % [si, fi]
		print("[Paint] click %s" % _last_pick)
		_update_hud()
		return [si, fi]
	# No face_index (Jolt backend does not populate it): fall back to the
	# nearest triangle around the hit point (physics already guarantees the
	# hit is ON a triangle, so the nearest exact tri is the right one).
	var local: Vector3 = ((_surfs[si] as Dictionary)["mi"] as Node3D).global_transform.affine_inverse() * (hit["position"] as Vector3)
	var near := _nearest_tri(si, local)
	_last_pick = "surf %d tri %d (near)" % [si, near]
	print("[Paint] click %s" % _last_pick)
	_update_hud()
	return [si, near]


## Nearest triangle to a MI-local point: centroid prefilter (6mm), then exact
## closest-point-on-triangle (Ericson 5.1.5) on the survivors.
func _nearest_tri(si: int, p: Vector3) -> int:
	var e: Dictionary = _surfs[si]
	var verts: PackedVector3Array = e["verts"]
	var idx: PackedInt32Array = e["idx"]
	var cen: PackedVector3Array = e["centroids"]
	var best := 0
	var best_d := 1e9
	for ti in cen.size():
		var dc := cen[ti] - p
		if dc.length_squared() > 0.000036: # 6mm radius
			continue
		var d := _tri_dist2(verts, idx, ti, p)
		if d < best_d:
			best_d = d
			best = ti
	if best_d > 0.000001: # >1mm: prefilter missed a large tri, scan all
		for ti in cen.size():
			var d := _tri_dist2(verts, idx, ti, p)
			if d < best_d:
				best_d = d
				best = ti
	return best


static func _tri_vert(verts: PackedVector3Array, idx: PackedInt32Array, ti: int, k: int) -> Vector3:
	var vi := ti * 3 + k
	if not idx.is_empty():
		vi = idx[ti * 3 + k]
	return verts[vi]


static func _tri_dist2(verts: PackedVector3Array, idx: PackedInt32Array, ti: int, p: Vector3) -> float:
	var a := _tri_vert(verts, idx, ti, 0)
	var b := _tri_vert(verts, idx, ti, 1)
	var c := _tri_vert(verts, idx, ti, 2)
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return ap.length_squared()
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return bp.length_squared()
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return cp.length_squared()
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		var v := d1 / (d1 - d3)
		return (a + ab * v - p).length_squared()
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		var w := d2 / (d2 - d6)
		return (a + ac * w - p).length_squared()
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		var w2 := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return (b + (c - b) * w2 - p).length_squared()
	return (ac.cross(ab).normalized().dot(ap)) ** 2.0


## _unhandled_input (not _input) so UI clicks (panel) never paint: consumed
## GUI events stop before unhandled, while viewport clicks/motion/keys flow.
func _unhandled_input(event: InputEvent) -> void:
	if _cam == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_l_held = mb.pressed
			if mb.pressed:
				var h := _pick(mb.position)
				if not h.is_empty():
					if _add_tri(int(h[0]), int(h[1]), 0):
						_push_undo({"add": [[int(h[0]), int(h[1])]]})
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_r_down = mb.position
				_r_moved = false
			else:
				if not _r_moved: # delete under cursor; Ctrl+Z undoes
					_delete_at(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist *= 0.93
			_update_cam()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist *= 1.08
			_update_cam()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _l_held:
			var h := _pick(mm.position)
			if not h.is_empty():
				if _add_tri(int(h[0]), int(h[1]), 0):
					_push_undo({"add": [[int(h[0]), int(h[1])]]})
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			if Input.is_key_pressed(KEY_SHIFT):
				var right := _cam.global_transform.basis.x
				var up := _cam.global_transform.basis.y
				_target -= right * mm.relative.x * _dist * 0.0016
				_target += up * mm.relative.y * _dist * 0.0016
				_update_cam()
				_update_hud()
			else:
				_yaw -= mm.relative.x * 0.008
				_pitch += mm.relative.y * 0.008 # drag up = look from above (08/10)
				_update_cam()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			if (mm.position - _r_down).length() > 5.0:
				_r_moved = true
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if not ke.pressed or ke.echo:
			return
		if ke.ctrl_pressed and ke.keycode == KEY_Z:
			_undo_pop()
			return
		match ke.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var i := int(ke.keycode) - int(KEY_1)
				if i < REGIONS.size():
					_region = i
					_refresh_all_overlays()
					_update_hud()
			KEY_TAB:
				_region = posmod(_region + (-1 if ke.shift_pressed else 1), REGIONS.size())
				_refresh_all_overlays()
				_update_hud()
			KEY_G:
				_grow()
				_update_hud()
			KEY_T:
				_shrink()
				_update_hud()
			KEY_C:
				_clear()
				_update_hud()
			KEY_P:
				_save_work()
			KEY_V:
				_toggle_wire()
			KEY_F:
				_reframe()


## Re-anchors the orbit on the Head bone position (authoring frame): escape
## hatch when panned/orbited into the void.
func _reframe() -> void:
	_target = _head_pos
	_dist = 0.30
	_yaw = 0.0
	_pitch = -0.05
	_update_cam()
	_update_hud()
	print("[Paint] reframed on head: %s" % str(_target))


func _load_work() -> void:
	var work: Dictionary = JsonFile.load_object(WORK_PATH)
	var wsec: Dictionary = work.get(GENDER, {})
	for region in REGIONS:
		var tris: Array = (wsec.get(region, {}) as Dictionary).get("tris", [])
		for t in tris:
			var ta: Array = t
			((_sel[region] as Dictionary)["order"] as Array).append([int(ta[0]), int(ta[1])])
			((_sel[region] as Dictionary)["set"] as Dictionary)[_key(int(ta[0]), int(ta[1]))] = 0


func _save_work() -> void:
	var wsec := {}
	for region in REGIONS:
		var order: Array = ((_sel[region] as Dictionary)["order"] as Array).duplicate()
		order.sort()
		wsec[region] = {"tris": order}
	var err := JsonFile.save_atomic(WORK_PATH, {"version": 1, GENDER: wsec})
	print("[Paint] work saved (%s)" % ("OK" if err == OK else ("ERR %d" % err)))
