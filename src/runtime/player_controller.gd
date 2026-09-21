class_name PlayerController
extends CharacterBody3D

## P2 thin player, souls facing (single heading — body and mesh are always
## aligned): owns velocity + move_and_slide, the state machine and anim
## resolution via RigKit. No AnimationTree. Free, the body turns toward the
## camera-relative wish; locked, it tracks the enemy; at rest it keeps its
## facing (nothing turns on its own). The rig is nailed at RIG_BASE_YAW —
## the mesh looks where the body looks, always. Body forward is -Z (Godot
## convention); the rig is authored +Z, hence the PI base yaw. Spawn faces
## away from the aft camera.
const WALK_SPEED := 2.5
const RUN_SPEED := 8.0
const ACCEL := 36.0
const DECEL := 44.0
const GRAVITY := 22.0
const AIR_TO_FALL := 0.65
const IDLE_AIR_TO_FALL := 0.35
## Free turn rate toward the wish heading (weight/sec — souls redirect feel).
const FREE_FACE := 12.0
const RIG_BASE_YAW := PI
const ANIM_BLEND := 0.15
## Stamina (P2 local pool — P7 derives max/regen from Endurance): dodge is
## the only spender for now. Depleted = dodge denied, regen pauses REGEN_DELAY
## after every spend.
const STAMINA_MAX := 100.0
const DODGE_COST := 25.0
const STAMINA_REGEN := 45.0
const REGEN_DELAY := 0.8
## Dodge rolls (P2 single tier — fast/mid/fat roll tiers are P3): committed
## constant-speed roll (forward/laterals), i-frames up front, then recovery
## to the buffered state. Neutral/backward input becomes a BACKSTEP instead
## (spacing hop, no rotation, no i-frames — features/17).
const ROLL_COST := 25.0
const ROLL_SPEED := 6.0
const ROLL_TIME := 0.8
const ROLL_IFRAMES := 0.5
## Clip opens on ~0.55 s anticipation — seek past it on enter (see anim_seek).
const ROLL_SEEK := 0.55
const BACKSTEP_COST := 15.0
const BACKSTEP_SPEED := 3.5
const BACKSTEP_TIME := 0.7
## Clip idles ~0.8 s before the impulse — seek past it on enter.
const BACKSTEP_SEEK := 0.8
## Light attack (P2 single swing): forward step during the attack section
## (the swing carries through — features/01), planted otherwise.
const ATTACK_STEP := 2.0
## Weapon (P2): the real mesh (VikingSwordBS) is authored in player.tscn
## under the BladeAttach BoneAttachment3D (oriented in the editor). The
## sweep auto-sizes from the weapon mesh AABB — daggers to great hammers
## need no code change: the longest AABB axis is the blade direction and
## the sweep inherits the attach orientation, so any mesh orientation works.
## Sweep hitbox (P2): blade-sized box riding the blade every physics poll
## during the armed attack section — repositioned from the BladeAttach
## frame, target = inter-frame center delta in sweep-local space (tunneling
## guard: the cast covers the motion between two frames, not just the
## current pose). SWEEP_EXTRA pads the blade axis for the arc between
## frames; a red debug box (child of the sweep) shows the detected bounds
## in-game.
const SWEEP_EXTRA := 0.1
## Fallback sweep when no weapon mesh is found under BladeAttach.
const SWEEP_FALLBACK_SIZE := Vector3(0.07, 1.05, 0.16)
const SWEEP_FALLBACK_CENTER := Vector3(0.0, 0.375, 0.0)
## Wall rebound threshold: a wall contact below this blade ratio (guard
## third of the blade) recoils the swing; above it the blade scrapes
## through with sparks only. Tuned per weapon feel, default 0.3.
const WALL_REBOUND_RATIO := 0.3
## Wall contacts below this world height are ground-plane grazes, not
## walls (the sweep rides at blade height; the floor is y=0).
const WALL_GROUND_Y := 0.25
## Player damage (P2 minimal — hyper-armor/guard/stance are P3/P7 per
## features/17): HP pool, poise pool (hits accumulate, stagger at zero,
## refills after POISE_RESET), HURT flinch interrupts everything including
## committed attacks (souls rule — only enemy hits break attacks, 05),
## death respawns at the spawn transform (test flow — bonfire flow later).
const HP_MAX := 100.0
const POISE_MAX := 50.0
## Sustained-pressure window: must exceed one enemy attack cycle (~2.7 s)
## or poise always refills between swings and HURT never triggers.
const POISE_RESET := 3.5
const HURT_TIME := 0.5
const RESPAWN_DELAY := 2.0
## Guard (P3 S1 graybox, features/17 block/guard): held Shift/L1 raises the
## equipped shield (GuardConfig class values). Blocked hits convert damage
## into stamina cost (stability_mult) + chip HP (1 - absorb) and skip poise
## entirely — stamina is the guard's pool. A hit exceeding the remaining
## stamina breaks the guard: extended HURT (GUARD_BREAK_TIME) + no regen
## (GUARD_BREAK_NOREGEN). Hits outside the frontal block_arc bypass.
const GUARD_WALK_MULT := 0.5
const GUARD_BREAK_TIME := 1.2
const GUARD_BREAK_NOREGEN := 1.0

