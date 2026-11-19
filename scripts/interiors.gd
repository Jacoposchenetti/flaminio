class_name Interiors
extends RefCounted

## Palazzi esplorabili: per alcuni edifici veri (scelti vicino ai luoghi principali) la sagoma piena viene
## sostituita da un palazzo vuoto con porta, solai, scale, finestre aperte (ci si affaccia e si spara),
## luci, qualche mobile e il tetto praticabile. Sono segnati sulla mappa con "E".

const FLOOR_H := 3.2
const BAY := 3.4
const WALL := 0.3
const COUNT := 7
## Luoghi vicino ai quali cercare un palazzo (più il punto di partenza).
const NEAR := [Vector2(318, 1303), Vector2(200, -700), Vector2(-145, -786), Vector2(-461, -1447), Vector2(-13, -499), Vector2(-780, -377)]

var city: CityBuilder
var _wall_mat: StandardMaterial3D
var _in_mat: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _furn_mat: StandardMaterial3D


## Sceglie gli edifici esplorabili e li segna con "enter" (CityBuilder non li costruisce pieni).
static func pick(data: Dictionary, spawn: Vector3) -> Array:
	var targets := [Vector2(spawn.x, spawn.z)]
	targets.append_array(NEAR)
	var chosen := []
	for t: Vector2 in targets:
		var best: Dictionary = {}
		var best_d := 350.0
		for b: Dictionary in data["buildings"]:
			if b.has("enter") or b.has("part") or b.has("dome") or b.get("style", "") != "":
				continue
			if LandmarkBuilder.in_maxxi(city_pts(b["p"])):
				continue
			var p: Array = b["p"]
			var n := p.size() / 2
			if n < 4 or n > 9:
				continue
			var h: float = b["h"]
			if h < 12.0 or h > 26.0:
				continue
			var pts := PackedVector2Array()
			for i in n:
				pts.append(Vector2(p[i * 2], p[i * 2 + 1]))
			var area := absf(_area(pts))
			if area < 220.0 or area > 1100.0 or Geometry2D.triangulate_polygon(pts).is_empty():
				continue
			var c := _centroid(pts)
			var d := c.distance_to(t)
			if d < best_d and _stair_rect(pts).size() == 4:
				var far := true
				for o: Dictionary in chosen:
					if _centroid(_poly(o)).distance_to(c) < 120.0:
						far = false
				if far:
					best_d = d
					best = b
		if not best.is_empty():
			best["enter"] = 1
			chosen.append(best)
		if chosen.size() >= COUNT:
			break
	return chosen


static func _poly(b: Dictionary) -> PackedVector2Array:
	var p: Array = b["p"]
	var out := PackedVector2Array()
	for i in p.size() / 2:
		out.append(Vector2(p[i * 2], p[i * 2 + 1]))
	return out


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return a * 0.5


static func _centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for q in p:
		c += q
	return c / maxf(p.size(), 1)


## Vano scala lungo il lato più lungo, all'interno: [a, b, c, d] (a-b sul muro), o [] se non ci sta.
static func _stair_rect(p: PackedVector2Array) -> PackedVector2Array:
	var best_i := 0
	var best_l := 0.0
	for i in p.size():
		var l := p[i].distance_to(p[(i + 1) % p.size()])
		if l > best_l:
			best_l = l
			best_i = i
	if best_l < 8.0:
		return PackedVector2Array()
	var a := p[best_i]
	var b := p[(best_i + 1) % p.size()]
	var u := (b - a) / best_l
	var n := Vector2(-u.y, u.x)
	if not Geometry2D.is_point_in_polygon((a + b) * 0.5 + n * 2.0, p):
		n = -n
	var mid := (a + b) * 0.5
	var r := PackedVector2Array([
		mid - u * 3.0 + n * (WALL + 0.05), mid + u * 3.0 + n * (WALL + 0.05),
		mid + u * 3.0 + n * (WALL + 2.4), mid - u * 3.0 + n * (WALL + 2.4),
	])
	for q in r:
		if not Geometry2D.is_point_in_polygon(q, p):
			return PackedVector2Array()
	return r


