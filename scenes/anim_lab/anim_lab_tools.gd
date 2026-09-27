@tool
extends Node

## Anim-lab take hider + renamer (scenes/anim_lab/anim_lab.tscn, LabTools
## node): while scrubbing takes in the editor Animation dock, "Hide current
## take" appends the previewed take to anim_lab_hidden.json + removes it live
## + re-saves the baked .res — never shown again until restored (remove its
## line from the JSON + re-bake with src/cli_tools/bake_player_pack.gd).
## "Rename current take" renames the previewed take to the curated alias in
## [member rename_to] (action__body__stance__NN, __ = field boundary): live
## rename + anim_lab_renames.json append (replayed on every bake BEFORE the
## hidden filter) + player_moveset.json clips updated when the take is used
## by a slot + .res re-save. The source .glb files are never touched.
## [member take_usage] mirrors the previewed take's moveset assignment
## (slots/variants + active/loop/phases, read-only, never saved).
## "Assign current take" writes the previewed take into player_moveset.json
## ([member assign_slot]/[member assign_body]/[member assign_stance] dropdowns:
## any/any = legacy clips, anything else = matching variant, created when
## absent) + optional loop/phases overrides (-1 = keep). Overwriting an
## existing entry pops a ConfirmationDialog with the diff (Confirmer writes,
## Annuler drops); creations and no-change re-assigns write at once. No
## re-bake needed: the take is already in the pack.
## Single-file setup: the dock library IS player_pack.res (the same file the
## game mounts) — hide/rename write straight into it; "Bake player pack"
## rebuilds it whole from the JSONs (bulk changes, reconsolidation).
## Dev only, nothing in the game reads the hidden/renames files.
## "Reset pose" clears dock preview residue between takes (see reset_pose):
## use it before judging a take, especially UAL ones.
## Note: LabPlayer lives under the RigRoot instance, so the editor hides it
## in the scene dock unless RigRoot is set to Editable Children — the tool
## resolves it dynamically, nothing to configure.
const HIDDEN_PATH := "res://scenes/anim_lab/anim_lab_hidden.json"
const RENAMES_PATH := "res://scenes/anim_lab/anim_lab_renames.json"
const PACK := "res://scenes/anim_lab/player_pack.res"

## Curated alias for the previewed take (see above): pre-filled with the
## previewed take name whenever the Animation dock selection changes — edit
## the take part, then press "Rename current take". Empty = the button
## no-ops with a hint.
@export_category("Rename")
@export var rename_to := ""
@export_tool_button("Rename current take") var rename_action: Callable = rename_current_take

## Assign target: the previewed take goes to this moveset slot (kept in sync
## with Moveset.KNOWN_SLOTS by hand — verify_assign fails loudly on drift).
## Pre-filled from the previewed take's own entry on switch (reset when
## lab-only). Empty = the assign button no-ops with a hint.
@export_category("Assign")
## Usage picker for the previewed take — one entry per slot/variant using it
## ("<slot>" legacy, "<slot> · <body>/<stance>" variant, same order as
## take_usage, chosen entry marked ► there). Picking pre-fills the fields
## below, so tweak + Assign is edit-not-type — including retargeting the axes
## to grow a new variant from an existing entry. Empty when lab-only.
@export var assign_entry: String = "":
	set(v):
		assign_entry = v
		if v != "" and _last_take != "":
			_prefill_from_key(_last_take, v)
@export_enum("idle", "walk", "run", "fall", "roll", "backstep", "land_hard", "attack_light_1", "walk_back", "run_back", "walk_strafe_left", "walk_strafe_right", "run_strafe_left", "run_strafe_right", "guard_idle", "roll_fast") var assign_slot: String = ""
## Body axis of the written entry (Moveset.KNOWN_BODIES): any + stance any =
## legacy clips, anything else = matching variant.
@export_enum("male", "female", "any") var assign_body: String = "any"
## Stance axis of the written entry (Moveset.KNOWN_STANCES).
@export_enum("sword_shield", "two_hand", "any") var assign_stance: String = "any"
## Loop override for the written entry: -1 = keep, 0 = loop:false,
## 1 = loop:true.
@export var assign_loop := -1
## Phase overrides for the written entry (slot in legacy, variant
## otherwise — the boot merge falls back per-key): -1 = keep.
@export var assign_attack_start := -1.0
@export var assign_release_start := -1.0
@export var assign_windup_speed := -1.0
@export var assign_attack_speed := -1.0
@export var assign_release_speed := -1.0
@export var assign_stamina_cost := -1.0
@export var assign_sweep_start := -1.0
@export var assign_contact_time := -1.0
@export_tool_button("Assign current take") var assign_action: Callable = assign_current_take

