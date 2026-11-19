class_name MapView
extends Control

## Mappa in stile Maps, con il nord in alto: base (data/minimap.png), nomi delle vie lungo le strade,
## icone dei luoghi (monumenti, musei, chiese, bar, negozi, armerie...), giocatori, segnalino.
## La stessa classe fa da minimappa (mini = true) e da mappa grande (tasto M: zoom con la rotella,
## trascina per spostarti, clic sinistro su un luogo per le indicazioni, clic destro per un segnalino libero).

## Destinazione scelta sulla mappa (Vector2 in metri, o null per toglierla) e il suo nome.
signal waypoint_changed(pos: Variant, label: String)

const CATS := {
	"monument": [Color(0.78, 0.32, 0.2), "M"],
	"culture": [Color(0.55, 0.3, 0.72), "A"],
	"worship": [Color(0.42, 0.42, 0.52), "+"],
	"food": [Color(0.95, 0.55, 0.15), "R"],
	"shop": [Color(0.2, 0.5, 0.85), "S"],
	"hotel": [Color(0.82, 0.3, 0.5), "H"],
	"bank": [Color(0.25, 0.6, 0.3), "B"],
	"health": [Color(0.15, 0.7, 0.45), "F"],
	"police": [Color(0.15, 0.25, 0.6), "P"],
	"building": [Color(0.5, 0.5, 0.5), "·"],
	"gun": [Color(0.9, 0.1, 0.08), "G"],
	"bar": [Color(0.96, 0.55, 0.08), "B"],
	"pharmacy": [Color(0.1, 0.68, 0.3), "+"],
	"dealer": [Color(0.6, 0.25, 0.9), "$"],
	"enter": [Color(0.85, 0.65, 0.1), "E"],
	"heli": [Color(0.2, 0.55, 0.95), "H"],
	"boss": [Color(0.1, 0.1, 0.1), "☠"],
	"banca": [Color(0.85, 0.65, 0.1), "€"],
	"mission": [Color(0.95, 0.8, 0.1), "M"],
	"casa": [Color(0.2, 0.7, 0.35), "C"],
	"casa_mia": [Color(0.2, 0.45, 0.95), "C"],
}
## Luoghi dove si fa qualcosa: segni grandi, colorati, col nome sempre scritto. Gli altri sono solo di riferimento.
const USEFUL := ["gun", "bar", "pharmacy", "dealer", "banca", "mission", "casa", "casa_mia", "enter", "heli", "boss"]
const USEFUL_NAMES := {
	"gun": "Armeria: armi e munizioni", "pharmacy": "Farmacia: cura", "bar": "Bar: cibo che cura, rapine",
	"dealer": "Spacciatore: erba, fumo, cocaina, MD, LSD", "enter": "Palazzo esplorabile", "heli": "Elicottero (F per salire)", "boss": "Boss di un clan (E per parlarci)", "banca": "Banca: conto, bancomat, rapine", "mission": "Missione (E dal contatto)", "casa": "Casa in vendita", "casa_mia": "Casa tua",
}

var mini := true
var city: CityBuilder
var player: Player
var others: Callable  # func() -> Array di [Vector3 posizione, String nome]
var police_dots: Callable  # func() -> Array di Vector3 (agenti e volanti)
var zones_fn: Callable  # func() -> Array di [poligono, colore, nome] (territori dei clan)
var dynamic_pois: Callable  # func() -> Array di luoghi che cambiano durante la partita
var extra_pois: Array = []  # luoghi del gioco (armerie, negozi, edifici esplorabili): [x, z, nome, categoria]
var waypoint: Variant = null  # Vector2 in metri, o null
var dest_name := ""  # nome della destinazione
var route: Dictionary = {}  # dal Navigator: points, length, steps
var center := Vector2.ZERO  # metri
var scale_px := 0.9  # pixel per metro
var _tex: Texture2D
var _font: Font
var _dragging := false
var _press_pos := Vector2.ZERO
var _follow := true
var _hover := []  # luogo sotto il mouse o il mirino: [x, z, nome, categoria]


func setup(c: CityBuilder, p: Player, is_mini: bool) -> void:
	city = c
	player = p
	mini = is_mini
	_font = ThemeDB.fallback_font
	_tex = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path("res://data/minimap.png")))
	clip_contents = true
	if mini:
		set_anchors_preset(Control.PRESET_TOP_RIGHT)
		offset_left = -290
		offset_right = -20
		offset_top = 20
		offset_bottom = 290
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		scale_px = 0.85
	else:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		scale_px = 0.45


