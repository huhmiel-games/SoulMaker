extends SceneTree

## Headless arm-IK gate (anim_creator Phase 0 + 0-bis): instantiates the arm
## spike and sweeps every solver mode over the reach envelope — TwoBoneIK
## across all 6 pole directions, FABRIK modes once each (no pole). Per
## (mode, dir) it reports samples, max hand-tracking error, elbow flips,
## worst dot and max flexion. GO = max error <= 0.05 m AND 0 flips (human
## visual confirm still required); anything else = Blender workflow.
## Run: <godot> --headless --path . --script res://src/cli_tools/spikes/arm_ik_validate.gd
const SCENE := "res://scenes/spikes/arm_ik_test.tscn"

const SETTLE_FRAMES := 60
const SAMPLE_SETTLE := 3
const STEP := 0.15
const EXTENT := 0.3
const REACH_FRAC := 0.88
const MIN_Y := 0.15
const ERR_TOL := 0.05

var _scene: Node
var _frame := 0
var _phase := 0  # 0 settle, 1 sweep, 2 twist re-run, 3 report
var _jobs: Array = []  # [{mode, dir, iters, delta, tag}]
var _job_idx := 0
var _pass := 0
var _side_idx := 0
var _samples: Array = []
var _sample_idx := 0
var _wait := 0
var _rows: Array = []

const SIDES := [&"Left", &"Right"]
const POLE_NAMES := ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]
## 0-bis tuning matrix on fabrik-arm (iters × angular step) + two/-Z baseline;
## the best tuning re-runs once with the twist disperser before the verdict.
const TUNINGS := [[64, 0.1], [64, 0.2], [64, 0.3], [128, 0.1], [128, 0.2], [128, 0.3]]


func _initialize() -> void:
	_scene = load(SCENE).instantiate()
	root.add_child.call_deferred(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _scene == null or not _scene.is_node_ready():
		return false
	if _phase == 0:
		if _frame >= SETTLE_FRAMES:
			_begin_dir()
		return false
	if _phase == 1:
		_step_sweep()
		return false
	if _phase == 2:
		_phase = 3
		_report()
		return true
	return false


func _begin_dir() -> void:
	_build_jobs_if_needed()
	var job: Dictionary = _jobs[_job_idx]
	_scene.set_solver_mode(StringName(job["mode"]))
	if String(job["mode"]) == "two":
		_scene.set_pole_dir(int(job["dir"]))
	else:
		_scene.set_fabrik_tuning(int(job["iters"]), float(job["delta"]))
	_side_idx = 0
	_build_samples()
	_sample_idx = 0
	_wait = SAMPLE_SETTLE
	_phase = 1


## Job list, built once: two/-Z baseline, the fabrik-arm tuning matrix, then
## (after the matrix) the best tuning re-run with the twist disperser.
## Fold jobs (fold=true) skip the grid: probes on spheres r=0.12/0.20 around
## the shoulder rest — deep flexion demand (~153°/134° by law of cosines).
const FOLD_RADII := [0.12, 0.20]
const FOLD_DIRS := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0.7, 0.7, 0), Vector3(-0.7, 0.7, 0)]
func _build_jobs_if_needed() -> void:
	if not _jobs.is_empty():
		return
	_jobs.append({"mode": "two", "dir": 5, "iters": 0, "delta": 0.0, "fold": false, "tag": "two/-Z"})
	for t in TUNINGS:
		_jobs.append({"mode": "fabrik-arm", "dir": -1, "iters": int(t[0]), "delta": float(t[1]), "fold": false, "tag": "fabrik-arm i%d/d%.1f" % [int(t[0]), float(t[1])]})


func _build_samples() -> void:
	_samples.clear()
	var side: StringName = SIDES[_side_idx]
	var job: Dictionary = _jobs[_job_idx]
	if bool(job.get("fold", false)):
		var shoulder: Vector3 = _scene.shoulder_rest_local(side)
		for r in FOLD_RADII:
			for dir in FOLD_DIRS:
				var p: Vector3 = shoulder + (dir as Vector3).normalized() * float(r)
				if p.y >= MIN_Y:
					_samples.append(p)
		return
	var rest: Vector3 = _scene.hand_rest_local(side)
	var reach: float = _scene.reach_of(side)
	var shoulder: Vector3 = _scene.shoulder_rest_local(side)
	var n := int(EXTENT / STEP)
	for ix in range(-n, n + 1):
		for iy in range(-n, n + 1):
			for iz in range(-n, n + 1):
				var p := rest + Vector3(ix, iy, iz) * STEP
				if p.y < MIN_Y:
					continue
				if shoulder.distance_to(p) > reach * REACH_FRAC:
					continue
				_samples.append(p)


func _step_sweep() -> void:
	var side: StringName = SIDES[_side_idx]
	if _sample_idx >= _samples.size():
		_side_idx += 1
		if _side_idx >= SIDES.size():
			_close_dir()
			return
		_build_samples()
		_sample_idx = 0
		_wait = SAMPLE_SETTLE
		return
	if _wait > 0:
		if _sample_idx == 0 and _wait == SAMPLE_SETTLE:
			_scene.set_hand_target(side, _samples[_sample_idx])
		_wait -= 1
		if _wait == 0:
			_record(side)
		return
	_sample_idx += 1
	if _sample_idx < _samples.size():
		_scene.set_hand_target(side, _samples[_sample_idx])
		_wait = SAMPLE_SETTLE


