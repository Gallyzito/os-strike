class_name MapSelect
extends Control
## Seleção de mapas (minimalista).
## - Direita: a lista de músicas. A roda do rato passa de música em música;
##   clicar numa música (ou Enter) mostra as dificuldades; clicar na dificuldade
##   escolhida (ou Enter, ou JOGAR) começa o mapa.
## - Esquerda: a imagem e os dados da dificuldade escolhida (CS/AR/OD/HP já com
##   os mods), estrelas e recorde.
## - Barra de baixo: VOLTAR, MODS, ALEATÓRIO, SKIN e JOGAR (todos clicáveis).
## - MODS (F1): painel com os mods do osu! para ligar e desligar.
## Escrever procura.

signal play_requested(map: Dictionary)
signal selection_changed(map: Dictionary)
signal back_requested

const PAD := 28.0
const TOP_H := 60.0
const BAR_H := 64.0
const SET_H := 60.0
const DIFF_H := 44.0
const GAP := 6.0
## Estrelas no fim dos gráficos de dificuldade (acima disto fica tudo cheio).
const SPECTRUM_MAX := 8.0

## Músicas: {"key", "title", "artist", "mapper", "source", "maps": Array}
var sets: Array[Dictionary] = []
var set_index := 0
var diff_index := 0

var _open := false
var _mods_open := false
var _filter := ""
var _filtered: Array[int] = []
var _last_diff: Dictionary[String, int] = {}
var _scroll := 0.0
var _expand := 1.0
var _rows: Array[Dictionary] = []
var _hover_row := -1
var _hover := ""
var _buttons: Dictionary[String, Rect2] = {}
var _bg: Texture2D
var _bg_prev: Texture2D
var _bg_fade := 1.0
var _detail_anim := 1.0
var _mods_anim := 0.0
var _best := {}
var _box := StyleBoxFlat.new()
var _title: Font
var _bold: Font
var _body: Font
var _mono: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_title = UITheme.din(700, 75)
	_bold = UITheme.din(700, 85)
	_body = UITheme.din(500, 100)
	_mono = UITheme.mono()
	_box.anti_aliasing = true


# --- Dados -----------------------------------------------------------------------

## Volta a ler a pasta de mapas e mantém (se possível) o mapa escolhido.
func refresh() -> void:
	var previous: String = current().get("id", Game.current_map.get("id", ""))
	sets.clear()
	var by_key := {}
	for map in Game.scan_maps():
		var key := String(map.dir)
		if not by_key.has(key):
			by_key[key] = sets.size()
			sets.append({
				"key": key, "title": map.title, "artist": map.artist, "mapper": map.get("mapper", "?"),
				"source": map.get("source", "os!strike"), "maps": [],
			})
		(sets[by_key[key]].maps as Array).append(map)
	for s in sets:
		(s.maps as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.stars) < float(b.stars) if float(a.stars) != float(b.stars) \
				else (a.notes as Array).size() < (b.notes as Array).size())
	sets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.title).naturalnocasecmp_to(b.title) < 0)
	set_index = 0
	diff_index = 0
	for i in sets.size():
		for j in (sets[i].maps as Array).size():
			if sets[i].maps[j].id == previous:
				set_index = i
				diff_index = j
	_apply_filter()
	_open = false
	_mods_open = false
	_on_selection(true)


func current() -> Dictionary:
	if set_index >= sets.size():
		return {}
	var maps: Array = sets[set_index].maps
	return maps[clampi(diff_index, 0, maps.size() - 1)]


## Escolhe uma música. `open`: mostra logo as dificuldades (clique); a roda não abre.
func select_set(index: int, open := false) -> void:
	if index < 0 or index >= sets.size():
		return
	if index == set_index:
		if open:
			open_set()
		return
	_last_diff[sets[set_index].key] = diff_index
	set_index = index
	diff_index = _last_diff.get(sets[index].key, 0)
	_open = open
	_expand = 0.0
	AudioManager.play_sfx(&"hover", -4.0, 0.9)
	_on_selection()


func open_set() -> void:
	if _open:
		return
	_open = true
	_expand = 0.0
	AudioManager.play_sfx(&"select", -6.0, 1.1)


func select_diff(index: int) -> void:
	var count: int = (sets[set_index].maps as Array).size() if set_index < sets.size() else 0
	if index < 0 or index >= count or index == diff_index:
		return
	diff_index = index
	AudioManager.play_sfx(&"hover", -6.0, randf_range(0.98, 1.06))
	_on_selection()


## Roda/setas: dentro de uma música aberta passa pelas dificuldades; senão de música em música.
func step(direction: int) -> void:
	if _filtered.is_empty():
		return
	if _open:
		var count: int = (sets[set_index].maps as Array).size()
		if diff_index + direction >= 0 and diff_index + direction < count:
			select_diff(diff_index + direction)
			return
	step_set(direction)


func step_set(direction: int) -> void:
	var pos := _filtered.find(set_index)
	if pos + direction >= 0 and pos + direction < _filtered.size():
		select_set(_filtered[pos + direction])


func random_set() -> void:
	if _filtered.size() < 2:
		return
	var choice := set_index
	while choice == set_index:
		choice = _filtered[randi() % _filtered.size()]
	select_set(choice, true)