## Backstab crit window (P3 S2, features/17): brief attacker
## invulnerability after landing a backstab, set by StateAttack.
const CRIT_IFRAMES := 0.6

## Locomotion clips resolve from data/characters/player_moveset.json (packs
## + slots + active variant); FALLBACK lives in Moveset, not here.

## Attach points (must exist in the scene scaffold).
@onready var rig_root: Node3D = get_node("RigRoot")
@onready var wedge: Node3D = get_node("FootWedge")
@onready var cam_pivot: Node3D = get_node("CamPivot")
@onready var camera: PlayerCamera = get_node("CamPivot") as PlayerCamera
@onready var state_label: Label = get_node("../HUD/State")

var intent := PlayerIntent.new()
var machine := PlayerStateMachine.new()
var anim_state := &"idle"
## One-shot anim offset (seconds) consumed by _resolve_anim: states seek past
## clip anticipation so the visible motion matches the committed displacement.
var anim_seek := -1.0
## Manual playback flag: StateAttack drives marker sections itself
## (play_phase) — _resolve_anim stands down while set.
var anim_manual := false
var stamina := STAMINA_MAX
## Invulnerability countdown (seconds left): set by StateDodge on enter,
## ticked here, read by future enemy hitboxes via is_invulnerable().
var iframes := 0.0
## Backstab crit invulnerability (seconds left): set by StateAttack on a
## crit connect, ticked here, honored by take_hit (features/17).
var crit_iframes := 0.0
var _regen_wait := 0.0
## Damage state (P2 minimal): hp/poise pools, dead flag + respawn timer,
## _home spawn transform captured at ready.
var hp := HP_MAX
var poise := POISE_MAX
var dead := false
var _poise_wait := 0.0
var _respawn_in := -1.0
var _home := Transform3D.IDENTITY
## Guard state (P3 S1): resolved shield class (GuardConfig.merged at boot),
## harness seam (guard_hold_override forces the held read without input —
## test scenes only, never gameplay), one-shot HURT duration override set
## by a guard break and consumed by StateHurt.exit.
var guard_cfg := {}
var guard_hold_override := false
var hurt_time_override := -1.0
var guard_release_needed := false

var _player: AnimationPlayer = null
var _clips := {}
var _anim_cur := &""
## Resolved attack phases per attack slot (Moveset.phases_for at boot).
var _attack_phases := {}
## Sweep hitbox + per-swing connect registry (strongest-once rule: one
## connect per body per swing; the chain fires on the first). The sweep
## rides the blade (child of BladeAttach) — _update_sweep repositions it
## every poll from the BladeAttach frame; _prev_mid tracks the inter-frame
## center delta, primed on swing_begin. _sweep_center is the AABB center in
## attach space (auto-detected); _sweep_debug is the red bounds box.
var _sweep: ShapeCast3D = null
var _swing_hits := {}
var _blade_attach: BoneAttachment3D = null
var _sweep_center := SWEEP_FALLBACK_CENTER
var _prev_mid := Vector3.ZERO
var _sweep_primed := false
var _sweep_debug: MeshInstance3D = null


