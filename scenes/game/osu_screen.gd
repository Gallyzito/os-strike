class_name OsuScreen
extends Control
## O que aparece no ecrã curvo (dentro de um SubViewport 1920 × 1080): o osu!
## desenhado com a skin escolhida. Cada elemento usa a imagem da skin se ela
## existir; senão é desenhado por código (a skin do os!strike).
## Também desenha a pausa, o ecrã de falhar e os resultados, com botões que se
## escolhem a disparar (OsuGame pergunta `button_at`).

const VIEW_SIZE := Vector2i(1920, 1080)
## 1 pixel do osu! = 2.25 px (como o osu! em 1080p); o campo de 512 × 384 fica centrado.
const SCALE := 2.25
const ORIGIN := Vector2((1920.0 - 512.0 * SCALE) * 0.5, (1080.0 - 384.0 * SCALE) * 0.5 + 8.0)
const JUDGE_COLORS: Array[Color] = [
	Color(0.45, 0.8, 1.0), Color(0.45, 1.0, 0.5), Color(1.0, 0.7, 0.25), Color(1.0, 0.22, 0.25),
]
const TRAIL_LENGTH := 14
## As imagens de interface das skins são feitas para 768 px de altura.
const UI_SCALE := 1080.0 / 768.0

var game: OsuGame

var _title: Font
var _bold: Font
var _body: Font
var _mono: Font
var _buttons: Dictionary[String, Rect2] = {}
var _errors: Array[Vector2] = []
var _trail: Array[Vector2] = []
var _shown_score := 0.0
var _bg: Texture2D
var _fl_tex: GradientTexture2D
## Camadas por baixo do resto: fundo (z -2) e corpos dos sliders (z -1).
var _bg_layer: Control
var _bodies_root: Node2D
var _bodies: Array[SliderBody] = []


static func osu_to_view(p: Vector2) -> Vector2:
	return ORIGIN + p * SCALE


static func view_to_osu(v: Vector2) -> Vector2:
	return (v - ORIGIN) / SCALE


func _ready() -> void:
	size = Vector2(VIEW_SIZE)
	_bg_layer = Control.new()
	_bg_layer.size = Vector2(VIEW_SIZE)
	_bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_layer.z_index = -2
	_bg_layer.draw.connect(_draw_background)
	add_child(_bg_layer)
	_bodies_root = Node2D.new()
	_bodies_root.z_index = -1
	add_child(_bodies_root)
	_title = UITheme.din(700, 75)
	_bold = UITheme.din(700, 85)
	_body = UITheme.din(500, 100)
	_mono = UITheme.mono()


func add_error(err: float, _windows: Vector3) -> void:
	_errors.append(Vector2(err, Time.get_ticks_msec() / 1000.0))
	if _errors.size() > 30:
		_errors.pop_front()


## Nome do botão debaixo do ponto (coordenadas do ecrã), ou "".
func button_at(view_pos: Vector2) -> String:
	for b: String in _buttons:
		if _buttons[b].has_point(view_pos):
			return b
	return ""


func _process(delta: float) -> void:
	if game == null:
		return
	if _bg == null and not game.map.is_empty():
		_bg = Game.background(game.map)
	_shown_score = lerpf(_shown_score, float(game.score), 1.0 - exp(-delta * 10.0))
	if game.aim_on_screen:
		_trail.append(game.aim_view)
		if _trail.size() > TRAIL_LENGTH:
			_trail.pop_front()
	elif not _trail.is_empty():
		_trail.pop_front()
	_update_bodies()
	_bg_layer.queue_redraw()
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	_buttons.clear()
	var phase := game.phase
	if phase != OsuGame.Phase.RESULTS:
		_draw_follow_points()
		_draw_objects()
		_draw_judgments()
		if "FL" in game.mods:
			_draw_flashlight()
		_draw_hud()
	match phase:
		OsuGame.Phase.PAUSED:
			_draw_pause()
		OsuGame.Phase.FAILED:
			_draw_fail()
		OsuGame.Phase.RESULTS:
			_draw_results()
		OsuGame.Phase.FAILING:
			pass
		OsuGame.Phase.RESUMING:
			_draw_countdown()
		_:
			_draw_intro()
	_draw_cursor()


