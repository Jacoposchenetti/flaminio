shader_type spatial;
// Superfici a pannelli: il piombo dei "scarabei" dell'Auditorium e il cemento a costoloni del Palazzetto.
// UV in metri: seam_u / seam_v = passo delle giunture.

uniform vec3 base_color : source_color = vec3(0.42, 0.44, 0.46);
uniform float seam_u = 1.2;
uniform float seam_v = 4.0;
uniform float metal = 0.55;
uniform float rough = 0.45;
uniform float seam_dark = 0.55;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(vec2(UV.x / seam_u, UV.y / seam_v));
	vec2 f = fract(vec2(UV.x / seam_u, UV.y / seam_v));
	float seam = min(min(f.x, 1.0 - f.x) * seam_u, min(f.y, 1.0 - f.y) * seam_v);
	vec3 col = base_color * (0.9 + 0.18 * hash(cell));
	col *= mix(seam_dark, 1.0, smoothstep(0.0, 0.05, seam));
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough + 0.15 * hash(cell + 3.0);
	// Rilievo delle giunture aggraffate.
	NORMAL_MAP = vec3(0.5 + 0.35 * (smoothstep(0.06, 0.0, f.x * seam_u) - smoothstep(0.06, 0.0, (1.0 - f.x) * seam_u)), 0.5, 1.0);
}