## Light-attack clip ("" = unresolved, attack refused — never T-poses).
func attack_clip() -> StringName:
	return _clips.get(&"attack_light_1", &"")


## Phases + speeds + stamina cost for the light attack (data-driven).
func attack_phases() -> Dictionary:
	return _attack_phases.get(&"attack_light_1", Moveset.PHASE_DEFAULTS)


## Impact payload for the light attack (damage, hitstop frames, shake
## scale — features/01 game feel). Weapon override point for 04.
func attack_impact() -> Dictionary:
	return attack_phases().get("impact", Moveset.IMPACT_DEFAULTS)


## Impact host of the current scene (test scenes carry one in group
## "impact"; null in scenes without — the swing still connects, only the
## juice stack stays silent).
func impact_host() -> ImpactHost:
	return get_tree().get_first_node_in_group(&"impact") as ImpactHost


## Blade-riding sweep, armed only during the attack section (StateAttack
## calls swing_begin/poll/end). Child of BladeAttach so it inherits the
## hand motion; size + center auto-detected from the weapon mesh AABB (see
## _find_weapon_mesh) so any weapon size works; _update_sweep snaps it onto
## the blade every poll. Self excluded; take_hit carriers connect as
## enemies, solid bodies without it (ground, walls) as wall contacts.
## A red debug box (child of the sweep) shows the detected bounds.
func _build_sweep() -> void:
	var skel := rig_root.get_node_or_null("Armature/GeneralSkeleton") as Skeleton3D
	if skel == null:
		push_warning("[Player] sweep skipped (no skeleton)")
		return
	_blade_attach = skel.get_node_or_null("BladeAttach") as BoneAttachment3D
	if _blade_attach == null:
		push_warning("[Player] sweep skipped (no BladeAttach — create it in player.tscn)")
		return
	var sweep_size := SWEEP_FALLBACK_SIZE
	var sweep_pos := SWEEP_FALLBACK_CENTER
	_sweep_center = SWEEP_FALLBACK_CENTER
	var weapon := _find_weapon_mesh(_blade_attach)
	if weapon != null:
		var aabb: AABB = weapon.get_aabb()
		if aabb.size.length() > 0.001:
			# Mesh-local AABB -> BladeAttach space (the mesh carries its own
			# rotation; the longest AABB axis is the blade direction).
			var rel: Transform3D = _blade_attach.global_transform.affine_inverse() * weapon.global_transform
			var sz: Vector3 = rel.basis * aabb.size
			var longest := 0
			if absf(sz.y) >= absf(sz.x) and absf(sz.y) >= absf(sz.z):
				longest = 1
			elif absf(sz.z) >= absf(sz.x) and absf(sz.z) >= absf(sz.y):
				longest = 2
			sweep_size = Vector3(absf(sz.x), absf(sz.y), absf(sz.z))
			sweep_size[longest] += SWEEP_EXTRA
			var center: Vector3 = rel * (aabb.position + aabb.size * 0.5)
			sweep_pos = center
			_sweep_center = center
			print("[Player] sweep from AABB size=%.3f x %.3f x %.3f center=(%.3f, %.3f, %.3f) blade_axis=%s" % [sweep_size.x, sweep_size.y, sweep_size.z, center.x, center.y, center.z, "XYZ"[longest]])
		else:
			push_warning("[Player] sweep using fallback size (weapon AABB empty)")
	else:
		push_warning("[Player] sweep using fallback size (no weapon mesh under BladeAttach)")
	_sweep = ShapeCast3D.new()
	_sweep.name = "Sweep"
	var box := BoxShape3D.new()
	box.size = sweep_size
	_sweep.shape = box
	_sweep.position = sweep_pos
	_sweep.target_position = Vector3.ZERO
	_sweep.enabled = false
	_sweep.add_exception(self)
	_blade_attach.add_child(_sweep)
	_sweep_debug = MeshInstance3D.new()
	_sweep_debug.name = "SweepDebug"
	var dbox := BoxMesh.new()
	dbox.size = sweep_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.0, 0.0, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	dbox.material = mat
	_sweep_debug.mesh = dbox
	_sweep.add_child(_sweep_debug)


