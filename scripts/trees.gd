class_name TreeKit
extends RefCounted

## Alberi romani costruiti dal codice: tronco e rami veri, chioma fatta di ciuffi di foglie (piani incrociati con
## una texture di foglie trasparente, disegnata qui all'avvio), così la sagoma ha buchi e controluce come un
## albero vero. Tre specie: pino domestico (chioma a ombrello), platano (chioma alta e tonda), leccio (scuro e
## compatto). Ogni specie ha tre livelli di dettaglio (vicino, medio, lontano) che city_builder alterna con la
## distanza. La normale di ogni ciuffo punta fuori dalla chioma: la luce la avvolge morbida invece di fare a
## scacchi su ogni foglia.

const KINDS := ["pino", "platano", "leccio"]
const LODS := 3  # 0 vicino, 1 medio, 2 lontano

const ATLAS_CACHE := "user://foglie_v1.png"

static var _atlas: Texture2D


## Texture delle foglie: a sinistra un rametto di foglie larghe (platano, leccio), a destra aghi di pino.
static func atlas() -> Texture2D:
	if _atlas:
		return _atlas
	# Disegnarla costa qualche secondo: la prima volta si salva, poi si ricarica (cambiando ATLAS_VER si rifà).
	var cached := Image.load_from_file(ProjectSettings.globalize_path(ATLAS_CACHE)) if FileAccess.file_exists(ATLAS_CACHE) else null
	if cached and not cached.is_empty():
		cached.generate_mipmaps()
		_atlas = ImageTexture.create_from_image(cached)
		return _atlas
	var w := 512
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# Foglie larghe: ellissi a punta con nervatura, sparse in un cerchio attorno a dei rametti.
	var c := Vector2(128, 128)
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf() * 0.3
		_line(img, c, c + Vector2(cos(a), sin(a)) * 105.0, Color(0.28, 0.22, 0.15, 1), 2.0)
	for i in 70:
		var ang := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * 100.0
		var p := c + Vector2(cos(ang), sin(ang)) * dist
		var leaf_a := ang + rng.randf_range(-0.8, 0.8)
		var shade := rng.randf_range(0.7, 1.15)
		_leaf(img, p, leaf_a, rng.randf_range(20.0, 30.0), rng.randf_range(9.0, 13.0), Color(0.42 * shade, 0.55 * shade, 0.24 * shade))
	# Aghi di pino: tanti rametti sparsi, ognuno con un ciuffo di aghi sottili in tutte le direzioni.
	var pc := Vector2(384, 128)
	for k in 30:
		var ang0 := rng.randf() * TAU
		var base := pc + Vector2(cos(ang0), sin(ang0)) * sqrt(rng.randf()) * 78.0
		var tw := rng.randf() * TAU
		_line(img, base - Vector2(cos(tw), sin(tw)) * 12.0, base + Vector2(cos(tw), sin(tw)) * 12.0, Color(0.32, 0.24, 0.15, 1), 2.0)
		for n in 26:
			var along := rng.randf_range(-12.0, 12.0)
			var from := base + Vector2(cos(tw), sin(tw)) * along
			var na := rng.randf() * TAU
			var ln := rng.randf_range(14.0, 32.0)
			var tip := from + Vector2(cos(na), sin(na)) * ln
			if tip.distance_to(pc) > 120.0 or from.distance_to(pc) > 120.0:
				continue
			var sh := rng.randf_range(0.7, 1.25)
			_line(img, from, tip, Color(0.3 * sh, 0.43 * sh, 0.2 * sh, 1), 1.3)
	img.save_png(ATLAS_CACHE)
	img.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(img)
	return _atlas


static func _leaf(img: Image, p: Vector2, a: float, length: float, width: float, col: Color) -> void:
	var dir := Vector2(cos(a), sin(a))
	var side := Vector2(-dir.y, dir.x)
	var r := int(length * 0.6) + 2
	for y in range(int(p.y) - r, int(p.y) + r):
		for x in range(int(p.x) - r, int(p.x) + r):
			if x < 0 or y < 0 or x >= img.get_width() / 2 or y >= img.get_height():
				continue
			var q := Vector2(x, y) - p
			var u := q.dot(dir) / (length * 0.5)  # -1..1 lungo la foglia
			var v := q.dot(side) / (width * 0.5)
			var edge := 1.0 - u * u  # più stretta alle punte
			if absf(u) > 1.0 or absf(v) > edge:
				continue
			var t := col * (0.85 + 0.25 * (1.0 - absf(v) / maxf(edge, 0.01)))  # più chiara al centro
			if absf(v) < 0.08:
				t = t.lightened(0.25)  # nervatura
			t.a = 1.0
			img.set_pixel(x, y, t)


