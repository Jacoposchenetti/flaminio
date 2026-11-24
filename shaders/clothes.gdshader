shader_type spatial;
// Vestiti dipinti sul corpo base (Quaternius Universal Base Characters, CC0): maglia, pantaloni, scarpe.
// La posizione del vertice nella posa a T è salvata in COLOR (x: (x+1)/2, y: y/2, z: z+0.5), così le
// zone dei vestiti restano attaccate al corpo anche quando si muove.

uniform sampler2D body_albedo : source_color, filter_linear_mipmap;
uniform sampler2D body_normal : hint_normal, filter_linear_mipmap;
uniform sampler2D body_rough : hint_roughness_g, filter_linear_mipmap;
uniform vec3 skin_ratio = vec3(1.0); // tonalità della pelle / colore medio della texture
uniform vec3 shirt_color : source_color = vec3(0.9);
uniform vec3 pants_color : source_color = vec3(0.15, 0.2, 0.35);
uniform vec3 shoe_color : source_color = vec3(0.9);
uniform float waist_y = 0.99;
uniform float neck_y = 1.48;
uniform float pants_end_y = 0.12; // 0.12 pantaloni lunghi, ~0.5 bermuda
uniform float shoe_y = 0.12;
uniform float sleeve_x = 0.33; // fine della manica lungo il braccio (posa a T)
uniform float torso_x = 0.2;
uniform float denim = 1.0; // trama del jeans
uniform float stripes = 0.0; // maglia a righe

varying vec3 bind;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	bind = vec3(COLOR.r * 2.0 - 1.0, COLOR.g * 2.0, COLOR.b - 0.5);
}

void fragment() {
	vec3 tex = texture(body_albedo, UV).rgb;
	vec3 nrm = texture(body_normal, UV).rgb;
	float rough = texture(body_rough, UV).g;
	vec3 col = tex * skin_ratio;
	float ax = abs(bind.x);
	float y = bind.y;
	float cloth = 0.0;
	vec3 ccol = vec3(0.0);

	if (y < shoe_y) {
		ccol = shoe_color;
		if (y < 0.025) ccol *= 0.35; // suola
		cloth = 1.0;
		rough = 0.55;
	} else if (y < waist_y && y >= pants_end_y && ax < 0.3) {
		ccol = pants_color;
		if (denim > 0.5) {
			float weave = vnoise(vec2(bind.x * 900.0 + bind.y * 900.0, bind.y * 300.0));
			ccol *= 0.85 + 0.25 * weave;
			// Scolorito su cosce e ginocchia.
			ccol = mix(ccol, ccol * 1.5, smoothstep(0.02, 0.0, abs(bind.z - 0.03)) * 0.4);
		}
		if (y > waist_y - 0.035) ccol = vec3(0.04, 0.03, 0.02); // cintura
		cloth = 1.0;
	} else if (ax > torso_x && y > waist_y + 0.2) {
		// Braccia (orizzontali nella posa a T): manica fino a sleeve_x.
		if (ax < sleeve_x) {
			ccol = shirt_color;
			if (stripes > 0.5) ccol *= 0.7 + 0.3 * step(0.5, fract(ax * 22.0));
			if (ax > sleeve_x - 0.015) ccol *= 0.85; // orlo della manica
			cloth = 1.0;
		}
	} else if (y >= waist_y - 0.005 && y < neck_y + max(0.0, ax - 0.06) * 0.9) {
		ccol = shirt_color;
		if (stripes > 0.5) ccol *= 0.7 + 0.3 * step(0.5, fract(y * 22.0));
		// Scollo a girocollo davanti.
		cloth = (ax < 0.06 && bind.z > 0.02 && y > neck_y - 0.02 + ax * 0.3) ? 0.0 : 1.0;
	}
	if (cloth > 0.5) {
		// Tessuto: pieghe morbide, niente muscoli in rilievo.
		float folds = vnoise(vec2(bind.x * 40.0, bind.y * 25.0));
		col = ccol * (0.85 + 0.2 * folds);
		nrm = mix(vec3(0.5, 0.5, 1.0), nrm, 0.25) + vec3((folds - 0.5) * 0.15, 0.0, 0.0);
		rough = max(rough, 0.8);
	}
	ALBEDO = col;
	NORMAL_MAP = nrm;
	ROUGHNESS = rough;
	SSS_STRENGTH = cloth > 0.5 ? 0.0 : 0.25;
}
