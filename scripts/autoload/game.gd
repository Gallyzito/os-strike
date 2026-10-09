extends Node
## Mapas, recordes e mudança de cena entre o lobby e o jogo.
##
## Os mapas estão na pasta "maps": ao lado do executável no jogo exportado, ou
## a pasta "maps" do projeto quando corre a partir do editor. Cada subpasta é
## uma música, com o áudio e um ficheiro .json por dificuldade:
##   maps/into_the_void/audio.mp3
##   maps/into_the_void/facil.json, normal.json, dificil.json, insano.json
## Para instalar mapas novos basta copiar a pasta deles para "maps".
## Mapas do osu! (.osz) postos na pasta são convertidos automaticamente
## (ver OsuImporter).

const LOBBY_SCENE := "res://scenes/main_menu/main_menu.tscn"
const GAME_SCENE := "res://scenes/game/game.tscn"
const SCORES_PATH := "user://scores.cfg"
const MAP_FORMAT := 2
## Imagem para os mapas que não trazem fundo.
const DEFAULT_BACKGROUND := "res://assets/ui/environments/dust2_long.jpg"
## Espectro contínuo de cor por estrelas (como o do osu!lazer): azul, ciano,
## verde, amarelo, laranja, vermelho, roxo e índigo. [estrelas, cor]
const DIFFICULTY_SPECTRUM: Array = [
	[0.0, Color("6f8fb3")], [1.25, Color("4fc0ff")], [2.0, Color("4fffd5")], [2.5, Color("7cff4f")],
	[3.3, Color("f6f05c")], [4.2, Color("ff8068")], [4.9, Color("ff4e6f")], [5.8, Color("c645b8")],
	[6.7, Color("6563de")], [7.7, Color("3f3bcf")], [9.0, Color("2a2790")],
]
## Nomes dos escalões, como os ícones de dificuldade do osu!. [estrelas mínimas, nome]
const DIFFICULTY_TIERS: Array = [
	[0.0, "EASY"], [2.0, "NORMAL"], [2.7, "HARD"], [4.0, "INSANE"], [5.3, "EXPERT"], [6.5, "EXPERT+"],
]

## Mapa escolhido (dados do .json + "dir" e "id").
var current_map := {}
## Resultado do último jogo (pontos, precisão, contagens...).
var last_result := {}
## Verdadeiro quando o lobby abre depois de um jogo (salta a abertura longa).
var returning := false
## Mensagens da última importação de mapas do osu! (para mostrar na seleção).
var import_messages: Array[String] = []

var _backgrounds: Dictionary[String, Texture2D] = {}
var _audio_cache := {}
var _audio_mutex := Mutex.new()


func maps_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://maps")
	return OS.get_executable_path().get_base_dir().path_join("maps")


## Lê todos os mapas instalados, ordenados por música e dificuldade.
## Antes disso converte os mapas do osu! que ainda não foram convertidos.
func scan_maps() -> Array[Dictionary]:
	import_messages = OsuImporter.import_all(maps_dir())
	var maps: Array[Dictionary] = []
	var root := DirAccess.open(maps_dir())
	if root == null:
		return maps
	for folder in root.get_directories():
		var dir := maps_dir().path_join(folder)
		for file in DirAccess.get_files_at(dir):
			if file.get_extension().to_lower() != "json":
				continue
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
			if not data is Dictionary or int(data.get("format", 0)) != MAP_FORMAT:
				continue
			if (data.get("notes", []) as Array).is_empty():
				continue
			data["dir"] = dir
			data["id"] = "%s/%s" % [folder, file.get_basename()]
			maps.append(data)
	maps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.title != b.title:
			return String(a.title).naturalnocasecmp_to(b.title) < 0
		if float(a.stars) != float(b.stars):
			return float(a.stars) < float(b.stars)
		return (a.notes as Array).size() < (b.notes as Array).size())
	return maps


## Uma música aleatória (o mapa mais fácil dela) para o menu, diferente de `exclude_id`.
func random_song(exclude_id := "") -> Dictionary:
	var by_dir := {}
	for map in scan_maps():
		if not by_dir.has(map.dir):
			by_dir[map.dir] = map
	var songs := by_dir.values()
	if songs.size() > 1:
		songs = songs.filter(func(m: Dictionary) -> bool: return music_id(m) != exclude_id)
	return songs.pick_random() if not songs.is_empty() else {}


