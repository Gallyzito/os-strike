class_name OsuSkin
extends RefCounted
## Skin do osu! (pasta dentro de "skins"). Lê as imagens (prefere as @2x),
## animações (nome-0, nome-1...), o skin.ini (cores e fontes) e os sons.
## Uma skin vazia ("") é a skin do os!strike: o ecrã desenha tudo por código
## quando falta uma imagem, por isso uma skin pode trazer só algumas imagens.
## Ficheiros .osk postos na pasta são extraídos.

const DEFAULT_COMBO: Array[Color] = [
	Color(1.0, 0.62, 0.11), Color(0.42, 0.62, 0.95), Color(0.3, 1.0, 0.45), Color(1.0, 0.3, 0.45),
]
const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg"]
const SOUND_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]

static var _cache: Dictionary[String, OsuSkin] = {}

var name := ""
var dir := ""
var combo_colours: Array[Color] = []
var slider_border := Color.WHITE
var slider_track: Variant = null
var hit_circle_prefix := "default"
var hit_circle_overlap := -2.0
var score_prefix := "score"
var score_overlap := 0.0
var combo_prefix := "score"
var combo_overlap := 0.0
var allow_ball_tint := false
var overlay_above_number := true
var cursor_centre := true
var cursor_expand := true

var _textures: Dictionary[String, Variant] = {}
var _scales: Dictionary[String, float] = {}
var _files: Dictionary[String, String] = {}
var _sounds: Dictionary[String, Variant] = {}


static func skins_dir() -> String:
	return Settings.skins_dir()


## Nomes das skins instaladas (extrai os .osk novos primeiro).
static func list_skins() -> Array[String]:
	var root := skins_dir()
	DirAccess.make_dir_recursive_absolute(root)
	for file in DirAccess.get_files_at(root):
		if file.get_extension().to_lower() == "osk":
			var dest := root.path_join(file.get_basename().strip_edges())
			if not DirAccess.dir_exists_absolute(dest):
				_extract(root.path_join(file), dest)
	var out: Array[String] = []
	for folder in DirAccess.get_directories_at(root):
		out.append(folder)
	out.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return out


## A skin escolhida nas Opções (em cache).
static func current() -> OsuSkin:
	return get_skin(Settings.get_value("osu/skin"))


static func get_skin(skin_name: String) -> OsuSkin:
	if _cache.has(skin_name):
		return _cache[skin_name]
	var skin := OsuSkin.new()
	skin.name = skin_name
	if not skin_name.is_empty():
		skin.dir = skins_dir().path_join(skin_name)
		if DirAccess.dir_exists_absolute(skin.dir):
			skin._index_files()
			skin._read_ini()
		else:
			skin.dir = ""
	if skin.combo_colours.is_empty():
		skin.combo_colours = DEFAULT_COMBO.duplicate()
	_cache[skin_name] = skin
	return skin


## Esquece as skins carregadas (depois de mudar ficheiros na pasta).
static func clear_cache() -> void:
	_cache.clear()


func display_name() -> String:
	return "os!strike (default)" if name.is_empty() else name


## Imagem `image_name` (sem extensão) ou null. Usa a @2x se houver.
func tex(image_name: String) -> Texture2D:
	if _textures.has(image_name):
		return _textures[image_name]
	var t: Texture2D = null
	var scale := 1.0
	for variant in [image_name + "@2x", image_name]:
		var path: String = _files.get(String(variant).to_lower(), "")
		if path.is_empty():
			continue
		var img := Image.load_from_file(path)
		if img and not img.is_empty():
			# Imagens de 1×1 servem para esconder o elemento: ficam transparentes (não se usa o padrão).
			if img.get_width() <= 1 or img.get_height() <= 1:
				img = Image.create(1, 1, false, Image.FORMAT_RGBA8)
			t = ImageTexture.create_from_image(img)
			scale = 0.5 if variant != image_name else 1.0
			break
	_textures[image_name] = t
	_scales[image_name] = scale
	return t


## Escala para converter os píxeis da imagem em píxeis "SD" do osu!.
func tex_scale(image_name: String) -> float:
	tex(image_name)
	return _scales.get(image_name, 1.0)


