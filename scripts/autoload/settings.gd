extends Node
## Definições do jogador, guardadas em user://settings.cfg.
## As chaves têm a forma "secção/nome" (ex.: "audio/music_volume").
## `set_value` aplica logo a mudança e emite `changed`.

signal changed(key: String)

const PATH := "user://settings.cfg"

const WINDOW_MODES: Array[String] = ["Windowed", "Fullscreen", "Exclusive fullscreen"]
const ASPECTS: Array[String] = ["16:9", "16:10", "4:3", "5:4"]
const RESOLUTIONS_BY_ASPECT: Array = [
	[Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
		Vector2i(2560, 1440), Vector2i(3840, 2160)],
	[Vector2i(1280, 800), Vector2i(1440, 900), Vector2i(1680, 1050), Vector2i(1920, 1200), Vector2i(2560, 1600)],
	[Vector2i(800, 600), Vector2i(1024, 768), Vector2i(1280, 960), Vector2i(1440, 1080), Vector2i(1600, 1200)],
	[Vector2i(1280, 1024)],
]
## Como mostrar uma proporção diferente da do monitor em ecrã inteiro.
const SCALING_MODES: Array[String] = ["Stretched", "Black bars"]
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra", "Custom"]
const QUALITY_CUSTOM := 4
## Gráficos avançados: o que cada predefinição (Low/Medium/High/Ultra) põe.
## render_scale = resolução 3D; upscaler 0 bilinear, 1 FSR 1, 2 FSR 2; msaa
## 0..3 (off/2x/4x/8x); post_aa 0 off, 1 FXAA, 2 SMAA; anisotropic 0..4
## (off/2x/4x/8x/16x); screen_res = resolução do ecrã do osu! (0 720p .. 3 4K).
const QUALITY_PRESETS: Array[Dictionary] = [
	{"gfx/render_scale": 0.67, "gfx/upscaler": 1, "gfx/sharpness": 0.6, "gfx/msaa": 0, "gfx/post_aa": 0, "gfx/taa": false,
		"gfx/anisotropic": 1, "gfx/bloom": false, "gfx/fog": false, "gfx/ssao": false, "gfx/debanding": false,
		"gfx/screen_res": 0},
	{"gfx/render_scale": 0.85, "gfx/upscaler": 1, "gfx/sharpness": 0.6, "gfx/msaa": 0, "gfx/post_aa": 1, "gfx/taa": false,
		"gfx/anisotropic": 2, "gfx/bloom": true, "gfx/fog": false, "gfx/ssao": false, "gfx/debanding": false,
		"gfx/screen_res": 1},
	{"gfx/render_scale": 1.0, "gfx/upscaler": 0, "gfx/sharpness": 0.6, "gfx/msaa": 1, "gfx/post_aa": 0, "gfx/taa": false,
		"gfx/anisotropic": 3, "gfx/bloom": true, "gfx/fog": true, "gfx/ssao": false, "gfx/debanding": true,
		"gfx/screen_res": 1},
	{"gfx/render_scale": 1.0, "gfx/upscaler": 0, "gfx/sharpness": 0.6, "gfx/msaa": 2, "gfx/post_aa": 2, "gfx/taa": false,
		"gfx/anisotropic": 4, "gfx/bloom": true, "gfx/fog": true, "gfx/ssao": true, "gfx/debanding": true,
		"gfx/screen_res": 2},
]
const UPSCALER_NAMES: Array[String] = ["Bilinear", "AMD FSR 1.0", "AMD FSR 2.2"]
const MSAA_NAMES: Array[String] = ["Off", "2x", "4x", "8x"]
const POST_AA_NAMES: Array[String] = ["Off", "FXAA", "SMAA"]
const ANISOTROPIC_NAMES: Array[String] = ["Off", "2x", "4x", "8x", "16x"]
const SCREEN_RES_NAMES: Array[String] = ["720p", "1080p", "1440p", "4K"]
const SCREEN_RES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
## A interface é desenhada para esta altura lógica; a largura adapta-se à proporção.
const UI_HEIGHT := 720
## Graus por "count" do rato, igual ao m_yaw do Counter-Strike.
const M_YAW := 0.022
const FPS_LIMITS: Array[int] = [0, 60, 120, 144, 240]
## Hitsounds especiais (os restantes são ficheiros da pasta "sounds").
const HITSOUND_DEFAULT := "default"
const HITSOUND_NONE := "none"
const HITSOUND_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]

