class_name OsuGame
extends Node3D
## os!strike: o osu! num ecrã curvo a flutuar no espaço, jogado em primeira
## pessoa. A mira (rato, como no CS) aponta para o ecrã; clicar (ou Z / X /
## botão direito) é carregar no círculo. Sliders: segurar e seguir a bola.
## Spinners: segurar e rodar a mira à volta do centro.
## A pausa e o ecrã de falhar são um menu 2D na janela do jogo (com a mira como
## cursor); os resultados aparecem no próprio ecrã e escolhem-se a disparar.

## FAILING: a animação de falhar (o ecrã avaria e explode) antes de FAILED.
## RESUMING: a contagem de 3 s depois de sair da pausa.
enum Phase { INTRO, PLAYING, PAUSED, FAILED, RESULTS, FAILING, RESUMING }
enum { HIT300, HIT100, HIT50, MISS }

const KEYS: Array[StringName] = [&"fire", &"osu_k1", &"osu_k2", &"osu_m2"]
const MIN_LEAD := 1.6
const POINTS: Array[int] = [300, 100, 50, 0]
## Voltas por segundo para completar um spinner (mais fácil do que no osu!: aqui roda-se com a mira).
const SPIN_RATE := 1.4
const SAMPLE_SETS: Array[String] = ["normal", "normal", "soft", "drum"]
const END_DELAY := 1.2
const RESUME_COUNTDOWN := 3.0

var map := {}
var beatmap: OsuBeatmap
var skin: OsuSkin
var clock := -2.0
var phase := Phase.INTRO
var score := 0
var combo := 0
var max_combo := 0
var counts: Array[int] = [0, 0, 0, 0]
var health := 1.0
var failed := false
## Estado de cada objeto (paralelo a beatmap.objects).
var states: Array[Dictionary] = []
## Julgamentos a desenhar: {pos, result, time}
var judgments: Array[Dictionary] = []
## (tempo, julgamento) para o gráfico dos resultados.
var timeline: Array[Vector2] = []
## Ponto para onde a mira aponta, em coordenadas do osu! (e se está no ecrã).
var aim_osu := Vector2(-9999, -9999)
var aim_on_screen := false
var aim_view := Vector2(-1, -1)
var keys_held := false
var result := {}
var record := false
## Segundos que faltam na contagem ao sair da pausa (0 = sem contagem).
var resume_countdown := 0.0
var _last_count := 0

var _first := 0
var _music: AudioStream
var _music_started := false
var _diff_mult := 3.0
var _phase_before_pause := Phase.PLAYING
var _map_sounds: Dictionary[String, String] = {}
var _sound_cache: Dictionary[String, Variant] = {}
var _leaving := false
var _options: OptionsPanel
## Tempo (real) desde que se falhou; -1 = não falhou.
var _fail_t := -1.0
var _fail_impact := Vector2(0.5, 0.5)
var _boomed := false
var _reassembled := false
## Menu de pausa / falhar (2D, por cima do jogo).
var _menu: Control
var _menu_title: Label
var _menu_info: Label
var _menu_items: VBoxContainer
var _menu_kind := ""
var _options_layer: Control
var _last_object_end := 0.0
## Mods ativos (ver OsuMods) e o multiplicador de pontos deles.
var mods: Array[String] = []
var _mult := 1.0
var _auto := false
var _auto_pressed := {}

@onready var _player: FPSPlayer = $Player
@onready var _screen: CurvedScreen = $Screen
@onready var _viewport: SubViewport = $ScreenViewport
@onready var _view: OsuScreen = $ScreenViewport/OsuScreen
@onready var _flash: ColorRect = %Flash
@onready var _crosshair: Control = %Crosshair


