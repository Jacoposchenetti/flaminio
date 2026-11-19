class_name Homes
extends Node3D

## Case in vendita, come in GTA: due per zona in palazzi veri (portone sul marciapiede, con il nome della via).
## Davanti al portone (E): vedere, visitare, comprare, entrare, vendere. Dentro: l'interno (monolocale, appartamento
## o attico) sta sotto il palazzo, nascosto, e c'è solo sul PC di chi ci entra; si arreda col tasto O (catalogo,
## mobili da posare col mouse, da spostare o rivendere). Mobili che servono: cassaforte (soldi e droga che non si
## perdono), armadio (cambiare personaggio), letto (dormire). Chi ha una casa rinasce lì.
## Tutto si salva in user://case.json sul PC del giocatore.

signal changed

const SAVE_PATH := "user://case.json"
const DEPTH := 60.0  # l'interno sta così sotto il marciapiede
const SELL_BACK := 0.7  # quanto ti ridanno della casa quando la vendi
const FURN_BACK := 0.5  # e dei mobili
const TYPES := {
	"mono": {"name": "Monolocale", "size": Vector2(8.0, 6.5), "price": 32000},
	"app": {"name": "Appartamento", "size": Vector2(12.0, 8.5), "price": 78000},
	"attico": {"name": "Attico", "size": Vector2(16.0, 11.0), "price": 190000},
}
const ZONE_PRICE := [1.0, 0.85, 1.0, 1.1, 1.6, 1.4, 1.8, 1.2]
const ZONE_TYPES := [["app", "mono"], ["mono", "app"], ["app", "mono"], ["app", "mono"], ["attico", "app"], ["attico", "app"], ["attico", "app"], ["app", "mono"]]
## Mobili: nome, prezzo, ingombro (x, y, z in metri) e a cosa servono ("" solo arredo).
const FURNITURE := {
	"divano": {"name": "Divano", "price": 1800, "size": Vector3(2.1, 0.9, 0.95), "use": ""},
	"poltrona": {"name": "Poltrona", "price": 700, "size": Vector3(0.95, 0.9, 0.9), "use": ""},
	"letto": {"name": "Letto matrimoniale", "price": 2200, "size": Vector3(1.8, 0.65, 2.15), "use": "sleep"},
	"tavolo": {"name": "Tavolo da pranzo", "price": 900, "size": Vector3(1.7, 0.76, 0.95), "use": ""},
	"sedia": {"name": "Sedia", "price": 150, "size": Vector3(0.48, 0.95, 0.5), "use": ""},
	"tv": {"name": "Televisore", "price": 1400, "size": Vector3(1.5, 1.25, 0.45), "use": ""},
	"libreria": {"name": "Libreria", "price": 600, "size": Vector3(1.3, 2.0, 0.38), "use": ""},
	"lampada": {"name": "Lampada da terra", "price": 250, "size": Vector3(0.4, 1.7, 0.4), "use": ""},
	"tappeto": {"name": "Tappeto persiano", "price": 1200, "size": Vector3(2.6, 0.02, 1.8), "use": ""},
	"pianta": {"name": "Pianta", "price": 120, "size": Vector3(0.6, 1.3, 0.6), "use": ""},
	"scrivania": {"name": "Scrivania con computer", "price": 1100, "size": Vector3(1.4, 1.2, 0.7), "use": ""},
	"armadio": {"name": "Armadio (cambia personaggio)", "price": 900, "size": Vector3(1.3, 2.15, 0.62), "use": "wardrobe"},
	"cassaforte": {"name": "Cassaforte (soldi e droga al sicuro)", "price": 4500, "size": Vector3(0.65, 0.85, 0.6), "use": "safe"},
	"acquario": {"name": "Acquario", "price": 3200, "size": Vector3(1.3, 1.35, 0.45), "use": ""},
	"bar": {"name": "Bancone bar", "price": 5500, "size": Vector3(2.2, 1.1, 0.65), "use": ""},
	"biliardo": {"name": "Biliardo", "price": 8000, "size": Vector3(2.6, 0.85, 1.45), "use": ""},
	"pianoforte": {"name": "Pianoforte a coda", "price": 15000, "size": Vector3(1.55, 1.0, 2.0), "use": ""},
}
const FURN_ORDER := ["divano", "poltrona", "letto", "tavolo", "sedia", "tv", "libreria", "lampada", "tappeto", "pianta",
	"scrivania", "armadio", "cassaforte", "acquario", "bar", "biliardo", "pianoforte"]
const FURN_LAYER := 64  # per cliccare sui mobili

