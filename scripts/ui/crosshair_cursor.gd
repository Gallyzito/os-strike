class_name CrosshairCursor
extends Control
## Mira do CS, configurável nas Opções (separador MIRA). Fica no centro do ecrã
## quando o rato está capturado (a jogar) e segue o rato nos menus, onde o
## cursor do sistema está escondido.
##
## É desenhada em píxeis reais do ecrã, alinhada à grelha de píxeis: assim fica
## sempre nítida e completa, mesmo em 4:3 esticado (onde a interface é esticada
## de forma desigual) e com espessuras finas.

## Os tamanhos da mira estão em "píxeis a 720p" e escalam com a altura do ecrã.
const REFERENCE_HEIGHT := 720.0

var _kick := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Abre a mira (ao disparar), se a mira dinâmica estiver ligada.
func kick() -> void:
	if Settings.get_value("crosshair/dynamic"):
		_kick = 1.0


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		kick()


func _process(delta: float) -> void:
	_kick = move_toward(_kick, 0.0, delta * 8.0)
	var to_screen := _canvas_to_screen()
	# A camada desfaz o esticar da janela: desenhamos em píxeis do ecrã.
	var layer := get_parent() as CanvasLayer
	if layer:
		layer.transform = to_screen.affine_inverse()
	var physical := Vector2(get_tree().root.size)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		position = (physical * 0.5).floor()
	else:
		position = (to_screen * get_viewport().get_mouse_position()).floor()
	queue_redraw()


func _draw() -> void:
	var px_scale := get_tree().root.size.y / REFERENCE_HEIGHT
	# Em 4:3 (ou outra proporção) esticado, a mira estica com a imagem, como no CS.
	var t := _canvas_to_screen()
	var stretch := t.x.x / t.y.y if t.y.y > 0.0 else 1.0
	draw_crosshair(self, Vector2.ZERO, _kick, px_scale, stretch)


## Transformação das coordenadas da interface (lógicas) para píxeis do ecrã,
## conforme o modo de esticar da janela.
func _canvas_to_screen() -> Transform2D:
	var root := get_tree().root
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(root.size)
	if logical.x <= 0.0 or logical.y <= 0.0:
		return Transform2D.IDENTITY
	var s := physical / logical
	if root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_IGNORE:
		return Transform2D(0.0, s, 0.0, Vector2.ZERO)
	var k := minf(s.x, s.y)
	return Transform2D(0.0, Vector2(k, k), 0.0, (physical - logical * k) * 0.5)


## Desenha a mira com as definições atuais, em píxeis inteiros.
## `kick` (0..1) abre a mira ao disparar; `px_scale` converte as unidades
## das definições (píxeis a 720p) em píxeis reais.
## `x_stretch`: alarga tudo na horizontal (resolução esticada).
static func draw_crosshair(canvas: CanvasItem, center: Vector2, kick := 0.0, px_scale := 1.0, x_stretch := 1.0) -> void:
	var color: Color = Settings.get_value("crosshair/color")
	color.a = Settings.get_value("crosshair/alpha")
	var t := maxf(1.0, roundf(float(Settings.get_value("crosshair/thickness")) * px_scale))
	var length := roundf(float(Settings.get_value("crosshair/length")) * px_scale)
	var gap := roundf((float(Settings.get_value("crosshair/gap")) + kick * 4.0) * px_scale)
	var outline := 0.0
	if Settings.get_value("crosshair/outline"):
		outline = maxf(1.0, roundf(float(Settings.get_value("crosshair/outline_thickness")) * px_scale))
	var outline_color := Color(0, 0, 0, 0.8 * color.a)

	# O "píxel central" começa em c; braços com espessura par ou ímpar ficam centrados.
	# Medidas na horizontal (esticadas) e na vertical.
	var tx := maxf(1.0, roundf(t * x_stretch))
	var length_x := roundf(length * x_stretch)
	var gap_x := roundf(gap * x_stretch)
	var c := center.floor()
	var x0 := c.x - floorf(tx * 0.5)
	var y0 := c.y - floorf(t * 0.5)
	var rects: Array[Rect2] = []
	if length > 0.0:
		rects.append(Rect2(x0, y0 - gap - length, tx, length))         # cima
		rects.append(Rect2(x0, y0 + t + gap, tx, length))              # baixo
		rects.append(Rect2(x0 - gap_x - length_x, y0, length_x, t))    # esquerda
		rects.append(Rect2(x0 + tx + gap_x, y0, length_x, t))          # direita
	if Settings.get_value("crosshair/dot"):
		rects.append(Rect2(x0, y0, tx, t))

	if outline > 0.0:
		for r in rects:
			var ox := maxf(1.0, roundf(outline * x_stretch))
			canvas.draw_rect(r.grow_individual(ox, outline, ox, outline), outline_color)
	for r in rects:
		canvas.draw_rect(r, color)