## Moveset usage of the previewed take (auto-follow, read-only, never stored
## in the scene): every slot/variant referencing it with active index, loop
## and phases — "not used" when lab-only. Refreshed on take switch (same
## watcher as [member rename_to]), at ready, and after an assign.
@export_category("Lab")
@export_multiline var take_usage := ""
@export_tool_button("Hide current take") var hide_action: Callable = hide_current_take
@export_tool_button("Bake player pack") var bake_action: Callable = bake_player_pack
@export_tool_button("Reset pose") var reset_action: Callable = reset_pose

## Last previewed take (short name): the pre-fill watcher below writes
## [member rename_to] only on take switch, never while you edit.
var _last_take := ""

## Pending overwrite dialog (one at a time — a second Assign press replaces
## it). Plain var, never stored in the scene.
var _assign_dialog: ConfirmationDialog = null


## Full rebuild of player_pack.res from the JSONs (moveset packs + lab packs,
## renames replayed, hidden removed): use after hand-editing hidden/renames,
## or to reconsolidate the pack. Same bake as
## --script res://src/cli_tools/bake_player_pack.gd. Hide/Rename buttons already
## write straight into the pack, so this is only needed for bulk changes.
func bake_player_pack() -> void:
	var err := PlayerPackBaker.bake_to(get_tree().root, PlayerPackBaker.PLAYER_PACK_OUT, "Pack")
	if err == OK:
		print("[AnimLab] player pack baked — lab and game use it immediately")
	else:
		push_warning("[AnimLab] player pack bake failed")


## Clears the dock preview residue: neither the player nor the dock resets
## bones a take does not animate (e.g. UAL takes carry no Spine track — it
## is stripped at import as immutable — so Spine keeps the previous take's
## pose when hopping takes in the dock). Stop + reset all bone poses to
## rest for a clean baseline before judging a take. Editor only, touches
## nothing on disk.
func reset_pose() -> void:
	var player := _find_lab_player()
	if player == null:
		push_warning("[AnimLab] reset pose: LabPlayer not resolved")
		return
	player.stop()
	var armature: Node = player.get_parent()
	if armature == null:
		push_warning("[AnimLab] reset pose: LabPlayer has no parent")
		return
	var skeleton := armature.get_node_or_null("GeneralSkeleton") as Skeleton3D
	if skeleton == null:
		push_warning("[AnimLab] reset pose: GeneralSkeleton not found under LabPlayer parent")
		return
	skeleton.reset_bone_poses()
	print("[AnimLab] pose reset to rest — preview any take from a clean baseline")


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	var player := _find_lab_player()
	if player == null:
		print("[AnimLab] LabTools ready — LabPlayer NOT resolved (reopen the scene / check the RigRoot instance)")
		return
	# Unit space (quirk sondé creator B2.1) : l'import GLTF pose
	# motion_scale=0.9491 et le mixer scale alors TOUTES les translations
	# évaluées. Données = mètres → 1.0 (previews exactes).
	var _arm: Node = player.get_parent()
	if _arm != null:
		var _sk := _arm.get_node_or_null("GeneralSkeleton") as Skeleton3D
		if _sk != null:
			_sk.motion_scale = 1.0
	var lib: AnimationLibrary = player.get_animation_library(&"rig")
	var count := lib.get_animation_list().size() if lib != null else 0
	print("[AnimLab] LabTools ready — player OK, %d takes" % count)
	_last_take = _previewed_short(player)
	_prefill_assign(_last_take)
	_refresh_take_usage(_last_take)


## [member take_usage] is display-only: editor-visible but read-only and
## never stored in the scene (keeps anim_lab.tscn a clean scaffold).
func _validate_property(property: Dictionary) -> void:
	if String(property.get("name", "")) == "take_usage":
		property["usage"] = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
	elif String(property.get("name", "")) == "assign_entry":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = ",".join(_usage_keys(_last_take))


