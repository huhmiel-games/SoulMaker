class_name MapIO
extends RefCounted

## Map file IO — the world schema's `$defs/map` subset (name + prefabs).
## Pure transforms in / out; the editor/world layers own node ownership.
## Placement shape: {prefab_id, instance_id?, transform: {position, rotation, scale}}
## All transforms are arrays of 3 numbers per schema v0.1; rotation in degrees.

const format_version := "0.1"
const TRANSFORM_KEYS := ["position", "rotation", "scale"]
## Ground relief section (EDIT_FLOOR): sparse heightfield over a 100x100 m
## slab (1 m cells, default 0 = flat). Only nonzero cells serialize; maps
## without the section load flat (additive, tolerant as usual).
const GROUND_N := 100
const GROUND_CELL := 1.0
## File quantum (1 mm, 3 decimals): the editor sculpts continuous floats,
## files round here — millimeter-precise (no visible terracing on gentle
## grades) yet clean to read.
const GROUND_STEP := 0.001
const GROUND_H_MIN := -8.0
const GROUND_H_MAX := 8.0
## Ambiance override section (map editor page, features/06 set): sun
## elevation/exposure, fog depth/height, tonemapping, ambient energy.
## Sparse like ground — absent = env_default.tres. Files nest per the world
## schema ({sun, fog, tonemapping, ambient}); the editor works a flat dict
## ({sun_elev, sun_energy, fog_enabled, fog_begin, fog_end, fog_height,
## fog_hdensity, tonemap_mode, tonemap_exposure, ambient_energy}).
## Bounds are single-sourced here; steps live with the editor rows.
const AMBIANCE_BOUNDS := {
	"sun_elev": [10.0, 90.0],
	"sun_energy": [0.0, 8.0],
	"fog_begin": [0.0, 400.0],
	"fog_end": [5.0, 500.0],
	"fog_height": [-50.0, 100.0],
	"fog_hdensity": [0.0, 1.0],
	"tonemap_mode": [0.0, 4.0],
	"tonemap_exposure": [0.1, 4.0],
	"ambient_energy": [0.0, 2.0],
}
## Mirrors env_default.tres (fog off). The editor applies these on boot when
## the map carries no section, so the viewport always shows defined values.
const AMBIANCE_DEFAULTS := {
	"sun_elev": 45.0, "sun_energy": 1.1,
	"fog_enabled": false, "fog_begin": 10.0, "fog_end": 100.0,
	"fog_height": 0.0, "fog_hdensity": 0.0,
	"tonemap_mode": 2.0, "tonemap_exposure": 1.0,
	"ambient_energy": 0.6,
}
## Flat key → [file group, file key].
const AMBIANCE_NEST := {
	"sun_elev": ["sun", "elevation"], "sun_energy": ["sun", "energy"],
	"fog_enabled": ["fog", "enabled"], "fog_begin": ["fog", "depth_begin"],
	"fog_end": ["fog", "depth_end"], "fog_height": ["fog", "height"],
	"fog_hdensity": ["fog", "height_density"],
	"tonemap_mode": ["tonemapping", "mode"],
	"tonemap_exposure": ["tonemapping", "exposure"],
	"ambient_energy": ["ambient", "energy"],
}


## Encodes parent-local placements (passed as
## {prefab_id: String, transform: {position: Vector3, rotation: Vector3, scale: Vector3}})
## into a schema-conform map object. ground is the sparse relief
## {Vector2i cell: float height} (may be empty = flat, section omitted).
## ambiance is the flat override dict (may be empty = defaults, omitted).
## spawn is {position: Vector3, yaw: float} (may be empty = origin + drop, omitted).
static func serialize(name: String, placements: Array, ground := {}, ambiance := {}, spawn := {}) -> Dictionary:
	var prefabs := []
	for p in placements:
		var t: Dictionary = p.get("transform", {})
		prefabs.append({
			"prefab_id": p.get("prefab_id"),
			"instance_id": p.get("instance_id", ""),
			"transform": {
				"position": _vec3_to_array(t.get("position", Vector3.ZERO)),
				"rotation": _vec3_to_array(t.get("rotation", Vector3.ZERO)),
				"scale": _vec3_to_array(t.get("scale", Vector3.ONE)),
			},
		})
	var out := {"format_version": format_version, "name": name, "prefabs": prefabs}
	if not (ground as Dictionary).is_empty():
		out["ground"] = {"cell": GROUND_CELL, "cells": _ground_to_data(ground)}
	if not (ambiance as Dictionary).is_empty():
		out["ambiance"] = ambiance_to_data(ambiance)
	if not (spawn as Dictionary).is_empty():
		out["spawn"] = spawn_to_data(spawn)
	return out


