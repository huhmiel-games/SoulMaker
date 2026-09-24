class_name Moveset
extends RefCounted

## Player moveset loader (P2 locomotion, schema moveset_v0.1): packs + slots
## from data/characters/player_moveset.json. Switching idle variant or adding
## a .glb is a JSON edit — the states and controller never change.
## Slots carry legacy clips (body/stance agnostic fallback) plus an optional
## "variants" list of {match: {body, stance}, clips, active} entries — the
## resolver picks the best body/stance match and falls back to legacy clips.
## Variants accept an optional "phases" object (2H attack timing): merged
## per-key over the slot phases for markers and combat reads.
## Alias convention for curated takes: action__body__stance__NN (double
## underscore = field boundary, single underscore = word separator).
## Tolerant (ADR-009): missing clips warn at boot and fall back to the first
## existing clip of the slot; a missing/corrupt file falls back to code
## defaults (current locomotion set) instead of breaking the boot.
const PATH := "res://data/characters/player_moveset.json"
const FORMAT := "0.1"

## Body axis (character config, features/02): "any" = fallback entry.
const KNOWN_BODIES := [&"male", &"female", &"any"]
## Stance axis (equipment grip, features/04+17): "any" = fallback entry.
## V1 scope = sword_shield + two_hand (dual is vault — no anims yet).
const KNOWN_STANCES := [&"sword_shield", &"two_hand", &"any"]

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

const KNOWN_SLOTS := [&"idle", &"walk", &"run", &"fall", &"roll", &"backstep", &"land_hard", &"attack_light_1",
	&"walk_back", &"run_back", &"walk_strafe_left", &"walk_strafe_right", &"run_strafe_left", &"run_strafe_right",
	&"guard_idle", &"roll_fast"]

