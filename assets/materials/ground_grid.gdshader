// Ground with grid lines that match the airport grid, tinted by zone (landside / airside)
// and showing walkway floor and taxiways.
// Cell size, origin, map size and the flag map are set by ground.gd.
//
// One mesh, one draw call. Everything about a cell comes from ONE texture, the flag layer of the
// AirportGrid (see scenes/ground/ground_flag_texture.gd). Later ground materials (grass base,
// asphalt on taxiways, concrete on stands, markings atlas: assets/materials/,
// art/ground/markings_atlas.md) are added in fragment() by reading the same flags, see the HOOKs.
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.42, 0.55, 0.36, 1.0);
uniform vec4 line_color : source_color = vec4(0.34, 0.45, 0.29, 1.0);
uniform vec4 airside_color : source_color = vec4(0.5, 0.53, 0.57, 1.0);
uniform vec4 airside_line_color : source_color = vec4(0.42, 0.45, 0.49, 1.0);
uniform vec4 landside_floor_color : source_color = vec4(0.84, 0.81, 0.74, 1.0);
uniform vec4 airside_floor_color : source_color = vec4(0.78, 0.8, 0.83, 1.0);
uniform vec4 floor_line_color : source_color = vec4(0.68, 0.66, 0.62, 1.0);
uniform vec4 taxiway_color : source_color = vec4(0.2, 0.21, 0.23, 1.0);
uniform vec4 taxiway_line_color : source_color = vec4(0.9, 0.75, 0.15, 1.0);
// Size of one grid cell in meters.
uniform float cell_size = 2.0;
// World XZ position of the map corner where cell (0, 0) starts.
uniform vec2 grid_origin = vec2(0.0);
// Map size in meters.
uniform vec2 map_size = vec2(128.0);
// R8, one texel per cell: the cell's flag byte of AirportGrid (value / 255 when sampled).
//   bits 0-2 (0x07): zone, 0 = landside, 1 = airside     bit 3 (0x08): walkway
//   bit 4 (0x10): taxiway                                bit 5 (0x20): owned (not filled yet)
// Keep these in step with AirportGrid.ZONE_MASK / WALKWAY_BIT / TAXIWAY_BIT / OWNED_BIT.
// "filter_nearest" keeps cell edges sharp.
uniform sampler2D flag_map : filter_nearest, repeat_disable;
// Land the airport owns (world XZ: min x, min z, max x, max z). Outside it is shaded darker
// (design doc §14.1).
uniform vec4 owned_rect = vec4(-1.0e6, -1.0e6, 1.0e6, 1.0e6);
uniform float not_owned_brightness = 0.6;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 local = world_position.xz - grid_origin;
	// Decode the flag byte (the texel is byte / 255).
	int flags = int(texture(flag_map, local / map_size).r * 255.0 + 0.5);
	float airside = (flags & 0x07) == 1 ? 1.0 : 0.0;
	float walkway = (flags & 0x08) != 0 ? 1.0 : 0.0;
	float taxiway = (flags & 0x10) != 0 ? 1.0 : 0.0;
	// HOOK: more bits (stand, markings) are read from `flags` here, and the material textures
	// (grass, asphalt, concrete) are sampled with `cell` below, mixed by these masks.

	vec2 cell = local / cell_size;
	// Distance to the nearest grid line, measured in screen pixels (anti-aliased, constant width).
	vec2 grid = abs(fract(cell - 0.5) - 0.5) / fwidth(cell);
	float line = 1.0 - min(min(grid.x, grid.y), 1.0);

	// HOOK base: the grass material replaces base_color here.
	vec3 ground = mix(base_color.rgb, airside_color.rgb, airside);
	vec3 lines = mix(line_color.rgb, airside_line_color.rgb, airside);
	ground = mix(ground, mix(landside_floor_color.rgb, airside_floor_color.rgb, airside), walkway);
	lines = mix(lines, floor_line_color.rgb, walkway);
	vec3 color = mix(ground, lines, line);
	// HOOK taxiway / stand: asphalt and concrete materials, and the markings atlas, go in this block.
	if (taxiway > 0.5) {
		// Asphalt with a yellow dot in the middle of each cell: together they read as a centre line.
		vec2 in_cell = fract(cell) - 0.5;
		float dot_mark = 1.0 - smoothstep(0.08, 0.12, length(in_cell));
		color = mix(taxiway_color.rgb, taxiway_line_color.rgb, dot_mark);
	}
	// Unowned land. HOOK: once the owned bit (0x20) is filled in the grid, read it from `flags` here
	// instead of the rectangle.
	bool owned = world_position.x >= owned_rect.x && world_position.z >= owned_rect.y
		&& world_position.x <= owned_rect.z && world_position.z <= owned_rect.w;
	if (!owned) {
		float gray = dot(color, vec3(0.3, 0.59, 0.11));
		color = mix(color, vec3(gray), 0.5) * not_owned_brightness;
	}
	ALBEDO = color;
	ROUGHNESS = 1.0;
}