func open_at(pos: Vector2) -> void:
	center = pos
	_follow = false
	visible = true


var _redraw_t := 0.0


func _process(delta: float) -> void:
	if not visible or player == null:
		return
	if mini:
		# La minimappa si ridisegna 30 volte al secondo: basta per seguire il giocatore e costa la metà.
		_redraw_t += delta
		if _redraw_t < 1.0 / 30.0:
			return
		_redraw_t = 0.0
		center = Vector2(player.global_position.x, player.global_position.z)
	else:
		# Mappa grande col joypad (o WASD): levetta sinistra sposta, grilletti zoom, A / Croce / Spazio segnalino al centro.
		var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		center += mv * 700.0 * delta / scale_px
		var z := Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
		if z != 0.0:
			scale_px = clampf(scale_px * pow(2.0, z * delta * 1.5), 0.12, 5.0)
		if mv != Vector2.ZERO:
			_hover = _poi_at(size * 0.5)
		if Input.is_action_just_pressed("jump"):
			_choose(size * 0.5)
	queue_redraw()


## Clic (o A del joypad) in s: un luogo lì vicino diventa la destinazione; sul segnalino lo toglie;
## altrimenti, se libero, mette un segnalino senza nome.
func _choose(s: Vector2, free_pin := true) -> void:
	if waypoint != null and to_screen(waypoint).distance_to(s) < 14.0:
		waypoint_changed.emit(null, "")
		return
	var poi := _poi_at(s)
	if not poi.is_empty():
		waypoint_changed.emit(Vector2(poi[0], poi[1]), String(poi[2]))
	elif free_pin:
		waypoint_changed.emit(to_world(s), "Segnalino")


## Tutti i luoghi della mappa (OpenStreetMap e del gioco).
func _all_pois() -> Array:
	return city.data.get("pois", []) + extra_pois + (dynamic_pois.call() as Array if dynamic_pois.is_valid() else [])


## Il luogo mostrato più vicino al punto s dello schermo (entro 16 pixel), o [].
func _poi_at(s: Vector2) -> Array:
	var best := []
	var best_d := 16.0
	for p: Array in _all_pois():
		if not _poi_shown(p):
			continue
		var at := to_screen(Vector2(p[0], p[1]))
		if String(p[3]) in USEFUL:
			at += Vector2(0, -(9.0 if mini else 12.0) * 1.55)  # la testa dello spillo
		var d := at.distance_to(s)
		if d < best_d:
			best_d = d
			best = p
	return best


func _poi_shown(p: Array) -> bool:
	var cat: String = p[3]
	if cat in USEFUL:
		return true
	if mini:
		return false
	if cat == "monument" or cat == "culture":
		return scale_px >= 0.35
	if cat == "building":
		return scale_px >= 1.5
	return scale_px >= 0.8


func to_screen(w: Vector2) -> Vector2:
	return size * 0.5 + (w - center) * scale_px


func to_world(s: Vector2) -> Vector2:
	return center + (s - size * 0.5) / scale_px


