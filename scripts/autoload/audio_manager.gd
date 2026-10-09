extends Node
## Música do jogo e análise de espectro.
## Lê o bus "Music" para dar a outros nós o nível dos graves e as bandas do
## espectro (usados pelos visuais), e toca os efeitos sonoros da interface.

## Emitido quando uma música sem loop chega ao fim.
signal music_finished

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const SFX_VOICES := 8
const MENU_TRACK: AudioStream = preload("res://assets/music/into_the_void.mp3")
const MENU_TRACK_TITLE := "Into The Void"
const MENU_TRACK_ARTIST := "POLTERGST, RØØTZ, Jordan Lindley"

## Número de bandas do espectro (espaçadas logaritmicamente).
const BAND_COUNT := 48
const MIN_FREQ := 40.0
const MAX_FREQ := 12000.0
const DB_RANGE := 60.0
const BASS_LOW := 35.0
const BASS_HIGH := 130.0

## Nível dos graves suavizado, 0..1.
var bass_level := 0.0
## Energia de cada banda, 0..1. Atualizado a cada frame.
var bands := PackedFloat32Array()

var _player: AudioStreamPlayer
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _sfx: Dictionary[StringName, AudioStream] = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _muffle_tween: Tween
var _music_tween: Tween
var _hitsound: AudioStream
## Identificador da música atual (ver `play_music`).
var current_music_id := ""
var _hitsound_name := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bands.resize(BAND_COUNT)
	_player = AudioStreamPlayer.new()
	_player.bus = MUSIC_BUS
	_player.finished.connect(func() -> void: music_finished.emit())
	add_child(_player)

	_sfx = SfxBank.build()
	for i in SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = SFX_BUS
		add_child(voice)
		_sfx_players.append(voice)


## Janela sem foco: o som baixa (bus Master) para o volume escolhido nas Opções;
## com foco volta ao normal. Transição suave.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_fade_master(float(Settings.get_value("audio/inactive_volume")))
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_fade_master(1.0)


var _master_tween: Tween
var _master_level := 1.0


func _fade_master(target: float) -> void:
	if _master_tween:
		_master_tween.kill()
	_master_tween = create_tween()
	_master_tween.tween_method(_set_master_level, _master_level, target, 0.4 if target < 1.0 else 0.25)


func _set_master_level(level: float) -> void:
	_master_level = level
	var bus := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(level, 0.001)))
	AudioServer.set_bus_mute(bus, level <= 0.001)


func _exit_tree() -> void:
	# Evita que o stream fique "em uso" quando o jogo fecha.
	_player.stop()
	_player.stream = null


