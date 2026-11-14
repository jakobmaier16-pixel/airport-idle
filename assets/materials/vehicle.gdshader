// Shared material of every vehicle (art/vehicles/vehicles.md). One material serves all paint colours:
// the paint colour comes per car from the MultiMesh instance colour (Color("#hex", flake)) and is
// multiplied only where the atlas alpha marks paint. Glass, tyres, lamps and trim keep their atlas colour.
// INSTANCE_CUSTOM.r switches the lamps on (0 = parked, 1 = driving / night); needs use_custom_data.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D rme_atlas : hint_default_white, filter_linear_mipmap, repeat_disable;
// Metallic paints (instance colour alpha = 1) get this much metallic flake.
uniform float flake_metallic : hint_range(0.0, 1.0) = 0.5;
uniform float light_energy : hint_range(0.0, 16.0) = 4.0;

varying vec4 paint;
varying float lights_on;

void vertex() {
	// COLOR = vertex colour (white in the models) x MultiMesh instance colour.
	paint = COLOR;
	lights_on = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec4 atlas = texture(albedo_atlas, UV);
	vec3 rme = texture(rme_atlas, UV).rgb;
	// The instance colour is given in sRGB (as written in vehicles.md); light maths needs linear.
	vec3 p = paint.rgb;
	vec3 paint_linear = mix(p / 12.92, pow((p + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), p));
	ALBEDO = atlas.rgb * mix(vec3(1.0), paint_linear, atlas.a);
	ROUGHNESS = rme.r;
	METALLIC = clamp(rme.g + atlas.a * paint.a * flake_metallic, 0.0, 1.0);
	EMISSION = atlas.rgb * rme.b * lights_on * light_energy;
}
