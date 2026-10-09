shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Clarão da boca do cano: estrela de 4/8 pontas, sempre virada para a câmara.

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float angle = 0.0;
uniform vec3 core_color : source_color = vec3(1.0, 0.95, 0.8);
uniform vec3 edge_color : source_color = vec3(1.0, 0.5, 0.1);

void vertex() {
	// Billboard: mantém a posição do nó mas vira o quad para a câmara.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x) + angle;
	float spikes = pow(abs(cos(a * 2.0)), 18.0) + 0.6 * pow(abs(cos(a * 4.0 + 0.4)), 30.0);
	float shape = smoothstep(1.0, 0.0, r / (0.25 + spikes * 0.75));
	float core = smoothstep(0.35, 0.0, r);
	vec3 col = mix(edge_color, core_color, core);
	ALBEDO = col * (shape + core) * flash * 6.0;
	ALPHA = clamp((shape + core) * flash, 0.0, 1.0);
}