const DEFAULTS := {
	"audio/music_volume": 0.8,
	"audio/sfx_volume": 0.8,
	"audio/hitsound": HITSOUND_DEFAULT,
	"audio/hitsound_volume": 0.8,
	# Volume geral quando a janela do jogo não está ativa (0 = mudo).
	"audio/inactive_volume": 0.25,
	# Volume dos disparos e da troca de arma (relativo aos EFEITOS; 0 = mudo).
	"audio/weapon_volume": 1.0,
	# Discord Rich Presence (ver DiscordPresence).
	"discord/enabled": true,
	"discord/client_id": "",
	"video/window_mode": 0,
	"video/aspect": 0,
	"video/resolution": Vector2i(1280, 720),
	"video/scaling": 0,
	"video/quality": 2,
	# Gráficos avançados (ver QUALITY_PRESETS; os valores por defeito são os do High).
	"gfx/render_scale": 1.0,
	"gfx/upscaler": 0,
	"gfx/sharpness": 0.6,
	"gfx/msaa": 1,
	"gfx/post_aa": 0,
	"gfx/taa": false,
	"gfx/anisotropic": 3,
	"gfx/bloom": true,
	"gfx/fog": true,
	"gfx/ssao": false,
	"gfx/debanding": true,
	"gfx/screen_res": 1,
	"video/vsync": true,
	"video/max_fps": 0,
	# Contador de FPS e ms no canto inferior direito.
	"video/show_fps": false,
	"crosshair/color": Color(0.3, 1.0, 0.45),
	"crosshair/length": 8.0,
	"crosshair/thickness": 2.0,
	"crosshair/gap": 4.0,
	"crosshair/outline": true,
	"crosshair/outline_thickness": 1.0,
	"crosshair/dot": false,
	"crosshair/alpha": 1.0,
	"crosshair/dynamic": true,
	# Deslocamento do viewmodel em centímetros, como o viewmodel_offset do CS.
	"viewmodel/offset_x": 0.0,
	"viewmodel/offset_y": 0.0,
	"viewmodel/offset_z": 0.0,
	# A câmara dá um "coice" (sobe e treme) a cada tiro, como no CS.
	"player/camera_recoil": true,
	# Arma nas mãos (ver Viewmodel.WEAPONS): "ak", "usp" ou "deagle".
	"player/weapon": "ak",
	"mouse/sensitivity": 2.0,
	"mouse/dpi": 800,
	"mouse/invert_y": false,
	# FOV horizontal medido em 4:3, como no CS (90 = valor do CS).
	"video/fov": 90.0,
	# osu!: skin (pasta em "skins"; vazio = a skin do os!strike), distância do
	# ecrã curvo em metros, escurecer o fundo do mapa, mira (0 = do CS, 1 = cursor
	# da skin, 2 = as duas), mostrar a AK e usar os hitsounds da skin/do mapa.
	"osu/skin": "",
	"osu/screen_distance": 3.0,
	"osu/background_dim": 0.75,
	"osu/cursor_mode": 2,
	"osu/show_weapon": true,
	"osu/skin_hitsounds": true,
	# Mods ativos (ver OsuMods), ex.: "HD,HR".
	"osu/mods": "",
}

