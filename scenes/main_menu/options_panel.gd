class_name OptionsPanel
extends PanelContainer
## Painel de opções com separadores: OSU!, ÁUDIO, VÍDEO, MIRA, ARMA e SENSIBILIDADE.
## Cada controlo escreve logo em Settings, por isso as mudanças veem-se em
## tempo real (a mira, a posição da AK, o hitsound...).

const TABS: Array[String] = ["OSU!", "AUDIO", "VIDEO", "CROSSHAIR", "WEAPON", "SENSITIVITY"]
const LABEL_WIDTH := 150.0
const PAGE_HEIGHT := 340.0
const CROSSHAIR_COLORS: Array[Color] = [
	Color(0.3, 1.0, 0.45), Color(1.0, 1.0, 0.2), Color(0.2, 0.9, 1.0),
	Color(1.0, 0.25, 0.25), Color(1.0, 1.0, 1.0), Color(1.0, 0.3, 1.0),
]

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _builders: Array[Callable] = []
var _current := 0

@onready var _vbox: VBoxContainer = $VBox


func _ready() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := _make_tab_button(TABS[i], group)
		b.pressed.connect(_show_page.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	_vbox.add_child(tabs)
	_vbox.move_child(tabs, 1)

	_builders = [_build_osu, _build_audio, _build_video, _build_crosshair, _build_viewmodel, _build_mouse]
	for i in _builders.size():
		var page: Control = _builders[i].call()
		_vbox.add_child(page)
		_vbox.move_child(page, 2 + i)
		_pages.append(page)
	_show_page(0)


func focus_first() -> void:
	_tab_buttons[_current].grab_focus()


func _show_page(index: int) -> void:
	if index != _current:
		AudioManager.play_sfx(&"hover", -6.0)
	_current = index
	_tab_buttons[index].button_pressed = true
	for i in _pages.size():
		_pages[i].visible = i == index


## Volta a construir uma página (depois de "Repor", por exemplo).
func _rebuild_page(index: int) -> void:
	var old := _pages[index]
	var page: Control = _builders[index].call()
	_vbox.add_child(page)
	_vbox.move_child(page, old.get_index())
	old.queue_free()
	_pages[index] = page
	_show_page(index)


# --- Páginas -----------------------------------------------------------------

func _build_osu() -> Control:
	var page := _page()
	var skins: Array[String] = [""]
	skins.append_array(OsuSkin.list_skins())
	var labels: Array[String] = ["os!strike (default)"]
	for s in skins.slice(1):
		labels.append(s)
	var current: String = Settings.get_value("osu/skin")
	_option(page, "SKIN", labels, maxi(skins.find(current), 0), func(i: int) -> void:
		Settings.set_value("osu/skin", skins[i]))
	var row := _row(page, "")
	row.add_child(_action("OPEN FOLDER", _open_skins_dir))
	row.add_child(_action("REFRESH", func() -> void:
		OsuSkin.clear_cache()
		_rebuild_page(0)))
	_slider(page, "SCREEN DISTANCE", "osu/screen_distance", 1.5, 8.0, 0.1, 1.0, "%.1f m")
	_slider(page, "BACKGROUND DIM", "osu/background_dim", 0, 100, 1, 100.0, "%d%%")
	_option(page, "IN-GAME CURSOR", ["CS crosshair", "Skin cursor", "Both"] as Array[String],
		int(Settings.get_value("osu/cursor_mode")), func(i: int) -> void: Settings.set_value("osu/cursor_mode", i))
	_check(page, "SHOW WEAPON", "osu/show_weapon")
	_check(page, "SKIN HITSOUNDS", "osu/skin_hitsounds")
	_check(page, "DISCORD STATUS", "discord/enabled")
	var id_row := _row(page, "DISCORD APP ID")
	var id_edit := LineEdit.new()
	id_edit.text = String(Settings.get_value("discord/client_id"))
	id_edit.placeholder_text = "Application ID (discord.com/developers)"
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_edit.text_changed.connect(func(t: String) -> void: Settings.set_value("discord/client_id", t.strip_edges()))
	id_row.add_child(id_edit)
	_note(page, "Put osu! skins (folders or .osk files) in the \"skins\" folder and press REFRESH. Keys: click, Z, X or right mouse button. A farther screen looks smaller (harder aim).")
	return page


func _build_audio() -> Control:
	var page := _page()
	_slider(page, "MUSIC", "audio/music_volume", 0, 100, 1, 100.0)
	var sfx := _slider(page, "EFFECTS", "audio/sfx_volume", 0, 100, 1, 100.0)
	sfx.drag_ended.connect(func(_c: bool) -> void: AudioManager.play_sfx(&"select"))
	var weapons := _slider(page, "WEAPONS", "audio/weapon_volume", 0, 100, 1, 100.0, "%d%%")
	weapons.drag_ended.connect(func(_c: bool) -> void:
		var v := float(Settings.get_value("audio/weapon_volume"))
		if v > 0.001:
			AudioManager.play_sfx(&"shot", -8.0 + linear_to_db(v)))
	_slider(page, "WHEN INACTIVE", "audio/inactive_volume", 0, 100, 1, 100.0, "%d%%")

	_section(page, "HITSOUND")
	var options: Array[String] = [Settings.HITSOUND_DEFAULT, Settings.HITSOUND_NONE]
	var labels: Array[String] = ["Default (os!strike)", "None"]
	for file in Settings.list_hitsounds():
		options.append(file)
		labels.append(file.get_basename())
	var current: String = Settings.get_value("audio/hitsound")
	var selected := maxi(options.find(current), 0)
	_option(page, "SOUND", labels, selected, func(i: int) -> void:
		Settings.set_value("audio/hitsound", options[i])
		AudioManager.reload_hitsound()
		AudioManager.play_hitsound())
	var vol := _slider(page, "VOLUME", "audio/hitsound_volume", 0, 100, 1, 100.0)
	vol.drag_ended.connect(func(_c: bool) -> void: AudioManager.play_hitsound())

	var row := _row(page, "")
	row.add_child(_action("TEST", AudioManager.play_hitsound))
	row.add_child(_action("REFRESH", func() -> void:
		AudioManager.reload_hitsound()
		_rebuild_page(1)))
	row.add_child(_action("OPEN FOLDER", _open_sounds_dir))
	_note(page, "Put .wav, .ogg or .mp3 files in the \"sounds\" folder and press REFRESH.")
	return page


func _build_video() -> Control:
	var page := _page()
	_option(page, "MODE", Settings.WINDOW_MODES, Settings.get_value("video/window_mode"),
		func(i: int) -> void: Settings.set_value("video/window_mode", i))
	_option(page, "ASPECT RATIO", Settings.ASPECTS, Settings.get_value("video/aspect"),
		func(i: int) -> void:
			Settings.set_aspect(i)
			_rebuild_page.call_deferred(2))

	var resolutions := Settings.available_resolutions(Settings.get_value("video/aspect"))
	var current: Vector2i = Settings.get_value("video/resolution")
	if not resolutions.has(current):
		resolutions.append(current)
	var res_labels: Array[String] = []
	for r in resolutions:
		res_labels.append("%d × %d" % [r.x, r.y])
	_option(page, "RESOLUTION", res_labels, resolutions.find(current),
		func(i: int) -> void: Settings.set_value("video/resolution", resolutions[i]))
	_option(page, "SCALING", Settings.SCALING_MODES, Settings.get_value("video/scaling"),
		func(i: int) -> void: Settings.set_value("video/scaling", i))

	_slider(page, "FOV", "video/fov", 70, 120, 1)
	_check(page, "VSYNC", "video/vsync")

	var fps_labels: Array[String] = []
	for f in Settings.FPS_LIMITS:
		fps_labels.append("Unlimited" if f == 0 else "%d FPS" % f)
	_option(page, "FPS LIMIT", fps_labels, maxi(Settings.FPS_LIMITS.find(Settings.get_value("video/max_fps")), 0),
		func(i: int) -> void: Settings.set_value("video/max_fps", Settings.FPS_LIMITS[i]))
	_check(page, "SHOW FPS", "video/show_fps")
	_note(page, "Horizontal FOV measured at 4:3, like CS (90 = CS default). SCALING only applies in fullscreen with an aspect ratio different from the monitor (e.g. 4:3 stretched on a 16:9 monitor).")

	# --- Gráficos avançados ---
	_section(page, "ADVANCED GRAPHICS")
	var preset := _option(page, "PRESET", Settings.QUALITY_NAMES, Settings.get_value("video/quality"),
		func(i: int) -> void:
			if i < Settings.QUALITY_CUSTOM:
				Settings.set_value("video/quality", i)
				_rebuild_page.call_deferred(2))
	Settings.changed.connect(_on_quality_changed.bind(preset))
	_slider(page, "RENDER SCALE", "gfx/render_scale", 50, 200, 5, 100.0, "%d%%")
	_option(page, "UPSCALER", Settings.UPSCALER_NAMES, Settings.get_value("gfx/upscaler"),
		func(i: int) -> void: Settings.set_value("gfx/upscaler", i))
	_slider(page, "FSR SHARPNESS", "gfx/sharpness", 0, 100, 5, 100.0, "%d%%")
	_option(page, "MSAA", Settings.MSAA_NAMES, Settings.get_value("gfx/msaa"),
		func(i: int) -> void: Settings.set_value("gfx/msaa", i))
	_option(page, "POST AA", Settings.POST_AA_NAMES, Settings.get_value("gfx/post_aa"),
		func(i: int) -> void: Settings.set_value("gfx/post_aa", i))
	_check(page, "TAA", "gfx/taa")
	_option(page, "TEXTURE FILTER", Settings.ANISOTROPIC_NAMES, Settings.get_value("gfx/anisotropic"),
		func(i: int) -> void: Settings.set_value("gfx/anisotropic", i))
	_option(page, "OSU! SCREEN", Settings.SCREEN_RES_NAMES, Settings.get_value("gfx/screen_res"),
		func(i: int) -> void: Settings.set_value("gfx/screen_res", i))
	_check(page, "BLOOM", "gfx/bloom")
	_check(page, "VOLUMETRIC FOG", "gfx/fog")
	_check(page, "AMBIENT OCCLUSION", "gfx/ssao")
	_check(page, "DEBANDING", "gfx/debanding")
	_note(page, "RENDER SCALE below 100% renders the 3D at a lower resolution (more FPS); the UPSCALER sharpens it back (FSR). Above 100% = supersampling (sharper, slower). OSU! SCREEN is the resolution of the curved screen: higher = sharper circles and text. TAA smooths edges but can blur moving notes.")

	# A página é mais alta do que o painel: fica dentro de uma área com scroll.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, PAGE_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.custom_minimum_size = Vector2.ZERO
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	return scroll


## Mostra "Custom" na predefinição quando se mexe num gráfico avançado.
func _on_quality_changed(key: String, preset: OptionButton) -> void:
	if key == "video/quality" and is_instance_valid(preset):
		preset.select(int(Settings.get_value("video/quality")))


func _build_crosshair() -> Control:
	var page := _page()
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	page.add_child(columns)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(controls)

	var color_row := _row(controls, "COLOR")
	for c in CROSSHAIR_COLORS:
		color_row.add_child(_swatch(c))
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(36, 26)
	picker.color = Settings.get_value("crosshair/color")
	picker.edit_alpha = false
	picker.color_changed.connect(func(c: Color) -> void: Settings.set_value("crosshair/color", c))
	color_row.add_child(picker)

	_slider(controls, "LENGTH", "crosshair/length", 0, 20, 0.5, 1.0, "%.1f")
	_slider(controls, "THICKNESS", "crosshair/thickness", 0.5, 6, 0.5, 1.0, "%.1f")
	_slider(controls, "INTERVALO", "crosshair/gap", -3, 12, 0.5, 1.0, "%.1f")
	_slider(controls, "OPACITY", "crosshair/alpha", 10, 100, 1, 100.0)
	_check(controls, "OUTLINE", "crosshair/outline")
	_slider(controls, "OUTLINE SIZE", "crosshair/outline_thickness", 0.5, 3, 0.5, 1.0, "%.1f")
	_check(controls, "CENTER DOT", "crosshair/dot")
	_check(controls, "DYNAMIC", "crosshair/dynamic")
	controls.add_child(_action("RESET CROSSHAIR", func() -> void:
		Settings.reset_section("crosshair")
		_rebuild_page(3)))

	columns.add_child(CrosshairPreview.new())
	return page


func _build_viewmodel() -> Control:
	var page := _page()
	var ids: Array[String] = []
	var names: Array[String] = []
	for id: String in Viewmodel.WEAPON_ORDER:
		ids.append(id)
		names.append("%d  ·  %s" % [ids.size(), Viewmodel.WEAPONS[id].name])
	_option(page, "WEAPON", names, maxi(ids.find(String(Settings.get_value("player/weapon"))), 0),
		func(i: int) -> void: Settings.set_value("player/weapon", ids[i]))
	_check(page, "CAMERA RECOIL", "player/camera_recoil")
	_slider(page, "SIDE", "viewmodel/offset_x", -10, 10, 0.5, 1.0, "%+.1f")
	_slider(page, "HEIGHT", "viewmodel/offset_y", -10, 10, 0.5, 1.0, "%+.1f")
	_slider(page, "DISTANCE", "viewmodel/offset_z", -10, 20, 0.5, 1.0, "%+.1f")
	page.add_child(_action("RESET POSITION", func() -> void:
		Settings.reset_section("viewmodel")
		_rebuild_page(4)))
	_note(page, "Switch weapons any time with 1, 2, 3, Q (last weapon) or the mouse wheel. CAMERA RECOIL off = the view no longer kicks up when you shoot.\nPosition in centimetres, like CS viewmodel_offset; positive distance moves the gun away.")
	return page


func _build_mouse() -> Control:
	var page := _page()
	var readout := Label.new()
	readout.add_theme_font_override("font", UITheme.mono())
	readout.add_theme_font_size_override("font_size", 15)
	readout.add_theme_color_override("font_color", UITheme.CROSSHAIR_GREEN)
	var update_readout := func() -> void:
		var sens: float = Settings.get_value("mouse/sensitivity")
		readout.text = "eDPI %d   ·   %.1f cm/360°" % [roundi(sens * float(Settings.get_value("mouse/dpi"))), Settings.cm_per_360()]

	# Slider + caixa numérica para escrever a sensibilidade exata do CS.
	var row := _row(page, "SENSITIVITY")
	var slider := HSlider.new()
	slider.min_value = 0.05
	slider.max_value = 10.0
	slider.step = 0.01
	slider.value = Settings.get_value("mouse/sensitivity")
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var spin := SpinBox.new()
	spin.min_value = 0.01
	spin.max_value = 20.0
	spin.step = 0.001
	spin.custom_minimum_size = Vector2(110, 0)
	spin.value = slider.value
	slider.value_changed.connect(func(v: float) -> void:
		if not is_equal_approx(spin.value, v):
			spin.set_value_no_signal(v)
		Settings.set_value("mouse/sensitivity", v)
		update_readout.call())
	spin.value_changed.connect(func(v: float) -> void:
		slider.set_value_no_signal(v)
		Settings.set_value("mouse/sensitivity", v)
		update_readout.call())
	row.add_child(slider)
	row.add_child(spin)

	var dpi_row := _row(page, "MOUSE DPI")
	var dpi := SpinBox.new()
	dpi.min_value = 100
	dpi.max_value = 32000
	dpi.step = 50
	dpi.value = Settings.get_value("mouse/dpi")
	dpi.custom_minimum_size = Vector2(110, 0)
	dpi.value_changed.connect(func(v: float) -> void:
		Settings.set_value("mouse/dpi", int(v))
		update_readout.call())
	dpi_row.add_child(dpi)

	_check(page, "INVERT Y", "mouse/invert_y")
	var readout_row := _row(page, "")
	readout_row.add_child(readout)
	update_readout.call()
	page.add_child(_action("RESET SENSITIVITY", func() -> void:
		Settings.reset_section("mouse")
		_rebuild_page(5)))
	_note(page, "Same formula as Counter-Strike (m_yaw 0.022): you can use your CS2 sensitivity directly. DPI is only used to compute cm/360°.")
	return page


# --- Construtores de controlos ----------------------------------------------

func _page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(0, PAGE_HEIGHT)
	page.add_theme_constant_override("separation", 10)
	return page


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)
	parent.add_child(row)
	return row


