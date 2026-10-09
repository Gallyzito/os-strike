class_name OsuBeatmap
extends RefCounted
## Um beatmap do osu!standard lido de um ficheiro .osu (ou de um mapa .json do
## os!strike, só com círculos). Coordenadas no espaço do osu! (512 × 384) e
## tempos em segundos.
##
## Cada objeto é um Dictionary:
##   type        CIRCLE / SLIDER / SPINNER
##   time        início; end_time fim (= time nos círculos)
##   pos         posição (Vector2); end_pos onde acaba
##   combo_index cor do combo; combo_number número desenhado
##   hit_sound   bits do osu! (2 whistle, 4 finish, 8 clap); sample_set (1 normal, 2 soft, 3 drum)
## Sliders também têm: path (PackedVector2Array), cum (distâncias acumuladas),
##   length, repeats, span_duration, ticks (tempos), checkpoints [{time, kind}]

enum { CIRCLE, SLIDER, SPINNER }

const PLAYFIELD := Vector2(512, 384)
const DEFAULT_COLOURS: Array[Color] = [
	Color8(255, 192, 0), Color8(0, 202, 0), Color8(18, 124, 255), Color8(242, 24, 57),
]

var title := ""
var artist := ""
var version := ""
var creator := ""
var audio_file := ""
var background := ""
var preview := -1.0
var lead_in := 0.0
## Modo do osu! (0 = standard; os outros não servem).
var mode := 0
var hp := 5.0
var cs := 4.0
var od := 5.0
var ar := 5.0
var slider_multiplier := 1.4
var slider_tick_rate := 1.0
## Velocidade da música (mods DT/HT). O AR e o OD contam no tempo da música (como no osu!),
## por isso com DT tudo acontece 1.5× mais depressa em tempo real.
var rate := 1.0
## (tempo s, duração da batida ms, multiplicador de velocidade, sample set, volume 0..1)
var timing: Array[Dictionary] = []
var objects: Array[Dictionary] = []
var colours: Array[Color] = []
var breaks: Array[Vector2] = []


# --- Valores do osu! -----------------------------------------------------------------

## Raio dos círculos em pixels do osu!.
func radius() -> float:
	return 54.4 - 4.48 * cs


## Tempo (s) entre o círculo aparecer e ter de ser carregado (AR).
func preempt() -> float:
	if ar < 5.0:
		return (1200.0 + 600.0 * (5.0 - ar) / 5.0) / 1000.0
	return (1200.0 - 750.0 * (ar - 5.0) / 5.0) / 1000.0


func fade_in() -> float:
	if ar < 5.0:
		return (800.0 + 400.0 * (5.0 - ar) / 5.0) / 1000.0
	return (800.0 - 500.0 * (ar - 5.0) / 5.0) / 1000.0


## Janelas (s, para cada lado) de 300, 100 e 50 (OD).
func hit_windows() -> Vector3:
	return Vector3(80.0 - 6.0 * od, 140.0 - 8.0 * od, 200.0 - 10.0 * od) / 1000.0


func length() -> float:
	return objects[-1].end_time if not objects.is_empty() else 0.0


func first_time() -> float:
	return objects[0].time if not objects.is_empty() else 0.0


## Ponto de tempo ativo em `t` (s): o não herdado e o herdado mais recentes.
func timing_at(t: float) -> Dictionary:
	var beat := 500.0
	var sv := 1.0
	var sample_set := 1
	var volume := 0.7
	for tp in timing:
		if tp.time > t + 0.002:
			break
		if tp.uninherited:
			beat = tp.beat
			sv = 1.0
		else:
			sv = tp.sv
		sample_set = tp.sample_set
		volume = tp.volume
	return {"beat": beat, "sv": sv, "sample_set": sample_set, "volume": volume}


func is_break(t: float) -> bool:
	for b in breaks:
		if t >= b.x and t <= b.y:
			return true
	return false


## Posição da bola de um slider no tempo `t`.
static func slider_ball(obj: Dictionary, t: float) -> Vector2:
	var span: float = obj.span_duration
	var elapsed := clampf(t - float(obj.time), 0.0, span * int(obj.repeats))
	var index := mini(int(elapsed / span), int(obj.repeats) - 1)
	var progress := (elapsed - index * span) / span
	if index % 2 == 1:
		progress = 1.0 - progress
	return point_at(obj, progress * float(obj.length))