var main: Node
var city: CityBuilder
var properties: Array = []  # {id, name, type, zone, door: Vector3, face: float, price}
var owned := {}  # id -> {furniture: [[mobile, x, z, yaw]], cash, drugs {}}
var inside := ""  # id della casa in cui si trova il giocatore ("" fuori)
var visiting := false  # dentro senza averla comprata
var map_entries: Array = []  # [x, z, nome, categoria] condivisi con le mappe
var _room: Node3D
var _ceiling: Node3D
var _windows: Array[StandardMaterial3D] = []
var _items: Array = []  # [Node3D, voce in owned]
var _origin := Vector3.ZERO
var _size := Vector2.ZERO
var _markers := {}  # id -> Label3D


func setup(m: Node, c: CityBuilder) -> void:
	main = m
	city = c
	_pick()
	_load()
	for p: Dictionary in properties:
		_marker(p)
		map_entries.append([(p["door"] as Vector3).x, (p["door"] as Vector3).z, _pin_name(p), "casa_mia" if owned.has(p["id"]) else "casa"])


# --- Scelta delle case ----------------------------------------------------------------------------


func _pick() -> void:
	var road_pts := PackedVector2Array()
	for r: Dictionary in city.data["roads"]:
		if r["k"] != "road" or int(r["b"]) == 1:
			continue
		var pts := city._pts(r["p"])
		for i in pts.size() - 1:
			var l := pts[i].distance_to(pts[i + 1])
			for k in int(l / 6.0) + 1:
				road_pts.append(pts[i].lerp(pts[i + 1], k * 6.0 / maxf(l, 0.01)))
	var by_zone := {}
	for b: Dictionary in city.data["buildings"]:
		if b.has("enter") or b.has("venue") or b.has("part") or b.has("dome") or b.get("style", "") != "" or float(b["h"]) < 9.0:
			continue
		var poly := Venues._poly(b)
		if LandmarkBuilder.in_maxxi(poly):
			continue
		var c := Vector2.ZERO
		for q in poly:
			c += q
		c /= poly.size()
		var area := absf(_area(poly))
		if area < 250.0 or area > 4000.0:
			continue
		var z := Crime.zone_of(c)
		if not by_zone.has(z):
			by_zone[z] = []
		by_zone[z].append([c.distance_to(Crime.ZONES[z]["c"]), b, poly, c])
	var n := 0
	for z in Crime.ZONES.size():
		var cands: Array = by_zone.get(z, [])
		cands.sort_custom(func(a: Array, b2: Array) -> bool: return a[0] < b2[0])
		var chosen: Array[Vector2] = []
		for cand: Array in cands.slice(0, 30):
			if chosen.size() >= 2:
				break
			var cc: Vector2 = cand[3]
			var far := true
			for o in chosen:
				if o.distance_to(cc) < 120.0:
					far = false
			if not far:
				continue
			var door := _door(cand[2], road_pts)
			if door.is_empty():
				continue
			chosen.append(cc)
			var kind: String = ZONE_TYPES[z][chosen.size() - 1]
			var at: Vector2 = door[0]
			var street := city.street_name(Vector3(at.x, 0, at.y), 40.0)
			var civic := 2 + (int(absf(at.x * 7.0 + at.y * 3.0)) % 140)
			properties.append({"id": "casa%d" % n, "name": "%s %d" % [street if street != "" else Crime.ZONES[z]["name"], civic],
				"type": kind, "zone": z, "door": Vector3(at.x, city.surface_at(at.x, at.y), at.y), "face": float(door[1]),
				"price": int(round(int(TYPES[kind]["price"]) * float(ZONE_PRICE[z]) / 1000.0)) * 1000})
			n += 1


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return a * 0.5


## Portone: a metà del lato più vicino a una strada, un metro e mezzo fuori. [punto, direzione verso il palazzo].
func _door(poly: PackedVector2Array, road_pts: PackedVector2Array) -> Array:
	var best := []
	var best_d := 30.0
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		if a.distance_to(b) < 5.0:
			continue
		var mid := (a + b) * 0.5
		var u := (b - a).normalized()
		var n := Vector2(-u.y, u.x)
		if Geometry2D.is_point_in_polygon(mid + n * 0.5, poly):
			n = -n
		var d := INF
		for r in road_pts:
			d = minf(d, r.distance_to(mid))
		if d < best_d:
			var p := mid + n * 1.5
			if city.carve_at(p.x, p.y) < -0.3:
				continue
			best_d = d
			best = [p, atan2(-n.x, -n.y)]
	return best