func _slider(parent: Control, text: String, key: String, min_v: float, max_v: float, step: float,
		scale := 1.0, fmt := "%d") -> HSlider:
	var row := _row(parent, text)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = Settings.get_value(key) * scale
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(56, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_override("font", UITheme.mono())
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.text = fmt % slider.value
	slider.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, v / scale)
		value_label.text = fmt % v)
	row.add_child(slider)
	row.add_child(value_label)
	return slider


func _option(parent: Control, text: String, items: Array[String], selected: int, on_select: Callable) -> OptionButton:
	var row := _row(parent, text)
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	option.select(selected)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.item_selected.connect(func(i: int) -> void:
		AudioManager.play_sfx(&"hover")
		on_select.call(i))
	row.add_child(option)
	return option


func _check(parent: Control, text: String, key: String) -> CheckButton:
	var row := _row(parent, text)
	var check := CheckButton.new()
	check.button_pressed = Settings.get_value(key)
	check.toggled.connect(func(on: bool) -> void:
		AudioManager.play_sfx(&"hover")
		Settings.set_value(key, on))
	row.add_child(check)
	return check


func _action(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(func() -> void:
		AudioManager.play_sfx(&"select")
		callback.call())
	return button


func _swatch(color: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(26, 26)
	b.tooltip_text = color.to_html(false)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = color
		box.set_border_width_all(2 if state != "normal" else 0)
		box.border_color = Color.WHITE
		b.add_theme_stylebox_override(state, box)
	b.pressed.connect(func() -> void: Settings.set_value("crosshair/color", color))
	return b


func _section(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", UITheme.T_ORANGE)
	label.add_theme_font_override("font", UITheme.din(700, 85))
	label.add_theme_font_size_override("font_size", 15)
	parent.add_child(label)


func _note(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	label.add_theme_font_size_override("font_size", 13)
	parent.add_child(label)


func _make_tab_button(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.add_theme_font_override("font", UITheme.din(700, 75))
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", UITheme.TEXT)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", UITheme.TEXT)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.08) if state.contains("pressed") else Color(0, 0, 0, 0)
		box.content_margin_left = 14
		box.content_margin_right = 14
		box.content_margin_top = 4
		box.content_margin_bottom = 6
		if state.contains("pressed"):
			box.border_width_bottom = 3
			box.border_color = UITheme.T_ORANGE
		elif state == "focus":
			box.draw_center = false
			box.border_width_bottom = 1
			box.border_color = UITheme.TEXT_DIM
		b.add_theme_stylebox_override(state, box)
	return b


func _open_skins_dir() -> void:
	var dir := Settings.skins_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	OS.shell_open(dir)


func _open_sounds_dir() -> void:
	var dir := Settings.sounds_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	OS.shell_open(dir)


## Pré-visualização da mira num quadrado escuro, ampliada 2x.
class CrosshairPreview:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(170, 170)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	func _ready() -> void:
		Settings.changed.connect(_on_settings_changed)

	func _on_settings_changed(_key: String) -> void:
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.12))
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.15), false, 1.0)
		CrosshairCursor.draw_crosshair(self, size * 0.5, 0.0, 2.0)