func _ready() -> void:
	map = Game.current_map
	if map.is_empty():
		var maps := Game.scan_maps()
		if not maps.is_empty():
			map = maps[0]
			Game.current_map = map
	skin = OsuSkin.current()
	beatmap = _load_beatmap(map)
	if beatmap == null:
		push_error("Could not read the map")
		beatmap = OsuBeatmap.from_json({"notes": [{"t": 2.0, "x": 0.0, "y": 0.5}]})
	mods = OsuMods.active()
	OsuMods.apply(beatmap, mods)
	_mult = OsuMods.multiplier(mods)
	_auto = "AU" in mods
	for o in beatmap.objects:
		states.append({"judged": false, "head_done": false, "head_result": MISS, "tracking": false, "cp": 0,
			"cp_hit": 0, "spin": 0.0, "last_angle": 0.0, "has_angle": false, "spins_scored": 0,
			"judge_time": 0.0, "shake": -10.0})
		_last_object_end = maxf(_last_object_end, float(o.end_time))
	_diff_mult = _difficulty_multiplier()
	_index_map_sounds()
	if not map.is_empty():
		_music = Game.load_audio(map)
	clock = minf(-0.5, beatmap.first_time() - beatmap.preempt() - MIN_LEAD)

	_apply_screen_res()
	Settings.configure_environment($WorldEnvironment.environment)
	_screen.texture = _viewport.get_texture()
	_view.game = self
	_player.position = Vector3.ZERO
	_player.set_view(0.0)
	_player.automatic = false
	_player.fire_enabled = false
	_player.punch_scale = 0.25
	var show_weapon: bool = Settings.get_value("osu/show_weapon")
	_player.viewmodel.visible = show_weapon
	# Sem faíscas nem traçadores no ecrã (tapavam as notas).
	_player.bullet_fx.visible = false
	_crosshair.visible = int(Settings.get_value("osu/cursor_mode")) != 1
	Settings.changed.connect(_on_setting_changed)
	for mesh in _player.viewmodel.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	%Root.theme = UITheme.build()

	AudioManager.stop_music()
	_presence_playing()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_flash.color = Color.BLACK
	_flash.modulate.a = 1.0
	create_tween().tween_property(_flash, "modulate:a", 0.0, 0.6)


func _load_beatmap(data: Dictionary) -> OsuBeatmap:
	if data.has("osu_file"):
		return OsuBeatmap.load_file(String(data.dir).path_join(data.osu_file))
	return OsuBeatmap.from_json(data)


# --- Valores ----------------------------------------------------------------------

func accuracy() -> float:
	var total := counts[0] + counts[1] + counts[2] + counts[3]
	if total == 0:
		return 1.0
	return (300.0 * counts[0] + 100.0 * counts[1] + 50.0 * counts[2]) / (300.0 * total)


func grade() -> String:
	if failed:
		return "F"
	var total := counts[0] + counts[1] + counts[2] + counts[3]
	var acc := accuracy()
	if total == 0 or acc >= 1.0:
		return "SS"
	var no_miss := counts[MISS] == 0
	if acc > 0.9 and no_miss and counts[HIT50] < total * 0.01:
		return "S"
	if (acc > 0.8 and no_miss) or acc > 0.9:
		return "A"
	if (acc > 0.7 and no_miss) or acc > 0.8:
		return "B"
	if acc > 0.6:
		return "C"
	return "D"


func song_length() -> float:
	return maxf(_last_object_end, 1.0)


## Pode saltar a introdução (primeiro objeto longe).
func can_skip() -> bool:
	return phase == Phase.INTRO or (phase == Phase.PLAYING and clock < beatmap.first_time() - beatmap.preempt() - 2.5)


func _difficulty_multiplier() -> float:
	var drain := maxf(_last_object_end - beatmap.first_time(), 1.0)
	var density := clampf(beatmap.objects.size() / drain * 8.0, 0.0, 16.0)
	return clampf(roundf((beatmap.hp + beatmap.cs + beatmap.od + density) / 38.0 * 5.0), 2.0, 6.0)


# --- Ciclo -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_aim()
	keys_held = false
	for k in KEYS:
		if Input.is_action_pressed(k):
			keys_held = true
	if _auto and phase in [Phase.INTRO, Phase.PLAYING]:
		_autoplay()
	match phase:
		Phase.INTRO, Phase.PLAYING:
			_advance_clock(delta)
			_update_objects(delta)
			_update_health(delta)
			if not failed and _first >= beatmap.objects.size() and clock > _last_object_end + END_DELAY:
				_finish()
		Phase.RESUMING:
			_update_resume(delta)
	if _fail_t >= 0.0:
		_update_fail(delta)


func _update_aim() -> void:
	var uv := _screen.aim_uv(_player.aim_direction())
	aim_on_screen = uv.x >= 0.0
	if aim_on_screen:
		aim_view = uv * Vector2(OsuScreen.VIEW_SIZE)
		aim_osu = OsuScreen.view_to_osu(aim_view)
	else:
		aim_view = Vector2(-1, -1)
		aim_osu = Vector2(-9999, -9999)


