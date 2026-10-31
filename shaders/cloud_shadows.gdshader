shader_type canvas_item;
// Тени облаков: мягкие тёмные пятна медленно плывут над городом по ветру. strength — сила (ночью 0).

uniform float n = 64.0;          // клеток по стороне карты
uniform float strength = 0.22;
uniform vec2 wind = vec2(0.35, 0.12);  // клеток в секунду

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * noise(p);
		p = p * 2.03 + 11.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = (UV * n - wind * TIME) * 0.045;
	float c = smoothstep(0.52, 0.72, fbm(p) + 0.08 * sin(TIME * 0.05));
	COLOR = vec4(0.02, 0.03, 0.06, c * strength);
}
