class_name SoldierEnemy
extends CharacterBody3D

## P2 first enemy archetype (roadmap l.78, features/05): hollow soldier,
## sword + shield, capsule placeholder (real shared rig arrives P4).
## Behavior = the single hardcoded pattern "soldier_melee_v1", fully driven
## by data/enemies/soldier_melee_v1.json via EnemyConfig (stats, sliders,
## senses, timings) — the behavior_pattern_id hook lets P9 resolve the same
## config shape to data-driven patterns without a rewrite.
## State machine: IDLE → CHASE → WINDUP → STRIKE → RECOVER (+ FLINCH on
## poise break, DEAD with test reset). take_hit honors the FakeEnemy
## contract {killed, blocked} so the player sweep/rebound stack works
## unchanged; the shield blocks frontal connects (shield_half_angle).
## Telegraph: emissive ramp grey → red over the windup (readability first,
## 05/16). Lock-on: "lockable" group + LockMarker child (player convention).

const GRAVITY := 22.0
## Incoming poise damage per damage point (player weapons carry no hit_poise
## field yet — bounded weapon payloads arrive with 04/17; factor noted here).
const POISE_FACTOR := 1.5
const RESET_DELAY := 4.0
const STRIKE_REACH_PAD := 1.0
const HOME_ARRIVE := 0.5
## Facing stagger (behavior, not guard): a landed hit slows the soldier's
## turn briefly — it "feels" the blow, so a flank double-tap is feasible
## (1st flank → slow turn → 2nd flank → FLINCH).
const TURN_SUPPRESS_TIME := 0.5
const TURN_SUPPRESS_MULT := 0.3
## Backstab rear cone half-angle (features/17: ±30° off the back axis).
const BACKSTAB_HALF_ANGLE := 30.0

enum { IDLE, CHASE, WINDUP, STRIKE, RECOVER, FLINCH, DEAD }
const NAMES := {IDLE: "IDLE", CHASE: "CHASE", WINDUP: "WINDUP", STRIKE: "STRIKE", RECOVER: "RECOVER", FLINCH: "FLINCH", DEAD: "DEAD"}

@export var enemy_id := "soldier_melee_v1"

var cfg := {}
var state := IDLE
var hp := 60.0
var poise := 40.0
var hits := 0
var blocked_hits := 0

var _t := 0.0
var _cooldown := 0.0
var _poise_wait := 0.0
var _turn_suppress := 0.0
var _reset_in := -1.0
var _struck := false
var _home := Transform3D.IDENTITY
var _player: PlayerController = null
var _mesh: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _label: Label = null


func _ready() -> void:
	# Same layer convention as FakeEnemy: layers 1+2 so the player sweep
	# (mask 1) connects and the body still collides with the world (mask 1).
	collision_layer = 3
	collision_mask = 1
	add_to_group("lockable")
	cfg = EnemyConfig.merged(enemy_id)
	hp = float((cfg.get("stats", {}) as Dictionary).get("hp", 60.0))
	poise = float((cfg.get("stats", {}) as Dictionary).get("poise", 40.0))
	_home = global_transform
	_build_scaffold()
	_find_player()
	_label = get_node_or_null("../HUD/EnemyAI") as Label
	_update_label()
	print("[EnemyAI] %s ready hp %.0f pattern %s" % [enemy_id, hp, str(cfg.get("behavior_pattern_id", "?"))])


func _physics_process(delta: float) -> void:
	if _player != null and not is_instance_valid(_player):
		_player = null
	if _player == null:
		_find_player()
	_tick(delta)
	move_and_slide()
	_update_label()


