shader_type sky;
// Cielo romano: gradiente fisico (azzurro in alto, foschia lattiginosa all'orizzonte), alone del sole
// (diffusione di Mie), disco del sole, nuvole alte che prendono i colori del tramonto, stelle e luna di notte.
// I colori li decide DayNight (day_night.gd) a seconda dell'ora; la direzione del sole è la luce 0.

uniform vec3 top_color : source_color = vec3(0.22, 0.42, 0.75);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.76, 0.8);
uniform vec3 ground_color : source_color = vec3(0.32, 0.31, 0.3);
uniform vec3 glow_color : source_color = vec3(1.0, 0.85, 0.65); // alone intorno al sole
uniform float daylight = 1.0; // 0 notte, 1 giorno
uniform float sunset = 0.0; // 1 col sole basso: orizzonte arancio dalla parte del sole
uniform float energy = 1.0;
uniform float cloud_cover = 0.42;
uniform vec2 cloud_offset = vec2(0.0); // le nuvole scorrono piano (lo muove DayNight)

// Hash senza seno: stabile anche con coordinate grandi (col seno le nuvole venivano a quadretti).
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 sun_dir = LIGHT0_DIRECTION;
	float mu = dot(d, sun_dir);
	float sun_up = clamp(sun_dir.y * 4.0 + 0.3, 0.0, 1.0) * daylight;

	// Gradiente: l'orizzonte è più chiaro e lattiginoso, lo zenit più profondo.
	float hp = max(h, 0.0);
	vec3 col = mix(horizon_color, top_color, pow(hp, 0.45));
	// Fascia di foschia proprio sull'orizzonte.
	col = mix(col, horizon_color * 1.05, exp(-hp * 22.0) * 0.35);
	// Tramonto: l'orizzonte dalla parte del sole si accende di arancio e rosa.
	float toward = pow(max(mu * 0.5 + 0.5, 0.0), 3.0);
	vec3 dusk = mix(vec3(1.0, 0.45, 0.22), vec3(0.95, 0.55, 0.6), clamp(hp * 4.0, 0.0, 1.0));
	col = mix(col, dusk, sunset * toward * exp(-hp * 3.5) * 0.85);

	// Alone del sole (Mie): largo e morbido, più stretto vicino al disco.
	float mie = pow(max(mu, 0.0), 6.0) * 0.18 + pow(max(mu, 0.0), 48.0) * 0.45 + pow(max(mu, 0.0), 600.0) * 1.2;
	col += glow_color * mie * sun_up * LIGHT0_ENERGY * 0.6;

	// Nuvole: strato alto proiettato su un piano, più rade verso l'orizzonte.
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.22) * 1.2 + cloud_offset;
		int oct = AT_CUBEMAP_PASS ? 3 : 6;
		float n = fbm(uv * 1.6, oct);
		float wisps = fbm(uv * vec2(2.6, 1.5) + 4.0, oct); // cirri un po' allungati
		float c = smoothstep(1.0 - cloud_cover, 1.05 - cloud_cover * 0.5, n * 0.75 + wisps * 0.35);
		c *= smoothstep(0.06, 0.4, h);
		// Illuminate dal sole: bianche di giorno, rosa/arancio al tramonto, grigio-blu di notte.
		vec3 lit = mix(vec3(1.0), vec3(1.0, 0.62, 0.45), sunset);
		vec3 shade = mix(horizon_color * 0.85, vec3(0.45, 0.42, 0.55), sunset * 0.6);
		vec3 ccol = mix(shade, lit, clamp(0.55 + mu * 0.35 + (n - 0.5), 0.0, 1.0));
		ccol += glow_color * pow(max(mu, 0.0), 12.0) * 0.8 * sun_up; // bordo luminoso verso il sole
		ccol = mix(vec3(0.025, 0.03, 0.045), ccol, daylight);
		col = mix(col, ccol, c * 0.85);
	}

	// Disco del sole (di notte la luce 0 è la luna: disco più piccolo e freddo).
	float disk_size = mix(0.9997, 0.99985, daylight);
	float disk = smoothstep(disk_size, disk_size + 0.00006, mu) * step(0.0, h + 0.02);
	vec3 disk_col = mix(vec3(0.75, 0.8, 0.95) * 1.6, LIGHT0_COLOR * 30.0, daylight);
	col += disk * disk_col;

	// Stelle e un velo di bagliore della città sull'orizzonte di notte.
	if (!AT_CUBEMAP_PASS && daylight < 0.6 && h > 0.0) {
		vec2 sp = vec2(atan(d.x, d.z) * 180.0, h * 300.0);
		vec2 cell = floor(sp);
		float s = hash(cell);
		float star = step(0.9965, s) * smoothstep(0.35, 0.0, length(fract(sp) - 0.5));
		col += vec3(0.85, 0.9, 1.0) * star * (1.0 - daylight / 0.6) * smoothstep(0.05, 0.3, h) * (0.6 + 0.8 * hash(cell + 3.0));
	}
	col += vec3(0.3, 0.2, 0.12) * exp(-hp * 9.0) * (1.0 - daylight) * 0.25;

	// Sotto l'orizzonte: terra velata dalla foschia.
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, 1.0 - exp(h * 12.0));
	}
	COLOR = col * energy;
}
