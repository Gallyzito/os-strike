shader_type spatial;
render_mode unshaded, cull_disabled;
// Grelha estilo sala de treino (Aim Lab). Desvanece com a distância à câmara.

uniform vec3 base_color : source_color = vec3(0.02, 0.022, 0.035);
uniform vec3 line_color : source_color = vec3(0.35, 0.2, 0.5);
uniform vec2 cells = vec2(40.0, 40.0);
uniform float scroll = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float fade_near = 4.0;
uniform float fade_far = 38.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 coord = UV * cells + vec2(0.0, scroll);
	vec2 g = abs(fract(coord - 0.5) - 0.5) / fwidth(coord);
	float line = 1.0 - min(min(g.x, g.y), 1.0);

	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_near, fade_far, dist);

	vec3 col = base_color + line_color * line * fade * (1.0 + pulse * 1.6);
	ALBEDO = col;
}