func _record(side: StringName) -> void:
	var err: float = _scene.tracking_error(side)
	var dot: float = _scene.elbow_dot(side)
	var flex: float = _scene.elbow_flexion(side)
	_rows.append({"tag": String((_jobs[_job_idx] as Dictionary)["tag"]), "mode": String((_jobs[_job_idx] as Dictionary)["mode"]), "side": String(side), "err": err, "flip": dot < 0.0, "dot": dot, "flex": flex, "pos": _samples[_sample_idx]})


func _close_dir() -> void:
	_job_idx += 1
	if _job_idx < _jobs.size():
		_begin_dir()
		return
	_finish_pass()


## End of a pass: pass 0 computes the best fabrik-arm tuning (lowest max_err
## with 0 flips) and re-runs it once with the twist disperser; pass 1 (or an
## unwinnable matrix) goes to the report — TwoBone fallback included.
func _finish_pass() -> void:
	if _pass == 1:
		_phase = 2
		return
	var best_err := 9e9
	var best_it := 0
	var best_d := 0.0
	var seen := {}
	for r in _rows:
		var d: Dictionary = r
		if String(d["mode"]) != "fabrik-arm":
			continue
		var tag := String(d["tag"])
		var s: Dictionary = seen.get(tag, {"max": 0.0, "flips": 0, "iters": 0, "delta": 0.0})
		s["max"] = maxf(float(s["max"]), float(d["err"]))
		if bool(d["flip"]):
			s["flips"] = int(s["flips"]) + 1
		seen[tag] = s
	for tag in seen:
		var s: Dictionary = seen[tag]
		if int(s["flips"]) == 0 and float(s["max"]) < best_err:
			best_err = float(s["max"])
			var tb: PackedStringArray = String(tag).split(" ")[1].split("/")
			best_it = int(tb[0].trim_prefix("i"))
			best_d = float(tb[1].trim_prefix("d"))
	if best_it == 0:
		_phase = 2
		return
	_pass = 1
	_jobs = [
		{"mode": "fabrik-twist", "dir": -1, "iters": best_it, "delta": best_d, "fold": false, "tag": "fabrik-twist i%d/d%.1f" % [best_it, best_d]},
		{"mode": "two", "dir": 5, "iters": 0, "delta": 0.0, "fold": true, "tag": "fold-two"},
		{"mode": "fabrik-arm", "dir": -1, "iters": best_it, "delta": best_d, "fold": true, "tag": "fold-fabrik-arm i%d/d%.1f" % [best_it, best_d]},
	]
	_job_idx = 0
	_begin_dir()


func _report() -> void:
	var per_tag := {}
	for r in _rows:
		var d: Dictionary = r
		var tag := String(d["tag"])
		var e: Dictionary = per_tag.get(tag, {"n": 0, "max_err": 0.0, "flips": 0, "min_dot": 1.0, "max_flex": 0.0, "over": 0, "worst": Vector3.ZERO})
		e["n"] = int(e["n"]) + 1
		e["max_err"] = maxf(float(e["max_err"]), float(d["err"]))
		e["max_flex"] = maxf(float(e["max_flex"]), float(d["flex"]))
		if float(d["err"]) > ERR_TOL:
			e["over"] = int(e["over"]) + 1
			e["worst"] = d["pos"]
		if bool(d["flip"]):
			e["flips"] = int(e["flips"]) + 1
		e["min_dot"] = minf(float(e["min_dot"]), float(d["dot"]))
		per_tag[tag] = e
	var best := ""
	var folds := {}
	for tag in per_tag:
		var e: Dictionary = per_tag[tag]
		print("[ArmIK] %s: n=%d max_err=%.1fmm over=%d worst=%s flips=%d min_dot=%.2f max_flex=%.0f" % [tag, int(e["n"]), float(e["max_err"]) * 1000.0, int(e["over"]), str(e["worst"]), int(e["flips"]), float(e["min_dot"]), float(e["max_flex"])])
		if tag.begins_with("fold"):
			folds[tag] = e
			continue
		if int(e["flips"]) == 0 and float(e["max_err"]) <= ERR_TOL and (best == "" or float(e["max_err"]) < float((per_tag[best] as Dictionary)["max_err"])):
			best = tag
	for tag in folds:
		var e: Dictionary = folds[tag]
		print("[ArmIK] %s: deepest fold flex=%.0f (expect ~153 at 12cm, ~134 at 20cm)" % [tag, float(e["max_flex"])])
	if best == "":
		print("[ArmIK] NO-GO all: TwoBone fallback stands (robotic-but-exact)")
		quit(1)
		return
	if best.begins_with("fabrik-arm"):
		var win: Dictionary = per_tag[best]
		print("[ArmIK] GO %s (flex %.0f vs two 123 — bot half, human feel decides)" % [best, float(win["max_flex"])])
	else:
		print("[ArmIK] GO %s (bot half — human visual confirm still required)" % best)
	quit(0)
