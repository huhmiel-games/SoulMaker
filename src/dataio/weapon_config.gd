class_name WeaponConfig
extends RefCounted

## Player weapon loader (P3 S3 graybox, features/17 push/shove): reads
## data/weapons/<id>.json via JsonFile (same corruption-quarantine contract
## as Moveset/GuardConfig/EnemyConfig), validates the weapon field set, falls
## back to FALLBACK (light sword = current behavior, mesh unscaled, no
## push_move) when the file is missing or invalid. P8 inventory owns items —
## this migrates into the weapon item payload then (fields already match the
## shared stat-block shape: damage/crit/guard/push_move).

const DIR := "res://data/weapons"


## Fallback = light sword (pre-S3 behavior): damage 10, crit x1.5, base
## speeds/costs, medium-shield-grade guard, no shove.
const FALLBACK := {
	"id": "light_sword",
	"display_name": "Light Sword (built-in)",
	"class": "straight_sword",
	"mesh_scale": 1.0,
	"attack": {"damage": 10.0, "critical_multiplier": 1.5, "windup_speed": 1.0, "attack_speed": 1.25, "release_speed": 1.0, "stamina_cost": 20.0, "hitstop_frames": 4, "shake_scale": 1.0},
	"guard": {"guard_absorb": 0.9, "stability_mult": 1.0, "block_arc": 75.0},
	"push_move": {"type": "none"},
}


## Shared-path loader (Moveset.load_object pattern — {} when unusable).
static func load_object(weapon_id: String) -> Dictionary:
	return JsonFile.load_object("%s/%s.json" % [DIR, weapon_id])


## Field validation: presence + number/bool types. Returns issues
## (empty = usable). Unknown extra fields tolerated (ADR-009).
static func validate_config(obj: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if str(obj.get("id", "")) == "":
		issues.append("weapon config: missing id")
	if str(obj.get("class", "")) == "":
		issues.append("weapon config: missing class")
	var ms: Variant = obj.get("mesh_scale", -1.0)
	if not ms is float and not ms is int:
		issues.append("weapon config mesh_scale must be a number")
	elif float(ms) <= 0.0:
		issues.append("weapon config mesh_scale must be > 0")
	for section in ["attack", "guard", "push_move"]:
		if not (obj.get(section, {}) is Dictionary):
			issues.append("weapon config: section '%s' must be an object" % section)
	for key in ["damage", "critical_multiplier", "windup_speed", "attack_speed", "release_speed", "stamina_cost", "hitstop_frames", "shake_scale"]:
		var v: Variant = (obj.get("attack", {}) as Dictionary).get(key, -1.0)
		if not v is float and not v is int:
			issues.append("weapon config attack.%s must be a number" % key)
		elif float(v) < 0.0:
			issues.append("weapon config attack.%s must be >= 0" % key)
	for key in ["guard_absorb", "stability_mult", "block_arc"]:
		var g: Variant = (obj.get("guard", {}) as Dictionary).get(key, -1.0)
		if not g is float and not g is int:
			issues.append("weapon config guard.%s must be a number" % key)
		elif float(g) < 0.0:
			issues.append("weapon config guard.%s must be >= 0" % key)
	var pm: Dictionary = obj.get("push_move", {})
	var ptype := str(pm.get("type", "none"))
	if ptype != "none" and ptype != "blade_shove":
		issues.append("weapon config push_move.type '%s' unknown (V1: none|blade_shove, kick is V2)" % ptype)
	if ptype == "blade_shove":
		for key in ["reach", "guard_break", "recovery", "damage"]:
			var s: Variant = pm.get(key, -1.0)
			if not s is float and not s is int:
				issues.append("weapon config push_move.%s must be a number" % key)
			elif float(s) < 0.0:
				issues.append("weapon config push_move.%s must be >= 0" % key)
	return issues


## Merged weapon: file values over FALLBACK (missing file/invalid fields =
## fallback values, never a crash). Nested sections merge per-key.
static func merged(weapon_id: String) -> Dictionary:
	var out: Dictionary = (FALLBACK as Dictionary).duplicate(true)
	var obj := load_object(weapon_id)
	if obj.is_empty():
		if weapon_id != str((FALLBACK as Dictionary).get("id", "")):
			push_warning("[WeaponConfig] '%s' missing/unusable — fallback" % weapon_id)
		return out
	for issue in validate_config(obj):
		push_warning("[WeaponConfig] %s" % issue)
	for section in ["attack", "guard", "push_move"]:
		var base: Dictionary = out.get(section, {})
		var over: Dictionary = obj.get(section, {})
		for key in over:
			base[key] = over[key]
	for key in ["display_name", "class", "mesh_scale"]:
		if obj.has(key):
			out[key] = obj[key]
	return out