## Player connect: damage + poise, FakeEnemy contract {killed, blocked}
## (+ crit on backstab). Resolution order: backstab first (rear arc +
## eligible state + flag — bypasses the shield, which only covers the
## front), then the shield block, then the normal hit.
## Backstab (P3 S2, features/17): attacker inside the rear cone (±30° off
## the back axis) while the soldier is neutral (IDLE/CHASE) or committed
## (WINDUP/STRIKE/RECOVER — the state IS the ~0.6 s window) and the config
## flag allows it → immediate critical: damage x crit_mult, poise damage
## scaled the same way (the mult IS the "high poise damage"). FLINCH/DEAD
## are not eligible (no chain-crit on a stagger). Ignored while DEAD.
## Shielded + attacker inside the frontal shield cone + guard up = blocked
## (no damage, no poise damage — the attacker's blade rebounds, 01). Guard
## is up in IDLE/CHASE/WINDUP only: once the swing is committed
## (STRIKE/RECOVER) or the soldier flinches, the shield is down — readable
## souls rule, flank-or-punish. Poise break = FLINCH, which cancels an
## in-flight windup (05). Ignored while DEAD.
func take_hit(power: float, from: Vector3, crit_mult := 1.0) -> Dictionary:
	if state == DEAD:
		return {"killed": false, "blocked": false}
	var to_you: Vector3 = from - global_position
	to_you.y = 0.0
	if crit_mult > 1.0 and to_you.length_squared() > 0.0001 and _backstab_open(to_you):
		var dmg := power * crit_mult
		hp = maxf(hp - dmg, 0.0)
		poise = maxf(poise - dmg * POISE_FACTOR, 0.0)
		_poise_wait = float((cfg.get("stats", {}) as Dictionary).get("poise_reset_time", 3.5))
		_turn_suppress = TURN_SUPPRESS_TIME
		hits += 1
		_flash(Color(1.0, 0.8, 0.2))
		print("[EnemyAI] BACKSTAB x%.1f dmg %.0f hp %.0f poise %.0f" % [crit_mult, dmg, hp, poise])
		if hp <= 0.0:
			_die()
			return {"killed": true, "blocked": false, "crit": true}
		if poise <= 0.0:
			poise = float((cfg.get("stats", {}) as Dictionary).get("poise", 40.0))
			_enter(FLINCH)
			print("[EnemyAI] flinched (%d)" % hits)
		_update_label()
		return {"killed": false, "blocked": false, "crit": true}
	if _would_block(to_you):
		blocked_hits += 1
		_flash(Color(0.6, 0.7, 1.0))
		print("[EnemyAI] blocked %d" % blocked_hits)
		_update_label()
		return {"killed": false, "blocked": true}
	hp = maxf(hp - power, 0.0)
	poise = maxf(poise - power * POISE_FACTOR, 0.0)
	_poise_wait = float((cfg.get("stats", {}) as Dictionary).get("poise_reset_time", 3.5))
	_turn_suppress = TURN_SUPPRESS_TIME
	hits += 1
	_flash(Color(1, 1, 1))
	var away: Vector3 = global_position - from
	away.y = 0.0
	if away.length_squared() > 0.0001:
		global_position += away.normalized() * 0.12
	if hp <= 0.0:
		_die()
		return {"killed": true, "blocked": false}
	if poise <= 0.0:
		poise = float((cfg.get("stats", {}) as Dictionary).get("poise", 40.0))
		_enter(FLINCH)
		print("[EnemyAI] flinched (%d)" % hits)
	else:
		print("[EnemyAI] hit %d hp %.0f poise %.0f" % [hits, hp, poise])
	_update_label()
	return {"killed": false, "blocked": false}


## Blade-shove connect (P3 S3, features/17): the heavies' guard-break
## answer. If the shield would block this connect (frontal + guard up),
## the shove cracks it: small chip damage + guard_break as flat poise
## damage (a 70-break vs 30 poise always flinches — one shove cracks),
## never blocked, never rebounds. Vs a down guard / flanked soldier the
## shove is near-useless: small damage + modest poise only (plan 21/09).
## Returns {killed, blocked:false, cracked}. Ignored while DEAD.
func take_shove(power: float, guard_break: float, from: Vector3) -> Dictionary:
	if state == DEAD:
		return {"killed": false, "blocked": false, "cracked": false}
	var to_you: Vector3 = from - global_position
	to_you.y = 0.0
	if _would_block(to_you):
		hp = maxf(hp - power, 0.0)
		poise = maxf(poise - guard_break, 0.0)
		_poise_wait = float((cfg.get("stats", {}) as Dictionary).get("poise_reset_time", 3.5))
		_turn_suppress = TURN_SUPPRESS_TIME
		hits += 1
		_flash(Color(1.0, 0.6, 0.1))
		print("[EnemyAI] SHOVE CRACK dmg %.0f hp %.0f poise %.0f" % [power, hp, poise])
		if hp <= 0.0:
			_die()
			return {"killed": true, "blocked": false, "cracked": true}
		poise = float((cfg.get("stats", {}) as Dictionary).get("poise", 40.0))
		_enter(FLINCH)
		print("[EnemyAI] flinched (%d)" % hits)
		_update_label()
		return {"killed": false, "blocked": false, "cracked": true}
	hp = maxf(hp - power, 0.0)
	poise = maxf(poise - power * POISE_FACTOR, 0.0)
	_poise_wait = float((cfg.get("stats", {}) as Dictionary).get("poise_reset_time", 3.5))
	hits += 1
	_flash(Color(1, 1, 1))
	if hp <= 0.0:
		_die()
		return {"killed": true, "blocked": false, "cracked": false}
	if poise <= 0.0:
		poise = float((cfg.get("stats", {}) as Dictionary).get("poise", 40.0))
		_enter(FLINCH)
		print("[EnemyAI] flinched (%d)" % hits)
	else:
		print("[EnemyAI] shoved %d hp %.0f poise %.0f" % [hits, hp, poise])
	_update_label()
	return {"killed": false, "blocked": false, "cracked": false}


