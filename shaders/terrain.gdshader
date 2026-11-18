shader_type spatial;
// Terreno: marciapiedi e cortili in cemento, banchine erbose del Tevere, fango sul fondo.
// Quote da una texture: R = quota del terreno (rilievo vero + Tevere), G = quanto scava il Tevere (per i colori).

uniform sampler2D heights : filter_linear, repeat_disable;
uniform sampler2D relief_map : filter_linear, repeat_disable; // quota senza il Tevere: la differenza è lo scavo del fiume
uniform vec2 origin; // angolo nord-ovest in metri (x, z)
uniform vec2 extent; // dimensione coperta dalla texture in metri
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying float h; // scavo del Tevere: 0 in città, negativo su muraglioni, banchine e fondale
varying vec2 wpos;
varying float slope; // 0 in piano, 1 in verticale

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = (w.xz - origin) / extent;
	h = 0.0;
	slope = 0.0;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
	if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
		float th = texture(heights, uv).r;
		VERTEX.y += th;
		h = th - texture(relief_map, uv).r; // i colori di muraglioni, banchine e fango dipendono solo dallo scavo del fiume
		// Normale dalla pendenza: le colline prendono luce e ombra.
		vec2 px = 1.0 / vec2(textureSize(heights, 0));
		vec2 st = extent * px;
		float hl = texture(heights, uv - vec2(px.x, 0.0)).r;
		float hr = texture(heights, uv + vec2(px.x, 0.0)).r;
		float hn = texture(heights, uv - vec2(0.0, px.y)).r;
		float hs = texture(heights, uv + vec2(0.0, px.y)).r;
		NORMAL = normalize(vec3((hl - hr) / (2.0 * st.x), 1.0, (hn - hs) / (2.0 * st.y)));
		TANGENT = normalize(vec3(1.0, (hr - hl) / (2.0 * st.x), 0.0));
		BINORMAL = normalize(vec3(0.0, (hs - hn) / (2.0 * st.y), 1.0));
		slope = 1.0 - NORMAL.y;
	}
	wpos = w.xz;
}

void fragment() {
	vec2 guv = wpos / 3.0;
	vec3 pave = texture(ground_albedo, guv).rgb * vec3(0.82, 0.8, 0.76);
	pave *= 0.9 + 0.1 * hash(floor(wpos / 6.0));
	vec3 grass = texture(grass_albedo, wpos / 4.0).rgb * vec3(0.95, 0.9, 0.7);
	vec3 wall = texture(ground_albedo, vec2(wpos.x + wpos.y, h) / 2.0).rgb * vec3(0.92, 0.84, 0.7); // muraglione in travertino
	vec3 mud = vec3(0.09, 0.08, 0.05);
	float wall_t = smoothstep(-0.05, -0.6, h) * (1.0 - smoothstep(-8.6, -9.4, h));
	float bank = smoothstep(-8.6, -9.4, h);
	float wet = smoothstep(-10.3, -11.0, h);
	vec3 col = mix(pave, wall, wall_t);
	col = mix(col, mix(grass, pave * 0.8, 0.35), bank * (1.0 - wet));
	// In città: le scarpate tra strade e palazzi sono prato, quelle quasi verticali muri di contenimento.
	float city = 1.0 - smoothstep(-0.05, -0.4, h);
	float green = smoothstep(0.035, 0.08, slope) * city;
	float retain = smoothstep(0.28, 0.4, slope) * city;
	vec3 tufo = texture(ground_albedo, vec2(wpos.x + wpos.y, wpos.x * 0.37 - wpos.y * 0.21) / 2.0).rgb * vec3(0.85, 0.72, 0.55);
	col = mix(col, grass * 0.85, green * (1.0 - retain));
	col = mix(col, tufo, retain);
	ALBEDO = mix(col, mud, wet);
	NORMAL_MAP = mix(texture(ground_normal, guv).rgb, texture(grass_normal, wpos / 4.0).rgb, max(bank * (1.0 - wet), green * (1.0 - retain)));
	ROUGHNESS = mix(0.9, 0.5, wet);
}
