shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Сияние вокруг солнца: квадрат всегда лицом к камере, мягкий свет и медленные лучи.
// Планеты перед солнцем его закрывают (проверка глубины включена).

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float core = exp(-r * 30.0) * 3.0;
	float halo = exp(-r * 9.0) * 0.9 + exp(-r * 3.5) * 0.12;
	float rays = (0.5 + 0.5 * sin(a * 9.0 + TIME * 0.05) * sin(a * 5.0 - TIME * 0.08)) * exp(-r * 12.0) * 0.6;
	float fade = 1.0 - smoothstep(0.75, 1.0, r);
	ALBEDO = vec3(1.0, 0.86, 0.6) * (core + halo + rays) * fade;
}
