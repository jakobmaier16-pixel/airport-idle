// The ground of the whole map: one mesh, one draw call. Material look: grass base, concrete under
// stands, asphalt under runways and on taxiways, paving on walkways, markings painted from the
// markings atlas (art/ground/markings_atlas.md). Zone colours and the cell grid are an overlay that the
// build view switches on (ground.gd).
//
// Everything about a cell comes from ONE texture, the flag layer of the AirportGrid (see
// scenes/ground/ground_flag_texture.gd); neighbour cells are read with texelFetch, so no extra
// data is needed (taxiway centrelines and stand edges are derived from the neighbour bits).
// Per pixel: 1 flag fetch + 1 material sample (+ 1 atlas sample on a marking, + 4 neighbour fetches on
// taxiway / stand cells). Textures tile in world metres (1 cell = 2 m), albedo only (the ORM and normal
// maps of the .tres materials are for the 3D models; the ground is flat).
shader_type spatial;

// Material albedo (same files as assets/materials/*.tres) and how many metres one tile covers.
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paving_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Markings atlas, 1024 x 1024; only strips of it are used (rows given in pixels, y from the top).
uniform sampler2D markings_tex : source_color, filter_linear, repeat_enable;
uniform float grass_tile_m = 8.0;
uniform float asphalt_tile_m = 4.0;
uniform float concrete_tile_m = 5.0;
uniform float paving_tile_m = 2.0;
// Atlas rows (px) of the yellow_line and red_line strips.
uniform vec2 yellow_line_rows = vec2(236.0, 268.0);
uniform vec2 red_line_rows = vec2(272.0, 304.0);
// Line widths in metres: taxi centreline 0.3 m, stand boundary 0.2 m, inset from the stand edge.
uniform float taxi_line_width_m = 0.3;
uniform float stand_line_width_m = 0.2;
uniform float stand_line_inset_m = 0.8;

// Overlay (build view only, set by ground.gd): 1.0 = zone colours, 0.0 = off.
uniform float zone_overlay = 0.0;
// Grid lines over the cells (build view only).
uniform float show_grid = 0.0;
uniform vec4 landside_tint : source_color = vec4(0.35, 0.65, 0.35, 1.0);
uniform vec4 airside_tint : source_color = vec4(0.3, 0.5, 0.9, 1.0);
uniform float zone_tint_strength = 0.4;
uniform vec4 grid_line_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float grid_line_strength = 0.28;

// Size of one grid cell in meters.
uniform float cell_size = 2.0;
// World XZ position of the map corner where cell (0, 0) starts.
uniform vec2 grid_origin = vec2(0.0);
// Map size in meters.
uniform vec2 map_size = vec2(128.0);
// R8, one texel per cell: the cell's flag byte of AirportGrid.
//   bits 0-2 (0x07): zone, 0 = landside, 1 = airside     bit 3 (0x08): walkway
//   bit 4 (0x10): taxiway                                bit 5 (0x20): owned (unused)
//   bits 6-7 (0xC0): surface under a building, 1 = concrete (stand), 2 = runway asphalt
// Keep these in step with AirportGrid.ZONE_MASK / WALKWAY_BIT / TAXIWAY_BIT / OWNED_BIT / SURFACE_MASK.
uniform sampler2D flag_map : filter_nearest, repeat_disable;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

int flags_at(ivec2 cell, ivec2 limit) {
	// Outside the map counts as empty.
	if (cell.x < 0 || cell.y < 0 || cell.x >= limit.x || cell.y >= limit.y) {
		return 0;
	}
	return int(texelFetch(flag_map, cell, 0).r * 255.0 + 0.5);
}

// Paint coverage of a line `half_width` (cell units) from `dist`, anti-aliased over one pixel.
// `px` is the pixel size in cells. Thin lines are widened to stay about one pixel wide and fade out
// when far away, so nothing shimmers at full-map zoom.
float line_cover(float dist, float half_width, float px) {
	float hw = max(half_width, px * 0.75);
	float cover = clamp((hw - dist) / px + 0.5, 0.0, 1.0);
	return cover * (1.0 - smoothstep(0.35, 0.8, px));
}

