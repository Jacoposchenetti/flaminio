shader_type spatial;
// Laterizio romano (Mura Aureliane, basamenti): mattoni sottili, malta, macchie del tempo. Coordinate mondo.

uniform vec3 brick_color : source_color = vec3(0.62, 0.36, 0.24);
uniform vec3 mortar_color : source_color = vec3(0.7, 0.66, 0.58);

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Coordinata orizzontale lungo la parete.
	vec3 tang = normalize(cross(vec3(0.0, 1.0, 0.0), wnrm) + vec3(1e-4, 0.0, 0.0));
	float u = dot(wpos, tang);
	float v = wpos.y;
	vec2 b = vec2(u / 0.42, v / 0.075);
	float row = floor(b.y);
	b.x += mod(row, 2.0) * 0.5;
	vec2 f = fract(b);
	float mortar = step(f.y, 0.22) + step(f.x, 0.04);
	vec3 brick = brick_color * (0.75 + 0.45 * hash(floor(b)));
	// Macchie e dilavamento.
	float stain = hash(floor(vec2(u, v) / 3.0));
	brick *= 0.85 + 0.25 * stain;
	vec3 col = mix(brick, mortar_color, clamp(mortar, 0.0, 1.0) * 0.8);
	// Da lontano i mattoni sono più piccoli di un pixel: sfumo verso il colore medio (niente moiré).
	float aa = clamp(max(fwidth(b.x), fwidth(b.y)) * 1.5 - 0.3, 0.0, 1.0);
	col = mix(col, mix(brick_color * 0.95, mortar_color, 0.3), aa);
	if (abs(wnrm.y) > 0.6) col = mortar_color * 0.8;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	NORMAL_MAP = vec3(0.5, 0.5 + 0.25 * (1.0 - step(0.22, f.y)), 1.0);
}
