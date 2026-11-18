class_name Venues
extends RefCounted

## Locali veri (bar, farmacie, supermercati che nel gioco fanno da armerie) sui punti reali di OpenStreetMap.
## Scelta: per ogni tipo si parte dal più vicino al punto di partenza e si aggiunge ogni volta il locale reale più
## lontano da quelli già scelti, finché restano posti distanti almeno SPACING: così ogni zona della mappa ha i
## suoi, sempre dove esistono davvero. Ogni locale occupa un vano al piano terra del palazzo che lo contiene:
## porta e vetrine aperte nella facciata, bancone con la cassa, scaffali, luce e (lo mette npc.gd) il commesso.

const KIND_OF := {
	"cafe": "bar", "bar": "bar", "pub": "bar", "pharmacy": "pharmacy", "chemist": "pharmacy",
	"supermarket": "gun", "convenience": "gun",
}
const SPACING := {"bar": 220.0, "pharmacy": 250.0, "gun": 290.0}
const ROOM_W := 8.0
const ROOM_H := 3.4
const WALL := 0.3
const DOOR_W := 1.8
const DOOR_H := 2.6
const TITLES := {"bar": "Bar", "pharmacy": "Farmacia", "gun": "Armeria"}
const SIGN := {"bar": Color(1.0, 0.65, 0.2), "pharmacy": Color(0.2, 1.0, 0.45), "gun": Color(1.0, 0.25, 0.2)}


## Sceglie i locali e segna i palazzi che li ospitano con "venue" (indice nella lista restituita).
## Quota del terreno (la imposta CityBuilder prima di pick): la porta deve stare a livello del marciapiede.
static var ground: Callable


static func pick(data: Dictionary, spawn: Vector3) -> Array:
	var blds: Array = data["buildings"]
	var polys := []
	var boxes := []
	for b: Dictionary in blds:
		var p := _poly(b)
		polys.append(p)
		var r := Rect2(p[0], Vector2.ZERO)
		for q in p:
			r = r.expand(q)
		boxes.append(r)
	var by_kind := {}
	for poi: Array in data.get("pois", []):
		if poi.size() < 6 or not KIND_OF.has(String(poi[5])) or String(poi[2]) == "":
			continue
		var k: String = KIND_OF[String(poi[5])]
		if not by_kind.has(k):
			by_kind[k] = []
		by_kind[k].append(poi)
	var venues := []
	var sp := Vector2(spawn.x, spawn.z)
	for kind: String in ["gun", "pharmacy", "bar"]:
		var cands: Array = by_kind.get(kind, [])
		var chosen: Array[Vector2] = []
		var tried := {}
		while true:
			# Il candidato più lontano da quelli già scelti (il primo: il più vicino alla partenza).
			var best: Array = []
			var best_score := -INF
			for poi: Array in cands:
				var at := Vector2(poi[0], poi[1])
				if tried.has(at):
					continue
				var score := -at.distance_to(sp)
				if not chosen.is_empty():
					score = INF
					for c in chosen:
						score = minf(score, c.distance_to(at))
					if score < float(SPACING[kind]):
						continue
				if score > best_score:
					best_score = score
					best = poi
			if best.is_empty():
				break
			var at2 := Vector2(best[0], best[1])
			tried[at2] = true
			var v := _place(kind, best, blds, polys, boxes)
			if v.is_empty():
				continue
			v["index"] = venues.size()
			blds[int(v["bid"])]["venue"] = venues.size()
			venues.append(v)
			chosen.append(at2)
	return venues


static func _poly(b: Dictionary) -> PackedVector2Array:
	var p: Array = b["p"]
	var out := PackedVector2Array()
	for i in p.size() / 2:
		out.append(Vector2(p[i * 2], p[i * 2 + 1]))
	return out