## Nomes dos fotogramas de uma animação: nome-0, nome-1... (ou nome0, nome1...);
## senão a imagem simples; vazio se não houver nenhuma.
func frame_names(image_name: String, dash := true) -> Array[String]:
	var out: Array[String] = []
	var i := 0
	while i < 120:
		var frame := "%s%s%d" % [image_name, "-" if dash else "", i]
		if tex(frame) == null:
			break
		out.append(frame)
		i += 1
	if out.is_empty() and tex(image_name):
		out.append(image_name)
	return out


## Som da skin (ex.: "normal-hitnormal") ou null.
func sound(sound_name: String) -> AudioStream:
	if _sounds.has(sound_name):
		return _sounds[sound_name]
	var s: AudioStream = null
	var path: String = _files.get(sound_name.to_lower() + "#sound", "")
	if not path.is_empty():
		s = AudioManager.load_sound_file(path)
	_sounds[sound_name] = s
	return s


func combo_colour(index: int, beatmap_colours: Array[Color]) -> Color:
	# Como no osu!: as cores do mapa ganham às da skin.
	var list := beatmap_colours if not beatmap_colours.is_empty() else combo_colours
	if list.is_empty():
		list = DEFAULT_COMBO
	return list[posmod(index, list.size())]


func _index_files() -> void:
	for file in DirAccess.get_files_at(dir):
		var ext := file.get_extension().to_lower()
		var base := file.get_basename().to_lower()
		if ext in IMAGE_EXTENSIONS:
			# Prefere png se houver duas versões.
			if not _files.has(base) or ext == "png":
				_files[base] = dir.path_join(file)
		elif ext in SOUND_EXTENSIONS:
			_files[base + "#sound"] = dir.path_join(file)


func _read_ini() -> void:
	var path := ""
	for file in DirAccess.get_files_at(dir):
		if file.to_lower() == "skin.ini":
			path = dir.path_join(file)
	if path.is_empty():
		return
	var section := ""
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		var i := line.find(":")
		if i <= 0:
			continue
		var key := line.substr(0, i).strip_edges()
		var value := line.substr(i + 1).strip_edges()
		var comment := value.find("//")
		if comment >= 0:
			value = value.substr(0, comment).strip_edges()
		match section:
			"General":
				match key:
					"AllowSliderBallTint": allow_ball_tint = value == "1"
					"HitCircleOverlayAboveNumber", "HitCircleOverlayAboveNumer": overlay_above_number = value != "0"
					"CursorCentre": cursor_centre = value != "0"
					"CursorExpand": cursor_expand = value != "0"
			"Colours":
				var col: Variant = _colour(value)
				if col != null:
					if key.begins_with("Combo"):
						combo_colours.append(col)
					elif key == "SliderBorder":
						slider_border = col
					elif key == "SliderTrackOverride":
						slider_track = col
			"Fonts":
				match key:
					"HitCirclePrefix": hit_circle_prefix = value.replace("\\", "/")
					"HitCircleOverlap": hit_circle_overlap = float(value)
					"ScorePrefix": score_prefix = value.replace("\\", "/")
					"ScoreOverlap": score_overlap = float(value)
					"ComboPrefix": combo_prefix = value.replace("\\", "/")
					"ComboOverlap": combo_overlap = float(value)
	# Prefixos com subpastas (ex.: "fonts/default"): indexa essas pastas também.
	for prefix: String in [hit_circle_prefix, score_prefix, combo_prefix]:
		if prefix.contains("/"):
			var sub := dir.path_join(prefix.get_base_dir())
			if DirAccess.dir_exists_absolute(sub):
				for file in DirAccess.get_files_at(sub):
					if file.get_extension().to_lower() in IMAGE_EXTENSIONS:
						_files[(prefix.get_base_dir() + "/" + file.get_basename()).to_lower()] = sub.path_join(file)


static func _colour(value: String) -> Variant:
	var c := value.split(",")
	if c.size() < 3:
		return null
	return Color8(clampi(int(c[0]), 0, 255), clampi(int(c[1]), 0, 255), clampi(int(c[2]), 0, 255))


static func _extract(zip_path: String, dest: String) -> void:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return
	DirAccess.make_dir_recursive_absolute(dest)
	for entry in zip.get_files():
		if entry.ends_with("/") or entry.contains("..") or entry.begins_with("/") or entry.contains(":"):
			continue
		var target := dest.path_join(entry)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out:
			out.store_buffer(zip.read_file(entry))
			out.close()
	zip.close()
