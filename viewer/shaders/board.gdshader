// A flat board with a picture, seen from both sides: from behind the picture
// is mirrored back, so it reads the right way round.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D picture : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	vec2 uv = FRONT_FACING ? UV : vec2(1.0 - UV.x, UV.y);
	ALBEDO = texture(picture, uv).rgb;
	ROUGHNESS = 0.7;
}
