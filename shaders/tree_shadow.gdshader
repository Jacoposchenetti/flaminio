shader_type spatial;
render_mode unshaded, cull_disabled;
// Sagoma invisibile che fa l'ombra degli alberi (scripts/trees.gd → shadow_mesh): chioma piena ma bucherellata
// da un rumore, così a terra l'ombra ha le chiazze di luce come sotto una chioma vera. Il tronco resta pieno.

varying vec3 lp;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
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
	lp = VERTEX;
}

void fragment() {
	float n = vnoise(lp * 1.3) * 0.65 + vnoise(lp * 3.1 + 7.0) * 0.35;
	bool trunk = lp.y < 2.2;
	ALPHA = trunk ? 1.0 : step(0.38, n);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = vec3(0.0);
}