## Contagem ao sair da pausa: número grande ao centro, um anel que se esvazia
## ao longo dos 3 s e um "approach circle" que fecha em cada segundo.
func _draw_countdown() -> void:
	var t := game.resume_countdown
	var total := OsuGame.RESUME_COUNTDOWN
	var n := int(ceilf(t))
	var p := float(n) - t
	var c := Vector2(VIEW_SIZE) * 0.5
	draw_rect(Rect2(Vector2.ZERO, Vector2(VIEW_SIZE)), Color(0, 0, 0, 0.35 * clampf(t / 0.4, 0.0, 1.0)))
	var r := 170.0
	draw_circle(c, r, Color(0, 0, 0, 0.45))
	draw_arc(c, r, 0.0, TAU, 96, Color(1, 1, 1, 0.12), 10.0, true)
	var start := -PI * 0.5
	draw_arc(c, r, start, start + TAU * clampf(t / total, 0.0, 1.0), 96, UITheme.T_ORANGE, 10.0, true)
	# Approach circle a fechar sobre o anel, um por segundo.
	draw_arc(c, lerpf(r * 1.9, r, p), 0.0, TAU, 96, Color(1, 1, 1, 0.55 * p), 6.0, true)
	# O número entra grande e assenta.
	var pop := 1.0 + 0.35 * pow(1.0 - minf(p / 0.25, 1.0), 2.0)
	var size := int(200.0 * pop)
	var text := str(maxi(n, 1))
	draw_string_outline(_title, Vector2(0, c.y + size * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, size, 12,
		Color(0, 0, 0, 0.6))
	draw_string(_title, Vector2(0, c.y + size * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, size, Color.WHITE)
	draw_string(_mono, Vector2(0, c.y + r + 70.0), "GET READY", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 34,
		Color(1, 1, 1, 0.7))


# --- Fundo -----------------------------------------------------------------------------

func _draw_background() -> void:
	if game == null:
		return
	var full := Rect2(Vector2.ZERO, Vector2(VIEW_SIZE))
	_bg_layer.draw_rect(full, Color(0.02, 0.025, 0.04))
	if _bg:
		var ts := _bg.get_size()
		var k := maxf(full.size.x / ts.x, full.size.y / ts.y)
		var src := full.size / k
		_bg_layer.draw_texture_rect_region(_bg, full, Rect2((ts - src) * 0.5, src))
	var dim: float = Settings.get_value("osu/background_dim")
	if game.beatmap.is_break(game.clock) or game.phase == OsuGame.Phase.INTRO:
		dim *= 0.75
	_bg_layer.draw_rect(full, Color(0, 0, 0, dim))


## Corpos dos sliders visíveis (os mais antigos por cima). O corpo cresce a
## partir da cabeça quando aparece e encolhe atrás da bola (como no osu!).
func _update_bodies() -> void:
	var used := 0
	if game.phase != OsuGame.Phase.RESULTS:
		var bm := game.beatmap
		var clock := game.clock
		var preempt := bm.preempt()
		var objects := bm.objects
		var last := game._first
		while last < objects.size() and float(objects[last].time) - preempt <= clock:
			last += 1
		var skin := game.skin
		for i in range(last - 1, maxi(game._first - 12, 0) - 1, -1):
			var o: Dictionary = objects[i]
			if int(o.type) != OsuBeatmap.SLIDER:
				continue
			var s: Dictionary = game.states[i]
			# Como no osu!: quando o slider acaba, o corpo some logo (já foi "comido" pela bola).
			if s.judged or clock >= float(o.end_time):
				continue
			var alpha := _fade(o, clock, preempt)
			if alpha <= 0.0:
				continue
			var length := float(o.length)
			var t := float(o.time)
			var to := length * clampf((clock - (t - preempt)) / (preempt * 0.35), 0.0, 1.0)
			var from := 0.0
			# Na última passagem o corpo encolhe atrás da bola (snaking out).
			var repeats := int(o.repeats)
			var last_start := t + float(o.span_duration) * (repeats - 1)
			if clock > last_start:
				var p := clampf((clock - last_start) / float(o.span_duration), 0.0, 1.0)
				if repeats % 2 == 1:
					from = p * length
				else:
					to = minf(to, (1.0 - p) * length)
			if to - from < 0.5:
				continue
			var colour := _colour(o)
			var border := skin.slider_border if skin.name != "" else colour.lightened(0.15)
			var track: Color = skin.slider_track if skin.slider_track != null else colour.darkened(0.55)
			if skin.name == "":
				track = Color(0.05, 0.05, 0.07)
			if used >= _bodies.size():
				var body := SliderBody.new()
				_bodies_root.add_child(body)
				_bodies.append(body)
			var b := _bodies[used]
			_bodies_root.move_child(b, used)
			b.show_body(_path_points(o, from, to), _radius_px(), border, track, alpha)
			used += 1
	for k in range(used, _bodies.size()):
		_bodies[k].visible = false


## Pontos do caminho (no ecrã) entre as distâncias `from` e `to`.
func _path_points(o: Dictionary, from: float, to: float) -> PackedVector2Array:
	var path: PackedVector2Array = o.path
	var cum: PackedFloat32Array = o.cum
	var out := PackedVector2Array([osu_to_view(OsuBeatmap.point_at(o, from))])
	var last_added := -1
	for k in path.size():
		if cum[k] > from and cum[k] < to:
			if last_added < 0 or k - last_added >= 1:
				out.append(osu_to_view(path[k]))
				last_added = k
	out.append(osu_to_view(OsuBeatmap.point_at(o, to)))
	return out


# --- Objetos -------------------------------------------------------------------------------

func _radius_px() -> float:
	return game.beatmap.radius() * SCALE


## Escala das imagens de círculo (as do osu! têm 128 px de diâmetro para raio 64).
func _circle_scale() -> float:
	return game.beatmap.radius() / 64.0 * SCALE


func _colour(obj: Dictionary) -> Color:
	return game.skin.combo_colour(int(obj.combo_index), game.beatmap.colours)


func _draw_objects() -> void:
	var bm := game.beatmap
	var clock := game.clock
	var preempt := bm.preempt()
	var objects := bm.objects
	# Do mais tardio para o mais cedo: os primeiros ficam por cima.
	var last := game._first
	while last < objects.size() and float(objects[last].time) - preempt <= clock:
		last += 1
	var start := maxi(game._first - 12, 0)
	for i in range(last - 1, start - 1, -1):
		var o: Dictionary = objects[i]
		var s: Dictionary = game.states[i]
		if s.judged and clock - float(s.judge_time) > 0.35:
			continue
		match int(o.type):
			OsuBeatmap.CIRCLE:
				_draw_circle_object(o, s, clock, preempt)
			OsuBeatmap.SLIDER:
				_draw_slider(o, s, clock, preempt)
			OsuBeatmap.SPINNER:
				_draw_spinner(o, s, clock)


func _fade(o: Dictionary, clock: float, preempt: float) -> float:
	var t := float(o.time)
	if "HD" in game.mods:
		# Hidden: aparece em 40% da aproximação e desaparece logo a seguir (os sliders
		# vão desaparecendo até ao fim).
		var appear := clampf((clock - (t - preempt)) / (preempt * 0.4), 0.0, 1.0)
		var out_start := t - preempt * 0.6
		var out_end := maxf(float(o.end_time), t - preempt * 0.3)
		return appear * (1.0 - clampf((clock - out_start) / maxf(out_end - out_start, 0.01), 0.0, 1.0))
	return clampf((clock - (t - preempt)) / game.beatmap.fade_in(), 0.0, 1.0)


func _draw_circle_object(o: Dictionary, s: Dictionary, clock: float, preempt: float) -> void:
	var pos := osu_to_view(o.pos)
	var alpha := _fade(o, clock, preempt)
	var scale := 1.0
	if s.judged:
		var t := (clock - float(s.judge_time)) / 0.25
		if int(s.result) == OsuGame.MISS:
			alpha = 1.0 - clampf(t * 2.0, 0.0, 1.0)
		else:
			alpha = 1.0 - clampf(t, 0.0, 1.0)
			scale = 1.0 + 0.4 * clampf(t, 0.0, 1.0)
	pos += _shake_offset(s, clock)
	_hit_circle(pos, _colour(o), alpha, scale, int(o.combo_number), not s.judged)
	if not s.judged and clock < float(o.time):
		_approach(pos, _colour(o), alpha, clock, float(o.time), preempt)


func _shake_offset(s: Dictionary, clock: float) -> Vector2:
	var t := clock - float(s.shake)
	if t < 0.0 or t > 0.25:
		return Vector2.ZERO
	return Vector2(sin(t * 80.0) * 10.0 * (1.0 - t / 0.25), 0)


## Círculo com número (imagens hitcircle + hitcircleoverlay + default-N, ou desenhado).
func _hit_circle(pos: Vector2, colour: Color, alpha: float, scale: float, number: int, show_number: bool,
		base := "hitcircle") -> void:
	var skin := game.skin
	var cs := _circle_scale() * scale
	var tex := skin.tex(base)
	if tex:
		_sprite(base, pos, cs, Color(colour, alpha))
		var overlay_name := base + "overlay"
		if not skin.overlay_above_number:
			_sprite(overlay_name, pos, cs, Color(1, 1, 1, alpha))
		if show_number:
			_number(number, pos, cs * 0.8, alpha)
		if skin.overlay_above_number:
			_sprite(overlay_name, pos, cs, Color(1, 1, 1, alpha))
		return
	var r := _radius_px() * scale
	draw_circle(pos, r, Color(0.06, 0.06, 0.08, 0.92 * alpha))
	draw_arc(pos, r * 0.84, 0.0, TAU, 48, Color(colour, alpha), r * 0.2, true)
	draw_arc(pos, r * 0.97, 0.0, TAU, 48, Color(1, 1, 1, alpha), r * 0.07, true)
	draw_circle(pos, r * 0.62, Color(colour.darkened(0.55), 0.6 * alpha))
	if show_number:
		_number(number, pos, cs * 0.8, alpha)


func _approach(pos: Vector2, colour: Color, alpha: float, clock: float, time: float, preempt: float) -> void:
	if "HD" in game.mods:
		return
	var k := clampf((time - clock) / preempt, 0.0, 1.0)
	var scale := 1.0 + 3.0 * k
	if game.skin.tex("approachcircle"):
		_sprite("approachcircle", pos, _circle_scale() * scale, Color(colour, alpha))
	else:
		draw_arc(pos, _radius_px() * scale, 0.0, TAU, 64, Color(colour.lightened(0.2), alpha), 4.0, true)


func _number(n: int, pos: Vector2, scale: float, alpha: float) -> void:
	var skin := game.skin
	var text := str(n)
	var prefix := skin.hit_circle_prefix
	if skin.tex(prefix + "-0"):
		_digits(prefix, text, pos, scale, skin.hit_circle_overlap, alpha, 0.5)
		return
	var fs := int(_radius_px() * 0.95)
	var w := _title.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(_title, pos + Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6,
		Color(0, 0, 0, 0.5 * alpha))
	draw_string(_title, pos + Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, alpha))


## Escreve números com as imagens prefixo-0..9 (centrado em `pos` se align = 0.5).
func _digits(prefix: String, text: String, pos: Vector2, scale: float, overlap: float, alpha: float, align := 0.5) -> float:
	var skin := game.skin
	var names: Array[String] = []
	var width := 0.0
	var count := 0
	for c in text:
		var n := prefix + "-" + ({",": "comma", ".": "dot", "%": "percent", "x": "x"}.get(c, c) as String)
		names.append(n)
		var t := skin.tex(n)
		if t:
			width += t.get_width() * skin.tex_scale(n) * scale
			count += 1
	# A sobreposição (skin.ini) só conta entre dígitos, não à volta de um só.
	width -= overlap * scale * maxi(count - 1, 0)
	var x := pos.x - width * align
	for n in names:
		var t := skin.tex(n)
		if t == null:
			continue
		var w := t.get_width() * skin.tex_scale(n) * scale
		_sprite(n, Vector2(x + w * 0.5, pos.y), scale, Color(1, 1, 1, alpha))
		x += w - overlap * scale
	return width


func _draw_slider(o: Dictionary, s: Dictionary, clock: float, preempt: float) -> void:
	var alpha := _fade(o, clock, preempt)
	if s.judged:
		alpha = 1.0 - clampf((clock - float(s.judge_time)) / 0.25, 0.0, 1.0)
	if alpha <= 0.0:
		return
	# O corpo é desenhado por _update_bodies (camada por baixo).
	var colour := _colour(o)
	var skin := game.skin
	var r := _radius_px()
	var path: PackedVector2Array = o.path
	var pts := PackedVector2Array([osu_to_view(path[0]), osu_to_view(path[mini(3, path.size() - 1)]),
		osu_to_view(path[maxi(path.size() - 4, 0)]), osu_to_view(path[path.size() - 1])])
	# Círculo do fim (quando o corpo já chegou lá).
	var grown := clampf((clock - (float(o.time) - preempt)) / (preempt * 0.35), 0.0, 1.0)
	if grown >= 1.0 and not s.judged:
		var tail := osu_to_view(o.end_pos)
		if skin.tex("sliderendcircle"):
			_sprite("sliderendcircle", tail, _circle_scale(), Color(colour, alpha))
			if skin.tex("sliderendcircleoverlay"):
				_sprite("sliderendcircleoverlay", tail, _circle_scale(), Color(1, 1, 1, alpha))
	# Ticks ainda por apanhar.
	var checkpoints: Array = o.checkpoints
	for k in range(int(s.cp), checkpoints.size()):
		var cp: Dictionary = checkpoints[k]
		if cp.kind != "tick":
			continue
		var tp := osu_to_view(cp.pos)
		if skin.tex("sliderscorepoint"):
			_sprite("sliderscorepoint", tp, _circle_scale(), Color(1, 1, 1, alpha))
		else:
			draw_circle(tp, r * 0.14, Color(1, 1, 1, 0.85 * alpha))
	# Setas de repetição.
	var repeats := int(o.repeats)
	if repeats > 1:
		var elapsed_spans := int(clampf((clock - float(o.time)) / float(o.span_duration), 0.0, repeats))
		if elapsed_spans < repeats - 1:
			var at_end := elapsed_spans % 2 == 0
			var tip := pts[pts.size() - 1] if at_end else pts[0]
			var prev := pts[2] if at_end else pts[1]
			var ang := (prev - tip).angle()
			if skin.tex("reversearrow"):
				_sprite("reversearrow", tip, _circle_scale(), Color(1, 1, 1, alpha), ang)
			else:
				var d := Vector2.from_angle(ang)
				var side := d.orthogonal()
				draw_polyline(PackedVector2Array([tip - d * r * 0.25 + side * r * 0.4, tip + d * r * 0.25,
					tip - d * r * 0.25 - side * r * 0.4]), Color(1, 1, 1, alpha), r * 0.14, true)
	# Cabeça (até ser carregada).
	var head := osu_to_view(o.pos) + _shake_offset(s, clock)
	if not s.head_done:
		_hit_circle(head, colour, alpha, 1.0, int(o.combo_number), true, "sliderstartcircle" if skin.tex("sliderstartcircle") else "hitcircle")
		if clock < float(o.time):
			_approach(head, colour, alpha, clock, float(o.time), preempt)
	elif int(s.head_result) != OsuGame.MISS:
		var t := clampf((clock - float(o.time)) / 0.25, 0.0, 1.0)
		if t < 1.0:
			_hit_circle(head, colour, 1.0 - t, 1.0 + 0.4 * t, int(o.combo_number), false)
	# Bola e círculo de seguimento.
	if clock >= float(o.time) and clock <= float(o.end_time):
		var ball := osu_to_view(OsuBeatmap.slider_ball(o, clock))
		var balls := skin.frame_names("sliderb", false)
		if not balls.is_empty():
			var frame: String = balls[int(clock * 30.0) % balls.size()]
			var tint := colour if skin.allow_ball_tint or skin.name == "" else Color.WHITE
			_sprite(frame, ball, _circle_scale(), Color(tint, 1.0))
		else:
			draw_circle(ball, r * 0.9, Color(1, 1, 1, 0.95))
			draw_circle(ball, r * 0.6, Color(colour, 1.0))
		if s.tracking:
			if skin.tex("sliderfollowcircle"):
				_sprite("sliderfollowcircle", ball, _circle_scale(), Color(1, 1, 1, 0.9))
			else:
				draw_arc(ball, r * 2.4, 0.0, TAU, 64, Color(colour.lightened(0.3), 0.9), 5.0, true)


func _draw_spinner(o: Dictionary, s: Dictionary, clock: float) -> void:
	if clock < float(o.time) - 0.3:
		return
	var alpha := clampf((clock - (float(o.time) - 0.3)) / 0.3, 0.0, 1.0)
	if s.judged:
		alpha = 1.0 - clampf((clock - float(s.judge_time)) / 0.25, 0.0, 1.0)
	var center := osu_to_view(OsuBeatmap.PLAYFIELD * 0.5)
	var duration := maxf(float(o.end_time) - float(o.time), 0.1)
	var required := maxf(1.0, duration / game.beatmap.rate * OsuGame.SPIN_RATE)
	var progress := clampf(float(s.spin) / TAU / required, 0.0, 1.0)
	var spin: float = s.spin
	var k := clampf((clock - float(o.time)) / duration, 0.0, 1.0)
	var skin := game.skin
	var big := 384.0 * SCALE * 0.5
	if skin.tex("spinner-bottom") or skin.tex("spinner-circle"):
		if skin.tex("spinner-background"):
			_sprite("spinner-background", center, UI_SCALE, Color(1, 1, 1, alpha))
		for part in [["spinner-bottom", 0.2], ["spinner-top", 0.5], ["spinner-middle2", 1.0], ["spinner-circle", 1.0]]:
			if skin.tex(part[0]):
				_sprite(part[0], center, UI_SCALE, Color(1, 1, 1, alpha), spin * float(part[1]))
		if skin.tex("spinner-approachcircle"):
			_sprite("spinner-approachcircle", center, UI_SCALE * (1.0 - k), Color(1, 1, 1, alpha))
	else:
		draw_arc(center, big, 0.0, TAU, 96, Color(1, 1, 1, 0.25 * alpha), 6.0, true)
		for seg in 6:
			var a0 := spin + seg * TAU / 6.0
			draw_arc(center, big * 0.82, a0, a0 + 0.6, 24, Color(UITheme.T_ORANGE, 0.8 * alpha), 14.0, true)
		draw_arc(center, big * 0.95 * (1.0 - k) + 8.0, 0.0, TAU, 96, Color(1, 1, 1, 0.8 * alpha), 3.0, true)
		draw_arc(center, big * 0.6, -PI / 2.0, -PI / 2.0 + TAU * progress, 64, Color(0.45, 1.0, 0.5, alpha), 10.0, true)
	var label := "%.1f / %d" % [float(s.spin) / TAU, int(ceil(required))]
	draw_string(_title, center + Vector2(-200, big * 0.65), "SPIN!", HORIZONTAL_ALIGNMENT_CENTER, 400, 44, Color(1, 1, 1, alpha))
	draw_string(_mono, center + Vector2(-200, big * 0.65 + 34), label, HORIZONTAL_ALIGNMENT_CENTER, 400, 22, Color(1, 1, 1, 0.8 * alpha))


func _draw_follow_points() -> void:
	var bm := game.beatmap
	var clock := game.clock
	var objects := bm.objects
	var skin := game.skin
	for i in range(maxi(game._first - 1, 1), objects.size()):
		var b: Dictionary = objects[i]
		if float(b.time) - bm.preempt() > clock:
			break
		var a: Dictionary = objects[i - 1]
		if b.new_combo or int(a.type) == OsuBeatmap.SPINNER or int(b.type) == OsuBeatmap.SPINNER:
			continue
		if clock > float(b.time):
			continue
		var p0 := osu_to_view(a.end_pos)
		var p1 := osu_to_view(b.pos)
		var dist := p0.distance_to(p1)
		var r := _radius_px()
		if dist < r * 2.5:
			continue
		var dir := (p1 - p0) / dist
		var d := r * 1.2
		while d < dist - r * 1.2:
			var pt := p0 + dir * d
			var t_at := lerpf(float(a.end_time), float(b.time), d / dist)
			var alpha := clampf((clock - (t_at - bm.preempt())) / 0.3, 0.0, 1.0) * clampf((t_at - clock) / 0.2 + 1.0, 0.0, 1.0)
			if alpha > 0.01:
				if skin.tex("followpoint"):
					_sprite("followpoint", pt, UI_SCALE * 0.7, Color(1, 1, 1, alpha * 0.8), dir.angle())
				else:
					var side := dir.orthogonal() * 7.0
					draw_colored_polygon(PackedVector2Array([pt + dir * 9.0, pt + side, pt - side]), Color(1, 1, 1, alpha * 0.55))
			d += 32.0 * SCALE


func _draw_judgments() -> void:
	var skin := game.skin
	var clock := game.clock
	for j in game.judgments:
		var age := clock - float(j.time)
		if age > 0.7 or age < 0.0:
			continue
		var res: int = j.result
		if res == OsuGame.HIT300 and not skin.tex("hit300") and skin.name == "":
			continue
		var pos := osu_to_view(j.pos)
		var a := clampf(1.0 - (age - 0.4) / 0.3, 0.0, 1.0)
		var pop := 1.0 + maxf(0.0, 0.12 - age) * 3.0
		var name: String = ["hit300", "hit100", "hit50", "hit0"][res]
		var frames := skin.frame_names(name)
		if not frames.is_empty():
			var frame: String = frames[mini(int(age * 30.0), frames.size() - 1)]
			_sprite(frame, pos + Vector2(0, -age * 20.0 if res == OsuGame.MISS else 0.0), UI_SCALE * 0.8 * pop,
				Color(1, 1, 1, a))
		else:
			var text: String = ["300", "100", "50", "✕"][res]
			var fs := int(44 * pop)
			draw_string_outline(_title, pos + Vector2(-100, -_radius_px() - 4.0 + age * 12.0), text, HORIZONTAL_ALIGNMENT_CENTER,
				200, fs, 8, Color(0, 0, 0, 0.6 * a))
			draw_string(_title, pos + Vector2(-100, -_radius_px() - 4.0 + age * 12.0), text, HORIZONTAL_ALIGNMENT_CENTER, 200,
				fs, Color(JUDGE_COLORS[res], a))


func _draw_cursor() -> void:
	if int(Settings.get_value("osu/cursor_mode")) == 0 or not game.aim_on_screen:
		return
	var skin := game.skin
	var trail := skin.tex("cursortrail")
	for i in _trail.size():
		var a := float(i + 1) / _trail.size() * 0.5
		if trail:
			_sprite("cursortrail", _trail[i], UI_SCALE, Color(1, 1, 1, a))
		else:
			draw_circle(_trail[i], 10.0 * a + 2.0, Color(UITheme.T_ORANGE, a * 0.8))
	var pos := game.aim_view
	var expand := 1.25 if game.keys_held and skin.cursor_expand else 1.0
	if skin.tex("cursor"):
		_sprite("cursor", pos, UI_SCALE * expand, Color.WHITE)
		if skin.tex("cursormiddle"):
			_sprite("cursormiddle", pos, UI_SCALE, Color.WHITE)
	else:
		draw_circle(pos, 16.0 * expand, Color(UITheme.T_ORANGE, 0.35))
		draw_arc(pos, 16.0 * expand, 0.0, TAU, 32, Color(1, 1, 1, 0.95), 3.0, true)
		draw_circle(pos, 4.0, Color.WHITE)


# --- HUD ------------------------------------------------------------------------------

func _draw_hud() -> void:
	var skin := game.skin
	var w := float(VIEW_SIZE.x)
	var h := float(VIEW_SIZE.y)
	# Vida (canto superior esquerdo).
	if skin.tex("scorebar-bg"):
		_sprite_at("scorebar-bg", Vector2.ZERO, UI_SCALE, Color.WHITE)
	var bar_tex := skin.tex("scorebar-colour")
	if bar_tex:
		var sc := skin.tex_scale("scorebar-colour") * UI_SCALE
		var full := bar_tex.get_size()
		var shown := Vector2(full.x * clampf(game.health, 0.0, 1.0), full.y)
		draw_texture_rect_region(bar_tex, Rect2(Vector2(5, 16) * UI_SCALE, shown * sc), Rect2(Vector2.ZERO, shown))
	else:
		var bar := Rect2(30, 26, 640, 18)
		draw_rect(bar.grow(4), Color(0, 0, 0, 0.5))
		var col := Color(0.45, 1.0, 0.55).lerp(UITheme.KILL_RED, clampf((0.4 - game.health) / 0.4, 0.0, 1.0))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(game.health, 0.0, 1.0), bar.size.y)), col)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(game.health, 0.0, 1.0), 4)), Color(1, 1, 1, 0.4))
	# Pontos e precisão (canto superior direito).
	var score_text := str(int(_shown_score)).lpad(8, "0")
	var acc_text := "%.2f%%" % (game.accuracy() * 100.0)
	if skin.tex(skin.score_prefix + "-0"):
		_digits(skin.score_prefix, score_text, Vector2(w - 24, 50), UI_SCALE * 0.75, skin.score_overlap, 1.0, 1.0)
		_digits(skin.score_prefix, acc_text, Vector2(w - 24, 118), UI_SCALE * 0.45, skin.score_overlap, 1.0, 1.0)
	else:
		draw_string_outline(_title, Vector2(w - 524, 78), score_text, HORIZONTAL_ALIGNMENT_RIGHT, 500, 72, 8, Color(0, 0, 0, 0.6))
		draw_string(_title, Vector2(w - 524, 78), score_text, HORIZONTAL_ALIGNMENT_RIGHT, 500, 72, Color.WHITE)
		draw_string_outline(_title, Vector2(w - 524, 126), acc_text, HORIZONTAL_ALIGNMENT_RIGHT, 500, 40, 6, Color(0, 0, 0, 0.6))
		draw_string(_title, Vector2(w - 524, 126), acc_text, HORIZONTAL_ALIGNMENT_RIGHT, 500, 40, Color(1, 1, 1, 0.9))
	# Progresso da música (tarte).
	var pie_c := Vector2(w - 230, 112)
	var start := game.beatmap.first_time()
	var progress := clampf((game.clock - start) / maxf(game.song_length() - start, 0.1), 0.0, 1.0)
	draw_circle(pie_c, 18, Color(0, 0, 0, 0.4))
	if progress > 0.0:
		var pts := PackedVector2Array([pie_c])
		for k in 33:
			pts.append(pie_c + Vector2.from_angle(-PI / 2.0 + TAU * progress * k / 32.0) * 18.0)
		draw_colored_polygon(pts, Color(1, 1, 1, 0.75))
	draw_arc(pie_c, 18, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 2.0, true)
	# Combo (canto inferior esquerdo).
	var combo_text := "%dx" % game.combo
	if skin.tex(skin.combo_prefix + "-0"):
		_digits(skin.combo_prefix, combo_text, Vector2(24, h - 50), UI_SCALE * 0.9, skin.combo_overlap, 1.0, 0.0)
	else:
		draw_string_outline(_title, Vector2(28, h - 30), combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 92, 10, Color(0, 0, 0, 0.6))
		draw_string(_title, Vector2(28, h - 30), combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 92, Color.WHITE)
	_draw_error_bar(w, h)
	# Mods ativos, por baixo da precisão.
	var mx := w - 24.0
	for i in range(game.mods.size() - 1, -1, -1):
		var id: String = game.mods[i]
		var col: Color = OsuMods.GROUP_COLORS[int(OsuMods.info(id).group)]
		var r := Rect2(mx - 64.0, 150.0, 64.0, 36.0)
		draw_rect(r, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 4.0)), col)
		draw_string(_title, Vector2(r.position.x, r.end.y - 7.0), id, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26, col.lightened(0.3))
		mx -= 72.0
	if game._auto:
		draw_string(_title, Vector2(0, 120), "AUTO", HORIZONTAL_ALIGNMENT_CENTER, w, 40, Color(0.55, 0.7, 1.0, 0.8))