func _gui_input(event: InputEvent) -> void:
	if mini:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var before := to_world(mb.position)
			scale_px = clampf(scale_px * (1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 0.12, 5.0)
			center += before - to_world(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_choose(mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = true
			_press_pos = mb.position
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
		if (event as InputEventMouseButton).position.distance_to(_press_pos) < 6.0:
			_choose((event as InputEventMouseButton).position, false)  # clic sinistro: solo sui luoghi
	elif event is InputEventMouseMotion:
		if _dragging:
			center -= event.relative / scale_px
		_hover = _poi_at((event as InputEventMouseMotion).position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not _hover.is_empty() else Control.CURSOR_ARROW
	accept_event()


func _draw() -> void:
	if _tex == null or city == null:
		return
	var bg := Color(0.84, 0.82, 0.77)
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	# Base: la texture della mappa (1 pixel = city.cell metri) nella porzione visibile.
	var tl := to_world(Vector2.ZERO)
	var br := to_world(size)
	# Solo la parte di mappa che esiste: fuori dal quartiere resta lo sfondo.
	var tex_world := Rect2(city.origin, Vector2(_tex.get_width(), _tex.get_height()) * city.cell)
	var vis := tex_world.intersection(Rect2(tl, br - tl))
	if vis.size.x > 0.0 and vis.size.y > 0.0:
		var src := Rect2((vis.position - city.origin) / city.cell, vis.size / city.cell)
		draw_texture_rect_region(_tex, Rect2(to_screen(vis.position), vis.size * scale_px), src)
	var view := Rect2(tl, br - tl).abs().grow(40.0)
	_draw_zones()
	_draw_route()
	_draw_labels(view)
	_draw_pois(view)
	_draw_players()
	_draw_waypoint()
	if not mini:
		_draw_hover()
		_draw_directions()
	if mini:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.1, 0.85), false, 3.0)
		draw_string(_font, Vector2(size.x * 0.5 - 5, 18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
	else:
		# Mirino al centro: lì va il segnalino messo col joypad.
		var c := size * 0.5
		for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * 6.0, c + d * 16.0, Color(0.1, 0.1, 0.1, 0.8), 2.0)
		_draw_legend()


## Territori dei clan: velo del colore del clan e bordo; sulla mappa grande anche il nome della zona.
func _draw_zones() -> void:
	if not zones_fn.is_valid():
		return
	for zd: Array in zones_fn.call():
		var poly: PackedVector2Array = zd[0]
		if poly.size() < 3:
			continue
		var col: Color = zd[1]
		var pts := PackedVector2Array()
		var c := Vector2.ZERO
		for p in poly:
			pts.append(to_screen(p))
			c += p
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.13 if mini else 0.17))
		pts.append(pts[0])
		draw_polyline(pts, Color(col.r, col.g, col.b, 0.6), 2.0 if mini else 3.0)
		if not mini:
			_text(to_screen(c / poly.size()), String(zd[2]).to_upper(), 16, col.darkened(0.35), 0.0, Color(1, 1, 1, 0.75))


func _text(pos: Vector2, s: String, fsize: int, col: Color, angle := 0.0, outline := Color(1, 1, 1, 0.9)) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_set_transform(pos, angle, Vector2.ONE)
	draw_string_outline(_font, Vector2(-w * 0.5, fsize * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, outline)
	draw_string(_font, Vector2(-w * 0.5, fsize * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_labels(view: Rect2) -> void:
	# Più si ingrandisce, più vie compaiono.
	var min_imp := 3 if scale_px < 0.35 else (2 if scale_px < 0.75 else (1 if scale_px < 1.5 else 0))
	if mini:
		min_imp = 2
	var fsize := int(clampf(9.0 + scale_px * 6.0, 10.0, 18.0))
	for l: Array in city.data.get("labels", []):
		if int(l[4]) < min_imp:
			continue
		var w := Vector2(l[0], l[1])
		if not view.has_point(w):
			continue
		_text(to_screen(w), String(l[3]), fsize + int(l[4]), Color(0.25, 0.25, 0.28), float(l[2]))


func _draw_pois(view: Rect2) -> void:
	var all := _all_pois()
	# Prima, piccoli e sbiaditi, i luoghi solo di riferimento (monumenti, chiese, negozi veri...).
	for p: Array in all:
		var cat: String = p[3]
		if cat in USEFUL or not _poi_shown(p):
			continue
		var w := Vector2(p[0], p[1])
		if not view.has_point(w):
			continue
		var s := to_screen(w)
		var col: Color = CATS.get(cat, CATS["building"])[0]
		col = col.lerp(Color(0.55, 0.55, 0.55), 0.45)
		col.a = 0.6
		draw_circle(s, 4.5, Color(1, 1, 1, 0.6))
		draw_circle(s, 3.5, col)
		if scale_px > 1.6:
			_text(s + Vector2(0, -11), String(p[2]), 10, Color(0.35, 0.35, 0.35, 0.85))
	# Poi, sopra a tutto, i luoghi dove si fa qualcosa: spilli grandi e colorati con il nome.
	for p: Array in all:
		var cat: String = p[3]
		if not cat in USEFUL:
			continue
		var w := Vector2(p[0], p[1])
		if not view.has_point(w):
			continue
		_pin(to_screen(w), cat, 9.0 if mini else 12.0)
		if not mini and scale_px > 0.2:
			var label := String(p[2])
			_text(to_screen(w) + Vector2(0, -32 if not mini else -26), label, 14, Color(0.08, 0.08, 0.08))


## Spillo stile Maps: goccia colorata con bordo bianco e simbolo (croce per le farmacie).
func _pin(s: Vector2, cat: String, r: float) -> void:
	var col: Color = CATS[cat][0]
	var tip := s
	var c := s + Vector2(0, -r * 1.55)
	draw_circle(c + Vector2(1.5, 2.0), r + 2.5, Color(0, 0, 0, 0.25))  # ombra
	draw_colored_polygon(PackedVector2Array([tip, c + Vector2(-r * 0.75, r * 0.55), c + Vector2(r * 0.75, r * 0.55)]), Color.WHITE)
	draw_circle(c, r + 2.5, Color.WHITE)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -2.5), c + Vector2(-r * 0.6, r * 0.5), c + Vector2(r * 0.6, r * 0.5)]), col)
	draw_circle(c, r, col)
	if cat == "pharmacy":
		var a := r * 0.62
		var b := r * 0.22
		draw_rect(Rect2(c - Vector2(a, b), Vector2(a * 2, b * 2)), Color.WHITE)
		draw_rect(Rect2(c - Vector2(b, a), Vector2(b * 2, a * 2)), Color.WHITE)
	else:
		_text(c, CATS[cat][1], int(r * 1.25), Color.WHITE, 0.0, Color(0, 0, 0, 0))


