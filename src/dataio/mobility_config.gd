class_name MobilityConfig
extends RefCounted

## Player mobility loader (P3 S4 graybox, features/17 equip-load/backstep/
## plunge): reads data/characters/player_mobility.json via JsonFile (same
## corruption-quarantine contract as Moveset/GuardConfig/WeaponConfig),
## validates the tier/cost/plunge/fall field set, falls back to FALLBACK
## (the S4 tranche numbers) when the file is missing or invalid. Base-owned,
## NOT creator-tunable — thresholds live here, load comes from the
## controller export (no inventory until P8).

const PATH := "res://data/characters/player_mobility.json"

## Fallback = the S4 tranche numbers (21/09/2026).
const FALLBACK := {
	"thresholds": {"fast_max": 0.3, "mid_max": 0.7},
	"roll": {
		"base_time": 0.8,
		"fast": {"iframes": 0.5, "distance": 6.0, "recovery_bonus": 0.0, "anim_speed": 1.0},
		"mid": {"iframes": 0.4, "distance": 4.0, "recovery_bonus": 0.08, "anim_speed": 0.9},
		"fat": {"iframes": 0.25, "distance": 3.0, "recovery_bonus": 0.3, "anim_speed": 0.75},
	},
	"costs": {
		"roll": 25.0,
		"backstep": {"fast": 15.0, "mid": 18.0, "fat": 22.0},
	},
	"plunge": {
		"min_reach": 1.5,
		"min_drop": 2.0,
		"damage_per_meter": 8.0,
		"damage_cap": 40.0,
		"knockback": 1.5,
		"hit_recovery": 0.4,
		"miss_recovery": 0.9,
		"roll_cancel_at": 0.5,
	},
	"fall_damage": {"threshold": 5.0, "per_meter": 15.0, "cap": 50.0},
}


## Raw object ({} when missing/corrupt — JsonFile quarantines corruption).
static func load_object() -> Dictionary:
	return JsonFile.load_object(PATH)


## Field validation: presence + number types. Returns issues
## (empty = usable). Unknown extra fields tolerated (ADR-009).
static func validate_config(obj: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	var th: Variant = obj.get("thresholds", {})
	if not th is Dictionary:
		issues.append("mobility config: thresholds must be an object")
	else:
		for key in ["fast_max", "mid_max"]:
			var v: Variant = (th as Dictionary).get(key, -1.0)
			if not v is float and not v is int:
				issues.append("mobility config thresholds.%s must be a number" % key)
			elif float(v) < 0.0 or float(v) > 1.0:
				issues.append("mobility config thresholds.%s must be in [0, 1]" % key)
	var roll: Variant = obj.get("roll", {})
	if not roll is Dictionary:
		issues.append("mobility config: roll must be an object")
	else:
		for tier in ["fast", "mid", "fat"]:
			var t: Variant = (roll as Dictionary).get(tier, {})
			if not t is Dictionary:
				issues.append("mobility config: roll.%s must be an object" % tier)
				continue
			for key in ["iframes", "distance", "recovery_bonus", "anim_speed"]:
				var u: Variant = (t as Dictionary).get(key, -1.0)
				if not u is float and not u is int:
					issues.append("mobility config roll.%s.%s must be a number" % [tier, key])
				elif float(u) < 0.0:
					issues.append("mobility config roll.%s.%s must be >= 0" % [tier, key])
	var costs: Variant = obj.get("costs", {})
	if not costs is Dictionary:
		issues.append("mobility config: costs must be an object")
	else:
		var rc: Variant = (costs as Dictionary).get("roll", -1.0)
		if not rc is float and not rc is int:
			issues.append("mobility config costs.roll must be a number")
		var bs: Variant = (costs as Dictionary).get("backstep", {})
		if not bs is Dictionary:
			issues.append("mobility config: costs.backstep must be an object")
		else:
			for tier in ["fast", "mid", "fat"]:
				var w: Variant = (bs as Dictionary).get(tier, -1.0)
				if not w is float and not w is int:
					issues.append("mobility config costs.backstep.%s must be a number" % tier)
				elif float(w) < 0.0:
					issues.append("mobility config costs.backstep.%s must be >= 0" % tier)
	for section in ["plunge", "fall_damage"]:
		var s: Variant = obj.get(section, {})
		if not s is Dictionary:
			issues.append("mobility config: %s must be an object" % section)
	var pl: Dictionary = obj.get("plunge", {})
	for key in ["min_reach", "min_drop", "damage_per_meter", "damage_cap", "knockback", "hit_recovery", "miss_recovery", "roll_cancel_at"]:
		if not pl.is_empty():
			var v: Variant = pl.get(key, -1.0)
			if not v is float and not v is int:
				issues.append("mobility config plunge.%s must be a number" % key)
			elif float(v) < 0.0:
				issues.append("mobility config plunge.%s must be >= 0" % key)
	var fd: Dictionary = obj.get("fall_damage", {})
	for key in ["threshold", "per_meter", "cap"]:
		if not fd.is_empty():
			var v: Variant = fd.get(key, -1.0)
			if not v is float and not v is int:
				issues.append("mobility config fall_damage.%s must be a number" % key)
			elif float(v) < 0.0:
				issues.append("mobility config fall_damage.%s must be >= 0" % key)
	return issues


## Merged mobility: file values over FALLBACK (missing file/invalid fields =
## fallback values, never a crash). Nested sections merge per-key.
static func merged() -> Dictionary:
	var out: Dictionary = (FALLBACK as Dictionary).duplicate(true)
	var obj := load_object()
	if obj.is_empty():
		push_warning("[MobilityConfig] missing/unusable — fallback")
		return out
	for issue in validate_config(obj):
		push_warning("[MobilityConfig] %s" % issue)
	var th_out: Dictionary = out.get("thresholds", {})
	var th_over: Dictionary = obj.get("thresholds", {})
	for key in th_over:
		if th_out.has(key):
			th_out[key] = float(th_over[key])
	var roll_out: Dictionary = out.get("roll", {})
	var roll_over: Dictionary = obj.get("roll", {})
	for tier in ["fast", "mid", "fat"]:
		if roll_over.has(tier) and roll_over[tier] is Dictionary:
			var base: Dictionary = roll_out.get(tier, {})
			for key in (roll_over[tier] as Dictionary):
				if base.has(key):
					base[key] = float((roll_over[tier] as Dictionary)[key])
	if roll_over.has("base_time"):
		roll_out["base_time"] = float(roll_over["base_time"])
	var costs_out: Dictionary = out.get("costs", {})
	var costs_over: Dictionary = obj.get("costs", {})
	if costs_over.has("roll"):
		costs_out["roll"] = float(costs_over["roll"])
	if costs_over.has("backstep") and costs_over["backstep"] is Dictionary:
		var bs_out: Dictionary = costs_out.get("backstep", {})
		for tier in (costs_over["backstep"] as Dictionary):
			if bs_out.has(tier):
				bs_out[tier] = float((costs_over["backstep"] as Dictionary)[tier])
	for section in ["plunge", "fall_damage"]:
		var base: Dictionary = out.get(section, {})
		var over: Dictionary = obj.get(section, {})
		for key in over:
			if base.has(key):
				base[key] = float(over[key])
	return out