static func _line(img: Image, a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var n := int(a.distance_to(b)) + 1
	var hw := width * 0.5
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		for oy in range(-int(ceilf(hw)), int(ceilf(hw)) + 1):
			for ox in range(-int(ceilf(hw)), int(ceilf(hw)) + 1):
				var x := int(p.x) + ox
				var y := int(p.y) + oy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and Vector2(ox, oy).length() <= hw + 0.2:
					img.set_pixel(x, y, col)


## Il materiale delle chiome (uno per specie: cambia il colore).
static func leaves_material(kind: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/foliage_cards.gdshader")
	m.set_shader_parameter("leaf_tex", atlas())
	var col: Dictionary = {"pino": Color(0.62, 0.72, 0.55), "platano": Color(0.9, 0.95, 0.72), "leccio": Color(0.55, 0.62, 0.5)}
	m.set_shader_parameter("leaf_tint", col[kind] as Color)
	return m


## Mesh di un albero: superficie 0 tronco e rami (bark), superficie 1 chioma (leaves).
static func mesh(kind: String, lod: int, bark: Material, leaves: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int({"pino": 11, "platano": 23, "leccio": 37}[kind])
	var wood := []  # [Mesh, Transform3D]
	var cards := SurfaceTool.new()
	cards.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs: int = [8, 6, 5][lod]
	var n_clusters: int
	var size: float
	match kind:
		"pino":
			# Tronco alto e un po' inclinato, che in cima si apre in 4-5 bracci; chioma piatta a ombrello.
			var top := Vector3(0.7, 7.6, 0.25)
			wood.append(_limb(Vector3.ZERO, top, 0.34, 0.2, segs))
			var crown := top + Vector3(0, 2.2, 0)
			if lod < 2:
				for k in 5:
					var a := TAU * k / 5.0 + rng.randf() * 0.5
					var rr0 := rng.randf_range(1.6, 2.6)
					var end := top + Vector3(cos(a) * rr0, rng.randf_range(1.5, 1.9), sin(a) * rr0)
					wood.append(_limb(top, end, 0.17, 0.06, maxi(segs - 2, 4)))
			n_clusters = int([150, 52, 18][lod])
			size = float([2.2, 3.3, 4.6][lod])
			for i in n_clusters:
				var ang := rng.randf() * TAU
				var rr := sqrt(rng.randf()) * 4.8
				var dome := (1.0 - pow(rr / 4.8, 2.0)) * 0.9
				var p := crown + Vector3(cos(ang) * rr, dome + rng.randf_range(-0.45, 0.3), sin(ang) * rr)
				var nrm := ((p - (crown - Vector3(0, 1.4, 0))) * Vector3(1.0, 2.6, 1.0)).normalized()
				_cluster(cards, p, size * rng.randf_range(0.8, 1.2), nrm, true, rng, 0.5, 1.0)
		"platano":
			var top := Vector3(0.0, 3.8, 0.0)
			wood.append(_limb(Vector3.ZERO, top, 0.38, 0.27, segs))
			var center := Vector3(0, 8.6, 0)
			if lod < 2:
				for k in 4:
					var a := TAU * k / 4.0 + rng.randf() * 0.6
					var end := Vector3(cos(a) * rng.randf_range(1.6, 2.6), rng.randf_range(7.2, 9.4), sin(a) * rng.randf_range(1.6, 2.6))
					wood.append(_limb(top, end, 0.2, 0.07, maxi(segs - 2, 4)))
			n_clusters = int([130, 48, 18][lod])
			size = float([2.0, 3.0, 4.3][lod])
			for i in n_clusters:
				var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1), rng.randf_range(-1, 1)).normalized()
				var p := center + dir * Vector3(4.1, 3.4, 4.1) * lerpf(0.5, 1.0, sqrt(rng.randf()))
				_cluster(cards, p, size * rng.randf_range(0.8, 1.2), dir, false, rng, 0.0, 0.5)
		_:  # leccio
			var top := Vector3(0.15, 2.4, 0.0)
			wood.append(_limb(Vector3.ZERO, top, 0.3, 0.22, segs))
			var center := Vector3(0.15, 5.4, 0)
			if lod < 2:
				for k in 3:
					var a := TAU * k / 3.0 + rng.randf() * 0.6
					wood.append(_limb(top, center + Vector3(cos(a) * 1.4, 0.4, sin(a) * 1.4), 0.16, 0.06, maxi(segs - 2, 4)))
			n_clusters = int([110, 40, 15][lod])
			size = float([1.8, 2.7, 3.8][lod])
			for i in n_clusters:
				var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
				var p := center + dir * Vector3(3.3, 2.8, 3.3) * lerpf(0.45, 1.0, sqrt(rng.randf()))
				_cluster(cards, p, size * rng.randf_range(0.8, 1.2), dir, false, rng, 0.0, 0.5)
	var out := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for w: Array in wood:
		st.append_from(w[0], 0, w[1])
	st.set_material(bark)
	st.commit(out)
	cards.index()
	cards.set_material(leaves)
	cards.generate_tangents()
	cards.commit(out)
	return out


## Ramo o tronco: un cilindro da a a b, raggi r0 alla base e r1 in cima.
static func _limb(a: Vector3, b: Vector3, r0: float, r1: float, segs: int) -> Array:
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = r0
	cyl.top_radius = r1
	cyl.height = a.distance_to(b)
	cyl.radial_segments = segs
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(side, up, side.cross(up).normalized())
	return [cyl, Transform3D(basis.orthonormalized(), (a + b) * 0.5)]


## Un ciuffo: due piani incrociati con la texture delle foglie. nrm = direzione fuori dalla chioma.
## needles: aghi di pino (metà destra della texture), piani più sdraiati.
static func _cluster(st: SurfaceTool, p: Vector3, s: float, nrm: Vector3, needles: bool, rng: RandomNumberGenerator, u0: float, u1: float) -> void:
	if needles:
		u0 = 0.5
		u1 = 1.0
	var yaw := rng.randf() * TAU
	var tilt := rng.randf_range(-0.5, 0.5) if not needles else rng.randf_range(0.9, 1.4)  # i pini: ciuffi quasi orizzontali
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	var col := Color(nrm.x * 0.5 + 0.5, nrm.y * 0.5 + 0.5, nrm.z * 0.5 + 0.5, 1.0)
	for q in 2:
		var bq := b * Basis(Vector3.UP, q * PI * 0.5) if not needles else b * Basis(Vector3.FORWARD, q * 0.6 - 0.3)
		var ax := bq.x * s * 0.5
		var ay := bq.y * s * 0.5
		var n := bq.z
		var corners: Array[Vector3] = [p - ax - ay, p + ax - ay, p + ax + ay, p - ax + ay]
		var uvs: Array[Vector2] = [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0)]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])


