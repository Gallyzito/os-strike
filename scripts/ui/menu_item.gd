class_name MenuItem
extends Button
## Item do menu ao estilo do buy menu do CS: tecla numérica, título e
## descrição. Ao passar o rato, uma placa laranja inclinada desliza por trás.

@export var key_label := "1"
@export var title := "PLAY"
@export var subtitle := ""
@export var accent: Color = UITheme.T_ORANGE
## Tecla que ativa o item (KEY_NONE para nenhuma).
@export var shortcut_key: Key = KEY_NONE

const TEXT_COLOR := UITheme.TEXT
const SKEW := 14.0
const TITLE_SIZE := 40
const SUBTITLE_SIZE := 14

## 0..1, usado na animação de entrada.
var reveal := 1.0:
	set(value):
		reveal = value
		queue_redraw()

var _hot := 0.0
var _mouse_in := false
var _flash := 0.0
var _title_font: Font
var _subtitle_font: Font
var _key_font: Font


func _ready() -> void:
	flat = true
	text = ""
	focus_mode = Control.FOCUS_ALL
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_title_font = UITheme.din(700, 75)
	_subtitle_font = UITheme.din(400, 100)
	_key_font = UITheme.mono()

	mouse_entered.connect(_on_mouse.bind(true))
	mouse_exited.connect(_on_mouse.bind(false))
	focus_entered.connect(_update_hot)
	focus_exited.connect(_update_hot)
	pressed.connect(func() -> void: _flash = 1.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if shortcut_key != KEY_NONE and is_visible_in_tree() and not disabled \
			and event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == shortcut_key or event.physical_keycode == shortcut_key):
		_flash = 1.0
		pressed.emit()
		get_viewport().set_input_as_handled()


func _on_mouse(inside: bool) -> void:
	_mouse_in = inside
	_update_hot()


func _update_hot() -> void:
	var on := _mouse_in or has_focus()
	if on and _hot < 0.5:
		AudioManager.play_sfx(&"hover", -8.0, randf_range(0.97, 1.03))
	create_tween().tween_method(_set_hot, _hot, 1.0 if on else 0.0, 0.16)


func _set_hot(value: float) -> void:
	_hot = value
	queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 4.0, 0.0)
		queue_redraw()


func _draw() -> void:
	var h := size.y
	var offset := -40.0 * (1.0 - reveal)
	var alpha := reveal
	var ease_hot := 1.0 - pow(1.0 - _hot, 3.0)

	# Placa inclinada.
	if ease_hot > 0.001:
		var x0 := -16.0 + offset
		var w := (size.x + 24.0) * ease_hot
		var slab := PackedVector2Array([
			Vector2(x0 + SKEW, 0), Vector2(x0 + w + SKEW, 0),
			Vector2(x0 + w, h), Vector2(x0, h),
		])
		draw_colored_polygon(slab, Color(accent.lerp(Color.WHITE, _flash * 0.6), alpha))

	var ink := TEXT_COLOR.lerp(Color(0.05, 0.05, 0.06), ease_hot)
	ink.a = alpha

	# Caixa com a tecla.
	var key_rect := Rect2(offset, (h - 30.0) * 0.5, 30.0 if key_label.length() <= 1 else 44.0, 30.0)
	draw_rect(key_rect, Color(ink, alpha * (0.45 + ease_hot * 0.4)), false, 1.5)
	draw_string(_key_font, Vector2(key_rect.position.x, key_rect.position.y + 21.0), key_label,
		HORIZONTAL_ALIGNMENT_CENTER, key_rect.size.x, 15, ink)

	var text_x := key_rect.end.x + 18.0 + ease_hot * 8.0
	var title_y := h * 0.5 + (4.0 if subtitle.is_empty() else -2.0) + TITLE_SIZE * 0.32
	draw_string(_title_font, Vector2(text_x, title_y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, ink)
	if not subtitle.is_empty():
		var sub_color := Color(ink, alpha * (0.5 + ease_hot * 0.3))
		draw_string(_subtitle_font, Vector2(text_x + 2.0, title_y + 18.0), subtitle,
			HORIZONTAL_ALIGNMENT_LEFT, -1, SUBTITLE_SIZE, sub_color)

	# Seta à direita quando ativo.
	if ease_hot > 0.01:
		var ax := size.x - 18.0 + offset - (1.0 - ease_hot) * 12.0
		var ay := h * 0.5
		draw_colored_polygon(PackedVector2Array([
			Vector2(ax, ay - 8), Vector2(ax + 9, ay), Vector2(ax, ay + 8),
		]), Color(ink, alpha * ease_hot))