## Flashlight: tudo escuro menos um círculo à volta da mira (mais pequeno com o combo).
func _draw_flashlight() -> void:
	if _fl_tex == null:
		var g := Gradient.new()
		g.set_offset(0, 0.55)
		g.set_color(0, Color(0, 0, 0, 0))
		g.set_color(1, Color(0, 0, 0, 1))
		_fl_tex = GradientTexture2D.new()
		_fl_tex.gradient = g
		_fl_tex.fill = GradientTexture2D.FILL_RADIAL
		_fl_tex.fill_from = Vector2(0.5, 0.5)
		_fl_tex.fill_to = Vector2(1.0, 0.5)
		_fl_tex.width = 256
		_fl_tex.height = 256
	var size_k := 1.0 if game.combo < 100 else (0.86 if game.combo < 200 else 0.72)
	var r := 210.0 * SCALE * size_k
	var c := game.aim_view if game.aim_on_screen else Vector2(VIEW_SIZE) * 0.5
	var box := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
	draw_texture_rect(_fl_tex, box, false)
	var full := Rect2(Vector2.ZERO, Vector2(VIEW_SIZE))
	var black := Color(0, 0, 0, 1)
	draw_rect(Rect2(0, 0, full.size.x, maxf(box.position.y, 0.0)), black)
	draw_rect(Rect2(0, box.end.y, full.size.x, maxf(full.size.y - box.end.y, 0.0)), black)
	draw_rect(Rect2(0, box.position.y, maxf(box.position.x, 0.0), box.size.y), black)
	draw_rect(Rect2(box.end.x, box.position.y, maxf(full.size.x - box.end.x, 0.0), box.size.y), black)