func _arrow(s: Vector2, yaw: float, col: Color, r := 11.0) -> void:
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([s + fwd * r, s - fwd * r * 0.6 + side * r * 0.65, s - fwd * r * 0.25,
		s - fwd * r * 0.6 - side * r * 0.65]), col)


func _draw_players() -> void:
	if police_dots.is_valid():
		var blink := int(Time.get_ticks_msec() / 250) % 2 == 0
		for p: Vector3 in police_dots.call():
			var s := to_screen(Vector2(p.x, p.z))
			draw_circle(s, 6.0, Color.WHITE)
			draw_circle(s, 4.5, Color(0.9, 0.1, 0.1) if blink else Color(0.15, 0.3, 1.0))
	if others.is_valid():
		for o: Array in others.call():
			var p: Vector3 = o[0]
			var s := to_screen(Vector2(p.x, p.z))
			draw_circle(s, 7.0, Color.WHITE)
			draw_circle(s, 5.5, Color(0.2, 0.55, 1.0))
			if not mini:
				_text(s + Vector2(0, -16), String(o[1]), 13, Color(0.1, 0.25, 0.6))
	if player:
		var me := to_screen(Vector2(player.global_position.x, player.global_position.z))
		var yaw := player.cam_yaw
		_arrow(me, yaw, Color(0.85, 0.15, 0.1), 12.0 if mini else 14.0)


func _draw_waypoint() -> void:
	if waypoint == null:
		return
	var s := to_screen(waypoint)
	if size.x < 40.0 or size.y < 40.0:
		return
	var inside := Rect2(Vector2.ZERO, size).grow(-10).has_point(s)
	if not inside:
		# Freccia sul bordo verso il segnalino.
		var c := size * 0.5
		var d := (s - c).normalized()
		var t := minf((size.x * 0.5 - 14) / maxf(absf(d.x), 0.001), (size.y * 0.5 - 14) / maxf(absf(d.y), 0.001))
		s = c + d * t
	draw_circle(s, 9.0, Color.WHITE)
	draw_circle(s, 7.0, Color(0.95, 0.75, 0.1))
	if player:
		var dist: float = route["length"] if not route.is_empty() else \
			Vector2(player.global_position.x, player.global_position.z).distance_to(waypoint)
		_text(s + Vector2(0, 16), Navigator.fmt_dist(dist), 12, Color(0.2, 0.15, 0.0))


## Percorso in blu come su Google Maps, con bordo bianco.
func _draw_route() -> void:
	if route.is_empty() or waypoint == null:
		return
	var pts: PackedVector2Array = route["points"]
	if pts.size() < 2:
		return
	var sp := PackedVector2Array()
	for p in pts:
		sp.append(to_screen(p))
	var w := clampf(scale_px * 7.0, 4.0, 9.0)
	draw_polyline(sp, Color.WHITE, w + 3.0, true)
	draw_polyline(sp, Color(0.26, 0.52, 0.96), w, true)


## Luogo sotto il mouse o il mirino: cerchio evidenziato e nome con l'invito a cliccare.
func _draw_hover() -> void:
	if _hover.is_empty():
		return
	var s := to_screen(Vector2(_hover[0], _hover[1]))
	draw_arc(s, 13.0, 0, TAU, 32, Color(0.26, 0.52, 0.96), 3.0)
	var txt := "%s · clic o A: indicazioni" % String(_hover[2])
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var box := Rect2(s + Vector2(16, -30), Vector2(tw + 16, 24))
	draw_rect(box, Color(1, 1, 1, 0.95))
	draw_rect(box, Color(0.26, 0.52, 0.96), false, 1.5)
	draw_string(_font, box.position + Vector2(8, 17), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.1, 0.1, 0.1))