## Trova il palazzo e il lato della facciata per il locale; {} se non c'è posto.
static func _place(kind: String, poi: Array, blds: Array, polys: Array, boxes: Array) -> Dictionary:
	var at := Vector2(poi[0], poi[1])
	# Palazzi candidati: quello del locale vero, poi i vicini (entro 30 m), dal più vicino.
	var cands := []
	for i in blds.size():
		var b: Dictionary = blds[i]
		if b.has("enter") or b.has("venue") or b.has("part") or b.has("dome") or b.get("style", "") != "" or float(b["h"]) < 4.0:
			continue
		if not (boxes[i] as Rect2).grow(30.0).has_point(at):
			continue
		var p: PackedVector2Array = polys[i]
		if Geometry2D.triangulate_polygon(p).is_empty():
			continue
		var d := 0.0
		if not Geometry2D.is_point_in_polygon(at, p):
			d = INF
			for k in p.size():
				d = minf(d, Geometry2D.get_closest_point_to_segment(at, p[k], p[(k + 1) % p.size()]).distance_to(at))
		if d <= 30.0:
			cands.append([d, i])
	cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for cb: Array in cands.slice(0, 6):
		var v := _place_in(kind, poi, at, int(cb[1]), polys[int(cb[1])])
		if not v.is_empty():
			return v
	return {}


## Il locale nel palazzo bid: sul lato lungo abbastanza più vicino al punto vero, con la porta a livello della strada.
static func _place_in(kind: String, poi: Array, at: Vector2, bid: int, p: PackedVector2Array) -> Dictionary:
	var edges := []
	for k in p.size():
		var a := p[k]
		var c := p[(k + 1) % p.size()]
		if a.distance_to(c) >= ROOM_W + 1.2:
			edges.append([Geometry2D.get_closest_point_to_segment(at, a, c).distance_to(at), k])
	edges.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for ek: Array in edges:
		if float(ek[0]) > float(edges[0][0]) + 12.0:
			break  # solo le facciate verso il punto vero (non quelle sul cortile dietro)
		var edge := int(ek[1])
		var a := p[edge]
		var c := p[(edge + 1) % p.size()]
		var length := a.distance_to(c)
		var u := (c - a) / length
		var n_in := Vector2(-u.y, u.x)
		if not Geometry2D.is_point_in_polygon((a + c) * 0.5 + n_in * 1.0, p):
			n_in = -n_in
		var t := clampf((at - a).dot(u), ROOM_W * 0.5 + 0.6, length - ROOM_W * 0.5 - 0.6)
		if ground.is_valid():
			# In collina: niente locali con la porta sopra o sotto il marciapiede (servirebbero scale).
			var door := a + u * t
			var outside: float = ground.call(door.x - n_in.x * 2.5, door.y - n_in.y * 2.5)
			var inside: float = ground.call(door.x + n_in.x * 2.0, door.y + n_in.y * 2.0)
			var further: float = ground.call(door.x - n_in.x * 6.0, door.y - n_in.y * 6.0)
			if absf(outside - inside) > 0.4 or absf(further - inside) > 0.9:
				continue
		for depth: float in [6.5, 5.0]:
			var e0 := a + u * (t - ROOM_W * 0.5)
			var e1 := a + u * (t + ROOM_W * 0.5)
			var ok := true
			for q: Vector2 in [e0 + n_in * depth, e1 + n_in * depth, (e0 + e1) * 0.5 + n_in * depth, e0 + n_in * 1.0, e1 + n_in * 1.0]:
				if not Geometry2D.is_point_in_polygon(q, p):
					ok = false
			if ok:
				var title: String = TITLES[kind]
				return {
					"kind": kind, "name": title if String(poi[2]).to_lower() == title.to_lower() else "%s · %s" % [title, poi[2]],
					"real": String(poi[2]), "bid": bid, "edge": edge,
					"t0": t - ROOM_W * 0.5, "t1": t + ROOM_W * 0.5, "a": a, "u": u, "n_in": n_in, "depth": depth,
				}
		if not ground.is_valid():
			break  # senza quote: solo la facciata più vicina, come prima
	return {}


## Rettangoli pieni della facciata del lato col locale: [u0, u1, v0, v1] in metri lungo il lato e dal piede del muro.
## g_off = quota del pavimento del locale sopra il piede del muro; h = altezza del muro.
static func facade_rects(v: Dictionary, length: float, g_off: float, h: float) -> Array:
	var t0: float = v["t0"]
	var t1: float = v["t1"]
	var band_top := g_off + ROOM_H
	var out := [[0.0, t0, 0.0, h], [t1, length, 0.0, h], [t0, t1, band_top, h]]
	# Piano terra del locale: vetrina - porta - vetrina, con zoccolo e architrave.
	var hs := holes(v, g_off)
	var cur := t0
	for hole: Array in hs:
		out.append([cur, hole[0], 0.0, band_top])
		out.append([hole[0], hole[1], 0.0, hole[2]])
		out.append([hole[0], hole[1], hole[3], band_top])
		cur = hole[1]
	out.append([cur, t1, 0.0, band_top])
	return out.filter(func(r: Array) -> bool: return float(r[1]) - float(r[0]) > 0.01 and float(r[3]) - float(r[2]) > 0.01)


