extends Node3D
## Lobby do os!strike. Abre com um flashbang; o jogador está parado numa
## plataforma em primeira pessoa. As opções do menu (JOGAR, OPÇÕES, SAIR) são
## palavras gigantes feitas de cubos que saltam com a música: dispara numa
## palavra e ela rebenta em cubos e abre a opção. O terreno atrás mostra o
## espectro da música.

enum State { LOBBY, OPTIONS, MAPS }

## Para onde cada feixe de luz aponta (T à esquerda, CT à direita).
const BEAM_TARGETS: Array[Vector3] = [Vector3(-2.0, -2.4, -2.0), Vector3(3.5, -2.4, -3.0)]
## Tempo mínimo entre duas ações do mesmo alvo (para uma rajada não repetir a ação).
const ACTION_COOLDOWN_MS := 700
## Para sair é preciso voltar a disparar no SAIR dentro deste tempo.
const QUIT_CONFIRM_MS := 3000

var _state := State.LOBBY
var _beam_flash := 0.0
var _beam_bases: Array[Vector3] = []
var _quit_armed_until := 0
var _panel_tween: Tween
var _toast_tween: Tween
var _starting := false
var _song_label := ""

@onready var _player: FPSPlayer = $Player
@onready var _beams: Array[SpotLight3D] = [$Stage/BeamT, $Stage/BeamCT]
@onready var _targets: Array[MusicWord] = [$Words/Play, $Words/Options, $Words/Quit]
@onready var _options_panel: OptionsPanel = %OptionsPanel
@onready var _map_select: MapSelect = %MapSelect
@onready var _dim: ColorRect = %Dim
@onready var _kill_feed: KillFeed = %KillFeed
@onready var _reticle: Control = %Reticle
@onready var _flash: ColorRect = %Flash
@onready var _toast: Control = %Toast
@onready var _progress: ProgressBar = %SongProgress
@onready var _song_time: Label = %SongTime


func _ready() -> void:
	%Root.theme = UITheme.build()
	_apply_fonts()
	for i in _beams.size():
		_beams[i].look_at(BEAM_TARGETS[i])
		_beam_bases.append(_beams[i].rotation)

	_player.fired.connect(func(_r: Dictionary) -> void: %Crosshair.kick())
	for target in _targets:
		target.shot.connect(_on_target_shot)
		# A palavra fica virada para o jogador.
		var to_player := _player.global_position - target.global_position
		target.rotation.y = atan2(to_player.x, to_player.z)
	%BackItem.pressed.connect(_close_overlay)
	_map_select.selection_changed.connect(_preview_map)
	_map_select.play_requested.connect(_start_map)
	_map_select.back_requested.connect(_close_overlay)
	AudioManager.music_finished.connect(_on_music_finished)
	Settings.configure_environment($WorldEnvironment.environment)
	Settings.changed.connect(_on_setting_changed)

	for node: CanvasItem in [_options_panel, _map_select, _dim]:
		node.visible = false
		node.modulate.a = 0.0
	_toast.modulate.a = 0.0
	_set_state(State.LOBBY)
	if Game.returning:
		_return_from_game()
	else:
		_intro()


func _apply_fonts() -> void:
	%Logo.add_theme_font_override("normal_font", UITheme.din(800, 75))
	%OptionsTitle.add_theme_font_override("font", UITheme.din(700, 75))
	%NowPlayingCaption.add_theme_font_override("font", UITheme.din(700, 100))
	%SongTitle.add_theme_font_override("font", UITheme.din(700, 75))
	%SongArtist.add_theme_font_override("font", UITheme.din(400, 100))
	%ToastLabel.add_theme_font_override("font", UITheme.din(700, 75))
	for label: Label in [_song_time, %Hints]:
		label.add_theme_font_override("font", UITheme.mono())


func _on_setting_changed(key: String) -> void:
	if key.begins_with("gfx/"):
		Settings.configure_environment($WorldEnvironment.environment)