func _pin_name(p: Dictionary) -> String:
	return "%s · %s%s" % [TYPES[p["type"]]["name"], p["name"], " (tua)" if owned.has(p["id"]) else " · € %s" % SlotMachine._thousands(int(p["price"]))]


func _marker(p: Dictionary) -> void:
	var at: Vector3 = p["door"]
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 34
	l.outline_size = 10
	l.pixel_size = 0.006
	l.visibility_range_end = 40.0
	add_child(l)
	l.global_position = at + Vector3(0, 2.4, 0)
	_markers[p["id"]] = l
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.7
	t.outer_radius = 0.82
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.9, 0.5, 0.8)
	m.emission_enabled = true
	m.emission = Color(0.2, 0.8, 0.4)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	t.material = m
	ring.mesh = t
	ring.scale = Vector3(1, 0.15, 1)
	add_child(ring)
	ring.global_position = at + Vector3(0, 0.05, 0)
	ring.set_meta("mat", m)
	l.set_meta("ring", ring)
	_refresh_marker(p)


func _refresh_marker(p: Dictionary) -> void:
	var l: Label3D = _markers[p["id"]]
	var mine := owned.has(p["id"])
	l.text = ("CASA TUA\n%s" % TYPES[p["type"]]["name"]) if mine else ("IN VENDITA\n%s · € %s" % [TYPES[p["type"]]["name"], SlotMachine._thousands(int(p["price"]))])
	l.modulate = Color(0.45, 0.75, 1.0) if mine else Color(0.5, 1.0, 0.6)
	var ring: MeshInstance3D = l.get_meta("ring")
	(ring.get_meta("mat") as StandardMaterial3D).albedo_color = Color(0.35, 0.65, 1.0, 0.8) if mine else Color(0.3, 0.9, 0.5, 0.8)
	for e: Array in map_entries:
		if absf(float(e[0]) - (p["door"] as Vector3).x) < 0.01 and absf(float(e[1]) - (p["door"] as Vector3).z) < 0.01:
			e[2] = _pin_name(p)
			e[3] = "casa_mia" if mine else "casa"


# --- Domande ----------------------------------------------------------------------------------------


func door_near(pos: Vector3) -> Dictionary:
	for p: Dictionary in properties:
		if (p["door"] as Vector3).distance_to(pos) < 1.8:
			return p
	return {}


func prop(id: String) -> Dictionary:
	for p: Dictionary in properties:
		if p["id"] == id:
			return p
	return {}


func furniture_value(id: String) -> int:
	var v := 0
	for f: Array in owned.get(id, {}).get("furniture", []):
		v += int(FURNITURE[String(f[0])]["price"])
	return v


func sell_price(id: String) -> int:
	return int(int(prop(id)["price"]) * SELL_BACK) + int(furniture_value(id) * FURN_BACK)