## Pre-fill watcher (editor only): whenever the dock preview moves to another
## take, [member rename_to] follows so rename is edit-not-type. Your edits
## are never overwritten — writes happen only on take switch, and only when
## the value actually differs.
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var player := _find_lab_player()
	if player == null:
		return
	var short := _previewed_short(player)
	if short != "" and short != _last_take:
		_last_take = short
		if rename_to != short:
			rename_to = short
		_prefill_assign(short)
		_refresh_take_usage(short)


## Recomputes [member take_usage] for the previewed take ("" = hint text).
## Notifies the inspector only on actual change — the rebuild fires on take
## switch, assign, or ready, never while you edit another field.
func _refresh_take_usage(short: String) -> void:
	var sel := assign_entry
	if sel != "" and not sel in _usage_keys(short):
		sel = ""
	var text := _describe_take_usage(short, sel) if short != "" else "preview a take to see its moveset usage"
	if text != take_usage:
		take_usage = text
		notify_property_list_changed()


## One block per slot/variant referencing the take: kind, active index, loop
## and raw phases (variant phases first, then the slot phases they merge
## over) — "not used" when the take is lab-only. The picker-selected entry
## is marked ►. Pure Moveset read, no player needed (headless-testable seam).
func _describe_take_usage(short: String, selected: String = "") -> String:
	var lines := PackedStringArray(["rig/" + short])
	var slots: Variant = (Moveset.load_object()).get("slots", {})
	for u in _usages(short):
		var d := u as Dictionary
		var slot: Variant = (slots as Dictionary).get(String(d["slot"]), {}) if slots is Dictionary else {}
		if not slot is Dictionary:
			continue
		var entry: Dictionary = slot as Dictionary
		if not bool(d["legacy"]):
			for v in (slot as Dictionary).get("variants", []):
				if v is Dictionary:
					var m := (v as Dictionary).get("match", {}) as Dictionary
					if str(m.get("body", "any")) == String(d["body"]) and str(m.get("stance", "any")) == String(d["stance"]):
						entry = v as Dictionary
						break
		var clips: Array = entry.get("clips", [])
		var mark := "► " if String(d["key"]) == selected else ""
		lines.append(_describe_use(mark, String(d["slot"]), _kind_label(d), int(entry.get("active", 0)), clips.size(), slot as Dictionary, entry))
	if lines.size() == 1:
		lines.append("not used by any moveset slot (lab-only)")
	return "\n".join(lines)


## "legacy" or "variant body=X stance=Y" for a usage record.
func _kind_label(d: Dictionary) -> String:
	if bool(d.get("legacy", false)):
		return "legacy"
	return "variant body=%s stance=%s" % [String(d["body"]), String(d["stance"])]


## Single usage line: loop lives on the slot (shared by its variants);
## variant phases merge per-key over the slot phases at boot, so both are
## shown when a variant carries its own.
func _describe_use(mark: String, slot_name: String, kind: String, active: int, total: int, slot: Dictionary, entry: Dictionary) -> String:
	var s := "%sslot %s — %s clips[%d/%d] loop=%s" % [mark, slot_name, kind, active, total, str(bool(slot.get("loop", false)))]
	if not entry.is_empty():
		var vph: Variant = entry.get("phases", {})
		if vph is Dictionary and not (vph as Dictionary).is_empty():
			s += "\n    variant phases " + str(vph)
	var sph: Variant = slot.get("phases", {})
	if sph is Dictionary and not (sph as Dictionary).is_empty():
		s += "\n    slot phases " + str(sph)
	return s


## Pre-fills the Assign section from the previewed take's current moveset
## entries: the picker selects the first usage (take_usage marks it ►),
## picking another entry re-fills the fields below. Unused take = picker
## empty + section reset to defaults. Setting the picker goes through its
## setter, which pre-fills from the chosen key.
func _prefill_assign(short: String) -> void:
	_last_take = short
	var keys := _usage_keys(short)
	if keys.is_empty():
		_reset_assign()
		_refresh_take_usage(short)
		return
	_reset_assign()
	assign_entry = keys[0]