## Teclas do lobby: ação -> teclas físicas (ou botão do rato).
const INPUT_ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"walk": [KEY_SHIFT],
	"crouch": [KEY_CTRL],
	"fire": [MOUSE_BUTTON_LEFT],
	# Teclas do osu! (como no osu!: carregar = clicar). O botão direito também conta.
	"osu_k1": [KEY_Z],
	"osu_k2": [KEY_X],
	"osu_m2": [MOUSE_BUTTON_RIGHT],
}
const MOUSE_ACTIONS: Array[String] = ["fire", "osu_m2"]

var _values := {}
var _applying_preset := false
var _render_scale_extra := 1.0
var _stretched := false
var _stretch_layer: CanvasLayer
var _stretch_viewport: SubViewport
var _stretch_camera: Camera3D


func _ready() -> void:
	# Corre depois da cena, para a câmara do 3D esticado copiar a posição já atualizada.
	process_priority = 1000
	_values = DEFAULTS.duplicate()
	_setup_input()
	load_settings()
	apply_all()


func _setup_input() -> void:
	for action: String in INPUT_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for code: int in INPUT_ACTIONS[action]:
			if action in MOUSE_ACTIONS:
				var mouse := InputEventMouseButton.new()
				mouse.button_index = code
				InputMap.action_add_event(action, mouse)
			else:
				var key := InputEventKey.new()
				key.physical_keycode = code
				InputMap.action_add_event(action, key)


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	_values[key] = value
	_apply(key)
	changed.emit(key)
	if key == "video/quality" and int(value) < QUALITY_PRESETS.size():
		# Uma predefinição escreve todos os gráficos avançados.
		_applying_preset = true
		var preset: Dictionary = QUALITY_PRESETS[int(value)]
		for k: String in preset:
			set_value(k, preset[k])
		_applying_preset = false
	elif key.begins_with("gfx/") and not _applying_preset and int(get_value("video/quality")) != QUALITY_CUSTOM:
		# Mexer num gráfico avançado à mão passa a "Personalizado".
		_values["video/quality"] = QUALITY_CUSTOM
		changed.emit("video/quality")


func reset_section(section: String) -> void:
	for key: String in DEFAULTS:
		if key.begins_with(section + "/"):
			set_value(key, DEFAULTS[key])


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key: String in DEFAULTS:
		var parts := key.split("/")
		var value: Variant = cfg.get_value(parts[0], parts[1], DEFAULTS[key])
		if typeof(value) == typeof(DEFAULTS[key]) \
				or (typeof(DEFAULTS[key]) == TYPE_FLOAT and typeof(value) == TYPE_INT):
			_values[key] = value
	# Definições antigas (sem gráficos avançados): vêm da predefinição escolhida.
	var q := int(_values.get("video/quality", 2))
	if not cfg.has_section("gfx") and q < QUALITY_PRESETS.size():
		_values.merge(QUALITY_PRESETS[q], true)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key: String in _values:
		var parts := key.split("/")
		cfg.set_value(parts[0], parts[1], _values[key])
	cfg.save(PATH)


func apply_all() -> void:
	for key: String in DEFAULTS:
		_apply(key)


## Pasta onde o jogador põe os hitsounds: ao lado do executável no jogo
## exportado, ou a pasta "sounds" do projeto quando corre a partir do editor.
## Pasta das skins do osu! (ao lado do executável; no editor, a do projeto).
func skins_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://skins")
	return OS.get_executable_path().get_base_dir().path_join("skins")


func sounds_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://sounds")
	return OS.get_executable_path().get_base_dir().path_join("sounds")


func list_hitsounds() -> PackedStringArray:
	var files := PackedStringArray()
	var dir := DirAccess.open(sounds_dir())
	if dir == null:
		return files
	for file in dir.get_files():
		if file.get_extension().to_lower() in HITSOUND_EXTENSIONS:
			files.append(file)
	files.sort()
	return files