func _draw_error_bar(w: float, h: float) -> void:
	var win := game.beatmap.hit_windows()
	var half := 210.0
	var cx := w * 0.5
	var y := h - 26.0
	draw_rect(Rect2(cx - half, y - 3, half * 2, 6), Color(JUDGE_COLORS[2], 0.5))
	draw_rect(Rect2(cx - half * win.y / win.z, y - 3, half * 2 * win.y / win.z, 6), Color(JUDGE_COLORS[1], 0.65))
	draw_rect(Rect2(cx - half * win.x / win.z, y - 3, half * 2 * win.x / win.z, 6), Color(JUDGE_COLORS[0], 0.8))
	draw_rect(Rect2(cx - 1.5, y - 14, 3, 28), Color.WHITE)
	var now := Time.get_ticks_msec() / 1000.0
	for e in _errors:
		var age := now - e.y
		if age > 6.0:
			continue
		var x := cx + clampf(e.x / win.z, -1.0, 1.0) * half
		draw_rect(Rect2(x - 2, y - 12, 4, 24), Color(1, 1, 1, 1.0 - age / 6.0))


func _draw_intro() -> void:
	var w := float(VIEW_SIZE.x)
	var h := float(VIEW_SIZE.y)
	var bm := game.beatmap
	var clock := game.clock
	var before := bm.first_time() - bm.preempt() - clock
	if before > 0.0:
		var a := clampf(before / 0.6, 0.0, 1.0)
		draw_string_outline(_title, Vector2(0, h * 0.42), game.beatmap.title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, 72, 10,
			Color(0, 0, 0, 0.6 * a))
		draw_string(_title, Vector2(0, h * 0.42), game.beatmap.title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, 72, Color(1, 1, 1, a))
		draw_string(_bold, Vector2(0, h * 0.42 + 54), "%s  ·  [%s]" % [game.beatmap.artist, game.beatmap.version],
			HORIZONTAL_ALIGNMENT_CENTER, w, 30, Color(UITheme.T_ORANGE, a))
	if game.can_skip() and before > 2.5:
		var r := Rect2(w - 420, h - 170, 380, 110)
		_buttons["skip"] = r
		if game.skin.tex("play-skip-0") or game.skin.tex("play-skip"):
			var frames := game.skin.frame_names("play-skip")
			var frame: String = frames[int(Time.get_ticks_msec() / 60.0) % frames.size()]
			_sprite(frame, r.get_center(), UI_SCALE, Color.WHITE)
		else:
			draw_rect(r, Color(0, 0, 0, 0.55))
			draw_rect(r, Color(UITheme.T_ORANGE, 0.9), false, 3.0)
			draw_string(_title, Vector2(r.position.x, r.position.y + 62), "SKIP ▶", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 48, Color.WHITE)
			draw_string(_mono, Vector2(r.position.x, r.position.y + 94), "[SPACE]", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18,
				Color(1, 1, 1, 0.6))
	if bm.is_break(clock):
		draw_string(_title, Vector2(0, h * 0.5), "BREAK", HORIZONTAL_ALIGNMENT_CENTER, w, 52, Color(1, 1, 1, 0.5))