## Pannello delle indicazioni (a destra): destinazione, distanza, minuti a piedi, passaggi.
func _draw_directions() -> void:
	if route.is_empty() or waypoint == null:
		return
	var steps: Array = route["steps"]
	var n := mini(steps.size(), 9)
	var w := 380.0
	var x := size.x - w - 16.0
	var h := 96.0 + n * 24.0 + 30.0
	draw_rect(Rect2(x, 16, w, h), Color(1, 1, 1, 0.94))
	draw_rect(Rect2(x, 16, w, 6), Color(0.26, 0.52, 0.96))
	var title := dest_name if dest_name != "" else "Destinazione"
	draw_string(_font, Vector2(x + 14, 48), title, HORIZONTAL_ALIGNMENT_LEFT, w - 28, 18, Color(0.1, 0.1, 0.1))
	var length: float = route["length"]
	draw_string(_font, Vector2(x + 14, 74), "%s · %d min a piedi" % [Navigator.fmt_dist(length), Navigator.walk_minutes(length)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.1, 0.45, 0.2))
	draw_line(Vector2(x + 14, 88), Vector2(x + w - 14, 88), Color(0.85, 0.85, 0.85), 1.0)
	var y := 110.0
	for i in n:
		var st: Array = steps[i]
		draw_circle(Vector2(x + 22, y - 5), 4.0, Color(0.26, 0.52, 0.96))
		draw_string(_font, Vector2(x + 34, y), String(st[0]), HORIZONTAL_ALIGNMENT_LEFT, w - 120, 14, Color(0.15, 0.15, 0.15))
		draw_string(_font, Vector2(x + w - 80, y), Navigator.fmt_dist(float(st[1])), HORIZONTAL_ALIGNMENT_RIGHT, 66, 14, Color(0.4, 0.4, 0.4))
		y += 24.0
	if steps.size() > n:
		draw_string(_font, Vector2(x + 34, y), "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.4, 0.4, 0.4))
		y += 24.0
	draw_string(_font, Vector2(x + 14, y + 4), "Arrivo: %s" % title, HORIZONTAL_ALIGNMENT_LEFT, w - 28, 14, Color(0.1, 0.1, 0.1))
	draw_string(_font, Vector2(x + 14, 16 + h - 8), "Clic destro / A sul segnalino giallo per toglierlo",
		HORIZONTAL_ALIGNMENT_LEFT, w - 28, 12, Color(0.5, 0.5, 0.5))


func _draw_legend() -> void:
	var lines := [
		"Mappa di Roma – Flaminio", "Clic su un luogo: indicazioni · Clic destro: segnalino · Rotella: zoom · Trascina: sposta · M o Esc: chiudi",
		"Joypad: levetta sinistra sposta · grilletti zoom · A / Croce sul luogo al centro: indicazioni · B / Cerchio chiudi",
	]
	draw_rect(Rect2(16, 16, 800, 80), Color(1, 1, 1, 0.85))
	draw_string(_font, Vector2(28, 40), lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.1, 0.1, 0.1))
	draw_string(_font, Vector2(28, 64), lines[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 0.3, 0.3))
	draw_string(_font, Vector2(28, 86), lines[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 0.3, 0.3))
	# Legenda: prima i luoghi dove si fa qualcosa (spilli), poi quelli solo di riferimento (puntini sbiaditi).
	var y := 112.0
	draw_rect(Rect2(16, y, 270, 30 + USEFUL.size() * 34), Color(1, 1, 1, 0.92))
	draw_string(_font, Vector2(28, y + 22), "Dove fai qualcosa", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.1, 0.1, 0.1))
	y += 34.0
	for k: String in USEFUL:
		_pin(Vector2(36, y + 24), k, 10.0)
		draw_string(_font, Vector2(58, y + 14), USEFUL_NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.12, 0.12, 0.12))
		y += 34.0
	y += 14.0
	var refs := {"monument": "Monumenti", "culture": "Musei e teatri", "worship": "Chiese", "food": "Ristoranti veri",
		"shop": "Negozi veri", "health": "Farmacie vere (non si entra)"}
	draw_rect(Rect2(16, y, 270, 28 + refs.size() * 20), Color(1, 1, 1, 0.75))
	draw_string(_font, Vector2(28, y + 19), "Solo riferimento", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.4, 0.4))
	y += 30.0
	for k: String in refs:
		var col: Color = CATS[k][0].lerp(Color(0.55, 0.55, 0.55), 0.45)
		draw_circle(Vector2(32, y + 6), 4.0, col)
		draw_string(_font, Vector2(46, y + 11), refs[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.4, 0.4))
		y += 20.0
