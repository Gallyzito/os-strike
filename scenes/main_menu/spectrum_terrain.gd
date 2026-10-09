class_name SpectrumTerrain
extends MultiMeshInstance3D
## Campo de colunas que forma um espectrograma 3D: a linha da frente mostra o
## espectro atual (graves ao centro, agudos nas pontas) e vai recuando.

const COLS := 48
const ROWS := 56
const SPACING := 0.95
const ROWS_PER_SECOND := 24.0

var _image: Image
var _texture: ImageTexture
var _head := 0
var _accum := 0.0
var _base_z := 0.0

@onready var _material: ShaderMaterial = material_override


func _ready() -> void:
	_base_z = position.z
	_image = Image.create(COLS, ROWS, false, Image.FORMAT_RF)
	_texture = ImageTexture.create_from_image(_image)
	_material.set_shader_parameter("heights", _texture)
	_material.set_shader_parameter("cols", COLS)
	_material.set_shader_parameter("rows", ROWS)

	var box := BoxMesh.new()
	box.size = Vector3(SPACING * 0.8, 1.0, SPACING * 0.8)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = COLS * ROWS
	for row in ROWS:
		for col in COLS:
			var x := (col - (COLS - 1) * 0.5) * SPACING
			mm.set_instance_transform(row * COLS + col, Transform3D(Basis(), Vector3(x, 0.0, -row * SPACING)))
	multimesh = mm
	# O shader estica as colunas, por isso a caixa de culling tem de ser manual.
	custom_aabb = AABB(Vector3(-COLS * SPACING * 0.5, -1.0, -ROWS * SPACING - 1.0),
		Vector3(COLS * SPACING, 8.0, ROWS * SPACING + 2.0))


func _process(delta: float) -> void:
	_accum += delta * ROWS_PER_SECOND
	while _accum >= 1.0:
		_accum -= 1.0
		_push_row()
	# Movimento contínuo entre linhas, para não andar aos saltos.
	position.z = _base_z - _accum * SPACING
	_material.set_shader_parameter("head", _head)


func _push_row() -> void:
	_head = (_head + 1) % ROWS
	var bands := AudioManager.bands
	var half := COLS >> 1
	@warning_ignore("integer_division")
	var band_step := bands.size() / half
	for col in COLS:
		var d := col - half if col >= half else half - 1 - col
		var value := 0.0
		for k in band_step:
			value = maxf(value, bands[d * band_step + k])
		_image.set_pixel(col, _head, Color(pow(value, 1.7), 0.0, 0.0))
	_texture.update(_image)
