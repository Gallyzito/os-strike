class_name OsuMods
## Mods do osu!. Os ativos ficam guardados nas Opções ("osu/mods", ex.: "HD,HR").
##
## Efeitos (como no osu!):
##   EZ  CS/AR/OD/HP a metade              HR  CS ×1.3, AR/OD/HP ×1.4, mapa ao contrário
##   HT  música a 0.75×                    DT  música a 1.5×      NC  1.5× com tom mais agudo
##   NF  não se morre                      SD  morre-se no primeiro falhanço
##   PF  morre-se se não for tudo 300      HD  sem círculos de aproximação; os círculos desaparecem
##   FL  só se vê à volta da mira          AU  o jogo joga sozinho (os pontos não ficam guardados)

const LIST: Array[Dictionary] = [
	{"id": "EZ", "name": "Easy", "desc": "Larger, slower and more forgiving circles", "mult": 0.5, "group": 0, "key": KEY_Q},
	{"id": "NF", "name": "No Fail", "desc": "You can't fail", "mult": 0.5, "group": 0, "key": KEY_W},
	{"id": "HT", "name": "Half Time", "desc": "Music at 0.75×", "mult": 0.3, "group": 0, "key": KEY_E},
	{"id": "HR", "name": "Hard Rock", "desc": "Everything harder and the map flipped", "mult": 1.06, "group": 1, "key": KEY_A},
	{"id": "SD", "name": "Sudden Death", "desc": "One miss and you fail", "mult": 1.0, "group": 1, "key": KEY_S},
	{"id": "PF", "name": "Perfect", "desc": "Anything but a 300 fails", "mult": 1.0, "group": 1, "key": KEY_S},
	{"id": "DT", "name": "Double Time", "desc": "Music at 1.5×", "mult": 1.12, "group": 1, "key": KEY_D},
	{"id": "NC", "name": "Nightcore", "desc": "1.5× with higher pitch", "mult": 1.12, "group": 1, "key": KEY_D},
	{"id": "HD", "name": "Hidden", "desc": "No approach circles; objects fade out", "mult": 1.06, "group": 1, "key": KEY_F},
	{"id": "FL", "name": "Flashlight", "desc": "You only see around the cursor", "mult": 1.12, "group": 1, "key": KEY_G},
	{"id": "AU", "name": "Auto", "desc": "Watch the map play itself", "mult": 1.0, "group": 2, "key": KEY_V},
]
const GROUP_NAMES: Array[String] = ["DIFFICULTY REDUCTION", "DIFFICULTY INCREASE", "SPECIAL"]
const GROUP_COLORS: Array[Color] = [Color(0.45, 0.9, 0.5), Color(1.0, 0.42, 0.42), Color(0.55, 0.7, 1.0)]
## Mods que não podem estar ligados ao mesmo tempo.
const CONFLICTS := {
	"EZ": ["HR"], "HR": ["EZ"], "HT": ["DT", "NC"], "DT": ["HT", "NC"], "NC": ["HT", "DT"],
	"NF": ["SD", "PF", "AU"], "SD": ["NF", "PF", "AU"], "PF": ["NF", "SD", "AU"], "AU": ["NF", "SD", "PF"],
}


static func active() -> Array[String]:
	var out: Array[String] = []
	for id in String(Settings.get_value("osu/mods")).split(",", false):
		if info(id).size() > 0:
			out.append(id)
	return out


static func is_on(id: String) -> bool:
	return id in active()


static func info(id: String) -> Dictionary:
	for m in LIST:
		if m.id == id:
			return m
	return {}


## Liga/desliga um mod (desliga os que não podem estar com ele).
static func toggle(id: String) -> void:
	var mods := active()
	if id in mods:
		mods.erase(id)
	else:
		for other: String in CONFLICTS.get(id, []):
			mods.erase(other)
		mods.append(id)
	set_active(mods)


static func set_active(mods: Array[String]) -> void:
	var ordered: Array[String] = []
	for m in LIST:
		if m.id in mods:
			ordered.append(m.id)
	Settings.set_value("osu/mods", ",".join(ordered))
	Settings.save_settings()


static func multiplier(mods: Array[String]) -> float:
	var k := 1.0
	for id in mods:
		k *= float(info(id).get("mult", 1.0))
	return k


## Velocidade da música.
static func speed(mods: Array[String]) -> float:
	if "DT" in mods or "NC" in mods:
		return 1.5
	if "HT" in mods:
		return 0.75
	return 1.0


## CS, AR, OD e HP com os mods (sem contar a velocidade).
static func adjust_stats(cs: float, ar: float, od: float, hp: float, mods: Array[String]) -> Vector4:
	if "EZ" in mods:
		return Vector4(cs * 0.5, ar * 0.5, od * 0.5, hp * 0.5)
	if "HR" in mods:
		return Vector4(minf(cs * 1.3, 10.0), minf(ar * 1.4, 10.0), minf(od * 1.4, 10.0), minf(hp * 1.4, 10.0))
	return Vector4(cs, ar, od, hp)


## AR e OD "efetivos" com a velocidade (como o osu! mostra com DT/HT).
static func effective_ar(ar: float, rate: float) -> float:
	var ms := (1200.0 + 600.0 * (5.0 - ar) / 5.0 if ar < 5.0 else 1200.0 - 750.0 * (ar - 5.0) / 5.0) / rate
	return 5.0 + (1200.0 - ms) / 150.0 if ms <= 1200.0 else 5.0 - (ms - 1200.0) / 120.0


static func effective_od(od: float, rate: float) -> float:
	return (80.0 - (80.0 - 6.0 * od) / rate) / 6.0


## Estrelas aproximadas com os mods.
static func star_factor(mods: Array[String]) -> float:
	var k := 1.0
	if "EZ" in mods:
		k *= 0.6
	if "HR" in mods:
		k *= 1.1
	if "FL" in mods:
		k *= 1.12
	var s := speed(mods)
	if s > 1.0:
		k *= 1.38
	elif s < 1.0:
		k *= 0.75
	return k


## Aplica os mods a um beatmap já lido.
static func apply(bm: OsuBeatmap, mods: Array[String]) -> void:
	var st := adjust_stats(bm.cs, bm.ar, bm.od, bm.hp, mods)
	bm.cs = st.x
	bm.ar = st.y
	bm.od = st.z
	bm.hp = st.w
	bm.rate = speed(mods)
	if "HR" in mods:
		_flip(bm)


## HR: o mapa fica de pernas para o ar.
static func _flip(bm: OsuBeatmap) -> void:
	var h := OsuBeatmap.PLAYFIELD.y
	for o in bm.objects:
		o.pos = Vector2(o.pos.x, h - o.pos.y)
		o.end_pos = Vector2(o.end_pos.x, h - o.end_pos.y)
		if o.has("path"):
			var path: PackedVector2Array = o.path
			for i in path.size():
				path[i] = Vector2(path[i].x, h - path[i].y)
			o.path = path
		for cp: Dictionary in o.get("checkpoints", []):
			cp.pos = Vector2(cp.pos.x, h - cp.pos.y)
