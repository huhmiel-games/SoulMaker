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


## Encodes parent-local placements (passed as
## {prefab_id: String, transform: {position: Vector3, rotation: Vector3, scale: Vector3}})
## into a schema-conform map object. ground is the sparse relief
## {Vector2i cell: float height} (may be empty = flat, section omitted).
static func serialize(name: String, placements: Array, ground := {}) -> Dictionary:
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


## Decodes the ground section back into a sparse relief {Vector2i: float}.
## Tolerant (bad entries skipped); validate_ground reports them separately.
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