func _advance_clock(delta: float) -> void:
	if not _music_started:
		clock += delta * beatmap.rate
		if clock >= 0.0:
			_music_started = true
			phase = Phase.PLAYING
			AudioManager.play_music(_music, Game.music_id(map), clock)
			AudioManager.set_music_speed(beatmap.rate, not "NC" in mods)
		return
	clock += delta * beatmap.rate
	if AudioManager.is_music_playing():
		var audio_time := AudioManager.get_song_time()
		if absf(audio_time - clock) > 0.08:
			clock = audio_time
		else:
			clock = lerpf(clock, audio_time, 0.12)


func _update_objects(_delta: float) -> void:
	var w := beatmap.hit_windows()
	var objects := beatmap.objects
	var i := _first
	while i < objects.size():
		var o := objects[i]
		if float(o.time) - beatmap.preempt() > clock:
			break
		var s := states[i]
		if not s.judged:
			match int(o.type):
				OsuBeatmap.CIRCLE:
					if clock > float(o.time) + w.z:
						_judge(i, MISS, o.pos)
				OsuBeatmap.SLIDER:
					_update_slider(i, o, s, w)
				OsuBeatmap.SPINNER:
					_update_spinner(i, o, s)
		i += 1
	while _first < objects.size() and states[_first].judged:
		_first += 1


func _update_slider(i: int, o: Dictionary, s: Dictionary, w: Vector3) -> void:
	if not s.head_done and clock > float(o.time) + w.z:
		s.head_done = true
		s.head_result = MISS
		_break_combo()
	if clock < float(o.time):
		return
	var ball := OsuBeatmap.slider_ball(o, clock)
	var follow := beatmap.radius() * (2.4 if s.tracking else 1.0)
	s.tracking = keys_held and aim_on_screen and aim_osu.distance_to(ball) <= follow
	var checkpoints: Array = o.checkpoints
	while s.cp < checkpoints.size() and float(checkpoints[s.cp].time) <= clock:
		var cp: Dictionary = checkpoints[s.cp]
		if s.tracking:
			s.cp_hit += 1
			combo += 1
			max_combo = maxi(max_combo, combo)
			_add_score(10 if cp.kind == "tick" else 30)
			health = minf(health + 0.01, 1.0)
			if cp.kind == "tick":
				_play_hitsound(0, cp.time, "slidertick")
			else:
				_play_hitsound(int(o.hit_sound), cp.time)
		elif cp.kind != "tail":
			_break_combo()
		s.cp += 1
	if clock >= float(o.end_time):
		var total := 1 + checkpoints.size()
		var hits := int(s.cp_hit) + (0 if int(s.head_result) == MISS else 1)
		var res := MISS
		if hits == total:
			res = HIT300
		elif hits * 2 >= total:
			res = HIT100
		elif hits > 0:
			res = HIT50
		_judge(i, res, o.end_pos, false)


func _update_spinner(i: int, o: Dictionary, s: Dictionary) -> void:
	if clock < float(o.time):
		return
	var duration := maxf(float(o.end_time) - float(o.time), 0.1)
	var required := maxf(1.0, duration / beatmap.rate * SPIN_RATE)
	if keys_held and aim_on_screen and clock < float(o.end_time):
		var angle := (aim_osu - OsuBeatmap.PLAYFIELD * 0.5).angle()
		if s.has_angle:
			s.spin += minf(absf(wrapf(angle - float(s.last_angle), -PI, PI)), 1.2)
		s.last_angle = angle
		s.has_angle = true
	else:
		s.has_angle = false
	var spins := int(float(s.spin) / TAU)
	while int(s.spins_scored) < spins:
		s.spins_scored += 1
		var bonus: bool = s.spins_scored > required
		_add_score(1000 if bonus else 100)
		health = minf(health + 0.02, 1.0)
		if bonus:
			_play_sound_named("spinnerbonus")
	if clock >= float(o.end_time):
		var ratio := float(s.spin) / TAU / required
		var res := MISS
		if ratio >= 1.0:
			res = HIT300
		elif ratio >= 0.75:
			res = HIT100
		elif ratio >= 0.5:
			res = HIT50
		_judge(i, res, o.pos)


func _update_health(delta: float) -> void:
	if phase != Phase.PLAYING or failed:
		return
	if clock < beatmap.first_time() or clock > _last_object_end or beatmap.is_break(clock):
		return
	health -= (0.004 + beatmap.hp * 0.003) * delta
	if health <= 0.0:
		_fail()


# --- Acertos -----------------------------------------------------------------------------

