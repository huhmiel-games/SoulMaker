extends SceneTree

## Headless freeze-enforcer for the input mapping (AGENTS.md ## Input).
## Run: <godot> --headless --path . --script res://src/cli_tools/input_audit.gd
## Checks (any FAIL exits nonzero, one line per violation):
## 1. Per profile, no two actions share one discrete binding: same key code,
##    same (btn, shifted), same (mouse, shifted, mod) or same trigger.
##    Sticks may repeat (analog sharing is intended). Known benign overlaps
##    live in OVERLAP_ALLOW with their justification.
## 2. Every game-profile action is reachable from both devices (a pad-side
##    source: btn/trigger/stick, and a key-side source: key/mouse), unless
##    flagged "mirror_only" (Q re-exposes the d-pad capability, P8).
## 3. Every action name consumed in src/ — is_pressed / is_just_pressed /
##    is_just_released / time_held / analog / wheel_ticks args and
##    `action == &"x"` comparisons — names a real action of some profile
##    (catches phantom actions like the old fine_mode/nudge_*).
## 4. No raw input reads outside input_manager.gd: Input.is_*/get_* polling
##    or raw key/button event fields. Input.mouse_mode stays allowed
##    (cursor management, not gameplay input).
## This file exempts itself from rule 3 (its regexes contain &"..." text).

const OVERLAP_ALLOW := {
	# Empty: S used to be shared by cam_pan_back and pause_menu — every S
	# press opened the pause instead of panning. Kept as the escape hatch
	# for genuinely benign overlaps, with justification.
}

const CONSUME_RES := [
	"(?:is_just_pressed|is_just_released|is_pressed|time_held|analog|action_value|wheel_ticks)\\(&\"([A-Za-z_0-9]+)\"\\)",
	"action\\s*==\\s*&\"([A-Za-z_0-9]+)\"",
]

const RAW_INPUT_RES := [
	"Input\\.(is_physical_key_pressed|is_key_pressed|is_joy_button_pressed|is_action_pressed|is_action_just_pressed|is_action_just_released|get_joy_axis|get_joy_name|get_axis|get_vector|get_accelerometer|get_gravity|get_magnetometer|get_gyroscope)",
	"\\.(physical_keycode|keycode|button_index)\\b",
]


func _initialize() -> void:
	var errors: Array[String] = []
	var IM: GDScript = load("res://src/autoloads/input_manager.gd") as GDScript
	if IM == null:
		printerr("INPUT AUDIT FAIL: cannot load input_manager.gd")
		quit(1)
		return
	var profiles: Dictionary = IM.PROFILES
	_check_bindings(profiles, errors)
	_check_coverage(profiles, errors)
	_check_consumers(profiles, errors)
	_check_raw_input(errors)
	if errors.is_empty():
		var total := 0
		for profile in profiles:
			total += (profiles[profile] as Dictionary).size()
		print("INPUT AUDIT PASS: %d profiles, %d actions, bindings unique, consumers known, no raw input" % [profiles.size(), total])
		quit(0)
	else:
		for e in errors:
			printerr("INPUT AUDIT FAIL: %s" % e)
		quit(1)


func _check_bindings(profiles: Dictionary, errors: Array[String]) -> void:
	for profile in profiles:
		var seen := {}
		var entries: Dictionary = profiles[profile]
		for action in entries:
			var e: Dictionary = entries[action]
			for s in e.get("sources", []):
				var tags: Array[String] = _binding_tags(s)
				for tag in tags:
					var key := "%s/%s" % [String(profile), tag]
					if seen.has(key):
						if not _overlap_allowed(String(profile), tag, String(seen[key]), String(action)):
							errors.append("profile %s: %s and %s share %s" % [profile, seen[key], action, tag])
					else:
						seen[key] = String(action)


func _binding_tags(s: Dictionary) -> Array[String]:
	var tags: Array[String] = []
	if s.has("key"):
		tags.append("key:%d" % int(s["key"]))
	if s.has("btn"):
		tags.append("btn:%d/%s" % [int(s["btn"]), str(bool(s.get("shifted", false)))])
	if s.has("mouse"):
		tags.append("mouse:%d/%s/%d" % [int(s["mouse"]), str(bool(s.get("shifted", false))), int(s.get("mod", 0))])
	if s.has("trigger"):
		tags.append("trigger:%s" % str(s["trigger"]))
	return tags


func _overlap_allowed(profile: String, tag: String, a: String, b: String) -> bool:
	var allowed: Array = OVERLAP_ALLOW.get("%s/%s" % [profile, tag], [])
	return a in allowed and b in allowed


func _check_coverage(profiles: Dictionary, errors: Array[String]) -> void:
	var game: Dictionary = profiles.get("game", {})
	for action in game:
		var e: Dictionary = game[action]
		if bool(e.get("mirror_only", false)):
			continue
		var pad := false
		var pc := false
		for s in e.get("sources", []):
			if s.has("btn") or s.has("trigger") or s.has("stick"):
				pad = true
			if s.has("key") or s.has("mouse"):
				pc = true
		for feed in ["stick", "mouse_x", "mouse_y", "wheel"]:
			if bool(e.get(feed, false)) or int(e.get(feed, -1)) >= 0:
				if feed == "stick":
					pad = true
				else:
					pc = true
		if not pad:
			errors.append("game/%s: no pad-side source" % action)
		if not pc:
			errors.append("game/%s: no keyboard/mouse-side source" % action)


func _check_consumers(profiles: Dictionary, errors: Array[String]) -> void:
	var valid := {}
	for profile in profiles:
		for action in (profiles[profile] as Dictionary):
			valid[String(action)] = true
	var files := _gd_files("res://src")
	for path in files:
		if path.ends_with("tools/input_audit.gd"):
			continue
		var text := FileAccess.get_file_as_string(path)
		for pattern in CONSUME_RES:
			var re := RegEx.new()
			re.compile(pattern)
			for m in re.search_all(text):
				var action := m.get_string(1)
				if not valid.has(action):
					errors.append("%s: unknown action &\"%s\"" % [path, action])


func _check_raw_input(errors: Array[String]) -> void:
	var files := _gd_files("res://src")
	for path in files:
		if path.ends_with("autoloads/input_manager.gd"):
			continue
		var text := FileAccess.get_file_as_string(path)
		for pattern in RAW_INPUT_RES:
			var re := RegEx.new()
			re.compile(pattern)
			for m in re.search_all(text):
				# Input.mouse_mode is cursor management, not gameplay input.
				var line := text.substr(0, m.get_start()).rsplit("\n", true, 1)[-1] + m.get_string(0)
				if line.contains("mouse_mode"):
					continue
				errors.append("%s: raw input read `%s`" % [path, m.get_string(0)])


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for entry in dir.get_files():
		if entry.ends_with(".gd"):
			out.append(dir_path.path_join(entry))
	for sub in dir.get_directories():
		out.append_array(_gd_files(dir_path.path_join(sub)))
	return out
