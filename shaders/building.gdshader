shader_type spatial;
// Facciate romane: intonaco PBR colorato (COLOR), zoccolo in travertino, negozi al piano terra,
// finestre con cornice, persiane verdi o marroni, vetri riflettenti con tende.
// UV.x = distanza lungo il perimetro, UV.y = altezza dal piede del muro, UV2.x = altezza del muro,
// UV2.y: 0 muro, 1 tetto, 2 finiture (cornicione, parapetto, balconi).

uniform sampler2D plaster_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_rough : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool modern = false; // calcestruzzo liscio con nastri vetrati (MAXXI)
uniform float floor_h = 3.2;
uniform float bay_w = 3.4;
global uniform float night; // 0 di giorno, 1 di notte (DayNight): finestre e vetrine accese

varying vec3 tint;
varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 3.7) * 0.3 + vnoise(p * 4.3 + 9.1) * 0.15;
}

// Stanza finta dietro il vetro (interior mapping): il raggio dalla camera entra dalla finestra e colpisce
// pareti, pavimento o soffitto di una scatola; cambia prospettiva mentre ci si muove.
// lp: punto sulla finestra in metri (x lungo il muro, y in alto, 0 al centro della finestra).
vec3 room(vec2 lp, vec3 rd, float seed, float floor_y, float ceil_y, out float lit_mask) {
	float hw = 1.9;
	float depth = 4.0;
	vec3 inv = sign(rd + 1e-6) / max(abs(rd), vec3(1e-4));
	float tx = ((rd.x > 0.0 ? hw : -hw) - lp.x) * inv.x;
	float ty = ((rd.y > 0.0 ? ceil_y : floor_y) - lp.y) * inv.y;
	float tz = depth * inv.z;
	float t = min(tx, min(ty, tz));
	vec3 hit = vec3(lp, 0.0) + rd * t;
	vec3 wall = mix(vec3(0.85, 0.8, 0.7), vec3(0.7, 0.78, 0.82), step(0.6, seed)); // pareti color crema o azzurrine
	wall = mix(wall, vec3(0.9, 0.88, 0.85), step(0.85, seed));
	vec3 c;
	if (t == tz) {
		c = wall * 0.8; // parete di fondo
		// Un mobile e un quadro.
		if (abs(hit.x - (seed - 0.5) * 1.6) < 0.5 && hit.y > floor_y + 0.2 && hit.y < floor_y + 1.9 && seed > 0.3) c = vec3(0.35, 0.24, 0.16);
		if (abs(hit.x + (seed - 0.5)) < 0.35 && abs(hit.y - 0.3) < 0.25) c = vec3(0.5, 0.4, 0.35);
	} else if (t == ty) {
		c = rd.y > 0.0 ? vec3(0.92, 0.9, 0.86) : vec3(0.42, 0.28, 0.17) * (0.85 + 0.15 * step(0.5, fract(hit.x * 2.5))); // soffitto o parquet
	} else {
		c = wall * 0.9;
	}
	// Più buio in fondo.
	c *= mix(1.0, 0.45, clamp(hit.z / depth, 0.0, 1.0));
	lit_mask = (rd.y > 0.0 && t == ty) ? 1.0 : 0.6;
	return c;
}

vec3 srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

void vertex() {
	tint = pow(COLOR.rgb, vec3(2.2)) / 0.62; // palette in sRGB; l'intonaco ha albedo ~0,62
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (abs(NORMAL.y) > 0.5) {
		TANGENT = vec3(1.0, 0.0, 0.0);
		BINORMAL = vec3(0.0, 0.0, 1.0);
	} else {
		TANGENT = normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL));
		BINORMAL = vec3(0.0, -1.0, 0.0);
	}
}