# --- Pausa, falhar, resultados ------------------------------------------------------------

## Pausa: só escurece o ecrã e mostra "PAUSED" (o menu é 2D, na janela do jogo).
func _draw_pause() -> void:
	var full := Rect2(Vector2.ZERO, Vector2(VIEW_SIZE))
	draw_rect(full, Color(0, 0, 0, 0.6))
	if game.skin.tex("pause-overlay"):
		_cover(game.skin.tex("pause-overlay"), full, Color.WHITE)
	else:
		draw_string(_title, Vector2(0, VIEW_SIZE.y * 0.5 + 40), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 120,
			Color(1, 1, 1, 0.85))


## Falhar: fundo/título no ecrã; os botões estão no menu 2D do jogo.
func _draw_fail() -> void:
	var full := Rect2(Vector2.ZERO, Vector2(VIEW_SIZE))
	draw_rect(full, Color(0.15, 0, 0, 0.55))
	if game.skin.tex("fail-background"):
		_cover(game.skin.tex("fail-background"), full, Color.WHITE)
	else:
		var y := VIEW_SIZE.y * 0.5 + 50
		draw_string_outline(_title, Vector2(0, y), "FAILED", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 150, 14, Color(0, 0, 0, 0.7))
		draw_string(_title, Vector2(0, y), "FAILED", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 150, Color(1.0, 0.3, 0.55))