## Decodes a map object back into placements (Dictionary with Vector3
## transforms). Fills defaults; generates instance_id when absent.
static func deserialize(map: Dictionary) -> Array[Dictionary]:
	var out := []
	var n := 0
	for p in map.get("prefabs", []):
		if not p is Dictionary:
			continue
		var t: Dictionary = p.get("transform", {})
		var placement: Dictionary = {
			"prefab_id": str(p.get("prefab_id", "")),
			"instance_id": str(p.get("instance_id", "")),
			"transform": {
				"position": _array_to_vec3(t.get("position", [0, 0, 0])),
				"rotation": _array_to_vec3(t.get("rotation", [0, 0, 0])),
				"scale": _array_to_vec3(t.get("scale", [1, 1, 1])),
			},
		}
		if placement["instance_id"].is_empty():
			placement["instance_id"] = "inst_%d" % n
		n += 1
		out.append(placement)
	return out


## Structural checks against schema v0.1 (no catalog reference).
static func validate_map(map: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if map.get("format_version") != format_version:
		issues.append("map format_version must be '%s'" % format_version)
	var name: Variant = map.get("name")
	if not name is String or (name as String).strip_edges().is_empty():
		issues.append("map name missing")
	var list: Variant = map.get("prefabs")
	if not list is Array:
		issues.append("prefabs missing")
		return issues
	for p in list:
		if not p is Dictionary:
			issues.append("prefab entry is not an object")
			continue
		var pid: Variant = p.get("prefab_id")
		if not pid is String or not SchemaUtil.matches_id(pid as String):
			issues.append("bad prefab_id: %s" % pid)
		var iid: Variant = p.get("instance_id", "")
		if not iid is String or (not (iid as String).is_empty() and not SchemaUtil.matches_id(iid as String)):
			issues.append("bad instance_id: %s" % iid)
		var t: Variant = p.get("transform", {})
		if not t is Dictionary:
			issues.append("bad transform (%s)" % pid)
			continue
		for key in TRANSFORM_KEYS:
			if t.has(key) and not _is_float_triple(t[key]):
				issues.append("transform.%s must be 3 numbers (%s)" % [key, pid])
	issues.append_array(validate_ground(map))
	issues.append_array(validate_ambiance(map))
	issues.append_array(validate_spawn(map))
	return issues


## Reference integrity: every prefab_id must exist in the catalog and resolve
## to a scene file.
static func validate_refs(map: Dictionary, catalog: Catalog) -> PackedStringArray:
	var issues := PackedStringArray()
	for p in map.get("prefabs", []):
		if not p is Dictionary:
			continue
		var pid: String = str(p.get("prefab_id", ""))
		if not catalog.has(pid):
			issues.append("unknown prefab_id in catalog: %s" % pid)
		elif catalog.resolve_scene_path(pid).is_empty():
			issues.append("prefab_id has no scene file: %s" % pid)
	return issues


## Player spawn section (round-trip playtest): {position: Vector3, yaw: float}
## in, {position: [3 numbers], yaw: float} out. Empty dict = absent.
static func spawn_to_data(spawn: Dictionary) -> Dictionary:
	var p: Vector3 = spawn.get("position", Vector3.ZERO)
	return {"position": _vec3_to_array(p), "yaw": float(spawn.get("yaw", 0.0))}


## Decodes the spawn section back ({position: Vector3, yaw: float}).
## Absent/malformed = {} (caller defaults to origin + drop).
static func spawn_from_data(map: Dictionary) -> Dictionary:
	var s: Variant = map.get("spawn", {})
	if not s is Dictionary:
		return {}
	var pos := _array_to_vec3((s as Dictionary).get("position", [0, 0, 0]))
	var yaw: Variant = (s as Dictionary).get("yaw", 0.0)
	if not yaw is float and not yaw is int:
		return {}
	return {"position": pos, "yaw": float(yaw)}


## Structural checks for the spawn section (absent = default = valid).
static func validate_spawn(map: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if not map.has("spawn"):
		return issues
	var s: Variant = map.get("spawn")
	if not s is Dictionary:
		issues.append("spawn must be an object")
		return issues
	if (s as Dictionary).has("position") and not _is_float_triple((s as Dictionary)["position"]):
		issues.append("spawn.position must be 3 numbers")
	var yaw: Variant = (s as Dictionary).get("yaw", 0.0)
	if not yaw is float and not yaw is int:
		issues.append("spawn.yaw must be a number")
	return issues
static func ground_from_data(map: Dictionary) -> Dictionary:
	var out := {}
	var g: Variant = map.get("ground", {})
	if not g is Dictionary:
		return out
	var cells: Variant = (g as Dictionary).get("cells", {})
	if not cells is Dictionary:
		return out
	for key in (cells as Dictionary):
		var cell := _parse_cell_key(str(key))
		if cell.x < 0:
			continue
		var h: Variant = (cells as Dictionary)[key]
		if h is float or h is int:
			out[cell] = float(h)
	return out


## Structural checks for the ground section (absent = flat = valid).
static func validate_ground(map: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if not map.has("ground"):
		return issues
	var g: Variant = map.get("ground")
	if not g is Dictionary:
		issues.append("ground must be an object")
		return issues
	if float((g as Dictionary).get("cell", GROUND_CELL)) != GROUND_CELL:
		issues.append("ground.cell must be %s" % GROUND_CELL)
	var cells: Variant = (g as Dictionary).get("cells", {})
	if not cells is Dictionary:
		issues.append("ground.cells missing")
		return issues
	for key in (cells as Dictionary):
		var cell := _parse_cell_key(str(key))
		if cell.x < 0 or cell.x >= GROUND_N or cell.y < 0 or cell.y >= GROUND_N:
			issues.append("ground cell out of range: %s" % key)
			continue
		var h: Variant = (cells as Dictionary)[key]
		if not h is float and not h is int:
			issues.append("ground height not a number: %s" % key)
			continue
		var hf := float(h)
		if hf < GROUND_H_MIN or hf > GROUND_H_MAX:
			issues.append("ground height out of range [-8, +8]: %s" % key)
		elif absf(hf - snappedf(hf, GROUND_STEP)) > 0.0001:
			issues.append("ground height not a %s step: %s" % [GROUND_STEP, key])
	return issues


## Flat override dict → nested file section (3-decimal quants, same file
## discipline as ground). Only known keys serialize; fog_enabled as bool,
## tonemap_mode as int.
static func ambiance_to_data(amb: Dictionary) -> Dictionary:
	var out := {"sun": {}, "fog": {}, "tonemapping": {}, "ambient": {}}
	for flat in AMBIANCE_NEST:
		if not (amb as Dictionary).has(flat):
			continue
		var pair: Array = AMBIANCE_NEST[flat]
		var v: Variant = (amb as Dictionary)[flat]
		if flat == "fog_enabled":
			(out[pair[0]] as Dictionary)[pair[1]] = bool(v)
		elif flat == "tonemap_mode":
			(out[pair[0]] as Dictionary)[pair[1]] = int(v)
		elif v is float or v is int:
			var q := roundf(snappedf(float(v), 0.001) * 1000.0) / 1000.0
			(out[pair[0]] as Dictionary)[pair[1]] = q
	return out


## Nested file section → flat editor dict. Tolerant (bad entries skipped);
## validate_ambiance reports them separately. Unknown groups/keys ignored.
static func ambiance_from_data(map: Dictionary) -> Dictionary:
	var out := {}
	var section: Variant = map.get("ambiance", {})
	if not section is Dictionary:
		return out
	var flip := {}
	for flat in AMBIANCE_NEST:
		var pair: Array = AMBIANCE_NEST[flat]
		flip["%s/%s" % [pair[0], pair[1]]] = flat
	for group in (section as Dictionary):
		var gd: Variant = (section as Dictionary)[group]
		if not gd is Dictionary:
			continue
		for key in (gd as Dictionary):
			var flat: String = str(flip.get("%s/%s" % [group, key], ""))
			if flat.is_empty():
				continue
			var v: Variant = (gd as Dictionary)[key]
			if flat == "fog_enabled":
				out[flat] = bool(v)
			elif v is float or v is int or (flat == "tonemap_mode" and v is int):
				out[flat] = float(v)
	return out


## Structural checks for the ambiance section (absent = defaults = valid).
static func validate_ambiance(map: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if not map.has("ambiance"):
		return issues
	var section: Variant = map.get("ambiance")
	if not section is Dictionary:
		issues.append("ambiance must be an object")
		return issues
	var flat := ambiance_from_data(map)
	for key in flat:
		if key == "fog_enabled":
			continue
		if not AMBIANCE_BOUNDS.has(key):
			continue
		var bounds: Array = AMBIANCE_BOUNDS[key]
		var v := float(flat[key])
		if v < float(bounds[0]) or v > float(bounds[1]):
			issues.append("ambiance.%s out of range [%s, %s]: %s" % [key, bounds[0], bounds[1], v])
	if flat.has("fog_end") and flat.has("fog_begin") and float(flat["fog_end"]) <= float(flat["fog_begin"]):
		issues.append("ambiance.fog_end must exceed fog_begin")
	return issues


## Library helpers (map menu): file-level operations under a maps directory.
## Names are bare (no extension); files are "<name>.json", sorted.


## Sorted bare map names present in dir (empty if missing). Creates dir.
static func list_map_names(dir: String) -> PackedStringArray:
	DirAccess.make_dir_recursive_absolute(dir)
	var out := PackedStringArray()
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if not da.current_is_dir() and fname.to_lower().ends_with(".json"):
			out.append(fname.left(fname.length() - 5))
		fname = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


## Deletes one map file. Returns OK or the DirAccess error.
static func delete_map_file(dir: String, name: String) -> Error:
	var da := DirAccess.open(dir)
	if da == null:
		return ERR_CANT_OPEN
	return da.remove("%s.json" % name)


## First free "untitled_NN" name (NN from 01 up) given the existing names.
static func first_free_name(existing: PackedStringArray, stem := "untitled") -> String:
	var n := 1
	var candidate := "%s_%02d" % [stem, n]
	while candidate in existing:
		n += 1
		candidate = "%s_%02d" % [stem, n]
	return candidate


## ── internal ──────────────────────────────────────────────────────────

static func _ground_to_data(ground: Dictionary) -> Dictionary:
	# Format guarantee: files store GROUND_STEP quants (the editor sculpts
	# continuous floats in memory); near-zero rounds out and stays sparse.
	var cells := {}
	for c in ground:
		if c is Vector2i:
			# Binary dust (7×0.05 != 0.35) normalized to 3 decimals so files
			# stay readable and round-trips idempotent.
			var q := roundf(snappedf(float(ground[c]), GROUND_STEP) * 1000.0) / 1000.0
			if not is_zero_approx(q):
				cells["%d,%d" % [c.x, c.y]] = q
	return cells


## Parses an "x,z" cell key; (-1, -1) when malformed.
static func _parse_cell_key(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


static func _vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _array_to_vec3(arr: Variant) -> Vector3:
	if arr is Array and (arr as Array).size() >= 3:
		return Vector3(float((arr as Array)[0]), float((arr as Array)[1]), float((arr as Array)[2]))
	return Vector3.ZERO


static func _is_float_triple(v: Variant) -> bool:
	if not v is Array:
		return false
	var arr := v as Array
	return arr.size() == 3 and arr[0] is float and arr[1] is float and arr[2] is float