## Resoluções de uma proporção que cabem no ecrã atual.
func available_resolutions(aspect: int) -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size()
	var out: Array[Vector2i] = []
	for r: Vector2i in RESOLUTIONS_BY_ASPECT[aspect]:
		if r.x <= screen.x and r.y <= screen.y:
			out.append(r)
	if out.is_empty():
		out.append(RESOLUTIONS_BY_ASPECT[aspect][0])
	return out


## Muda a proporção e escolhe a maior resolução dessa proporção que cabe no ecrã.
func set_aspect(aspect: int) -> void:
	_values["video/aspect"] = aspect
	set_value("video/resolution", available_resolutions(aspect).back())
	changed.emit("video/aspect")


## FOV vertical da câmara (o Godot mantém a altura) a partir do FOV horizontal 4:3.
func vertical_fov() -> float:
	var h := deg_to_rad(float(get_value("video/fov")))
	return rad_to_deg(2.0 * atan(tan(h * 0.5) * 0.75))


## Centímetros de rato para uma volta completa (360°), com a sensibilidade e DPI atuais.
func cm_per_360() -> float:
	var counts_per_turn := 360.0 / (M_YAW * float(get_value("mouse/sensitivity")))
	return counts_per_turn / float(get_value("mouse/dpi")) * 2.54


## Liga/desliga os efeitos caros de um Environment conforme os gráficos
## avançados. O nevoeiro e o bloom só se ligam se a cena os tiver (guardam-se os
## valores originais da primeira vez).
func configure_environment(env: Environment) -> void:
	if not env.has_meta("orig_fog"):
		env.set_meta("orig_fog", env.volumetric_fog_enabled)
		env.set_meta("orig_glow", env.glow_enabled)
	env.volumetric_fog_enabled = bool(env.get_meta("orig_fog")) and bool(get_value("gfx/fog"))
	env.glow_enabled = bool(env.get_meta("orig_glow")) and bool(get_value("gfx/bloom"))
	env.ssao_enabled = bool(get_value("gfx/ssao"))


func _apply(key: String) -> void:
	match key:
		"audio/music_volume":
			_set_bus_volume(&"Music", get_value(key))
		"audio/sfx_volume":
			_set_bus_volume(&"SFX", get_value(key))
		"video/window_mode", "video/resolution", "video/scaling":
			_apply_window()
		"video/quality":
			_apply_quality()
		"video/vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if get_value(key) else DisplayServer.VSYNC_DISABLED)
		"video/max_fps":
			Engine.max_fps = get_value(key)
	if key.begins_with("gfx/"):
		_apply_quality()


## Aplica modo de janela, resolução e proporção.
## - Janela: a janela fica com a resolução escolhida (logo, com a proporção dela).
## - Ecrã inteiro com a mesma proporção do monitor: imagem nativa, a resolução
##   só define a resolução interna do 3D.
## - Ecrã inteiro com outra proporção (ex.: 4:3 num monitor 16:9): o jogo é
##   desenhado nessa proporção e esticado para encher o ecrã, como o "4:3
##   esticado" do CS, ou mostrado com barras pretas.
## A interface tem sempre 720 de altura lógica e a largura segue a proporção.
func _apply_window() -> void:
	var mode: int = get_value("video/window_mode")
	var res: Vector2i = get_value("video/resolution")
	var root := get_tree().root
	match mode:
		0:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(res)
			var usable := DisplayServer.screen_get_usable_rect()
			DisplayServer.window_set_position(usable.position + (usable.size - res) / 2)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	var screen := DisplayServer.screen_get_size()
	var res_aspect := float(res.x) / res.y
	var screen_aspect := float(screen.x) / screen.y
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if mode != 0 and absf(res_aspect - screen_aspect) > 0.01:
		# A interface é desenhada à resolução nativa (nítida) mas com a geometria
		# da proporção escolhida, esticada ou com barras.
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE if get_value("video/scaling") == 0 \
			else Window.CONTENT_SCALE_ASPECT_KEEP
		root.content_scale_size = Vector2i(roundi(UI_HEIGHT * res_aspect), UI_HEIGHT)
		_render_scale_extra = 1.0
		_enable_stretched_3d(res)
	else:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		root.content_scale_size = Vector2i(roundi(UI_HEIGHT * 16.0 / 9.0), UI_HEIGHT)
		_render_scale_extra = minf(float(res.y) / screen.y, 1.0) if mode != 0 else 1.0
		_disable_stretched_3d()
	_apply_quality()