func _try_hit() -> void:
	var w := beatmap.hit_windows()
	var r := beatmap.radius()
	var objects := beatmap.objects
	for i in range(_first, objects.size()):
		var o := objects[i]
		if float(o.time) - beatmap.preempt() > clock:
			break
		var s := states[i]
		if int(o.type) == OsuBeatmap.SPINNER or s.judged or s.head_done:
			continue
		var err := clock - float(o.time)
		if err > w.z or aim_osu.distance_to(o.pos) > r:
			continue
		if err < -w.z:
			# Cedo demais: o círculo abana (como no osu!lazer).
			s.shake = clock
			return
		var res := HIT50
		if absf(err) <= w.x:
			res = HIT300
		elif absf(err) <= w.y:
			res = HIT100
		_view.add_error(err, w)
		if int(o.type) == OsuBeatmap.CIRCLE:
			_judge(i, res, o.pos)
			_play_hitsound(int(o.hit_sound), float(o.time))
		else:
			s.head_done = true
			s.head_result = res
			s.judge_time = clock
			combo += 1
			max_combo = maxi(max_combo, combo)
			_add_score(30)
			_play_hitsound(int(o.hit_sound), float(o.time))
		return


func _judge(i: int, res: int, pos: Vector2, add_combo := true) -> void:
	var s := states[i]
	s.judged = true
	s.result = res
	s.judge_time = clock
	counts[res] += 1
	if "PF" in mods and res != HIT300:
		_fail()
	if res == MISS:
		_break_combo()
		health -= 0.06 + beatmap.hp * 0.012
		if health <= 0.0:
			_fail()
	else:
		_add_score(int(POINTS[res] * (1.0 + maxi(combo - 1, 0) * _diff_mult / 25.0)))
		if add_combo:
			combo += 1
		max_combo = maxi(max_combo, combo)
		var gain := maxf(0.025 - beatmap.hp * 0.0015, 0.008)
		health = minf(health + [gain, gain * 0.4, 0.0, 0.0][res], 1.0)
	judgments.append({"pos": pos, "result": res, "time": clock})
	if judgments.size() > 40:
		judgments.pop_front()
	timeline.append(Vector2(float(beatmap.objects[i].time), res))


# --- Auto (o jogo joga sozinho) ---------------------------------------------------

## Mira automática: vai de objeto em objeto, segue a bola dos sliders e roda nos
## spinners; carrega no tempo certo. A câmara também se vira para lá.
func _autoplay() -> void:
	var objects := beatmap.objects
	var target := Vector2(256, 192)
	var hold := false
	var index := -1
	for i in range(_first, objects.size()):
		if not states[i].judged:
			index = i
			break
	if index >= 0:
		var o := objects[index]
		var t := float(o.time)
		if clock >= t:
			match int(o.type):
				OsuBeatmap.SLIDER:
					target = OsuBeatmap.slider_ball(o, clock)
					hold = true
				OsuBeatmap.SPINNER:
					var a := clock * TAU * 3.0 / beatmap.rate
					target = OsuBeatmap.PLAYFIELD * 0.5 + Vector2(cos(a), sin(a)) * 70.0
					hold = true
				_:
					target = o.pos
		else:
			var prev_pos := OsuBeatmap.PLAYFIELD * 0.5
			var prev_t := t - beatmap.preempt()
			if index > 0:
				prev_pos = objects[index - 1].end_pos
				prev_t = float(objects[index - 1].end_time)
			var k := clampf((clock - prev_t) / maxf(t - prev_t, 0.001), 0.0, 1.0)
			target = prev_pos.lerp(o.pos, k * k * (3.0 - 2.0 * k))
		if int(o.type) != OsuBeatmap.SPINNER and clock >= t - 0.004 and not _auto_pressed.has(index):
			_auto_pressed[index] = true
			_set_auto_aim(o.pos)
			_on_key_press()
	_set_auto_aim(target)
	keys_held = hold


func _set_auto_aim(osu: Vector2) -> void:
	aim_osu = osu
	aim_view = OsuScreen.osu_to_view(osu)
	aim_on_screen = true
	var dir := _screen.uv_to_world(aim_view / Vector2(OsuScreen.VIEW_SIZE)) - _screen.eye
	_player.set_view(atan2(-dir.x, -dir.z), atan2(dir.y, Vector2(dir.x, dir.z).length()))


func _add_score(points: int) -> void:
	score += int(roundf(points * _mult))


func _break_combo() -> void:
	# SD/PF: falhar um slider também mata.
	if "SD" in mods or "PF" in mods:
		_fail()
	if combo >= 20:
		_play_sound_named("combobreak")
	combo = 0


# --- Sons --------------------------------------------------------------------------------

