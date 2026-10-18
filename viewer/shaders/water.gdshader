// A lake: dark water with small waves that catch the sky and the sun.
shader_type spatial;
// The triangles of a lake are cut at the edges of a tile in either winding.
render_mode cull_disabled;

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 0.4;
	// Far off the waves calm down, or they would flicker in the distance.
	float calm = clamp(1.0 - length(VERTEX) / 900.0, 0.12, 1.0);
	vec2 wave = vec2(
		0.05 * sin(world.x * 0.35 + world.z * 0.11 + t) + 0.03 * sin(world.z * 0.9 - t * 1.7)
			+ 0.02 * sin((world.x - world.z) * 1.7 + t * 2.3),
		0.05 * cos(world.z * 0.31 - world.x * 0.13 + t * 1.2) + 0.03 * cos(world.x * 0.8 + t * 1.5)
			+ 0.02 * cos((world.x + world.z) * 1.9 - t * 2.1));
	vec3 n = normalize(vec3(wave.x * calm, 1.0, wave.y * calm));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = vec3(0.03, 0.09, 0.11);
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
}