func play_sfx(sfx_name: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	var stream: AudioStream = _sfx.get(sfx_name)
	if stream == null:
		push_warning("SFX desconhecido: %s" % sfx_name)
		return
	var voice := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()


## Toca o hitsound escolhido nas Opções (padrão, nenhum ou ficheiro da pasta "sounds").
func play_hitsound() -> void:
	var choice: String = Settings.get_value("audio/hitsound")
	if choice == Settings.HITSOUND_NONE:
		return
	if choice != _hitsound_name:
		_hitsound_name = choice
		_hitsound = _sfx[&"hit"] if choice == Settings.HITSOUND_DEFAULT \
			else load_sound_file(Settings.sounds_dir().path_join(choice))
	if _hitsound == null:
		return
	var voice := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	voice.stream = _hitsound
	voice.volume_db = linear_to_db(maxf(Settings.get_value("audio/hitsound_volume"), 0.001))
	voice.pitch_scale = 1.0
	voice.play()


## Toca um som qualquer (ex.: hitsound de uma skin do osu!) com volume linear 0..1.
func play_sample(stream: AudioStream, volume := 1.0) -> void:
	if stream == null:
		return
	var voice := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	voice.stream = stream
	voice.volume_db = linear_to_db(maxf(volume, 0.001))
	voice.pitch_scale = 1.0
	voice.play()


## Velocidade da música (mods DT/HT/NC). `keep_pitch`: mantém o tom (um efeito
## de pitch shift no bus "Music" compensa); senão o tom sobe/desce com ela.
func set_music_speed(speed: float, keep_pitch: bool) -> void:
	_player.pitch_scale = speed
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	var index := _music_effect_index("AudioEffectPitchShift")
	var need := keep_pitch and not is_equal_approx(speed, 1.0)
	if index == -1:
		if not need:
			return
		var shift := AudioEffectPitchShift.new()
		shift.oversampling = 4
		AudioServer.add_bus_effect(bus, shift, 0)
		index = _music_effect_index("AudioEffectPitchShift")
		_spectrum = null
	(AudioServer.get_bus_effect(bus, index) as AudioEffectPitchShift).pitch_scale = 1.0 / speed if need else 1.0
	AudioServer.set_bus_effect_enabled(bus, index, need)


## Salta a música para o segundo `t`.
func seek(t: float) -> void:
	if _player.playing:
		_player.seek(maxf(t, 0.0))


## Esquece o hitsound em cache (ex.: depois de o jogador trocar ficheiros na pasta).
func reload_hitsound() -> void:
	_hitsound_name = ""


## Carrega um ficheiro de áudio de fora do projeto (wav, ogg ou mp3).
static func load_sound_file(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		push_warning("Sound file not found: %s" % path)
		return null
	match path.get_extension().to_lower():
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
	return null


## Efeito de flashbang: a música fica abafada e vai abrindo, com zumbido.
func flashbang(duration: float) -> void:
	var filter := _music_effect("AudioEffectLowPassFilter") as AudioEffectLowPassFilter
	if filter == null:
		return
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	var index := _music_effect_index("AudioEffectLowPassFilter")
	AudioServer.set_bus_effect_enabled(bus, index, true)
	if _muffle_tween:
		_muffle_tween.kill()
	_muffle_tween = create_tween()
	_muffle_tween.tween_property(filter, "cutoff_hz", 20500.0, duration) \
		.from(250.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_muffle_tween.tween_callback(Callable(AudioServer, "set_bus_effect_enabled").bind(bus, index, false))
	play_sfx(&"ring", -4.0)


func _music_effect_index(type_name: String) -> int:
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i).is_class(type_name):
			return i
	return -1


func _music_effect(type_name: String) -> AudioEffect:
	var index := _music_effect_index(type_name)
	return AudioServer.get_bus_effect(AudioServer.get_bus_index(MUSIC_BUS), index) if index != -1 else null


func play_menu_music() -> void:
	# O loop está ligado nas definições de importação do mp3.
	play_music(MENU_TRACK, MENU_TRACK_TITLE + "|" + MENU_TRACK_ARTIST, 0.0, 1.5)


## Toca uma música. `id` identifica-a: se já estiver a tocar a mesma, não recomeça.
func play_music(stream: AudioStream, id: String, from := 0.0, fade := 0.0) -> void:
	if stream == null or (_player.playing and id == current_music_id):
		return
	if _music_tween:
		_music_tween.kill()
	current_music_id = id
	_player.stream = stream
	_player.stream_paused = false
	set_music_speed(1.0, true)
	_player.volume_db = -30.0 if fade > 0.0 else 0.0
	_player.play(from)
	if fade > 0.0:
		_music_tween = create_tween()
		_music_tween.tween_property(_player, "volume_db", 0.0, fade) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func stop_music() -> void:
	_player.stop()
	current_music_id = ""


func set_music_paused(paused: bool) -> void:
	_player.stream_paused = paused


func is_music_playing() -> bool:
	return _player.playing and not _player.stream_paused


## Posição da música que está a sair nas colunas agora (compensa o tempo desde
## a última mistura e a latência de saída). É a referência de tempo do jogo.
func get_song_time() -> float:
	if not _player.playing:
		return 0.0
	# Com a música mais rápida/lenta, o tempo real conta multiplicado pela velocidade.
	return _player.get_playback_position() + (AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()) * _player.pitch_scale


## Abranda a música até parar (quando o jogador morre).
func wind_down(duration: float) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel()
	_music_tween.tween_property(_player, "pitch_scale", 0.25, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_music_tween.tween_property(_player, "volume_db", -40.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_music_tween.chain().tween_callback(stop_music)


func fade_out(duration: float) -> Tween:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_player, "volume_db", -40.0, duration)
	return _music_tween


## Progresso da música atual, 0..1.
func get_progress() -> float:
	var length := get_length()
	return get_position() / length if length > 0.0 else 0.0


func get_position() -> float:
	return _player.get_playback_position() if _player.playing else 0.0


func get_length() -> float:
	return _player.stream.get_length() if _player.stream else 0.0


func _process(delta: float) -> void:
	if _spectrum == null:
		_spectrum = _find_spectrum()
		if _spectrum == null:
			return
	_update_bands()
	_update_bass(delta)


func _find_spectrum() -> AudioEffectSpectrumAnalyzerInstance:
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	if bus == -1:
		return null
	for i in AudioServer.get_bus_effect_count(bus):
		var instance := AudioServer.get_bus_effect_instance(bus, i)
		if instance is AudioEffectSpectrumAnalyzerInstance:
			return instance
	return null


func _update_bands() -> void:
	var prev_hz := MIN_FREQ
	for i in BAND_COUNT:
		var t := float(i + 1) / BAND_COUNT
		var hz := MIN_FREQ * pow(MAX_FREQ / MIN_FREQ, t)
		var mag := _spectrum.get_magnitude_for_frequency_range(prev_hz, hz)
		# As altas frequências têm menos energia; compensamos com uma inclinação.
		var db := linear_to_db(maxf(mag.x, mag.y)) + 14.0 * t
		bands[i] = clampf((db + DB_RANGE) / DB_RANGE, 0.0, 1.0)
		prev_hz = hz


func _update_bass(delta: float) -> void:
	var mag := _spectrum.get_magnitude_for_frequency_range(BASS_LOW, BASS_HIGH)
	var bass_norm := clampf((linear_to_db((mag.x + mag.y) * 0.5) + 45.0) / 45.0, 0.0, 1.0)
	bass_level = lerpf(bass_level, bass_norm, 1.0 - exp(-delta * 18.0))