func _draw_results() -> void:
	var w := float(VIEW_SIZE.x)
	var r := game.result
	draw_rect(Rect2(0, 0, w, VIEW_SIZE.y), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(0, 0, w, 150), Color(0, 0, 0, 0.7))
	draw_string(_title, Vector2(60, 80), game.beatmap.title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w - 120, 58, Color.WHITE)
	draw_string(_bold, Vector2(62, 124), "%s  ·  [%s]  ·  mapped by %s" % [game.beatmap.artist, game.beatmap.version,
		game.beatmap.creator], HORIZONTAL_ALIGNMENT_LEFT, w - 120, 28, Color(1, 1, 1, 0.7))
	var grade: String = r.get("grade", "D")
	var skin := game.skin
	var gx := w - 520.0
	var rank_name := "ranking-%s" % ("X" if grade == "SS" else grade)
	if skin.tex(rank_name):
		_sprite(rank_name, Vector2(gx + 220, 470), UI_SCALE * 0.8, Color.WHITE)
	else:
		var gcol: Color = {"SS": Color(1, 0.9, 0.4), "S": Color(1.0, 0.82, 0.3), "A": Color(0.45, 1.0, 0.5),
			"B": Color(0.45, 0.7, 1.0), "C": Color(0.8, 0.45, 1.0), "D": Color(1.0, 0.3, 0.3)}.get(grade, Color.WHITE)
		draw_string_outline(_title, Vector2(gx, 620), grade, HORIZONTAL_ALIGNMENT_CENTER, 440, 400, 16, Color(0, 0, 0, 0.6))
		draw_string(_title, Vector2(gx, 620), grade, HORIZONTAL_ALIGNMENT_CENTER, 440, 400, gcol)
	if game.record:
		draw_string(_bold, Vector2(gx, 700), "NEW RECORD!", HORIZONTAL_ALIGNMENT_CENTER, 440, 44, UITheme.CROSSHAIR_GREEN)
	draw_string(_mono, Vector2(80, 230), "SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.5))
	draw_string(_title, Vector2(80, 330), str(int(r.get("score", 0))).lpad(8, "0"), HORIZONTAL_ALIGNMENT_LEFT, -1, 120, Color.WHITE)
	var counts: Array = r.get("counts", [0, 0, 0, 0])
	var labels := ["300", "100", "50", "MISS"]
	for k in 4:
		var x := 80.0 + (k % 2) * 380.0
		var y := 420.0 + floorf(k / 2.0) * 120.0
		var name: String = ["hit300", "hit100", "hit50", "hit0"][k]
		var frames := skin.frame_names(name)
		if not frames.is_empty():
			_sprite(frames[0], Vector2(x + 60, y + 40), UI_SCALE * 0.7, Color.WHITE)
		else:
			draw_string(_title, Vector2(x, y + 60), labels[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 54, JUDGE_COLORS[k])
		draw_string(_title, Vector2(x + 140, y + 62), "%dx" % int(counts[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color.WHITE)
	draw_string(_mono, Vector2(80, 700), "MAX COMBO", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.5))
	draw_string(_title, Vector2(80, 776), "%dx" % int(r.get("max_combo", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 80, Color.WHITE)
	draw_string(_mono, Vector2(460, 700), "ACCURACY", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.5))
	draw_string(_title, Vector2(460, 776), "%.2f%%" % (float(r.get("accuracy", 0.0)) * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 80,
		Color.WHITE)
	_draw_timeline(Rect2(80, 830, 760, 60))
	var y0 := 760.0
	for b in [["retry", "RETRY  [R]", UITheme.T_ORANGE], ["back", "CONTINUE  [ENTER]", Color(0.45, 1.0, 0.5)]]:
		var rect := Rect2(w - 640, y0, 560, 100)
		var hot := rect.has_point(game.aim_view)
		var col: Color = b[2]
		draw_rect(rect, Color(0, 0, 0, 0.7))
		draw_rect(rect, Color(col, 1.0 if hot else 0.6), false, 6.0 if hot else 3.0)
		if hot:
			draw_rect(rect, Color(col, 0.2))
		draw_string(_title, Vector2(rect.position.x, rect.position.y + 68), b[1], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 50,
			Color.WHITE if hot else col)
		_buttons[b[0]] = rect
		y0 += 130.0


func _draw_timeline(r: Rect2) -> void:
	draw_rect(r, Color(0, 0, 0, 0.5))
	var length := game.song_length()
	for e in game.timeline:
		var x := r.position.x + clampf(e.x / length, 0.0, 1.0) * r.size.x
		var res := int(e.y)
		var hgt := r.size.y * (0.9 if res == OsuGame.MISS else 0.5 - res * 0.12)
		draw_rect(Rect2(x - 1, r.end.y - hgt, 2, hgt), Color(JUDGE_COLORS[res], 0.9))


# --- Utilitários -----------------------------------------------------------------------------

## Imagem da skin centrada em `pos`, com a escala dos píxeis "SD" do osu!.
func _sprite(name: String, pos: Vector2, scale: float, modulate: Color, rotation := 0.0) -> void:
	var t := game.skin.tex(name)
	if t == null:
		return
	_texture_centered(t, pos, scale * game.skin.tex_scale(name), modulate, rotation)


func _sprite_at(name: String, top_left: Vector2, scale: float, modulate: Color) -> void:
	var t := game.skin.tex(name)
	if t:
		draw_texture_rect(t, Rect2(top_left, t.get_size() * game.skin.tex_scale(name) * scale), false, modulate)


func _texture_centered(t: Texture2D, pos: Vector2, scale: float, modulate: Color, rotation := 0.0) -> void:
	var size_px := t.get_size() * scale
	if rotation != 0.0:
		draw_set_transform(pos, rotation, Vector2.ONE)
		draw_texture_rect(t, Rect2(-size_px * 0.5, size_px), false, modulate)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect(t, Rect2(pos - size_px * 0.5, size_px), false, modulate)


func _cover(tex: Texture2D, r: Rect2, modulate: Color) -> void:
	var ts := tex.get_size()
	var k := maxf(r.size.x / ts.x, r.size.y / ts.y)
	var src := r.size / k
	draw_texture_rect_region(tex, r, Rect2((ts - src) * 0.5, src), modulate)
