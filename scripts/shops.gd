class_name Shops
extends Node3D

## Negozi del gioco sui locali reali di OpenStreetMap (vedi venues.gd): bar (cibo che cura), farmacie (kit medico),
## supermercati che nel gioco fanno da armerie (armi, munizioni, giubbotto). Si entra dalla porta, si va al bancone
## e si compra dal commesso (E); se il commesso non c'è (rapinato, scappato, morto) il locale è chiuso.
## Il fornitore dello spaccio è un personaggio che aspetta in un vialetto del verde.

signal opened(shop: Dictionary)

const KINDS := {
	"gun": {"title": "Armeria", "color": Color(0.85, 0.15, 0.1), "cat": "gun"},
	"bar": {"title": "Bar", "color": Color(0.95, 0.6, 0.15), "cat": "bar"},
	"pharmacy": {"title": "Farmacia", "color": Color(0.15, 0.75, 0.4), "cat": "pharmacy"},
	"dealer": {"title": "Fornitore", "color": Color(0.6, 0.25, 0.9), "cat": "dealer"},
}
## Spaccio: pacchetti comprati dal fornitore e rivenduti ai passanti (vedi main.gd, _try_sell).
const STASH := [
	{"name": "5 pacchetti", "n": 5, "price": 150},
	{"name": "10 pacchetti", "n": 10, "price": 280},
	{"name": "20 pacchetti", "n": 20, "price": 520},
]
const FOOD := [
	{"id": "caffe", "name": "Caffè", "price": 2, "heal": 10},
	{"id": "cornetto", "name": "Cornetto", "price": 3, "heal": 20},
	{"id": "supplì", "name": "Supplì", "price": 4, "heal": 30},
	{"id": "pizza", "name": "Pizza al taglio", "price": 8, "heal": 60},
]
const PHARMA := [
	{"id": "cerotti", "name": "Cerotti", "price": 15, "heal": 25},
	{"id": "kit", "name": "Kit medico", "price": 120, "heal": 100},
]

var shops: Array = []  # {kind, pos: Vector3, name}
var player: Player


func setup(city: CityBuilder, p: Player) -> void:
	player = p
	for i in city.venues.size():
		var v: Dictionary = city.venues[i]
		var room: Dictionary = city.venue_rooms[i]
		shops.append({
			"kind": v["kind"], "pos": room["counter_front"], "name": v["name"], "door": room["door2d"],
			"entrance": room["entrance"], "clerk_pos": room["clerk"], "clerk_yaw": room["clerk_yaw"], "venue": true,
		})
	_place_dealers(city)
	for s: Dictionary in shops:
		_marker(s)


## Vecchia scelta (cerchi sul marciapiede davanti ai negozi reali): non più usata, resta per riferimento.
func _setup_rings(city: CityBuilder) -> void:
	var pois: Array = city.data.get("pois", [])
	var used: Array[Vector2] = []
	var pick := func(filter: Callable, kind: String, count: int, min_gap: float) -> void:
		var cands := []
		for poi: Array in pois:
			if filter.call(poi):
				cands.append(poi)
		# Prima quelli vicini al punto di partenza, poi distanziati tra loro.
		cands.sort_custom(func(a: Array, b: Array) -> bool:
			return Vector2(a[0], a[1]).distance_to(Vector2(city.spawn.x, city.spawn.z)) < Vector2(b[0], b[1]).distance_to(Vector2(city.spawn.x, city.spawn.z)))
		var n := 0
		for poi: Array in cands:
			var at := Vector2(poi[0], poi[1])
			var ok := true
			for u in used:
				if u.distance_to(at) < min_gap:
					ok = false
			if not ok:
				continue
			used.append(at)
			var pos := _sidewalk(city, at)
			var label := "%s · %s" % [KINDS[kind]["title"], poi[2]]
			shops.append({"kind": kind, "pos": pos, "name": label, "door": at})
			n += 1
			if n >= count:
				return
	# Le armerie del gioco stanno in negozi di sport, ferramenta, caccia o, in mancanza, in altri negozi.
	pick.call(func(poi: Array) -> bool: return poi[3] == "shop" and String(poi[4]) in ["sports", "hardware", "outdoor", "hunting", "weapons", "doityourself"], "gun", 4, 350.0)
	if shops.size() < 3:
		pick.call(func(poi: Array) -> bool: return poi[3] == "shop", "gun", 3 - shops.size(), 350.0)
	pick.call(func(poi: Array) -> bool: return poi[3] == "food", "bar", 10, 150.0)
	pick.call(func(poi: Array) -> bool: return poi[3] == "health", "pharmacy", 5, 250.0)
	_place_dealers(city)
	for s: Dictionary in shops:
		_marker(s)


