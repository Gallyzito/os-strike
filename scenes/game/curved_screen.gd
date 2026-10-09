class_name CurvedScreen
extends Node3D
## Ecrã curvo à frente do jogador: um pedaço de cilindro com o eixo nos olhos
## dele, por isso todos os pontos do ecrã ficam à mesma distância. A largura e a
## altura são fixas (em metros); a distância vem das Opções, por isso um ecrã
## mais longe parece mais pequeno (como afastar o monitor).
## A mira converte-se no ponto do ecrã de forma exata (intersecção raio-cilindro).

const WIDTH := 4.2
const HEIGHT := WIDTH * 9.0 / 16.0
const COLUMNS := 96
const SHADER := preload("res://shaders/curved_screen.gdshader")
const WORLD_LAYER := 1

## Centro dos olhos do jogador (eixo do cilindro).
var eye := Vector3(0, 1.65, 0)
var distance := 3.0
var texture: Texture2D:
	set(value):
		texture = value
		if _material:
			_material.set_shader_parameter("screen_texture", value)

var _material: ShaderMaterial
var _screen: MeshInstance3D
var _frame: MeshInstance3D
var _body: StaticBody3D
var _decor: Array[Node3D] = []
## Estilhaços: {node, vel, spin (eixo * velocidade angular), home, from}
var _shards: Array[Dictionary] = []
var _shard_root: Node3D
var _return_t := -1.0
var _return_time := 0.8


func _ready() -> void:
	distance = float(Settings.get_value("osu/screen_distance"))
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	if texture:
		_material.set_shader_parameter("screen_texture", texture)
	_build()


## Muda a distância do ecrã (Opções) e refaz a malha.
func set_distance(d: float) -> void:
	distance = d
	_build()


func angle_span() -> float:
	return WIDTH / distance


## Ponto do ecrã (UV 0..1) para onde aponta um raio que sai dos olhos, ou
## Vector2(-1, -1) se não acertar no ecrã.
func aim_uv(direction: Vector3) -> Vector2:
	var flat := Vector2(direction.x, direction.z)
	if flat.length() < 0.0001:
		return Vector2(-1, -1)
	var t := distance / flat.length()
	var ang := atan2(direction.x, -direction.z)
	var u := ang / angle_span() + 0.5
	var v := 0.5 - direction.y * t / HEIGHT
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return Vector2(-1, -1)
	return Vector2(u, v)


## Ponto 3D do ecrã para um UV (para efeitos, ex.: balas).
func uv_to_world(uv: Vector2) -> Vector3:
	var ang := (uv.x - 0.5) * angle_span()
	return eye + Vector3(sin(ang) * distance, (0.5 - uv.y) * HEIGHT, -cos(ang) * distance)


func _build() -> void:
	for child in get_children():
		if child != _shard_root:
			child.queue_free()
	_decor.clear()
	_screen = MeshInstance3D.new()
	_screen.mesh = _cylinder(distance, WIDTH, HEIGHT, true)
	_screen.material_override = _material
	_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_screen)
	# Moldura escura um pouco maior, atrás do ecrã.
	_frame = MeshInstance3D.new()
	_frame.mesh = _cylinder(distance + 0.03, WIDTH * (distance + 0.03) / distance + 0.12, HEIGHT + 0.12, true)
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.03, 0.035, 0.05)
	frame_mat.roughness = 0.4
	frame_mat.metallic = 0.6
	frame_mat.emission_enabled = true
	frame_mat.emission = Color(0.05, 0.06, 0.09)
	frame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_frame.material_override = frame_mat
	add_child(_frame)
	_decor.append(_frame)
	# Linhas de luz em cima e em baixo.
	for y in [HEIGHT * 0.5 + 0.045, -HEIGHT * 0.5 - 0.045]:
		var strip := MeshInstance3D.new()
		strip.mesh = _cylinder(distance + 0.01, WIDTH + 0.06, 0.012, true, y)
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(1.0, 0.62, 0.11) * 2.2
		glow.cull_mode = BaseMaterial3D.CULL_DISABLED
		strip.material_override = glow
		add_child(strip)
		_decor.append(strip)
	# Colisão (as balas fazem faíscas no ecrã).
	_body = StaticBody3D.new()
	_body.collision_layer = WORLD_LAYER
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var tri := _screen.mesh.create_trimesh_shape()
	tri.backface_collision = true
	shape.shape = tri
	_body.add_child(shape)
	add_child(_body)


