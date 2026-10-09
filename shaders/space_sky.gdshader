shader_type sky;
// Espaço escuro: estrelas em três camadas (umas a cintilar) e uma nebulosa
// azul/roxa suave, como o fundo de uma skin do osu!.

uniform vec3 deep_color : source_color = vec3(0.012, 0.018, 0.035);
uniform vec3 nebula_a : source_color = vec3(0.08, 0.16, 0.32);
uniform vec3 nebula_b : source_color = vec3(0.22, 0.08, 0.3);
uniform float star_density = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}

float stars(vec3 dir, float scale, float threshold, float twinkle) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float h = hash(cell);
	if (h < threshold) {
		return 0.0;
	}
	vec3 center = cell + vec3(hash(cell + 1.3), hash(cell + 2.7), hash(cell + 4.1));
	float d = length(p - center);
	float s = smoothstep(0.12, 0.0, d);
	float tw = 0.65 + 0.35 * sin(TIME * (1.5 + h * 3.0) + h * 40.0) * twinkle;
	return s * tw * (h - threshold) / (1.0 - threshold);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float n = fbm(dir * 2.2 + vec3(0.0, 0.0, TIME * 0.004));
	float n2 = fbm(dir * 4.5 + vec3(7.1, 3.3, 1.2));
	vec3 col = deep_color;
	col += nebula_a * smoothstep(0.42, 0.85, n) * 0.9;
	col += nebula_b * smoothstep(0.5, 0.9, n2) * 0.7;
	float s = stars(dir, 140.0, 0.93 / star_density, 1.0) * 1.6;
	s += stars(dir, 300.0, 0.95 / star_density, 0.6);
	s += stars(dir, 60.0, 0.985, 0.3) * 3.0;
	col += vec3(0.85, 0.9, 1.0) * s;
	COLOR = col;
}
