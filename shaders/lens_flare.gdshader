shader_type canvas_item;
render_mode blend_add, unshaded;
// Riflessi del sole sulla lente, come in una ripresa: bagliore attorno al sole, striscia orizzontale,
// raggi a stella e "fantasmi" colorati lungo la linea sole-centro dello schermo.
// sun_pos in pixel dello schermo; strength 0 quando il sole è dietro un palazzo o è notte.

uniform vec2 sun_pos = vec2(0.0);
uniform vec2 screen = vec2(1920.0, 1080.0);
uniform float strength = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.85, 0.65);

float ghost(vec2 p, vec2 c, float r, float soft) {
	float d = length(p - c);
	return smoothstep(r, r * soft, d);
}

void fragment() {
	if (strength <= 0.001) {
		discard;
	}
	float asp = screen.x / screen.y;
	vec2 p = (FRAGCOORD.xy / screen - 0.5) * vec2(asp, 1.0);
	vec2 s = (sun_pos / screen - 0.5) * vec2(asp, 1.0);
	vec2 rel = p - s;
	float d = length(rel);
	vec3 col = vec3(0.0);
	// Bagliore attorno al sole.
	col += tint * (0.35 / (1.0 + d * d * 90.0) + 0.12 * exp(-d * 7.0));
	// Striscia orizzontale (anamorfica), sottile.
	col += tint * vec3(0.9, 0.95, 1.1) * exp(-abs(rel.y) * 260.0) * exp(-abs(rel.x) * 2.2) * 0.35;
	// Raggi a stella.
	float ang = atan(rel.y, rel.x);
	float rays = pow(abs(cos(ang * 3.0)), 60.0) + pow(abs(cos(ang * 3.0 + 0.52)), 90.0) * 0.6;
	col += tint * rays * exp(-d * 9.0) * 0.35;
	// Fantasmi lungo la linea dal sole al centro, e oltre.
	vec2 axis = -s;
	col += vec3(0.4, 0.75, 0.5) * ghost(p, s + axis * 0.55, 0.045, 0.2) * 0.10;
	col += vec3(0.85, 0.45, 0.85) * ghost(p, s + axis * 1.25, 0.09, 0.75) * 0.06;
	col += vec3(0.95, 0.75, 0.35) * ghost(p, s + axis * 1.6, 0.03, 0.1) * 0.12;
	col += vec3(0.45, 0.6, 1.0) * ghost(p, s + axis * 2.1, 0.16, 0.9) * 0.05;
	// Anello (alone) attorno al centro opposto al sole.
	float ring = abs(length(p - (s + axis * 1.9)) - 0.22);
	col += vec3(0.6, 0.8, 1.0) * exp(-ring * 120.0) * 0.04;
	COLOR = vec4(col * strength, 1.0);
}
