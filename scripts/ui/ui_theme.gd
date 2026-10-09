class_name UITheme
## Paleta, fontes e estilos partilhados pelos menus do os!strike.
## Cores inspiradas nos lados do CS: laranja (T) e azul aço (CT).

const T_ORANGE := Color(1.0, 0.62, 0.11)
const CT_BLUE := Color(0.42, 0.62, 0.95)
const CROSSHAIR_GREEN := Color(0.3, 1.0, 0.45)
const KILL_RED := Color(0.9, 0.12, 0.12)
const TEXT := Color(0.93, 0.93, 0.9)
const TEXT_DIM := Color(0.93, 0.93, 0.9, 0.5)
const PANEL_BG := Color(0.035, 0.04, 0.05, 0.86)
## Cor de cada nota (como no osu!).
const GRADE_COLORS := {
	"SS": Color(1.0, 0.92, 0.45), "S": Color(1.0, 0.82, 0.3), "A": Color(0.45, 1.0, 0.5),
	"B": Color(0.45, 0.7, 1.0), "C": Color(0.8, 0.45, 1.0), "D": Color(1.0, 0.45, 0.2), "F": Color(1.0, 0.2, 0.22),
}

## Bahnschrift é uma fonte variável estilo DIN que vem com o Windows.
## TODO: incluir uma fonte livre equivalente no projeto antes de distribuir.
const DIN_PATH := "C:/Windows/Fonts/bahnschrift.ttf"

static var _din: Font
static var _cache: Dictionary[String, Font] = {}


## Fonte estilo DIN. `width` vai de 75 (condensada) a 100 (normal);
## `spacing` afasta as letras (em píxeis).
static func din(weight := 600, width := 100, spacing := 0) -> Font:
	var key := "%d/%d/%d" % [weight, width, spacing]
	if _cache.has(key):
		return _cache[key]

	var variation := FontVariation.new()
	variation.base_font = _din_base()
	# Os eixos têm de ser passados como tags numéricas; a Bahnschrift vai de
	# 300 a 700 de peso e de 75 a 100 de largura.
	var ts := TextServerManager.get_primary_interface()
	variation.variation_opentype = {
		ts.name_to_tag("wght"): clampi(weight, 300, 700),
		ts.name_to_tag("wdth"): clampi(width, 75, 100),
	}
	variation.spacing_glyph = spacing
	_cache[key] = variation
	return variation


static func mono() -> Font:
	if not _cache.has("mono"):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
		f.font_weight = 600
		_cache["mono"] = f
	return _cache["mono"]


static func _din_base() -> Font:
	if _din:
		return _din
	if FileAccess.file_exists(DIN_PATH):
		var file := FontFile.new()
		if file.load_dynamic_font(DIN_PATH) == OK:
			_din = file
			return _din
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Arial"])
	_din = fallback
	return _din


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = din(500)
	theme.default_font_size = 18

	theme.set_color("font_color", "Label", TEXT)

	theme.set_stylebox("panel", "PanelContainer", panel_box())

	theme.set_stylebox("slider", "HSlider", _bar(Color(1, 1, 1, 0.1), 2))
	theme.set_stylebox("grabber_area", "HSlider", _bar(T_ORANGE, 2))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _bar(T_ORANGE.lightened(0.25), 2))
	var grabber := _square_icon(14, T_ORANGE.lightened(0.3))
	theme.set_icon("grabber", "HSlider", grabber)
	theme.set_icon("grabber_highlight", "HSlider", _square_icon(14, Color.WHITE))

	theme.set_stylebox("background", "ProgressBar", _bar(Color(1, 1, 1, 0.1), 1))
	theme.set_stylebox("fill", "ProgressBar", _bar(T_ORANGE, 1))

	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		theme.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	theme.set_color("font_color", "CheckButton", TEXT)
	theme.set_color("font_hover_color", "CheckButton", Color.WHITE)
	theme.set_color("font_pressed_color", "CheckButton", TEXT)
	theme.set_color("font_hover_pressed_color", "CheckButton", Color.WHITE)
	theme.set_icon("checked", "CheckButton", _toggle_icon(true))
	theme.set_icon("unchecked", "CheckButton", _toggle_icon(false))

	# Botões pequenos e listas (OptionButton herda de Button).
	theme.set_stylebox("normal", "Button", _field(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.15)))
	theme.set_stylebox("hover", "Button", _field(Color(1, 1, 1, 0.12), T_ORANGE))
	theme.set_stylebox("pressed", "Button", _field(Color(T_ORANGE, 0.35), T_ORANGE))
	theme.set_stylebox("hover_pressed", "Button", _field(Color(T_ORANGE, 0.45), T_ORANGE))
	var focus := _field(Color(0, 0, 0, 0), Color(1, 1, 1, 0.6))
	focus.draw_center = false
	theme.set_stylebox("focus", "Button", focus)
	theme.set_font("font", "Button", din(600, 85))
	theme.set_font_size("font_size", "Button", 16)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)

	# Caixas de texto (as SpinBox usam LineEdit).
	theme.set_stylebox("normal", "LineEdit", _field(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.15)))
	theme.set_stylebox("focus", "LineEdit", _field(Color(1, 1, 1, 0.1), T_ORANGE))
	theme.set_font("font", "LineEdit", mono())
	theme.set_font_size("font_size", "LineEdit", 15)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("caret_color", "LineEdit", T_ORANGE)
	theme.set_color("selection_color", "LineEdit", Color(T_ORANGE, 0.4))

	var popup := StyleBoxFlat.new()
	popup.bg_color = Color(0.05, 0.055, 0.07, 0.98)
	popup.set_border_width_all(1)
	popup.border_color = Color(1, 1, 1, 0.15)
	popup.set_content_margin_all(6)
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", _field(Color(T_ORANGE, 0.35), Color(0, 0, 0, 0)))
	theme.set_font("font", "PopupMenu", din(500, 100))
	theme.set_font_size("font_size", "PopupMenu", 16)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	return theme


static func _field(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_border_width_all(1)
	box.border_color = border
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	return box


static func panel_box(accent := T_ORANGE) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL_BG
	box.border_width_top = 3
	box.border_color = accent
	box.set_content_margin_all(22)
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_size = 24
	return box


static func _bar(color: Color, half_height: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.content_margin_top = half_height
	box.content_margin_bottom = half_height
	return box


static func _square_icon(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## Interruptor retangular: barra com um bloco à esquerda (off) ou à direita (on).
static func _toggle_icon(on: bool) -> ImageTexture:
	var w := 44
	var h := 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0.1))
	var knob := Rect2i(w - h + 3, 3, h - 6, h - 6) if on else Rect2i(3, 3, h - 6, h - 6)
	if on:
		img.fill_rect(Rect2i(0, 0, w, h), Color(T_ORANGE, 0.35))
	img.fill_rect(knob, T_ORANGE if on else Color(1, 1, 1, 0.45))
	return ImageTexture.create_from_image(img)
