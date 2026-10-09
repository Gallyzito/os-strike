class_name SliderBody
extends CanvasGroup
## Corpo de um slider. Desenha-se opaco (borda + interior com degradé, sem
## partes sobrepostas a ficar mais escuras) e o CanvasGroup aplica a
## transparência ao corpo inteiro de uma vez, como no osu!.

var _drawer := Node2D.new()
var _pts := PackedVector2Array()
var _radius := 10.0
var _border := Color.WHITE
var _track := Color.BLACK


func _init() -> void:
	add_child(_drawer)
	_drawer.draw.connect(_draw_body)
	fit_margin = 4.0
	clear_margin = 4.0


## `pts`: caminho em píxeis do ecrã; `alpha`: transparência do corpo todo.
func show_body(pts: PackedVector2Array, radius: float, border: Color, track: Color, alpha: float) -> void:
	_pts = pts
	_radius = radius
	_border = border
	_track = track
	self_modulate = Color(1, 1, 1, alpha)
	visible = true
	_drawer.queue_redraw()


func _draw_body() -> void:
	if _pts.size() < 2:
		if _pts.size() == 1:
			_drawer.draw_circle(_pts[0], _radius, _border)
		return
	# Camadas da borda para dentro: borda, depois o interior a clarear até ao centro.
	_layer(_radius, _border)
	var inner := _radius * 0.86
	var steps := 6
	for k in steps:
		var f := float(k) / steps
		var col := _track.darkened(0.25).lerp(_track.lightened(0.18), f)
		_layer(inner * (1.0 - f * 0.75), col)


func _layer(radius: float, col: Color) -> void:
	_drawer.draw_polyline(_pts, col, radius * 2.0, false)
	# Círculos ao longo do caminho tapam as juntas das curvas apertadas.
	var stride := maxi(1, int(radius * 0.35 / 3.0))
	for i in range(0, _pts.size(), stride):
		_drawer.draw_circle(_pts[i], radius, col)
	_drawer.draw_circle(_pts[_pts.size() - 1], radius, col)
