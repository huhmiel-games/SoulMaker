class_name ImpactKit
extends RefCounted

## Impact-chain time helper (P2): hitstop freezes result processing while the
## camera stays alive (the camera consumes unscaled delta — see
## PlayerCamera). Fire-and-forget: overlapping hitstops extend, never cut
## each other short (token guard). No audio here — deferred to the vault
## (ADR-014); the P2 "slam" jury reads without sound.


## Freeze to HITSTOP_SCALE for (frames / 60) real seconds, then restore.
## Re-entry bumps the token so a stale timer never restores early.
static var _token := 0
const HITSTOP_SCALE := 0.05
## Real-second duration of the most recent hitstop (features/01 blade
## rebound): the attack state reads it on a blocked connect so the reversal
## starts exactly when the freeze ends — hitstop masks the transition.
static var last_hitstop_dur := 0.0


static func hitstop(tree: SceneTree, frames: int) -> void:
	if tree == null or frames <= 0:
		return
	_token += 1
	var mine := _token
	last_hitstop_dur = float(frames) / 60.0
	Engine.time_scale = HITSTOP_SCALE
	await tree.create_timer(float(frames) / 60.0, true, false, true).timeout
	if mine == _token:
		Engine.time_scale = 1.0
