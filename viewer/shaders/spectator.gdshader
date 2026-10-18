// A spectator by the road: the base character standing, painted by where a
// point lies on the body at rest (CUSTOM1): skin with its texture, the shirt
// in the instance colour, the trousers in INSTANCE_CUSTOM, dark shoes.
shader_type spatial;

uniform sampler2D skin_albedo : source_color, filter_linear_mipmap;

varying vec3 rest;
varying vec4 shirt;
varying vec4 trousers;

void vertex() {
	rest = CUSTOM1.xyz;
	shirt = COLOR;
	trousers = INSTANCE_CUSTOM;
}

void fragment() {
	float ax = abs(rest.x);
	vec3 albedo = texture(skin_albedo, UV).rgb * 1.15;
	float rough = 0.6;
	if (rest.y < 0.08) {
		albedo = vec3(0.06);
	} else if (rest.y < 0.98 && ax < 0.3) {
		albedo = trousers.rgb;
		rough = 0.9;
	} else if (rest.y < 1.53 && ax < 0.36 && !(ax > 0.2 && rest.y > 1.3 && ax > 0.33)) {
		// The shirt, with short sleeves.
		albedo = shirt.rgb;
		rough = 0.85;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
}