func _index_map_sounds() -> void:
	var dir := String(map.get("dir", ""))
	if dir.is_empty():
		return
	for file in DirAccess.get_files_at(dir):
		if file.get_extension().to_lower() in OsuSkin.SOUND_EXTENSIONS:
			_map_sounds[file.get_basename().to_lower()] = dir.path_join(file)


## Hitsound do osu!: hitnormal (+ whistle / finish / clap) do sample set do momento.
func _play_hitsound(bits: int, time: float, only := "") -> void:
	if not Settings.get_value("osu/skin_hitsounds"):
		if only.is_empty():
			AudioManager.play_hitsound()
		return
	var tp := beatmap.timing_at(time)
	var sample_set: String = SAMPLE_SETS[clampi(int(tp.sample_set), 0, 3)]
	var volume: float = tp.volume
	var names: Array[String] = []
	if not only.is_empty():
		names.append("%s-%s" % [sample_set, only])
	else:
		names.append(sample_set + "-hitnormal")
		if bits & 2:
			names.append(sample_set + "-hitwhistle")
		if bits & 4:
			names.append(sample_set + "-hitfinish")
		if bits & 8:
			names.append(sample_set + "-hitclap")
	for n in names:
		var stream := _find_sound(n)
		if stream:
			AudioManager.play_sample(stream, volume * float(Settings.get_value("audio/hitsound_volume")))
		elif n.ends_with("hitnormal"):
			AudioManager.play_hitsound()


func _play_sound_named(sound_name: String) -> void:
	var stream := _find_sound(sound_name)
	if stream:
		AudioManager.play_sample(stream, float(Settings.get_value("audio/hitsound_volume")))


## Som do mapa, senão da skin.
func _find_sound(sound_name: String) -> AudioStream:
	if _sound_cache.has(sound_name):
		return _sound_cache[sound_name]
	var stream: AudioStream = null
	if _map_sounds.has(sound_name):
		stream = AudioManager.load_sound_file(_map_sounds[sound_name])
	if stream == null:
		stream = skin.sound(sound_name)
	_sound_cache[sound_name] = stream
	return stream


# --- Entrada -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
		return
	if _options and _options_layer.visible:
		# Com as opções abertas só o ESC conta (fecha-as); o resto é do painel.
		if event.is_action_pressed("ui_cancel"):
			_close_options()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		match phase:
			Phase.INTRO, Phase.PLAYING, Phase.RESUMING:
				_pause()
			Phase.PAUSED:
				_resume()
			Phase.FAILING, Phase.FAILED:
				# Depois de falhar o ESC não sai do jogo: abre o menu com TENTAR DE NOVO.
				_show_menu("fail")
			Phase.RESULTS:
				_back_to_lobby()
		get_viewport().set_input_as_handled()
		return
	if _menu_open():
		if event is InputEventKey and event.pressed and not event.echo:
			match (event as InputEventKey).physical_keycode:
				KEY_R:
					_restart()
				KEY_O:
					_open_options()
				KEY_Q:
					_back_to_lobby()
		# Com o menu aberto, os cliques e as teclas do osu! não chegam ao jogo.
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	for k in KEYS:
		if event.is_action_pressed(k, false):
			_on_key_press()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_SPACE:
				if can_skip():
					_skip_intro()
			KEY_R:
				if phase in [Phase.FAILING, Phase.FAILED, Phase.RESULTS]:
					_restart()
			KEY_ENTER, KEY_KP_ENTER:
				if phase == Phase.RESULTS:
					_back_to_lobby()


func _on_key_press() -> void:
	if Settings.get_value("osu/show_weapon"):
		_player.shoot_once()
		%Crosshair.kick()
	match phase:
		Phase.INTRO, Phase.PLAYING:
			if aim_on_screen:
				_try_hit()
		Phase.RESULTS:
			match _view.button_at(aim_view):
				"retry":
					_restart()
				"back":
					_back_to_lobby()


# --- Menu de pausa / falhar (2D, na janela do jogo) ------------------------------------

func _menu_open() -> bool:
	return _menu != null and _menu.visible