func _apply_filter() -> void:
	_filtered.clear()
	for i in sets.size():
		if _matches(sets[i]):
			_filtered.append(i)
	if not _filtered.is_empty() and not set_index in _filtered:
		set_index = _filtered[0]
		diff_index = 0
		_on_selection()


func _matches(s: Dictionary) -> bool:
	if _filter.is_empty():
		return true
	var text := "%s %s %s" % [s.title, s.artist, s.mapper]
	for m: Dictionary in s.maps:
		text += " " + String(m.difficulty)
	for word in _filter.split(" ", false):
		if text.findn(word) < 0:
			return false
	return true


func _on_selection(instant := false) -> void:
	var map := current()
	if map.is_empty():
		return
	_best = Game.best_score(map.id)
	var bg := Game.background_blur(map)
	if bg != _bg:
		_bg_prev = _bg
		_bg = bg
		_bg_fade = 1.0 if instant else 0.0
	_detail_anim = 1.0 if instant else 0.0
	selection_changed.emit(map)


# --- Entrada ------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_update_hover(event.position)
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if not _mods_open:
					step(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if not _mods_open:
					step(1)
			MOUSE_BUTTON_LEFT:
				_click()
			MOUSE_BUTTON_RIGHT:
				if _hover == "skin":
					_change_skin(-1)
		accept_event()
	elif event is InputEventMouseMotion:
		_update_hover(event.position)


func _click() -> void:
	if _hover.begins_with("mod:"):
		OsuMods.toggle(_hover.substr(4))
		AudioManager.play_sfx(&"select", -4.0, 1.2)
		_on_selection()
		return
	match _hover:
		"play":
			_request_play()
		"random":
			random_set()
		"back":
			back_requested.emit()
		"skin":
			_change_skin(1)
		"mods":
			_toggle_mods()
		"mods_clear":
			OsuMods.set_active([] as Array[String])
			AudioManager.play_sfx(&"back")
			_on_selection()
		"mods_sheet":
			pass
		_:
			if _mods_open:
				# Clicar fora do painel fecha-o.
				_toggle_mods()
				return
			if _hover_row < 0:
				return
			var row: Dictionary = _rows[_hover_row]
			if row.kind == "set":
				select_set(row.set, true)
			elif row.diff == diff_index and row.set == set_index:
				_request_play()
			else:
				select_diff(row.diff)


func _toggle_mods() -> void:
	_mods_open = not _mods_open
	AudioManager.play_sfx(&"select" if _mods_open else &"back", -4.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed:
		return
	var key := event as InputEventKey
	var handled := true
	if _mods_open:
		match key.keycode:
			KEY_ESCAPE, KEY_F1:
				_toggle_mods()
			KEY_ENTER, KEY_KP_ENTER:
				_mods_open = false
				_request_play()
			_:
				var found := false
				for m in OsuMods.LIST:
					if int(m.key) == key.keycode and not (m.id in ["PF", "NC"] and not key.shift_pressed) \
							and not (m.id in ["SD", "DT"] and key.shift_pressed):
						OsuMods.toggle(m.id)
						AudioManager.play_sfx(&"select", -4.0, 1.2)
						_on_selection()
						found = true
						break
				handled = found
		if handled:
			get_viewport().set_input_as_handled()
		return
	match key.keycode:
		KEY_UP:
			step(-1)
		KEY_DOWN:
			step(1)
		KEY_LEFT:
			step_set(-1)
		KEY_RIGHT:
			step_set(1)
		KEY_ENTER, KEY_KP_ENTER:
			if _open:
				_request_play()
			else:
				open_set()
		KEY_F1:
			_toggle_mods()
		KEY_F2:
			random_set()
		KEY_TAB:
			_change_skin(-1 if key.shift_pressed else 1)
		KEY_BACKSPACE:
			if _filter.is_empty():
				handled = false
			else:
				_filter = _filter.substr(0, _filter.length() - 1)
				_apply_filter()
		KEY_ESCAPE:
			# Com uma pesquisa escrita, o ESC limpa-a; senão volta ao lobby.
			if _filter.is_empty():
				handled = false
			else:
				_filter = ""
				_apply_filter()
		_:
			var c := key.unicode
			if c >= 32 and not key.ctrl_pressed and not key.alt_pressed and (c != 32 or not _filter.is_empty()) \
					and _filter.length() < 32:
				_filter += String.chr(c)
				_apply_filter()
			else:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _change_skin(direction: int) -> void:
	var names := _skin_names()
	var index := names.find(String(Settings.get_value("osu/skin")))
	Settings.set_value("osu/skin", names[posmod(index + direction, names.size())])
	Settings.save_settings()
	AudioManager.play_sfx(&"hover", -4.0, 1.1)


func _skin_names() -> Array[String]:
	var names: Array[String] = [""]
	names.append_array(OsuSkin.list_skins())
	return names


func _request_play() -> void:
	var map := current()
	if map.is_empty():
		return
	AudioManager.play_sfx(&"select")
	play_requested.emit(map)


func _update_hover(pos: Vector2) -> void:
	var old := _hover
	var old_row := _hover_row
	_hover = ""
	_hover_row = -1
	# Os botões do painel de mods ficam por cima de tudo (foram desenhados depois).
	var keys := _buttons.keys()
	keys.reverse()
	for name: String in keys:
		if _buttons[name].has_point(pos):
			_hover = name
			break
	if _hover.is_empty() and not _mods_open:
		for i in _rows.size():
			if (_rows[i].rect as Rect2).has_point(pos):
				_hover_row = i
	var changed := (_hover != old and not _hover.is_empty() and _hover != "mods_sheet") or (_hover_row != old_row and _hover_row >= 0)
	if changed:
		AudioManager.play_sfx(&"hover", -14.0, 1.2)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_expand = move_toward(_expand, 1.0, delta * 5.0)
	_bg_fade = move_toward(_bg_fade, 1.0, delta * 3.0)
	_detail_anim = move_toward(_detail_anim, 1.0, delta * 6.0)
	_mods_anim = move_toward(_mods_anim, 1.0 if _mods_open else 0.0, delta * 7.0)
	queue_redraw()


# --- Desenho -----------------------------------------------------------------------------

func _draw() -> void:
	_buttons.clear()
	var w := size.x
	var h := size.y
	_draw_background(w, h)
	var split := clampf(w * 0.4, 340.0, 520.0)
	_draw_list(Rect2(split + 8.0, TOP_H + 8.0, w - split - 8.0 - PAD, h - TOP_H - BAR_H - 16.0))
	_draw_info(Rect2(PAD, TOP_H + 12.0, split - PAD - 24.0, h - TOP_H - BAR_H - 24.0))
	_draw_top(w)
	_draw_bar(w, h)
	if _mods_anim > 0.01:
		_draw_mods(w, h)


func _draw_background(w: float, h: float) -> void:
	var full := Rect2(Vector2.ZERO, Vector2(w, h))
	draw_rect(full, Color(0.02, 0.022, 0.03))
	if _bg_prev and _bg_fade < 1.0:
		_cover(_bg_prev, full, Color(1, 1, 1, 1.0 - _bg_fade))
	if _bg:
		_cover(_bg, full, Color(1, 1, 1, _bg_fade))
	draw_rect(full, Color(0.02, 0.022, 0.03, 0.72))


func _draw_top(w: float) -> void:
	draw_string(_title, Vector2(PAD, 40), "Song select", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	var maps := 0
	for i in _filtered:
		maps += (sets[i].maps as Array).size()
	var tx := PAD + _title.get_string_size("Song select", HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 14.0
	draw_string(_body, Vector2(tx, 39), "%d songs · %d maps" % [_filtered.size(), maps], HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1, 1, 1, 0.4))
	# Pesquisa.
	var box := Rect2(w - PAD - 260.0, 16.0, 260.0, 32.0)
	if box.position.x > tx + 200.0:
		_rrect(box, Color(1, 1, 1, 0.07), 16.0, Color(UITheme.T_ORANGE, 0.8) if not _filter.is_empty() else Color(0, 0, 0, 0), 1.5)
		var icon := box.position + Vector2(18, 16)
		draw_arc(icon, 5.5, 0.0, TAU, 16, Color(1, 1, 1, 0.55), 1.6, true)
		draw_line(icon + Vector2(4, 4), icon + Vector2(8.5, 8.5), Color(1, 1, 1, 0.55), 1.6, true)
		var caret := "|" if int(Time.get_ticks_msec() / 500.0) % 2 == 0 else ""
		var text := _filter + caret if not _filter.is_empty() else "Search"
		draw_string(_body, box.position + Vector2(34, 21), text, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 44.0, 14,
			Color.WHITE if not _filter.is_empty() else Color(1, 1, 1, 0.35))


# --- Informação do mapa ---------------------------------------------------------------------

func _draw_info(area: Rect2) -> void:
	var map := current()
	if map.is_empty():
		return
	var mods := OsuMods.active()
	var a := 0.4 + 0.6 * _detail_anim
	var x := area.position.x
	var w := area.size.x
	var y := area.position.y
	# Imagem.
	var img_h := clampf(area.size.y - 368.0, 90.0, w * 0.56)
	var img := Rect2(x, y, w, img_h)
	var tex := Game.background(map)
	if tex:
		_cover(tex, img, Color(1, 1, 1, a))
	_rrect(img, Color(0, 0, 0, 0), 10.0, Color(1, 1, 1, 0.12), 1.0)
	y = img.end.y + 34.0
	# Título, artista.
	draw_string(_title, Vector2(x, y), _fit(_title, String(map.title), 30, w), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, a))
	y += 22.0
	draw_string(_body, Vector2(x, y), _fit(_body, String(map.artist), 15, w), HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		Color(1, 1, 1, 0.6 * a))
	y += 14.0
	# Dificuldade: medidor circular com o espectro de cores, a encher até às estrelas.
	var stars := float(map.stars) * OsuMods.star_factor(mods)
	var col := Game.difficulty_color(stars)
	var gauge_c := Vector2(x + 36.0, y + 36.0)
	_draw_star_gauge(gauge_c, 32.0, stars, a)
	var tx := x + 88.0
	draw_string(_bold, Vector2(tx, y + 30.0), _fit(_bold, String(map.difficulty), 20, w - 92.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		Color(1, 1, 1, a))
	var tier := Game.difficulty_tier(stars)
	var tag_w := _mono.get_string_size(tier, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 14.0
	var tag := Rect2(tx, y + 40.0, tag_w, 17.0)
	_rrect(tag, Color(col, 0.18 * a), 8.5, Color(col, 0.75 * a), 1.0)
	draw_string(_mono, Vector2(tag.position.x, tag.end.y - 5.0), tier, HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 10,
		Color(col.lightened(0.35), a))
	draw_string(_body, Vector2(tag.end.x + 10.0, tag.end.y - 4.0), _fit(_body, "mapped by %s" % map.get("mapper", "?"), 12,
		w - (tag.end.x + 10.0 - x)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.4 * a))
	y += 96.0
	# Linha de dados.
	var rate := OsuMods.speed(mods)
	var info := "%s   ·   %d BPM   ·   %d objects" % [_fmt_time(float(map.get("length", 0.0)) / rate),
		int(roundf(float(map.get("bpm", 0)) * rate)), (map.notes as Array).size()]
	draw_string(_body, Vector2(x, y), info, HORIZONTAL_ALIGNMENT_LEFT, w, 13, Color(1, 1, 1, 0.65 * a))
	y += 24.0
	# CS AR OD HP (com os mods).
	var base := Vector4(float(map.get("cs", 4.0)), float(map.get("ar", 5.0)), float(map.get("od", 5.0)), float(map.get("hp", 5.0)))
	var mod := OsuMods.adjust_stats(base.x, base.y, base.z, base.w, mods)
	mod.y = OsuMods.effective_ar(mod.y, rate)
	mod.z = OsuMods.effective_od(mod.z, rate)
	var names: Array[String] = ["CS", "AR", "OD", "HP"]
	for i in 4:
		var bv: float = base[i]
		var mv: float = mod[i]
		var bar := Rect2(x + 34.0, y - 5.0, w - 34.0 - 44.0, 5.0)
		draw_string(_bold, Vector2(x, y + 1.0), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.55 * a))
		_rrect(bar, Color(1, 1, 1, 0.1 * a), 2.5)
		var vcol := Color(1, 1, 1, 0.85)
		if mv > bv + 0.05:
			vcol = Color(1.0, 0.5, 0.45)
		elif mv < bv - 0.05:
			vcol = Color(0.5, 0.95, 0.55)
		_rrect(Rect2(bar.position, Vector2(bar.size.x * clampf(mv / 10.0, 0.02, 1.0), bar.size.y)), Color(vcol, a), 2.5)
		draw_string(_mono, Vector2(bar.end.x + 8.0, y + 1.0), _num(mv), HORIZONTAL_ALIGNMENT_RIGHT, 36.0, 12, Color(vcol, a))
		y += 20.0
	y += 12.0
	# Recorde.
	if _best.is_empty():
		draw_string(_body, Vector2(x, y), "Not played yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.35 * a))
	else:
		var gcol: Color = UITheme.GRADE_COLORS.get(String(_best.grade), UITheme.TEXT)
		draw_string(_title, Vector2(x, y + 4.0), String(_best.grade), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(gcol, a))
		draw_string(_body, Vector2(x + 34.0, y), "%s   ·   %.2f%%   ·   %dx" % [_fmt_score(int(_best.score)),
			float(_best.accuracy) * 100.0, int(_best.get("max_combo", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7 * a))


# --- Lista -------------------------------------------------------------------------------------

func _draw_list(area: Rect2) -> void:
	_rows.clear()
	if _filtered.is_empty():
		var msg := "No maps found" if _filter.is_empty() else "No results for \"%s\"" % _filter
		draw_string(_bold, Vector2(area.position.x, area.get_center().y), msg, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, 20,
			Color(1, 1, 1, 0.6))
		if _filter.is_empty():
			draw_string(_body, Vector2(area.position.x, area.get_center().y + 24.0), "Put maps or .osz files in: " + Game.maps_dir(),
				HORIZONTAL_ALIGNMENT_CENTER, area.size.x, 12, Color(1, 1, 1, 0.35))
		return
	var layout: Array[Dictionary] = []
	var y := 0.0
	var selected_center := 0.0
	var ease := 1.0 - pow(1.0 - _expand, 3.0)
	for i in _filtered:
		layout.append({"kind": "set", "set": i, "diff": -1, "y": y, "h": SET_H})
		if i == set_index and not _open:
			selected_center = y + SET_H * 0.5
		y += SET_H + GAP
		if i == set_index and _open:
			var maps: Array = sets[i].maps
			for j in maps.size():
				var dh := DIFF_H * ease
				layout.append({"kind": "diff", "set": i, "diff": j, "y": y, "h": dh})
				if j == diff_index:
					selected_center = y + dh * 0.5
				y += (dh + GAP) * ease
	var target := selected_center - area.size.y * 0.45
	_scroll = lerpf(_scroll, target, 1.0 - exp(-get_process_delta_time() * 12.0))
	for row in layout:
		var top: float = area.position.y + float(row.y) - _scroll
		var rh: float = row.h
		if top + rh < area.position.y - 2.0 or top > area.end.y + 2.0 or rh < 4.0:
			continue
		var indent := 20.0 if row.kind == "diff" else 0.0
		var rect := Rect2(area.position.x + indent, top, area.size.x - indent, rh)
		# Esbate junto às bordas da lista.
		var fade := clampf((top - area.position.y + 30.0) / 50.0, 0.0, 1.0) * clampf((area.end.y - top - rh + 30.0) / 50.0, 0.0, 1.0)
		row["rect"] = rect
		_rows.append(row)
		var hovered := _rows.size() - 1 == _hover_row
		if row.kind == "set":
			_draw_set_row(rect, sets[row.set], row.set == set_index, hovered, fade)
		else:
			_draw_diff_row(rect, sets[row.set].maps[row.diff], row.diff == diff_index, hovered, fade * ease)


func _draw_set_row(r: Rect2, s: Dictionary, selected: bool, hovered: bool, a: float) -> void:
	var bg := 0.1 if selected else (0.075 if hovered else 0.045)
	_rrect(r, Color(1, 1, 1, bg * a), 10.0)
	if selected:
		_rrect(Rect2(r.position + Vector2(0, 10), Vector2(3, r.size.y - 20)), Color(UITheme.T_ORANGE, a), 1.5)
	var maps: Array = s.maps
	var thumb := Rect2(r.position.x + 10.0, r.position.y + 8.0, 76.0, r.size.y - 16.0)
	var tex := Game.background(maps[0])
	if tex:
		_cover(tex, thumb, Color(1, 1, 1, a))
	var tx := thumb.end.x + 14.0
	var right := r.end.x - 16.0
	var chart_w := clampf(r.size.x * 0.22, 90.0, 170.0)
	var tw := right - tx - chart_w - 16.0
	draw_string(_bold, Vector2(tx, r.position.y + 27.0), _fit(_bold, String(s.title), 17, tw), HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
		Color(1, 1, 1, (1.0 if selected else 0.85) * a))
	draw_string(_body, Vector2(tx, r.position.y + 46.0), _fit(_body, String(s.artist), 13, tw), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(1, 1, 1, 0.5 * a))
	_draw_spread(Rect2(right - chart_w, r.position.y + 12.0, chart_w, r.size.y - 24.0), maps, a)


## Gráfico das dificuldades de uma música: o espectro de 0 a 8★ (apagado), a
## faixa que a música cobre (acesa) e um traço por dificuldade, na sua cor.
func _draw_spread(r: Rect2, maps: Array, a: float) -> void:
	var factor := OsuMods.star_factor(OsuMods.active())
	var lo := INF
	var hi := 0.0
	for m: Dictionary in maps:
		lo = minf(lo, float(m.stars) * factor)
		hi = maxf(hi, float(m.stars) * factor)
	var line_y := r.end.y - 6.0
	var steps := 40
	var seg := r.size.x / steps
	for k in steps:
		var v := (k + 0.5) / steps * SPECTRUM_MAX
		var inside := v >= lo - SPECTRUM_MAX / steps and v <= hi + SPECTRUM_MAX / steps
		var c := Game.difficulty_color(v)
		var th := 3.0 if inside else 1.5
		draw_rect(Rect2(r.position.x + k * seg, line_y - th * 0.5, seg + 0.5, th), Color(c, (0.9 if inside else 0.16) * a))
	for m: Dictionary in maps:
		var v := float(m.stars) * factor
		var px := r.position.x + clampf(v / SPECTRUM_MAX, 0.0, 1.0) * r.size.x
		var c := Game.difficulty_color(v)
		draw_rect(Rect2(px - 1.0, line_y - 9.0, 2.0, 12.0), Color(c.lightened(0.2), a))
	var label: String = "%.1f – %.1f★" % [lo, hi] if hi - lo > 0.05 else "%.1f★" % hi
	draw_string(_mono, Vector2(r.position.x, line_y - 13.0), label, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, 10,
		Color(1, 1, 1, 0.45 * a))


func _draw_diff_row(r: Rect2, map: Dictionary, selected: bool, hovered: bool, a: float) -> void:
	if a <= 0.02:
		return
	var stars := float(map.stars) * OsuMods.star_factor(OsuMods.active())
	var col := Game.difficulty_color(stars)
	var bright := col.lightened(0.3)
	# Fundo com a cor da dificuldade a desvanecer para a direita.
	if selected:
		_rrect_gradient(r, 10.0, Color(col, 0.34 * a), Color(col, 0.05 * a))
		_rrect(r, Color(0, 0, 0, 0), 10.0, Color(col, 0.9 * a), 1.5)
	else:
		_rrect_gradient(r, 10.0, Color(col, (0.24 if hovered else 0.15) * a), Color(1, 1, 1, 0.025 * a))
	_rrect(Rect2(r.position.x + 1.0, r.position.y + 9.0, 3.0, r.size.y - 18.0), Color(col, a), 1.5)
	var mid := r.get_center().y
	# Medidor de 10 segmentos (um por estrela), cada um na cor do seu nível.
	var shimmer: float = fmod(Time.get_ticks_msec() / 1000.0 * 6.0, 16.0) - 3.0 if selected else -10.0
	var meter_end := _draw_meter(Vector2(r.position.x + 16.0, mid - 8.0), 16.0, stars, a, shimmer)
	draw_string(_title, Vector2(meter_end + 12.0, mid + 8.0), "%.1f" % stars, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(bright, a))
	var name_x := meter_end + 62.0
	var right := r.end.x - 14.0
	var best := Game.best_score(map.id)
	if not best.is_empty():
		var gcol: Color = UITheme.GRADE_COLORS.get(String(best.grade), UITheme.TEXT)
		draw_string(_title, Vector2(right - 30.0, mid + 8.0), String(best.grade), HORIZONTAL_ALIGNMENT_RIGHT, 30.0, 20, Color(gcol, a))
		right -= 40.0
	if selected:
		# Triângulo de "jogar" a pulsar.
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
		var px := right - 8.0
		draw_colored_polygon(PackedVector2Array([Vector2(px - 7, mid - 7), Vector2(px + 5, mid), Vector2(px - 7, mid + 7)]),
			Color(bright, pulse * a))
		right -= 24.0
	var tier := Game.difficulty_tier(stars)
	var tier_w := _mono.get_string_size(tier, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(_mono, Vector2(right - tier_w, mid + 4.0), tier, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(bright, (0.85 if selected else 0.55) * a))
	right -= tier_w + 14.0
	draw_string(_bold, Vector2(name_x, mid + 6.0), _fit(_bold, String(map.difficulty), 15, right - name_x), HORIZONTAL_ALIGNMENT_LEFT,
		-1, 15, Color(1, 1, 1, a))


## Medidor de estrelas: 10 segmentos inclinados, cheios até às estrelas (o último
## em parte), cada um com a cor do espectro do seu nível. `shimmer` = posição do
## brilho que passa pelos segmentos (negativo = sem brilho). Devolve onde acaba.
func _draw_meter(origin: Vector2, height: float, stars: float, a: float, shimmer := -10.0) -> float:
	var seg_w := 6.0
	var gap := 3.0
	var slant := height * 0.4
	for i in 10:
		var x := origin.x + i * (seg_w + gap)
		var top := origin.y
		var bottom := origin.y + height
		draw_colored_polygon(PackedVector2Array([Vector2(x + slant, top), Vector2(x + slant + seg_w, top),
			Vector2(x + seg_w, bottom), Vector2(x, bottom)]), Color(1, 1, 1, 0.07 * a))
		var fill := clampf(stars - i, 0.0, 1.0)
		if fill <= 0.0:
			continue
		var y := bottom - height * fill
		var s := slant * fill
		var c := Game.difficulty_color(minf(i + 0.8, stars))
		var glow := clampf(1.0 - absf(shimmer - i) / 1.6, 0.0, 1.0)
		c = c.lerp(Color.WHITE, glow * 0.55)
		draw_colored_polygon(PackedVector2Array([Vector2(x + s, y), Vector2(x + s + seg_w, y),
			Vector2(x + seg_w, bottom), Vector2(x, bottom)]), Color(c, a))
	return origin.x + 10.0 * (seg_w + gap) - gap + slant


## Medidor circular (270°) com o espectro de cores, aceso até às estrelas, com o
## número ao centro. Enche com uma animação quando se muda de dificuldade.
func _draw_star_gauge(c: Vector2, radius: float, stars: float, a: float) -> void:
	var start := deg_to_rad(135.0)
	var sweep := deg_to_rad(270.0)
	var steps := 54
	var shown := stars * (1.0 - pow(1.0 - _detail_anim, 3.0))
	var col := Game.difficulty_color(stars)
	draw_circle(c, radius + 7.0, Color(0, 0, 0, 0.35 * a))
	for k in steps:
		var v0 := float(k) / steps * SPECTRUM_MAX
		var lit := v0 < shown
		var seg_c := Game.difficulty_color(v0 + SPECTRUM_MAX / steps * 0.5)
		var a0 := start + sweep * k / steps
		var a1 := start + sweep * (k + 1) / steps
		draw_arc(c, radius, a0, a1 + 0.004, 3, Color(seg_c, (0.95 if lit else 0.24) * a), 6.0 if lit else 3.0, true)
	var tip := c + Vector2.from_angle(start + sweep * clampf(shown / SPECTRUM_MAX, 0.0, 1.0)) * radius
	draw_circle(tip, 8.0, Color(col, 0.3 * a))
	draw_circle(tip, 3.5, Color(1, 1, 1, a))
	draw_string(_title, Vector2(c.x - radius, c.y + 8.0), "%.1f" % stars, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 24,
		Color(col.lightened(0.35), a))
	_star(Vector2(c.x, c.y + radius - 2.0), 5.0, Color(col.lightened(0.2), a))


## Retângulo arredondado com degradé horizontal (a cor depende do x).
func _rrect_gradient(r: Rect2, radius: float, left: Color, right: Color) -> void:
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var centers := [r.end - Vector2(rad, rad), Vector2(r.position.x + rad, r.end.y - rad), r.position + Vector2(rad, rad),
		Vector2(r.end.x - rad, r.position.y + rad)]
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for q in 4:
		for k in 7:
			var p: Vector2 = centers[q] + Vector2.from_angle(q * PI * 0.5 + k * PI / 12.0) * rad
			pts.append(p)
			cols.append(left.lerp(right, clampf((p.x - r.position.x) / r.size.x, 0.0, 1.0)))
	draw_polygon(pts, cols)


# --- Barra de baixo ----------------------------------------------------------------------------

func _draw_bar(w: float, h: float) -> void:
	var y := h - BAR_H
	draw_rect(Rect2(0, y, w, BAR_H), Color(0.015, 0.016, 0.022, 0.92))
	draw_rect(Rect2(0, y, w, 1), Color(1, 1, 1, 0.08))
	var x := PAD
	var by := y + 12.0
	var mods := OsuMods.active()
	var skin_name := OsuSkin.current().display_name()
	var items := [
		["back", "ESC", "Back", ""],
		["mods", "F1", "Mods", str(mods.size()) if not mods.is_empty() else ""],
		["random", "F2", "Random", ""],
		["skin", "TAB", "Skin: " + skin_name, ""],
	]
	var play_w := 168.0
	var max_x := w - PAD - play_w - 12.0
	for it in items:
		var label: String = it[2]
		var key: String = it[1]
		var kw := _mono.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 12.0
		var bw := _bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + kw + 44.0
		if it[0] == "skin":
			bw = minf(bw, max_x - x)
		if bw < 60.0:
			continue
		var r := Rect2(x, by, bw, 40.0)
		var hot: bool = _hover == it[0] or (it[0] == "mods" and _mods_open)
		_rrect(r, Color(1, 1, 1, 0.14 if hot else 0.06), 20.0)
		var kr := Rect2(r.position.x + 12.0, r.position.y + 12.0, kw, 16.0)
		_rrect(kr, Color(1, 1, 1, 0.12), 4.0)
		draw_string(_mono, Vector2(kr.position.x, kr.end.y - 4.0), key, HORIZONTAL_ALIGNMENT_CENTER, kw, 10, Color(1, 1, 1, 0.75))
		draw_string(_bold, Vector2(kr.end.x + 10.0, r.position.y + 25.0), _fit(_bold, label, 14, r.end.x - kr.end.x - 18.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE if hot else Color(1, 1, 1, 0.85))
		if not String(it[3]).is_empty():
			var badge := Vector2(r.end.x - 4.0, r.position.y + 4.0)
			draw_circle(badge, 9.0, UITheme.T_ORANGE)
			draw_string(_bold, badge + Vector2(-9, 4.5), it[3], HORIZONTAL_ALIGNMENT_CENTER, 18.0, 11, Color(0.05, 0.05, 0.06))
		_buttons[it[0]] = r
		x = r.end.x + 10.0
	# JOGAR (com os mods ativos ao lado).
	var play := Rect2(w - PAD - play_w, by, play_w, 40.0)
	var hot := _hover == "play"
	_rrect(play, UITheme.T_ORANGE.lightened(0.15 if hot else 0.0), 20.0)
	var tri := Vector2(play.position.x + 26.0, play.get_center().y)
	draw_colored_polygon(PackedVector2Array([tri + Vector2(-5, -8), tri + Vector2(8, 0), tri + Vector2(-5, 8)]), Color(0.05, 0.05, 0.06))
	draw_string(_title, Vector2(play.position.x + 42.0, play.position.y + 29.0), "Play", HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
		Color(0.05, 0.05, 0.06))
	draw_string(_mono, Vector2(play.end.x - 70.0, play.position.y + 25.0), "ENTER", HORIZONTAL_ALIGNMENT_RIGHT, 56.0, 10,
		Color(0.05, 0.05, 0.06, 0.55))
	_buttons["play"] = play
	var cx := play.position.x - 10.0
	for i in range(mods.size() - 1, -1, -1):
		var id: String = mods[i]
		var chip := Rect2(cx - 34.0, by + 10.0, 34.0, 20.0)
		if chip.position.x < x:
			break
		_rrect(chip, Color(OsuMods.GROUP_COLORS[int(OsuMods.info(id).group)], 0.9), 6.0)
		draw_string(_bold, Vector2(chip.position.x, chip.end.y - 5.0), id, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 12,
			Color(0.05, 0.05, 0.06))
		cx -= 40.0


# --- Painel de mods -----------------------------------------------------------------------------

func _draw_mods(w: float, h: float) -> void:
	var k := 1.0 - pow(1.0 - _mods_anim, 3.0)
	draw_rect(Rect2(0, 0, w, h - BAR_H), Color(0, 0, 0, 0.5 * k))
	var sw := minf(w - PAD * 2.0, 900.0)
	var sh := 330.0
	var sheet := Rect2((w - sw) * 0.5, h - BAR_H - sh - 14.0 + (1.0 - k) * 40.0, sw, sh)
	_buttons["mods_sheet"] = sheet
	_rrect(sheet, Color(0.055, 0.06, 0.075, 0.98 * k), 16.0, Color(1, 1, 1, 0.08 * k), 1.0)
	var mods := OsuMods.active()
	var x0 := sheet.position.x + 24.0
	var y := sheet.position.y + 38.0
	draw_string(_title, Vector2(x0, y), "Mods", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, k))
	var mult := OsuMods.multiplier(mods)
	var mcol := Color(1, 1, 1, 0.8) if is_equal_approx(mult, 1.0) else (Color(0.5, 0.95, 0.55) if mult > 1.0 else Color(1.0, 0.55, 0.45))
	draw_string(_body, Vector2(x0 + 80.0, y - 2.0), "Score ×%.2f" % mult, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(mcol, k))
	var clear := Rect2(sheet.end.x - 24.0 - 96.0, sheet.position.y + 16.0, 96.0, 30.0)
	_rrect(clear, Color(1, 1, 1, (0.14 if _hover == "mods_clear" else 0.06) * k), 15.0)
	draw_string(_bold, Vector2(clear.position.x, clear.end.y - 9.0), "Clear", HORIZONTAL_ALIGNMENT_CENTER, clear.size.x, 13,
		Color(1, 1, 1, 0.85 * k))
	_buttons["mods_clear"] = clear
	y += 22.0
	var label_w := 150.0
	var tile_w := clampf((sw - 48.0 - label_w) / 7.0 - 8.0, 70.0, 100.0)
	var tile_h := 74.0
	for g in 3:
		var gx := x0 + label_w
		draw_string(_mono, Vector2(x0, y + tile_h * 0.5 + 4.0), OsuMods.GROUP_NAMES[g], HORIZONTAL_ALIGNMENT_LEFT, label_w - 10.0, 10,
			Color(OsuMods.GROUP_COLORS[g], 0.9 * k))
		for m in OsuMods.LIST:
			if int(m.group) != g:
				continue
			var tile := Rect2(gx, y, tile_w, tile_h)
			var on: bool = m.id in mods
			var hot := _hover == "mod:" + String(m.id)
			var col: Color = OsuMods.GROUP_COLORS[g]
			if on:
				_rrect(tile, Color(col, 0.92 * k), 12.0)
			else:
				_rrect(tile, Color(1, 1, 1, (0.1 if hot else 0.045) * k), 12.0, Color(col, (0.6 if hot else 0.0) * k), 1.5)
			var ink := Color(0.05, 0.05, 0.06, k) if on else Color(1, 1, 1, k)
			draw_string(_title, Vector2(tile.position.x, tile.position.y + 34.0), m.id, HORIZONTAL_ALIGNMENT_CENTER, tile.size.x, 26, ink)
			draw_string(_body, Vector2(tile.position.x + 4.0, tile.position.y + 52.0), _fit(_body, m.name, 10, tile.size.x - 8.0),
				HORIZONTAL_ALIGNMENT_CENTER, tile.size.x - 8.0, 10, Color(ink, 0.8 * k))
			draw_string(_mono, Vector2(tile.position.x, tile.position.y + 66.0), ("×%.2f" % float(m.mult)).trim_suffix("0").trim_suffix(".0"),
				HORIZONTAL_ALIGNMENT_CENTER, tile.size.x, 9, Color(ink, 0.55 * k))
			_buttons["mod:" + String(m.id)] = tile
			gx += tile_w + 8.0
		y += tile_h + 12.0
	# Descrição do mod debaixo do rato.
	var desc := "Click to toggle · keys Q W E A S D F G V (Shift+S = PF, Shift+D = NC)"
	if _hover.begins_with("mod:"):
		var info := OsuMods.info(_hover.substr(4))
		desc = "%s — %s" % [info.name, info.desc]
	draw_string(_body, Vector2(x0, sheet.end.y - 16.0), desc, HORIZONTAL_ALIGNMENT_LEFT, sw - 48.0, 12, Color(1, 1, 1, 0.55 * k))


# --- Utilitários ------------------------------------------------------------------------------

func _rrect(r: Rect2, fill: Color, radius: float, border := Color(0, 0, 0, 0), border_w := 0.0) -> void:
	_box.bg_color = fill
	_box.set_corner_radius_all(int(radius))
	_box.border_color = border
	_box.set_border_width_all(int(border_w) if border.a > 0.0 else 0)
	_box.draw_center = fill.a > 0.0
	draw_style_box(_box, r)


func _cover(tex: Texture2D, r: Rect2, modulate: Color) -> void:
	var ts := tex.get_size()
	var k := maxf(r.size.x / ts.x, r.size.y / ts.y)
	var src_size := r.size / k
	draw_texture_rect_region(tex, r, Rect2((ts - src_size) * 0.5, src_size), modulate)


func _star(c: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var ang := -PI / 2.0 + k * PI / 5.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * (radius if k % 2 == 0 else radius * 0.45))
	draw_colored_polygon(pts, color)


func _fit(font: Font, text: String, font_size: int, max_w: float) -> String:
	if max_w <= 0.0 or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var out := text
	while out.length() > 1 and font.get_string_size(out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_w:
		out = out.substr(0, out.length() - 1)
	return out.strip_edges() + "…"


static func _num(v: Variant) -> String:
	var f := float(v)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else "%.1f" % f


static func _fmt_time(seconds: float) -> String:
	var s := int(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [s / 60, s % 60]


static func _fmt_score(score: int) -> String:
	var s := str(score).lpad(7, "0")
	return "%s %s" % [s.substr(0, 4), s.substr(4)]
