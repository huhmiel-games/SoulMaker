class_name MapIO
extends RefCounted

## Map file IO — the world schema's `$defs/map` subset (name + prefabs).
## Pure transforms in / out; the editor/world layers own node ownership.
## Placement shape: {prefab_id, instance_id?, transform: {position, rotation, scale}}
## All transforms are arrays of 3 numbers per schema v0.1; rotation in degrees.

const format_version := "0.1"
const TRANSFORM_KEYS := ["position", "rotation", "scale"]


## Encodes parent-local placements (passed as
## {prefab_id: String, transform: {position: Vector3, rotation: Vector3, scale: Vector3}})
## into a schema-conform map object.
static func serialize(name: String, placements: Array) -> Dictionary:
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
	return {"format_version": format_version, "name": name, "prefabs": prefabs}


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


## ── internal ──────────────────────────────────────────────────────────

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