## Sagoma per le ombre: tronco e chioma pieni, pochi triangoli, nessuna trasparenza. Proietta l'ombra al posto
## dei ciuffi (le chiome trasparenti nell'ombra costano molto). La chioma ha qualche buco per non sembrare un disco.
static func shadow_mesh(kind: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spec: Array = {
		"pino": [Vector3(0.7, 7.6, 0.25), 0.3, [[Vector3(0.7, 10.0, 0.25), Vector3(4.6, 0.9, 4.6)], [Vector3(2.4, 10.2, 1.6), Vector3(2.6, 0.7, 2.6)], [Vector3(-1.4, 10.1, -1.2), Vector3(2.8, 0.7, 2.8)]]],
		"platano": [Vector3(0, 3.8, 0), 0.32, [[Vector3(0, 8.6, 0), Vector3(3.8, 3.1, 3.8)], [Vector3(1.6, 9.6, 1.0), Vector3(2.4, 2.0, 2.4)]]],
		"leccio": [Vector3(0.15, 2.4, 0), 0.26, [[Vector3(0.15, 5.4, 0), Vector3(3.1, 2.6, 3.1)]]],
	}[kind]
	var trunk_top: Vector3 = spec[0]
	var tr: Array = _limb(Vector3.ZERO, trunk_top, spec[1], spec[1] * 0.7, 5)
	st.append_from(tr[0], 0, tr[1])
	for blob: Array in spec[2]:
		var sph := SphereMesh.new()
		sph.radial_segments = 12
		sph.rings = 6
		sph.radius = 1.0
		sph.height = 2.0
		st.append_from(sph, 0, Transform3D(Basis().scaled(blob[1]), blob[0]))
	# Con il rumore che buca l'ombra (shaders/tree_shadow.gdshader) era più bella ma costava ~8 FPS: piena.
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	st.set_material(m)
	return st.commit()
