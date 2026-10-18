// A house by the road: the walls in the instance colour with windows in rows
// and a door towards the road, the roof in INSTANCE_CUSTOM with rows of
// tiles. The mesh is a unit house: walls up to 1, the roof above, the front
// at z = -0.5, a plinth down to -0.5 into the ground.
shader_type spatial;

varying vec3 local;
varying vec3 size;
varying vec4 wall;
varying vec4 roof;

void vertex() {
	local = VERTEX;
	size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	wall = COLOR;
	roof = INSTANCE_CUSTOM;
}

void fragment() {
	// How much of the house one pixel covers: from far away the windows
	// fade into the wall instead of flickering.
	float blur = length(fwidth(local * size));
	if (local.y > 1.0005) {
		float rows = fract((local.y - 1.0) * size.y / 0.32);
		ALBEDO = roof.rgb * mix(0.82 + 0.18 * step(0.45, rows), 0.91, smoothstep(0.08, 0.3, blur));
		ROUGHNESS = 0.75;
	} else {
		// Metres along the facade and above the ground.
		bool end = abs(abs(local.x) - 0.5) < 0.002;
		float along = end ? local.z * size.z : local.x * size.x;
		float up = local.y * size.y;
		float storey = fract(up / 3.0);
		float bay = fract(along / 3.2 + 0.5);
		float window = (up > 0.9 && storey > 0.3 && storey < 0.78 && bay > 0.28 && bay < 0.72) ? 1.0 : 0.0;
		float door = (!end && local.z < -0.498 && up > 0.0 && up < 2.2 && abs(along) < 0.65) ? 1.0 : 0.0;
		float clear = 1.0 - smoothstep(0.15, 0.6, blur);
		vec3 c = wall.rgb * (up < 0.0 ? 0.65 : 1.0);
		c = mix(c, vec3(0.06, 0.08, 0.1), window * clear);
		c = mix(c, vec3(0.22, 0.13, 0.07), door);
		ALBEDO = c;
		ROUGHNESS = mix(0.9, 0.25, window * clear);
	}
}