## Pedaço de cilindro (raio `radius`, comprimento de arco `arc`, altura `height`)
## centrado nos olhos e virado para dentro.
func _cylinder(radius: float, arc: float, height: float, inward: bool, y_offset := 0.0) -> ArrayMesh:
	var span := arc / radius
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in COLUMNS:
		var u0 := float(i) / COLUMNS
		var u1 := float(i + 1) / COLUMNS
		var a0 := (u0 - 0.5) * span
		var a1 := (u1 - 0.5) * span
		var p: Array[Vector3] = [
			eye + Vector3(sin(a0) * radius, y_offset + height * 0.5, -cos(a0) * radius),
			eye + Vector3(sin(a1) * radius, y_offset + height * 0.5, -cos(a1) * radius),
			eye + Vector3(sin(a1) * radius, y_offset - height * 0.5, -cos(a1) * radius),
			eye + Vector3(sin(a0) * radius, y_offset - height * 0.5, -cos(a0) * radius),
		]
		var uv: Array[Vector2] = [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)]
		var order: Array[int] = [0, 1, 2, 0, 2, 3]
		if not inward:
			order = [0, 2, 1, 0, 3, 2]
		for k in order:
			var n := (eye - p[k]) * Vector3(1, 0, 1)
			st.set_normal(n.normalized())
			st.set_uv(uv[k])
			st.add_vertex(p[k])
	return st.commit()


# --- Explosão (quando o jogador falha o mapa) ---------------------------------------------

## Avaria do ecrã: `g` glitch 0..1, `c` rachas 0..1 a partir de `impact_uv`.
func set_glitch(g: float, c: float, impact_uv := Vector2(0.5, 0.5)) -> void:
	_material.set_shader_parameter("glitch", g)
	_material.set_shader_parameter("crack", c)
	_material.set_shader_parameter("impact", impact_uv)


## Parte o ecrã em estilhaços (com a imagem do jogo) que voam a partir do impacto.
func shatter(impact_uv: Vector2) -> void:
	_clear_shards()
	_screen.visible = false
	for d in _decor:
		d.visible = false
	_shard_root = Node3D.new()
	add_child(_shard_root)
	var cols := 22
	var rows := 12
	var rng := RandomNumberGenerator.new()
	# Grelha de pontos (com os de dentro baralhados) em UV.
	var grid: Array[Vector2] = []
	for j in rows + 1:
		for i in cols + 1:
			var uv := Vector2(float(i) / cols, float(j) / rows)
			if i > 0 and i < cols and j > 0 and j < rows:
				uv += Vector2(rng.randf_range(-0.38, 0.38) / cols, rng.randf_range(-0.38, 0.38) / rows)
			grid.append(uv)
	var hit := uv_to_world(impact_uv)
	for j in rows:
		for i in cols:
			var a := grid[j * (cols + 1) + i]
			var b := grid[j * (cols + 1) + i + 1]
			var c := grid[(j + 1) * (cols + 1) + i + 1]
			var d := grid[(j + 1) * (cols + 1) + i]
			var tris: Array = [[a, b, c], [a, c, d]] if rng.randf() < 0.5 else [[a, b, d], [b, c, d]]
			for tri in tris:
				_add_shard(tri, hit, rng)
	_explosion_fx(hit)


func _add_shard(tri: Array, hit: Vector3, rng: RandomNumberGenerator) -> void:
	var pts: Array[Vector3] = []
	var centroid := Vector3.ZERO
	for uv: Vector2 in tri:
		var p := uv_to_world(uv)
		pts.append(p)
		centroid += p / 3.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal := ((eye - centroid) * Vector3(1, 0, 1)).normalized()
	for k in 3:
		st.set_normal(normal)
		st.set_uv(tri[k])
		st.add_vertex(pts[k] - centroid)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = centroid
	_shard_root.add_child(mi)
	var away := centroid - hit
	var dist := away.length()
	var out := away.normalized() if dist > 0.01 else Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), 0).normalized()
	var toward := (eye - centroid).normalized()
	var power := clampf(1.6 - dist / 2.5, 0.35, 1.6)
	var vel := out * rng.randf_range(1.0, 3.6) * power + toward * rng.randf_range(0.3, 2.4) * power \
		+ Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.4
	var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
	_shards.append({"node": mi, "vel": vel, "spin": axis * rng.randf_range(2.0, 14.0) * power,
		"home": mi.transform, "from": mi.transform})


