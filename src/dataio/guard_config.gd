class_name GuardConfig
extends RefCounted

## Player guard loader (P3 S1 graybox, features/17 block/guard): reads
## data/characters/player_guard.json via JsonFile (same corruption-quarantine
## contract as Moveset/EnemyConfig), validates the shield-class set, falls
## back to FALLBACK (medium shield) when the file is missing or invalid.
## P8 inventory owns items — this migrates into the shield item payload
## then (the fields already match the shared stat block shape).

const PATH := "res://data/characters/player_guard.json"

## Fallback = medium shield (the P3 kickoff starter numbers).
const FALLBACK := {
	"equipped_shield": "medium",
	"class": {"guard_absorb": 0.9, "stability_mult": 1.0, "block_arc": 75.0},
}


## Raw object ({} when missing/corrupt — JsonFile quarantines corruption).
static func load_object() -> Dictionary:
	return JsonFile.load_object(PATH)


## Field validation: presence + number types + equipped class known.
## Returns issues (empty = usable). Unknown extra fields tolerated (ADR-009).
static func validate_config(obj: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	var classes: Variant = obj.get("shield_classes", {})
	if not classes is Dictionary or (classes as Dictionary).is_empty():
		issues.append("guard config: shield_classes missing or empty")
	else:
		for name in (classes as Dictionary):
			var c: Variant = (classes as Dictionary)[name]
			if not c is Dictionary:
				issues.append("guard config: class '%s' must be an object" % name)
				continue
			for key in ["guard_absorb", "stability_mult", "block_arc"]:
				var v: Variant = (c as Dictionary).get(key, -1.0)
				if not v is float and not v is int:
					issues.append("guard config: class '%s'.%s must be a number" % [name, key])
				elif float(v) < 0.0:
					issues.append("guard config: class '%s'.%s must be >= 0" % [name, key])
	var equipped := str(obj.get("equipped_shield", ""))
	if equipped != "" and not ((obj.get("shield_classes", {}) as Dictionary).has(equipped)):
		issues.append("guard config: equipped_shield '%s' unknown" % equipped)
	return issues


## Merged guard: equipped class values (file over FALLBACK class, missing
## file/invalid fields = fallback values, never a crash).
static func merged() -> Dictionary:
	var out: Dictionary = (FALLBACK as Dictionary).duplicate(true)
	var obj := load_object()
	if obj.is_empty():
		push_warning("[GuardConfig] missing/unusable — fallback")
		return out
	for issue in validate_config(obj):
		push_warning("[GuardConfig] %s" % issue)
	var equipped := str(obj.get("equipped_shield", "medium"))
	var classes: Dictionary = obj.get("shield_classes", {})
	if classes.has(equipped) and classes[equipped] is Dictionary:
		out["equipped_shield"] = equipped
		var cls: Dictionary = out["class"]
		for key in cls:
			if (classes[equipped] as Dictionary).has(key):
				cls[key] = float((classes[equipped] as Dictionary)[key])
	return out