## Ponto do caminho a `distance` pixels do início.
static func point_at(obj: Dictionary, distance: float) -> Vector2:
	var path: PackedVector2Array = obj.path
	var cum: PackedFloat32Array = obj.cum
	if path.size() == 1:
		return path[0]
	distance = clampf(distance, 0.0, cum[cum.size() - 1])
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] < distance:
			lo = mid
		else:
			hi = mid
	var seg := cum[hi] - cum[lo]
	var k := (distance - cum[lo]) / seg if seg > 0.0001 else 0.0
	return path[lo].lerp(path[hi], k)


# --- Leitura --------------------------------------------------------------------------

static func load_file(file_path: String) -> OsuBeatmap:
	var text := FileAccess.get_file_as_string(file_path)
	if text.is_empty():
		return null
	var map := OsuBeatmap.new()
	var section := ""
	var raw_objects: PackedStringArray = []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		match section:
			"General", "Metadata", "Difficulty", "Colours":
				var i := line.find(":")
				if i > 0:
					map._set_value(section, line.substr(0, i).strip_edges(), line.substr(i + 1).strip_edges())
			"Events":
				var parts := line.split(",")
				if parts.size() >= 3 and parts[0] == "0" and map.background.is_empty():
					map.background = parts[2].strip_edges().trim_prefix("\"").trim_suffix("\"")
				elif parts.size() >= 3 and (parts[0] == "2" or parts[0] == "Break"):
					map.breaks.append(Vector2(float(parts[1]), float(parts[2])) / 1000.0)
			"TimingPoints":
				var p := line.split(",")
				if p.size() >= 2:
					var beat := float(p[1])
					var uninherited := p.size() < 7 or p[6].strip_edges() == "1"
					map.timing.append({
						"time": float(p[0]) / 1000.0,
						"uninherited": uninherited and beat > 0.0,
						"beat": beat if beat > 0.0 else 500.0,
						"sv": clampf(-100.0 / beat, 0.1, 10.0) if beat < 0.0 else 1.0,
						"sample_set": int(p[3]) if p.size() > 3 else 1,
						"volume": (float(p[5]) if p.size() > 5 else 70.0) / 100.0,
					})
			"HitObjects":
				raw_objects.append(line)
	map.timing.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.time < b.time or (a.time == b.time and a.uninherited and not b.uninherited))
	for line in raw_objects:
		map._parse_object(line)
	map.objects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	map._assign_combos()
	return map if not map.objects.is_empty() else null


## Mapa .json do os!strike (notas com posição -1..1 / 0..1): círculos.
static func from_json(data: Dictionary) -> OsuBeatmap:
	var map := OsuBeatmap.new()
	map.title = data.get("title", "")
	map.artist = data.get("artist", "")
	map.version = data.get("difficulty", "")
	map.creator = data.get("mapper", "os!strike")
	map.audio_file = data.get("audio", "audio.mp3")
	map.background = data.get("background", "")
	var stars := float(data.get("stars", 2.0))
	map.cs = 4.0
	map.od = clampf(2.0 + stars * 1.5, 0.0, 10.0)
	var preempt_ms := float(data.get("approach", 1.0)) * 1000.0
	map.ar = 5.0 - (preempt_ms - 1200.0) / 120.0 if preempt_ms > 1200.0 else 5.0 + (1200.0 - preempt_ms) / 150.0
	map.hp = clampf(float(data.get("hp_miss", 8.0)) * 0.5, 2.0, 8.0)
	map.timing.append({"time": 0.0, "uninherited": true, "beat": 60000.0 / maxf(float(data.get("bpm", 120)), 1.0),
		"sv": 1.0, "sample_set": 2, "volume": 0.7})
	var count := 0
	for n: Dictionary in data.get("notes", []):
		count += 1
		map.objects.append({
			"type": CIRCLE, "time": float(n.t), "end_time": float(n.t),
			"pos": Vector2(256.0 + float(n.get("x", 0.0)) * 220.0, 40.0 + float(n.get("y", 0.5)) * 300.0),
			"new_combo": count % 6 == 1, "combo_skip": 0, "hit_sound": 0, "sample_set": 0,
		})
	for o in map.objects:
		o["end_pos"] = o.pos
	map._assign_combos()
	return map


