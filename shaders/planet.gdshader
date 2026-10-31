shader_type canvas_item;
// Шар планеты: развёртка (TEXTURE) натягивается на сферу, свет от солнца слева.
// Свет считается по нормали до поворота, поэтому день всегда со стороны солнца.

uniform float rot = 0.0;   // поворот вокруг оси, рад
uniform float tilt = 0.0;  // наклон к зрителю, рад
uniform vec3 sun = vec3(-1.0, 0.15, 0.3);  // на солнце: x вправо, y вверх, z к зрителю
uniform float edge = 0.9;  // радиус шара в долях половины квадрата
uniform float clouds = 0.0;  // поворот облаков (крутятся быстрее планеты), рад
uniform float glow = 0.0;    // 0..1 — подсветка атмосферы (наведение, выбор)
uniform float seed = 0.0;    // свой рисунок облаков и огней у каждой планеты

const vec3 ATMO = vec3(0.55, 0.75, 1.0);
const vec3 NIGHT = vec3(0.08, 0.10, 0.22);  // слабый синеватый свет ночной стороны
const vec3 CITY = vec3(1.0, 0.78, 0.4);     // огни городов на ночной стороне

varying vec4 tint;  // modulate (затемнение при приближении)

void vertex() {
	tint = COLOR;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3) + seed);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// шум по точке на сфере — без шва на линии смены даты
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
	for (int k = 0; k < 4; k++) {
		v += a * noise3(x);
		x *= 2.03;
		a *= 0.5;
	}
	return v;
}

// точка шара в координатах планеты, повёрнутая на угол a вокруг оси
vec3 spin(vec3 b, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(b.x * c - b.z * s, b.y, b.x * s + b.z * c);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) / edge;
	float r = length(p);
	vec3 L = normalize(sun);

	// атмосфера вокруг шара, ярче со стороны солнца
	float side = smoothstep(-0.6, 0.8, dot(normalize(vec2(p.x, -p.y) + 1e-5), normalize(L.xy)));
	float halo = pow(clamp(1.0 - (r - 1.0) / (0.09 + 0.05 * glow), 0.0, 1.0), 2.0) * (mix(0.1, 0.7, side) + 0.5 * glow);
	vec4 col = vec4(ATMO + vec3(0.2, 0.15, 0.0) * glow, halo);

	if (r < 1.0) {
		vec3 n = vec3(p.x, -p.y, sqrt(1.0 - r * r));
		// нормаль в координатах планеты: снять наклон, потом поворот
		float ct = cos(tilt);
		float st = sin(tilt);
		vec3 b = vec3(n.x, n.y * ct + n.z * st, -n.y * st + n.z * ct);
		float lon = atan(b.z, b.x) - rot;
		float lat = asin(clamp(b.y, -1.0, 1.0));
		// 5 выборок вокруг точки — берег без «лесенки» от пикселей развёртки
		vec2 uv = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
		vec2 px = 0.6 / vec2(textureSize(TEXTURE, 0));
		vec3 albedo = (texture(TEXTURE, uv).rgb * 2.0 + texture(TEXTURE, uv + vec2(px.x, 0.0)).rgb
			+ texture(TEXTURE, uv - vec2(px.x, 0.0)).rgb + texture(TEXTURE, uv + vec2(0.0, px.y)).rgb
			+ texture(TEXTURE, uv - vec2(0.0, px.y)).rgb) / 6.0;

		float d = dot(n, L);
		float day = smoothstep(-0.15, 0.35, d);  // мягкая граница дня и ночи
		bool water = albedo.b > albedo.r * 1.15 && albedo.b > albedo.g * 0.95;
		vec3 lit = albedo * (0.45 + 0.75 * max(d, 0.0));
		// солнечный блик на воде
		if (water) {
			vec3 h = normalize(L + vec3(0.0, 0.0, 1.0));
			lit += vec3(1.0, 0.95, 0.8) * pow(max(dot(n, h), 0.0), 60.0) * 0.6;
		}
		vec3 dark = albedo * 0.12 + NIGHT * 0.25;
		// огни городов ночью: мерцающие точки на суше
		vec3 ground = spin(b, -rot);  // точка поверхности (крутится вместе с сушей)
		vec3 q = ground * 38.0;
		float town = step(0.86, hash3(floor(q))) * step(0.45, fbm(ground * 3.0));
		float twinkle = 0.75 + 0.25 * sin(TIME * 3.0 + hash3(floor(q) + 7.0) * 40.0);
		if (!water) {
			dark += CITY * town * twinkle * (1.0 - smoothstep(0.0, 0.5, length(fract(q) - 0.5) * 2.0)) * 0.9;
		}
		vec3 c = mix(dark, lit, day);
		// облака: свой шум, крутятся быстрее суши; тень облаков темнее ночью
		float cl = smoothstep(0.52, 0.78, fbm(spin(b, -rot - clouds) * 2.6 + vec3(seed * 9.0)));
		c = mix(c, vec3(1.0) * mix(0.1, 0.95, day) + ATMO * 0.05, cl * 0.75);
		// кайма атмосферы по краю шара, ярче на дневной стороне
		c += ATMO * pow(1.0 - n.z, 2.5) * mix(0.08, 0.7, smoothstep(-0.3, 0.6, d));

		float inside = 1.0 - smoothstep(1.0 - fwidth(r), 1.0, r);
		col = mix(col, vec4(c, 1.0), inside);
	}
	COLOR = col * tint;
}
