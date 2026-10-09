class_name BulletFX
extends Node3D
## Efeitos das balas: tracer da boca do cano até ao impacto e faíscas no
## ponto de impacto. Usa um conjunto fixo de emissores de partículas, copiados
## do filho "Sparks" (que define o aspeto das faíscas).

const SPARK_POOL := 8
const TRACER_TIME := 0.06
const TRACER_WIDTH := 0.01

var _sparks: Array[GPUParticles3D] = []
var _next_spark := 0
var _tracer_mesh := BoxMesh.new()


func _ready() -> void:
	var template: GPUParticles3D = $Sparks
	_sparks.append(template)
	for i in SPARK_POOL - 1:
		var copy := template.duplicate() as GPUParticles3D
		add_child(copy)
		_sparks.append(copy)


func spawn_tracer(from: Vector3, to: Vector3) -> void:
	var dir := to - from
	if dir.length() < 0.05:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.85, 0.55)

	var tracer := MeshInstance3D.new()
	tracer.mesh = _tracer_mesh
	tracer.material_override = mat
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer.top_level = true
	add_child(tracer)
	var up := Vector3.UP if absf(dir.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var look := Basis.looking_at(dir.normalized(), up)
	tracer.global_transform = Transform3D(
		Basis(look.x * TRACER_WIDTH, look.y * TRACER_WIDTH, look.z * dir.length()), from + dir * 0.5)

	var tween := tracer.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, TRACER_TIME)
	tween.tween_callback(tracer.queue_free)


func spawn_impact(point: Vector3, normal: Vector3, strength := 1.0) -> void:
	var sparks := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	sparks.global_position = point + normal * 0.01
	# As partículas saem na direção -Z local; apontamos -Z para fora da superfície.
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	sparks.look_at(sparks.global_position + normal, up)
	sparks.amount_ratio = 0.3 + strength * 0.7
	sparks.restart()
