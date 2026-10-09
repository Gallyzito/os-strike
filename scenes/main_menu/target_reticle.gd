extends Control
## Cantos de "alvo bloqueado" à volta da palavra do menu para onde o jogador
## aponta, com leituras pequenas (nome, acertos, nível dos graves) e a dica.
## Desenhado em 2D por cima da cena 3D.

const BRACKET := 18.0
const PADDING := 14.0

## Palavra para onde se aponta neste frame (ou null); definida pelo menu.
var target: MusicWord
var hits := 0

var _kick := 0.0
var _lock := 0.0
var _last_target: MusicWord
var _readout_font: Font
var _hint_font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout_font = UITheme.mono()
	_hint_font = UITheme.din(600, 85)


## Chamado quando uma palavra leva um tiro: os cantos abrem e o contador sobe.
func on_hit(strength: float) -> void:
	_kick = maxf(_kick, 0.35 + strength * 0.65)
	hits += 1


func _process(delta: float) -> void:
	_kick *= exp(-delta * 8.0)
	if target:
		_last_target = target
	_lock = move_toward(_lock, 1.0 if target else 0.0, delta * 6.0)
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	var t := _last_target
	if t == null or cam == null or _lock <= 0.0 or cam.is_position_behind(t.global_position):
		return
	var rect := t.screen_rect(cam).grow(PADDING + (1.0 - _lock) * 30.0 + _kick * 10.0)
	var alpha := _lock
	var accent := t.color.lightened(0.3)

	var bracket_color := Color(accent, 0.9 * alpha)
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var dirs := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for i in 4:
		var c: Vector2 = corners[i]
		var d: Vector2 = dirs[i]
		draw_line(c, c + Vector2(d.x * BRACKET, 0), bracket_color, 2.0)
		draw_line(c, c + Vector2(0, d.y * BRACKET), bracket_color, 2.0)

	var lines := [
		"TARGET // %s" % t.title,
		"HITS %03d" % hits,
		"SYNC %s" % _meter(AudioManager.bass_level),
	]
	var readout_pos := Vector2(rect.end.x + 10.0, rect.position.y + 12.0)
	for i in lines.size():
		draw_string(_readout_font, readout_pos + Vector2(0, i * 15.0), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UITheme.CROSSHAIR_GREEN, 0.8 * alpha))

	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
	draw_string(_hint_font, Vector2(rect.get_center().x - 180.0, rect.end.y + 24.0), "▸ " + t.hint + " ◂",
		HORIZONTAL_ALIGNMENT_CENTER, 360.0, 15, Color(1, 1, 1, pulse * alpha))


static func _meter(value: float) -> String:
	var filled := clampi(roundi(value * 8.0), 0, 8)
	return "■".repeat(filled) + "□".repeat(8 - filled)
