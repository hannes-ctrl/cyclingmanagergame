// The rider on his bike. The positions of the vertices come from a texture:
// six stances with sixteen positions of the cranks each. The shader blends
// between two crank positions and between neighbouring stances, rolls the
// bike with the pedal strokes out of the saddle and turns the wheels. The
// kit is painted in the team's colours.
//
// Per rider: COLOR is the first team colour, its alpha the design of the
// jersey (whole: 0..5 painted in the team colours, from 8 on the layer of
// the real kit from the WorldDB plus 8) plus the rider's own number for skin
// and lenses (fraction);
// INSTANCE_CUSTOM is the second team colour, its alpha the stance times 16
// (whole) plus the position of the cranks in turns (fraction).
//
// CUSTOM0: x = region of the mesh (0 the body), y = part (1 front wheel,
// 2 rear wheel). CUSTOM1: for the body, where the point lies on the body
// standing at rest with the arms out; skin and kit are told apart by it,
// so that every hem is a clean line.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D vat : filter_nearest, repeat_disable;
uniform int frames = 16;
uniform int vat_width = 4096;
uniform int rows_per_frame = 3;
uniform int stances = 6;
// Turn of the wheels, in radians.
uniform float wheel = 0.0;
uniform sampler2D skin_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap_anisotropic;
// Kits from the WorldDB: one layer per team or leader, and per layer the
// colours of socks, shoes, gloves, bar tape and bottle (rows 0 to 4) and the
// two main colours of the jersey (rows 5 and 6), for helmet and bike.
uniform sampler2DArray kits : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D kit_colours : source_color, filter_nearest, repeat_disable;

// Parts of the kit on the body.
const int SKIN = 0;
const int JERSEY = 1;
const int SLEEVE = 2;
const int SHORTS = 3;
const int SHOES = 4;
const int MITTS = 5;
const int SOCKS = 6;

// How far the bike rolls with each pedal stroke, per stance (as in
// rider_model.gd).
const float ROCK[6] = {0.0, 0.0, 0.12, 0.2, 0.0, 0.0};

varying vec3 model_pos;
varying vec3 rest;
varying flat int region;
varying vec4 team1;
varying vec4 team2;
varying flat float stance;
varying flat float seed;
varying float rest_front;

vec3 fetch(int v, int st, int frame, int block) {
	ivec2 at = ivec2(v % vat_width, ((st * 2 + block) * frames + frame) * rows_per_frame + v / vat_width);
	return texelFetch(vat, at, 0).xyz;
}

