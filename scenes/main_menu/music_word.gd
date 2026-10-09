class_name MusicWord
extends Node3D
## Palavra gigante do menu (JOGAR, OPÇÕES, SAIR...) feita de cubos, numa fonte
## de píxeis. Cada coluna de cubos salta com uma banda do espectro da música
## (graves ao centro, agudos nas pontas), como o terreno atrás.
## - Apontar: a palavra acende e os cubos aproximam-se.
## - Cada bala empurra os cubos à volta do ponto de impacto.
## - `explode()`: os cubos voam em todas as direções e voltam a montar a palavra.
## A frente da palavra é o +Z local. Tudo é construído em código.

signal shot(word: MusicWord, strength: float)

const SHADER := preload("res://shaders/music_word.gdshader")
## Camada de física das palavras (os tiros testam a camada do mundo + esta).
const PHYSICS_LAYER := 2
## Fonte 5×10: 2 linhas para acentos em cima, 7 de letra, 1 para a cedilha.
const GLYPH_W := 5
const GLYPH_H := 10
const GLYPHS := {
	"A": ["", "", ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#", ""],
	"C": ["", "", ".####", "#....", "#....", "#....", "#....", "#....", ".####", ""],
	"Ç": ["", "", ".####", "#....", "#....", "#....", "#....", "#....", ".####", "..#.."],
	"E": ["", "", "#####", "#....", "#....", "####.", "#....", "#....", "#####", ""],
	"G": ["", "", ".####", "#....", "#....", "#..##", "#...#", "#...#", ".###.", ""],
	"I": ["", "", "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####", ""],
	"J": ["", "", "..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##..", ""],
	"O": ["", "", ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###.", ""],
	"Õ": [".##.#", "#.##.", ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###.", ""],
	"P": ["", "", "####.", "#...#", "#...#", "####.", "#....", "#....", "#....", ""],
	"R": ["", "", "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#", ""],
	"S": ["", "", ".####", "#....", "#....", ".###.", "....#", "....#", "####.", ""],
	"T": ["", "", "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#..", ""],
	"N": ["", "", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#", ""],
	"L": ["", "", "#....", "#....", "#....", "#....", "#....", "#....", "#####", ""],
	"Y": ["", "", "#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#..", ""],
	"Q": ["", "", ".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#", ""],
	"U": ["", "", "#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###.", ""],
	" ": ["", "", "", "", "", "", "", "", "", ""],
}
const EXPLODE_TIME := 0.9
const REASSEMBLE_TIME := 0.55

@export var text := "PLAY"
## Texto mostrado na mira quando se aponta para a palavra.
@export var hint := "SHOOT TO PLAY"
@export var color: Color = UITheme.T_ORANGE
## Tamanho de cada cubo (a palavra escala com isto).
@export var cube := 0.14

## Nome curto usado no kill feed e na mira.
var title: String:
	get:
		return text
## Verdadeiro enquanto o jogador aponta para esta palavra.
var hovered := false
## Usado para não repetir a ação a cada bala de uma rajada.
var next_action_ms := 0

var _cells: Array[Vector2i] = []   # (coluna, linha) de cada cubo
var _rest: PackedVector3Array       # posição de repouso de cada cubo
var _offset: PackedVector3Array     # empurrão das balas (mola)
var _offset_vel: PackedVector3Array
var _flash: PackedFloat32Array
var _level: PackedFloat32Array      # nível da música por cubo (suavizado)
var _fly: PackedVector3Array        # deslocamento da explosão
var _fly_vel: PackedVector3Array
var _spin: PackedVector3Array
var _spin_vel: PackedVector3Array
var _columns := 0
var _rows := 0
var _hover := 0.0
var _explode_t := -1.0
var _shake := 0.0
var _mm: MultiMesh
var _size := Vector3.ZERO


func _ready() -> void:
	_build_cells()
	_build_mesh()
	_build_collision()


## Uma bala acertou em `point` (posição global).
func hit(point: Vector3, strength: float, _collider: Object = null) -> void:
	var local := to_local(point)
	for i in _cells.size():
		var d := Vector2(_rest[i].x - local.x, _rest[i].y - local.y).length()
		var falloff := clampf(1.0 - d / (cube * 4.5), 0.0, 1.0)
		if falloff <= 0.0:
			continue
		_offset_vel[i] += Vector3(0, 0, -2.6 * falloff * strength)
		_flash[i] = maxf(_flash[i], falloff)
	shot.emit(self, strength)


## A palavra rebenta em cubos e volta a montar-se.
func explode() -> void:
	_explode_t = 0.0
	for i in _cells.size():
		var outward := Vector3(_rest[i].x, _rest[i].y, 0.0).normalized()
		_fly[i] = Vector3.ZERO
		_fly_vel[i] = (outward * randf_range(1.5, 4.5) + Vector3(randf_range(-1, 1), randf_range(0.5, 3.0),
			randf_range(1.5, 5.0))) * (cube / 0.14)
		_spin_vel[i] = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
		_flash[i] = 1.0


## Treme (usado antes de confirmar SAIR).
func shake() -> void:
	_shake = 1.0


## Retângulo da palavra no ecrã (em coordenadas do viewport).
func screen_rect(cam: Camera3D) -> Rect2:
	var rect := Rect2()
	var first := true
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			var p := cam.unproject_position(to_global(Vector3(_size.x * sx, _size.y * sy, 0.0)))
			if first:
				rect = Rect2(p, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(p)
	return rect


func _process(delta: float) -> void:
	_hover = move_toward(_hover, 1.0 if hovered else 0.0, delta * 6.0)
	_shake = maxf(_shake - delta * 2.5, 0.0)
	var bands := AudioManager.bands
	var half := (_columns - 1) * 0.5

	var exploding := _explode_t >= 0.0
	var reassemble := 0.0
	if exploding:
		_explode_t += delta
		if _explode_t > EXPLODE_TIME:
			reassemble = clampf((_explode_t - EXPLODE_TIME) / REASSEMBLE_TIME, 0.0, 1.0)
			reassemble = 1.0 - pow(1.0 - reassemble, 3.0)
		if _explode_t > EXPLODE_TIME + REASSEMBLE_TIME:
			_explode_t = -1.0
			exploding = false

	var k := 1.0 - exp(-delta * 18.0)
	for i in _cells.size():
		var cell := _cells[i]
		# Banda da música desta coluna: graves ao centro, agudos nas pontas.
		var d := absf(cell.x - half) / maxf(half, 1.0)
		var band := clampi(int(d * 30.0), 0, bands.size() - 1) if bands.size() > 0 else 0
		var target_level := pow(bands[band], 1.5) if bands.size() > 0 else 0.0
		_level[i] = maxf(target_level, _level[i] - delta * 1.6) if target_level < _level[i] \
			else lerpf(_level[i], target_level, k)

		# Mola dos empurrões das balas.
		_offset_vel[i] += (-_offset[i] * 90.0 - _offset_vel[i] * 9.0) * delta
		_offset[i] += _offset_vel[i] * delta
		_flash[i] = maxf(_flash[i] - delta * 3.0, 0.0)

		if exploding:
			if _explode_t <= EXPLODE_TIME:
				_fly_vel[i] += Vector3(0, -6.0 * (cube / 0.14), 0) * delta
				_fly[i] += _fly_vel[i] * delta
				_spin[i] += _spin_vel[i] * delta
			else:
				_fly[i] = _fly[i].lerp(Vector3.ZERO, reassemble)
				_spin[i] = _spin[i].lerp(Vector3.ZERO, reassemble)

		var level := _level[i]
		var depth := cube * (0.7 + level * 3.0 + _hover * 0.6)
		var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * cube * 0.25 * _shake
		var pos := _rest[i] + _offset[i] + _fly[i] + shake + Vector3(0, 0, depth * 0.5 + _hover * cube * 0.8)
		var basis := Basis.from_euler(_spin[i]) * Basis.from_scale(Vector3(cube * 0.86, cube * 0.86, depth))
		_mm.set_instance_transform(i, Transform3D(basis, pos))
		_mm.set_instance_custom_data(i, Color(level, _flash[i], _hover, 0.0))


func _build_cells() -> void:
	var col := 0
	for ch in text.to_upper():
		var glyph: Array = GLYPHS.get(ch, GLYPHS[" "])
		for r in GLYPH_H:
			var row: String = glyph[r]
			for c in row.length():
				if row[c] == "#":
					_cells.append(Vector2i(col + c, r))
		col += GLYPH_W + 1
	_columns = col - 1
	_rows = GLYPH_H
	_size = Vector3(_columns * cube, _rows * cube, cube)

	var n := _cells.size()
	# (Os Packed*Array são valores, por isso cada um é redimensionado à parte.)
	_rest.resize(n)
	_offset.resize(n)
	_offset_vel.resize(n)
	_fly.resize(n)
	_fly_vel.resize(n)
	_spin.resize(n)
	_spin_vel.resize(n)
	_flash.resize(n)
	_level.resize(n)
	for i in n:
		var c := _cells[i]
		_rest[i] = Vector3((c.x - (_columns - 1) * 0.5) * cube, ((_rows - 1) * 0.5 - c.y) * cube, 0.0)


func _build_mesh() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("low_color", color.darkened(0.25))
	mat.set_shader_parameter("high_color", color.lightened(0.35))
	box.material = mat

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = box
	_mm.instance_count = _cells.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A explosão espalha os cubos para fora da caixa da palavra.
	mmi.custom_aabb = AABB(-_size * 2.0 - Vector3(0, 3, 0), _size * 4.0 + Vector3(0, 6, 8))
	add_child(mmi)

	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = maxf(_size.x, 3.0)
	light.light_energy = 0.8
	light.light_volumetric_fog_energy = 0.3
	light.position = Vector3(0, 0, cube * 4.0)
	add_child(light)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = PHYSICS_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_size.x, _size.y, cube * 3.0)
	shape.shape = box
	shape.position = Vector3(0, 0, cube * 1.5)
	body.add_child(shape)
	add_child(body)
