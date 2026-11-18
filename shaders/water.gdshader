shader_type spatial;
// Tevere: acqua verde-fango, increspature animate, riflessi (SSR quando la qualità è alta).

varying vec3 wpos;

vec2 waves(vec2 p, float t) {
	// Derivate di una somma di onde: danno la pendenza della superficie.
	vec2 d = vec2(0.0);
	vec2 dirs[4] = vec2[](vec2(0.8, 0.6), vec2(-0.4, 0.9), vec2(0.95, -0.3), vec2(-0.7, -0.7));
	float freqs[4] = float[](0.9, 1.7, 3.1, 5.3);
	for (int i = 0; i < 4; i++) {
		float ph = dot(dirs[i], p) * freqs[i] + t * (1.0 + float(i) * 0.6);
		d += dirs[i] * cos(ph) * freqs[i] * 0.02 / (1.0 + float(i));
	}
	return d;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 d = waves(wpos.xz + vec2(TIME * 0.4, 0.0), TIME);
	NORMAL_MAP = normalize(vec3(-d.x, -d.y, 1.0)) * 0.5 + 0.5;
	ALBEDO = vec3(0.035, 0.05, 0.03);
	ROUGHNESS = 0.03;
	SPECULAR = 0.6;
}
