class_name Viewmodel
extends Node3D
## Arma nas mãos do jogador (com os braços do CS), presa à câmara como no CS2.
## Há três armas (AK-47, USP-S e Desert Eagle) e troca-se com 1/2/3, Q ou a roda
## do rato: a arma atual desce e a nova sobe. Ao disparar: coice, ferrolho ou
## corrediça a recuar, clarão na boca do cano e cápsula ejetada.
## Balança ao andar e atrasa-se ao rodar o rato. As posições foram afinadas para
## FOV 52° em 16:9; noutras FOV/proporções é compensada para ficar igual no ecrã.

signal weapon_changed(id: String)

const MODEL_LAYER := 2
const RECOVER := 13.0
const FLASH_TIME := 0.05
const CASING_LIFETIME := 0.7
const DESIGN_FOV := 52.0
const DESIGN_ASPECT := 16.0 / 9.0
const BOB_SPEED := 9.0
const BOB_AMOUNT := 0.006
const SWAY_AMOUNT := 0.0012
const SWAY_MAX := 0.02
## Duração de cada metade da troca de arma (descer / subir), em segundos.
const SWITCH_TIME := 0.16

const WEAPON_ORDER: Array[String] = ["ak", "usp", "deagle"]
## Cada arma: modelo, onde fica o eixo do cano (`rest`, x direita, y cima, -z
## frente, em relação à câmara), rotações de repouso em graus (`toe` converge
## para o centro, `cant` inclina o topo para a esquerda se negativo, `pitch`
## levanta o cano), peça que recua ao disparar e quanto, coice, som e clarão.
const WEAPONS := {
	"ak": {
		"name": "AK-47", "scene": "res://assets/models/viewmodel_ak.glb",
		"barrel_height": 0.182, "rest": Vector3(0.3, -0.17, -0.62), "toe": 4.0, "cant": -18.0, "pitch": 0.0,
		"bolt": "AK47_Bolt", "bolt_travel": 0.06, "muzzle": "Muzzle",
		"kick_back": 0.045, "kick_pitch": 4.5, "kick_up": 0.01,
		"sound": &"shot", "volume": -8.0, "flash": 1.0, "casing": 1.0,
		"automatic": true, "interval": 0.1, "punch": 0.9,
	},
	"usp": {
		"name": "USP-S", "scene": "res://assets/models/viewmodel_usp.glb",
		"barrel_height": 0.0, "rest": Vector3(0.14, -0.045, -0.40), "toe": 5.0, "cant": -6.0, "pitch": 4.0,
		"bolt": "USP_Slide", "bolt_travel": 0.028, "muzzle": "USP_Muzzle",
		"kick_back": 0.03, "kick_pitch": 7.0, "kick_up": 0.008,
		"sound": &"shot_usp", "volume": -6.0, "flash": 0.25, "casing": 0.75,
		"automatic": false, "interval": 0.15, "punch": 0.7,
	},
	"deagle": {
		"name": "DESERT EAGLE", "scene": "res://assets/models/viewmodel_deagle.glb",
		"barrel_height": 0.0, "rest": Vector3(0.14, -0.045, -0.40), "toe": 5.0, "cant": -6.0, "pitch": 4.0,
		"bolt": "Deagle_Slide", "bolt_travel": 0.04, "muzzle": "DE_Muzzle",
		"kick_back": 0.06, "kick_pitch": 16.0, "kick_up": 0.02,
		"sound": &"shot_deagle", "volume": -5.0, "flash": 1.3, "casing": 1.2,
		"automatic": false, "interval": 0.22, "punch": 2.2,
	},
}

var muzzle: Node3D
## 0..1, quão depressa o jogador anda (para o balanço da arma).
var move_amount := 0.0
## Arma atual (chave de WEAPONS).
var weapon_id := ""

var _weapon: Dictionary = {}
var _models := {}
var _model: Node3D
var _kick := 0.0
var _bob_phase := 0.0
var _sway := Vector2.ZERO
var _sway_target := Vector2.ZERO
var _roll := 0.0
var _flash := 0.0
var _bolt_rest := Vector3.ZERO
var _bolt: Node3D
var _flash_material: ShaderMaterial
var _casing_mesh: CylinderMesh
var _casings: Array[Dictionary] = []
## Troca de arma: 0 = arma em baixo (escondida), 1 = em posição.
var _raise := 1.0
var _pending_id := ""
var _last_id := ""

@onready var _flash_quad: MeshInstance3D = $MuzzleFlash
@onready var _flash_light: OmniLight3D = $MuzzleLight