func _init(c: CityBuilder) -> void:
	city = c
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_texture = TexLib.tex("Plaster001", "color")
	_wall_mat.normal_enabled = true
	_wall_mat.normal_texture = TexLib.tex("Plaster001", "normal")
	_wall_mat.uv1_triplanar = true
	_wall_mat.uv1_scale = Vector3(0.3, 0.3, 0.3)
	_in_mat = _wall_mat.duplicate() as StandardMaterial3D
	_in_mat.albedo_color = Color(0.93, 0.9, 0.84)
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.albedo_texture = TexLib.tex("PavingStones046", "color")
	_floor_mat.albedo_color = Color(0.85, 0.75, 0.62)
	_floor_mat.uv1_triplanar = true
	_floor_mat.uv1_scale = Vector3(0.6, 0.6, 0.6)
	_furn_mat = StandardMaterial3D.new()
	_furn_mat.albedo_color = Color(0.45, 0.3, 0.2)


## Costruisce il palazzo esplorabile e restituisce [x, z, nome] per la mappa (davanti alla porta).
func build(b: Dictionary) -> Array:
	var pts := _poly(b)
	if _area(pts) < 0.0:
		pts.reverse()  # antiorario: le normali esterne vengono a destra dei lati
	var cc: Array = city.data["colors"][int(b["c"])]
	var outside := _wall_mat.duplicate() as StandardMaterial3D
	outside.albedo_color = Color(cc[0], cc[1], cc[2])
	var c := _centroid(pts)
	var g := city.height_at(c.x, c.y)
	var floors := maxi(2, int(float(b["h"]) / FLOOR_H))
	var top := g + floors * FLOOR_H
	var stair := _stair_rect(pts)
	# La porta sta sul lato più lungo che guarda verso la strada più vicina (qui: il primo lato non della scala).
	var door_edge := _door_edge(pts)
	var ext := CityBuilder.Acc.new()
	var inn := CityBuilder.Acc.new()
	var slabs := CityBuilder.Acc.new()
	var ceilings := CityBuilder.Acc.new()
	var furn := CityBuilder.Acc.new()
	for i in pts.size():
		var a := pts[i]
		var e := pts[(i + 1) % pts.size()]
		var length := a.distance_to(e)
		if length < 0.3:
			continue
		var u := (e - a) / length
		var n_out := Vector2(u.y, -u.x)  # poligono antiorario (asse z verso sud): esterno a destra
		if Geometry2D.is_point_in_polygon((a + e) * 0.5 + n_out * 0.5, pts):
			n_out = -n_out
		for f in floors + 1:
			var y0 := g + f * FLOOR_H
			var band := FLOOR_H if f < floors else 1.1  # all'ultimo "piano" solo il parapetto del tetto
			var holes := []
			if f < floors:
				var bays := int(length / BAY)
				for k in bays:
					var uc := (k + 0.5) * length / bays
					if f == 0 and i == door_edge and k == bays / 2:
						holes.append([uc - 0.85, uc + 0.85, 0.0, 2.5])  # portone
					elif f > 0 or i != door_edge:
						holes.append([uc - 0.6, uc + 0.6, 0.95, 2.45])  # finestra
			_wall_with_holes(ext, inn, a, u, n_out, length, y0, band, holes)
	# Solai con il vano scala, e il tetto.
	# Il buco del vano scala arriva fino al muro: così il solaio ha una "tacca" e non un buco interno.
	var inward := (stair[3] - stair[0]).normalized()
	var hole := PackedVector2Array([stair[0] - inward * 0.8, stair[1] - inward * 0.8, stair[2], stair[3]])
	var cw := Geometry2D.is_polygon_clockwise(pts)
	for f in range(1, floors + 1):
		var y := g + f * FLOOR_H
		for poly in Geometry2D.clip_polygons(pts, hole):
			if Geometry2D.is_polygon_clockwise(poly) == cw:
				_slab(slabs, poly, y, ceilings)
	_slab(slabs, pts, g + 0.02)  # pavimento del piano terra
	# Scale: rampe sovrapposte nello stesso vano, una per piano.
	var stairs := CityBuilder.Acc.new()
	var body := StaticBody3D.new()
	body.name = "Scale_%d" % int(b["id"])
	city.add_child(body)
	for f in floors:
		_flight(stairs, body, stair, g + f * FLOOR_H)
	# Luci e mobili.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b["id"])
	for f in floors:
		var y := g + f * FLOOR_H
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.86, 0.68)
		light.light_energy = 1.4
		light.omni_range = 14.0
		light.position = Vector3(c.x, y + 2.7, c.y)
		light.distance_fade_enabled = true
		light.distance_fade_begin = 90.0
		light.distance_fade_length = 30.0
		city.add_child(light)
		for k in 4:
			var p := c + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
			if not Geometry2D.is_point_in_polygon(p, pts) or Geometry2D.is_point_in_polygon(p, stair):
				continue
			var size := Vector3(rng.randf_range(0.8, 2.2), rng.randf_range(0.45, 0.9), rng.randf_range(0.6, 1.2))
			_box(furn, Vector3(p.x, y + size.y * 0.5 + 0.02, p.y), size, rng.randf() * PI)
	var tag := "Edificio_%d" % int(b["id"])
	city._add_mesh(ext.mesh(outside), tag + "_fuori")
	city._add_mesh(inn.mesh(_in_mat), tag + "_dentro")
	city._add_mesh(slabs.mesh(_floor_mat), tag + "_solai")
	city._add_mesh(ceilings.mesh(_in_mat), tag + "_soffitti")
	city._add_mesh(stairs.mesh(_floor_mat), tag + "_scale")
	city._add_mesh(furn.mesh(_furn_mat), tag + "_mobili")
	var faces := ext.v.duplicate()
	faces.append_array(inn.v)
	faces.append_array(slabs.v)
	faces.append_array(furn.v)
	city._add_trimesh_body(faces, tag + "_fisico")
	# Insegna e punto per la mappa davanti alla porta.
	var da := pts[door_edge]
	var db := pts[(door_edge + 1) % pts.size()]
	var dn := Vector2((db - da).y, -(db - da).x).normalized()
	if Geometry2D.is_point_in_polygon((da + db) * 0.5 + dn * 0.5, pts):
		dn = -dn
	var door := (da + db) * 0.5 + dn * 1.5
	var label := Label3D.new()
	label.text = "Edificio esplorabile"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.012
	label.modulate = Color(1.0, 0.85, 0.3)
	label.position = Vector3(door.x, g + 3.2, door.y)
	label.visibility_range_end = 90.0
	city.add_child(label)
	return [door.x, door.y, "Edificio esplorabile (%d piani)" % floors, "enter", c.x, c.y, g, floors, stair[0], stair[1], stair[3]]


