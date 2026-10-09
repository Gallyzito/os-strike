class_name SfxBank
## Efeitos sonoros gerados por código (sem ficheiros de áudio).

const RATE := 44100


static func build() -> Dictionary[StringName, AudioStream]:
	return {
		&"hover": _hover(),
		&"select": _select(),
		&"back": _back(),
		&"shot": _shot(),
		&"shot_usp": _shot_usp(),
		&"shot_deagle": _shot_deagle(),
		&"draw": _draw(),
		&"ring": _ring(),
		&"hit": _hit(),
		&"beep": _beep(),
		&"hurt": _hurt(),
		&"explosion": _explosion(),
		&"glass": _glass(),
		&"glitch": _glitch(),
	}


## Bip da contagem decrescente (como o da bomba).
static func _beep() -> AudioStreamWAV:
	var s := _buffer(0.12)
	for i in s.size():
		var t := float(i) / RATE
		var env := minf(t / 0.004, 1.0) * exp(-t * 22.0)
		s[i] = (sin(TAU * 1760.0 * t) * 0.6 + sin(TAU * 3520.0 * t) * 0.15) * env * 0.6
	return _wav(s)


## Levar um tiro: "thud" abafado com um estalo curto.
static func _hurt() -> AudioStreamWAV:
	var s := _buffer(0.3)
	var low := 0.0
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		low = lerpf(low, _noise(), 0.08)
		phase += TAU * lerpf(140.0, 45.0, minf(t / 0.2, 1.0)) / RATE
		s[i] = tanh((sin(phase) * exp(-t * 14.0) * 0.9 + low * exp(-t * 20.0) * 2.0) * 1.3) * 0.75
	return _wav(s)


## Hitsound padrão: "dink" metálico curto, como o headshot do CS.
static func _hit() -> AudioStreamWAV:
	var s := _buffer(0.18)
	for i in s.size():
		var t := float(i) / RATE
		var ping := sin(TAU * 1850.0 * t) * 0.5 + sin(TAU * 2790.0 * t) * 0.3 + sin(TAU * 4120.0 * t) * 0.15
		s[i] = ping * exp(-t * 26.0) * 0.6 + _noise() * exp(-t * 400.0) * 0.25
	return _wav(s)


## Tique curto e metálico ao passar o rato.
static func _hover() -> AudioStreamWAV:
	var s := _buffer(0.035)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * 2600.0 * t) * exp(-t * 160.0) * 0.25 + _noise() * exp(-t * 500.0) * 0.12
	return _wav(s)


## "Thunk" grave ao confirmar.
static func _select() -> AudioStreamWAV:
	var s := _buffer(0.16)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		phase += TAU * lerpf(190.0, 60.0, minf(t / 0.12, 1.0)) / RATE
		s[i] = sin(phase) * exp(-t * 22.0) * 0.7 + _noise() * exp(-t * 300.0) * 0.2
	return _wav(s)


static func _back() -> AudioStreamWAV:
	var s := _buffer(0.12)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		phase += TAU * lerpf(90.0, 170.0, minf(t / 0.1, 1.0)) / RATE
		s[i] = sin(phase) * exp(-t * 28.0) * 0.55 + _noise() * exp(-t * 400.0) * 0.15
	return _wav(s)


## Disparo: estalo + corpo de ruído filtrado + "thump" grave.
static func _shot() -> AudioStreamWAV:
	var s := _buffer(0.45)
	var low := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var n := _noise()
		low = lerpf(low, n, 0.18)
		var crack := n * exp(-t * 120.0) * 0.6
		var body := low * exp(-t * 14.0) * 1.6
		var thump := sin(TAU * 62.0 * t) * exp(-t * 18.0) * 0.8
		s[i] = tanh((crack + body + thump) * 1.4) * 0.8
	return _wav(s)


## USP-S com silenciador: "tchk" abafado (sopro curto filtrado) + estalo metálico
## da corrediça.
static func _shot_usp() -> AudioStreamWAV:
	var s := _buffer(0.3)
	var low := 0.0
	var lower := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var n := _noise()
		low = lerpf(low, n, 0.25)
		lower = lerpf(lower, low, 0.12)
		var puff := (low * 0.7 + lower * 1.8) * exp(-t * 38.0)
		var click := sin(TAU * 2900.0 * t) * exp(-maxf(t - 0.012, 0.0) * 260.0) * (0.0 if t < 0.012 else 0.22)
		var slide := n * exp(-maxf(t - 0.05, 0.0) * 180.0) * (0.0 if t < 0.05 else 0.12)
		s[i] = tanh((puff + click + slide) * 1.3) * 0.75
	return _wav(s)