## All moveset entries referencing the take, in take_usage display order:
## [{key, slot, body, stance, legacy}]. Shared by the describe text and the
## picker so both always agree.
func _usages(short: String) -> Array:
	var out: Array = []
	var slots: Variant = (Moveset.load_object()).get("slots", {})
	if not slots is Dictionary:
		return out
	for slot_name in (slots as Dictionary):
		var slot: Variant = (slots as Dictionary)[slot_name]
		if not slot is Dictionary:
			continue
		if ((slot as Dictionary).get("clips", []) as Array).has(short):
			out.append({"key": str(slot_name), "slot": str(slot_name), "body": "any", "stance": "any", "legacy": true})
		for v in (slot as Dictionary).get("variants", []):
			if v is Dictionary and ((v as Dictionary).get("clips", []) as Array).has(short):
				var m := (v as Dictionary).get("match", {}) as Dictionary
				var b := str(m.get("body", "any"))
				var s := str(m.get("stance", "any"))
				out.append({"key": "%s · %s/%s" % [str(slot_name), b, s], "slot": str(slot_name), "body": b, "stance": s, "legacy": false})
	return out


## Picker keys for the take ("" when lab-only).
func _usage_keys(short: String) -> PackedStringArray:
	var keys := PackedStringArray()
	for u in _usages(short):
		keys.append(String((u as Dictionary)["key"]))
	return keys


## Pre-fills the Assign fields from one picker key (no-op on stale/foreign
## keys). The key's entry provides slot/body/stance; loop comes from the
## slot, phases from the written entry (absent keys stay -1).
func _prefill_from_key(short: String, key: String) -> void:
	var parsed := _parse_usage_key(key)
	if not bool(parsed[4]):
		return
	var slots: Variant = (Moveset.load_object()).get("slots", {})
	var slot: Variant = (slots as Dictionary).get(String(parsed[0]), {}) if slots is Dictionary else {}
	if not slot is Dictionary:
		return
	if bool(parsed[3]):
		if not (((slot as Dictionary).get("clips", [])) as Array).has(short):
			return
		_prefill_entry(String(parsed[0]), "any", "any", slot as Dictionary, slot as Dictionary)
	else:
		var hit := false
		for v in (slot as Dictionary).get("variants", []):
			if v is Dictionary:
				var m := (v as Dictionary).get("match", {}) as Dictionary
				if str(m.get("body", "any")) == String(parsed[1]) and str(m.get("stance", "any")) == String(parsed[2]) and (((v as Dictionary).get("clips", [])) as Array).has(short):
					_prefill_entry(String(parsed[0]), String(parsed[1]), String(parsed[2]), slot as Dictionary, v as Dictionary)
					hit = true
					break
		if not hit:
			return
	_refresh_take_usage(short)


## Splits a picker key into [slot, body, stance, is_legacy, ok].
func _parse_usage_key(key: String) -> Array:
	if " · " in key:
		var lr := key.split(" · ", true, 1)
		if lr.size() != 2:
			return ["", "", "", false, false]
		var bs := lr[1].split("/", true, 1)
		if bs.size() != 2 or lr[0] == "" or bs[0] == "" or bs[1] == "":
			return ["", "", "", false, false]
		return [lr[0], bs[0], bs[1], false, true]
	if key != "":
		return [key, "any", "any", true, true]
	return ["", "", "", false, false]


## Resets the Assign section to "keep" defaults (fresh take).
func _reset_assign() -> void:
	assign_slot = ""
	assign_body = "any"
	assign_stance = "any"
	assign_loop = -1
	assign_attack_start = -1.0
	assign_release_start = -1.0
	assign_windup_speed = -1.0
	assign_attack_speed = -1.0
	assign_release_speed = -1.0
	assign_stamina_cost = -1.0
	assign_sweep_start = -1.0
	assign_contact_time = -1.0