## Os estilhaços voltam ao sítio (como a rebobinar) em `duration` segundos.
func reassemble(duration := 0.8) -> void:
	if _shards.is_empty():
		return
	for s in _shards:
		s.from = (s.node as Node3D).transform
	_return_time = duration
	_return_t = 0.0


func _process(delta: float) -> void:
	if _shards.is_empty():
		return
	if _return_t >= 0.0:
		_return_t += delta / maxf(Engine.time_scale, 0.01)
		var k := clampf(_return_t / _return_time, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		for s in _shards:
			(s.node as Node3D).transform = (s.from as Transform3D).interpolate_with(s.home, e)
		if k >= 1.0:
			_clear_shards()
			_screen.visible = true
			for d in _decor:
				d.visible = true
		return
	var drag := exp(-1.4 * delta)
	for s in _shards:
		var n: Node3D = s.node
		n.position += s.vel * delta
		s.vel *= drag
		var spin: Vector3 = s.spin
		if spin.length() > 0.001:
			n.basis = Basis(spin.normalized(), spin.length() * delta) * n.basis
		s.spin = spin * drag


func _clear_shards() -> void:
	_shards.clear()
	_return_t = -1.0
	if _shard_root:
		_shard_root.queue_free()
		_shard_root = null


## Clarão, onda de choque e faíscas no ponto do impacto.
func _explosion_fx(at: Vector3) -> void:
	var to_eye := (eye - at).normalized()
	# Luz.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 14.0
	light.omni_range = 9.0
	light.position = at + to_eye * 0.4
	add_child(light)
	var lt := create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.9).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	lt.tween_callback(light.queue_free)
	# Duas ondas de choque (anéis que crescem e desaparecem).
	for k in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.92
		torus.outer_radius = 1.0
		torus.rings = 64
		torus.ring_segments = 6
		ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(2.0, 1.1, 0.4, 1.0) if k == 0 else Color(0.95, 1.2, 1.6, 0.8)
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = at + to_eye * (0.05 + k * 0.1)
		ring.basis = Basis(Quaternion(Vector3.UP, to_eye)).scaled(Vector3.ONE * 0.1)
		add_child(ring)
		var rt := create_tween().set_parallel().set_ignore_time_scale(true)
		var target_scale := ring.basis.get_scale() * (45.0 if k == 0 else 30.0)
		rt.tween_property(ring, "scale", target_scale, 1.1 + k * 0.4).set_delay(k * 0.08) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		rt.tween_property(mat, "albedo_color:a", 0.0, 0.7 + k * 0.2).set_delay(k * 0.08).set_ease(Tween.EASE_IN)
		rt.chain().tween_callback(ring.queue_free)
	# Faíscas.
	var sparks := CPUParticles3D.new()
	sparks.position = at
	sparks.one_shot = true
	sparks.explosiveness = 0.95
	sparks.amount = 320
	sparks.lifetime = 1.6
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.25
	sparks.direction = to_eye
	sparks.spread = 180.0
	sparks.initial_velocity_min = 3.0
	sparks.initial_velocity_max = 13.0
	sparks.damping_min = 2.0
	sparks.damping_max = 5.0
	sparks.gravity = Vector3(0, -1.5, 0)
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.6
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.8, 1.0))
	grad.add_point(0.35, Color(1.0, 0.55, 0.15, 1.0))
	grad.set_color(grad.get_point_count() - 1, Color(0.8, 0.1, 0.05, 0.0))
	sparks.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(0.022, 0.022)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	smat.albedo_color = Color(1.6, 1.6, 1.6)
	quad.material = smat
	sparks.mesh = quad
	add_child(sparks)
	sparks.emitting = true
	sparks.finished.connect(sparks.queue_free)