## Mostra o menu: "pause" (continuar, recomeçar, opções, sair) ou "fail"
## (tentar de novo, sair). O rato fica livre e a mira do CS serve de cursor.
func _show_menu(kind: String) -> void:
	if _leaving:
		return
	if _menu == null:
		_build_menu()
	if _menu_open() and _menu_kind == kind:
		return
	_menu_kind = kind
	for child in _menu_items.get_children():
		child.queue_free()
	var first: MenuItem
	if kind == "pause":
		_menu_title.text = "PAUSED"
		_menu_title.add_theme_color_override("font_color", UITheme.TEXT)
		_menu_info.text = "%s\n%s  ·  %s  ·  %.2f%%" % [_map_label(), _mods_label(), _progress_label(), accuracy() * 100.0]
		first = _menu_item("ESC", "CONTINUE", "Back to the song", Color(0.45, 1.0, 0.5), _resume)
		_menu_item("R", "RETRY", "Start the map again", UITheme.T_ORANGE, _restart)
		_menu_item("O", "OPTIONS", "Skin, screen distance, audio, crosshair...", UITheme.CT_BLUE, _open_options)
		_menu_item("Q", "QUIT", "Back to the map select", UITheme.KILL_RED, _back_to_lobby)
	else:
		_menu_title.text = "FAILED"
		_menu_title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.45))
		_menu_info.text = "%s\n%s  ·  %s  ·  %.2f%%  ·  %dx" % [_map_label(), _mods_label(), _progress_label(),
			accuracy() * 100.0, max_combo]
		first = _menu_item("R", "TRY AGAIN", "Start the map again right away", UITheme.T_ORANGE, _restart)
		_menu_item("Q", "QUIT", "Back to the map select", UITheme.KILL_RED, _back_to_lobby)
	_menu.visible = true
	_menu.modulate.a = 0.0
	create_tween().set_ignore_time_scale(true).tween_property(_menu, "modulate:a", 1.0, 0.18)
	_free_mouse()
	first.grab_focus.call_deferred()


func _hide_menu() -> void:
	if _menu:
		_menu.visible = false
	_menu_kind = ""
	_capture_mouse()


## Rato livre para os menus: a mira do CS segue o rato e faz de cursor.
func _free_mouse() -> void:
	_player.active = false
	_crosshair.visible = true
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		Input.warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.3, 0.5))
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _capture_mouse() -> void:
	_player.active = true
	_crosshair.visible = int(Settings.get_value("osu/cursor_mode")) != 1
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _progress_label() -> String:
	var first := beatmap.first_time()
	var progress := clampf((clock - first) / maxf(_last_object_end - first, 0.01), 0.0, 1.0)
	return "%d%% of the song" % roundi(progress * 100.0)


func _menu_item(key: String, title: String, subtitle: String, accent: Color, action: Callable) -> MenuItem:
	var item := MenuItem.new()
	item.key_label = key
	item.title = title
	item.subtitle = subtitle
	item.accent = accent
	item.custom_minimum_size = Vector2(440, 62)
	item.pressed.connect(action)
	_menu_items.add_child(item)
	return item


func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.visible = false
	%Root.add_child(_menu)
	# Escurece mais à esquerda (onde está o menu) e deixa ver o ecrã à direita.
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	var grad := Gradient.new()
	grad.set_color(0, Color(0.01, 0.012, 0.016, 0.88))
	grad.set_color(1, Color(0.01, 0.012, 0.016, 0.35))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.15, 0)
	tex.fill_to = Vector2(0.9, 0)
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	_menu.add_child(shade)
	var column := VBoxContainer.new()
	column.position = Vector2(80, 0)
	column.anchor_top = 0.0
	column.anchor_bottom = 1.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	_menu.add_child(column)
	_menu_title = Label.new()
	_menu_title.add_theme_font_override("font", UITheme.din(700, 75))
	_menu_title.add_theme_font_size_override("font_size", 72)
	column.add_child(_menu_title)
	_menu_info = Label.new()
	_menu_info.add_theme_font_override("font", UITheme.din(400, 100))
	_menu_info.add_theme_font_size_override("font_size", 16)
	_menu_info.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	column.add_child(_menu_info)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	column.add_child(gap)
	_menu_items = VBoxContainer.new()
	_menu_items.add_theme_constant_override("separation", 8)
	column.add_child(_menu_items)


# --- Opções a meio do jogo ------------------------------------------------------------

## Abre o painel de Opções (o mesmo do lobby) por cima do menu de pausa.
func _open_options() -> void:
	if phase != Phase.PAUSED:
		return
	if _options == null:
		_build_options()
	AudioManager.play_sfx(&"select")
	_options_layer.visible = true
	if _menu:
		_menu.visible = false
	_free_mouse()
	_options.focus_first.call_deferred()


func _close_options() -> void:
	AudioManager.play_sfx(&"back")
	Settings.save_settings()
	_options_layer.visible = false
	if phase == Phase.PAUSED and _menu:
		# Volta ao menu de pausa (não ao jogo).
		_menu.visible = true
		_free_mouse()
		_menu_items.get_child(0).grab_focus.call_deferred()
	else:
		_capture_mouse()