func _ready() -> void:
	_flash_material = _flash_quad.material_override
	_flash_quad.layers = MODEL_LAYER

	_casing_mesh = CylinderMesh.new()
	_casing_mesh.top_radius = 0.0055
	_casing_mesh.bottom_radius = 0.0058
	_casing_mesh.height = 0.039
	_casing_mesh.radial_segments = 10
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.85, 0.62, 0.25)
	brass.metallic = 1.0
	brass.roughness = 0.3
	_casing_mesh.material = brass

	# Os três modelos ficam carregados (trocar é instantâneo); só um está visível.
	for id: String in WEAPON_ORDER:
		var model: Node3D = (load(WEAPONS[id].scene) as PackedScene).instantiate()
		model.visible = false
		add_child(model)
		for node in model.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).layers = MODEL_LAYER
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_models[id] = model
	var start := String(Settings.get_value("player/weapon"))
	_equip(start if WEAPONS.has(start) else "ak")
	_last_id = "usp" if weapon_id != "usp" else "ak"
	Settings.changed.connect(_on_setting_changed)


## Troca para outra arma (com a animação de descer/subir).
func switch_to(id: String) -> void:
	if not WEAPONS.has(id) or id == (_pending_id if not _pending_id.is_empty() else weapon_id):
		return
	_pending_id = id
	if String(Settings.get_value("player/weapon")) != id:
		Settings.set_value("player/weapon", id)


## Volta à arma anterior (como o Q do CS).
func switch_last() -> void:
	switch_to(_last_id)


## Arma seguinte/anterior na lista (roda do rato).
func cycle(step: int) -> void:
	var current := _pending_id if not _pending_id.is_empty() else weapon_id
	var i := WEAPON_ORDER.find(current)
	switch_to(WEAPON_ORDER[posmod(i + step, WEAPON_ORDER.size())])


func weapon_name() -> String:
	return String(_weapon.get("name", ""))


## Valor de uma característica da arma atual (ver WEAPONS).
func stat(key: String) -> Variant:
	return _weapon.get(key)


## Falso durante a troca de arma (não se dispara com a arma em baixo).
func ready_to_fire() -> bool:
	return _pending_id.is_empty() and _raise >= 0.6


## Dispara um tiro. `strength` (0..1) controla o coice.
func fire(strength: float = 1.0) -> void:
	_play_weapon_sound(_weapon.sound, float(_weapon.volume))
	_kick = minf(_kick + 0.55 + strength * 0.45, 1.6)
	_roll = randf_range(-2.0, 2.0) * (0.5 + strength)
	_flash = 1.0
	_flash_material.set_shader_parameter("angle", randf() * TAU)
	_eject_casing()


## Som da arma com o volume das Opções (ÁUDIO → WEAPONS).
func _play_weapon_sound(sound: StringName, volume_db: float) -> void:
	var v := float(Settings.get_value("audio/weapon_volume"))
	if v <= 0.001:
		return
	AudioManager.play_sfx(sound, volume_db + linear_to_db(v), randf_range(0.95, 1.05))


## Movimento do rato em graus, para a arma "atrasar-se" um pouco ao rodar.
func add_sway(degrees: Vector2) -> void:
	_sway_target = (_sway_target + degrees * SWAY_AMOUNT).limit_length(SWAY_MAX)


func _on_setting_changed(key: String) -> void:
	if key == "player/weapon":
		switch_to(String(Settings.get_value(key)))


func _equip(id: String) -> void:
	if not weapon_id.is_empty() and weapon_id != id:
		_last_id = weapon_id
	weapon_id = id
	_weapon = WEAPONS[id]
	for other: String in _models:
		_models[other].visible = other == id
	_model = _models[id]
	_model.position = Vector3(0.0, -float(_weapon.barrel_height), 0.0)
	muzzle = _model.find_child(String(_weapon.muzzle), true, false)
	_bolt = _model.find_child(String(_weapon.bolt), true, false)
	if _bolt:
		_bolt_rest = _bolt.position
	_kick = 0.0
	weapon_changed.emit(id)


