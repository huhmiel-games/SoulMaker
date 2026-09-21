class_name EnemyConfig
extends RefCounted

## Enemy config loader (P2): reads data/enemies/<id>.json via JsonFile
## (same corruption-quarantine contract as Moveset), validates the P2
## field set, falls back to FALLBACK (soldier_melee_v1 values) when the
## file is missing or invalid. Field set mirrors features/05 (poise,
## poise_reset_time, hit_poise, activation_radius) + the behavior_pattern_id
## hook the P9 data-driven patterns will resolve (same shape, no rewrite).

const DIR := "res://data/enemies"

## Shared-path loader (Moveset.load_object pattern — {} when unusable).
static func load_object(enemy_id: String) -> Dictionary:
	return JsonFile.load_object("%s/%s.json" % [DIR, enemy_id])


## P2 field validation: presence + number/bool types. Returns issues
## (empty = usable). Unknown extra fields tolerated (ADR-009).
static func validate_config(obj: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if str(obj.get("id", "")) == "":
		issues.append("enemy config: missing id")
	if str(obj.get("behavior_pattern_id", "")) == "":
		issues.append("enemy config: missing behavior_pattern_id")
	for section in ["stats", "sliders", "senses", "locomotion", "attack"]:
		if not (obj.get(section, {}) is Dictionary):
			issues.append("enemy config: section '%s' must be an object" % section)
	for key in ["hp", "damage", "hit_poise", "hit_stamina_damage", "poise", "poise_reset_time"]:
		var v: Variant = (obj.get("stats", {}) as Dictionary).get(key, -1.0)
		if not v is float and not v is int:
			issues.append("enemy config stats.%s must be a number" % key)
		elif float(v) < 0.0:
			issues.append("enemy config stats.%s must be >= 0" % key)
	for key in ["aggression", "telegraph_scale", "cadence"]:
		var s: Variant = (obj.get("sliders", {}) as Dictionary).get(key, -1.0)
		if not s is float and not s is int:
			issues.append("enemy config sliders.%s must be a number" % key)
		elif float(s) < 0.0:
			issues.append("enemy config sliders.%s must be >= 0" % key)
	for key in ["activation_radius", "aggro_radius", "deaggro_radius"]:
		var r: Variant = (obj.get("senses", {}) as Dictionary).get(key, -1.0)
		if not r is float and not r is int:
			issues.append("enemy config senses.%s must be a number" % key)
		elif float(r) <= 0.0:
			issues.append("enemy config senses.%s must be > 0" % key)
	return issues


## Merged config: file values over FALLBACK (missing file/invalid fields =
## fallback values, never a crash). Nested sections merge per-key.
static func merged(enemy_id: String) -> Dictionary:
	var out: Dictionary = FALLBACK.duplicate(true)
	var obj := load_object(enemy_id)
	if obj.is_empty():
		push_warning("[EnemyConfig] '%s' missing/unusable — fallback" % enemy_id)
		return out
	var issues := validate_config(obj)
	for issue in issues:
		push_warning("[EnemyConfig] %s" % issue)
	for section in ["stats", "sliders", "senses", "locomotion", "attack"]:
		var base: Dictionary = out.get(section, {})
		var over: Dictionary = obj.get(section, {})
		for key in over:
			base[key] = over[key]
	for key in ["display_name", "behavior_pattern_id", "boss_level", "backstab_vulnerable"]:
		if obj.has(key):
			out[key] = obj[key]
	return out


## Fallback = soldier_melee_v1 values (the only P2 pattern).
const FALLBACK := {
	"id": "soldier_melee_v1",
	"display_name": "Hollow Soldier",
	"behavior_pattern_id": "soldier_melee_v1",
	"stats": {"hp": 60.0, "damage": 10.0, "hit_poise": 20.0, "hit_stamina_damage": 30.0, "poise": 30.0, "poise_reset_time": 3.5},
	"sliders": {"aggression": 0.6, "telegraph_scale": 1.0, "cadence": 1.0},
	"senses": {"activation_radius": 14.0, "aggro_radius": 12.0, "deaggro_radius": 20.0},
	"locomotion": {"walk_speed": 2.2, "hurry_speed": 3.2, "hurry_range": 5.0, "turn_rate": 6.0},
	"attack": {"range": 2.2, "windup_time": 0.7, "strike_time": 0.25, "recover_time": 0.9, "flinch_time": 0.45, "shielded": true, "shield_half_angle": 45.0},
	"boss_level": false,
	"backstab_vulnerable": true,
}
