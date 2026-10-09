shader_type spatial;
// Terreno de colunas: cada linha é um instante do espectro da música e as
// linhas antigas afastam-se para o fundo (espectrograma 3D).
// Colunas escuras com arestas néon: baixas em azul CT, altas em laranja T.

uniform sampler2D heights : filter_nearest, repeat_disable;
uniform int cols = 48;
uniform int rows = 56;
uniform int head = 0;
uniform float max_height = 3.0;
uniform vec3 metal_color : source_color = vec3(0.025, 0.028, 0.035);
uniform vec3 low_color : source_color = vec3(0.42, 0.62, 0.95);
uniform vec3 high_color : source_color = vec3(1.0, 0.62, 0.11);
uniform float glow = 2.2;

varying float v_height;
varying float v_y;
varying float v_row;

void vertex() {
	int col = INSTANCE_ID % cols;
	int row = INSTANCE_ID / cols;
	int tex_row = (head - row + rows) % rows;
	float h = texelFetch(heights, ivec2(col, tex_row), 0).r;

	v_height = clamp(h, 0.0, 1.5);
	v_row = float(row) / float(rows - 1);
	v_y = VERTEX.y + 0.5;
	VERTEX.y = v_y * (0.03 + h * max_height);
}

void fragment() {
	float fade = pow(1.0 - v_row, 1.6);
	vec3 heat = mix(low_color, high_color, smoothstep(0.3, 0.85, v_height));

	// O BoxMesh põe as 6 faces numa grelha 3x2 de UV: recuperamos o UV da face
	// para desenhar as arestas com ~1 píxel de espessura.
	vec2 face_uv = UV * vec2(3.0, 2.0);
	vec2 f = fract(face_uv);
	vec2 d = min(f, 1.0 - f) / max(fwidth(face_uv), vec2(0.0001));
	float edge = 1.0 - clamp(min(d.x, d.y) - 0.5, 0.0, 1.0);

	float cap = smoothstep(0.96, 1.0, v_y);
	float rise = pow(v_y, 6.0) * v_height;

	ALBEDO = metal_color;
	METALLIC = 0.6;
	ROUGHNESS = 0.4;
	EMISSION = heat * glow * fade * (edge * (0.25 + v_height * 1.4) + cap * v_height * 0.6 + rise * 0.25);
}
