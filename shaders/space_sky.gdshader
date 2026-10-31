shader_type sky;
// Небо космоса: россыпь звёзд (одни крупнее, другие тусклые), бледная туманность и свет со стороны солнца.

uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// звёзды одного слоя: в каждой клетке сетки — может быть одна звезда
float stars(vec3 d, float scale, float chance) {
	vec3 q = d * scale;
	vec3 c = floor(q);
	float h = hash3(c);
	if (h < chance) {
		return 0.0;
	}
	vec3 off = vec3(hash3(c + 3.1), hash3(c + 7.7), hash3(c + 11.3)) * 0.6 + 0.2;
	float dist = length(fract(q) - off);
	return smoothstep(0.12, 0.0, dist) * (0.3 + 0.7 * hash3(c + 1.9));
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = vec3(0.01, 0.012, 0.02);
	} else {
		vec3 d = EYEDIR;
		vec3 col = vec3(0.006, 0.008, 0.016);
		// туманность: еле заметные облака цвета
		float neb = noise3(d * 2.2) * 0.6 + noise3(d * 5.1) * 0.4;
		col += mix(vec3(0.05, 0.02, 0.08), vec3(0.01, 0.04, 0.08), noise3(d * 1.3 + 4.0)) * smoothstep(0.45, 0.85, neb) * 0.6;
		col += vec3(0.85, 0.9, 1.0) * stars(d, 260.0, 0.93) * 0.7;
		col += vec3(1.0, 0.95, 0.85) * stars(d, 90.0, 0.975) * 1.4;
		// свет солнца разлит по небу вокруг него
		float s = max(dot(d, normalize(sun_dir)), 0.0);
		col += vec3(1.0, 0.85, 0.6) * (pow(s, 12.0) * 0.12 + pow(s, 3.0) * 0.02);
		COLOR = col;
	}
}
