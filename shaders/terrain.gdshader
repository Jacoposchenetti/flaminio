shader_type spatial;
// Terreno: marciapiedi e cortili in cemento, banchine erbose del Tevere, fango sul fondo.
// Il letto del fiume viene da una texture di altezze.

uniform sampler2D heights : filter_linear, repeat_disable;
uniform vec2 origin; // angolo nord-ovest in metri (x, z)
uniform vec2 extent; // dimensione coperta dalla texture in metri
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying float h;
varying vec2 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = (w.xz - origin) / extent;
	h = 0.0;
	if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
		h = texture(heights, uv).r;
	}
	VERTEX.y += h;
	wpos = w.xz;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
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
	ALBEDO = mix(col, mud, wet);
	NORMAL_MAP = mix(texture(ground_normal, guv).rgb, texture(grass_normal, wpos / 4.0).rgb, bank * (1.0 - wet));
	ROUGHNESS = mix(0.9, 0.5, wet);
}