## What an assign with the current fields would change on the existing entry
## ("" = new slot/variant, or no-change re-assign — both write at once):
## clips/active/loop lines plus one line per phase key the fields override
## with a different value. Pure read of the moveset object (headless-testable
## seam) — the caller shows it in the overwrite dialog when non-empty.
func _assign_diff(obj: Dictionary, slot_name: String, body: String, stance: String, take: String) -> String:
	var slots: Variant = obj.get("slots", {})
	if not slots is Dictionary or not (slots as Dictionary).has(slot_name):
		return ""
	var slot: Variant = (slots as Dictionary)[slot_name]
	if not slot is Dictionary:
		return ""
	var target: Dictionary = slot as Dictionary
	if not (body == "any" and stance == "any"):
		var found := {}
		for v in (slot as Dictionary).get("variants", []):
			if v is Dictionary:
				var m := (v as Dictionary).get("match", {}) as Dictionary
				if str(m.get("body", "any")) == body and str(m.get("stance", "any")) == stance:
					found = v as Dictionary
					break
		if found.is_empty():
			return ""
		target = found
	var changes := PackedStringArray()
	if (target.get("clips", []) as Array) != [take]:
		changes.append("clips %s -> [%s]" % [str(target.get("clips", [])), take])
	if int(target.get("active", 0)) != 0:
		changes.append("active %d -> 0" % int(target.get("active", 0)))
	if assign_loop != -1 and bool(target.get("loop", false)) != (assign_loop == 1):
		changes.append("loop %s -> %s" % [str(bool(target.get("loop", false))).to_lower(), str(assign_loop == 1).to_lower()])
	var ph: Variant = target.get("phases", {})
	var d := (ph as Dictionary) if ph is Dictionary else {}
	for pair in [["attack_start", assign_attack_start], ["release_start", assign_release_start], ["windup_speed", assign_windup_speed], ["attack_speed", assign_attack_speed], ["release_speed", assign_release_speed], ["stamina_cost", assign_stamina_cost], ["sweep_start", assign_sweep_start], ["contact_time", assign_contact_time]]:
		var nv: float = pair[1]
		if nv >= 0.0:
			var cv: Variant = d.get(String(pair[0]), null)
			if not ((cv is float or cv is int) and is_equal_approx(float(cv), nv)):
				changes.append("%s %s -> %s" % [String(pair[0]), str(cv) if cv != null else "absent", str(nv)])
	return "\n".join(changes)


## Copies one entry's coordinates into the Assign vars: loop comes from the
## slot (shared by its variants), phases from the written entry itself
## (variant phases in variant mode, slot phases in legacy) — absent keys
## stay -1 (the boot merge falls back per-key, so re-assign is a no-op).
func _prefill_entry(slot_name: String, body: String, stance: String, slot: Dictionary, entry: Dictionary) -> void:
	assign_slot = slot_name
	assign_body = body
	assign_stance = stance
	assign_loop = 1 if bool(slot.get("loop", false)) else 0
	var ph: Variant = entry.get("phases", {})
	var d := (ph as Dictionary) if ph is Dictionary else {}
	assign_attack_start = _phase_num(d, "attack_start")
	assign_release_start = _phase_num(d, "release_start")
	assign_windup_speed = _phase_num(d, "windup_speed")
	assign_attack_speed = _phase_num(d, "attack_speed")
	assign_release_speed = _phase_num(d, "release_speed")
	assign_stamina_cost = _phase_num(d, "stamina_cost")
	assign_sweep_start = _phase_num(d, "sweep_start")
	assign_contact_time = _phase_num(d, "contact_time")


## Numeric phase value or -1 (keep) when absent/non-numeric.
func _phase_num(d: Dictionary, key: String) -> float:
	var v: Variant = d.get(key, -1.0)
	if v is float or v is int:
		return float(v)
	return -1.0


## Short name of the dock-previewed take ("" when nothing previewed).
func _previewed_short(player: AnimationPlayer) -> String:
	var take: StringName = player.current_animation
	if take == &"":
		take = player.assigned_animation
	if not str(take).begins_with("rig/"):
		return ""
	return str(take).trim_prefix("rig/")


func hide_current_take() -> void:
	var player := _find_lab_player()
	if player == null:
		push_warning("[AnimLab] LabPlayer not found (reopen scenes/anim_lab/anim_lab.tscn / check the RigRoot instance)")
		return
	var take: StringName = player.current_animation
	if take == &"":
		take = player.assigned_animation
	if not str(take).begins_with("rig/"):
		print("[AnimLab] nothing to hide — preview a take in the Animation dock first (current='%s')" % str(take))
		return
	var short := str(take).trim_prefix("rig/")
	_append_hidden(short)
	_warn_slot_use(short)
	var lib: AnimationLibrary = player.get_animation_library(&"rig")
	if lib == null:
		print("[AnimLab] hidden '%s' in JSON (no live library)" % short)
		return
	var next_short := _next_take(lib, short)
	if lib.has_animation(short):
		lib.remove_animation(short)
		if ResourceSaver.save(lib, PACK) == OK:
			print("[AnimLab] hidden '%s' (%d takes left)" % [short, lib.get_animation_list().size()])
		else:
			push_warning("[AnimLab] hidden '%s' in JSON but .res re-save failed" % short)
	else:
		print("[AnimLab] hidden '%s' in JSON (already absent live)" % short)
	if next_short != "" and lib.has_animation(next_short):
		var full := StringName("rig/" + next_short)
		player.assigned_animation = full
		player.play(full)
		print("[AnimLab] now showing '%s'" % next_short)