## Due fornitori nei vialetti del verde (lontani dalle strade trafficate): uno a ~600 m dalla partenza, uno a ~1,3 km.
## Scelta fissa, uguale su tutti i PC.
func _place_dealers(city: CityBuilder) -> void:
	var sp := Vector2(city.spawn.x, city.spawn.z)
	var cands: Array[Vector2] = []
	for r: Dictionary in city.data["roads"]:
		if r["k"] != "foot" or int(r["b"]) == 1:
			continue
		var pts := city._pts(r["p"])
		if pts.size() < 2:
			continue
		var mid := pts[pts.size() / 2]
		if city.height_at(mid.x, mid.y) < -0.3:
			continue  # niente banchine del Tevere
		cands.append(mid)
	for target: float in [600.0, 1300.0]:
		var best := Vector2.INF
		var best_d := INF
		for c in cands:
			var d := absf(c.distance_to(sp) - target)
			var far_from_shops := true
			for s: Dictionary in shops:
				if Vector2((s["pos"] as Vector3).x, (s["pos"] as Vector3).z).distance_to(c) < 150.0:
					far_from_shops = false
					break
			if far_from_shops and d < best_d:
				best_d = d
				best = c
		if best != Vector2.INF:
			var pos := Vector3(best.x, maxf(city.height_at(best.x, best.y), 0.0), best.y)
			shops.append({"kind": "dealer", "pos": pos, "name": "Fornitore · " + city.street_name(pos, 80.0) if city.street_name(pos, 80.0) != "" else "Fornitore", "door": best})


## Il punto di marciapiede più vicino all'ingresso (i negozi in OSM stanno spesso dentro la sagoma del palazzo).
func _sidewalk(city: CityBuilder, at: Vector2) -> Vector3:
	var best := at
	var best_d := INF
	for r: Dictionary in city.data["roads"]:
		if r["k"] == "tram":
			continue
		var pts := city._pts(r["p"])
		for i in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(at, pts[i], pts[i + 1])
			var d := q.distance_to(at)
			if d < best_d:
				best_d = d
				var off := (at - q).normalized() * (float(r["w"]) * 0.5 + 1.4) if d > 0.1 else Vector2.ZERO
				best = q + off
	return Vector3(best.x, maxf(city.height_at(best.x, best.y), 0.0), best.y)


func _marker(s: Dictionary) -> void:
	var col: Color = KINDS[s["kind"]]["color"]
	if s["kind"] == "dealer":
		# Niente cerchio: c'è il fornitore in persona. Solo il nome sopra la sua posizione, da vicino.
		var tag := Label3D.new()
		tag.text = "Fornitore"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 36
		tag.outline_size = 8
		tag.pixel_size = 0.01
		tag.modulate = col.lightened(0.4)
		add_child(tag)
		tag.global_position = (s["pos"] as Vector3) + Vector3(0, 2.4, 0)
		tag.visibility_range_end = 25.0
		return
	var node := Node3D.new()
	add_child(node)
	node.global_position = s["pos"]
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	ring.material_override = mat
	ring.position.y = 0.06
	ring.scale = Vector3(1, 0.3, 1)
	node.add_child(ring)
	if s.get("venue", false):
		# Dentro il locale basta un cerchio piccolo davanti al bancone; il fascio di luce sta fuori, sulla porta.
		ring.scale = Vector3(0.55, 0.2, 0.55)
		var out := Node3D.new()
		add_child(out)
		out.global_position = s["entrance"]
		node = out
	var label := Label3D.new()
	label.text = String(s["name"])
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.012
	label.modulate = col.lightened(0.4)
	label.position.y = 2.6
	label.visibility_range_end = 80.0
	if not s.get("venue", false):
		node.add_child(label)
	# Fascio di luce verso il cielo, visibile da lontano: rosso alto per le armerie, più basso per bar e farmacie.
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var tall := 120.0 if s["kind"] == "gun" else 25.0
	var gun: bool = s["kind"] == "gun"
	cyl.top_radius = 1.4 if gun else 0.5
	cyl.bottom_radius = 1.0 if gun else 0.5
	cyl.height = tall
	cyl.radial_segments = 8
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmat.albedo_color = Color(minf(col.r * 1.3, 1.0), col.g, col.b, 0.6 if gun else 0.4)
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = tall * 0.5
	beam.visibility_range_begin = 6.0  # da vicino resta solo il cerchio a terra
	beam.visibility_range_end = 1500.0 if s["kind"] == "gun" else 400.0
	node.add_child(beam)
	var tw := ring.create_tween().set_loops()
	tw.tween_property(ring, "scale", Vector3(1.15, 0.3, 1.15), 0.8)
	tw.tween_property(ring, "scale", Vector3(1, 0.3, 1), 0.8)


