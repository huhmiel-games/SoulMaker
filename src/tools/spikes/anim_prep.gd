extends RefCounted

class_name AnimPrep


static func retarget_copy(source: Animation, player: AnimationPlayer, skeleton: Skeleton3D) -> Animation:
	var copy: Animation = source.duplicate()
	var skeleton_path: String = player.get_parent().get_path_to(skeleton)
	for i in copy.get_track_count() - 1:
		var path: NodePath = copy.track_get_path(i)
		var sub: String = String(path.get_subname(0)) if path.get_subname_count() > 0 else ""
		if sub.is_empty():
			continue
		copy.track_set_path(i, NodePath(skeleton_path + ":" + sub))
	return copy


static func split_body_parts(source: Animation, lower_bones: Dictionary, upper_bones: Dictionary, context: String = "") -> Dictionary:
	var lower: Animation = source.duplicate()
	var upper: Animation = source.duplicate()
	var dropped: Dictionary = {}
	for i in range(source.get_track_count() - 1, -1, -1):
		var path: NodePath = source.track_get_path(i)
		var type: Animation.TrackType = source.track_get_type(i)
		var sub := &""
		if path.get_subname_count() > 0:
			sub = path.get_subname(0)
		var keep_lower: bool = sub == &"" or lower_bones.has(sub)
		var keep_upper: bool = sub != &"" and upper_bones.has(sub) and type != Animation.TYPE_POSITION_3D
		if not keep_lower:
			lower.remove_track(i)
		if not keep_upper:
			upper.remove_track(i)
		if sub != &"" and not lower_bones.has(sub) and not upper_bones.has(sub):
			dropped[sub] = int(dropped.get(sub, 0)) + 1

	var parts: Dictionary = {"lower": lower, "upper": upper}
	if not context.is_empty() and dropped.size() > 0:
		print("[AnimPrep.split_body_parts] ", context, " dropped bone tracks not in lower/upper sets: ", dropped)
	if dropped.size() > 0:
		parts["dropped"] = dropped
	return parts


static func add_combat_markers(anim: Animation, windup_end_ratio: float = 0.3, attack_end_ratio: float = 0.6) -> void:
	var length: float = anim.length
	if windup_end_ratio <= 0.0 or windup_end_ratio >= 1.0:
		push_warning("AnimPrep.add_combat_markers: windup_end_ratio out of range (0,1): ", windup_end_ratio)
	if attack_end_ratio <= windup_end_ratio or attack_end_ratio >= 1.0:
		push_warning("AnimPrep.add_combat_markers: attack_end_ratio out of range (windup_end,1): ", attack_end_ratio)
	var times := {
		&"windup_start": 0.0,
		&"attack_start": length * clampf(windup_end_ratio, 0.01, 0.99),
		&"release_start": length * clampf(attack_end_ratio, 0.02, 0.99),
		&"anim_end": length,
	}
	for name: StringName in times:
		if anim.has_marker(name):
			anim.remove_marker(name)
		anim.add_marker(name, times[name])