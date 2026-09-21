class_name Moveset
extends RefCounted

## Player moveset loader (P2 locomotion, schema moveset_v0.1): packs + slots
## from data/characters/player_moveset.json. Switching idle variant or adding
## a .glb is a JSON edit — the states and controller never change.
## Tolerant (ADR-009): missing clips warn at boot and fall back to the first
## existing clip of the slot; a missing/corrupt file falls back to code
## defaults (current locomotion set) instead of breaking the boot.
const PATH := "res://data/characters/player_moveset.json"
const FORMAT := "0.1"

const FALLBACK_PACKS := {"adventure": "res://assets/animations/adventure.glb"}
const FALLBACK_SLOTS := {
	&"idle": ["idle"],
	&"walk": ["walking", "walk"],
	&"run": ["running", "run"],
	&"fall": ["falling", "fall", "drop"],
	&"roll": ["roll", "dodge", "flip"],
	&"backstep": ["backstep", "jump", "hop"],
	&"attack_light_1": ["attack", "slash", "swing", "hit"],
}

const KNOWN_SLOTS := [&"idle", &"walk", &"run", &"fall", &"roll", &"backstep", &"attack_light_1"]

## Default attack phases (no phases section = whole clip as release at 1.0).
const PHASE_DEFAULTS := {
	"attack_start": 0.0, "release_start": 0.0,
	"windup_speed": 1.0, "attack_speed": 1.0, "release_speed": 1.0,
	"stamina_cost": 20.0, "sweep_start": 0.4,
}

## Default impact payload (features/01 game feel): damage per connect,
## hitstop frames (2-10 by power), shake scale (trauma multiplier).
const IMPACT_DEFAULTS := {
	"damage": 10.0, "critical_multiplier": 1.5, "hitstop_frames": 4, "shake_scale": 1.0,
}

## Default blade rebound (features/01): reverse N frames at negative speed
## once hitstop ends, then blend to idle over reblend_time. Absent from the
## JSON = committed swing with no recoil (current behavior).
const REBOUND_DEFAULTS := {
	"frames": 4, "speed": 3.0, "hold_time": 0.15, "reblend_time": 0.15,
}