func _build_options() -> void:
	_options_layer = Control.new()
	_options_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	%Root.add_child(_options_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.012, 0.016, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_options_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_options_layer.add_child(center)
	_options = OptionsPanel.new()
	_options.custom_minimum_size = Vector2(660, 0)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "OPTIONS"
	title.add_theme_font_override("font", UITheme.din(700, 75))
	title.add_theme_font_size_override("font_size", 44)
	vbox.add_child(title)
	var back := MenuItem.new()
	back.key_label = "ESC"
	back.title = "BACK"
	back.subtitle = ""
	back.custom_minimum_size = Vector2(400, 56)
	back.pressed.connect(_close_options)
	vbox.add_child(back)
	_options.add_child(vbox)
	center.add_child(_options)


## Resolução a que se desenha o ecrã do osu! (o desenho é sempre feito em
## 1920×1080 e esticado; mais resolução = círculos e texto mais nítidos).
func _apply_screen_res() -> void:
	var res: Vector2i = Settings.SCREEN_RES[clampi(int(Settings.get_value("gfx/screen_res")), 0, Settings.SCREEN_RES.size() - 1)]
	_viewport.size = res
	_viewport.size_2d_override = OsuScreen.VIEW_SIZE
	_viewport.size_2d_override_stretch = true


## Mudanças nas Opções que se veem logo no jogo.
func _on_setting_changed(key: String) -> void:
	if key.begins_with("gfx/"):
		Settings.configure_environment($WorldEnvironment.environment)
	match key:
		"gfx/screen_res":
			_apply_screen_res()
		"osu/screen_distance":
			_screen.set_distance(float(Settings.get_value(key)))
		"osu/show_weapon":
			_player.viewmodel.visible = bool(Settings.get_value(key))
		"osu/skin":
			skin = OsuSkin.current()
			_sound_cache.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and phase in [Phase.INTRO, Phase.PLAYING, Phase.RESUMING]:
		_pause()


func _skip_intro() -> void:
	var target := beatmap.first_time() - beatmap.preempt() - 1.2
	if target <= clock:
		return
	AudioManager.play_sfx(&"select")
	if not _music_started:
		_music_started = true
		phase = Phase.PLAYING
		AudioManager.play_music(_music, Game.music_id(map), maxf(target, 0.0))
		AudioManager.set_music_speed(beatmap.rate, not "NC" in mods)
	else:
		AudioManager.seek(target)
	clock = target


## Discord: o mapa que se está a jogar, com estrelas, mods e o tempo que falta.
func _map_label() -> String:
	return "%s - %s [%s]" % [beatmap.artist, beatmap.title, beatmap.version]


func _mods_label() -> String:
	var stars := float(map.get("stars", 0.0)) * OsuMods.star_factor(mods)
	var text := "★%.1f" % stars
	if not mods.is_empty():
		text += " +" + "".join(mods)
	return text


func _presence_playing() -> void:
	var remaining := maxf(_last_object_end - maxf(clock, 0.0), 1.0) / beatmap.rate
	var verb := "Watching" if _auto else "Playing"
	DiscordPresence.set_status(_map_label(), "%s · %s" % [verb, _mods_label()], remaining + maxf(-clock, 0.0))


func _pause() -> void:
	# Pausar a meio da contagem volta ao menu sem perder a fase original.
	if phase != Phase.RESUMING:
		_phase_before_pause = phase
	phase = Phase.PAUSED
	resume_countdown = 0.0
	DiscordPresence.set_status(_map_label(), "Paused · " + _mods_label())
	AudioManager.set_music_paused(true)
	AudioManager.play_sfx(&"back")
	_show_menu("pause")


## Sai do menu de pausa: o jogo só continua depois de uma contagem de 3 s
## (a música e as notas ficam paradas até lá), para dar tempo de apontar.
func _resume() -> void:
	if phase != Phase.PAUSED:
		return
	_hide_menu()
	phase = Phase.RESUMING
	resume_countdown = RESUME_COUNTDOWN
	_last_count = int(ceilf(RESUME_COUNTDOWN))
	AudioManager.play_sfx(&"beep", -6.0)


func _update_resume(delta: float) -> void:
	resume_countdown -= delta
	var count := int(ceilf(resume_countdown))
	if count < _last_count and count > 0:
		_last_count = count
		AudioManager.play_sfx(&"beep", -6.0)
	if resume_countdown <= 0.0:
		resume_countdown = 0.0
		phase = _phase_before_pause
		AudioManager.set_music_paused(false)
		_presence_playing()
		AudioManager.play_sfx(&"select")


func _fail() -> void:
	if failed or "NF" in mods:
		health = maxf(health, 0.0)
		return
	failed = true
	phase = Phase.FAILING
	health = 0.0
	_fail_t = 0.0
	_fail_impact = aim_view / Vector2(OsuScreen.VIEW_SIZE) if aim_on_screen else Vector2(0.5, 0.5)
	AudioManager.wind_down(2.4)
	AudioManager.play_sfx(&"glitch", -2.0)
	DiscordPresence.set_status(_map_label(), "Failed · %.2f%% · %s" % [accuracy() * 100.0, _mods_label()])


## Animação de falhar (em tempo real, também durante a câmara lenta):
## 0.0–0.85 s o ecrã avaria e racha; 0.85 s explode em estilhaços com câmara lenta;
## 2.9 s os estilhaços voltam ao sítio e aparece o ecrã de FALHASTE.
func _update_fail(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_fail_t += real
	var t := _fail_t
	if t < 0.85:
		var g := clampf(t / 0.6, 0.0, 1.0)
		_screen.set_glitch(g, clampf((t - 0.2) / 0.6, 0.0, 1.0), _fail_impact)
		_player.add_punch(randf_range(-0.25, 0.25) * g, randf_range(-0.25, 0.25) * g)
		return
	if not _boomed:
		_boom()
	# Câmara lenta a voltar ao normal.
	Engine.time_scale = lerpf(0.25, 1.0, clampf((t - 1.15) / 1.0, 0.0, 1.0))
	if t >= 2.9 and not _reassembled:
		_reassembled = true
		phase = Phase.FAILED
		_screen.set_glitch(0.6, 0.0, _fail_impact)
		_screen.reassemble(0.75)
		AudioManager.play_sfx(&"glitch", -8.0, 1.6)
		_show_menu("fail")
	if _reassembled:
		_screen.set_glitch(clampf(0.6 - (t - 2.9) / 1.2, 0.0, 1.0) * 0.6, 0.0, _fail_impact)
		if t > 4.2:
			_fail_t = -1.0
			Engine.time_scale = 1.0
			_screen.set_glitch(0.0, 0.0)


func _boom() -> void:
	_boomed = true
	Engine.time_scale = 0.25
	_screen.set_glitch(1.0, 1.0, _fail_impact)
	_screen.shatter(_fail_impact)
	AudioManager.play_sfx(&"explosion", 2.0)
	AudioManager.play_sfx(&"glass", -2.0)
	_play_sound_named("failsound")
	_player.add_punch(randf_range(4.0, 6.0), randf_range(-3.0, 3.0))
	_flash.color = Color(1.0, 0.92, 0.8)
	_flash.modulate.a = 0.9
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_property(_flash, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# Tremor da câmara a acalmar.
	var shake := create_tween().set_ignore_time_scale(true)
	for k in 10:
		var f := 1.0 - k / 10.0
		shake.tween_callback(_player.add_punch.bind(randf_range(-1.5, 1.5) * f, randf_range(-1.5, 1.5) * f))
		shake.tween_interval(0.05)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	AudioManager.set_music_speed(1.0, true)


func _finish() -> void:
	phase = Phase.RESULTS
	result = {
		"score": score, "accuracy": accuracy(), "grade": grade(), "max_combo": max_combo,
		"counts": counts.duplicate(), "failed": false,
	}
	result["mods"] = mods.duplicate()
	DiscordPresence.set_status(_map_label(), "Rank %s · %.2f%% · %dx · %s" % [result.grade, result.accuracy * 100.0,
		max_combo, _mods_label()])
	Game.last_result = result
	if not map.is_empty() and not _auto:
		record = Game.save_score(map.id, result)
	_play_sound_named("applause")


func _restart() -> void:
	_leave(func() -> void: Game.play(map))


func _back_to_lobby() -> void:
	_leave(Game.back_to_lobby)


func _leave(then: Callable) -> void:
	if _leaving:
		return
	_leaving = true
	Engine.time_scale = 1.0
	AudioManager.play_sfx(&"back")
	AudioManager.fade_out(0.4)
	_flash.color = Color.BLACK
	var tween := create_tween()
	tween.tween_property(_flash, "modulate:a", 1.0, 0.4)
	tween.tween_callback(func() -> void:
		AudioManager.stop_music()
		then.call())