func _set_value(section: String, key: String, value: String) -> void:
	match section:
		"General":
			match key:
				"AudioFilename": audio_file = value
				"PreviewTime": preview = float(value) / 1000.0
				"AudioLeadIn": lead_in = float(value) / 1000.0
				"Mode": mode = int(value)
		"Metadata":
			match key:
				# O título romanizado primeiro (a fonte não tem japonês/chinês).
				"Title": title = value
				"TitleUnicode": title = value if title.is_empty() else title
				"Artist": artist = value
				"ArtistUnicode": artist = value if artist.is_empty() else artist
				"Version": version = value
				"Creator": creator = value
		"Difficulty":
			match key:
				"HPDrainRate": hp = float(value)
				"CircleSize": cs = float(value)
				"OverallDifficulty":
					od = float(value)
					if not _has_ar:
						ar = od
				"ApproachRate":
					ar = float(value)
					_has_ar = true
				"SliderMultiplier": slider_multiplier = float(value)
				"SliderTickRate": slider_tick_rate = float(value)
		"Colours":
			if key.begins_with("Combo"):
				var c := value.split(",")
				if c.size() >= 3:
					colours.append(Color8(int(c[0]), int(c[1]), int(c[2])))


var _has_ar := false


func _parse_object(line: String) -> void:
	var p := line.split(",")
	if p.size() < 4:
		return
	var type := int(p[3])
	var obj := {
		"pos": Vector2(float(p[0]), float(p[1])),
		"time": float(p[2]) / 1000.0,
		"new_combo": type & 4 != 0,
		"combo_skip": (type >> 4) & 7,
		"hit_sound": int(p[4]) if p.size() > 4 else 0,
		"sample_set": 0,
	}
	if type & 8:
		obj["type"] = SPINNER
		obj["end_time"] = float(p[5]) / 1000.0 if p.size() > 5 else obj.time + 1.0
		obj["pos"] = PLAYFIELD * 0.5
		obj["end_pos"] = obj.pos
		obj["new_combo"] = true
	elif type & 2 and p.size() >= 8:
		obj["type"] = SLIDER
		_build_slider(obj, p)
	else:
		obj["type"] = CIRCLE
		obj["end_time"] = obj.time
		obj["end_pos"] = obj.pos
	objects.append(obj)


func _build_slider(obj: Dictionary, p: PackedStringArray) -> void:
	var curve := p[5].split("|")
	var kind := curve[0]
	var points := PackedVector2Array([obj.pos])
	for i in range(1, curve.size()):
		var xy := curve[i].split(":")
		if xy.size() == 2:
			points.append(Vector2(float(xy[0]), float(xy[1])))
	var repeats := maxi(int(p[6]), 1)
	var pixel_length := float(p[7])
	var raw := SliderPath.compute(kind, points)
	if pixel_length <= 0.0:
		pixel_length = SliderPath.total_length(raw)
	var fitted := SliderPath.fit_length(raw, pixel_length)
	var tp := timing_at(obj.time)
	var velocity := slider_multiplier * 100.0 * float(tp.sv)  # pixels por batida
	var span := pixel_length / velocity * float(tp.beat) / 1000.0
	obj["path"] = fitted[0]
	obj["cum"] = fitted[1]
	obj["length"] = pixel_length
	obj["repeats"] = repeats
	obj["span_duration"] = maxf(span, 0.01)
	obj["end_time"] = obj.time + obj.span_duration * repeats
	obj["end_pos"] = point_at(obj, pixel_length if repeats % 2 == 1 else 0.0)
	# Pontos de controlo: ticks, repetições e o fim (um pouco antes, como no osu! stable).
	var checkpoints: Array[Dictionary] = []
	var tick_dist := velocity / maxf(slider_tick_rate, 0.1)
	for s in repeats:
		var d := tick_dist
		while d < pixel_length - tick_dist * 0.1:
			var frac := d / pixel_length
			if s % 2 == 1:
				frac = 1.0 - frac
			checkpoints.append({"time": obj.time + (s + d / pixel_length) * obj.span_duration,
				"kind": "tick", "pos": point_at(obj, frac * pixel_length)})
			d += tick_dist
		if s < repeats - 1:
			checkpoints.append({"time": obj.time + (s + 1) * obj.span_duration, "kind": "repeat",
				"pos": point_at(obj, pixel_length if s % 2 == 0 else 0.0)})
	checkpoints.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	checkpoints.append({"time": maxf(obj.end_time - 0.036, obj.time + obj.span_duration * 0.5), "kind": "tail",
		"pos": obj.end_pos})
	obj["checkpoints"] = checkpoints


func _assign_combos() -> void:
	var index := -1
	var number := 0
	for i in objects.size():
		var o := objects[i]
		if i == 0 or o.new_combo:
			index += 1 + int(o.get("combo_skip", 0))
			number = 0
		number += 1
		o["combo_index"] = index
		o["combo_number"] = number