## Plunging-attack connect (P3 S4, features/17): a vertical drop attack
## bypasses the shield (like a backstab — the slab only covers the front),
## deals the drop-scaled capped damage + planar knockback, never blocked,
## never rebounds. Returns {killed, blocked:false, plunged}. Ignored while
## DEAD. Melee only (the player sweep is the sole caller — no bow V1).
func take_plunge(power: float, knockback: float, from: Vector3) -> Dictionary:
	if state == DEAD:
		return {"killed": false, "blocked": false, "plunged": false}
	hp = maxf(hp - power, 0.0)
	poise = maxf(poise - power * POISE_FACTOR, 0.0)
	_poise_wait = float((cfg.get("stats", {}) as Dictionary).get("poise_reset_time", 3.5))
	_turn_suppress = TURN_SUPPRESS_TIME
	hits += 1
	_flash(Color(1.0, 0.75, 0.3))
	var away: Vector3 = global_position - from
	away.y = 0.0
	if away.length_squared() > 0.0001:
		global_position += away.normalized() * maxf(knockback, 0.0)
	print("[EnemyAI] PLUNGE dmg %.0f hp %.0f poise %.0f" % [power, hp, poise])
	if hp <= 0.0:
		_die()
		return {"killed": true, "blocked": false, "plunged": true}
	if poise <= 0.0:
		poise = float((cfg.get("stats", {}) as Dictionary).get("poise", 40.0))
		_enter(FLINCH)
		print("[EnemyAI] flinched (%d)" % hits)
	else:
		print("[EnemyAI] plunged %d hp %.0f poise %.0f" % [hits, hp, poise])
	_update_label()
	return {"killed": false, "blocked": false, "plunged": true}


func _is_shielded() -> bool:
	return bool((cfg.get("attack", {}) as Dictionary).get("shielded", false))


## Shared block predicate (shield + guard up + inside the frontal cone):
## take_hit blocks on it, take_shove cracks on it.
func _would_block(to_you: Vector3) -> bool:
	var guard_up := state == IDLE or state == CHASE or state == WINDUP
	if not (_is_shielded() and guard_up and to_you.length_squared() > 0.0001):
		return false
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	var half := deg_to_rad(float((cfg.get("attack", {}) as Dictionary).get("shield_half_angle", 60.0)))
	return fwd.normalized().dot(to_you.normalized()) > cos(half)


## Backstab eligibility (P3 S2): config flag + neutral/committed state +
## attacker inside the ±30° rear cone. to_you = attacker - self, planar.
func _backstab_open(to_you: Vector3) -> bool:
	if not bool(cfg.get("backstab_vulnerable", true)):
		return false
	if not (state == IDLE or state == CHASE or state == WINDUP or state == STRIKE or state == RECOVER):
		return false
	var back := global_transform.basis.z
	back.y = 0.0
	if back.length_squared() < 0.0001:
		return false
	return back.normalized().dot(to_you.normalized()) > cos(deg_to_rad(BACKSTAB_HALF_ANGLE))


func _enter(next: int) -> void:
	state = next
	_t = 0.0
	if next == STRIKE:
		_struck = false
		_set_glow(Color(1.0, 0.25, 0.1), 2.5)
	elif next == WINDUP:
		pass # telegraph ramps in _tick
	elif next == DEAD:
		pass
	print("[EnemyAI] -> %s" % str(NAMES.get(state, "?")))


