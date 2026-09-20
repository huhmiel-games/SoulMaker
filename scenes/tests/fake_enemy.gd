class_name FakeEnemy
extends StaticBody3D

## Hitting post for the P2 impact chain (test scenes only): HP pool, white
## flash + micro-knockback per connect, DOWN fall at zero with auto reset.
## Placeholder for the enemy archetype (05) — real poise/flinch/stagger
## arrive with it; this dummy only proves the player's connect stack reads.

const MAX_HP := 30.0
const KNOCKBACK := 0.22
const RESET_DELAY := 2.0
const FLASH_TIME := 0.09
const TIP_ANGLE := -1.45
const TIP_RATE := 8.0

var hp := MAX_HP
var hits := 0
var down := false

var _home := Transform3D.IDENTITY
var _mesh: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _base_emission := Color.BLACK
var _base_energy := 1.0
var _flash := 0.0
var _reset_in := -1.0
var _label: Label = null


func _ready() -> void:
	_home = global_transform
	_mesh = get_node_or_null("EnemyMesh") as MeshInstance3D
	if _mesh != null and _mesh.get_surface_override_material(0) == null:
		# Duplicate the effective material: the .tscn sub_resource is set
		# on the PrimitiveMesh and must not flash anything else.
		var src_mat: Material = null
		if _mesh.mesh is PrimitiveMesh:
			src_mat = (_mesh.mesh as PrimitiveMesh).material
		if src_mat is StandardMaterial3D:
			_mat = (src_mat as StandardMaterial3D).duplicate()
		else:
			_mat = StandardMaterial3D.new()
			_mat.albedo_color = Color(0.7, 0.15, 0.15)
		_mesh.set_surface_override_material(0, _mat)
	if _mat != null:
		_base_emission = _mat.emission
		_base_energy = _mat.emission_energy_multiplier
	_label = get_node_or_null("../HUD/Enemy") as Label
	_update_label()


## Player connect: damage + reaction. Ignored while DOWN (no chain spam on
## a fallen dummy). Returns true on the killing blow (overlay text).
func take_hit(power: float, from: Vector3) -> bool:
	if down:
		return false
	hp = maxf(hp - power, 0.0)
	hits += 1
	_flash = FLASH_TIME
	var away: Vector3 = global_position - from
	away.y = 0.0
	if away.length_squared() > 0.0001:
		global_position += away.normalized() * KNOCKBACK
	if hp <= 0.0:
		down = true
		_reset_in = RESET_DELAY
		print("[Enemy] DOWN after %d hits" % hits)
	else:
		print("[Enemy] hit %d hp %.0f" % [hits, hp])
	_update_label()
	return down


func _process(delta: float) -> void:
	# Real-time timers (hitstop must not stretch the flash or the reset).
	var raw := delta / maxf(Engine.time_scale, 0.001)
	if _flash > 0.0:
		_flash = maxf(_flash - raw, 0.0)
		_set_flash(_flash > 0.0)
	if down:
		rotation.x = lerpf(rotation.x, TIP_ANGLE, minf(TIP_RATE * raw, 1.0))
		if _reset_in > 0.0:
			_reset_in -= raw
			if _reset_in <= 0.0:
				_reset()


func _set_flash(on: bool) -> void:
	if _mat == null:
		return
	if on:
		_mat.emission_enabled = true
		_mat.emission = Color(1, 1, 1)
		_mat.emission_energy_multiplier = 3.0
	else:
		_mat.emission = _base_emission
		_mat.emission_energy_multiplier = _base_energy
		_mat.emission_enabled = _base_energy > 0.0


func _reset() -> void:
	global_transform = _home
	rotation.x = 0.0
	hp = MAX_HP
	hits = 0
	down = false
	_reset_in = -1.0
	_set_flash(false)
	_update_label()
	print("[Enemy] reset")


func _update_label() -> void:
	if _label != null:
		_label.text = "enemy hp %.0f%s" % [hp, " DOWN" if down else ""]
