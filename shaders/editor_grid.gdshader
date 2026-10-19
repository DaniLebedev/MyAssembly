shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Шаг сетки в метрах и частота «крупных» линий (в клетках).
uniform float cell_size = 0.5;
uniform float major_every = 10.0;
uniform vec4 minor_color : source_color = vec4(0.47, 0.56, 0.68, 0.1);
uniform vec4 major_color : source_color = vec4(0.62, 0.72, 0.86, 0.26);
uniform float fade_start = 40.0;
uniform float fade_end = 110.0;

varying vec3 world_position;

float line_mask(vec2 coord, float width) {
	vec2 grid = abs(fract(coord - 0.5) - 0.5) / max(fwidth(coord), vec2(0.00001));
	return 1.0 - clamp(min(grid.x, grid.y) / width, 0.0, 1.0);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 minor_uv = world_position.xz / cell_size;
	vec2 major_uv = world_position.xz / (cell_size * major_every);

	float minor = line_mask(minor_uv, 1.0);
	float major = line_mask(major_uv, 1.15);

	vec3 color = mix(minor_color.rgb, major_color.rgb, major);
	float alpha = max(minor_color.a * minor, major_color.a * major);

	float distance_to_camera = distance(world_position, CAMERA_POSITION_WORLD);
	float minor_fade = 1.0 - smoothstep(10.0, 38.0, distance_to_camera);
	float major_fade = 1.0 - smoothstep(fade_start, fade_end, distance_to_camera);
	alpha = max(
		minor_color.a * minor * minor_fade,
		major_color.a * major * major_fade
	);

	ALBEDO = color;
	ALPHA = alpha;
}