## Structural checks against schema v0.1. Returns the issue list (empty =
## clean); unknown slots are tolerated but reported.
static func validate_moveset(obj: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if obj.get("format_version") != FORMAT:
		issues.append("moveset format_version must be '%s'" % FORMAT)
	var packs: Dictionary = obj.get("packs", {})
	if packs.is_empty():
		issues.append("moveset packs missing or empty")
	for id in packs:
		if not str(packs[id]).ends_with(".glb"):
			issues.append("moveset pack '%s' is not a .glb path" % id)
	var slots: Dictionary = obj.get("slots", {})
	if slots.is_empty():
		issues.append("moveset slots missing or empty")
	for name in slots:
		var slot: Dictionary = slots[name] if slots[name] is Dictionary else {}
		var clips: Array = slot.get("clips", [])
		if clips.is_empty():
			issues.append("moveset slot '%s' has no clips" % name)
		var active := int(slot.get("active", 0))
		if not clips.is_empty() and (active < 0 or active >= clips.size()):
			issues.append("moveset slot '%s' active=%d out of range (clamps into range)" % [name, active])
		if not StringName(name) in KNOWN_SLOTS:
			issues.append("moveset slot '%s' unknown (ignored)" % name)
		var loop = slot.get("loop", false)
		if not (loop is bool):
			issues.append("moveset slot '%s' loop must be a boolean" % name)
		var phases: Variant = slot.get("phases", {})
		if not phases is Dictionary:
			issues.append("moveset slot '%s' phases must be an object" % name)
		else:
			for key in ["attack_start", "release_start", "windup_speed", "attack_speed", "release_speed", "stamina_cost", "sweep_start"]:
				var v: Variant = (phases as Dictionary).get(key, 0.0)
				if not v is float and not v is int:
					issues.append("moveset slot '%s' phases.%s must be a number" % [name, key])
		var a := float((phases as Dictionary).get("attack_start", 0.0))
		var r := float((phases as Dictionary).get("release_start", 0.0))
		if r < a:
			issues.append("moveset slot '%s' phases.release_start < attack_start" % name)
		var impact: Variant = (phases as Dictionary).get("impact", {})
		if not impact is Dictionary:
			issues.append("moveset slot '%s' phases.impact must be an object" % name)
		else:
			for key in ["damage", "critical_multiplier", "hitstop_frames", "shake_scale"]:
				var v: Variant = (impact as Dictionary).get(key, 0.0)
				if not v is float and not v is int:
					issues.append("moveset slot '%s' phases.impact.%s must be a number" % [name, key])
		var rebound: Variant = (phases as Dictionary).get("rebound", {})
		if not rebound is Dictionary:
			issues.append("moveset slot '%s' phases.rebound must be an object" % name)
		elif not (rebound as Dictionary).is_empty():
			for key in ["frames", "speed", "hold_time", "reblend_time"]:
				var v: Variant = (rebound as Dictionary).get(key, 0.0)
				if not v is float and not v is int:
					issues.append("moveset slot '%s' phases.rebound.%s must be a number" % [name, key])
	return issues


## Raw object ({} when missing/corrupt — JsonFile quarantines corruption).
static func load_object() -> Dictionary:
	return JsonFile.load_object(PATH)


## Packs for RigKit.build_player (fallback when the file is unusable).
static func packs_of(obj: Dictionary) -> Dictionary:
	var packs: Dictionary = obj.get("packs", {})
	return packs if not packs.is_empty() else FALLBACK_PACKS.duplicate()


## Resolve every known slot to a full "rig/pack__clip" name verified against
## the built player. Missing active clip -> first existing clip of the slot;
## nothing found -> "" (caller keeps the current anim, never T-poses).
## Applies each slot's loop flag (LOOP_LINEAR when true, LOOP_NONE otherwise)
## on the runtime copy — the imported .glb is never touched.
static func resolve_clips(obj: Dictionary, player: AnimationPlayer) -> Dictionary:
	var out := {}
	var have := player.get_animation_list() if player != null else PackedStringArray()
	var slots: Dictionary = obj.get("slots", {})
	if slots.is_empty():
		for name in FALLBACK_SLOTS:
			out[name] = RigKit.pick(player, "adventure", FALLBACK_SLOTS[name])
			_set_loop(player, out[name], false)
		return out
	var loops := {}
	var markers := {}
	for name in KNOWN_SLOTS:
		var key := String(name)
		if not slots.has(key):
			out[name] = &""
			continue
		var slot: Dictionary = slots[key]
		var clips: Array = slot.get("clips", [])
		var active := clampi(int(slot.get("active", 0)), 0, maxi(clips.size() - 1, 0))
		var order: Array = []
		if not clips.is_empty():
			order.append(clips[active])
			for c in clips:
				if c != clips[active]:
					order.append(c)
		var found := &""
		for c in order:
			var want := "rig/%s" % c
			if want in have:
				found = StringName(want)
				break
		if found == &"" and not clips.is_empty():
			push_warning("[Moveset] slot '%s': none of %s found on the rig" % [key, str(clips)])
		elif not clips.is_empty() and str(clips[active]) != str(found).trim_prefix("rig/"):
			push_warning("[Moveset] slot '%s': active '%s' missing, using '%s'" % [key, clips[active], found])
		out[name] = found
		loops[name] = _set_loop(player, found, bool(slot.get("loop", false)))
		markers[name] = _set_markers(player, found, slot.get("phases", {}))
	print("[Moveset] loops %s" % str(loops))
	print("[Moveset] markers %s" % str(markers))
	return out


## Writes the combat section markers (windup_start/attack_start/release_start/
## anim_end) on the resolved clip from absolute seconds placed by eye. Slots
## without phases keep whatever the import carries ("none"). Runtime copy only.
static func _set_markers(player: AnimationPlayer, clip: StringName, phases: Variant) -> String:
	if player == null or clip == &"" or not phases is Dictionary or (phases as Dictionary).is_empty():
		return "none"
	var anim: Animation = player.get_animation(clip)
	if anim == null:
		return "none"
	var length := anim.length
	var a_start := clampf(float((phases as Dictionary).get("attack_start", 0.0)), 0.0, length)
	var r_start := clampf(float((phases as Dictionary).get("release_start", a_start)), a_start, length)
	for m in [&"windup_start", &"attack_start", &"release_start", &"anim_end"]:
		if anim.has_marker(m):
			anim.remove_marker(m)
	anim.add_marker(&"windup_start", 0.0)
	anim.add_marker(&"attack_start", a_start)
	anim.add_marker(&"release_start", r_start)
	anim.add_marker(&"anim_end", length)
	return "%.2f/%.2f/%.2f" % [a_start, r_start, length]


## Attack phases for a slot (defaults when absent): absolute section bounds +
## per-section speeds + stamina cost + impact payload + rebound params. Read
## once by the controller at boot.
static func phases_for(obj: Dictionary, slot: StringName) -> Dictionary:
	var out := (PHASE_DEFAULTS as Dictionary).duplicate()
	out["impact"] = (IMPACT_DEFAULTS as Dictionary).duplicate()
	out["rebound"] = (REBOUND_DEFAULTS as Dictionary).duplicate()
	var slots: Dictionary = obj.get("slots", {})
	var entry: Variant = slots.get(String(slot), {})
	if entry is Dictionary:
		var phases: Variant = (entry as Dictionary).get("phases", {})
		if phases is Dictionary:
			for key in PHASE_DEFAULTS:
				if (phases as Dictionary).has(key):
					out[key] = float((phases as Dictionary)[key])
			var impact: Variant = (phases as Dictionary).get("impact", {})
			if impact is Dictionary:
				var merged := (IMPACT_DEFAULTS as Dictionary).duplicate()
				for key in merged:
					if (impact as Dictionary).has(key):
						merged[key] = float((impact as Dictionary)[key])
				out["impact"] = merged
			var rebound: Variant = (phases as Dictionary).get("rebound", {})
			if rebound is Dictionary and not (rebound as Dictionary).is_empty():
				var rmerged := (REBOUND_DEFAULTS as Dictionary).duplicate()
				for key in rmerged:
					if (rebound as Dictionary).has(key):
						rmerged[key] = float((rebound as Dictionary)[key])
				out["rebound"] = rmerged
	return out


## Sets the loop mode on a resolved clip. No loop by default (explicit
## loop:true required). Two slots sharing one clip: last write wins.
static func _set_loop(player: AnimationPlayer, clip: StringName, loop: bool) -> String:
	if player == null or clip == &"":
		return "none"
	var anim: Animation = player.get_animation(clip)
	if anim == null:
		return "none"
	anim.set_loop_mode(Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE)
	return "linear" if loop else "none"