## Renames the previewed take to [member rename_to]: live rename + renames
## JSON update (chain-collapsed: A->B then B->C records A->C only, so a
## re-bake applies single hops with no dead alias keys) + moveset clips
## updated + .res re-save.
func rename_current_take() -> void:
	var player := _find_lab_player()
	if player == null:
		push_warning("[AnimLab] LabPlayer not found (reopen scenes/anim_lab/anim_lab.tscn / check the RigRoot instance)")
		return
	var take: StringName = player.current_animation
	if take == &"":
		take = player.assigned_animation
	if not str(take).begins_with("rig/"):
		print("[AnimLab] nothing to rename — preview a take in the Animation dock first (current='%s')" % str(take))
		return
	var short := str(take).trim_prefix("rig/")
	var new := rename_to.strip_edges()
	if new == "":
		print("[AnimLab] set 'rename_to' to the curated alias first (action__body__stance__NN)")
		return
	if "/" in new or "\\" in new:
		push_warning("[AnimLab] alias must not contain a path separator: '%s'" % new)
		return
	if new == short:
		print("[AnimLab] already named '%s'" % short)
		return
	var lib: AnimationLibrary = player.get_animation_library(&"rig")
	if lib == null:
		print("[AnimLab] no live library to rename in")
		return
	if not lib.has_animation(short):
		print("[AnimLab] '%s' absent from the live library (re-bake?)" % short)
		return
	if lib.has_animation(new):
		push_warning("[AnimLab] target '%s' already exists (pick another alias)" % new)
		return
	if new.get_slice("__", 0) != short.get_slice("__", 0):
		push_warning("[AnimLab] pack prefix changes '%s' -> '%s' (allowed, tally/slot fallbacks follow the new name)" % [short, new])
	lib.rename_animation(short, new)
	_append_rename(short, new)
	var updated := _update_slot_clips(short, new)
	if ResourceSaver.save(lib, PACK) == OK:
		print("[AnimLab] renamed '%s' -> '%s' (%s slots updated)" % [short, new, updated])
	else:
		push_warning("[AnimLab] renamed '%s' -> '%s' live but .res re-save failed" % [short, new])
	var full := StringName("rig/" + new)
	player.assigned_animation = full
	player.play(full)
	_last_take = new