## Aperture: [u0, u1, v0, v1] (dal piede del muro).
static func holes(v: Dictionary, g_off: float) -> Array:
	var t0: float = v["t0"]
	var t1: float = v["t1"]
	var mid := (t0 + t1) * 0.5
	return [
		[t0 + 0.6, mid - DOOR_W * 0.5 - 0.5, g_off + 0.7, g_off + 2.8],
		[mid - DOOR_W * 0.5, mid + DOOR_W * 0.5, 0.0, g_off + DOOR_H],
		[mid + DOOR_W * 0.5 + 0.5, t1 - 0.6, g_off + 0.7, g_off + 2.8],
	]


## Costruisce l'interno e restituisce le posizioni utili per il negozio e il commesso.
static func build_room(city: CityBuilder, v: Dictionary) -> Dictionary:
	var a: Vector2 = v["a"]
	var u: Vector2 = v["u"]
	var n: Vector2 = v["n_in"]
	var depth: float = v["depth"]
	var t0: float = v["t0"]
	var kind: String = v["kind"]
	var o := a + u * t0  # angolo della stanza sulla facciata
	var g := city.height_at(o.x + n.x * 2.0, o.y + n.y * 2.0)
	g = maxf(g, city.relief_at(o.x + n.x * 2.0, o.y + n.y * 2.0))  # mai sotto la città (banchine)
	var to3 := func(x: float, z: float, y: float) -> Vector3:
		var p := o + u * x + n * z
		return Vector3(p.x, g + y, p.y)
	var U := Vector3(u.x, 0, u.y)
	var N := Vector3(n.x, 0, n.y)
	var walls := CityBuilder.Acc.new()
	var floor_acc := CityBuilder.Acc.new()
	var furn := CityBuilder.Acc.new()
	var dark := CityBuilder.Acc.new()
	var W := ROOM_W
	var H := ROOM_H
	_q(floor_acc, to3.call(0, 0.0, 0.02), to3.call(W, 0.0, 0.02), to3.call(W, depth, 0.02), to3.call(0, depth, 0.02), Vector3.UP)
	_q(walls, to3.call(0, 0.0, H), to3.call(W, 0.0, H), to3.call(W, depth, H), to3.call(0, depth, H), Vector3.DOWN)
	_q(walls, to3.call(0, depth, 0), to3.call(W, depth, 0), to3.call(W, depth, H), to3.call(0, depth, H), -N)
	_q(walls, to3.call(0, WALL, 0), to3.call(0, depth, 0), to3.call(0, depth, H), to3.call(0, WALL, H), U)
	_q(walls, to3.call(W, WALL, 0), to3.call(W, depth, 0), to3.call(W, depth, H), to3.call(W, WALL, H), -U)
	# Lato interno della facciata, con le stesse aperture.
	var hs := holes(v, 0.0)
	var cur := 0.0
	for h: Array in hs:
		var x0: float = float(h[0]) - t0
		var x1: float = float(h[1]) - t0
		_q(walls, to3.call(cur, WALL, 0), to3.call(x0, WALL, 0), to3.call(x0, WALL, H), to3.call(cur, WALL, H), N)
		_q(walls, to3.call(x0, WALL, 0), to3.call(x1, WALL, 0), to3.call(x1, WALL, h[2]), to3.call(x0, WALL, h[2]), N)
		_q(walls, to3.call(x0, WALL, h[3]), to3.call(x1, WALL, h[3]), to3.call(x1, WALL, H), to3.call(x0, WALL, H), N)
		# Spallette tra fuori e dentro.
		_q(walls, to3.call(x0, 0, h[2]), to3.call(x0, WALL, h[2]), to3.call(x0, WALL, h[3]), to3.call(x0, 0, h[3]), U)
		_q(walls, to3.call(x1, 0, h[2]), to3.call(x1, WALL, h[2]), to3.call(x1, WALL, h[3]), to3.call(x1, 0, h[3]), -U)
		_q(walls, to3.call(x0, 0, h[3]), to3.call(x1, 0, h[3]), to3.call(x1, WALL, h[3]), to3.call(x0, WALL, h[3]), Vector3.DOWN)
		if float(h[2]) > 0.0:
			_q(walls, to3.call(x0, 0, h[2]), to3.call(x1, 0, h[2]), to3.call(x1, WALL, h[2]), to3.call(x0, WALL, h[2]), Vector3.UP)
		cur = x1
	_q(walls, to3.call(cur, WALL, 0), to3.call(W, WALL, 0), to3.call(W, WALL, H), to3.call(cur, WALL, H), N)
	# Bancone con la cassa, e scaffali sul fondo.
	var yaw := atan2(U.z, U.x) * -1.0
	var cz := depth - 1.7
	_box(furn, to3.call(W * 0.5, cz, 0.53), Vector3(4.6, 1.06, 0.7), yaw)
	_box(dark, to3.call(W * 0.5 + 1.4, cz - 0.05, 1.2), Vector3(0.45, 0.28, 0.35), yaw)  # cassa
	_box(furn, to3.call(W * 0.5, depth - 0.2, 1.9), Vector3(W - 1.0, 0.06, 0.4), yaw)
	_box(furn, to3.call(W * 0.5, depth - 0.2, 1.3), Vector3(W - 1.0, 0.06, 0.4), yaw)
	var colors: Array = {"bar": [Color(0.2, 0.5, 0.2), Color(0.6, 0.35, 0.1), Color(0.8, 0.8, 0.85)],
		"pharmacy": [Color(0.95, 0.95, 0.95), Color(0.3, 0.75, 0.45), Color(0.6, 0.8, 0.95)],
		"gun": [Color(0.85, 0.2, 0.15), Color(0.95, 0.85, 0.2), Color(0.25, 0.45, 0.8)]}[kind]
	var bottles := CityBuilder.Acc.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(v["bid"])
	for shelf_y: float in [1.33, 1.93]:
		var x := 0.8
		while x < W - 0.8:
			var size := Vector3(0.12, 0.3, 0.12) if kind == "bar" else Vector3(0.25, 0.22, 0.18)
			_box(bottles, to3.call(x, depth - 0.2, shelf_y + size.y * 0.5), size, yaw, colors[rng.randi() % colors.size()])
			x += size.x + rng.randf_range(0.05, 0.15)
	if kind == "bar":
		for tx: float in [1.6, W - 1.6]:
			_cyl(furn, to3.call(tx, 1.9, 0.0), 0.06, 0.72)
			_cyl(furn, to3.call(tx, 1.9, 0.72), 0.45, 0.04)
			for s: float in [-0.7, 0.7]:
				_cyl(dark, to3.call(tx + s, 1.9, 0.0), 0.18, 0.46)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = {"bar": Color(0.38, 0.22, 0.12), "pharmacy": Color(0.9, 0.9, 0.88), "gun": Color(0.32, 0.33, 0.35)}[kind]
	wood.roughness = 0.6
	var plaster := StandardMaterial3D.new()
	plaster.albedo_color = {"bar": Color(0.86, 0.78, 0.64), "pharmacy": Color(0.95, 0.97, 0.97), "gun": Color(0.75, 0.74, 0.72)}[kind]
	var tiles := StandardMaterial3D.new()
	tiles.albedo_texture = TexLib.tex("PavingStones046", "color")
	tiles.albedo_color = {"bar": Color(0.8, 0.62, 0.45), "pharmacy": Color(0.95, 0.95, 0.95), "gun": Color(0.6, 0.6, 0.6)}[kind]
	tiles.uv1_triplanar = true
	tiles.uv1_scale = Vector3(0.8, 0.8, 0.8)
	var darkm := StandardMaterial3D.new()
	darkm.albedo_color = Color(0.08, 0.08, 0.09)
	darkm.metallic = 0.4
	var bottle_m := StandardMaterial3D.new()
	bottle_m.vertex_color_use_as_albedo = true
	bottle_m.vertex_color_is_srgb = true
	bottle_m.roughness = 0.2
	var tag := "Locale_%d" % int(v["index"])
	city._add_mesh(walls.mesh(plaster), tag + "_pareti", false)
	city._add_mesh(floor_acc.mesh(tiles), tag + "_pavimento", false)
	city._add_mesh(furn.mesh(wood), tag + "_arredi")
	city._add_mesh(dark.mesh(darkm), tag + "_cassa")
	city._add_mesh(bottles.mesh(bottle_m), tag + "_merce", false)
	var faces := walls.v.duplicate()
	faces.append_array(furn.v)
	city._add_trimesh_body(faces, tag + "_fisico")
	if kind == "gun":
		# Armi appese sopra gli scaffali.
		var k := 0
		for id: String in ["fucile", "pompa", "mitragliatrice", "cecchino"]:
			var m := Weapons.model(id)
			if m:
				city.add_child(m)
				m.global_transform = Transform3D(Basis(Vector3.UP, atan2(U.x, U.z)), to3.call(1.4 + k * 1.75, depth - 0.12, 2.55))
				k += 1
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.65) if kind == "bar" else Color(0.95, 0.98, 1.0)
	light.light_energy = 1.8
	light.omni_range = 9.0
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 20.0
	light.position = to3.call(W * 0.5, depth * 0.5, H - 0.3)
	city.add_child(light)
	# Insegna luminosa sopra la porta.
	var sign := Label3D.new()
	sign.text = String(v["real"]).to_upper() if kind == "bar" else (TITLES[kind] as String).to_upper()
	sign.font_size = 56
	sign.outline_size = 8
	sign.pixel_size = 0.01
	sign.modulate = SIGN[kind]
	sign.shaded = false
	sign.position = to3.call(W * 0.5, -0.12, H - 0.25)
	sign.rotation.y = atan2(-N.x, -N.z)
	sign.visibility_range_end = 120.0
	city.add_child(sign)
	if kind == "pharmacy":
		var cross := Label3D.new()
		cross.text = "✚"
		cross.font_size = 160
		cross.pixel_size = 0.01
		cross.modulate = Color(0.2, 1.0, 0.4)
		cross.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		cross.position = to3.call(W + 0.2, -0.5, H + 0.3)
		city.add_child(cross)
	return {
		"counter_front": to3.call(W * 0.5, cz - 1.0, 0.0),
		"clerk": to3.call(W * 0.5, depth - 0.85, 0.0),
		"clerk_yaw": atan2(-N.x, -N.z),
		"entrance": to3.call(W * 0.5, -1.6, 0.0),
		"door2d": o + u * (W * 0.5),
	}


