shader_type spatial;
// Ecrã curvo: mostra o osu! (textura do SubViewport) com um pouco de brilho,
// linhas de varrimento muito suaves e as bordas a escurecer.
// `glitch` (0..1): o ecrã a avariar (faixas deslocadas, cores separadas, estática).
// `crack` (0..1): rachas a brilhar que crescem a partir de `impact` (UV).
render_mode unshaded, cull_disabled;

uniform sampler2D screen_texture : source_color, filter_linear;
uniform float brightness = 1.05;
uniform float glitch = 0.0;
uniform float crack = 0.0;
uniform vec2 impact = vec2(0.5, 0.5);
uniform vec3 crack_color : source_color = vec3(1.0, 0.55, 0.25);

float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distância à aresta mais próxima de um padrão de Voronoi (vidro partido).
float voronoi_edge(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
			}
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return md;
}

void fragment() {
	vec2 uv = UV;
	float t = floor(TIME * 18.0);
	// Faixas horizontais que saltam para o lado.
	float band = floor(uv.y * 36.0);
	float r = hash1(band * 3.7 + t * 1.3);
	uv.x += (r - 0.5) * 0.12 * glitch * step(1.0 - glitch * 0.55, r);
	// Saltos verticais de vez em quando.
	uv.y += (hash1(t * 0.7) - 0.5) * 0.04 * glitch * step(0.82, hash1(t * 1.9));
	// Cores separadas.
	float split = 0.012 * glitch;
	vec3 c;
	c.r = texture(screen_texture, uv + vec2(split, 0.0)).r;
	c.g = texture(screen_texture, uv).g;
	c.b = texture(screen_texture, uv - vec2(split, split * 0.5)).b;
	c *= brightness;
	// Estática e um tom vermelho de alarme.
	float noise = hash1(dot(floor(UV * vec2(480.0, 270.0)), vec2(1.0, 57.0)) + t);
	c = mix(c, vec3(noise), glitch * 0.1 * step(0.6, hash1(band + t)));
	c *= mix(vec3(1.0), vec3(1.35, 0.55, 0.6), glitch * 0.55);
	float scan = 0.97 + 0.03 * sin(UV.y * 1080.0 * 3.14159);
	scan -= glitch * 0.25 * step(0.5, fract(UV.y * 135.0 + TIME * 6.0));
	vec2 edge = min(UV, 1.0 - UV);
	float vignette = smoothstep(0.0, 0.035, edge.x) * smoothstep(0.0, 0.06, edge.y);
	c *= scan * mix(0.55, 1.0, vignette);
	// Rachas.
	if (crack > 0.0) {
		vec2 p = (UV - impact) * vec2(16.0 / 9.0, 1.0);
		float dist = length(p);
		float e = voronoi_edge(p * 4.0 + vec2(3.1, 1.7));
		float radial = abs(sin(atan(p.y, p.x) * 9.0 + hash1(floor(atan(p.y, p.x) * 1.43)) * 2.0));
		float line = 1.0 - smoothstep(0.0, 0.025, e);
		line = max(line, (1.0 - smoothstep(0.0, 0.06, radial)) * step(dist, 0.6));
		float reach = crack * 1.9;
		float shown = 1.0 - smoothstep(reach - 0.08, reach, dist);
		float pulse = 0.75 + 0.25 * sin(TIME * 40.0);
		c = mix(c, crack_color * 3.0 * pulse, line * shown);
		// Escurece o vidro perto do impacto.
		c *= 1.0 - 0.35 * crack * (1.0 - smoothstep(0.0, 0.35, dist));
	}
	ALBEDO = c;
}
