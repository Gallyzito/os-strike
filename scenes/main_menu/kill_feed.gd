class_name KillFeed
extends VBoxContainer
## Kill feed no canto superior direito, como no CS. As tuas "kills" têm
## contorno vermelho, tal como no jogo.

const MAX_ENTRIES := 4
const LIFETIME := 4.5


## `ct_killer`: o assassino é CT (azul) e a vítima T (laranja), ao contrário do normal.
func push(killer: String, weapon: String, victim: String, headshot: bool, ct_killer := false) -> void:
	var entry := PanelContainer.new()
	entry.size_flags_horizontal = Control.SIZE_SHRINK_END
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.62)
	box.set_border_width_all(2)
	box.border_color = Color(UITheme.KILL_RED, 0.85)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	entry.add_theme_stylebox_override("panel", box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(row)

	var killer_color := UITheme.CT_BLUE if ct_killer else UITheme.T_ORANGE
	var victim_color := UITheme.T_ORANGE if ct_killer else UITheme.CT_BLUE
	row.add_child(_label(killer, killer_color, UITheme.din(700, 85)))
	row.add_child(_label(weapon, Color(1, 1, 1, 0.85), UITheme.din(500, 75), 15))
	if headshot:
		row.add_child(HeadshotIcon.new())
	row.add_child(_label(victim, victim_color, UITheme.din(700, 85)))

	add_child(entry)
	move_child(entry, 0)
	while get_child_count() > MAX_ENTRIES:
		var old := get_child(get_child_count() - 1)
		remove_child(old)
		old.queue_free()

	entry.modulate.a = 0.0
	var tween := entry.create_tween()
	tween.tween_property(entry, "modulate:a", 1.0, 0.12)
	tween.tween_interval(LIFETIME)
	tween.tween_property(entry, "modulate:a", 0.0, 0.6)
	tween.tween_callback(entry.queue_free)


static func _label(text: String, color: Color, font: Font, size := 17) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## Ícone de headshot: cabeça com uma mira por cima.
class HeadshotIcon:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(20, 20)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var col := Color(1, 1, 1, 0.9)
		draw_circle(c + Vector2(0, 1), 6.0, col)
		draw_rect(Rect2(c.x - 4, c.y + 5, 8, 4), col)
		var red := UITheme.KILL_RED
		draw_line(c + Vector2(-10, -2), c + Vector2(-4, -2), red, 2.0)
		draw_line(c + Vector2(4, -2), c + Vector2(10, -2), red, 2.0)
		draw_line(c + Vector2(0, -10), c + Vector2(0, -6), red, 2.0)