## Armeria più vicina a pos, o {}.
func nearest(kind: String, pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for s: Dictionary in shops:
		var d := (s["pos"] as Vector3).distance_to(pos)
		if s["kind"] == kind and d < best_d:
			best_d = d
			best = s
	return best


## Negozio davanti al bancone (o accanto al fornitore), se c'è qualcuno a servire; {} altrimenti.
func shop_here() -> Dictionary:
	for s: Dictionary in shops:
		if (s["pos"] as Vector3).distance_to(player.global_position) < (1.6 if s.get("venue", false) else 2.2):
			return s if attended(s) else {}
	return {}


## Il locale è aperto: dietro al bancone c'è il commesso vivo e non rapinato (o il fornitore è al suo posto).
## Vale anche sui PC che vedono solo le copie dei personaggi.
func attended(s: Dictionary) -> bool:
	var at: Vector3 = s.get("clerk_pos", s["pos"])
	for n: Node in get_tree().get_nodes_in_group("pedestrian"):
		if not (n.has_meta("clerk") or n.has_meta("dealer")):
			continue
		if n.get_meta("dead", false) or n.get("dead") == true or n.get_meta("robbed", false):
			continue
		if (n as Node3D).global_position.distance_to(at) < 2.5:
			return true
	return false


func map_pois() -> Array:
	var out := []
	for s: Dictionary in shops:
		var p: Vector3 = s.get("entrance", s["pos"])
		out.append([p.x, p.z, s["name"], KINDS[s["kind"]]["cat"]])
	return out


## Voci in vendita: [testo, prezzo, Callable che consegna la merce].
func items(shop: Dictionary) -> Array:
	var out := []
	match String(shop["kind"]):
		"gun":
			for id: String in Weapons.ORDER:
				var w := Weapons.info(id)
				if int(w.get("price", 0)) <= 0:
					continue
				var kind: String = w["kind"]
				var start := 0
				if kind == "gun" or kind == "rocket":
					start = int(w.get("mag", 10)) * 3
				elif kind == "throw" or kind == "place":
					start = 5
				out.append([String(w["name"]), int(w["price"]), func() -> void: player.give_weapon(id, start)])
				if w.has("ammo_price"):
					var mag: int = int(w.get("mag", 10))
					out.append(["   munizioni (%d)" % (mag * 2 if kind == "gun" else 3), int(w["ammo_price"]),
						func() -> void: player.give_weapon(id, mag * 2 if kind == "gun" else 3)])
			out.append(["Giubbotto antiproiettile", 600, func() -> void: player.armor = Player.MAX_ARMOR])
		"bar":
			for f: Dictionary in FOOD:
				out.append([String(f["name"]), int(f["price"]), func() -> void: player.heal(float(f["heal"]))])
		"pharmacy":
			for f: Dictionary in PHARMA:
				out.append([String(f["name"]), int(f["price"]), func() -> void: player.heal(float(f["heal"]))])
		"dealer":
			# Pacchetti da rivendere ai passanti (E vicino a qualcuno). Se ne portano al massimo Player.MAX_STASH.
			for f: Dictionary in STASH:
				out.append(["%s (ne hai %d, max %d)" % [f["name"], player.stash, Player.MAX_STASH], int(f["price"]),
					func() -> void: player.stash = mini(Player.MAX_STASH, player.stash + int(f["n"]))])
	return out
