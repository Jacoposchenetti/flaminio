shader_type spatial;
// Prati, boschi, campi sportivi: erba PBR tinta con COLOR (in sRGB).

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 tint;
varying vec2 wpos;

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1, 0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0, 1), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1, 1), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	tint = pow(COLOR.rgb, vec3(2.2)) / vec3(0.13, 0.22, 0.05);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz.xz;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec3 g = texture(grass_albedo, wpos / 4.0).rgb;
	// Erba secca a chiazze, come nei parchi romani d'estate.
	float dry = smoothstep(0.45, 0.8, noise(wpos / 18.0));
	g = mix(g, g * vec3(1.6, 1.25, 0.6), dry * 0.6);
	ALBEDO = g * clamp(tint, vec3(0.5), vec3(1.6));
	NORMAL_MAP = texture(grass_normal, wpos / 4.0).rgb;
	ROUGHNESS = 0.95;
}
