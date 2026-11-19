class_name LandmarkBuilder
extends RefCounted

## Monumenti ricostruiti a mano sulle piante reali di OpenStreetMap (data/city.json → "landmarks", "walls",
## "bridges"): Palazzetto dello Sport, Auditorium (tre sale e cavea), Stadio Flaminio, Porta del Popolo,
## obelischi, Mura Aureliane, ponti ad arcate e Ponte della Musica, cupole delle chiese.
## Le misure vengono dalle piante; altezze e proporzioni dalle misure reali note.

const ARCHES := {
	"Milvio": 5, "Duca": 1, "Risorgimento": 1, "Matteotti": 3, "Nenni": 3, "Margherita": 3, "Flaminio": 5,
}

var city: CityBuilder
var _stone: Material
var _concrete: Material
var _granite: Material
var _glass: Material
var _lead: Material
var _ribbed: Material
var _brick: Material
var _steel: Material
var _water: Material
var _cavea_center := Vector2.ZERO
var _gates: Array[Vector2] = []  # le mura si interrompono dove c'è una porta


func _init(c: CityBuilder) -> void:
	city = c
	_stone = c._stone_mat
	var conc := StandardMaterial3D.new()
	conc.albedo_texture = TexLib.tex("Concrete034", "color")
	conc.albedo_color = Color(0.85, 0.84, 0.82)
	conc.normal_enabled = true
	conc.normal_texture = TexLib.tex("Concrete034", "normal")
	conc.uv1_triplanar = true
	conc.uv1_scale = Vector3(0.25, 0.25, 0.25)
	conc.roughness = 0.85
	_concrete = conc
	var gran := conc.duplicate() as StandardMaterial3D
	gran.albedo_color = Color(0.72, 0.58, 0.55)  # granito rosa di Assuan
	gran.roughness = 0.5
	_granite = gran
	var gl := StandardMaterial3D.new()
	gl.albedo_color = Color(0.05, 0.07, 0.08)
	gl.metallic = 0.3
	gl.roughness = 0.05
	_glass = gl
	_lead = _panels(Color(0.45, 0.47, 0.5), 1.1, 3.0, 0.6, 0.45)
	_ribbed = _panels(Color(0.78, 0.77, 0.74), 2.2, 6.0, 0.0, 0.85)
	var br := ShaderMaterial.new()
	br.shader = load("res://shaders/brick.gdshader")
	_brick = br
	var st := StandardMaterial3D.new()
	st.albedo_color = Color(0.93, 0.93, 0.92)
	st.metallic = 0.6
	st.roughness = 0.3
	_steel = st
	_water = ShaderMaterial.new()
	(_water as ShaderMaterial).shader = load("res://shaders/water.gdshader")


