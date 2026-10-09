shader_type spatial;
// Cubos das palavras do menu. Por instância (INSTANCE_CUSTOM):
//   r = nível da música na coluna (0..1), g = flash de impacto, b = mira em cima.
// Arestas néon como o terreno, a cor vai de `low_color` (calmo) a `high_color` (forte).

uniform vec3 low_color : source_color = vec3(0.42, 0.62, 0.95);
uniform vec3 high_color : source_color = vec3(1.0, 0.62, 0.11);
uniform vec3 hot_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float glow = 2.2;

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	float level = custom.r;
	float flash = custom.g;
	float hover = custom.b;

	// O BoxMesh põe as 6 faces numa grelha 3x2 de UV: arestas com ~1 píxel.
	vec2 face_uv = UV * vec2(3.0, 2.0);
	vec2 f = fract(face_uv);
	vec2 d = min(f, 1.0 - f) / max(fwidth(face_uv), vec2(0.0001));
	float edge = 1.0 - clamp(min(d.x, d.y) - 0.5, 0.0, 1.0);

	vec3 heat = mix(low_color, high_color, smoothstep(0.15, 0.85, level));
	float body = 0.12 + level * 0.5 + hover * 0.35;
	float lines = edge * (0.6 + level * 1.4 + hover * 0.8);

	ALBEDO = vec3(0.03, 0.032, 0.04);
	METALLIC = 0.6;
	ROUGHNESS = 0.35;
	EMISSION = heat * (body + lines) * glow + hot_color * flash * 4.0;
}
