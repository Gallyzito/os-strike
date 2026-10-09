shader_type canvas_item;
// Vinheta + grão de filme por cima da cena 3D.

uniform float vignette : hint_range(0.0, 1.0) = 0.65;
uniform float grain : hint_range(0.0, 0.2) = 0.05;
uniform float scanlines : hint_range(0.0, 0.2) = 0.035;

void fragment() {
	vec2 uv = UV - 0.5;
	float v = smoothstep(0.25, 0.85, length(uv * vec2(1.0, 1.25)));
	float noise = fract(sin(dot(UV * 917.0 + fract(TIME * 7.13), vec2(12.9898, 78.233))) * 43758.5453);
	float lines = step(0.5, fract(FRAGCOORD.y * 0.5)) * scanlines;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(v * vignette + noise * grain + lines, 0.0, 1.0));
}
