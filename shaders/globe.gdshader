shader_type spatial;
render_mode unshaded, cull_back;
// Планета в 3D: развёртка (PlanetTexture) по точке шара, свет от далёкого солнца (sun — направление
// в мире), огни городов на ночной стороне, облака, блик на воде, кайма атмосферы по краю.

uniform sampler2D albedo_tex : source_color, filter_linear, repeat_enable;
uniform vec3 sun = vec3(1.0, 0.0, 0.0);  // на солнце, мировые координаты
uniform float clouds = 0.0;  // поворот облаков, рад
uniform float glow = 0.0;    // 0..1 — подсветка (наведение, выбор)
uniform float seed = 0.0;    // свой рисунок облаков и огней
// города при выборе: xyz — точка на шаре (координаты планеты), w — угловой радиус очертаний
uniform vec4 sites[32];
uniform int site_count = 0;
uniform int site_hover = -1;
uniform float sites_on = 0.0;  // 0..1 — очертания проявляются

const vec3 ATMO = vec3(0.45, 0.68, 1.0);
const vec3 NIGHT = vec3(0.04, 0.05, 0.12);
const vec3 CITY = vec3(1.0, 0.7, 0.3);

varying vec3 local_n;  // точка шара в координатах планеты

void vertex() {
	local_n = VERTEX;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3) + seed);
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

float fbm(vec3 x) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) {
		v += a * noise3(x);
		x *= 2.03;
		a *= 0.5;
	}
	return v;
}

vec3 spin(vec3 b, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(b.x * c - b.z * s, b.y, b.x * s + b.z * c);
}

void fragment() {
	vec3 b = normalize(local_n);
	float lon = atan(b.z, b.x);
	float lat = asin(clamp(b.y, -1.0, 1.0));
	vec2 uv = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
	// 5 выборок вокруг точки — берег без «лесенки» от пикселей развёртки
	vec2 px = 0.6 / vec2(textureSize(albedo_tex, 0));
	vec3 albedo = (texture(albedo_tex, uv).rgb * 2.0 + texture(albedo_tex, uv + vec2(px.x, 0.0)).rgb
		+ texture(albedo_tex, uv - vec2(px.x, 0.0)).rgb + texture(albedo_tex, uv + vec2(0.0, px.y)).rgb
		+ texture(albedo_tex, uv - vec2(0.0, px.y)).rgb) / 6.0;

	vec3 n = normalize(NORMAL);
	vec3 V = normalize(VIEW);
	vec3 L = normalize((VIEW_MATRIX * vec4(sun, 0.0)).xyz);
	float d = dot(n, L);
	float day = smoothstep(-0.2, 0.3, d);  // мягкая граница дня и ночи
	bool water = albedo.b > albedo.r * 1.15 && albedo.b > albedo.g * 0.95;
	vec3 lit = albedo * (0.25 + 1.0 * max(d, 0.0));
	if (water) {
		vec3 h = normalize(L + V);
		lit += vec3(1.0, 0.9, 0.7) * pow(max(dot(n, h), 0.0), 80.0) * 0.8;
	}
	vec3 dark = albedo * 0.012 + NIGHT * 0.04;  // цвета линейные: ночь должна быть почти чёрной
	// огни городов: мерцают на суше ночной стороны
	vec3 q = b * 44.0;
	float town = step(0.86, hash3(floor(q))) * step(0.45, fbm(b * 3.0));
	float twinkle = 0.75 + 0.25 * sin(TIME * 3.0 + hash3(floor(q) + 7.0) * 40.0);
	if (!water) {
		dark += CITY * town * twinkle * (1.0 - smoothstep(0.0, 0.5, length(fract(q) - 0.5) * 2.0)) * 1.4;
	}
	vec3 c = mix(dark, lit, day);
	// облака крутятся сами по себе; ночью — тёмные
	float cl = smoothstep(0.52, 0.78, fbm(spin(b, -clouds) * 2.6 + vec3(seed * 9.0)));
	c = mix(c, vec3(1.0) * mix(0.004, 0.9, day), cl * 0.75);
	// города: неровные очертания, внутри — крыши кварталов; наведённый — ярче
	if (sites_on > 0.001) {
		for (int i = 0; i < site_count; i++) {
			vec3 s = sites[i].xyz;
			float ang = length(b - s);
			float rr = sites[i].w * (1.0 + (noise3(b * 40.0 + float(i) * 7.3) - 0.5) * 0.55);
			if (ang > rr * 1.6) {
				continue;
			}
			bool hot = i == site_hover;
			float px = fwidth(ang) * 1.2;
			float line = 1.0 - smoothstep(px * 0.4, px * 1.6, abs(ang - rr));
			float inside = 1.0 - smoothstep(rr - px, rr, ang);
			vec3 q2 = b * 420.0;
			float roof = step(0.55, hash3(floor(q2))) * step(length(fract(q2) - 0.5), 0.38);
			vec3 roofs = mix(vec3(0.42, 0.3, 0.2), vec3(0.7, 0.42, 0.28), hash3(floor(q2) + 3.0)) * mix(0.08, 1.0, day);
			c = mix(c, roofs, inside * roof * sites_on * 0.85);
			c = mix(c, c + vec3(1.0, 0.8, 0.35) * 0.12, inside * sites_on * (hot ? 1.0 : 0.4));
			vec3 lc = hot ? vec3(1.6, 1.25, 0.5) : vec3(1.0, 0.86, 0.55);
			c = mix(c, lc, line * sites_on * (hot ? 1.0 : 0.8));
		}
	}
	// кайма атмосферы по краю шара, ярче на дневной стороне
	float rim = pow(1.0 - max(dot(n, V), 0.0), 2.5);
	c += ATMO * rim * mix(0.05, 0.8, smoothstep(-0.3, 0.6, d)) * (1.0 + glow * 0.8);
	ALBEDO = c;
}