## Writes the previewed take into player_moveset.json at [member assign_slot]
## (+ [member assign_body]/[member assign_stance]): any/any replaces the
## legacy clips (active reset to 0), anything else upserts the matching
## variant (created when absent, appended at the end — resolve_clip sorts by
## score so an exact match always wins regardless of JSON order). Loop and
## phase exports != -1 override the written entry; everything else
## (loop/phases of the other entries, slot loop/phases in variant mode) is
## kept. Validated with Moveset.validate_moveset before the atomic save.
func assign_current_take() -> void:
	var player := _find_lab_player()
	if player == null:
		push_warning("[AnimLab] LabPlayer not found (reopen scenes/anim_lab/anim_lab.tscn / check the RigRoot instance)")
		return
	var take: StringName = player.current_animation
	if take == &"":
		take = player.assigned_animation
	if not str(take).begins_with("rig/"):
		print("[AnimLab] nothing to assign — preview a take in the Animation dock first (current='%s')" % str(take))
		return
	var short := str(take).trim_prefix("rig/")
	var slot_name := assign_slot.strip_edges()
	if slot_name == "":
		print("[AnimLab] set 'assign_slot' to the moveset slot first (e.g. idle, walk, attack_light_1)")
		return
	var body := assign_body.strip_edges()
	var stance := assign_stance.strip_edges()
	if not StringName(body) in Moveset.KNOWN_BODIES:
		push_warning("[AnimLab] unknown body '%s' (male/female/any)" % body)
		return
	if not StringName(stance) in Moveset.KNOWN_STANCES:
		push_warning("[AnimLab] unknown stance '%s' (sword_shield/two_hand/any)" % stance)
		return
	var lib: AnimationLibrary = player.get_animation_library(&"rig")
	if lib == null or not lib.has_animation(short):
		push_warning("[AnimLab] '%s' absent from the live library (re-bake?)" % short)
		return
	var hidden: Array = (JsonFile.load_object(HIDDEN_PATH)).get("hidden", [])
	if hidden.has(short):
		push_warning("[AnimLab] '%s' is hidden — restore its line in anim_lab_hidden.json + re-bake before assigning" % short)
		return
	var obj := Moveset.load_object()
	if assign_loop < -1 or assign_loop > 1:
		push_warning("[AnimLab] assign_loop must be -1/0/1 (got %d, kept)" % assign_loop)
	if not StringName(slot_name) in Moveset.KNOWN_SLOTS:
		push_warning("[AnimLab] slot '%s' unknown — written anyway, the game ignores it until KNOWN_SLOTS grows" % slot_name)
	var phases := {
		"attack_start": assign_attack_start, "release_start": assign_release_start,
		"windup_speed": assign_windup_speed, "attack_speed": assign_attack_speed,
		"release_speed": assign_release_speed, "stamina_cost": assign_stamina_cost,
		"sweep_start": assign_sweep_start, "contact_time": assign_contact_time,
	}
	var diff := _assign_diff(obj, slot_name, body, stance, short)
	if diff == "":
		_execute_assign(obj, slot_name, body, stance, short, assign_loop, phases)
	else:
		_confirm_overwrite(slot_name, body, stance, short, assign_loop, phases, diff)


## Writes the previewed take at the given coordinates (creation and no-change
## re-assign — the caller only reaches here directly when _assign_diff is
## empty, or through the overwrite dialog's Confirmed path).
func _execute_assign(obj: Dictionary, slot_name: String, body: String, stance: String, short: String, loop: int, phases: Dictionary) -> void:
	var res := Moveset.assign_clip(obj, slot_name, body, stance, short, loop, phases)
	if not bool(res.get("ok", false)):
		push_warning("[AnimLab] assign failed: %s" % str(res.get("error", "?")))
		return
	for issue in Moveset.validate_moveset(obj):
		push_warning("[AnimLab] moveset: %s" % issue)
	JsonFile.save_atomic(Moveset.PATH, obj)
	print("[AnimLab] assigned '%s' -> slot '%s' %s" % [short, slot_name, str(res.get("where", ""))])
	_sync_entry_to_take(short)


## Modal overwrite guard (data is the game — a lost variant is hours lost):
## shows what the write would change on the existing entry, Confirmer writes,
## Annuler drops. Editor-only (the button lives in the inspector).
func _confirm_overwrite(slot_name: String, body: String, stance: String, short: String, loop: int, phases: Dictionary, diff: String) -> void:
	var where := "legacy" if body == "any" and stance == "any" else "variant {body:%s stance:%s}" % [body, stance]
	var params := {"slot": slot_name, "body": body, "stance": stance, "take": short, "loop": loop, "phases": phases}
	_assign_dialog = EditorConfirm.ask("Overwrite moveset entry?",
		"Assign '%s' would OVERWRITE slot '%s' %s:\n\n%s" % [short, slot_name, where, diff],
		"Overwrite", _on_assign_confirmed.bind(params),
		_assign_dialog if is_instance_valid(_assign_dialog) else null)


## Dialog Confirmed path: reloads the moveset fresh (never writes on stale
## data) and executes the pending assign.
func _on_assign_confirmed(params: Dictionary) -> void:
	_assign_dialog = null
	_execute_assign(Moveset.load_object(), String(params["slot"]), String(params["body"]), String(params["stance"]), String(params["take"]), int(params["loop"]), params["phases"] as Dictionary)


## Points the picker at the take's first current usage after a write (the
## setter re-fills the fields from the fresh state); picker empty when the
## take left no usage behind.
func _sync_entry_to_take(short: String) -> void:
	var keys := _usage_keys(short)
	var want := keys[0] if not keys.is_empty() else ""
	if assign_entry != want:
		assign_entry = want
	else:
		_refresh_take_usage(short)


