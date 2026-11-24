shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Chiome fatte di ciuffi (scripts/trees.gd): texture di foglie trasparente, normale "della chioma" presa dal
// colore del vertice (luce morbida e avvolgente), colore variato per albero, controluce e vento.

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 leaf_tint : source_color = vec3(0.9, 0.95, 0.72);

varying float tree_rand;
varying vec3 canopy_n;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	tree_rand = hash3(floor(origin));
	canopy_n = COLOR.rgb * 2.0 - 1.0;
	// Vento: la chioma oscilla tutta insieme, i ciuffi tremano un po' ognuno per conto suo.
	float h = clamp((VERTEX.y - 2.5) / 9.0, 0.0, 1.0);
	float sway = sin(TIME * 0.9 + origin.x * 0.11 + origin.z * 0.07) * 0.10;
	float flutter = sin(TIME * 3.1 + dot(VERTEX, vec3(1.7, 2.3, 1.1))) * 0.035;
	VERTEX.x += (sway + flutter) * h;
	VERTEX.z += flutter * 0.7 * h;
	// Luce: per lo più la normale della chioma, un po' quella del ciuffo.
	NORMAL = normalize(mix(NORMAL, canopy_n, 0.85));
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	// Da lontano le mipmap sfumano l'alfa: lo rinforzo per non far "sparire" la chioma.
	float mip = max(0.0, log2(max(length(dFdx(UV * 512.0)), length(dFdy(UV * 512.0)))));
	ALPHA = clamp(t.a * (1.0 + mip * 0.35), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 col = t.rgb * leaf_tint * (0.8 + 0.4 * tree_rand);
	// Più scuro dentro e sotto la chioma (occlusione finta), più chiaro e giallino in cima.
	float up = canopy_n.y * 0.5 + 0.5;
	col *= mix(0.45, 1.05, up);
	col = mix(col, col * vec3(1.15, 1.1, 0.75), smoothstep(0.7, 1.0, up) * 0.4);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.75;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
