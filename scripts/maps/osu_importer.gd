class_name OsuImporter
## Prepara os mapas do osu! para a seleção de mapas.
##
## - Um ficheiro .osz posto na pasta "maps" é extraído para uma subpasta.
## - Cada .osu (modo osu!standard) ganha um .json ao lado com o índice do mapa
##   (título, dificuldade, estrelas, AR/OD/CS/HP, duração, densidade...). O jogo
##   lê o .osu completo (círculos, sliders e spinners) na altura de jogar.
## - As estrelas vêm da densidade de objetos, do AR e do tamanho dos saltos.
## Quando o índice muda (CONVERTER_VERSION), os mapas são indexados outra vez.

const CONVERTER_VERSION := 3
const SKIP_EXTENSIONS: Array[String] = ["mp4", "avi", "flv", "wmv", "mkv", "webm", "mov"]


## Importa tudo o que houver de novo. Devolve mensagens para mostrar ao jogador.
static func import_all(maps_dir: String) -> Array[String]:
	var messages: Array[String] = []
	if not DirAccess.dir_exists_absolute(maps_dir):
		return messages
	for file in DirAccess.get_files_at(maps_dir):
		if file.get_extension().to_lower() != "osz":
			continue
		var dest := maps_dir.path_join(_safe_name(file.get_basename()))
		if DirAccess.dir_exists_absolute(dest):
			continue
		if _extract(maps_dir.path_join(file), dest):
			messages.append("Imported: " + file)
		else:
			messages.append("Could not open: " + file)
	for folder in DirAccess.get_directories_at(maps_dir):
		var dir := maps_dir.path_join(folder)
		for file in DirAccess.get_files_at(dir):
			if file.get_extension().to_lower() != "osu":
				continue
			var json_path := dir.path_join(file.get_basename() + ".json")
			if FileAccess.file_exists(json_path) and _converter_version(json_path) >= CONVERTER_VERSION:
				continue
			var data := index_osu(dir.path_join(file))
			data["converter"] = CONVERTER_VERSION
			# Grava mesmo quando não serve (format 0), para não voltar a tentar.
			var out := FileAccess.open(json_path, FileAccess.WRITE)
			if out == null:
				continue
			out.store_string(JSON.stringify(data, " "))
			out.close()
			if int(data.get("format", 0)) == 0:
				messages.append("Skipped (%s): %s" % [data.get("reason", "?"), file])
	return messages


## Lê um .osu e devolve o índice do mapa ({"format": 0} se não servir).
static func index_osu(path: String) -> Dictionary:
	var bm := OsuBeatmap.load_file(path)
	if bm == null:
		return {"format": 0, "reason": "no objects"}
	if bm.mode != 0:
		return {"format": 0, "reason": "osu!standard only"}
	var notes: Array[Dictionary] = []
	var sliders := 0
	var spinners := 0
	for o in bm.objects:
		match int(o.type):
			OsuBeatmap.SLIDER:
				sliders += 1
			OsuBeatmap.SPINNER:
				spinners += 1
		var p: Vector2 = o.pos
		notes.append({"t": snappedf(float(o.time), 0.001), "x": snappedf(p.x / 256.0 - 1.0, 0.001),
			"y": snappedf(p.y / 384.0, 0.001)})
	var first := bm.first_time()
	var last := bm.length()
	var bpm := 0.0
	for tp in bm.timing:
		if tp.uninherited:
			bpm = 60000.0 / float(tp.beat)
			break
	var length := last + 1.0
	return {
		"format": 2,
		"title": bm.title if not bm.title.is_empty() else path.get_file().get_basename(),
		"artist": bm.artist,
		"mapper": bm.creator,
		"difficulty": bm.version if not bm.version.is_empty() else "?",
		"stars": _stars(notes, last - first, bm.ar),
		"audio": bm.audio_file,
		"background": bm.background,
		"bpm": roundf(bpm),
		"length": snappedf(length, 0.01),
		"preview": bm.preview if bm.preview >= 0.0 else snappedf(length * 0.3, 0.1),
		"approach": snappedf(bm.preempt(), 0.01),
		"late_window": snappedf(bm.hit_windows().z, 0.001),
		"cs": bm.cs,
		"ar": bm.ar,
		"od": bm.od,
		"hp": bm.hp,
		"sliders": sliders,
		"spinners": spinners,
		"source": "os!strike" if bm.creator == "os!strike" else "osu!",
		"osu_file": path.get_file(),
		"notes": notes,
	}


## Estrelas (0.5..9.9): objetos por segundo + AR alto + saltos grandes e rápidos.
static func _stars(notes: Array[Dictionary], drain: float, ar: float) -> float:
	var nps := notes.size() / maxf(drain, 1.0)
	var jump := 0.0
	for i in range(1, notes.size()):
		var a: Dictionary = notes[i - 1]
		var b: Dictionary = notes[i]
		var dt := maxf(float(b.t) - float(a.t), 0.08)
		if dt > 1.0:
			continue
		var dist := Vector2(float(b.x) - float(a.x), (float(b.y) - float(a.y)) * 0.75).length()
		jump += dist / dt
	jump = clampf(jump / maxf(notes.size() - 1, 1) * 0.3, 0.0, 1.6)
	return snappedf(clampf(0.3 + nps * 0.8 + maxf(ar - 5.0, 0.0) * 0.2 + jump, 0.5, 9.9), 0.1)


static func _converter_version(json_path: String) -> int:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not data is Dictionary:
		return 0
	return int(data.get("converter", 0))


## Extrai um .osz (zip). Ignora vídeos e caminhos perigosos.
static func _extract(zip_path: String, dest: String) -> bool:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return false
	DirAccess.make_dir_recursive_absolute(dest)
	for name in zip.get_files():
		if name.ends_with("/") or name.contains("..") or name.begins_with("/") or name.contains(":"):
			continue
		if name.get_extension().to_lower() in SKIP_EXTENSIONS:
			continue
		var target := dest.path_join(name)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			continue
		out.store_buffer(zip.read_file(name))
		out.close()
	zip.close()
	return true


## Nome de pasta válido no Windows.
static func _safe_name(name: String) -> String:
	var out := ""
	for c in name:
		out += "_" if "\\/:*?\"<>|".contains(c) else c
	return out.strip_edges().trim_suffix(".")