func _tick(delta: float) -> void:
	if velocity.y < 0.0 and is_on_floor():
		velocity.y = -0.5
	elif not is_on_floor():
		velocity.y -= GRAVITY * delta
	if _poise_wait > 0.0:
		_poise_wait -= delta
		if _poise_wait <= 0.0 and state != DEAD:
			poise = float((cfg.get("stats", {}) as Dictionary).get("poise", 40.0))
	if _cooldown > 0.0:
		_cooldown -= delta
	if _turn_suppress > 0.0:
		_turn_suppress -= delta
	match state:
		IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
			_set_glow(Color(0.35, 0.4, 0.5), 0.0)
			if _aggro(_sense("activation_radius")):
				_enter(CHASE)
		CHASE:
			_set_glow(Color(0.45, 0.5, 0.6), 0.3)
			if not _aggro(_sense("deaggro_radius")):
				_walk_home(delta)
			elif _player_dist() <= _attack("range") and _cooldown <= 0.0:
				velocity.x = 0.0
				velocity.z = 0.0
				_enter(WINDUP)
			else:
				_chase(delta)
		WINDUP:
			velocity.x = 0.0
			velocity.z = 0.0
			# Slow tracking (0.6x): the telegraph is circleable — strafe
			# around the red windup, punish the flank (souls skill move).
			_face_player(delta, 0.6)
			# Telegraph ramp: grey steel -> hot red over the windup.
			var windup := _attack("windup_time") * _slider("telegraph_scale")
			var k := clampf(_t / maxf(windup, 0.05), 0.0, 1.0)
			_set_glow(Color(0.45 + 0.55 * k, 0.5 - 0.4 * k, 0.6 - 0.5 * k), 0.3 + 2.2 * k)
			_t += delta
			if _t >= windup:
				_enter(STRIKE)
		STRIKE:
			_face_player(delta, 0.5)
			if not _struck:
				_struck = true
				_connect()
			# Committed lunge, decays over the strike.
			var lunge := _attack("range") * 1.5 * maxf(1.0 - _t / maxf(_attack("strike_time"), 0.05), 0.0)
			var fwd2 := -global_transform.basis.z
			fwd2.y = 0.0
			velocity.x = fwd2.normalized().x * lunge if fwd2.length_squared() > 0.0001 else 0.0
			velocity.z = fwd2.normalized().z * lunge if fwd2.length_squared() > 0.0001 else 0.0
			_t += delta
			if _t >= _attack("strike_time"):
				_enter(RECOVER)
		RECOVER:
			velocity.x = 0.0
			velocity.z = 0.0
			_set_glow(Color(0.6, 0.45, 0.3), 0.3)
			_t += delta
			if _t >= _attack("recover_time") / maxf(_slider("cadence"), 0.1):
				# Aggression gates the immediate re-attack: low aggression
				# enforces a spacing cooldown before the next windup. Cycle
				# stays under the player POISE_RESET window (sustained
				# pressure staggers — P2 readability, not stunlock).
				_cooldown = _attack("recover_time") * (1.5 - _slider("aggression"))
				_enter(CHASE)
		FLINCH:
			velocity.x = 0.0
			velocity.z = 0.0
			_t += delta
			if _t >= _attack("flinch_time"):
				_enter(CHASE)
		DEAD:
			velocity.x = 0.0
			velocity.z = 0.0
			if _reset_in > 0.0:
				_reset_in -= delta
				if _reset_in <= 0.0:
					_reset()


func _connect() -> void:
	if _player == null or _player.dead:
		print("[EnemyAI] strike whiffed (no target)")
		return
	if _player_dist() > _attack("range") + STRIKE_REACH_PAD:
		print("[EnemyAI] strike whiffed (%.1fm)" % _player_dist())
		return
	var res: Dictionary = _player.take_hit(float((cfg.get("stats", {}) as Dictionary).get("damage", 12.0)), float((cfg.get("stats", {}) as Dictionary).get("hit_poise", 25.0)), global_position, float((cfg.get("stats", {}) as Dictionary).get("hit_stamina_damage", 30.0)))
	print("[EnemyAI] strike connected killed=%s staggered=%s blocked=%s" % [str(res.get("killed", false)), str(res.get("staggered", false)), str(res.get("blocked", false))])


func _die() -> void:
	_enter(DEAD)
	_reset_in = RESET_DELAY
	(collision_shape() as CollisionShape3D).set_deferred("disabled", true)
	_set_marker(false)
	_set_glow(Color(0.15, 0.12, 0.12), 0.0)
	rotation.x = -1.45
	print("[EnemyAI] KILLED after %d hits (%d blocked)" % [hits, blocked_hits])


func _reset() -> void:
	global_transform = _home
	rotation.x = 0.0
	velocity = Vector3.ZERO
	hp = float((cfg.get("stats", {}) as Dictionary).get("hp", 60.0))
	poise = float((cfg.get("stats", {}) as Dictionary).get("poise", 40.0))
	hits = 0
	blocked_hits = 0
	_cooldown = 0.0
	_poise_wait = 0.0
	_reset_in = -1.0
	(collision_shape() as CollisionShape3D).set_deferred("disabled", false)
	state = IDLE
	_t = 0.0
	_set_glow(Color(0.35, 0.4, 0.5), 0.0)
	print("[EnemyAI] reset")


