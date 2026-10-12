// Flat ground with grid lines, so movement is visible on an otherwise featureless plane.
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.42, 0.55, 0.36, 1.0);
uniform vec4 line_color : source_color = vec4(0.34, 0.45, 0.29, 1.0);
// Size of one grid cell in meters.
uniform float cell_size = 2.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = world_position.xz / cell_size;
	// Distance to the nearest grid line, measured in screen pixels (anti-aliased, constant width).
	vec2 grid = abs(fract(cell - 0.5) - 0.5) / fwidth(cell);
	float line = 1.0 - min(min(grid.x, grid.y), 1.0);
	ALBEDO = mix(base_color.rgb, line_color.rgb, line);
	ROUGHNESS = 1.0;
}
