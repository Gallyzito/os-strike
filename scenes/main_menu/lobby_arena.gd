class_name LobbyArena
extends StaticBody3D
## Plataforma do lobby onde o jogador está: chão com grelha e rebordos néon.
## O chão tem colisão para as balas fazerem faíscas.

const GRID_SHADER := preload("res://shaders/grid.gdshader")
const FLOOR_LAYER := 1

## Tamanho da plataforma (x, z) e o centro dela.
@export var size := Vector2(14.0, 12.0)
@export var center := Vector3(0.0, -1.0, 4.5)


func _ready() -> void:
	collision_layer = FLOOR_LAYER
	collision_mask = 0
	_add_box(center + Vector3(0, -0.1, 0), Vector3(size.x, 0.2, size.y))
	_build_floor_visual()
	_build_edges()


func _add_box(pos: Vector3, extents: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = extents
	shape.shape = box
	shape.position = pos - position
	add_child(shape)


func _build_floor_visual() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var mat := ShaderMaterial.new()
	mat.shader = GRID_SHADER
	mat.set_shader_parameter("base_color", Color(0.03, 0.033, 0.042))
	mat.set_shader_parameter("line_color", Color(0.55, 0.36, 0.12))
	mat.set_shader_parameter("cells", size)
	mat.set_shader_parameter("fade_near", 3.0)
	mat.set_shader_parameter("fade_far", 26.0)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = mesh
	floor_mesh.material_override = mat
	floor_mesh.position = center + Vector3(0, 0.002, 0)
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mesh)


## Rebordos néon: laranja à frente (virado para os alvos), azul nos outros lados.
func _build_edges() -> void:
	var half := Vector3(size.x, 0, size.y) * 0.5
	var y := center.y + 0.02
	var edges := [
		[Vector3(center.x, y, center.z - half.z), Vector3(size.x, 0.04, 0.05), UITheme.T_ORANGE],
		[Vector3(center.x, y, center.z + half.z), Vector3(size.x, 0.04, 0.05), UITheme.CT_BLUE],
		[Vector3(center.x - half.x, y, center.z), Vector3(0.05, 0.04, size.y), UITheme.CT_BLUE],
		[Vector3(center.x + half.x, y, center.z), Vector3(0.05, 0.04, size.y), UITheme.CT_BLUE],
	]
	for e in edges:
		var box := BoxMesh.new()
		box.size = e[1]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.BLACK
		mat.emission_enabled = true
		mat.emission = e[2]
		mat.emission_energy_multiplier = 2.5
		box.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.position = e[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

