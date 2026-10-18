// The road surface: photo textures for asphalt, cobbles and gravel, the
// markings drawn sharp at any distance, a wet look in the rain, and the
// finish line.
//
// UV: x = metres right of the road centre, y = metres from the start.
// UV2: x = surface (0 asphalt, 1 cobbles, 2 gravel, 3 shoulder, 4 verge),
//      y = half the road width.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

// Metres one texture covers.
uniform float asphalt_size = 3.0;
uniform float cobble_size = 2.6;
uniform float gravel_size = 3.0;
// 0 dry, 1 soaked.
uniform float wet = 0.0;
// Metres from the start of the finish line; negative for none.
uniform float finish_m = -1.0;
// Colour of the grass on the verge, as the land around it.
uniform vec3 verge_colour = vec3(0.22, 0.33, 0.13);

varying vec2 road;
varying float surface;
varying float half_width;

void vertex() {
	road = UV;
	surface = UV2.x;
	half_width = UV2.y;
}

// 1 on a painted line of width w around 0, antialiased.
float paint(float x, float w) {
	float aa = fwidth(x) * 0.75;
	return 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, abs(x));
}

void fragment() {
	vec2 uv = vec2(road.x, road.y);
	// Beyond the edge of the road: the shoulder, then the verge.
	float across = abs(road.x);
	float kind = across > half_width + 0.35 ? 4.0 : (across > half_width ? 3.0 : surface);
	vec3 albedo;
	vec3 normal_map;
	float rough;
	if (kind < 0.5) {
		vec2 t = uv / asphalt_size;
		albedo = texture(asphalt_albedo, t).rgb;
		normal_map = texture(asphalt_normal, t).rgb;
		// Dry asphalt is rough; a polished line along the wheel tracks at most.
		rough = 0.62 + 0.38 * texture(asphalt_rough, t).r;
		// A large-scale variation hides the repetition of the texture.
		albedo *= 0.82 + 0.36 * texture(asphalt_albedo, uv / 47.0).g;
		// Wheel tracks are a little darker and smoother.
		float track = paint(abs(road.x) - half_width * 0.45, 1.2);
		albedo *= 1.0 - 0.08 * track;
		rough -= 0.06 * track;
		// Markings: a line along both edges, a dashed one in the middle.
		float edge = paint(abs(road.x) - (half_width - 0.32), 0.12);
		float centre = paint(road.x, 0.11) * step(fract(road.y / 12.0), 0.25);
		float line = max(edge, centre);
		albedo = mix(albedo, vec3(0.82, 0.82, 0.8), line * 0.92);
		rough = mix(rough, 0.55, line);
	} else if (kind < 1.5) {
		vec2 t = uv / cobble_size;
		albedo = texture(cobble_albedo, t).rgb;
		normal_map = texture(cobble_normal, t).rgb;
		// Dry stones are matt; only the joints hold a little shine.
		rough = 0.78 + 0.22 * texture(cobble_rough, t).r;
		albedo *= 0.85 + 0.3 * texture(cobble_albedo, uv / 31.0).g;
	} else if (kind < 2.5) {
		vec2 t = uv / gravel_size;
		albedo = texture(gravel_albedo, t).rgb * vec3(1.08, 1.05, 1.0);
		normal_map = texture(gravel_normal, t).rgb;
		rough = texture(gravel_rough, t).r;
	} else if (kind < 3.5) {
		// The shoulder: gravel and dust at the edge of the asphalt.
		vec2 t = uv / gravel_size;
		vec3 g = texture(gravel_albedo, t).rgb;
		// Grey grit, not the brown of a farm track.
		albedo = mix(vec3(dot(g, vec3(0.333))), g, 0.35) * 0.62;
		normal_map = texture(gravel_normal, t).rgb;
		rough = 0.95;
	} else {
		// The verge: grass over earth, as dark as the land.
		vec2 t = uv / gravel_size;
		float g = texture(gravel_albedo, t * 1.7).g;
		albedo = verge_colour * (0.75 + 0.5 * g);
		normal_map = mix(vec3(0.5, 0.5, 1.0), texture(gravel_normal, t).rgb, 0.4);
		rough = 0.97;
	}
	if (finish_m >= 0.0 && kind < 2.5) {
		// The finish line: a white band with a chequered edge.
		float band = paint(road.y - finish_m, 0.6);
		float chequer = step(0.5, fract(road.x / 0.3)) == step(0.5, fract((road.y - finish_m) / 0.3)) ? 1.0 : 0.0;
		float rim = paint(road.y - finish_m - 0.6, 0.6);
		albedo = mix(albedo, vec3(0.9), band);
		albedo = mix(albedo, mix(vec3(0.05), vec3(0.9), chequer), rim);
	}
	// In the rain the road darkens and shines.
	albedo *= mix(1.0, 0.55, wet * step(kind, 2.5));
	rough = mix(rough, 0.18, wet * step(kind, 2.5));
	ALBEDO = albedo;
	NORMAL_MAP = normal_map;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.3;
}