func _door_edge(pts: PackedVector2Array) -> int:
	var best := 0
	var best_l := -1.0
	var stair_edge := 0
	var sl := 0.0
	for i in pts.size():
		var l := pts[i].distance_to(pts[(i + 1) % pts.size()])
		if l > sl:
			sl = l
			stair_edge = i
	for i in pts.size():
		var l := pts[i].distance_to(pts[(i + 1) % pts.size()])
		if i != stair_edge and l > best_l and l > 4.0:
			best_l = l
			best = i
	return best


## Muro spesso con aperture: holes = [[u0, u1, y0, y1]] in metri lungo il lato e dal piede della fascia.
func _wall_with_holes(ext: CityBuilder.Acc, inn: CityBuilder.Acc, a: Vector2, u: Vector2, n_out: Vector2,
		length: float, y0: float, band: float, holes: Array) -> void:
	holes.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	# Rettangoli pieni: fascia sotto e sopra ogni apertura, pilastri tra le aperture.
	var rects := []
	var cur := 0.0
	for h: Array in holes:
		rects.append([cur, h[0], 0.0, band])
		rects.append([h[0], h[1], 0.0, h[2]])
		rects.append([h[0], h[1], h[3], band])
		cur = h[1]
	rects.append([cur, length, 0.0, band])
	var n3 := Vector3(n_out.x, 0, n_out.y)
	for r: Array in rects:
		if r[1] - r[0] < 0.01 or r[3] - r[2] < 0.01:
			continue
		var p0 := a + u * float(r[0])
		var p1 := a + u * float(r[1])
		var po0 := p0
		var po1 := p1
		var pi0 := p0 - n_out * WALL
		var pi1 := p1 - n_out * WALL
		var ya := y0 + float(r[2])
		var yb := y0 + float(r[3])
		_quad(ext, Vector3(po0.x, ya, po0.y), Vector3(po1.x, ya, po1.y), Vector3(po1.x, yb, po1.y), Vector3(po0.x, yb, po0.y), n3)
		_quad(inn, Vector3(pi0.x, ya, pi0.y), Vector3(pi1.x, ya, pi1.y), Vector3(pi1.x, yb, pi1.y), Vector3(pi0.x, yb, pi0.y), -n3)
	# Spallette, davanzali e architravi delle aperture.
	for h: Array in holes:
		var q0 := a + u * float(h[0])
		var q1 := a + u * float(h[1])
		var ya := y0 + float(h[2])
		var yb := y0 + float(h[3])
		var u3 := Vector3(u.x, 0, u.y)
		for s: Array in [[q0, u3], [q1, -u3]]:
			var q: Vector2 = s[0]
			var qi := q - n_out * WALL
			_quad(inn, Vector3(q.x, ya, q.y), Vector3(qi.x, ya, qi.y), Vector3(qi.x, yb, qi.y), Vector3(q.x, yb, q.y), s[1])
		var q0i := q0 - n_out * WALL
		var q1i := q1 - n_out * WALL
		if float(h[2]) > 0.0:
			_quad(inn, Vector3(q0.x, ya, q0.y), Vector3(q1.x, ya, q1.y), Vector3(q1i.x, ya, q1i.y), Vector3(q0i.x, ya, q0i.y), Vector3.UP)
		_quad(inn, Vector3(q0.x, yb, q0.y), Vector3(q1.x, yb, q1.y), Vector3(q1i.x, yb, q1i.y), Vector3(q0i.x, yb, q0i.y), Vector3.DOWN)
	# Copertina del muro in cima alla fascia (serve sul parapetto del tetto).
	var b0 := a + u * length
	var ai := a - n_out * WALL
	var bi := b0 - n_out * WALL
	_quad(inn, Vector3(a.x, y0 + band, a.y), Vector3(b0.x, y0 + band, b0.y), Vector3(bi.x, y0 + band, bi.y),
		Vector3(ai.x, y0 + band, ai.y), Vector3.UP)