## First MeshInstance3D under the given node (recursive — GLB instances
## nest meshes deeper). Skips the sweep itself and its debug box. Null
## when no mesh is equipped (fallback sweep size used).
func _find_weapon_mesh(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child == _sweep or child == _sweep_debug:
			continue
		if child is MeshInstance3D:
			return child as MeshInstance3D
		var found := _find_weapon_mesh(child)
		if found != null:
			return found
	return null


## Snap the sweep onto the blade for this poll: the sweep inherits the
## BladeAttach orientation (the box is already blade-aligned in attach
## space) and sits at the detected AABB center (world space); target =
## inter-frame center delta in sweep-local space (covers the motion between
## two frames — the tunneling guard). First poll of a swing primes
## _prev_mid (zero delta, overlap test only).
func _update_sweep() -> void:
	if _sweep == null or _blade_attach == null:
		return
	var ag: Transform3D = _blade_attach.global_transform
	var mid: Vector3 = ag * _sweep_center
	if not _sweep_primed:
		_prev_mid = mid
		_sweep_primed = true
	var world_delta: Vector3 = mid - _prev_mid
	_sweep.global_transform = Transform3D(ag.basis, mid)
	_sweep.target_position = ag.basis.inverse() * world_delta
	_prev_mid = mid


## Open a swing: clear the connect registry, unprime the inter-frame delta
## (first poll overlaps only), and arm the sweep.
func swing_begin() -> void:
	_swing_hits.clear()
	_sweep_primed = false
	if _sweep != null:
		_sweep.enabled = true


## Close a swing: disarm the sweep (registry clears on the next begin).
func swing_end() -> void:
	_sweep_primed = false
	if _sweep != null:
		_sweep.enabled = false


## New connects this physics tick: [{body, point, is_wall}] for bodies
## not yet touched by this swing. take_hit carriers are enemies;
## solid bodies without it (ground, walls — layer 1) report is_wall=true
## so the attack can spark or recoil off them. Empty when disarmed.
## Snaps the sweep onto the blade first so the cast covers the current
## bone pose.
func sweep_poll() -> Array:
	var out: Array = []
	if _sweep == null or not _sweep.enabled:
		return out
	_update_sweep()
	_sweep.force_shapecast_update()
	for i in _sweep.get_collision_count():
		var body := _sweep.get_collider(i) as Object
		if body == null:
			continue
		var id := body.get_instance_id()
		if _swing_hits.has(id):
			continue
		_swing_hits[id] = true
		out.append({"body": body, "point": _sweep.get_collision_point(i), "is_wall": not body.has_method("take_hit")})
	return out


## Wall contact position on the blade [0.0, 1.0]: 0.0 = guard side,
## 1.0 = blade tip. The world contact point goes to BladeAttach-local
## space and is measured on the blade axis (longest sweep axis) against
## the detected AABB center — weapon-size agnostic.
func blade_contact_ratio(contact_point: Vector3) -> float:
	if _blade_attach == null or _sweep == null or _sweep.shape == null:
		return 0.5
	var local: Vector3 = _blade_attach.global_transform.affine_inverse() * contact_point
	var sweep_sz: Vector3 = (_sweep.shape as BoxShape3D).size
	var axis := 0
	if sweep_sz.y >= sweep_sz.x and sweep_sz.y >= sweep_sz.z:
		axis = 1
	elif sweep_sz.z >= sweep_sz.x and sweep_sz.z >= sweep_sz.y:
		axis = 2
	var blade_len: float = sweep_sz[axis]
	if blade_len <= 0.001:
		return 0.5
	var half: float = blade_len * 0.5
	return clampf((local[axis] - (_sweep_center[axis] - half)) / blade_len, 0.0, 1.0)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	InputManager.set_profile(&"game")
	ToonKit.apply_to(self)
	add_to_group("player")
	_home = global_transform
	var ms := Moveset.load_object()
	for issue in Moveset.validate_moveset(ms):
		push_warning("[Moveset] %s" % issue)
	_player = RigKit.build_player(rig_root, Moveset.packs_of(ms))
	_clips = Moveset.resolve_clips(ms, _player)
	_attack_phases[&"attack_light_1"] = Moveset.phases_for(ms, &"attack_light_1")
	guard_cfg = GuardConfig.merged()
	print("[Player] guard %s %s" % [str(guard_cfg.get("equipped_shield", "?")), str(guard_cfg.get("class", {}))])
	# Sweep resolves _blade_attach and auto-sizes from the weapon mesh.
	_build_sweep()
	# Single facing: the rig never yaws (nailed once — mesh = body heading).
	rig_root.rotation.y = RIG_BASE_YAW
	print("[Player] impact %s" % str(attack_impact()))
	if _player != null:
		_play(_clips.get(&"idle", &""))
		print("[Player] clips idle=%s walk=%s run=%s fall=%s roll=%s backstep=%s attack=%s" % [_clips.get(&"idle"), _clips.get(&"walk"), _clips.get(&"run"), _clips.get(&"fall"), _clips.get(&"roll"), _clips.get(&"backstep"), _clips.get(&"attack_light_1")])
	intent.setup(self)
	var idle := StateIdle.new()
	var loco := StateLocomotion.new()
	var fall := StateFall.new()
	var roll := StateRoll.new()
	var backstep := StateBackstep.new()
	var lockon := StateLockOn.new()
	var attack := StateAttack.new()
	var hurt := StateHurt.new()
	var guard := StateGuard.new()
	for st in [idle, loco, fall, roll, backstep, lockon, attack, hurt, guard]:
		(st as PlayerState).setup(self, intent)
	machine.add_state(PlayerStateMachine.IDLE, idle)
	machine.add_state(PlayerStateMachine.LOCOMOTION, loco)
	machine.add_state(PlayerStateMachine.FALL, fall)
	machine.add_state(PlayerStateMachine.ROLL, roll)
	machine.add_state(PlayerStateMachine.BACKSTEP, backstep)
	machine.add_state(PlayerStateMachine.LOCKON, lockon)
	machine.add_state(PlayerStateMachine.ATTACK, attack)
	machine.add_state(PlayerStateMachine.HURT, hurt)
	machine.add_state(PlayerStateMachine.GUARD, guard)
	machine.start(PlayerStateMachine.IDLE)
	print("[Player] ready — profile %s, body-relative, nodess SM" % InputManager.get_profile())


func _physics_process(delta: float) -> void:
	_tick_stamina(delta)
	if not intent.guard_held():
		guard_release_needed = false
	if iframes > 0.0:
		iframes = maxf(iframes - delta, 0.0)
	if crit_iframes > 0.0:
		crit_iframes = maxf(crit_iframes - delta, 0.0)
	if _poise_wait > 0.0:
		_poise_wait -= delta
		if _poise_wait <= 0.0 and not dead:
			poise = POISE_MAX
	if _respawn_in > 0.0:
		_respawn_in -= delta
		if _respawn_in <= 0.0:
			_respawn()
	machine.step(delta)
	move_and_slide()
	_resolve_anim()


## Stamina spend gate: true + deducts when affordable, false when denied
## (no partial spend, no overdraw — edge case from features/01).
func spend_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina -= amount
	_regen_wait = REGEN_DELAY
	return true


func is_invulnerable() -> bool:
	return iframes > 0.0


## Enemy connect (P2 damage/poise + P3 S1 guard): ignored while dead or
## invulnerable (dodge i-frames). Guard raised + attacker inside the frontal
## block_arc = blocked: stamina cost (stability_mult) + chip HP, poise
## untouched; a hit exceeding the remaining stamina breaks the guard
## (extended HURT, no regen — features/17). Otherwise damage + poise; poise
## break staggers (forced HURT — the only thing that breaks a committed
## attack, souls rule, 05); HP zero kills (respawn timer, test flow).
## stamina_damage defaults to power (damage x 1.0 baseline). Returns
## {killed, staggered, blocked} (+ broken on guard break) for bookkeeping.
func take_hit(power: float, hit_poise: float, _from: Vector3, stamina_damage := -1.0) -> Dictionary:
	if dead or is_invulnerable() or crit_iframes > 0.0:
		return {"killed": false, "staggered": false, "blocked": false}
	if is_guarding() and _guard_covers(_from):
		var g: Dictionary = guard_cfg.get("class", {})
		var sdmg := (power if stamina_damage < 0.0 else stamina_damage) * float(g.get("stability_mult", 1.0))
		var chip := power * (1.0 - float(g.get("guard_absorb", 0.9)))
		hp = maxf(hp - chip, 0.0)
		if hp <= 0.0:
			dead = true
			_respawn_in = RESPAWN_DELAY
			machine.start(PlayerStateMachine.HURT)
			print("[Player] DIED through guard (chip)")
			return {"killed": true, "staggered": true, "blocked": true}
		if stamina < sdmg:
			stamina = 0.0
			hurt_time_override = GUARD_BREAK_TIME
			_regen_wait = GUARD_BREAK_NOREGEN
			guard_release_needed = true
			# Break readability (graybox, no anim): the full impact stack at
			# the chest — hitstop + shake + rumble + spark. Without it the
			# break is a silent idle-freeze (log 21/09).
			var host := impact_host()
			if host != null:
				host.impact(global_position + Vector3(0.0, 1.2, 0.0), 4, 1.5, camera)
			machine.start(PlayerStateMachine.HURT)
			print("[Player] GUARD BREAK stam 0 hp %.0f (release + re-hold to re-raise)" % hp)
			return {"killed": false, "staggered": true, "blocked": true, "broken": true}
		stamina -= sdmg
		_regen_wait = REGEN_DELAY
		print("[Player] blocked stam %.0f hp %.0f" % [stamina, hp])
		return {"killed": false, "staggered": false, "blocked": true}
	hp = maxf(hp - power, 0.0)
	poise = maxf(poise - hit_poise, 0.0)
	_poise_wait = POISE_RESET
	if hp <= 0.0:
		dead = true
		_respawn_in = RESPAWN_DELAY
		machine.start(PlayerStateMachine.HURT)
		print("[Player] DIED")
		return {"killed": true, "staggered": true, "blocked": false}
	if poise <= 0.0:
		poise = POISE_MAX
		machine.start(PlayerStateMachine.HURT)
		print("[Player] staggered hp %.0f" % hp)
		return {"killed": false, "staggered": true, "blocked": false}
	print("[Player] hit hp %.0f poise %.0f" % [hp, poise])
	return {"killed": false, "staggered": false, "blocked": false}


## Guard raised = machine in GUARD (held input or harness override).
func is_guarding() -> bool:
	return machine.state_id() == PlayerStateMachine.GUARD


## Guard entry = held (or harness override) AND no forced drop pending. A
## guard break sets guard_release_needed — the shield only re-raises after
## the hold is released once (souls rule, no chain-breaks at 0 stamina).
func guard_wanted() -> bool:
	if guard_hold_override:
		return true
	return intent.guard_held() and not guard_release_needed


## HURT duration: guard-break override (one-shot, consumed by StateHurt.exit)
## or the standard flinch time.
func hurt_duration() -> float:
	return hurt_time_override if hurt_time_override >= 0.0 else HURT_TIME


## Frontal arc check: attacker position inside block_arc/2 of the body
## forward (-Z, flattened). Same cone convention as the soldier shield.
func _guard_covers(from: Vector3) -> bool:
	var to: Vector3 = from - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return true
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	var half := deg_to_rad(float((guard_cfg.get("class", {}) as Dictionary).get("block_arc", 75.0)) * 0.5)
	return fwd.normalized().dot(to.normalized()) > cos(half)


## Test-flow respawn: restore spawn transform, pools and machine (bonfire
## flow arrives later — this only proves the death loop closes).
func _respawn() -> void:
	global_transform = _home
	velocity = Vector3.ZERO
	hp = HP_MAX
	poise = POISE_MAX
	dead = false
	_poise_wait = 0.0
	_respawn_in = -1.0
	clear_lock()
	anim_state = &"idle"
	machine.start(PlayerStateMachine.IDLE)
	print("[Player] respawned")


func _tick_stamina(delta: float) -> void:
	if _regen_wait > 0.0:
		_regen_wait -= delta
		return
	# Shield up = no regen (S1 turtle tax — log 21/09: 45/s refilled the
	# 10-stamina blocks between swings, stamina sat at 90 forever and the
	# guard never broke). Regen resumes on release (after REGEN_DELAY, set
	# by spends and blocked hits alike).
	if is_guarding():
		return
	stamina = minf(stamina + STAMINA_REGEN * delta, STAMINA_MAX)


## Lock-on (P2): tap MMB/R3 to lock the nearest lockable in the front cone,
## tap again / target gone / past break range to release. The FakeEnemy
## cylinder carries a LockMarker child shown while locked.
const LOCK_RANGE := 20.0
const LOCK_BREAK := 25.0
const LOCK_HALF_ANGLE := 60.0 # degrees, front cone at acquire
const LOCK_FACE := 10.0 # body ease toward the target (weight/sec)
const LOCK_CHEST := 1.2 # aim height on the target

var lock_target: Node3D = null


## Nearest lockable inside LOCK_RANGE and the front cone. Arms the marker.
func try_acquire_lock() -> bool:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3(0.0, 0.0, -1.0)
	var best: Node3D = null
	var best_d := LOCK_RANGE
	for n in get_tree().get_nodes_in_group("lockable"):
		if not (n is Node3D):
			continue
		var to: Vector3 = (n as Node3D).global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > LOCK_RANGE or d < 0.001:
			continue
		if rad_to_deg(acos(clampf(fwd.dot(to / d), -1.0, 1.0))) > LOCK_HALF_ANGLE:
			continue
		if d < best_d:
			best_d = d
			best = n
	if best == null:
		return false
	lock_target = best
	_set_marker(true)
	print("[Player] lock acquired %s %.1fm" % [best.name, best_d])
	return true


func clear_lock() -> void:
	if lock_target != null and is_instance_valid(lock_target):
		_set_marker(false)
		print("[Player] lock released")
	lock_target = null


## Still locked: target alive and inside break range (called every LockOn tick).
func lock_valid() -> bool:
	if lock_target == null or not is_instance_valid(lock_target):
		lock_target = null
		return false
	var to: Vector3 = lock_target.global_position - global_position
	to.y = 0.0
	if to.length() > LOCK_BREAK:
		return false
	return true


func lock_chest() -> Vector3:
	return lock_target.global_position + Vector3(0.0, LOCK_CHEST, 0.0)


func lock_distance() -> float:
	if lock_target == null or not is_instance_valid(lock_target):
		return -1.0
	var to: Vector3 = lock_target.global_position - global_position
	to.y = 0.0
	return to.length()


func _set_marker(on: bool) -> void:
	if lock_target != null and lock_target.has_node("LockMarker"):
		(lock_target.get_node("LockMarker") as Node3D).visible = on


## Lock-on tracking shared by LockOn/Roll/Backstep: ease the body toward
## the target (camera world-yaw preserved via shift_yaw) and the camera
## behind the body (track_aft). No-op without a valid lock — free motion is
## untouched. Displacement states keep their own locked _dir; only facing
## and camera track through them, so the camera never freezes mid-roll.
func track_lock_target(delta: float) -> void:
	if lock_target == null or not lock_valid():
		return
	var to: Vector3 = lock_chest() - global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		var before := rotation.y
		rotation.y = lerp_angle(before, atan2(-to.x, -to.z), minf(LOCK_FACE * delta, 1.0))
		camera.shift_yaw(rotation.y - before)
	camera.track_aft(delta)


## Snap the aft camera behind the body (Locomotion enter, old reset_camera).
func reset_camera() -> void:
	rotation.y += cam_pivot.rotation.y
	cam_pivot.rotation.y = 0.0
	camera.snap_aft()


func set_cam_yaw(enabled: bool) -> void:
	camera.yaw_enabled = enabled


## Souls turn (P2 single facing): ease the body toward a world direction,
## camera world-yaw preserved via shift_yaw (reset_camera convention).
## No-op on degenerate input. Free locomotion + free rolls own the heading
## through this; locked states use track_lock_target instead.
func turn_body_to(dir: Vector3, delta: float, rate := FREE_FACE) -> void:
	var f := Vector3(dir.x, 0.0, dir.z)
	if f.length_squared() < 0.0001:
		return
	var before := rotation.y
	rotation.y = lerp_angle(before, atan2(-f.x, -f.z), minf(rate * delta, 1.0))
	camera.shift_yaw(rotation.y - before)


func _resolve_anim() -> void:
	# Attack drives its own marker sections (play_phase) — the auto-resolve
	# stands down or it would replay the whole clip over the sections.
	if anim_manual:
		return
	_play(str(_clips.get(anim_state, &"")))
	if anim_seek >= 0.0 and _player != null:
		_player.seek(anim_seek, true)
		anim_seek = -1.0


func _play(anim: StringName) -> void:
	if anim != &"" and anim != _anim_cur and _player != null:
		_player.play(anim, ANIM_BLEND)
		if _anim_cur != &"":
			print("[Player] anim %s" % anim)
		_anim_cur = anim


## Manual section playback for StateAttack: plays one marker section at its
## data speed. Sets anim_manual (auto-resolve off) — the state clears it.
func play_phase(clip: StringName, sec_from: StringName, sec_to: StringName, speed: float) -> void:
	if _player == null or clip == &"":
		return
	anim_manual = true
	_player.play_section_with_markers(clip, sec_from, sec_to, ANIM_BLEND, speed)
	_anim_cur = str(clip)


## Native reverse playback for the StateAttack blade rebound: replays the
## clip backwards from from_pos to the clip start at the data speed. Uses
## play_section_backwards (verified headless: play_section+from_end stops
## after one tick in 4.7.2, negative custom_speed never starts — only the
## dedicated backwards method and negative speed_scale actually rewind).
## The section stops by itself at 0 (clips are LOOP_NONE); the state
## watches is_playing(). Sets anim_manual (cleared via play_slot_blend /
## exit, which also restores speed_scale to 1.0).
func play_reverse(clip: StringName, from_pos: float, speed: float) -> void:
	if _player == null or clip == &"":
		return
	anim_manual = true
	_player.play_section_backwards(clip, 0.0, maxf(from_pos, 0.01), ANIM_BLEND)
	_player.speed_scale = maxf(speed, 0.5)
	_anim_cur = str(clip)


## Direct AnimationPlayer access for states that drive playback themselves
## (blade rebound reversal) — null before the rig is built.
func anim_player() -> AnimationPlayer:
	return _player


## Playback speed_scale override (states own the restore — exit() resets
## to 1.0).
func set_anim_speed(speed: float) -> void:
	if _player != null:
		_player.speed_scale = speed


## Idle-clip crossfade with a custom blend (blade rebound recovery): hands
## playback back to the auto-resolve and starts the named slot clip over
## the given blend time. No-op when the slot has no resolved clip.
func play_slot_blend(slot: StringName, blend: float) -> void:
	var clip := StringName(str(_clips.get(slot, &"")))
	if _player == null or clip == &"":
		return
	anim_manual = false
	anim_state = slot
	_player.play(clip, maxf(blend, 0.01))
	_anim_cur = str(clip)


## End time of the currently playing section (0 when idle).
func phase_end() -> float:
	if _player == null:
		return 0.0
	return _player.get_section_end_time()


## Position inside the current section (-1 when nothing plays = done).
func anim_pos() -> float:
	if _player == null or not _player.is_playing():
		return -1.0
	return _player.current_animation_position


## Marker time on a rig clip (0 when missing — lets states detect degenerate
## sections without calling the native section player).
func marker_time(clip: StringName, marker: StringName) -> float:
	if _player == null:
		return 0.0
	var anim: Animation = _player.get_animation(clip)
	if anim == null or not anim.has_marker(marker):
		return 0.0
	return anim.get_marker_time(marker)


func _process(_delta: float) -> void:
	if state_label != null:
		var planar := Vector2(velocity.x, velocity.z).length()
		state_label.text = "%s · speed %.1f · floor %s · anim %s · stam %.0f · hp %.0f · poise %.0f%s%s\nprofile %s · raw %s" % [
			machine.state_name(),
			planar,
			"yes" if is_on_floor() else "NO",
			_anim_cur,
			stamina,
			hp,
			poise,
			" INVULN" if is_invulnerable() else "",
			" LOCK %.1fm" % lock_distance() if lock_target != null else "",
			InputManager.get_profile(),
			intent.move_raw(),
		]