void fragment() {
	vec2 suv = UV / 3.0; // l'intonaco si ripete ogni 3 m
	vec3 col;
	vec3 nmap = texture(plaster_normal, suv).rgb;
	vec3 emit = vec3(0.0);
	float rough = texture(plaster_rough, suv).r;
	float metal = 0.0;
	float spec = 0.5;
	float kind = UV2.y;

	if (kind > 1.5) {
		// Finiture chiare: stucco/travertino.
		vec2 tuv = (abs(NORMAL.y) > 0.5 ? wpos.xz : UV) / 2.5;
		col = mix(texture(stone_albedo, tuv).rgb, vec3(0.86, 0.82, 0.74), 0.75) * 1.05;
		nmap = texture(stone_normal, tuv).rgb;
		rough = 0.75;
	} else if (kind > 0.5) {
		// Terrazza: guaina grigia, a volte cotto.
		vec2 ruv = wpos.xz / 4.0;
		col = texture(roof_albedo, ruv).rgb * 0.75;
		if (hash(floor(wpos.xz / 40.0)) > 0.65) col = col * vec3(1.25, 0.8, 0.62);
		nmap = texture(roof_normal, ruv).rgb;
		rough = 0.9;
	} else if (modern) {
		float v = UV.y;
		col = vec3(0.62, 0.62, 0.6) * (0.9 + 0.1 * texture(plaster_albedo, suv).r);
		rough = 0.6;
		if (fract(v / 7.0) > 0.62 && fract(v / 7.0) < 0.9 && v > 2.0) {
			col = vec3(0.02, 0.025, 0.03); // nastro vetrato
			rough = 0.03;
			spec = 1.0;
			nmap = vec3(0.5, 0.5, 1.0);
		}
	} else {
		float u = UV.x;
		float v = UV.y;
		float h = UV2.x;
		vec3 plaster = texture(plaster_albedo, suv).rgb;
		// L'intonaco è quasi bianco: lo tingo con il colore dell'edificio, con macchie e sporco in basso.
		col = plaster * tint;
		// Intonaco vissuto: macchie larghe, rappezzi ridipinti, umidità in basso, sporco sotto il cornicione.
		float stain = fbm(vec2(u, v) / 5.0 + hash(floor(wpos.xz / 60.0)) * 30.0);
		col *= 0.82 + 0.3 * stain;
		float patch_v = hash(vec2(floor(u / 6.0), floor(v / 4.5)));
		col *= patch_v > 0.85 ? 1.07 : (patch_v < 0.1 ? 0.93 : 1.0);
		col *= mix(0.72, 1.0, smoothstep(0.2, 2.6 + stain * 1.5, v));
		col *= mix(0.78, 1.0, smoothstep(0.0, 1.3, h - v));
		float bay = floor(u / bay_w);
		float fu = fract(u / bay_w);
		float lv = floor((v - 0.4) / floor_h);
		float fv = fract((v - 0.4) / floor_h);
		bool tall = h > 6.5;
		if (v < 1.0 && tall) {
			// Zoccolo in travertino.
			col = mix(texture(stone_albedo, UV / 2.0).rgb, vec3(0.8, 0.76, 0.68), 0.6);
			nmap = texture(stone_normal, UV / 2.0).rgb;
			rough = 0.7;
		} else if (v < 3.8 && tall) {
			// Piano terra: vetrine, saracinesche, portoni in legno.
			if (fu > 0.1 && fu < 0.9 && v > 1.0 && v < 3.3) {
				float shop = hash(vec2(bay, floor(u / 40.0) + 7.0));
				if (shop < 0.5) {
					col = vec3(0.05, 0.06, 0.07) + 0.05 * hash(vec2(bay, 3.0)); // vetrina
					if (v > 0.4 && v < 2.8 && hash(vec2(bay, 21.0)) < 0.55) emit = vec3(1.0, 0.82, 0.55) * 1.6 * night; // accesa la sera
					rough = 0.05;
					spec = 0.9;
					if (v > 2.9) col = srgb(vec3(0.6, 0.15 + 0.5 * hash(vec2(bay, 9.0)), 0.12)); // insegna
				} else if (shop < 0.8) {
					col = vec3(0.25, 0.26, 0.27) * (0.85 + 0.15 * step(0.5, fract(v * 5.0))); // saracinesca
					metal = 0.6;
					rough = 0.45;
				} else {
					col = srgb(vec3(0.33, 0.21, 0.13)) * (0.8 + 0.2 * step(0.5, fract(fu * 6.0))); // portone
					rough = 0.6;
				}
			} else if (abs(v - 3.55) < 0.25) {
				col = mix(col, vec3(0.85, 0.82, 0.75), 0.7); // fascia marcapiano
			}
		} else if (v < h - 1.2 || !tall) {
			vec2 c = vec2(fu - 0.5, fv - 0.52);
			bool win = abs(c.x) < 0.19 && abs(c.y) < 0.29 && v < h - 1.0;
			bool frame = abs(c.x) < 0.24 && abs(c.y) < 0.34 && v < h - 1.0;
			float r = hash(vec2(bay, lv + floor(u / 50.0) * 13.0));
			if (win) {
				if (r < 0.3) {
					// Persiane chiuse, a listelli.
					vec3 sh = r < 0.2 ? vec3(0.18, 0.27, 0.17) : vec3(0.36, 0.22, 0.12);
					float slat = step(0.5, fract(fv * 22.0));
					col = srgb(sh) * (0.75 + 0.25 * slat);
					nmap = vec3(0.5, mix(0.35, 0.65, slat), 1.0);
					rough = 0.55;
				} else {
					// Vetro: riflette il cielo; dietro si vede una stanza vera (prospettiva che cambia).
					vec3 tw = normalize(cross(vec3(0.0, 1.0, 0.0), wnorm));
					vec3 vd = normalize(wpos - CAMERA_POSITION_WORLD);
					vec3 rd = vec3(dot(vd, tw), vd.y, max(dot(vd, -wnorm), 0.05));
					vec2 lp = vec2(c.x * bay_w, c.y * floor_h);
					float lm;
					vec3 inside = room(lp, rd, r, -0.52 * floor_h, 0.48 * floor_h, lm);
					col = vec3(0.015, 0.018, 0.022);
					float lit = hash(vec2(bay * 1.7 + 3.0, lv * 5.3 + floor(u / 50.0)));
					// Di giorno la stanza si intravede in penombra; di notte una parte delle finestre è accesa
					// (luce calda, qualcuna più fredda: la TV).
					emit = srgb(inside) * 0.07 * (1.0 - night);
					if (lit < 0.32) emit += srgb(inside) * (lit < 0.05 ? vec3(0.55, 0.65, 1.0) : vec3(1.0, 0.8, 0.55)) * (1.1 + lit * 2.0) * mix(0.7, 1.0, lm) * night;
					// Tenda chiara in alto in alcune finestre.
					if (r > 0.75 && c.y > -0.05) {
						col = srgb(vec3(0.75, 0.72, 0.62)) * 0.35;
						emit *= 0.5;
					}
					rough = 0.04;
					spec = 1.0;
					metal = 0.15;
					nmap = vec3(0.5, 0.5, 1.0);
					// Imbotte: ombra sul bordo alto e a sinistra, finestra incassata.
					float edge = smoothstep(0.29, 0.22, c.y) * smoothstep(-0.19, -0.13, c.x);
					col *= mix(0.4, 1.0, edge);
					emit *= mix(0.5, 1.0, edge);
				}
			} else if (abs(c.x) < 0.2 && c.y < -0.34 && v < h - 1.0) {
				// Colature di pioggia sotto il davanzale.
				float streak = vnoise(vec2(u * 9.0, 0.5)) * smoothstep(-0.95, -0.34, c.y);
				col *= 1.0 - 0.22 * streak;
			} else if (frame) {
				col = srgb(vec3(0.9, 0.87, 0.8)); // cornice della finestra
				rough = 0.7;
				nmap = vec3(0.5, 0.5, 1.0);
				if (c.y < -0.29) col *= 0.8; // davanzale
			} else if (fv < 0.04 && tall) {
				col *= 0.9; // marcapiano
			}
		}
	}
	ALBEDO = col;
	EMISSION = emit;
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
}