func _chase(delta: float) -> void:
	var to: Vector3 = _player.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	_face_player(delta, 1.0)
	# Hurry from afar (fewer free whiff-escapes), walk once in range.
	var sp := _loco("walk_speed")
	if to.length() > _loco("hurry_range"):
		sp = _loco("hurry_speed")
	velocity.x = to.normalized().x * sp
	velocity.z = to.normalized().z * sp


func _walk_home(delta: float) -> void:
	var to: Vector3 = _home.origin - global_position
	to.y = 0.0
	if to.length() <= HOME_ARRIVE:
		velocity.x = 0.0
		velocity.z = 0.0
		_enter(IDLE)
		return
	_face_point(_home.origin, delta, 1.0)
	velocity.x = to.normalized().x * _loco("walk_speed")
	velocity.z = to.normalized().z * _loco("walk_speed")


func _face_player(delta: float, mult: float) -> void:
	if _player == null:
		return
	_face_point(_player.global_position, delta, mult)


func _face_point(p: Vector3, delta: float, mult: float) -> void:
	var to: Vector3 = p - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	if _turn_suppress > 0.0:
		mult *= TURN_SUPPRESS_MULT
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(_loco("turn_rate") * mult * delta, 1.0))


func _aggro(radius: float) -> bool:
	if _player == null or _player.dead:
		return false
	return _player_dist() <= radius


func _player_dist() -> float:
	if _player == null:
		return 999.0
	var to: Vector3 = _player.global_position - global_position
	to.y = 0.0
	return to.length()


func _find_player() -> void:
	var ps := get_tree().get_nodes_in_group("player")
	if not ps.is_empty() and ps[0] is PlayerController:
		_player = ps[0] as PlayerController


func _sense(key: String) -> float:
	return float((cfg.get("senses", {}) as Dictionary).get(key, 12.0))


func _slider(key: String) -> float:
	return float((cfg.get("sliders", {}) as Dictionary).get(key, 1.0))


func _loco(key: String) -> float:
	return float((cfg.get("locomotion", {}) as Dictionary).get(key, 2.0))


func _attack(key: String) -> float:
	return float((cfg.get("attack", {}) as Dictionary).get(key, 1.0))


func _build_scaffold() -> void:
	# Procedural placeholder scaffold (P4 replaces the mesh with the shared
	# rig): named nodes so the human sees them in the remote scene tree.
	var body := CollisionShape3D.new()
	body.name = "Body"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	body.shape = cap
	body.position = Vector3(0.0, 0.9, 0.0)
	add_child(body)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.7
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.35, 0.4, 0.5)
	cm.material = _mat
	_mesh.mesh = cm
	_mesh.position = Vector3(0.0, 0.9, 0.0)
	add_child(_mesh)
	# Shield slab, front-left: the visual anchor of the blocked cone.
	var shield := MeshInstance3D.new()
	shield.name = "ShieldMesh"
	var sb := BoxMesh.new()
	sb.size = Vector3(0.5, 0.9, 0.08)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.45, 0.42, 0.35)
	sb.material = smat
	shield.mesh = sb
	shield.position = Vector3(-0.45, 1.0, -0.25)
	add_child(shield)
	var marker := MeshInstance3D.new()
	marker.name = "LockMarker"
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	var mmat := StandardMaterial3D.new()
	mmat.emission_enabled = true
	mmat.emission = Color(1.0, 0.85, 0.2)
	mmat.emission_energy_multiplier = 2.0
	sm.material = mmat
	marker.mesh = sm
	marker.position = Vector3(0.0, 2.1, 0.0)
	marker.visible = false
	add_child(marker)


func collision_shape() -> Node:
	return get_node_or_null("Body")


func _set_marker(on: bool) -> void:
	var m := get_node_or_null("LockMarker") as MeshInstance3D
	if m != null:
		m.visible = on


func _set_glow(color: Color, energy: float) -> void:
	if _mat == null:
		return
	_mat.albedo_color = color
	_mat.emission_enabled = energy > 0.0
	_mat.emission = color
	_mat.emission_energy_multiplier = energy


func _flash(color: Color) -> void:
	# One-frame white/blue pop over the state glow (the glow is reapplied
	# next tick by the state — same flash-then-state pattern as FakeEnemy).
	_set_glow(color, 3.0)


func _update_label() -> void:
	if _label != null:
		_label.text = "soldier %s hp %.0f poise %.0f hits %d%s" % [
			str(NAMES.get(state, "?")), hp, poise, hits,
			" BLOCK+%d" % blocked_hits if blocked_hits > 0 else "",
		]