## Abertura: flashbang com a música abafada.
func _intro() -> void:
	_play_random_song()
	AudioManager.flashbang(2.6)
	_flash.color = Color.WHITE
	_flash.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.35)
	tween.tween_property(_flash, "modulate:a", 0.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Depois de um jogo: volta logo à seleção de mapas, sem o flashbang.
func _return_from_game() -> void:
	Game.returning = false
	_flash.color = Color.BLACK
	_flash.modulate.a = 1.0
	create_tween().tween_property(_flash, "modulate:a", 0.0, 0.5)
	_open_maps(false)
	if not AudioManager.is_music_playing():
		_play_random_song(0.8)


func _show_song(title: String, artist: String) -> void:
	%SongTitle.text = title.to_upper()
	%SongArtist.text = artist
	_song_label = "♪ %s - %s" % [title, artist]
	_update_presence()


## Discord: no lobby / a escolher música, com a música que está a tocar.
func _update_presence() -> void:
	var song := _song_label
	match _state:
		State.MAPS:
			DiscordPresence.set_status("Choosing a song", song)
		State.OPTIONS:
			DiscordPresence.set_status("In the options", song)
		_:
			DiscordPresence.set_status("In the lobby", song)


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	# Feixes de luz a varrer o nevoeiro.
	_beam_flash *= exp(-delta * 6.0)
	for i in _beams.size():
		var phase := i * 2.1
		_beams[i].rotation = _beam_bases[i] + Vector3(sin(t * 0.37 + phase) * 0.18, sin(t * 0.29 + phase) * 0.45, 0.0)
		_beams[i].light_energy = 0.8 + AudioManager.bass_level * 1.2 + _beam_flash * 2.5

	var aimed := _player.aimed_target as MusicWord if _state == State.LOBBY else null
	for target in _targets:
		target.hovered = target == aimed
	_reticle.target = aimed

	_progress.value = AudioManager.get_progress() * 100.0
	_song_time.text = "%s / %s" % [_fmt_time(AudioManager.get_position()), _fmt_time(AudioManager.get_length())]


func _unhandled_input(event: InputEvent) -> void:
	if _starting:
		return
	if event.is_action_pressed("ui_cancel"):
		if _state == State.LOBBY:
			_open_options()
		else:
			_close_overlay()
		get_viewport().set_input_as_handled()
	elif _state == State.LOBBY and event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Depois de mudar de janela, o primeiro clique só volta a prender o rato.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _state == State.LOBBY and is_node_ready():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_state(state: State) -> void:
	_state = state
	if is_node_ready():
		_update_presence()
	_player.active = state == State.LOBBY
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if state == State.LOBBY else Input.MOUSE_MODE_HIDDEN


func _on_target_shot(target: MusicWord, strength: float) -> void:
	AudioManager.play_hitsound()
	_reticle.on_hit(strength)
	_beam_flash = maxf(_beam_flash, strength)
	var now := Time.get_ticks_msec()
	if now < target.next_action_ms or _state != State.LOBBY:
		return
	target.next_action_ms = now + ACTION_COOLDOWN_MS
	_kill_feed.push("YOU", "AK-47", target.title, true)
	match target.name:
		"Play":
			target.explode()
			AudioManager.play_sfx(&"select")
			get_tree().create_timer(0.35).timeout.connect(_open_maps)
		"Options":
			target.explode()
			# Deixa ver a explosão antes de abrir o painel.
			get_tree().create_timer(0.35).timeout.connect(_open_options)
		"Quit":
			if now < _quit_armed_until:
				target.explode()
				_player.active = false
				get_tree().create_timer(0.5).timeout.connect(_quit)
			else:
				target.shake()
				_quit_armed_until = now + QUIT_CONFIRM_MS
				AudioManager.play_sfx(&"back")
				_show_toast("SHOOT QUIT AGAIN TO EXIT")


func _open_options() -> void:
	if _state != State.LOBBY:
		return
	AudioManager.play_sfx(&"select")
	_set_state(State.OPTIONS)
	_swap_overlay(_options_panel, true)
	_options_panel.focus_first.call_deferred()


func _open_maps(sound := true) -> void:
	if _state != State.LOBBY:
		return
	if sound:
		AudioManager.play_sfx(&"select")
	_set_state(State.MAPS)
	_map_select.refresh()
	_swap_overlay(_map_select, true)


## Fecha o painel aberto (opções ou mapas) e volta ao lobby.
func _close_overlay() -> void:
	if _state == State.LOBBY:
		return
	AudioManager.play_sfx(&"back")
	var panel: CanvasItem = _options_panel
	if _state == State.OPTIONS:
		Settings.save_settings()
	else:
		# A música escolhida na seleção continua a tocar no lobby (como no osu!).
		panel = _map_select
	_set_state(State.LOBBY)
	_swap_overlay(panel, false)


## Música do menu: uma música aleatória da pasta de mapas (do ponto de
## pré-visualização); quando acaba, toca outra.
func _play_random_song(fade := 1.5) -> void:
	var map := Game.random_song(AudioManager.current_music_id)
	if map.is_empty():
		AudioManager.play_menu_music()
		_show_song(AudioManager.MENU_TRACK_TITLE, AudioManager.MENU_TRACK_ARTIST)
		return
	AudioManager.play_music(Game.load_audio(map), Game.music_id(map), float(map.get("preview", 0.0)), fade)
	_show_song(map.title, map.artist)


func _on_music_finished() -> void:
	if _starting:
		return
	if _state == State.MAPS:
		# Na seleção, a pré-visualização recomeça.
		_preview_map(_map_select.current())
	else:
		_play_random_song(0.5)


## Toca a música do mapa escolhido (a partir do ponto de pré-visualização).
func _preview_map(map: Dictionary) -> void:
	if AudioManager.current_music_id == Game.music_id(map) and AudioManager.is_music_playing():
		return
	AudioManager.play_music(Game.load_audio(map), Game.music_id(map), float(map.get("preview", 0.0)), 0.8)
	_show_song(map.title, map.artist)


func _start_map(map: Dictionary) -> void:
	if _starting:
		return
	_starting = true
	AudioManager.fade_out(0.6)
	_flash.color = Color.BLACK
	var tween := create_tween()
	tween.tween_property(_flash, "modulate:a", 1.0, 0.6)
	tween.tween_callback(func() -> void:
		AudioManager.stop_music()
		Game.play(map))


func _quit() -> void:
	Settings.save_settings()
	_player.active = false
	AudioManager.fade_out(0.5)
	_flash.color = Color.BLACK
	var tween := create_tween()
	tween.tween_property(_flash, "modulate:a", 1.0, 0.5)
	tween.tween_callback(get_tree().quit)


## Mostra/esconde um painel (opções ou mapas) e o fundo escurecido; o HUD do
## lobby (mira dos alvos, "A TOCAR", dicas) faz o contrário.
func _swap_overlay(panel: CanvasItem, show_panel: bool) -> void:
	if _panel_tween:
		_panel_tween.kill()
	_panel_tween = create_tween().set_parallel()
	var overlay: Array[CanvasItem] = [panel, _dim]
	var hud: Array[CanvasItem] = [_reticle, %Hints, $UI/Root/NowPlaying, _kill_feed]
	# A seleção de mapas ocupa o ecrã todo e tem o seu próprio título.
	if panel == _map_select:
		hud.append($UI/Root/Logo)
	if show_panel:
		_dim.color.a = 0.86 if panel == _map_select else 0.62
	for node in overlay:
		node.visible = true
		_panel_tween.tween_property(node, "modulate:a", 1.0 if show_panel else 0.0, 0.18)
	for node in hud:
		_panel_tween.tween_property(node, "modulate:a", 0.0 if show_panel else 1.0, 0.18)
	if not show_panel:
		_panel_tween.chain().tween_callback(func() -> void:
			for node in overlay:
				node.visible = false)


func _show_toast(text: String) -> void:
	%ToastLabel.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_toast.pivot_offset = _toast.size * 0.5
	_toast.scale = Vector2(1.0, 0.6)
	_toast_tween = create_tween().set_parallel()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.12)
	_toast_tween.tween_property(_toast, "scale:y", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.chain().tween_interval(1.8)
	_toast_tween.chain().tween_property(_toast, "modulate:a", 0.0, 0.4)


static func _fmt_time(seconds: float) -> String:
	var s := int(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [s / 60, s % 60]