## The take right after [param short] in the library list (previous one when
## hiding the last, "" when alone) — the dock is moved there after a hide
## instead of falling back to the top of the list.
func _next_take(lib: AnimationLibrary, short: String) -> String:
	var names: Array = lib.get_animation_list()
	var idx := -1
	for i in names.size():
		if str(names[i]) == short:
			idx = i
			break
	if idx == -1 or names.size() < 2:
		return ""
	if idx + 1 < names.size():
		return str(names[idx + 1])
	return str(names[idx - 1])


## The AnimationPlayer carrying the baked "rig" library, searched from the
## edited scene root — no configured path to go stale.
func _find_lab_player() -> AnimationPlayer:
	var scope := get_owner() if get_owner() != null else get_parent()
	if scope == null:
		return null
	for n in scope.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		if ap != null and ap.has_animation_library(&"rig"):
			return ap
	var any: Array = scope.find_children("*", "AnimationPlayer", true, false)
	if not any.is_empty():
		return any[0] as AnimationPlayer
	return null


func _append_hidden(short: String) -> void:
	var obj := JsonFile.load_object(HIDDEN_PATH)
	var hidden: Array = obj.get("hidden", [])
	if not hidden.has(short):
		hidden.append(short)
	obj["hidden"] = hidden
	JsonFile.save_atomic(HIDDEN_PATH, obj)


## Records old -> new in the renames map. Renaming an already-renamed take
## (old is itself an alias) updates the original entry instead of adding a
## new one: values pointing at old are rewritten to new (chain collapse) and
## no intermediate old -> new key is stored, so the baker applies single
## hops and the map never grows dead alias keys.
func _append_rename(old: String, new: String) -> void:
	var obj := JsonFile.load_object(RENAMES_PATH)
	var raw: Variant = obj.get("renames", {})
	var renames := (raw as Dictionary).duplicate() if raw is Dictionary else {}
	var collapsed := false
	for key in renames:
		if str(renames[key]) == old:
			renames[key] = new
			collapsed = true
	if not collapsed:
		renames[old] = new
	obj["renames"] = renames
	JsonFile.save_atomic(RENAMES_PATH, obj)


## Rewrites old -> new in every moveset slot clip list (legacy + variants).
## Returns the updated slot count (0 = the take is lab-only, nothing to do).
func _update_slot_clips(old: String, new: String) -> int:
	var obj := Moveset.load_object()
	var slots: Variant = obj.get("slots", {})
	if not slots is Dictionary:
		return 0
	var updated := 0
	for slot_name in (slots as Dictionary):
		var slot: Variant = (slots as Dictionary)[slot_name]
		if not slot is Dictionary:
			continue
		var touched := false
		var clips: Array = (slot as Dictionary).get("clips", [])
		for i in clips.size():
			if str(clips[i]) == old:
				clips[i] = new
				touched = true
		for v in (slot as Dictionary).get("variants", []):
			if v is Dictionary:
				var vclips: Array = (v as Dictionary).get("clips", [])
				for i in vclips.size():
					if str(vclips[i]) == old:
						vclips[i] = new
						touched = true
		if touched:
			updated += 1
			print("[AnimLab] slot '%s': '%s' -> '%s'" % [slot_name, old, new])
	if updated > 0:
		JsonFile.save_atomic(Moveset.PATH, obj)
	return updated


## Loud warning (not a block — restore is one JSON line away) when the take
## is referenced by a moveset slot (legacy clips or variant clips): the game
## would silently fall back.
func _warn_slot_use(short: String) -> void:
	var slots: Variant = (Moveset.load_object()).get("slots", {})
	if not slots is Dictionary:
		return
	for slot_name in (slots as Dictionary):
		var slot: Variant = (slots as Dictionary)[slot_name]
		if not slot is Dictionary:
			continue
		var clips: Array = (slot as Dictionary).get("clips", [])
		if clips.has(short):
			push_warning("[AnimLab] '%s' is used by slot '%s' (game falls back)" % [short, slot_name])
		for v in (slot as Dictionary).get("variants", []):
			if v is Dictionary and ((v as Dictionary).get("clips", []) as Array).has(short):
				push_warning("[AnimLab] '%s' is used by slot '%s' variant %s (game falls back)" % [short, slot_name, str((v as Dictionary).get("match", {}))])
