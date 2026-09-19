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
}

const KNOWN_SLOTS := [&"idle", &"walk", &"run", &"fall", &"roll", &"backstep"]


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
	print("[Moveset] loops %s" % str(loops))
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
