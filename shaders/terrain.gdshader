shader_type canvas_item;
// Земля карты без квадратов: у каждой клетки свой слой (трава, земля, песок, тропа, вода), а на стыках
// слои плавно перетекают друг в друга по неровной (шумной) границе. У воды песок темнеет (мокрый),
// по кромке — светлая пена; вода у берега светлее, вдали темнее, по ней бежит лёгкая рябь.

uniform sampler2D splat : filter_nearest;               // R*255 — слой клетки: 0..6 текстуры (под водой — песок)
uniform sampler2D water_mask : filter_linear;           // R — вода, размытая по соседям: берег — линия уровня 0.42
uniform sampler2D depth : filter_linear;                // R — глубина воды: 0 у берега .. 1 далеко
uniform sampler2DArray grounds : filter_linear_mipmap, repeat_enable;
uniform float n = 64.0;                                 // клеток по стороне карты

const vec3 SHALLOW = vec3(0.30, 0.43, 0.44);
const vec3 DEEP = vec3(0.13, 0.22, 0.29);

// хэш без sin: на больших координатах sin теряет точность, и шум становится «квадратным»
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

int layer_at(vec2 c) {
	ivec2 ic = ivec2(clamp(c, vec2(0.0), vec2(n - 1.0)));
	return int(texelFetch(splat, ic, 0).r * 255.0 + 0.5);
}

void fragment() {
	vec2 p = UV * n;  // в клетках
	// граница неровная: точку, по которой решаем «чья клетка», сдвигаем шумом двух масштабов
	vec2 wob = vec2(noise(p * 0.9), noise(p * 0.9 + 31.0)) - 0.5;
	wob += (vec2(noise(p * 3.1 + 7.0), noise(p * 3.1 + 53.0)) - 0.5) * 0.45;
	vec2 q = p + wob * 0.9;
	// 3x3 клетки вокруг: вес по расстоянию до центра клетки (круглые пятна, не квадраты),
	// у каждого слоя свой шум — края слоёв «зубчатые», песок крупинками заходит в траву
	vec2 b = floor(q);
	vec3 land = vec3(0.0);
	float lw = 0.0;
	for (int k = 0; k < 9; k++) {
		vec2 c = b + vec2(float(k % 3) - 1.0, float(k / 3) - 1.0);
		float dist = length(q - (c + 0.5));
		float w = smoothstep(1.3, 0.2, dist);
		if (w < 0.001) {
			continue;
		}
		int l = layer_at(c);
		w *= w * (0.55 + 0.9 * noise(p * 2.2 + float(l) * 13.7));
		land += texture(grounds, vec3(p, float(l))).rgb * w;
		lw += w;
	}
	land /= max(lw, 0.0001);
	// берег — линия уровня размытой маски воды: гладкая, без зубцов; лёгкий неподвижный изгиб шумом
	float field = texture(water_mask, UV).r + (noise(p * 0.8 + 5.0) - 0.5) * 0.08;
	const float LEVEL = 0.42;
	float aa = max(fwidth(field), 0.002);
	float shore = smoothstep(LEVEL - aa, LEVEL + aa, field);
	// мокрый песок у воды
	land *= 1.0 - 0.28 * smoothstep(LEVEL - 0.22, LEVEL, field);
	// вода: глубина плавно, рябь едва заметна
	float d = texture(depth, UV).r;
	vec3 water = mix(SHALLOW, DEEP, smoothstep(0.0, 1.0, d));
	float rip = noise(p * 1.4 + vec2(TIME * 0.2, TIME * 0.1)) * noise(p * 1.9 - vec2(TIME * 0.15, -TIME * 0.17));
	water += vec3(0.035, 0.04, 0.04) * smoothstep(0.3, 0.7, rip);
	// пена — тонкая светлая кайма сразу у берега
	float foam = (1.0 - smoothstep(0.0, 0.07, field - LEVEL)) * shore;
	water = mix(water, vec3(0.78, 0.84, 0.82), foam * (0.35 + 0.1 * sin(TIME * 1.3 + p.x * 0.7 + p.y * 0.5)));
	COLOR = vec4(mix(land, water, shore), 1.0);
}