## O 3D é desenhado num SubViewport com a resolução e proporção escolhidas
## (ex.: 1440×1080) e depois esticado para o ecrã. Uma câmara própria copia a
## câmara do jogo em cada frame; o mundo 3D é o mesmo.
func _enable_stretched_3d(res: Vector2i) -> void:
	if _stretch_layer == null:
		_stretch_layer = CanvasLayer.new()
		_stretch_layer.layer = -100
		_stretch_viewport = SubViewport.new()
		_stretch_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_stretch_camera = Camera3D.new()
		_stretch_viewport.add_child(_stretch_camera)
		_stretch_layer.add_child(_stretch_viewport)
		var rect := TextureRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.texture = _stretch_viewport.get_texture()
		_stretch_layer.add_child(rect)
		get_tree().root.add_child.call_deferred(_stretch_layer)
	_stretch_viewport.size = res
	_stretch_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_stretch_layer.visible = true
	_stretch_camera.current = true
	get_tree().root.disable_3d = true
	_stretched = true


func _disable_stretched_3d() -> void:
	_stretched = false
	get_tree().root.disable_3d = false
	if _stretch_layer:
		_stretch_layer.visible = false
		_stretch_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _process(_delta: float) -> void:
	if not _stretched:
		return
	var cam := get_tree().root.get_camera_3d()
	if cam == null:
		return
	_stretch_camera.global_transform = cam.global_transform
	_stretch_camera.fov = cam.fov
	_stretch_camera.near = cam.near
	_stretch_camera.far = cam.far
	_stretch_camera.cull_mask = cam.cull_mask


## Aplica os gráficos avançados às janelas 3D (a principal e a do 4:3 esticado).
func _apply_quality() -> void:
	var viewports: Array[Viewport] = [get_tree().root]
	if _stretch_viewport:
		viewports.append(_stretch_viewport)
	var msaa: Array[Viewport.MSAA] = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
	var upscalers: Array[Viewport.Scaling3DMode] = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR,
		Viewport.SCALING_3D_MODE_FSR2]
	var scale := clampf(float(get_value("gfx/render_scale")) * _render_scale_extra, 0.25, 2.0)
	var upscaler := clampi(int(get_value("gfx/upscaler")), 0, 2)
	# O FSR só serve para baixar a resolução; acima de 100% usa-se supersampling normal.
	if scale >= 0.999 and upscaler == 1:
		upscaler = 0
	for viewport in viewports:
		viewport.msaa_3d = msaa[clampi(int(get_value("gfx/msaa")), 0, 3)]
		viewport.screen_space_aa = clampi(int(get_value("gfx/post_aa")), 0, 2) as Viewport.ScreenSpaceAA
		viewport.use_taa = bool(get_value("gfx/taa"))
		viewport.scaling_3d_mode = upscalers[upscaler]
		viewport.scaling_3d_scale = scale
		viewport.fsr_sharpness = 2.0 * (1.0 - clampf(float(get_value("gfx/sharpness")), 0.0, 1.0))
		viewport.anisotropic_filtering_level = clampi(int(get_value("gfx/anisotropic")), 0, 4) as Viewport.AnisotropicFiltering
		viewport.use_debanding = bool(get_value("gfx/debanding"))


func _set_bus_volume(bus_name: StringName, value: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus == -1:
		return
	AudioServer.set_bus_mute(bus, value <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value, 0.001)))