void fragment() {
	vec2 world = world_position.xz;
	vec2 local = world - grid_origin;
	vec2 cell = local / cell_size;
	ivec2 limit = textureSize(flag_map, 0);
	ivec2 cell_i = ivec2(floor(cell));
	int flags = flags_at(cell_i, limit);
	bool airside = (flags & 0x07) == 1;
	bool walkway = (flags & 0x08) != 0;
	bool taxiway = (flags & 0x10) != 0;
	int surface = (flags >> 6) & 3;

	// Derivatives are taken here, in uniform control flow, and passed to textureGrad below: sampling
	// inside the branches with plain texture() would give wrong mip levels at their edges.
	vec2 dx = dFdx(world);
	vec2 dy = dFdy(world);
	vec2 cell_px = vec2(length(vec2(dx.x, dy.x)), length(vec2(dx.y, dy.y))) / cell_size;
	float px = max(cell_px.x, cell_px.y);

	vec3 color;
	if (taxiway || surface == 2) {
		color = textureGrad(asphalt_tex, world / asphalt_tile_m, dx / asphalt_tile_m, dy / asphalt_tile_m).rgb;
	} else if (surface == 1) {
		color = textureGrad(concrete_tex, world / concrete_tile_m, dx / concrete_tile_m, dy / concrete_tile_m).rgb;
	} else if (walkway) {
		color = textureGrad(paving_tex, world / paving_tile_m, dx / paving_tile_m, dy / paving_tile_m).rgb;
	} else {
		color = textureGrad(grass_tex, world / grass_tile_m, dx / grass_tile_m, dy / grass_tile_m).rgb;
	}

	vec2 in_cell = fract(cell) - 0.5;
	if (taxiway) {
		// Centreline, derived from the neighbouring taxiway cells: an arm from the cell centre to every
		// side that has a taxiway neighbour; a lone cell is a dot.
		bool east = (flags_at(cell_i + ivec2(1, 0), limit) & 0x10) != 0;
		bool west = (flags_at(cell_i + ivec2(-1, 0), limit) & 0x10) != 0;
		bool south = (flags_at(cell_i + ivec2(0, 1), limit) & 0x10) != 0;
		bool north = (flags_at(cell_i + ivec2(0, -1), limit) & 0x10) != 0;
		float dist = length(in_cell);
		if (in_cell.x > 0.0 ? east : west) {
			dist = min(dist, abs(in_cell.y));
		}
		if (in_cell.y > 0.0 ? south : north) {
			dist = min(dist, abs(in_cell.x));
		}
		float cover = line_cover(dist, taxi_line_width_m / cell_size * 0.5, px);
		if (cover > 0.0) {
			// The paint colour comes from the middle of the atlas strip (solid strips repeat along U).
			vec2 uv = vec2(0.5, mix(yellow_line_rows.x, yellow_line_rows.y, 0.5) / 1024.0);
			vec4 paint = textureLod(markings_tex, uv, 0.0);
			color = mix(color, paint.rgb, cover * paint.a);
		}
	} else if (surface == 1) {
		// Stand boundary: a red line inset from every side that borders a non-concrete cell.
		float dist = 1.0e3;
		if (((flags_at(cell_i + ivec2(-1, 0), limit) >> 6) & 3) != 1) { dist = min(dist, in_cell.x + 0.5); }
		if (((flags_at(cell_i + ivec2(1, 0), limit) >> 6) & 3) != 1) { dist = min(dist, 0.5 - in_cell.x); }
		if (((flags_at(cell_i + ivec2(0, -1), limit) >> 6) & 3) != 1) { dist = min(dist, in_cell.y + 0.5); }
		if (((flags_at(cell_i + ivec2(0, 1), limit) >> 6) & 3) != 1) { dist = min(dist, 0.5 - in_cell.y); }
		// The line sits `inset` cells inside the stand edge, kept within the edge cell (0.8 m = 0.4 cells).
		float inset = min(stand_line_inset_m / cell_size, 0.45);
		float cover = line_cover(abs(dist - inset), stand_line_width_m / cell_size * 0.5, px);
		if (dist < 1.0e2 && cover > 0.0) {
			vec2 uv = vec2(0.5, mix(red_line_rows.x, red_line_rows.y, 0.5) / 1024.0);
			vec4 paint = textureLod(markings_tex, uv, 0.0);
			color = mix(color, paint.rgb, cover * paint.a);
		}
	}

	// Build-view overlay: zone tint and cell grid.
	if (zone_overlay > 0.5) {
		color = mix(color, airside ? airside_tint.rgb : landside_tint.rgb, zone_tint_strength);
	}
	if (show_grid > 0.5) {
		// Distance to the nearest grid line, measured in screen pixels (anti-aliased, constant width);
		// faded out when a cell is only a few pixels wide.
		vec2 grid = abs(fract(cell - 0.5) - 0.5) / max(cell_px, vec2(1.0e-5));
		float line = (1.0 - min(min(grid.x, grid.y), 1.0)) * (1.0 - smoothstep(0.15, 0.4, px));
		color = mix(color, grid_line_color.rgb, line * grid_line_strength);
	}

	ALBEDO = color;
	ROUGHNESS = 1.0;
}