func _process(delta: float) -> void:
	# Troca de arma: desce a atual, muda de modelo e sobe a nova.
	if not _pending_id.is_empty():
		_raise = maxf(_raise - delta / SWITCH_TIME, 0.0)
		if _raise <= 0.0:
			_equip(_pending_id)
			_pending_id = ""
			_play_weapon_sound(&"draw", -10.0)
	elif _raise < 1.0:
		_raise = minf(_raise + delta / SWITCH_TIME, 1.0)

	_kick *= exp(-delta * RECOVER)
	_roll *= exp(-delta * RECOVER)
	_flash = maxf(_flash - delta / FLASH_TIME, 0.0)
	_sway_target = _sway_target.lerp(Vector2.ZERO, 1.0 - exp(-delta * 6.0))
	_sway = _sway.lerp(_sway_target, 1.0 - exp(-delta * 12.0))
	_bob_phase += delta * BOB_SPEED * move_amount

	var w := _weapon
	var lowered := 1.0 - _raise * _raise * (3.0 - 2.0 * _raise)
	var t := Time.get_ticks_msec() / 1000.0
	var breathe := Vector3(sin(t * 1.3) * 0.002, sin(t * 2.1) * 0.003, 0.0)
	var bob := Vector3(sin(_bob_phase) * BOB_AMOUNT, -absf(cos(_bob_phase)) * BOB_AMOUNT, 0.0) * move_amount
	var sway := Vector3(-_sway.x, _sway.y, 0.0)
	var local: Vector3 = w.rest + _player_offset() + breathe + bob + sway \
		+ Vector3(0.0, _kick * float(w.kick_up), _kick * float(w.kick_back)) \
		+ Vector3(0.0, -0.22, 0.05) * lowered

	# Compensação de FOV (escala tudo à volta da câmara) e de proporção (x).
	var cam := get_parent() as Camera3D
	var k := 1.0
	if cam:
		k = tan(deg_to_rad(DESIGN_FOV) * 0.5) / tan(deg_to_rad(cam.fov) * 0.5)
	var rect := get_viewport().get_visible_rect().size
	local.x *= (rect.x / rect.y) / DESIGN_ASPECT
	position = local * k
	basis = Basis(Vector3.UP, deg_to_rad(float(w.toe))) \
		* Basis(Vector3.RIGHT, deg_to_rad(float(w.pitch) + _kick * float(w.kick_pitch) + _sway.y * 40.0 - lowered * 35.0)) \
		* Basis(Vector3.FORWARD, deg_to_rad(float(w.cant) + _roll + _sway.x * 60.0)) \
		* Basis.from_scale(Vector3.ONE * k)

	if _bolt:
		_bolt.position = _bolt_rest + Vector3(0.0, 0.0, minf(_kick, 1.0) * float(w.bolt_travel))

	if muzzle:
		_flash_quad.global_position = muzzle.global_position
		_flash_light.global_position = muzzle.global_position
	var flash := _flash * float(w.flash)
	_flash_quad.visible = flash > 0.0
	_flash_material.set_shader_parameter("flash", minf(flash, 1.0))
	_flash_quad.scale = Vector3.ONE * (0.8 + _flash * 0.6) * clampf(float(w.flash), 0.4, 1.3)
	_flash_light.light_energy = flash * 4.0

	_update_casings(delta)


## Deslocamento escolhido nas Opções, em cm (z positivo = mais longe do ecrã).
## Está calibrado para a distância da AK; as pistolas ficam mais perto da câmara,
## por isso o deslocamento encolhe na mesma proporção (move o mesmo no ecrã).
func _player_offset() -> Vector3:
	var depth_ratio := absf(Vector3(_weapon.rest).z) / absf(Vector3(WEAPONS.ak.rest).z)
	return Vector3(Settings.get_value("viewmodel/offset_x"), Settings.get_value("viewmodel/offset_y"),
		-Settings.get_value("viewmodel/offset_z")) * 0.01 * depth_ratio


func _eject_casing() -> void:
	if _bolt == null:
		return
	var casing := MeshInstance3D.new()
	casing.mesh = _casing_mesh
	casing.layers = MODEL_LAYER
	casing.top_level = true
	casing.scale = Vector3.ONE * float(_weapon.casing)
	add_child(casing)
	# Janela de ejeção: lado direito, junto ao ferrolho/corrediça.
	casing.global_position = _bolt.global_position + global_basis.x * 0.03
	var velocity := global_basis.x * randf_range(1.4, 2.0) + global_basis.y * randf_range(1.2, 1.7) \
		+ global_basis.z * randf_range(0.1, 0.4)
	var spin := Vector3(randf_range(-30, 30), randf_range(-30, 30), randf_range(-30, 30))
	_casings.append({"node": casing, "velocity": velocity, "spin": spin, "age": 0.0})


func _update_casings(delta: float) -> void:
	for i in range(_casings.size() - 1, -1, -1):
		var c := _casings[i]
		var node: MeshInstance3D = c["node"]
		c["age"] += delta
		if c["age"] > CASING_LIFETIME:
			node.queue_free()
			_casings.remove_at(i)
			continue
		c["velocity"] += Vector3.DOWN * 9.8 * delta
		node.global_position += c["velocity"] * delta
		node.rotation += c["spin"] * delta
		node.scale = Vector3.ONE * float(_weapon.casing)
