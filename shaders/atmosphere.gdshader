shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled;
// Свечение атмосферы вокруг планеты: оболочка чуть больше шара. Яркость — по тому, как близко луч
// взгляда проходит к поверхности (у края планеты ярко, наружу гаснет), со стороны солнца ярче.

uniform vec3 sun = vec3(1.0, 0.0, 0.0);
uniform float planet_r = 1.0;
uniform float shell_r = 1.15;
uniform float glow = 0.0;

const vec3 ATMO = vec3(0.45, 0.68, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 dir = normalize(wpos - cam);
	vec3 closest = cam + dir * dot(center - cam, dir);
	float h = length(closest - center);
	float a = pow(clamp((shell_r - h) / (shell_r - planet_r), 0.0, 1.0), 2.4);
	float lit = smoothstep(-0.45, 0.5, dot(normalize(closest - center), normalize(sun)));
	ALBEDO = ATMO * a * (0.06 + 0.9 * lit) * (1.0 + glow);
}