void vertex() {
	float packed = INSTANCE_CUSTOM.a;
	float whole = floor(packed);
	float turn = packed - whole;
	float pose = whole / 16.0;
	int s0 = clamp(int(floor(pose)), 0, stances - 1);
	int s1 = min(s0 + 1, stances - 1);
	float w = pose - float(s0);
	float f = turn * float(frames);
	int f0 = int(floor(f)) % frames;
	int f1 = (f0 + 1) % frames;
	float t = fract(f);
	int v = VERTEX_ID;
	vec3 p = mix(fetch(v, s0, f0, 0), fetch(v, s0, f1, 0), t);
	vec3 n = mix(fetch(v, s0, f0, 1), fetch(v, s0, f1, 1), t);
	if (w > 0.001) {
		p = mix(p, mix(fetch(v, s1, f0, 0), fetch(v, s1, f1, 0), t), w);
		n = mix(n, mix(fetch(v, s1, f0, 1), fetch(v, s1, f1, 1), t), w);
	}
	n = normalize(n);
	float own = fract(COLOR.a + 0.001);
	int part = int(CUSTOM0.y + 0.5);
	if (part > 0) {
		vec3 axle = part == 1 ? vec3(0.0, 0.336, 0.585) : vec3(0.0, 0.336, -0.405);
		float a = wheel + own * 37.0;
		float c = cos(a);
		float s = sin(a);
		vec3 q = p - axle;
		p = axle + vec3(q.x, q.y * c - q.z * s, q.y * s + q.z * c);
		n = vec3(n.x, n.y * c - n.z * s, n.y * s + n.z * c);
	}
	// Out of the saddle the bike rolls away from the pedal pushing down.
	float rock = mix(ROCK[s0], ROCK[s1], w);
	if (rock > 0.0) {
		float r = -rock * sin(6.2831853 * turn);
		float c = cos(r);
		float s = sin(r);
		p = vec3(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
		n = vec3(n.x * c - n.y * s, n.x * s + n.y * c, n.z);
	}
	VERTEX = p;
	NORMAL = n;
	model_pos = p;
	rest = CUSTOM1.xyz;
	rest_front = CUSTOM1.w;
	region = int(CUSTOM0.x + 0.5);
	team1 = COLOR;
	team2 = INSTANCE_CUSTOM;
	stance = pose;
	seed = own;
}

float hash(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

// Which part of the kit covers a point of the body, from where it lies at
// rest: standing, the arms out to the sides, the palms down.
int kit(vec3 r) {
	float ax = abs(r.x);
	if (ax > 0.2 && r.y > 1.25) {
		// An arm: sleeve to the middle of the upper arm, mitts over the palm.
		if (ax < 0.355) return SLEEVE;
		if (ax < 0.69) return SKIN;
		return ax < 0.83 ? MITTS : SKIN;
	}
	// The neck, round its axis; the collar hugs it.
	float neck = length(vec2(r.x, r.z + 0.035));
	if (r.y > 1.565 || (r.y > 1.495 && neck < 0.068)) return SKIN;
	// The jersey rides up at the back when he leans forward.
	float hem = mix(0.975, 1.005, clamp(-r.z / 0.1, 0.0, 1.0));
	if (r.y > hem) return JERSEY;
	if (r.y > 0.63) return SHORTS;
	if (r.y > 0.25) return SKIN;
	return r.y > 0.08 ? SOCKS : SHOES;
}

// Whether a point of the head is under the helmet: above its rim, which
// runs just above the glasses, above the ears and low over the back of the
// head (as in rider_model.gd).
bool under_helmet(vec3 r) {
	if (r.y < 1.6) {
		return false;
	}
	float lon = atan(r.x, r.z + 0.012);
	float back = pow(0.5 - 0.5 * cos(lon), 1.3);
	return r.y > 1.705 + 0.12 * cos(mix(1.445, 2.09, back)) + 0.004;
}

// Where a point of the body lies on a kit texture of the WorldDB: the front
// of jersey and shorts on its left half, the back on its right half, the
// sleeves in the top corners of each, as if the rider stood with his arms
// out; the shorts are drawn larger than the jersey.
vec2 kit_uv(vec3 r, float front) {
	bool ahead = front > 0.0;
	float v = r.y > 0.975 ? (1.505 - r.y) * 860.0 : 455.0 + (0.975 - r.y) * 1075.0;
	float u;
	if (abs(r.x) > 0.19 && r.y > 1.25) {
		float beyond = (abs(r.x) - 0.19) * 1000.0;
		u = ahead ? clamp(300.0 + sign(r.x) * (175.0 + beyond), 2.0, 598.0)
			: clamp(905.0 - sign(r.x) * (230.0 + beyond), 602.0, 1198.0);
	} else {
		u = ahead ? 300.0 + r.x * 930.0 : 905.0 - r.x * 1250.0;
	}
	return vec2(u / 1200.0, clamp(v, 1.0, 825.0) / 826.0);
}

void fragment() {
	vec3 c1 = team1.rgb;
	vec3 c2 = team2.rgb;
	int code = int(floor(team1.a + 0.001));
	bool real = code >= 8;
	int layer = code - 8;
	int design = real ? 0 : code;
	if (real) {
		// Helmet and bike in the colours of the real kit.
		c1 = texelFetch(kit_colours, ivec2(layer, 5), 0).rgb;
		c2 = texelFetch(kit_colours, ivec2(layer, 6), 0).rgb;
	}
	// A second pick by team, for socks and shoes.
	float pick = fract(c1.r * 7.31 + c1.g * 3.17 + c1.b * 5.71);
	// How much of the shell or body one pixel covers, for patterns that
	// would flicker from far away.
	float blur = length(fwidth(rest));
	vec3 albedo = vec3(0.5);
	float rough = 0.5;
	float metal = 0.0;
	float normal_depth = 0.0;
	if (region == 0) {
		int part = kit(rest);
		float ax = abs(rest.x);
		float y = rest.y;
		if (part == SKIN && under_helmet(rest)) {
			// The head under the helmet, hair in its shadow: where the coarse
			// model of a rider far away lets it through, it looks like a vent.
			albedo = vec3(0.04, 0.03, 0.025);
			rough = 0.9;
		} else if (part == SKIN) {
			// Mostly fair skin, tanned by the season, now and then darker.
			float k = hash(seed * 113.0 + 0.7);
			float tone = k < 0.1 ? 0.55 + 2.0 * k : 1.05 + 0.4 * k;
			albedo = texture(skin_albedo, UV).rgb * vec3(tone, tone * 0.95, tone * 0.88);
			rough = 0.55;
			normal_depth = 1.0;
		} else if (real && (part == JERSEY || part == SLEEVE || part == SHORTS)) {
			albedo = texture(kits, vec3(kit_uv(rest, rest_front), float(layer))).rgb;
			rough = part == SHORTS ? 0.5 : 0.6;
			normal_depth = part == SHORTS ? 0.3 : 0.15;
		} else if (part == JERSEY) {
			albedo = c1;
			if (design == 0) {
				albedo = (y > 1.3 && y < 1.37) ? c2 : c1;
			} else if (design == 1) {
				albedo = y > 1.2 ? c1 : c2;
			} else if (design == 2) {
				albedo = ax < 0.045 ? c2 : c1;
			} else if (design == 3) {
				albedo = ax > 0.12 ? c2 : c1;
			} else if (design == 4) {
				float sash = rest.x * 0.9 + y;
				albedo = (sash > 1.24 && sash < 1.34) ? c2 : c1;
			} else {
				albedo = y > 1.4 ? c2 : c1;
			}
			// The collar in the second colour.
			if (y > 1.475 && length(vec2(rest.x, rest.z + 0.035)) < 0.082) {
				albedo = c2;
			}
			rough = 0.6;
			normal_depth = 0.15;
		} else if (part == SLEEVE) {
			// Side panels and yoke run on into the sleeves; a band at the cuff
			// in the other colour.
			bool second = design == 3 || design == 5;
			if (ax > 0.335) {
				second = !second;
			}
			albedo = second ? c2 : c1;
			rough = 0.6;
			normal_depth = 0.15;
		} else if (part == SHORTS) {
			// Panels in the team's colour down the outside of the thighs.
			albedo = ax > 0.16 && y < 0.92 ? c1 * 0.8 : vec3(0.025);
			// The grippers at the hem.
			if (y < 0.655) {
				albedo = vec3(0.02);
			}
			rough = 0.5;
			normal_depth = 0.3;
		} else if (part == SHOES) {
			albedo = real ? texelFetch(kit_colours, ivec2(layer, 1), 0).rgb : (pick < 0.55 ? vec3(0.88) : vec3(0.03));
			// The sole.
			if (y < 0.022) {
				albedo = vec3(0.05);
			}
			rough = 0.3;
		} else if (part == MITTS) {
			albedo = real ? texelFetch(kit_colours, ivec2(layer, 2), 0).rgb : vec3(0.03);
			rough = 0.65;
			normal_depth = 0.3;
		} else {
			albedo = real ? texelFetch(kit_colours, ivec2(layer, 0), 0).rgb : (pick < 0.3 ? vec3(0.03) : (pick < 0.8 ? vec3(0.86) : c1));
			rough = 0.8;
		}
	} else if (region == 7) {
		// The shell of the helmet: rest holds the direction from its middle.
		// A band of the second colour down the middle, vents in three rows
		// either side of it, opening towards the front.
		vec3 d = normalize(rest);
		float across = abs(atan(d.x, d.y));
		float along = d.z;
		albedo = across < 0.1 ? c2 : c1;
		rough = 0.25;
		float row = along > 0.4 ? 0.0 : (along > -0.15 ? 1.0 : 2.0);
		float open = row == 0.0 ? smoothstep(0.42, 0.47, along) * (1.0 - smoothstep(0.8, 0.86, along))
			: (row == 1.0 ? smoothstep(-0.12, -0.07, along) * (1.0 - smoothstep(0.3, 0.35, along))
			: smoothstep(-0.72, -0.67, along) * (1.0 - smoothstep(-0.3, -0.25, along)));
		float vent = 0.0;
		for (int c = 0; c < 3; c++) {
			float at = 0.3 + float(c) * 0.33 + row * 0.06;
			float width = 0.075 - 0.02 * row;
			vent = max(vent, 1.0 - smoothstep(width - 0.015, width, abs(across - at)));
		}
		// The time trial helmet is smooth.
		vent *= open * (1.0 - smoothstep(0.025, 0.07, blur)) * (stance > 4.5 ? 0.0 : 1.0);
		albedo = mix(albedo, vec3(0.015), vent);
		rough = mix(rough, 0.9, vent);
	} else if (region == 8) {
		// Lenses: smoke, or mirrored blue or orange, by rider.
		float k = hash(seed * 71.0 + 0.3);
		albedo = k < 0.5 ? vec3(0.02, 0.02, 0.025) : (k < 0.8 ? vec3(0.04, 0.1, 0.3) : vec3(0.35, 0.1, 0.02));
		rough = 0.08;
		metal = k < 0.5 ? 0.7 : 0.95;
	} else if (region == 17) {
		// Foam inside the helmet.
		albedo = vec3(0.05);
		rough = 0.9;
	} else if (region == 9) {
		albedo = c1 * 0.92;
		rough = 0.22;
	} else if (region == 10) {
		albedo = vec3(0.03);
		rough = 0.4;
	} else if (region == 11) {
		albedo = vec3(0.62);
		rough = 0.3;
		metal = 0.9;
	} else if (region == 12) {
		albedo = vec3(0.035);
		rough = 0.25;
	} else if (region == 13) {
		albedo = vec3(0.04);
		rough = 0.85;
	} else if (region == 14) {
		albedo = real ? texelFetch(kit_colours, ivec2(layer, 3), 0).rgb : vec3(0.02);
		rough = 0.55;
	} else if (region == 16) {
		albedo = real ? texelFetch(kit_colours, ivec2(layer, 1), 0).rgb : (pick < 0.55 ? vec3(0.88) : vec3(0.03));
		rough = 0.3;
	} else {
		albedo = real ? texelFetch(kit_colours, ivec2(layer, 4), 0).rgb : c2;
		rough = 0.35;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	if (normal_depth > 0.0) {
		NORMAL_MAP = texture(skin_normal, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
}
