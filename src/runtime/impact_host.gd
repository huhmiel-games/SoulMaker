class_name ImpactHost
extends Node3D

## Impact-chain host (P2, test scenes): owns the spark pool and fires the
## connect stack — hitstop (ImpactKit) + camera trauma + gamepad rumble +
## spark burst at the contact point. Lives in group "impact"; the player
## finds it there (no scene-structure coupling). No audio — ADR-014.

const POOL_SIZE := 3
const SPARK_COUNT := 18
const SPARK_LIFETIME := 0.35

var _pool: Array[GPUParticles3D] = []
var _next := 0


func _ready() -> void:
	add_to_group(&"impact")
	for i in POOL_SIZE:
		_pool.append(_build_spark("Spark%d" % i))
	print("[Impact] pool %d sparks ready" % POOL_SIZE)


## Full connect stack for one impact frame. Camera stays alive by contract
## (unscaled delta); rumble is an unconditional output call (no-op without
## a pad — parity-safe, no device branch).
func impact(point: Vector3, hitstop_frames: int, shake_scale: float, camera: PlayerCamera) -> void:
	ImpactKit.hitstop(get_tree(), hitstop_frames)
	if camera != null:
		camera.add_trauma(0.4 * shake_scale)
	InputManager.rumble(0.25, 0.6, 0.12)
	_fire(point)


func _fire(point: Vector3) -> void:
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.global_position = point
	p.restart()


## Spark-only follow-up for secondary connects on the same swing (the full
## stack fired once already — spec strongest-once rule).
func spark_at(point: Vector3) -> void:
	_fire(point)


## One-shot radial spark burst, fully code-built (no .tscn wrestling):
## sphere emission, hot-white color, gravity pull, world-space (the burst
## stays where the blade connected).
func _build_spark(spark_name: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = spark_name
	p.amount = SPARK_COUNT
	p.lifetime = SPARK_LIFETIME
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.06
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 7.0
	mat.gravity = Vector3(0, -12, 0)
	mat.damping_min = 1.0
	mat.damping_max = 2.0
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	mat.color = Color(1.0, 0.9, 0.6)
	p.process_material = mat
	var dot := SphereMesh.new()
	dot.radius = 0.025
	dot.height = 0.05
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.95, 0.75)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.85, 0.5)
	glow.emission_energy_multiplier = 3.0
	dot.material = glow
	p.draw_pass_1 = dot
	add_child(p)
	p.emitting = false
	return p
