shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Faíscas e partículas aditivas. A cor vem da rampa do material de partículas.

uniform float intensity = 4.0;

void fragment() {
	ALBEDO = COLOR.rgb * intensity;
	ALPHA = COLOR.a;
}
