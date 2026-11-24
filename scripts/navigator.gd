class_name Navigator
extends RefCounted

## Indicazioni stradali in stile Google Maps: percorso a piedi sulle strade vere (grafo del traffico, senza
## sensi unici) da un punto a una destinazione, con i passaggi "Prosegui su… / Gira a destra in…".

var city: CityBuilder
var _astar := AStar2D.new()


func setup(c: CityBuilder, traffic: Traffic) -> void:
	city = c
	for i in traffic._pos.size():
		_astar.add_point(i, traffic._pos[i])
	for i in traffic._adj.size():
		for e: Array in traffic._adj[i]:
			var j := int(e[0])
			if not _astar.are_points_connected(i, j):
				_astar.connect_points(i, j, true)


## Percorso da from a to (metri, x/z). Ritorna {points: PackedVector2Array, length: float, steps: Array di
## [testo, metri]}. Se le strade non aiutano (destinazione vicina) è una linea dritta.
func route(from: Vector2, to: Vector2) -> Dictionary:
	var pts := PackedVector2Array([from])
	if from.distance_to(to) > 60.0 and _astar.get_point_count() > 0:
		var a := _astar.get_closest_point(from)
		var b := _astar.get_closest_point(to)
		var path := _astar.get_point_path(a, b)
		pts.append_array(path)
	pts.append(to)
	pts = _trim(pts)
	var length := 0.0
	for i in range(1, pts.size()):
		length += pts[i - 1].distance_to(pts[i])
	return {"points": pts, "length": length, "steps": _steps(pts)}


## Toglie i pezzi che tornano indietro all'inizio e alla fine (il nodo più vicino può stare alle spalle).
func _trim(pts: PackedVector2Array) -> PackedVector2Array:
	while pts.size() > 2 and pts[0].distance_to(pts[2]) < pts[1].distance_to(pts[2]):
		pts.remove_at(1)
	while pts.size() > 2:
		var n := pts.size()
		if pts[n - 1].distance_to(pts[n - 3]) < pts[n - 2].distance_to(pts[n - 3]):
			pts.remove_at(n - 2)
		else:
			break
	return pts


## Passaggi: tratti consecutivi sulla stessa via uniti; a ogni cambio di via la svolta (destra/sinistra/dritto).
func _steps(pts: PackedVector2Array) -> Array:
	var groups := []  # [nome, metri, direzione iniziale, direzione finale]
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var d := a.distance_to(b)
		if d < 0.5:
			continue
		var mid := (a + b) * 0.5
		var n := city.street_name(Vector3(mid.x, 0, mid.y), 18.0)
		var dir := (b - a) / d
		if not groups.is_empty() and (n == "" or n == groups[-1][0]):
			groups[-1][1] += d
			groups[-1][3] = dir
		else:
			groups.append([n, d, dir, dir])
	var out := []
	for k in groups.size():
		var g: Array = groups[k]
		var name: String = g[0] if g[0] != "" else "la strada"
		var text := ""
		if k == 0:
			text = "Prosegui su %s" % name
		else:
			var prev: Vector2 = groups[k - 1][3]
			var cur: Vector2 = g[2]
			var cross := prev.x * cur.y - prev.y * cur.x  # z verso sud: positivo = svolta a destra
			if prev.dot(cur) > 0.85:
				text = "Continua dritto su %s" % name
			elif cross > 0.0:
				text = "Gira a destra in %s" % name
			else:
				text = "Gira a sinistra in %s" % name
		out.append([text, float(g[1]), name])
	# Tratti cortissimi (incroci, raccordi) dentro il passaggio precedente; poi la stessa via una volta sola.
	var merged := []
	for s: Array in out:
		if not merged.is_empty() and (float(s[1]) < 15.0 or s[2] == merged[-1][2]):
			merged[-1][1] += float(s[1])
		else:
			merged.append(s)
	return merged


static func fmt_dist(m: float) -> String:
	if m >= 1000.0:
		return "%.1f km" % (m / 1000.0)
	return "%d m" % (roundi(m / 10.0) * 10 if m > 50.0 else roundi(m))


## Minuti a piedi (passo normale ~1,4 m/s, come Google Maps).
static func walk_minutes(m: float) -> int:
	return maxi(1, roundi(m / 1.4 / 60.0))
