class_name FPSPlayer
extends Node3D
## Jogador em primeira pessoa (lobby e jogo). Fica parado num ponto fixo: só
## olha à volta com o rato e dispara a arma (clique esquerdo; a AK é automática,
## as pistolas um tiro por clique). Troca de arma com 1/2/3, Q ou a roda do rato.
## A sensibilidade usa a mesma fórmula do CS (graus = counts × sens × 0.022) e
## o FOV vem das Opções.
##
## Qualquer nó acertado (ou um antepassado dele) com um método
## `hit(point: Vector3, strength: float, collider: Object)` recebe o tiro.

## Disparado em cada bala; `result` é o resultado do raycast (vazio se falhou).
signal fired(result: Dictionary)

const RAY_LENGTH := 150.0
## O tiro testa o mundo (camada 1) e os alvos (camada 2).
const SHOT_MASK := 1 | 2
const MAX_PITCH := 89.0

## Falso enquanto um menu está aberto: o jogador não roda nem dispara.
var active := true
## Verdadeiro: dispara enquanto o botão estiver carregado. Falso: um tiro por
## clique (no jogo, para cada tiro ter de ser dado no ritmo).
var automatic := true
## Inclinação lateral da câmara (radianos), p. ex. ao morrer.
var roll := 0.0
## Falso: o próprio jogador não dispara com o clique (o jogo chama `shoot_once`).
var fire_enabled := true
## Força do recuo da vista a cada tiro (1 = como no CS).
var punch_scale := 1.0
## Alvo para onde a mira aponta neste frame (nó com `hit`, ou null).
var aimed_target: Node

var _yaw := 0.0
var _pitch := 0.0
var _punch := Vector2.ZERO
var _fire_cooldown := 0.0
var _shots_in_burst := 0

@onready var _head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var viewmodel: Viewmodel = $Head/Camera3D/Viewmodel
@onready var bullet_fx: BulletFX = $BulletFX


func _ready() -> void:
	_yaw = rotation.y
	camera.fov = Settings.vertical_fov()
	Settings.changed.connect(_on_setting_changed)


## Vira o jogador para uma direção (radianos à volta de Y; 0 = olhar para -Z).
func set_view(yaw: float, pitch := 0.0) -> void:
	_yaw = yaw
	_pitch = pitch


## Direção para onde a mira aponta (sem o recuo da vista).
func aim_direction() -> Vector3:
	return -_head.global_basis.z


## Dispara um tiro já (efeitos e som), sem esperar pelo intervalo da arma.
func shoot_once() -> void:
	_shoot()


## Abana a vista (graus), p. ex. ao levar um tiro.
func add_punch(pitch_deg: float, yaw_deg: float) -> void:
	_punch += Vector2(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg))


func _on_setting_changed(key: String) -> void:
	if key == "video/fov":
		camera.fov = Settings.vertical_fov()


func _unhandled_input(event: InputEvent) -> void:
	if not active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		# screen_relative não é afetado pela escala da janela (ex.: 4:3 esticado).
		var degrees: Vector2 = event.screen_relative * float(Settings.get_value("mouse/sensitivity")) * Settings.M_YAW
		var invert := -1.0 if Settings.get_value("mouse/invert_y") else 1.0
		_yaw -= deg_to_rad(degrees.x)
		_pitch = clampf(_pitch - deg_to_rad(degrees.y) * invert, -deg_to_rad(MAX_PITCH), deg_to_rad(MAX_PITCH))
		viewmodel.add_sway(degrees)
	elif event is InputEventKey and event.pressed and not event.echo:
		# Troca de arma como no CS: 1 = AK-47, 2 = USP-S, 3 = Desert Eagle, Q = a anterior.
		match (event as InputEventKey).physical_keycode:
			KEY_1, KEY_KP_1:
				viewmodel.switch_to("ak")
			KEY_2, KEY_KP_2:
				viewmodel.switch_to("usp")
			KEY_3, KEY_KP_3:
				viewmodel.switch_to("deagle")
			KEY_Q:
				viewmodel.switch_last()
	elif event is InputEventMouseButton and event.pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_UP:
				viewmodel.cycle(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				viewmodel.cycle(1)


func _process(delta: float) -> void:
	rotation.y = _yaw
	_head.rotation.x = _pitch
	# "View punch" do recuo, que volta ao sítio.
	_punch = _punch.lerp(Vector2.ZERO, 1.0 - exp(-delta * 10.0))
	camera.rotation = Vector3(_punch.x, _punch.y, roll)

	aimed_target = _target_at(_raycast(camera.global_position, -camera.global_basis.z))

	_fire_cooldown -= delta
	# As pistolas são semiautomáticas: um tiro por clique, com um intervalo mínimo.
	var auto := automatic and bool(viewmodel.stat("automatic"))
	var firing := active and fire_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and viewmodel.ready_to_fire() \
		and (Input.is_action_pressed("fire") if auto else Input.is_action_just_pressed("fire"))
	if not automatic and firing:
		_fire_cooldown = minf(_fire_cooldown, 0.0)
	if not firing:
		if not Input.is_action_pressed("fire"):
			_shots_in_burst = 0
	elif _fire_cooldown <= 0.0:
		_fire_cooldown = float(viewmodel.stat("interval"))
		_shoot()


func _shoot() -> void:
	viewmodel.fire(0.6)
	# O primeiro tiro é certeiro; numa rajada a dispersão vai aumentando.
	var spread := deg_to_rad(minf(_shots_in_burst * 0.35, 2.5))
	_shots_in_burst += 1
	var dir := -camera.global_basis.z
	dir = dir.rotated(camera.global_basis.y, randf_range(-spread, spread))
	dir = dir.rotated(camera.global_basis.x, randf_range(-spread, spread) * 0.5)
	var result := _raycast(camera.global_position, dir)

	var end: Vector3 = result.position if result else camera.global_position + dir * RAY_LENGTH
	var target := _target_at(result)
	if viewmodel.muzzle:
		bullet_fx.spawn_tracer(viewmodel.muzzle.global_position, end)
	if result:
		bullet_fx.spawn_impact(result.position, result.normal, 1.0 if target else 0.5)
	if target:
		target.hit(result.position, 1.0, result.collider)
	# Coice da câmara (pode desligar-se nas Opções → WEAPON → CAMERA RECOIL).
	if Settings.get_value("player/camera_recoil"):
		_punch.x += deg_to_rad(float(viewmodel.stat("punch"))) * punch_scale
		_punch.y += deg_to_rad(randf_range(-0.35, 0.35)) * punch_scale
	fired.emit(result)


func _raycast(origin: Vector3, dir: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * RAY_LENGTH, SHOT_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query)


## Sobe a partir do objeto acertado até encontrar um nó que saiba levar tiros.
static func _target_at(result: Dictionary) -> Node:
	if result.is_empty() or result.collider == null:
		return null
	var node: Node = result.collider
	for i in 4:
		if node == null:
			return null
		if node.has_method("hit") and node is not CollisionObject3D:
			return node
		node = node.get_parent()
	return null