static func _q(acc: CityBuilder.Acc, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col := Color.WHITE) -> void:
	acc.quad(a, b, c, d, n, col, Vector2(a.x + a.z, a.y), Vector2(b.x + b.z, b.y), Vector2(c.x + c.z, c.y), Vector2(d.x + d.z, d.y), Vector2.ZERO)


static func _box(acc: CityBuilder.Acc, center: Vector3, size: Vector3, yaw: float, col := Color.WHITE) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var h := size * 0.5
	var c := []
	for i in 8:
		c.append(center + bs * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for f: Array in [[0, 1, 3, 2, -bs.z], [4, 5, 7, 6, bs.z], [0, 1, 5, 4, -bs.y], [2, 3, 7, 6, bs.y], [0, 2, 6, 4, -bs.x], [1, 3, 7, 5, bs.x]]:
		_q(acc, c[f[0]], c[f[1]], c[f[2]], c[f[3]], f[4], col)


static func _cyl(acc: CityBuilder.Acc, base: Vector3, r: float, h: float) -> void:
	for i in 10:
		var a0 := TAU * i / 10.0
		var a1 := TAU * (i + 1) / 10.0
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_q(acc, base + d0 * r, base + d1 * r, base + d1 * r + Vector3(0, h, 0), base + d0 * r + Vector3(0, h, 0), (d0 + d1).normalized())
		acc.tri(base + Vector3(0, h, 0), base + d0 * r + Vector3(0, h, 0), base + d1 * r + Vector3(0, h, 0), Vector3.UP, Color.WHITE,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