func _panels(col: Color, su: float, sv: float, metal: float, rough: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/panels.gdshader")
	m.set_shader_parameter("base_color", col)
	m.set_shader_parameter("seam_u", su)
	m.set_shader_parameter("seam_v", sv)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("rough", rough)
	return m


func build() -> void:
	var lms: Array = city.data.get("landmarks", [])
	for lm: Dictionary in lms:
		if lm["t"] == "cavea":
			_cavea_center = _centroid(_pts(lm["p"]))
	for lm: Dictionary in lms:
		match String(lm["t"]):
			"palazzetto":
				_palazzetto(lm)
			"hall":
				_hall(lm)
			"cavea":
				_cavea(lm)
			"stadium":
				_stadium(lm)
			"canopy":
				_canopy(lm)
			"gate":
				_gate(lm)
			"obelisk":
				_obelisk(lm)
	for lm: Dictionary in lms:
		if lm["t"] == "gate":
			_gates.append(_centroid(_pts(lm["p"])))
	for w: Array in city.data.get("walls", []):
		_city_wall(_pts(w))
	for b: Dictionary in city.data.get("bridges", []):
		if String(b["n"]).contains("Musica"):
			_music_bridge(_pts(b["p"]))
		else:
			_arch_bridge(_pts(b["p"]), String(b["n"]))
	_maxxi()


# --- Strumenti --------------------------------------------------------------------------------


func _pts(flat: Array) -> PackedVector2Array:
	return city._pts(flat)


func _centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for q in p:
		c += q
	return c / maxf(p.size(), 1)


func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Quadrilatero a-b-c-d con normale esplicita.
func _q(acc: CityBuilder.Acc, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv := Rect2(0, 0, 1, 1)) -> void:
	acc.quad(a, b, c, d, n.normalized(), Color.WHITE, uv.position, Vector2(uv.end.x, uv.position.y), uv.end,
		Vector2(uv.position.x, uv.end.y), Vector2.ZERO)


## Quadrilatero con la normale calcolata e girata lontano da `away`.
func _qa(acc: CityBuilder.Acc, a: Vector3, b: Vector3, c: Vector3, d: Vector3, away: Vector3, uv := Rect2(0, 0, 1, 1)) -> void:
	var n := (b - a).cross(d - a)
	if n.length_squared() < 1e-10:
		n = (c - b).cross(d - b)
	if n.dot((a + b + c + d) * 0.25 - away) < 0.0:
		n = -n
	_q(acc, a, b, c, d, n, uv)


func _box(acc: CityBuilder.Acc, xf: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var c := []
	for i in 8:
		c.append(xf * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	var o := xf.origin
	for f: Array in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
		_qa(acc, c[f[0]], c[f[1]], c[f[2]], c[f[3]], o, Rect2(0, 0, size.x, size.y))


## Trave tra due punti (sezione w x d).
func _strut(acc: CityBuilder.Acc, a: Vector3, b: Vector3, w: float, d := -1.0) -> void:
	var z := b - a
	var length := z.length()
	if length < 0.01:
		return
	z /= length
	var x := z.cross(Vector3.UP)
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := x.cross(z)
	_box(acc, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, w if d < 0.0 else d, length))


func _cyl(acc: CityBuilder.Acc, base: Vector3, r0: float, r1: float, h: float, segs := 16, cap := true) -> void:
	var axis_c := base + Vector3(0, h * 0.5, 0)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_qa(acc, base + d0 * r0, base + d1 * r0, base + d1 * r1 + Vector3(0, h, 0), base + d0 * r1 + Vector3(0, h, 0), axis_c,
			Rect2(r0 * a0, 0, r0 * (a1 - a0), h))
		if cap and r1 > 0.01:
			var t := base + Vector3(0, h, 0)
			acc.tri(t, t + d0 * r1, t + d1 * r1, Vector3.UP, Color.WHITE, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


## Distanza dal punto c lungo la direzione dir fino al bordo del poligono.
func _ray(c: Vector2, dir: Vector2, poly: PackedVector2Array, far := 2000.0) -> float:
	var best := far
	for i in poly.size():
		var hit = Geometry2D.segment_intersects_segment(c, c + dir * far, poly[i], poly[(i + 1) % poly.size()])
		if hit != null:
			best = minf(best, c.distance_to(hit))
	return best


## Asse principale (lungo) del poligono: [centro, asse_u, asse_v, mezza_lunghezza, mezza_larghezza].
func _obb(p: PackedVector2Array) -> Array:
	var c := _centroid(p)
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	for q in p:
		var d := q - c
		sxx += d.x * d.x
		szz += d.y * d.y
		sxz += d.x * d.y
	var ang := 0.5 * atan2(2.0 * sxz, sxx - szz)
	var u := Vector2(cos(ang), sin(ang))
	var v := Vector2(-u.y, u.x)
	var umin := INF
	var umax := -INF
	var vmin := INF
	var vmax := -INF
	for q in p:
		var d := q - c
		umin = minf(umin, d.dot(u))
		umax = maxf(umax, d.dot(u))
		vmin = minf(vmin, d.dot(v))
		vmax = maxf(vmax, d.dot(v))
	c += u * (umin + umax) * 0.5 + v * (vmin + vmax) * 0.5
	return [c, u, v, (umax - umin) * 0.5, (vmax - vmin) * 0.5]


func _finish(acc: CityBuilder.Acc, mat: Material, node_name: String, collide := true) -> void:
	if acc.v.is_empty():
		return
	city._add_mesh(acc.mesh(mat), node_name)
	if collide:
		city._add_trimesh_body(acc.v, node_name + "_fisico")


# --- Palazzetto dello Sport (Pier Luigi Nervi, 1957) ------------------------------------------------


func _palazzetto(lm: Dictionary) -> void:
	var poly := _pts(lm["p"])
	var c := _centroid(poly)
	var r_out := 0.0
	for q in poly:
		r_out += c.distance_to(q)
	r_out /= poly.size()
	var g := city.height_at(c.x, c.y)
	var rd := r_out * 0.8  # cupola; fuori i 36 cavalletti a Y
	var spring := 7.0
	var crown := 21.0
	var hc := crown - spring
	var rs := (rd * rd + hc * hc) / (2.0 * hc)
	var dome := CityBuilder.Acc.new()
	var segs := 72
	var rings := 12
	var center3 := Vector3(c.x, g + crown - rs, c.y)
	for j in rings:
		var r0 := rd * (1.0 - float(j) / rings)
		var r1 := rd * (1.0 - float(j + 1) / rings)
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			# Bordo smerlato tra un cavalletto e l'altro.
			var sc0 := 1.3 * absf(sin(a0 * 18.0)) if j == 0 else 0.0
			var sc1 := 1.3 * absf(sin(a1 * 18.0)) if j == 0 else 0.0
			var y00 := g + crown - rs + sqrt(rs * rs - r0 * r0) + sc0
			var y01 := g + crown - rs + sqrt(rs * rs - r0 * r0) + sc1
			var y10 := g + crown - rs + sqrt(rs * rs - r1 * r1)
			var y11 := y10
			_qa(dome, Vector3(c.x + cos(a0) * r0, y00, c.y + sin(a0) * r0), Vector3(c.x + cos(a1) * r0, y01, c.y + sin(a1) * r0),
				Vector3(c.x + cos(a1) * r1, y11, c.y + sin(a1) * r1), Vector3(c.x + cos(a0) * r1, y10, c.y + sin(a0) * r1),
				center3, Rect2(a0 * rd, j * 4.0, (a1 - a0) * rd, 4.0))
	_finish(dome, _ribbed, "Palazzetto_cupola")
	# Fascia vetrata sotto la cupola e cavalletti inclinati.
	var glass := CityBuilder.Acc.new()
	_cyl(glass, Vector3(c.x, g, c.y), rd * 0.97, rd * 0.97, spring + 0.2, 72, false)
	_finish(glass, _glass, "Palazzetto_vetrate")
	var frame := CityBuilder.Acc.new()
	for i in 36:
		var a := TAU * (i + 0.5) / 36.0
		var foot := Vector3(c.x + cos(a) * r_out * 0.98, g, c.y + sin(a) * r_out * 0.98)
		var knee := Vector3(c.x + cos(a) * (rd + (r_out - rd) * 0.35), g + spring * 0.72, c.y + sin(a) * (rd + (r_out - rd) * 0.35))
		_strut(frame, foot, knee, 1.1, 0.7)
		for s: float in [-1.0, 1.0]:
			var a2: float = a + s * TAU / 36.0 * 0.5
			_strut(frame, knee, Vector3(c.x + cos(a2) * rd, g + spring + 0.4, c.y + sin(a2) * rd), 0.7, 0.5)
	# Anello di bordo.
	_cyl(frame, Vector3(c.x, g + spring - 0.2, c.y), rd + 0.6, rd + 0.6, 0.8, 72, false)
	_finish(frame, _concrete, "Palazzetto_cavalletti")


# --- Auditorium Parco della Musica (Renzo Piano, 2002) ----------------------------------------------


func _hall(lm: Dictionary) -> void:
	var poly := _pts(lm["p"])
	var ob := _obb(poly)
	var c: Vector2 = ob[0]
	var u: Vector2 = ob[1]
	var v: Vector2 = ob[2]
	var hl: float = ob[3]
	var height: float = lm.get("h", 20.0)
	# La parte alta guarda lontano dalla cavea.
	if (c + u * hl).distance_to(_cavea_center) < (c - u * hl).distance_to(_cavea_center):
		u = -u
		v = -v
	var g := city.height_at(c.x, c.y)
	var base := 4.0
	# Basamento in mattoni lungo la pianta.
	var walls := CityBuilder.Acc.new()
	var pc := _centroid(poly)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		_qa(walls, _v3(a, g), _v3(b, g), _v3(b, g + base), _v3(a, g + base), _v3(pc, g + base * 0.5))
	_finish(walls, _brick, "Auditorium_basamento_" + String(lm.get("n", "")))
	# Guscio di piombo: sezioni trasversali lungo l'asse, profilo più alto verso il retro.
	var roof := CityBuilder.Acc.new()
	var stations := 28
	var across := 14
	var rows := []
	for k in stations + 1:
		var t := float(k) / stations
		var uu := -hl + 2.0 * hl * t
		var p0 := c + u * uu
		var lo := -_ray(p0, -v, poly, 300.0)
		var hi := _ray(p0, v, poly, 300.0)
		if hi >= 300.0 or lo <= -300.0:
			lo = 0.0
			hi = 0.0
		var prof := pow(maxf(sin(PI * pow(clampf(t, 0.0, 1.0), 1.5)), 0.0), 0.55)
		var row := []
		for s in across + 1:
			var f := float(s) / across
			var vv := lerpf(lo, hi, f)
			var x := f * 2.0 - 1.0
			var y := g + base + (height - base) * prof * pow(maxf(1.0 - x * x, 0.0), 0.45)
			row.append(Vector3(p0.x + v.x * vv, y, p0.y + v.y * vv))
		rows.append(row)
	var inside := _v3(c, g)
	for k in stations:
		for s in across:
			_qa(roof, rows[k][s], rows[k][s + 1], rows[k + 1][s + 1], rows[k + 1][s], inside,
				Rect2(k * 2.0 * hl / stations, s * 3.0, 2.0 * hl / stations, 3.0))
	_finish(roof, _lead, "Auditorium_guscio_" + String(lm.get("n", "")))


## Cavea: in OpenStreetMap la pianta è la fascia delle gradinate a ferro di cavallo (aperta verso il palco).
## Dal centro del palco, per ogni direzione: dove la fascia comincia (bordo interno) e dove finisce (bordo
## esterno). Le gradinate salgono dall'interno verso l'esterno solo dove c'è la fascia; dietro e ai due
## capi la chiude un muro, così da fuori non si vede dentro.
func _cavea(lm: Dictionary) -> void:
	var poly := _pts(lm["p"])
	var c := _centroid(poly)
	var g := city.height_at(c.x, c.y)
	var acc := CityBuilder.Acc.new()
	var rays := 120
	var steps := 12
	var rise := 0.42
	var cols := []  # per raggio: [] se lì non c'è gradinata, altrimenti steps+1 punti [Vector2, quota]
	for k in rays:
		var dir := Vector2(cos(TAU * k / rays), sin(TAU * k / rays))
		var hits := _ray_all(c, dir, poly, 200.0)
		var col := []
		if hits.size() >= 2 and hits[-1] - hits[0] > 3.0:
			for j in steps + 1:
				var r := lerpf(hits[0], hits[-1], float(j) / steps)
				col.append([c + dir * r, g + 0.2 + j * rise])
		cols.append(col)
	for k in rays:
		var prev: Array = cols[k]
		var col: Array = cols[(k + 1) % rays]
		if prev.is_empty() or col.is_empty():
			continue
		for j in steps:
			var a0: Vector2 = prev[j][0]
			var b0: Vector2 = col[j][0]
			var a1: Vector2 = prev[j + 1][0]
			var b1: Vector2 = col[j + 1][0]
			var y0: float = prev[j][1]
			var y1: float = prev[j + 1][1]
			# Pedata e alzata del gradone.
			_q(acc, _v3(a0, y0), _v3(b0, y0), _v3(b1, y0), _v3(a1, y0), Vector3.UP)
			var inward := (c - (a1 + b1) * 0.5).normalized()
			_q(acc, _v3(a1, y0), _v3(b1, y0), _v3(b1, y1), _v3(a1, y1), Vector3(inward.x, 0, inward.y))
		# Primo gradino dal palco e muro di schiena fino a terra.
		var ia: Vector2 = prev[0][0]
		var ib: Vector2 = col[0][0]
		_qa(acc, _v3(ia, g - 0.5), _v3(ib, g - 0.5), _v3(ib, g + 0.2), _v3(ia, g + 0.2), _v3(c * 2.0 - (ia + ib) * 0.5, g))
		var oa: Vector2 = prev[steps][0]
		var ob: Vector2 = col[steps][0]
		var top: float = prev[steps][1]
		_qa(acc, _v3(oa, g - 0.5), _v3(ob, g - 0.5), _v3(ob, top + 1.0), _v3(oa, top + 1.0), _v3(c, g))
		# Parapetto in cima: copertina.
		var oa2 := oa + (oa - c).normalized() * 0.3
		var ob2 := ob + (ob - c).normalized() * 0.3
		_q(acc, _v3(oa, top + 1.0), _v3(ob, top + 1.0), _v3(ob2, top + 1.0), _v3(oa2, top + 1.0), Vector3.UP)
		_qa(acc, _v3(oa2, g - 0.5), _v3(ob2, g - 0.5), _v3(ob2, top + 1.0), _v3(oa2, top + 1.0), _v3(c, g))
	# Testate: dove la gradinata finisce (verso il lato aperto) un muro a gradini fino a terra.
	for k in rays:
		var col: Array = cols[k]
		if col.is_empty():
			continue
		var before: Array = cols[(k - 1 + rays) % rays]
		var after: Array = cols[(k + 1) % rays]
		if not before.is_empty() and not after.is_empty():
			continue
		var side_away := _v3(c + ((col[steps][0] as Vector2) - c).rotated(PI / 2 if before.is_empty() else -PI / 2), g)
		for j in steps:
			var p0: Vector2 = col[j][0]
			var p1: Vector2 = col[j + 1][0]
			var yj: float = col[j][1]
			_qa(acc, _v3(p0, g - 0.5), _v3(p1, g - 0.5), _v3(p1, yj), _v3(p0, yj), side_away)
		var pt: Vector2 = col[steps][0]
		var pt2 := pt + (pt - c).normalized() * 0.3
		_qa(acc, _v3(pt, g - 0.5), _v3(pt2, g - 0.5), _v3(pt2, float(col[steps][1]) + 1.0), _v3(pt, float(col[steps][1]) + 1.0), side_away)
	_finish(acc, _stone, "Auditorium_cavea")


## Tutte le distanze a cui il raggio da c in direzione dir taglia il poligono, in ordine.
func _ray_all(c: Vector2, dir: Vector2, poly: PackedVector2Array, far: float) -> Array:
	var out := []
	for i in poly.size():
		var hit = Geometry2D.segment_intersects_segment(c, c + dir * far, poly[i], poly[(i + 1) % poly.size()])
		if hit != null:
			out.append(c.distance_to(hit))
	out.sort()
	return out


# --- Stadio Flaminio (Nervi, 1959) ------------------------------------------------------------------


func _stadium(lm: Dictionary) -> void:
	var outer := _pts(lm["p"])
	var inner := PackedVector2Array()
	if lm.has("inner") and not lm["inner"].is_empty():
		inner = _pts(lm["inner"][0])
	var c := _centroid(inner if inner.size() > 2 else outer)
	var g := city.height_at(c.x, c.y)
	var acc := CityBuilder.Acc.new()
	var rays := 120
	var steps := 18
	var prev := []
	for k in rays + 1:
		var a := TAU * k / rays
		var dir := Vector2(cos(a), sin(a))
		var ro := _ray(c, dir, outer, 400.0)
		var ri := _ray(c, dir, inner, 400.0) if inner.size() > 2 else ro * 0.62
		ri = minf(ri, ro - 6.0)
		var col := [[c + dir * ri, g]]
		for j in steps + 1:
			var r := lerpf(ri + 1.5, ro - 1.0, float(j) / steps)
			col.append([c + dir * r, g + 2.4 + j * 0.72])
		col.append([c + dir * ro, g + 2.4 + steps * 0.72])
		col.append([c + dir * ro, g])
		if k > 0:
			for j in col.size() - 1:
				var a0: Vector2 = prev[j][0]
				var b0: Vector2 = col[j][0]
				var a1: Vector2 = prev[j + 1][0]
				var b1: Vector2 = col[j + 1][0]
				var y0: float = prev[j][1]
				var y1: float = prev[j + 1][1]
				var z0: float = col[j][1]
				var z1: float = col[j + 1][1]
				var n := (_v3(b0, z0) - _v3(a0, y0)).cross(_v3(a1, y1) - _v3(a0, y0)).normalized()
				var outward := Vector3(dir.x, 0, dir.y)
				var want := Vector3.UP
				if absf(n.y) < 0.5:
					want = outward if j == col.size() - 2 else -outward  # muro esterno fuori, alzate verso il campo
				if n.dot(want) < 0.0:
					n = -n
				_q(acc, _v3(a0, y0), _v3(b0, z0), _v3(b1, z1), _v3(a1, y1), n)
		prev = col
	_finish(acc, _concrete, "Stadio_Flaminio")


func _canopy(lm: Dictionary) -> void:
	var poly := _pts(lm["p"])
	var c := _centroid(poly)
	var g := city.height_at(c.x, c.y)
	var h: float = lm.get("h", 24.0)
	var idx := Geometry2D.triangulate_polygon(poly)
	var acc := CityBuilder.Acc.new()
	for i in range(0, idx.size(), 3):
		var p0 := poly[idx[i]]
		var p1 := poly[idx[i + 1]]
		var p2 := poly[idx[i + 2]]
		for side in [[h, Vector3.UP], [h - 0.8, Vector3.DOWN]]:
			acc.tri(_v3(p0, g + side[0]), _v3(p1, g + side[0]), _v3(p2, g + side[0]), side[1], Color.WHITE,
				p0 / 4.0, p1 / 4.0, p2 / 4.0, Vector2.ZERO)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		_qa(acc, _v3(a, g + h - 0.8), _v3(b, g + h - 0.8), _v3(b, g + h), _v3(a, g + h), _v3(c, g + h))
		# Pilastri lungo il bordo esterno della tribuna.
		if i % 2 == 0:
			_box(acc, Transform3D(Basis(), _v3(a, g + (h - 0.8) * 0.5)), Vector3(1.0, h - 0.8, 1.0))
	_finish(acc, _ribbed, "Stadio_copertura")


# --- Porta del Popolo -------------------------------------------------------------------------------


func _gate(lm: Dictionary) -> void:
	var ob := _obb(_pts(lm["p"]))
	var c: Vector2 = ob[0]
	var u: Vector2 = ob[1]
	var v: Vector2 = ob[2]
	var half_w: float = maxf(ob[3], 12.0)
	var half_d: float = clampf(ob[4], 3.0, 6.0)
	var g := city.height_at(c.x, c.y)
	var height := 17.5
	var arch_w := 3.2
	var arch_spring := 8.0
	var arch_top := arch_spring + arch_w
	# Prospetto con il fornice centrale, estruso nello spessore.
	var outline := PackedVector2Array([Vector2(-half_w, 0), Vector2(-arch_w, 0), Vector2(-arch_w, arch_spring)])
	for i in range(1, 12):
		var a := PI - PI * i / 12.0
		outline.append(Vector2(cos(a) * arch_w, arch_spring + sin(a) * arch_w))
	outline.append_array([Vector2(arch_w, arch_spring), Vector2(arch_w, 0), Vector2(half_w, 0), Vector2(half_w, height), Vector2(-half_w, height)])
	var to3 := func(p: Vector2, d: float) -> Vector3:
		return Vector3(c.x + u.x * p.x + v.x * d, g + p.y, c.y + u.y * p.x + v.y * d)
	var acc := CityBuilder.Acc.new()
	var idx := Geometry2D.triangulate_polygon(outline)
	for side: float in [-1.0, 1.0]:
		var n := Vector3(v.x, 0, v.y) * side
		for i in range(0, idx.size(), 3):
			acc.tri(to3.call(outline[idx[i]], half_d * side), to3.call(outline[idx[i + 1]], half_d * side),
				to3.call(outline[idx[i + 2]], half_d * side), n, Color.WHITE, outline[idx[i]], outline[idx[i + 1]],
				outline[idx[i + 2]], Vector2.ZERO)
	var mid := Vector3(c.x, g + height * 0.5, c.y)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var e := b - a
		var n2 := Vector2(e.y, -e.x).normalized()  # contorno orario: normale verso l'esterno del pieno
		var n3 := Vector3(u.x * n2.x, n2.y, u.y * n2.x)
		_q(acc, to3.call(a, -half_d), to3.call(b, -half_d), to3.call(b, half_d), to3.call(a, half_d), n3)
	# Su entrambe le facce: coppie di colonne, trabeazione, attico con lo stemma.
	for side: float in [-1.0, 1.0]:
		for x: float in [-arch_w - 1.6, -arch_w - 4.2, arch_w + 1.6, arch_w + 4.2]:
			var base: Vector3 = to3.call(Vector2(x, 0), side * (half_d + 0.55))
			_cyl(acc, base + Vector3(0, 1.6, 0), 0.55, 0.48, arch_top - 0.4, 12)
			_box(acc, Transform3D(Basis(Vector3.UP, -atan2(u.y, u.x)), base + Vector3(0, 0.8, 0)), Vector3(1.5, 1.6, 1.5))
		var tb: Vector3 = to3.call(Vector2(0, arch_top + 1.6), side * (half_d + 0.45))
		_box(acc, Transform3D(Basis(Vector3.UP, -atan2(u.y, u.x)), tb), Vector3(half_w * 2.0, 1.4, 0.9))
	var attic: Vector3 = to3.call(Vector2(0, height + 2.2), 0.0)
	var rot := Basis(Vector3.UP, -atan2(u.y, u.x))
	_box(acc, Transform3D(rot, attic), Vector3(arch_w * 2.0 + 6.0, 4.4, half_d * 2.0 - 0.6))
	_box(acc, Transform3D(rot, attic + Vector3(0, 3.0, 0)), Vector3(3.2, 1.6, 1.2))  # monti e stella dei Chigi
	_cyl(acc, attic + Vector3(0, 3.8, 0), 0.7, 0.0, 1.6, 8)
	_box(acc, Transform3D(rot, to3.call(Vector2(0, height + 0.2), 0.0)), Vector3(half_w * 2.0 + 0.6, 0.6, half_d * 2.0 + 0.6))
	_finish(acc, _stone, "Porta_del_Popolo")


# --- Obelischi --------------------------------------------------------------------------------------


func _obelisk(lm: Dictionary) -> void:
	var x: float = lm["x"]
	var z: float = lm["z"]
	var h: float = lm.get("h", 12.0)
	var g := city.height_at(x, z)
	var b: float = lm.get("base", h * 0.12)
	var ped := h * 0.33
	var shaft := h - ped
	var w0 := maxf(b * 0.55, h * 0.065)
	var acc := CityBuilder.Acc.new()
	var stone := CityBuilder.Acc.new()
	var p := Vector3(x, g, z)
	_box(stone, Transform3D(Basis(), p + Vector3(0, 0.6, 0)), Vector3(b * 2.2, 1.2, b * 2.2))
	_box(stone, Transform3D(Basis(), p + Vector3(0, 1.2 + (ped - 2.4) * 0.5, 0)), Vector3(b * 1.5, ped - 2.4, b * 1.5))
	_box(stone, Transform3D(Basis(), p + Vector3(0, ped - 0.6, 0)), Vector3(b * 1.75, 1.2, b * 1.75))
	# Fusto rastremato a sezione quadrata, con il pyramidion in cima.
	var top := shaft * 0.93
	var w1 := w0 * 0.72
	var y0 := g + ped
	var corners0 := []
	var corners1 := []
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		corners0.append(Vector3(x + cos(a) * w0 * 0.707, y0, z + sin(a) * w0 * 0.707))
		corners1.append(Vector3(x + cos(a) * w1 * 0.707, y0 + top, z + sin(a) * w1 * 0.707))
	var axis := Vector3(x, y0 + top * 0.5, z)
	var apex := Vector3(x, y0 + shaft, z)
	for i in 4:
		var j := (i + 1) % 4
		_qa(acc, corners0[i], corners0[j], corners1[j], corners1[i], axis, Rect2(0, 0, w0, top))
		var n: Vector3 = (corners1[j] - corners1[i]).cross(apex - corners1[i])
		if n.dot((corners1[i] + corners1[j]) * 0.5 - axis) < 0.0:
			n = -n
		acc.tri(corners1[i], corners1[j], apex, n.normalized(), Color.WHITE, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	_finish(acc, _granite, "Obelisco_" + String(lm.get("n", "")))
	if String(lm.get("n", "")).contains("Flaminio"):
		# Le quattro fontane dei leoni (Valadier) agli angoli del basamento.
		var water := CityBuilder.Acc.new()
		for i in 4:
			var a := TAU * i / 4.0 + PI / 4.0
			var fp := p + Vector3(cos(a), 0, sin(a)) * (b * 2.6 + 3.0)
			_cyl(stone, fp, 2.6, 2.6, 0.7, 20, false)
			_cyl(stone, fp + Vector3(0, 0.7, 0), 2.6, 2.3, 0.0, 20)
			_box(stone, Transform3D(Basis(Vector3.UP, -a), fp - Vector3(cos(a), 0, sin(a)) * 2.0 + Vector3(0, 1.4, 0)), Vector3(1.0, 1.4, 2.2))
			_cyl(water, fp + Vector3(0, 0.55, 0), 2.35, 2.35, 0.0, 20)
		_finish(water, _water, "Fontane_dei_leoni", false)
	_finish(stone, _stone, "Basamento_" + String(lm.get("n", "")))


# --- Mura Aureliane ---------------------------------------------------------------------------------


func _city_wall(src: PackedVector2Array) -> void:
	# Pezzi di 4 m al massimo: le mura salgono e scendono con il terreno (verso il Pincio).
	var line := PackedVector2Array()
	for i in src.size():
		if i > 0:
			var pieces := ceili(src[i - 1].distance_to(src[i]) / 4.0)
			for k in range(1, pieces):
				line.append(src[i - 1].lerp(src[i], float(k) / pieces))
		line.append(src[i])
	var acc := CityBuilder.Acc.new()
	var height := 12.0
	var half := 1.9
	var since := 0.0
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var d := b - a
		var length := d.length()
		if length < 0.2:
			continue
		var n := Vector2(-d.y, d.x) / length
		var near_gate := false
		for gc in _gates:
			if Geometry2D.get_closest_point_to_segment(gc, a, b).distance_to(gc) < 16.0:
				near_gate = true
		if near_gate:
			continue
		var ga := city.height_at(a.x, a.y)
		var gb := city.height_at(b.x, b.y)
		var mid := _v3((a + b) * 0.5, (ga + gb) * 0.5 + height * 0.5)
		for s: float in [-1.0, 1.0]:
			var oa := a + n * half * s
			var ob := b + n * half * s
			_qa(acc, _v3(oa, ga - 0.5), _v3(ob, gb - 0.5), _v3(ob, gb + height), _v3(oa, ga + height), mid)
		_q(acc, _v3(a + n * half, ga + height), _v3(b + n * half, gb + height), _v3(b - n * half, gb + height),
			_v3(a - n * half, ga + height), Vector3.UP)
		# Torri quadrate circa ogni 30 m.
		since += length
		while since > 30.0:
			since -= 30.0
			var t := 1.0 - since / length
			var p := a.lerp(b, clampf(t, 0.0, 1.0))
			var gp := city.height_at(p.x, p.y)
			_box(acc, Transform3D(Basis(Vector3.UP, -atan2(d.y, d.x)), _v3(p + n * 2.0, gp + 7.5)), Vector3(7.0, 16.0, 7.5))
	_finish(acc, _brick, "Mura_Aureliane")


# --- Ponti ------------------------------------------------------------------------------------------


func _arch_bridge(poly: PackedVector2Array, bname: String) -> void:
	var ob := _obb(poly)
	var c: Vector2 = ob[0]
	var u: Vector2 = ob[1]
	var v: Vector2 = ob[2]
	var hl: float = ob[3]
	var hw: float = ob[4]
	if hl < 8.0:
		return
	var arches := 3
	for key: String in ARCHES:
		if bname.contains(key):
			arches = ARCHES[key]
	var deck := 0.0
	var crown := -2.2
	var spring := -10.0
	var bed: float = city.data.get("river_depth", 13.5) * -1.0
	var pier := 5.0 if arches > 1 else 0.0
	var span := (2.0 * hl - pier * (arches - 1)) / arches
	var stone := _stone
	if bname.contains("Milvio"):
		stone = _brick
	var acc := CityBuilder.Acc.new()
	var to3 := func(along: float, across: float, y: float) -> Vector3:
		var p := c + u * along + v * across
		return Vector3(p.x, y, p.y)
	# Profilo inferiore (intradosso) campionato ogni metro.
	var bottom := func(x: float) -> float:
		var local := x + hl
		for k in arches:
			var s0 := k * (span + pier)
			if local >= s0 and local <= s0 + span:
				var t := (local - s0) / span * 2.0 - 1.0
				return spring + (crown - spring) * sqrt(maxf(1.0 - t * t, 0.0))
		return bed
	var samples := maxi(8, int(2.0 * hl))
	var prev_x := -hl
	var prev_b: float = bottom.call(-hl)
	for i in range(1, samples + 1):
		var x := -hl + 2.0 * hl * i / samples
		var bt: float = bottom.call(x)
		for s: float in [-1.0, 1.0]:
			var n := Vector3(v.x, 0, v.y) * s
			# Fianco (timpano) dal parapetto all'arco o alla pila.
			_q(acc, to3.call(prev_x, hw * s, prev_b), to3.call(x, hw * s, bt), to3.call(x, hw * s, deck + 1.1),
				to3.call(prev_x, hw * s, deck + 1.1), n, Rect2(prev_x, prev_b, x - prev_x, deck + 1.1 - prev_b))
			# Parapetto: faccia interna e copertina.
			_q(acc, to3.call(prev_x, (hw - 0.45) * s, deck), to3.call(x, (hw - 0.45) * s, deck),
				to3.call(x, (hw - 0.45) * s, deck + 1.1), to3.call(prev_x, (hw - 0.45) * s, deck + 1.1), -n)
			_q(acc, to3.call(prev_x, hw * s, deck + 1.1), to3.call(x, hw * s, deck + 1.1),
				to3.call(x, (hw - 0.45) * s, deck + 1.1), to3.call(prev_x, (hw - 0.45) * s, deck + 1.1), Vector3.UP)
		# Intradosso tra i due fianchi.
		_q(acc, to3.call(prev_x, -hw, prev_b), to3.call(x, -hw, bt), to3.call(x, hw, bt), to3.call(prev_x, hw, prev_b), Vector3.DOWN)
		# Piano di calpestio (marciapiedi; la carreggiata ci passa sopra).
		_q(acc, to3.call(prev_x, -hw + 0.45, deck + 0.02), to3.call(x, -hw + 0.45, deck + 0.02),
			to3.call(x, hw - 0.45, deck + 0.02), to3.call(prev_x, hw - 0.45, deck + 0.02), Vector3.UP)
		prev_x = x
		prev_b = bt
	_finish(acc, stone, "Ponte_" + bname)


## Ponte della Musica (2011): due archi d'acciaio bianchi ribassati sopra un impalcato sottile.
func _music_bridge(poly: PackedVector2Array) -> void:
	var ob := _obb(poly)
	var c: Vector2 = ob[0]
	var u: Vector2 = ob[1]
	var v: Vector2 = ob[2]
	var hl: float = ob[3]
	var hw: float = ob[4]
	var to3 := func(along: float, across: float, y: float) -> Vector3:
		var p := c + u * along + v * across
		return Vector3(p.x, y, p.y)
	var steel := CityBuilder.Acc.new()
	var deck := CityBuilder.Acc.new()
	var n := 40
	for i in n:
		var x0 := -hl + 2.0 * hl * i / n
		var x1 := -hl + 2.0 * hl * (i + 1) / n
		_q(deck, to3.call(x0, -hw, 0.02), to3.call(x1, -hw, 0.02), to3.call(x1, hw, 0.02), to3.call(x0, hw, 0.02), Vector3.UP)
		_q(deck, to3.call(x0, -hw, -1.2), to3.call(x1, -hw, -1.2), to3.call(x1, hw, -1.2), to3.call(x0, hw, -1.2), Vector3.DOWN)
		for s: float in [-1.0, 1.0]:
			_q(deck, to3.call(x0, hw * s, -1.2), to3.call(x1, hw * s, -1.2), to3.call(x1, hw * s, 0.02), to3.call(x0, hw * s, 0.02),
				Vector3(v.x, 0, v.y) * s)
			# Archi ribassati, leggermente inclinati verso l'esterno; tiranti verticali.
			var t0 := float(i) / n * 2.0 - 1.0
			var t1 := float(i + 1) / n * 2.0 - 1.0
			var ya := -8.0 + 22.0 * (1.0 - t0 * t0)
			var yb := -8.0 + 22.0 * (1.0 - t1 * t1)
			var off := (hw + 1.2 + 2.0 * (1.0 - t0 * t0)) * s
			var off2 := (hw + 1.2 + 2.0 * (1.0 - t1 * t1)) * s
			_strut(steel, to3.call(x0, off, ya), to3.call(x1, off2, yb), 1.1)
			if ya > 1.5 and i % 2 == 0:
				_strut(steel, to3.call(x0, off, ya), to3.call(x0, hw * s, 0.0), 0.12)
	_finish(deck, _steel, "Ponte_della_Musica_impalcato")
	_finish(steel, _steel, "Ponte_della_Musica_archi")


## Cupola su tamburo per le chiese (chiamata da CityBuilder per ogni edificio con "dome").
static func dome(acc: CityBuilder.Acc, c: Vector2, base_y: float, r: float) -> void:
	var drum_h := r * 0.55
	var segs := 24
	var center := Vector3(c.x, base_y + drum_h, c.y)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b := Vector3(c.x, base_y, c.y)
		acc.quad(b + d0 * r, b + d1 * r, b + d1 * r + Vector3(0, drum_h, 0), b + d0 * r + Vector3(0, drum_h, 0),
			((d0 + d1) * 0.5).normalized(), Color.WHITE, Vector2(a0 * r, 0), Vector2(a1 * r, 0), Vector2(a1 * r, drum_h),
			Vector2(a0 * r, drum_h), Vector2.ZERO)
		for j in 8:
			var e0 := PI * 0.5 * j / 8.0
			var e1 := PI * 0.5 * (j + 1) / 8.0
			var p00 := center + (d0 * cos(e0) + Vector3(0, sin(e0) * 1.15, 0)) * r
			var p01 := center + (d1 * cos(e0) + Vector3(0, sin(e0) * 1.15, 0)) * r
			var p11 := center + (d1 * cos(e1) + Vector3(0, sin(e1) * 1.15, 0)) * r
			var p10 := center + (d0 * cos(e1) + Vector3(0, sin(e1) * 1.15, 0)) * r
			var nn := ((p00 + p11) * 0.5 - center).normalized()
			acc.quad(p00, p01, p11, p10, nn, Color.WHITE, Vector2(a0 * r, e0 * r), Vector2(a1 * r, e0 * r),
				Vector2(a1 * r, e1 * r), Vector2(a0 * r, e1 * r), Vector2.ZERO)
	# Lanterna.
	var top := center + Vector3(0, r * 1.15, 0)
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var d0 := Vector3(cos(a0), 0, sin(a0)) * r * 0.18
		var d1 := Vector3(cos(a1), 0, sin(a1)) * r * 0.18
		acc.quad(top + d0, top + d1, top + d1 + Vector3(0, r * 0.35, 0), top + d0 + Vector3(0, r * 0.35, 0),
			((d0 + d1) * 0.5).normalized(), Color.WHITE, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		acc.tri(top + d0 + Vector3(0, r * 0.35, 0), top + d1 + Vector3(0, r * 0.35, 0), top + Vector3(0, r * 0.55, 0),
			((d0 + d1) * 0.5).normalized() + Vector3.UP, Color.WHITE, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


# --- MAXXI (Zaha Hadid, 2010) ------------------------------------------------------------------------
## Nastri di cemento chiaro lunghi e curvi che si intrecciano: il corpo lungo a nord, l'ala est che scende
## verso via Guido Reni, e la galleria 5 sollevata a sbalzo sopra la piazza con la grande vetrata nera in
## fondo. Sul tetto le travi parallele dei lucernari. Le linee centrali sono ricavate dalla pianta di
## OpenStreetMap (relazione MAXXI) e smussate con una spline.

const MAXXI_A := [Vector2(-628, -716), Vector2(-590, -727), Vector2(-552, -737), Vector2(-505, -746), Vector2(-466, -754)]
const MAXXI_B := [Vector2(-466, -754), Vector2(-450, -728), Vector2(-441, -700), Vector2(-427, -664)]
const MAXXI_C := [Vector2(-548, -738), Vector2(-536, -712), Vector2(-524, -684), Vector2(-512, -657)]
## Il lotto del MAXXI (OpenStreetMap, relazione 8748353).
const MAXXI_SITE := [Vector2(-448.1, -783.2), Vector2(-433.4, -736.3), Vector2(-426.6, -714.5), Vector2(-406.7, -651.1),
	Vector2(-416.9, -648.0), Vector2(-432.1, -643.4), Vector2(-440.1, -641.0), Vector2(-461.6, -634.4), Vector2(-518.7, -617.5),
	Vector2(-524.8, -637.8), Vector2(-549.2, -716.3), Vector2(-625.0, -694.4), Vector2(-710.1, -669.6), Vector2(-711.7, -675.2),
	Vector2(-719.7, -703.6), Vector2(-721.9, -711.2), Vector2(-638.9, -735.7), Vector2(-632.6, -726.7), Vector2(-552.3, -752.1),
	Vector2(-520.8, -762.1), Vector2(-484.7, -760.1), Vector2(-453.7, -770.4), Vector2(-450.5, -771.4), Vector2(-453.5, -781.2)]


## Gli edifici generici dentro il lotto del MAXXI (a est della vecchia caserma): city_builder non li costruisce.
static func in_maxxi(pts: PackedVector2Array) -> bool:
	var c := Vector2.ZERO
	for q in pts:
		c += q
	c /= pts.size()
	return c.x > -640.0 and Geometry2D.is_point_in_polygon(c, PackedVector2Array(MAXXI_SITE))


func _maxxi() -> void:
	var conc := _panels(Color(0.86, 0.85, 0.82), 4.5, 1.8, 0.0, 0.7)  # cemento a vista con i giunti dei casseri
	var walls := CityBuilder.Acc.new()
	var glass := CityBuilder.Acc.new()
	var fins := CityBuilder.Acc.new()
	var ground := INF
	for path: Array in [MAXXI_A, MAXXI_B, MAXXI_C]:
		for q: Vector2 in path:
			ground = minf(ground, city.height_at(q.x, q.y))
	var g := ground - 0.3
	# Corpo lungo: due piani di nastri, quello alto un po' più largo e spostato (gli sbalzi di Zaha).
	_ribbon(walls, glass, _spline(MAXXI_A), 30.0, g, g + 4.5, 0.0, true)
	_ribbon(walls, glass, _spline(MAXXI_A), 30.0, g + 4.5, g + 10.0, 0.0, false)
	_ribbon(walls, glass, _spline(MAXXI_A), 33.0, g + 10.0, g + 18.0, 1.5, false)
	# Ala est, più bassa, con il piano terra vetrato.
	_ribbon(walls, glass, _spline(MAXXI_B), 26.0, g, g + 4.5, 0.0, true)
	_ribbon(walls, glass, _spline(MAXXI_B), 26.0, g + 4.5, g + 14.0, 0.0, false)
	# Galleria 5: sollevata, a sbalzo sulla piazza, chiusa da una vetrata nera.
	var c_path := _spline(MAXXI_C)
	_ribbon(walls, glass, c_path, 22.0, g + 11.0, g + 20.0, 0.0, false, true)
	# Pilastri sottili sotto la galleria (solo nella prima metà: la punta è a sbalzo).
	for i in range(0, int(c_path.size() * 0.45), 4):
		var q: Vector2 = c_path[i]
		_cyl(walls, Vector3(q.x, g, q.y), 0.45, 0.45, 11.0, 10, false)
	# Tetto: travi parallele dei lucernari lungo i nastri.
	for spec: Array in [[MAXXI_A, 33.0, g + 18.0], [MAXXI_B, 26.0, g + 14.0], [MAXXI_C, 22.0, g + 20.0]]:
		var path := _spline(spec[0])
		var w: float = spec[1]
		var k := -w * 0.5 + 2.0
		while k < w * 0.5 - 1.5:
			for i in path.size() - 1:
				var a: Vector2 = path[i]
				var b: Vector2 = path[i + 1]
				var nrm := (b - a).orthogonal().normalized()
				_strut(fins, Vector3(a.x, 0, a.y) + Vector3(nrm.x, 0, nrm.y) * k + Vector3(0, spec[2] + 0.5, 0),
					Vector3(b.x, 0, b.y) + Vector3(nrm.x, 0, nrm.y) * k + Vector3(0, spec[2] + 0.5, 0), 0.25, 1.0)
			k += 2.6
	_finish(walls, conc, "MAXXI")
	var gl := StandardMaterial3D.new()
	gl.albedo_color = Color(0.02, 0.025, 0.03)
	gl.metallic = 0.4
	gl.roughness = 0.04
	_finish(glass, gl, "MAXXI_vetri")
	var fin_mat := StandardMaterial3D.new()
	fin_mat.albedo_color = Color(0.9, 0.9, 0.88)
	fin_mat.roughness = 0.6
	_finish(fins, fin_mat, "MAXXI_travi", false)


## Spline di Catmull-Rom che passa per i punti, un campione ogni ~4 m.
func _spline(ctrl: Array) -> Array:
	var out := []
	for i in ctrl.size() - 1:
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(i + 2, ctrl.size() - 1)]
		var n := maxi(int(p1.distance_to(p2) / 4.0), 2)
		for k in n:
			var t := float(k) / n
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[ctrl.size() - 1])
	return out


## Nastro: sezione rettangolare larga w da y0 a y1 lungo il percorso. shift sposta il nastro di lato;
## glazed: piano terra a vetri (rientrato); glass_end: la testata finale è una vetrata nera.
func _ribbon(acc: CityBuilder.Acc, glass: CityBuilder.Acc, path: Array, w: float, y0: float, y1: float, shift: float,
		glazed: bool, glass_end := false) -> void:
	var left := []
	var right := []
	for i in path.size():
		var a: Vector2 = path[maxi(i - 1, 0)]
		var b: Vector2 = path[mini(i + 1, path.size() - 1)]
		var nrm := (b - a).orthogonal().normalized()
		var p: Vector2 = path[i] + nrm * shift
		left.append(p + nrm * w * 0.5)
		right.append(p - nrm * w * 0.5)
	var inset := 1.5 if glazed else 0.0
	var u := 0.0
	for i in path.size() - 1:
		var seg: float = (path[i] as Vector2).distance_to(path[i + 1])
		var uv := Rect2(u, y0, seg, y1 - y0)
		for side: Array in [[left, 1.0], [right, -1.0]]:
			var pts: Array = side[0]
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var c: Vector2 = path[i]
			var d: Vector2 = path[i + 1]
			if inset > 0.0:
				a = a + (c - a).normalized() * inset
				b = b + (d - b).normalized() * inset
			var target := glass if glazed else acc
			_qa(target, _v3(a, y0), _v3(b, y0), _v3(b, y1), _v3(a, y1), _v3((c + d) * 0.5, (y0 + y1) * 0.5), uv)
		var la: Vector2 = left[i]
		var lb: Vector2 = left[i + 1]
		var ra: Vector2 = right[i]
		var rb: Vector2 = right[i + 1]
		_q(acc, _v3(la, y1), _v3(lb, y1), _v3(rb, y1), _v3(ra, y1), Vector3.UP, uv)
		_q(acc, _v3(la, y0), _v3(lb, y0), _v3(rb, y0), _v3(ra, y0), Vector3.DOWN, uv)
		u += seg
	# Testate.
	for end: Array in [[0, 1], [path.size() - 1, path.size() - 2]]:
		var i: int = end[0]
		var l: Vector2 = left[i]
		var r: Vector2 = right[i]
		var inward: Vector2 = path[end[1]]
		var is_glass := glass_end and i == path.size() - 1
		_qa(glass if (is_glass or glazed) else acc, _v3(l, y0), _v3(r, y0), _v3(r, y1), _v3(l, y1), _v3(inward, (y0 + y1) * 0.5),
			Rect2(0, y0, w, y1 - y0))
