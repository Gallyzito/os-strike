class_name SliderPath
## Curvas dos sliders do osu!: Bézier (com âncoras vermelhas), arco de círculo
## (P), linhas (L) e Catmull (C). Devolvem pontos a cada ~3 pixels.

const STEP := 3.0


static func compute(kind: String, points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 2:
		return points
	match kind:
		"L":
			return _subdivide(points)
		"P":
			if points.size() == 3:
				var arc := _arc(points)
				if not arc.is_empty():
					return arc
			return _bezier_segments(points)
		"C":
			return _catmull(points)
	return _bezier_segments(points)


static func total_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


## Corta (ou prolonga em linha reta) o caminho para ter `length` pixels.
## Devolve [pontos, distâncias acumuladas].
static func fit_length(path: PackedVector2Array, length: float) -> Array:
	var out := PackedVector2Array([path[0]])
	var cum := PackedFloat32Array([0.0])
	var total := 0.0
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		if seg < 0.0001:
			continue
		if total + seg >= length:
			out.append(path[i - 1].lerp(path[i], (length - total) / seg))
			cum.append(length)
			return [out, cum]
		total += seg
		out.append(path[i])
		cum.append(total)
	if total < length and out.size() >= 2:
		var dir := (out[out.size() - 1] - out[out.size() - 2]).normalized()
		out.append(out[out.size() - 1] + dir * (length - total))
		cum.append(length)
	elif out.size() == 1:
		out.append(out[0] + Vector2.RIGHT * maxf(length, 0.01))
		cum.append(maxf(length, 0.01))
	return [out, cum]


static func _subdivide(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([points[0]])
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var n := maxi(int(a.distance_to(b) / STEP), 1)
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / n))
	return out


## Bézier com segmentos separados por pontos repetidos (âncoras vermelhas).
static func _bezier_segments(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var segment := PackedVector2Array([points[0]])
	for i in range(1, points.size()):
		segment.append(points[i])
		var last := i == points.size() - 1
		if last or points[i] == points[i + 1]:
			var curve := _bezier(segment)
			if not out.is_empty():
				curve.remove_at(0)
			out.append_array(curve)
			segment = PackedVector2Array([points[i]])
	return out


static func _bezier(ctrl: PackedVector2Array) -> PackedVector2Array:
	if ctrl.size() == 2:
		return _subdivide(ctrl)
	var approx := total_length(ctrl)
	var n := clampi(int(approx / STEP), 4, 400)
	var out := PackedVector2Array()
	for k in n + 1:
		var t := float(k) / n
		var tmp := ctrl.duplicate()
		for level in range(1, ctrl.size()):
			for j in ctrl.size() - level:
				tmp[j] = tmp[j].lerp(tmp[j + 1], t)
		out.append(tmp[0])
	return out


## Arco de círculo pelos 3 pontos (vazio se forem colineares).
static func _arc(p: PackedVector2Array) -> PackedVector2Array:
	var a := p[0]
	var b := p[1]
	var c := p[2]
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 0.001:
		return PackedVector2Array()
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	var center := Vector2((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
		(a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
	var r := a.distance_to(center)
	var start := (a - center).angle()
	var end := (c - center).angle()
	# Sentido: o do ponto do meio.
	var ccw := (b - a).cross(c - b) > 0.0
	var sweep := end - start
	if ccw:
		while sweep < 0.0:
			sweep += TAU
	else:
		while sweep > 0.0:
			sweep -= TAU
	var n := clampi(int(absf(sweep) * r / STEP), 4, 600)
	var out := PackedVector2Array()
	for k in n + 1:
		var ang := start + sweep * k / n
		out.append(center + Vector2(cos(ang), sin(ang)) * r)
	return out


static func _catmull(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points.size() - 1:
		var p0 := points[i - 1] if i > 0 else points[i]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[i + 2] if i + 2 < points.size() else p2 + (p2 - p1)
		var n := clampi(int(p1.distance_to(p2) / STEP), 2, 200)
		for k in n:
			var t := float(k) / n
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(points[points.size() - 1])
	return out
