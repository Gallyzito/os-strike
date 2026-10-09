extends CanvasLayer
## Contador de desempenho discreto no canto inferior direito: uma linha pequena
## "240 FPS · 4.2 ms" e um ponto de cor (verde/amarelo/vermelho) conforme os FPS.
## Liga-se nas Opções (VIDEO → SHOW FPS).

const UPDATE_EVERY := 0.5
const MARGIN := Vector2(10, 4)
const FONT_SIZE := 11

var _label_box: Control
var _font: Font
var _text := ""
var _dot := Color.WHITE
var _last_usec := 0
var _acc_usec := 0
var _frames := 0


func _ready() -> void:
	layer = 126
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = UITheme.mono()
	_label_box = Control.new()
	_label_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_box.draw.connect(_draw_text)
	add_child(_label_box)
	_apply()
	Settings.changed.connect(func(key: String) -> void:
		if key == "video/show_fps":
			_apply())


func _apply() -> void:
	visible = bool(Settings.get_value("video/show_fps"))
	set_process(visible)
	_last_usec = Time.get_ticks_usec()
	_acc_usec = 0
	_frames = 0


func _process(_delta: float) -> void:
	# Tempo real entre frames (não é afetado pelo Engine.time_scale do slow-motion).
	var now := Time.get_ticks_usec()
	_acc_usec += now - _last_usec
	_last_usec = now
	_frames += 1
	if _acc_usec < UPDATE_EVERY * 1_000_000.0:
		return
	var fps := roundi(_frames * 1_000_000.0 / _acc_usec)
	_text = "%d FPS  ·  %.1f ms" % [fps, _acc_usec / 1000.0 / _frames]
	if fps >= 120:
		_dot = UITheme.CROSSHAIR_GREEN
	elif fps >= 60:
		_dot = Color(1.0, 0.85, 0.3)
	else:
		_dot = UITheme.KILL_RED.lightened(0.2)
	_acc_usec = 0
	_frames = 0
	_label_box.queue_redraw()


func _draw_text() -> void:
	if _text.is_empty():
		return
	var w := _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var base := _label_box.size - MARGIN
	var pos := Vector2(base.x - w, base.y)
	_label_box.draw_string(_font, pos + Vector2(1, 1), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0, 0, 0, 0.45))
	_label_box.draw_string(_font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1, 1, 1, 0.42))
	_label_box.draw_circle(Vector2(pos.x - 8.0, pos.y - FONT_SIZE * 0.36), 2.5, Color(_dot, 0.8))
