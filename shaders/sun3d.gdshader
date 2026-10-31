shader_type spatial;
render_mode unshaded;
// Поверхность солнца: кипящие гранулы, к краю темнее. Ярче 1 — светится (glow окружения).

varying vec3 local_n;

void vertex() {
	local_n = VERTEX;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
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

void fragment() {
	vec3 b = normalize(local_n);
	float g = noise3(b * 9.0 + vec3(TIME * 0.15)) * 0.6 + noise3(b * 23.0 - vec3(TIME * 0.3)) * 0.4;
	float limb = pow(max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 0.45);
	vec3 hot = vec3(1.0, 0.93, 0.75) * 5.0;
	vec3 warm = vec3(1.0, 0.6, 0.25) * 2.5;
	ALBEDO = mix(warm, hot, limb * (0.6 + 0.4 * g));
}