## La casa di proprietà più vicina a pos (per rinascere), o {}.
func nearest_owned(pos: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for p: Dictionary in properties:
		if owned.has(p["id"]):
			var d := (p["door"] as Vector3).distance_to(pos)
			if d < bd:
				bd = d
				best = p
	return best


# --- Comprare e vendere ---------------------------------------------------------------------------


func buy(id: String) -> String:
	var p := prop(id)
	if p.is_empty() or owned.has(id):
		return ""
	var pl: Player = main.player
	if pl.money < int(p["price"]) and not pl.creative:
		return "Non hai abbastanza contanti (puoi prelevare in banca)."
	if not pl.creative:
		pl.money -= int(p["price"])
	owned[id] = {"furniture": _starter(String(p["type"])), "cash": 0, "drugs": {}}
	_refresh_marker(p)
	save()
	changed.emit()
	Sfx.play2d("jackpot", -8.0)
	return "Congratulazioni: %s %s è tuo. Arredalo con O una volta dentro." % [TYPES[p["type"]]["name"].to_lower(), p["name"]]


func sell(id: String) -> String:
	if not owned.has(id):
		return ""
	var gain := sell_price(id)
	var stored: Dictionary = owned[id]
	var pl: Player = main.player
	pl.money += gain + int(stored.get("cash", 0))
	for d: String in (stored.get("drugs", {}) as Dictionary):
		pl.drugs[d] = int(pl.drugs.get(d, 0)) + int(stored["drugs"][d])
	if inside == id:
		leave()
	owned.erase(id)
	_refresh_marker(prop(id))
	save()
	changed.emit()
	return "Venduta per € %s (quello che c'era in cassaforte te lo sei portato via)." % SlotMachine._thousands(gain)


## Mobili che ci sono già quando la compri: un letto e un tavolo con due sedie (il resto lo scegli tu).
func _starter(kind: String) -> Array:
	var s: Vector2 = TYPES[kind]["size"]
	return [["letto", s.x - 1.6, s.y - 1.4, PI], ["tavolo", s.x * 0.35, s.y * 0.5, 0.0],
		["sedia", s.x * 0.35 - 0.5, s.y * 0.5 + 0.8, PI], ["sedia", s.x * 0.35 + 0.5, s.y * 0.5 + 0.8, PI]]


# --- Entrare e uscire -----------------------------------------------------------------------------


func enter(id: String, visit := false) -> String:
	var p := prop(id)
	if p.is_empty():
		return ""
	if main.my_stars() > 0:
		return "Con la polizia alle costole? Ti seguirebbero fino in casa: prima seminala."
	inside = id
	visiting = visit
	_build_room(p)
	var pl: Player = main.player
	pl.teleport(_to_world(Vector2(_size.x * 0.5, 1.2), 0.3))
	pl.cam_yaw = float(p["face"]) + PI
	pl.cam_pitch = -0.2
	return ("Visita: %s %s. € %s." % [TYPES[p["type"]]["name"], p["name"], SlotMachine._thousands(int(p["price"]))]) if visit else ""


func leave() -> void:
	if inside == "":
		return
	var p := prop(inside)
	inside = ""
	visiting = false
	if _room:
		_room.queue_free()
		_room = null
	_items.clear()
	_windows.clear()
	var pl: Player = main.player
	var out: Vector3 = p["door"]
	var back := Vector3(sin(float(p["face"])), 0, cos(float(p["face"])))
	pl.teleport(out - back * 0.8 + Vector3(0, 0.3, 0))
	pl.cam_yaw = float(p["face"])


func _to_world(local: Vector2, y: float) -> Vector3:
	var b := Basis(Vector3.UP, _yaw)
	return _origin + b * Vector3(local.x - _size.x * 0.5, y, local.y)


var _yaw := 0.0


## Interno sotto il palazzo: pavimento in parquet, pareti, soffitto, finestre luminose, cucina, bagno, porta.
func _build_room(p: Dictionary) -> void:
	if _room:
		_room.queue_free()
	_items.clear()
	_windows.clear()
	var kind: String = p["type"]
	_size = TYPES[kind]["size"]
	var door: Vector3 = p["door"]
	_origin = Vector3(door.x, city.surface_at(door.x, door.z) - DEPTH, door.z)
	_yaw = float(p["face"])
	_room = Node3D.new()
	_room.name = "Casa"
	add_child(_room)
	_room.global_transform = Transform3D(Basis(Vector3.UP, _yaw), _origin)
	var W := _size.x
	var D := _size.y
	var H := 2.9 if kind != "attico" else 3.4
	var to3 := func(x: float, z: float, y: float) -> Vector3: return Vector3(x - W * 0.5, y, z)
	var walls := CityBuilder.Acc.new()
	var floor_acc := CityBuilder.Acc.new()
	var ceil_acc := CityBuilder.Acc.new()
	var white := CityBuilder.Acc.new()
	var dark := CityBuilder.Acc.new()
	var tiles := CityBuilder.Acc.new()
	Venues._q(floor_acc, to3.call(0, 0, 0), to3.call(W, 0, 0), to3.call(W, D, 0), to3.call(0, D, 0), Vector3.UP)
	Venues._q(ceil_acc, to3.call(0, 0, H), to3.call(W, 0, H), to3.call(W, D, H), to3.call(0, D, H), Vector3.DOWN)
	Venues._q(walls, to3.call(0, 0, 0), to3.call(W, 0, 0), to3.call(W, 0, H), to3.call(0, 0, H), Vector3.BACK)
	Venues._q(walls, to3.call(0, D, 0), to3.call(W, D, 0), to3.call(W, D, H), to3.call(0, D, H), Vector3.FORWARD)
	Venues._q(walls, to3.call(0, 0, 0), to3.call(0, D, 0), to3.call(0, D, H), to3.call(0, 0, H), Vector3.RIGHT)
	Venues._q(walls, to3.call(W, 0, 0), to3.call(W, D, 0), to3.call(W, D, H), to3.call(W, 0, H), Vector3.LEFT)
	# Porta d'ingresso (per uscire) sulla parete davanti.
	Venues._box(dark, to3.call(W * 0.5, 0.05, 1.05), Vector3(1.0, 2.1, 0.08), 0.0)
	Venues._box(white, to3.call(W * 0.5, 0.04, 2.15), Vector3(1.25, 0.12, 0.1), 0.0)
	# Cucina lungo la parete di sinistra, in fondo.
	var kz := D - 0.35
	Venues._box(white, to3.call(1.6, kz, 0.45), Vector3(2.8, 0.9, 0.65), 0.0)
	Venues._box(dark, to3.call(1.6, kz, 0.92), Vector3(2.85, 0.05, 0.7), 0.0)
	Venues._box(white, to3.call(1.6, kz + 0.05, 1.9), Vector3(2.8, 0.7, 0.4), 0.0)
	Venues._box(white, to3.call(3.4, kz, 0.95), Vector3(0.75, 1.9, 0.65), 0.0)  # frigorifero
	# Bagno: angolo in fondo a destra chiuso da due pareti con il vano della porta.
	var bw := 2.6
	var bd := 2.4
	Venues._box(walls, to3.call(W - bw, D - bd * 0.5 - 0.45, H * 0.5), Vector3(0.12, H, bd - 0.9), 0.0)
	Venues._box(walls, to3.call(W - bw + 0.35, D - bd, H * 0.5), Vector3(0.7, H, 0.12), 0.0)
	Venues._box(walls, to3.call(W - 0.6, D - bd, H * 0.5), Vector3(1.2, H, 0.12), 0.0)
	Venues._box(tiles, to3.call(W - bw * 0.5, D - bd * 0.5, 0.01), Vector3(bw, 0.02, bd), 0.0)
	Venues._box(white, to3.call(W - 0.45, D - 1.0, 0.25), Vector3(0.75, 0.5, 1.6), 0.0)  # vasca
	Venues._box(white, to3.call(W - bw + 0.5, D - 0.35, 0.4), Vector3(0.45, 0.8, 0.55), 0.0)  # lavandino
	# Appartamento e attico: parete della camera con il passaggio.
	if kind != "mono":
		var px := W * 0.62
		Venues._box(walls, to3.call(px, 1.6, H * 0.5), Vector3(0.12, H, 3.2), 0.0)
		Venues._box(walls, to3.call(px, (4.4 + D - bd) * 0.5, H * 0.5), Vector3(0.12, H, D - bd - 4.4), 0.0)
	var plaster := StandardMaterial3D.new()
	plaster.albedo_color = Color(0.86, 0.83, 0.77) if kind != "attico" else Color(0.9, 0.9, 0.9)
	var parquet := StandardMaterial3D.new()
	parquet.albedo_texture = TexLib.tex("Bark014", "color")
	parquet.albedo_color = Color(1.0, 0.82, 0.62)
	parquet.uv1_triplanar = true
	parquet.uv1_scale = Vector3(0.6, 0.6, 0.6)
	parquet.roughness = 0.45
	var tile_m := StandardMaterial3D.new()
	tile_m.albedo_texture = TexLib.tex("Travertine005", "color")
	tile_m.uv1_triplanar = true
	var white_m := StandardMaterial3D.new()
	white_m.albedo_color = Color(0.93, 0.93, 0.92)
	white_m.roughness = 0.3
	var dark_m := StandardMaterial3D.new()
	dark_m.albedo_color = Color(0.25, 0.16, 0.1)
	dark_m.roughness = 0.5
	for pair: Array in [[walls, plaster], [floor_acc, parquet], [white, white_m], [dark, dark_m], [tiles, tile_m]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (pair[0] as CityBuilder.Acc).mesh(pair[1])
		_room.add_child(mi)
	var cm := MeshInstance3D.new()
	cm.mesh = ceil_acc.mesh(plaster)
	_room.add_child(cm)
	_ceiling = cm
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var faces := walls.v.duplicate()
	faces.append_array(floor_acc.v)
	faces.append_array(white.v)
	faces.append_array(ceil_acc.v)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	_room.add_child(body)
	# Finestre luminose sulle pareti laterali (il cielo cambia col giorno e la notte), lontane da cucina e bagno.
	var nwin := 1 if kind == "mono" else (2 if kind == "app" else 3)
	for side: float in [0.0, 1.0]:
		for k in nwin:
			var wz := (D - 2.6) * (k + 1) / (nwin + 1)
			var m := StandardMaterial3D.new()
			m.emission_enabled = true
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_windows.append(m)
			var box := BoxMesh.new()
			box.size = Vector3(0.02, 1.5 if kind != "attico" else 2.3, 1.3 if kind != "attico" else 2.2)
			box.material = m
			var wi := MeshInstance3D.new()
			wi.mesh = box
			wi.position = to3.call(0.02 if side == 0.0 else W - 0.02, wz, 1.6 if kind != "attico" else 1.7)
			_room.add_child(wi)
	_update_windows()
	for k in (1 if kind == "mono" else 3):
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.88, 0.72)
		l.light_energy = 1.3
		l.omni_range = 8.0
		l.position = to3.call(W * (k + 0.5) / (1 if kind == "mono" else 3), D * 0.5, H - 0.25)
		_room.add_child(l)
	for f: Array in owned.get(p["id"], {}).get("furniture", []):
		_spawn_item(f)


func _update_windows() -> void:
	var night: float = DayNight.current.lights_on if DayNight.current else 0.0
	for m in _windows:
		var col := Color(0.62, 0.78, 0.95).lerp(Color(0.05, 0.07, 0.16), night)
		m.albedo_color = col
		m.emission = col
		m.emission_energy_multiplier = 1.2


func _process(_delta: float) -> void:
	if inside != "" and Engine.get_process_frames() % 30 == 0:
		_update_windows()


# --- Mobili ---------------------------------------------------------------------------------------


## Crea il mobile f = [id, x, z, yaw] (coordinate della stanza) e lo mette nella casa.
func _spawn_item(f: Array) -> Node3D:
	var n := Homes.make_furniture(String(f[0]))
	_room.add_child(n)
	n.position = Vector3(float(f[1]) - _size.x * 0.5, 0.0, float(f[2]))
	n.rotation.y = float(f[3])
	n.set_meta("entry", f)
	_items.append(n)
	return n


func items() -> Array:
	return _items


func room_size() -> Vector2:
	return _size


func room_node() -> Node3D:
	return _room


func ceiling() -> Node3D:
	return _ceiling


## Il mobile utilizzabile vicino al giocatore: [nodo, uso] o [].
func usable_near(pos: Vector3) -> Array:
	for n: Node3D in _items:
		var use: String = FURNITURE[String(n.get_meta("entry")[0])]["use"]
		if use != "" and n.global_position.distance_to(pos) < 1.9:
			return [n, use]
	return []


func exit_near(pos: Vector3) -> bool:
	return inside != "" and pos.distance_to(_to_world(Vector2(_size.x * 0.5, 0.3), 0.0)) < 1.6


## Posa un mobile (nuovo o spostato) e salva. Restituisce il nodo.
func place(entry: Array) -> Node3D:
	var f: Array = owned[inside]["furniture"]
	if not f.has(entry):
		f.append(entry)
	save()
	return _spawn_item(entry)


func remove_item(n: Node3D, refund: bool) -> int:
	var entry: Array = n.get_meta("entry")
	(owned[inside]["furniture"] as Array).erase(entry)
	_items.erase(n)
	n.queue_free()
	save()
	return int(int(FURNITURE[String(entry[0])]["price"]) * FURN_BACK) if refund else 0


## Modello del mobile (davanti = +Z), con un corpo per la collisione e per cliccarlo.
static func make_furniture(id: String) -> Node3D:
	var root := Node3D.new()
	var d: Dictionary = FURNITURE[id]
	var size: Vector3 = d["size"]
	var parts: Array = []  # [dimensioni, centro, colore, luminoso]
	var fabric: Color = [Color(0.25, 0.32, 0.45), Color(0.5, 0.2, 0.18), Color(0.35, 0.38, 0.3), Color(0.6, 0.55, 0.48)][absi(id.hash()) % 4]
	var wood := Color(0.36, 0.22, 0.12)
	match id:
		"divano", "poltrona":
			parts = [[Vector3(size.x, 0.42, size.z), Vector3(0, 0.21, 0), fabric], [Vector3(size.x, 0.5, 0.22), Vector3(0, 0.62, -size.z * 0.5 + 0.11), fabric],
				[Vector3(0.18, 0.62, size.z), Vector3(-size.x * 0.5 + 0.09, 0.31, 0), fabric.darkened(0.15)], [Vector3(0.18, 0.62, size.z), Vector3(size.x * 0.5 - 0.09, 0.31, 0), fabric.darkened(0.15)]]
		"letto":
			parts = [[Vector3(size.x, 0.3, size.z), Vector3(0, 0.15, 0), wood], [Vector3(size.x - 0.1, 0.25, size.z - 0.1), Vector3(0, 0.42, 0.02), Color(0.95, 0.95, 0.93)],
				[Vector3(size.x, 1.0, 0.1), Vector3(0, 0.5, -size.z * 0.5 + 0.05), wood], [Vector3(size.x - 0.12, 0.08, size.z * 0.55), Vector3(0, 0.56, 0.35), fabric],
				[Vector3(0.6, 0.14, 0.35), Vector3(-0.42, 0.6, -0.75), Color.WHITE], [Vector3(0.6, 0.14, 0.35), Vector3(0.42, 0.6, -0.75), Color.WHITE]]
		"tavolo":
			parts = [[Vector3(size.x, 0.05, size.z), Vector3(0, 0.74, 0), wood]]
			for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				parts.append([Vector3(0.06, 0.72, 0.06), Vector3(c.x * (size.x * 0.5 - 0.08), 0.36, c.y * (size.z * 0.5 - 0.08)), wood])
		"sedia":
			parts = [[Vector3(0.45, 0.05, 0.45), Vector3(0, 0.46, 0), wood], [Vector3(0.45, 0.5, 0.05), Vector3(0, 0.72, -0.2), wood]]
			for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				parts.append([Vector3(0.04, 0.45, 0.04), Vector3(c.x * 0.19, 0.22, c.y * 0.19), wood])
		"tv":
			parts = [[Vector3(1.5, 0.45, 0.45), Vector3(0, 0.22, 0), Color(0.12, 0.12, 0.13)], [Vector3(1.3, 0.75, 0.05), Vector3(0, 0.85, -0.05), Color(0.05, 0.05, 0.06)],
				[Vector3(1.22, 0.68, 0.01), Vector3(0, 0.85, -0.02), Color(0.25, 0.45, 0.75), true]]
		"libreria":
			parts = [[Vector3(size.x, size.y, 0.05), Vector3(0, size.y * 0.5, -size.z * 0.5 + 0.03), wood]]
			for k in 5:
				parts.append([Vector3(size.x, 0.03, size.z), Vector3(0, 0.05 + k * 0.48, 0), wood])
				if k < 4:
					var x := -size.x * 0.5 + 0.1
					var bi := 0
					while x < size.x * 0.5 - 0.1:
						var w := 0.05 + (absi((id + str(k) + str(bi)).hash()) % 5) * 0.012
						parts.append([Vector3(w, 0.32, 0.25), Vector3(x + w * 0.5, 0.25 + k * 0.48, 0), Color.from_hsv(float(absi((str(k) + str(bi)).hash()) % 100) / 100.0, 0.55, 0.6)])
						x += w + 0.01
						bi += 1
		"lampada":
			parts = [[Vector3(0.3, 0.04, 0.3), Vector3(0, 0.02, 0), Color(0.15, 0.15, 0.15)], [Vector3(0.03, 1.5, 0.03), Vector3(0, 0.77, 0), Color(0.2, 0.2, 0.2)],
				[Vector3(0.38, 0.3, 0.38), Vector3(0, 1.55, 0), Color(1.0, 0.92, 0.75), true]]
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.85, 0.6)
			l.light_energy = 1.0
			l.omni_range = 5.0
			l.position = Vector3(0, 1.5, 0)
			root.add_child(l)
		"tappeto":
			parts = [[size, Vector3(0, 0.01, 0), Color(0.55, 0.12, 0.1)], [size * Vector3(0.82, 1.2, 0.78), Vector3(0, 0.012, 0), Color(0.85, 0.7, 0.4)],
				[size * Vector3(0.6, 1.4, 0.5), Vector3(0, 0.014, 0), Color(0.2, 0.15, 0.4)]]
		"pianta":
			parts = [[Vector3(0.42, 0.42, 0.42), Vector3(0, 0.21, 0), Color(0.6, 0.3, 0.18)], [Vector3(0.55, 0.8, 0.55), Vector3(0, 0.85, 0), Color(0.2, 0.45, 0.18)]]
		"scrivania":
			parts = [[Vector3(1.4, 0.05, 0.7), Vector3(0, 0.74, 0), wood], [Vector3(0.05, 0.72, 0.68), Vector3(-0.66, 0.36, 0), wood], [Vector3(0.05, 0.72, 0.68), Vector3(0.66, 0.36, 0), wood],
				[Vector3(0.6, 0.38, 0.04), Vector3(0, 1.0, -0.2), Color(0.05, 0.05, 0.06)], [Vector3(0.55, 0.33, 0.01), Vector3(0, 1.0, -0.175), Color(0.3, 0.6, 0.9), true],
				[Vector3(0.45, 0.02, 0.15), Vector3(0, 0.77, 0.12), Color(0.12, 0.12, 0.12)]]
		"armadio":
			parts = [[size, Vector3(0, size.y * 0.5, 0), wood.lightened(0.15)], [Vector3(0.02, size.y - 0.1, 0.01), Vector3(0, size.y * 0.5, size.z * 0.5 + 0.005), wood.darkened(0.3)],
				[Vector3(0.04, 0.2, 0.03), Vector3(-0.08, 1.1, size.z * 0.5 + 0.02), Color(0.8, 0.7, 0.4)], [Vector3(0.04, 0.2, 0.03), Vector3(0.08, 1.1, size.z * 0.5 + 0.02), Color(0.8, 0.7, 0.4)]]
		"cassaforte":
			parts = [[size, Vector3(0, size.y * 0.5, 0), Color(0.2, 0.22, 0.24)], [Vector3(0.45, 0.6, 0.02), Vector3(0, 0.45, size.z * 0.5 + 0.01), Color(0.3, 0.32, 0.35)],
				[Vector3(0.12, 0.12, 0.05), Vector3(0.1, 0.5, size.z * 0.5 + 0.04), Color(0.8, 0.7, 0.3)], [Vector3(0.05, 0.03, 0.01), Vector3(-0.15, 0.72, size.z * 0.5 + 0.03), Color(0.1, 1.0, 0.2), true]]
		"acquario":
			parts = [[Vector3(1.3, 0.7, 0.45), Vector3(0, 0.35, 0), wood], [Vector3(1.2, 0.6, 0.4), Vector3(0, 1.0, 0), Color(0.15, 0.45, 0.8), true],
				[Vector3(1.25, 0.05, 0.42), Vector3(0, 1.32, 0), Color(0.1, 0.1, 0.1)]]
		"bar":
			parts = [[Vector3(size.x, 1.05, size.z), Vector3(0, 0.52, 0), wood], [Vector3(size.x + 0.1, 0.05, size.z + 0.1), Vector3(0, 1.08, 0), Color(0.12, 0.1, 0.08)]]
			for k in 7:
				parts.append([Vector3(0.08, 0.3, 0.08), Vector3(-0.8 + k * 0.26, 1.25, -0.15), Color.from_hsv(k / 7.0, 0.6, 0.6)])
		"biliardo":
			parts = [[Vector3(size.x, 0.12, size.z), Vector3(0, 0.78, 0), wood], [Vector3(size.x - 0.2, 0.02, size.z - 0.2), Vector3(0, 0.85, 0), Color(0.1, 0.45, 0.2)],
				[Vector3(size.x - 0.4, 0.66, size.z - 0.4), Vector3(0, 0.36, 0), wood.darkened(0.2)]]
		"pianoforte":
			parts = [[Vector3(1.5, 0.35, 1.9), Vector3(0, 0.8, 0), Color(0.03, 0.03, 0.03)], [Vector3(1.3, 0.06, 0.18), Vector3(0, 0.75, 0.9), Color(0.95, 0.95, 0.95)],
				[Vector3(0.08, 0.6, 0.08), Vector3(-0.6, 0.3, 0.8), Color(0.03, 0.03, 0.03)], [Vector3(0.08, 0.6, 0.08), Vector3(0.6, 0.3, 0.8), Color(0.03, 0.03, 0.03)],
				[Vector3(0.08, 0.6, 0.08), Vector3(0, 0.3, -0.8), Color(0.03, 0.03, 0.03)]]
	for pr: Array in parts:
		var bm := BoxMesh.new()
		bm.size = pr[0]
		var m := StandardMaterial3D.new()
		m.albedo_color = pr[2]
		m.roughness = 0.55
		if pr.size() > 3 and pr[3]:
			m.emission_enabled = true
			m.emission = pr[2]
			m.emission_energy_multiplier = 1.5
		bm.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.position = pr[1]
		root.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1 | FURN_LAYER if id != "tappeto" else FURN_LAYER
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, maxf(size.y, 0.05), size.z)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, maxf(size.y, 0.05) * 0.5, 0)
	body.add_child(cs)
	root.add_child(body)
	root.set_meta("id", id)
	return root


# --- Salvataggio ----------------------------------------------------------------------------------


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if d is Dictionary:
		for id: String in (d.get("owned", {}) as Dictionary):
			if not prop(id).is_empty():
				owned[id] = d["owned"][id]


func save() -> void:
	if main.get("_args").has("autoquit"):
		return  # le prove non toccano le case di chi gioca
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"owned": owned}))
