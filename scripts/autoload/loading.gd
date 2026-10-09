extends CanvasLayer
## Ecrã de loading entre o lobby e o jogo (e ao tentar de novo).
##
## Aparece logo (antes de o Godot congelar a carregar), carrega a cena numa
## thread e, ao mesmo tempo, a música do mapa (fica na cache do Game). Só sai
## depois de a cena nova ter desenhado os primeiros frames, que é quando se
## compilam os shaders e o jogo engasga; assim nunca se vê o ecrã cinzento.

const MIN_TIME := 0.45
const SETTLE_FRAMES := 4
const FADE_OUT := 0.3

var _root: Control
var _bg: TextureRect
var _title: Label
var _info: Label
var _status: Label
var _spinner: Control
var _bar: Control
var _progress := 0.0
var _shown_progress := 0.0
var _busy := false
var _spin := 0.0


func _ready() -> void:
	# Por cima do "flash" preto das cenas (110); o contador de FPS fica por cima disto.
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func is_busy() -> bool:
	return _busy


## Muda para `scene_path` com o ecrã de loading. `map` (opcional) mostra a
## música que vai tocar e pré-carrega o áudio dela.
func go(scene_path: String, map := {}) -> void:
	if _busy:
		return
	_busy = true
	_show_info(map)
	_progress = 0.0
	_shown_progress = 0.0
	_root.modulate.a = 1.0
	visible = true
	var start := Time.get_ticks_msec()
	# Dois frames para o ecrã de loading chegar mesmo a ser desenhado.
	await get_tree().process_frame
	await get_tree().process_frame

	ResourceLoader.load_threaded_request(scene_path)
	var audio_task := -1
	if not map.is_empty() and map.has("audio"):
		audio_task = WorkerThreadPool.add_task(Game.preload_audio.bind(map))
	var progress := []
	while true:
		var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
		var scene_p: float = progress[0] if not progress.is_empty() else 0.0
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			scene_p = 1.0
		elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			push_error("Could not load %s" % scene_path)
			break
		var audio_done := audio_task < 0 or WorkerThreadPool.is_task_completed(audio_task)
		_progress = scene_p * 0.6 + (0.3 if audio_done else 0.0)
		if scene_p >= 1.0 and audio_done and Time.get_ticks_msec() - start >= MIN_TIME * 1000.0:
			break
		await get_tree().process_frame
	if audio_task >= 0:
		WorkerThreadPool.wait_for_task_completion(audio_task)

	_status.text = "STARTING"
	var packed := ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if packed:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(scene_path)
	# A cena nova faz o _ready e os primeiros frames (shaders) por baixo do loading.
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
		_progress = 0.9 + 0.1 * (i + 1) / SETTLE_FRAMES
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	await tween.finished
	visible = false
	_busy = false


func _process(delta: float) -> void:
	if not visible:
		return
	_spin += delta * 5.0
	_shown_progress = lerpf(_shown_progress, _progress, 1.0 - exp(-delta * 12.0))
	_spinner.queue_redraw()
	_bar.queue_redraw()


func _show_info(map: Dictionary) -> void:
	_status.text = "LOADING"
	if map.is_empty():
		_bg.texture = null
		_title.text = "os!strike"
		_info.text = "Back to the menu"
		return
	_bg.texture = Game.background_blur(map)
	_title.text = String(map.get("title", "")).to_upper()
	var stars := float(map.get("stars", 0.0)) * OsuMods.star_factor(OsuMods.active())
	var mods := OsuMods.active()
	var line := "%s  ·  [%s]  ·  mapped by %s  ·  ★%.1f" % [map.get("artist", ""), map.get("difficulty", ""),
		map.get("mapper", ""), stars]
	if not mods.is_empty():
		line += "  ·  +" + "".join(mods)
	_info.text = line


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var base := ColorRect.new()
	base.color = Color(0.02, 0.024, 0.032)
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(base)

	# Fundo do mapa desfocado e escuro.
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.modulate = Color(0.32, 0.32, 0.36)
	_root.add_child(_bg)

	# Sombra em baixo, para o texto se ler bem.
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.0))
	grad.set_color(1, Color(0, 0, 0, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0.35)
	tex.fill_to = Vector2(0, 1)
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	_root.add_child(shade)

	var column := VBoxContainer.new()
	column.anchor_left = 0.0
	column.anchor_right = 1.0
	column.anchor_top = 1.0
	column.anchor_bottom = 1.0
	column.offset_left = 70
	column.offset_right = -220
	column.offset_top = -190
	column.offset_bottom = -54
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 2)
	_root.add_child(column)

	_status = Label.new()
	_status.add_theme_font_override("font", UITheme.mono())
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", UITheme.T_ORANGE)
	column.add_child(_status)
	_title = Label.new()
	_title.add_theme_font_override("font", UITheme.din(700, 75))
	_title.add_theme_font_size_override("font_size", 56)
	_title.add_theme_color_override("font_color", UITheme.TEXT)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_title)
	_info = Label.new()
	_info.add_theme_font_override("font", UITheme.din(400, 100))
	_info.add_theme_font_size_override("font_size", 17)
	_info.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_info)

	# Anel a rodar (como um approach circle) no canto inferior direito.
	_spinner = Control.new()
	_spinner.anchor_left = 1.0
	_spinner.anchor_right = 1.0
	_spinner.anchor_top = 1.0
	_spinner.anchor_bottom = 1.0
	_spinner.offset_left = -150
	_spinner.offset_right = -60
	_spinner.offset_top = -150
	_spinner.offset_bottom = -60
	_spinner.draw.connect(_draw_spinner)
	_root.add_child(_spinner)

	# Barra de progresso fina em baixo.
	_bar = Control.new()
	_bar.anchor_left = 0.0
	_bar.anchor_right = 1.0
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_top = -4
	_bar.draw.connect(_draw_bar)
	_root.add_child(_bar)


func _draw_spinner() -> void:
	var c := _spinner.size * 0.5
	var r := minf(c.x, c.y) - 6.0
	_spinner.draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.12), 5.0, true)
	_spinner.draw_arc(c, r, _spin, _spin + TAU * 0.28, 32, UITheme.T_ORANGE, 5.0, true)
	_spinner.draw_arc(c, r * 0.62, -_spin * 0.7, -_spin * 0.7 + TAU * 0.18, 24, Color(1, 1, 1, 0.5), 3.0, true)
	var font := UITheme.mono()
	var text := "%d%%" % roundi(_shown_progress * 100.0)
	_spinner.draw_string(font, Vector2(0, c.y + 6), text, HORIZONTAL_ALIGNMENT_CENTER, _spinner.size.x, 16, UITheme.TEXT)


func _draw_bar() -> void:
	var w := _bar.size.x
	_bar.draw_rect(Rect2(0, 0, w, _bar.size.y), Color(1, 1, 1, 0.08))
	_bar.draw_rect(Rect2(0, 0, w * _shown_progress, _bar.size.y), UITheme.T_ORANGE)