func _slab(acc: CityBuilder.Acc, poly: PackedVector2Array, y: float, below: CityBuilder.Acc = null) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		var p0 := poly[idx[i]]
		var p1 := poly[idx[i + 1]]
		var p2 := poly[idx[i + 2]]
		acc.tri(Vector3(p0.x, y, p0.y), Vector3(p1.x, y, p1.y), Vector3(p2.x, y, p2.y), Vector3.UP, Color.WHITE, p0, p1, p2, Vector2.ZERO)
		if below:
			below.tri(Vector3(p0.x, y - 0.25, p0.y), Vector3(p1.x, y - 0.25, p1.y), Vector3(p2.x, y - 0.25, p2.y), Vector3.DOWN,
				Color.WHITE, p0, p1, p2, Vector2.ZERO)


## Rampa di scale nel vano, da y0 a y0 + un piano: gradini visibili e una rampa liscia per la fisica.
func _flight(acc: CityBuilder.Acc, body: StaticBody3D, r: PackedVector2Array, y0: float) -> void:
	var a := r[0]
	var b := r[1]
	var depth := r[3] - r[0]
	var run := a.distance_to(b)
	var u := (b - a) / run
	var steps := 18
	for k in steps:
		var t0 := float(k) / steps
		var t1 := float(k + 1) / steps
		var p := a + u * run * (t0 + t1) * 0.5 + depth * 0.5
		var h := FLOOR_H * t1
		_box(acc, Vector3(p.x, y0 + h - 0.09, p.y), Vector3(run / steps, 0.18, depth.length()), -atan2(u.y, u.x))
	var shape := BoxShape3D.new()
	var slope := Vector2(run, FLOOR_H).length()
	shape.size = Vector3(slope, 0.2, depth.length() - 0.1)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var mid := a + u * run * 0.5 + depth * 0.5
	var basis := Basis(Vector3.UP, -atan2(u.y, u.x)) * Basis(Vector3.BACK, atan2(FLOOR_H, run))
	cs.transform = Transform3D(basis, Vector3(mid.x, y0 + FLOOR_H * 0.5 - 0.1, mid.y))
	body.add_child(cs)


func _quad(acc: CityBuilder.Acc, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	acc.quad(a, b, c, d, n, Color.WHITE, Vector2(a.x + a.z, a.y), Vector2(b.x + b.z, b.y), Vector2(c.x + c.z, c.y),
		Vector2(d.x + d.z, d.y), Vector2.ZERO)


func _box(acc: CityBuilder.Acc, center: Vector3, size: Vector3, yaw: float) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var h := size * 0.5
	var c := []
	for i in 8:
		c.append(center + bs * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for f: Array in [[0, 1, 3, 2, -bs.z], [4, 5, 7, 6, bs.z], [0, 1, 5, 4, -bs.y], [2, 3, 7, 6, bs.y], [0, 2, 6, 4, -bs.x], [1, 3, 7, 5, bs.x]]:
		_quad(acc, c[f[0]], c[f[1]], c[f[2]], c[f[3]], f[4])


static func city_pts(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size() - 1, 2):
		out.append(Vector2(flat[i], flat[i + 1]))
	return out