func load_audio(map: Dictionary) -> AudioStream:
	var path := String(map.dir).path_join(map.audio)
	_audio_mutex.lock()
	var cached: AudioStream = _audio_cache.get(path)
	_audio_mutex.unlock()
	if cached:
		return cached
	return AudioManager.load_sound_file(path)


## Carrega a música do mapa para a cache (corre numa thread durante o loading).
## Só fica a última música: ao tentar de novo o mapa já está pronto.
func preload_audio(map: Dictionary) -> void:
	var path := String(map.dir).path_join(map.audio)
	_audio_mutex.lock()
	var has := _audio_cache.has(path)
	_audio_mutex.unlock()
	if has:
		return
	var stream := AudioManager.load_sound_file(path)
	_audio_mutex.lock()
	_audio_cache.clear()
	if stream:
		_audio_cache[path] = stream
	_audio_mutex.unlock()


## Imagem do mapa (o fundo do mapa, ou uma imagem por defeito se não tiver).
func background(map: Dictionary) -> Texture2D:
	return _background(map, false)


## A mesma imagem em muito pequeno: esticada no ecrã fica desfocada.
func background_blur(map: Dictionary) -> Texture2D:
	return _background(map, true)


func _background(map: Dictionary, blur: bool) -> Texture2D:
	var file := String(map.get("background", ""))
	var path := String(map.get("dir", "")).path_join(file) if not file.is_empty() else ""
	if path.is_empty() or not FileAccess.file_exists(path):
		path = DEFAULT_BACKGROUND
	if path.is_empty():
		return null
	var key := path + ("#blur" if blur else "")
	if _backgrounds.has(key):
		return _backgrounds[key]
	var img: Image = null
	if path.begins_with("res://"):
		var res: Texture2D = load(path)
		img = res.get_image() if res else null
	elif FileAccess.file_exists(path):
		img = Image.load_from_file(path)
	var tex: Texture2D = null
	if img:
		if img.is_compressed():
			img.decompress()
		var target := 72 if blur else 1280
		if img.get_width() > target:
			img.resize(target, maxi(int(img.get_height() * float(target) / img.get_width()), 1), Image.INTERPOLATE_LANCZOS)
		tex = ImageTexture.create_from_image(img)
	_backgrounds[key] = tex
	return tex


## Identificador da música do mapa (para não recomeçar a pré-visualização).
func music_id(map: Dictionary) -> String:
	return "%s|%s" % [map.title, map.artist]


## Cor de uma dificuldade, interpolada suavemente no espectro.
func difficulty_color(stars: float) -> Color:
	var first: Array = DIFFICULTY_SPECTRUM[0]
	if stars <= float(first[0]):
		return first[1]
	for i in range(1, DIFFICULTY_SPECTRUM.size()):
		var b: Array = DIFFICULTY_SPECTRUM[i]
		if stars <= float(b[0]):
			var a: Array = DIFFICULTY_SPECTRUM[i - 1]
			var t := (stars - float(a[0])) / (float(b[0]) - float(a[0]))
			return (a[1] as Color).lerp(b[1], t)
	return DIFFICULTY_SPECTRUM[-1][1]


## Escalão da dificuldade (EASY, NORMAL, HARD, INSANE, EXPERT, EXPERT+).
func difficulty_tier(stars: float) -> String:
	var name := ""
	for tier: Array in DIFFICULTY_TIERS:
		if stars >= float(tier[0]):
			name = tier[1]
	return name


func play(map: Dictionary) -> void:
	current_map = map
	Loading.go(GAME_SCENE, map)


func back_to_lobby() -> void:
	returning = true
	Loading.go(LOBBY_SCENE)


## Melhor resultado guardado de um mapa ({} se nunca foi jogado).
func best_score(map_id: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SCORES_PATH) != OK:
		return {}
	return cfg.get_value("scores", map_id, {})


## Guarda o resultado se for o melhor. Devolve verdadeiro se for recorde.
func save_score(map_id: String, result: Dictionary) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SCORES_PATH)
	var best: Dictionary = cfg.get_value("scores", map_id, {})
	if not best.is_empty() and int(best.get("score", 0)) >= int(result.score):
		return false
	cfg.set_value("scores", map_id, {
		"score": result.score, "accuracy": result.accuracy, "grade": result.grade, "max_combo": result.max_combo,
	})
	cfg.save(SCORES_PATH)
	return true