## Desert Eagle: estalo forte, estrondo grave longo e eco.
static func _shot_deagle() -> AudioStreamWAV:
	var s := _buffer(0.9)
	var low := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var n := _noise()
		low = lerpf(low, n, 0.12)
		var crack := n * exp(-t * 90.0) * 0.9
		var body := low * exp(-t * 8.0) * 2.0
		var thump := sin(TAU * lerpf(70.0, 42.0, minf(t / 0.25, 1.0)) * t) * exp(-t * 9.0) * 1.1
		var echo := low * exp(-maxf(t - 0.18, 0.0) * 7.0) * (0.0 if t < 0.18 else 0.35)
		s[i] = tanh((crack + body + thump + echo) * 1.8) * 0.85
	return _wav(s)


## Sacar a arma: dois cliques metálicos (carregador/corrediça).
static func _draw() -> AudioStreamWAV:
	var s := _buffer(0.22)
	for i in s.size():
		var t := float(i) / RATE
		var a := sin(TAU * 1800.0 * t) * exp(-t * 160.0) * 0.4 + _noise() * exp(-t * 300.0) * 0.25
		var t2 := maxf(t - 0.11, 0.0)
		var b := 0.0 if t < 0.11 else sin(TAU * 2400.0 * t2) * exp(-t2 * 140.0) * 0.35 + _noise() * exp(-t2 * 260.0) * 0.3
		s[i] = (a + b) * 0.8
	return _wav(s)


## Zumbido nos ouvidos depois de um flashbang.
static func _ring() -> AudioStreamWAV:
	var duration := 2.2
	var s := _buffer(duration)
	for i in s.size():
		var t := float(i) / RATE
		var env := minf(t / 0.05, 1.0) * pow(1.0 - t / duration, 2.0)
		s[i] = (sin(TAU * 3400.0 * t) + sin(TAU * 3417.0 * t) * 0.6) * env * 0.05
	return _wav(s)


static func _buffer(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


static func _noise() -> float:
	return randf() * 2.0 - 1.0


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## Explosão: estalo, estrondo grave a descer e ruído a crepitar.
static func _explosion() -> AudioStreamWAV:
	var s := _buffer(2.2)
	var low := 0.0
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var n := _noise()
		low = lerpf(low, n, 0.04)
		phase += TAU * lerpf(90.0, 28.0, minf(t / 1.2, 1.0)) / RATE
		var boom := sin(phase) * exp(-t * 2.2) * 1.1
		var rumble := low * exp(-t * 1.6) * 3.0
		var crack := n * exp(-t * 35.0) * 0.9
		var crackle := n * (1.0 if randf() < 0.004 * exp(-t * 2.0) * 60.0 else 0.0) * exp(-t * 1.5) * 0.5
		s[i] = tanh((boom + rumble + crack + crackle) * 1.6) * 0.85
	return _wav(s)


## Vidro a partir: muitos "tins" agudos e curtos sobre ruído.
static func _glass() -> AudioStreamWAV:
	var s := _buffer(1.2)
	var pings: Array[Vector3] = []
	for k in 24:
		pings.append(Vector3(randf() * 0.9 * randf(), randf_range(2500.0, 7500.0), randf_range(0.2, 0.7)))
	for i in s.size():
		var t := float(i) / RATE
		var v := _noise() * exp(-t * 12.0) * 0.35
		for p in pings:
			var dt := t - p.x
			if dt >= 0.0 and dt < 0.25:
				v += sin(TAU * p.y * dt) * exp(-dt * 30.0) * p.z * 0.35
		s[i] = tanh(v * 1.3) * 0.8
	return _wav(s)


## Zumbido de avaria: onda quadrada a falhar.
static func _glitch() -> AudioStreamWAV:
	var s := _buffer(0.9)
	var gate := 1.0
	for i in s.size():
		var t := float(i) / RATE
		if i % 1300 == 0:
			gate = 1.0 if randf() < 0.7 else 0.0
		var f := 110.0 + 40.0 * sin(t * 37.0) + t * 120.0
		var sq := 1.0 if fmod(t * f, 1.0) < 0.5 else -1.0
		s[i] = (sq * 0.35 + _noise() * 0.25) * gate * minf(t / 0.02, 1.0) * (0.6 + t * 0.5)
	return _wav(s)