## Default attack phases (no phases section = whole clip as release at 1.0).
const PHASE_DEFAULTS := {
	"attack_start": 0.0, "release_start": 0.0,
	"windup_speed": 1.0, "attack_speed": 1.0, "release_speed": 1.0,
	"stamina_cost": 20.0, "sweep_start": 0.4, "contact_time": 0.0,
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
		if clips.is_empty() and (slot.get("variants", []) as Array).is_empty():
			issues.append("moveset slot '%s' has no clips" % name)
		var active := int(slot.get("active", 0))
		if not clips.is_empty() and (active < 0 or active >= clips.size()):
			issues.append("moveset slot '%s' active=%d out of range (clamps into range)" % [name, active])
		for vi in (slot.get("variants", []) as Array).size():
			var v: Variant = (slot.get("variants", []) as Array)[vi]
			if not v is Dictionary:
				issues.append("moveset slot '%s' variants[%d] must be an object" % [name, vi])
				continue
			var match := (v as Dictionary).get("match", {}) as Dictionary
			var vbody := str(match.get("body", "any"))
			var vstance := str(match.get("stance", "any"))
			if not StringName(vbody) in KNOWN_BODIES:
				issues.append("moveset slot '%s' variants[%d] unknown body '%s'" % [name, vi, vbody])
			if not StringName(vstance) in KNOWN_STANCES:
				issues.append("moveset slot '%s' variants[%d] unknown stance '%s'" % [name, vi, vstance])
			var vclips: Array = (v as Dictionary).get("clips", [])
			if vclips.is_empty():
				issues.append("moveset slot '%s' variants[%d] has no clips" % [name, vi])
			var vactive := int((v as Dictionary).get("active", 0))
			if not vclips.is_empty() and (vactive < 0 or vactive >= vclips.size()):
				issues.append("moveset slot '%s' variants[%d] active=%d out of range (clamps into range)" % [name, vi, vactive])
			if (v as Dictionary).has("phases"):
				for issue in _check_phases((v as Dictionary).get("phases"), "slot '%s' variants[%d]" % [name, vi]):
					issues.append(issue)
		if not StringName(name) in KNOWN_SLOTS:
			issues.append("moveset slot '%s' unknown (ignored)" % name)
		var loop = slot.get("loop", false)
		if not (loop is bool):
			issues.append("moveset slot '%s' loop must be a boolean" % name)
		var phases: Variant = slot.get("phases", {})
		for issue in _check_phases(phases, "slot '%s'" % name):
			issues.append(issue)
	return issues


## Phase-shape checks shared by slot phases and variant phases (2H attack
## timing lives on the variant). [param owner] renders as "slot 'x'" or
## "slot 'x' variants[i]" inside the issue strings.
static func _check_phases(phases: Variant, owner: String) -> PackedStringArray:
	var issues := PackedStringArray()
	if not phases is Dictionary:
		issues.append("moveset %s phases must be an object" % owner)
		return issues
	for key in ["attack_start", "release_start", "windup_speed", "attack_speed", "release_speed", "stamina_cost", "sweep_start", "contact_time"]:
		var v: Variant = (phases as Dictionary).get(key, 0.0)
		if not v is float and not v is int:
			issues.append("moveset %s phases.%s must be a number" % [owner, key])
	var a := float((phases as Dictionary).get("attack_start", 0.0))
	var r := float((phases as Dictionary).get("release_start", 0.0))
	if r < a:
		issues.append("moveset %s phases.release_start < attack_start" % owner)
	var impact: Variant = (phases as Dictionary).get("impact", {})
	if not impact is Dictionary:
		issues.append("moveset %s phases.impact must be an object" % owner)
	else:
		for key in ["damage", "critical_multiplier", "hitstop_frames", "shake_scale"]:
			var v: Variant = (impact as Dictionary).get(key, 0.0)
			if not v is float and not v is int:
				issues.append("moveset %s phases.impact.%s must be a number" % [owner, key])
	var rebound: Variant = (phases as Dictionary).get("rebound", {})
	if not rebound is Dictionary:
		issues.append("moveset %s phases.rebound must be an object" % owner)
	elif not (rebound as Dictionary).is_empty():
		for key in ["frames", "speed", "hold_time", "reblend_time"]:
			var v: Variant = (rebound as Dictionary).get(key, 0.0)
			if not v is float and not v is int:
				issues.append("moveset %s phases.rebound.%s must be a number" % [owner, key])
	return issues


## Slot phases merged with the winning variant's phases (2H attack timing):
## variant keys win per-key, nested impact/rebound merge per-key too, absent
## keys fall back to the slot. any/any callers get the slot phases untouched.
static func _merged_variant_phases(slot: Dictionary, body: StringName, stance: StringName) -> Dictionary:
	var src: Variant = slot.get("phases", {})
	var out := (src as Dictionary).duplicate() if src is Dictionary else {}
	if body == &"any" and stance == &"any":
		return out
	var best := {}
	var best_score := -1
	for v in slot.get("variants", []):
		if not v is Dictionary:
			continue
		var s := _variant_score((v as Dictionary).get("match", {}) as Dictionary, body, stance)
		if s > best_score:
			best_score = s
			best = v
	if best_score < 0:
		return out
	var vp: Variant = (best as Dictionary).get("phases", {})
	if not vp is Dictionary:
		return out
	for k in (vp as Dictionary):
		var vv: Variant = (vp as Dictionary)[k]
		if vv is Dictionary and out.get(k) is Dictionary:
			var m := (out[k] as Dictionary).duplicate()
			for k2 in (vv as Dictionary):
				m[k2] = (vv as Dictionary)[k2]
			out[k] = m
		else:
			out[k] = vv
	return out


## Effective phases for a slot at a body/stance (defaults filled, winning
## variant merged over slot phases): the stance-aware twin of phases_for.
## phases_for stays slot-level (land_contact and other stance-agnostic
## readers are untouched).
static func effective_phases(obj: Dictionary, slot: StringName, body: StringName, stance: StringName) -> Dictionary:
	var out := (PHASE_DEFAULTS as Dictionary).duplicate()
	out["impact"] = (IMPACT_DEFAULTS as Dictionary).duplicate()
	out["rebound"] = (REBOUND_DEFAULTS as Dictionary).duplicate()
	var slots: Dictionary = obj.get("slots", {})
	var entry: Variant = slots.get(String(slot), {})
	if not entry is Dictionary:
		return out
	var merged := _merged_variant_phases(entry, body, stance)
	for key in PHASE_DEFAULTS:
		if merged.has(key):
			out[key] = float(merged[key])
	var impact: Variant = merged.get("impact", {})
	if impact is Dictionary:
		var imerged := (IMPACT_DEFAULTS as Dictionary).duplicate()
		for key in imerged:
			if (impact as Dictionary).has(key):
				imerged[key] = float((impact as Dictionary)[key])
		out["impact"] = imerged
	var rebound: Variant = merged.get("rebound", {})
	if rebound is Dictionary and not (rebound as Dictionary).is_empty():
		var rmerged := (REBOUND_DEFAULTS as Dictionary).duplicate()
		for key in rmerged:
			if (rebound as Dictionary).has(key):
				rmerged[key] = float((rebound as Dictionary)[key])
		out["rebound"] = rmerged
	return out


## Assigns a clip to a slot (anim-lab "Assign current take" seam — pure, no
## player needed, no side effects): body+stance any/any rewrites the legacy
## clips (active reset to 0), anything else upserts the matching variant
## (created when absent, appended — resolve_clip sorts by score so an exact
## match wins regardless of JSON order). [param loop] -1 = keep, 0/1 = set.
## [param phases] entries >= 0 override the written entry (slot in legacy,
## variant otherwise — the boot merge falls back per-key). Missing slots are
## created ({clips, active 0, loop false}). Returns {"ok": true, "where":
## "legacy"|"variant ..."} or {"ok": false, "error": ...} on unknown
## body/stance. Unknown slots are written (caller warns — the loader ignores
## them until KNOWN_SLOTS grows).
static func assign_clip(obj: Dictionary, slot_name: String, body: String, stance: String, clip: String, loop: int = -1, phases: Dictionary = {}) -> Dictionary:
	if not StringName(body) in KNOWN_BODIES:
		return {"ok": false, "error": "unknown body '%s'" % body}
	if not StringName(stance) in KNOWN_STANCES:
		return {"ok": false, "error": "unknown stance '%s'" % stance}
	var slots: Variant = obj.get("slots", {})
	if not slots is Dictionary:
		slots = {}
		obj["slots"] = slots
	var entry: Variant = (slots as Dictionary).get(slot_name, {})
	if not (slots as Dictionary).has(slot_name) or not entry is Dictionary:
		entry = {"clips": [], "active": 0, "loop": false}
		(slots as Dictionary)[slot_name] = entry
	var target: Dictionary = entry as Dictionary
	var where := "legacy"
	if not (body == "any" and stance == "any"):
		target = _upsert_assign_variant(entry as Dictionary, body, stance)
		where = "variant {body:%s stance:%s}" % [body, stance]
	target["clips"] = [clip]
	target["active"] = 0
	if loop == 0:
		target["loop"] = false
	elif loop == 1:
		target["loop"] = true
	var merged: Dictionary = (target.get("phases", {}) as Dictionary).duplicate() if target.get("phases") is Dictionary else {}
	for k in phases:
		var v: Variant = phases[k]
		if (v is float or v is int) and float(v) >= 0.0:
			merged[k] = float(v)
	if not merged.is_empty():
		target["phases"] = merged
	return {"ok": true, "where": where}


## Returns the variant entry matching body/stance, creating
## {match, clips: [], active: 0} when absent.
static func _upsert_assign_variant(slot: Dictionary, body: String, stance: String) -> Dictionary:
	for v in slot.get("variants", []):
		if v is Dictionary:
			var m := (v as Dictionary).get("match", {}) as Dictionary
			if str(m.get("body", "any")) == body and str(m.get("stance", "any")) == stance:
				return v as Dictionary
	if not slot.has("variants"):
		slot["variants"] = []
	var created := {"match": {"body": body, "stance": stance}, "clips": [], "active": 0}
	(slot["variants"] as Array).append(created)
	return created


## Raw object ({} when missing/corrupt — JsonFile quarantines corruption).
static func load_object() -> Dictionary:
	return JsonFile.load_object(PATH)


## Packs for RigKit.build_player (fallback when the file is unusable).
static func packs_of(obj: Dictionary) -> Dictionary:
	var packs: Dictionary = obj.get("packs", {})
	return packs if not packs.is_empty() else FALLBACK_PACKS.duplicate()


## Resolve every known slot to a full "rig/pack__clip" name verified against
## the built player. Variant entries are tried first (best body/stance match
## wins, ties go to the earliest entry — put body-specific entries before
## stance-specific ones), then the legacy clips; missing active clip -> first
## existing clip of the tried list; nothing found -> "" (caller keeps the
## current anim, never T-poses).
## Applies each slot's loop flag (LOOP_LINEAR when true, LOOP_NONE otherwise)
## on the runtime copy — the imported .glb is never touched.
static func resolve_clips(obj: Dictionary, player: AnimationPlayer, body: StringName = &"any", stance: StringName = &"any") -> Dictionary:
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
		var found := resolve_clip(slot, have, body, stance)
		if found == &"":
			push_warning("[Moveset] slot '%s': nothing found for body '%s' stance '%s'" % [key, body, stance])
		out[name] = found
		loops[name] = _set_loop(player, found, bool(slot.get("loop", false)))
		markers[name] = _set_markers(player, found, _merged_variant_phases(slot, body, stance))
	print("[Moveset] body=%s stance=%s loops %s" % [body, stance, str(loops)])
	print("[Moveset] markers %s" % str(markers))
	return out


## Single-slot resolution against an AnimationPlayer clip list (rig/-prefixed
## full names): best variant first, legacy clips last. Pure function for the
## harness seam — no player needed, no side effects.
static func resolve_clip(slot: Dictionary, have: PackedStringArray, body: StringName = &"any", stance: StringName = &"any") -> StringName:
	var lists: Array = _ordered_clip_lists(slot, body, stance)
	for entry in lists:
		var l: Array = entry
		for c in l:
			var want := "rig/%s" % c
			if want in have:
				return StringName(want)
	return &""


## Candidate clip lists, best match first: variants scored (exact = 2,
## "any" = 1, concrete mismatch = skip), ties keep JSON order, legacy last.
static func _ordered_clip_lists(slot: Dictionary, body: StringName, stance: StringName) -> Array:
	var clips: Array = slot.get("clips", [])
	var active := clampi(int(slot.get("active", 0)), 0, maxi(clips.size() - 1, 0))
	var legacy: Array = []
	if not clips.is_empty():
		legacy.append(clips[active])
		for c in clips:
			if c != clips[active]:
				legacy.append(c)
	if body == &"any" and stance == &"any":
		return [legacy] if not legacy.is_empty() else []
	var scored: Array = []
	for v in slot.get("variants", []):
		if not v is Dictionary:
			continue
		var match := (v as Dictionary).get("match", {}) as Dictionary
		var score := _variant_score(match, body, stance)
		if score < 0:
			continue
		var vclips: Array = (v as Dictionary).get("clips", [])
		var vactive := clampi(int((v as Dictionary).get("active", 0)), 0, maxi(vclips.size() - 1, 0))
		var order: Array = []
		if not vclips.is_empty():
			order.append(vclips[vactive])
			for c in vclips:
				if c != vclips[vactive]:
					order.append(c)
		scored.append({"score": score, "clips": order})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	var out: Array = []
	for s in scored:
		out.append((s as Dictionary)["clips"])
	if not legacy.is_empty():
		out.append(legacy)
	return out


## Match score for one variant: -1 = concrete mismatch (skip), else body
## points + stance points. Exact match = 2, variant-side "any" = 1,
## request-side "any" against a concrete variant = 0 (usable, least
## preferred — legacy any/any callers keep resolving the agnostic clips).
static func _variant_score(match: Dictionary, body: StringName, stance: StringName) -> int:
	var b := _axis_score(str(match.get("body", "any")), body)
	var s := _axis_score(str(match.get("stance", "any")), stance)
	if b < 0 or s < 0:
		return -1
	return b + s


static func _axis_score(want: String, got: StringName) -> int:
	if want == String(got):
		return 2
	if want == "any":
		return 1
	if got == &"any":
		return 0
	return -1


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
