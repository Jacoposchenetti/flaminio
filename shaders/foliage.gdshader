shader_type spatial;
// Chiome degli alberi: colore variato per albero e per ciuffo, foglie finte con rumore,
// luce che passa attraverso (backlight), leggero vento.

uniform vec3 leaf_color : source_color = vec3(0.33, 0.45, 0.17);

varying vec3 local_pos;
varying float tree_rand;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	local_pos = VERTEX;
	vec3 origin = MODEL_MATRIX[3].xyz;
	tree_rand = hash3(floor(origin));
	float sway = sin(TIME * 1.1 + origin.x * 0.13 + origin.z * 0.07) * 0.12 + sin(TIME * 2.7 + VERTEX.y) * 0.03;
	VERTEX.x += sway * clamp((VERTEX.y - 3.0) / 8.0, 0.0, 1.0);
}

void fragment() {
	float n = vnoise(local_pos * 2.3);
	float n2 = vnoise(local_pos * 6.0);
	vec3 col = leaf_color * (0.75 + 0.5 * tree_rand);
	col *= 0.65 + 0.55 * n;
	col = mix(col, col * vec3(1.3, 1.2, 0.7), smoothstep(0.6, 0.9, n2) * 0.5); // foglie al sole
	// Più scuro verso l'interno e in basso nella chioma.
	col *= mix(0.55, 1.0, clamp(dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz) * 0.5 + 0.6, 0.0, 1.0));
	ALBEDO = col;
	NORMAL_MAP = normalize(vec3(n2 - 0.5, n - 0.5, 0.6)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.5;
	ROUGHNESS = 0.85;
	BACKLIGHT = col * 0.6;
}
