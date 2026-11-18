shader_type spatial;
// Strade (asfalto PBR con segnaletica e strisce pedonali), vialetti, binari del tram, piazze in sampietrini.
// UV.x = distanza lungo la strada, UV.y = da -1 a 1 attraverso la carreggiata.
// COLOR.r = tipo / 4 (0 strada, 1 vialetto, 2 tram, 3 piazza), COLOR.g = larghezza / 32.
// UV2.x = metri dall'incrocio precedente, UV2.y = metri all'incrocio successivo.

uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_rough : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 wpos;
varying float kind;
varying float width;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	kind = floor(COLOR.r * 4.0 + 0.5);
	width = COLOR.g * 32.0;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 w = wpos.xz;
	float across = UV.y * width * 0.5;
	float along = UV.x;
	vec3 col;
	vec3 nmap;
	float rough;
	if (kind < 0.5 || kind > 1.5 && kind < 2.5) {
		vec2 auv = w / 4.0;
		col = texture(asphalt_albedo, auv).rgb * 0.55;
		// Chiazze di asfalto rifatto e usura sulle corsie.
		col *= 0.85 + 0.25 * hash(floor(w / 9.0));
		nmap = texture(asphalt_normal, auv).rgb;
		rough = texture(asphalt_rough, auv).r;
		vec3 paint = vec3(0.8);
		bool marked = false;
		if (kind < 0.5 && width >= 7.0) {
			float near_j = min(UV2.x, UV2.y);
			if (near_j > 2.5 && near_j < 6.5 && abs(across) < width * 0.5 - 0.4) {
				marked = fract(across / 1.0) < 0.5; // strisce pedonali
			} else if (near_j > 6.5) {
				if (abs(across) < 0.07 && fract(along / 7.0) < 0.45) marked = true; // mezzeria
				if (abs(abs(across) - (width * 0.5 - 0.45)) < 0.07) marked = true; // bordo
			}
		}
		if (kind > 1.5) {
			// Binari del tram: rotaie lucide su asfalto.
			if (abs(abs(across) - 0.72) < 0.04) { col = vec3(0.45); rough = 0.25; nmap = vec3(0.5, 0.5, 1.0); }
		}
		if (marked) {
			col = mix(col, paint, 0.85 * (0.7 + 0.3 * hash(floor(w * 4.0))));
			rough = 0.6;
		}
	} else if (kind < 1.5) {
		// Vialetti dei parchi e marciapiedi pedonali: brecciolino chiaro.
		vec2 puv = w / 3.0;
		col = texture(path_albedo, puv).rgb * vec3(0.95, 0.88, 0.75);
		nmap = texture(path_normal, puv).rgb;
		rough = 0.95;
	} else {
		// Piazze: sampietrini.
		vec2 cuv = w / 2.5;
		col = texture(cobble_albedo, cuv).rgb * vec3(0.7, 0.68, 0.66);
		nmap = texture(cobble_normal, cuv).rgb;
		rough = 0.8;
	}
	ALBEDO = col;
	NORMAL_MAP = nmap;
	ROUGHNESS = rough;
}
