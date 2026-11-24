class_name Missions
extends Node3D

## Missioni come in GTA: tre contatti nel quartiere (spillo giallo "M" e colonna di luce), ognuno con le sue
## missioni in fila. Ogni missione ha fasi con un obiettivo (scritto in basso, con il percorso sulla mappa), a
## volte un timer, e fallisce se muori (o se rovini quello che dovevi portare). Alla fine "MISSIONE COMPIUTA",
## soldi e fama. Sono di chi le fa: nemici, auto e pacchi della missione esistono solo sul suo PC.

const CONTACTS := [
	{"name": "Zio Franco", "c": Vector2(-170, -640), "look": "m6", "missions": ["crediti", "auto", "colpo"]},
	{"name": "La Contessa", "c": Vector2(330, -170), "look": "f4", "missions": ["festa", "furgone"]},
	{"name": "Er Meccanico", "c": Vector2(470, -1230), "look": "m5", "missions": ["corsa", "consegna"]},
]
const INFO := {
	"crediti": {"title": "Recupero crediti", "reward": 1500, "fame": 15,
		"intro": "«Mario er Tirchio mi deve duemila euro da sei mesi. Vai a farti pagare. Con le buone o con le cattive.»"},
	"auto": {"title": "Auto per il boss", "reward": 2500, "fame": 20,
		"intro": "«Al boss serve una macchina sportiva, pulita. Ce n'è una parcheggiata a Ponte Milvio: portala al Meccanico senza un graffio.»"},
	"colpo": {"title": "Il colpo grosso", "reward": 8000, "fame": 60,
		"intro": "«È il momento. Svuota il caveau della banca che ti segno: almeno due sacchi. Poi sparisci e torna da me.»"},
	"festa": {"title": "Festa privata", "reward": 5000, "fame": 40,
		"intro": "«Il Commendatore dà una festa ai Parioli. Ha la scorta. Non voglio che arrivi a domani mattina.»"},
	"furgone": {"title": "Furgone portavalori", "reward": 0, "fame": 35,
		"intro": "«Un portavalori fa il cambio a Della Vittoria. Tre guardie, poi il furgone. Quello che c'è dentro è tuo.»"},
	"corsa": {"title": "Corsa clandestina", "reward": 2000, "fame": 10,
		"intro": "«Stanotte si corre. Prendi una macchina e passa da tutti i punti prima che scada il tempo.»"},
	"consegna": {"title": "Consegna calda", "reward": 3000, "fame": 25,
		"intro": "«Un pacco da portare dall'altra parte del quartiere. La polizia sa già tutto: veloce.»"},
}

var main: Node
var city: CityBuilder
var combat: Combat
var active := ""
var stage := 0
var timer := -1.0  # secondi che restano (-1: niente timer)
var done: Array = []  # missioni completate (salvate nelle impostazioni)
var _contacts: Array = []  # [Node3D, indice]
var _things: Array = []  # nodi della missione da togliere alla fine
var _marker: Node3D
var _goal := Vector3.INF
var _data := {}
var _layer: CanvasLayer
var _title: Label
var _sub: Label
var _objective: Label
var _where: Label  # sotto l'obiettivo: dove si trova e quanto manca
var _where_street := ""
var _clock: Label
var _banner_t := 0.0


func setup(m: Node, c: CityBuilder, cb: Combat) -> void:
	main = m
	city = c
	combat = cb
	for i in CONTACTS.size():
		var at := spot(CONTACTS[i]["c"])
		_contacts.append([_contact(at, CONTACTS[i]), i])
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_title = _label(54, Color(1.0, 0.82, 0.25))
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.offset_top = -170
	_title.offset_left = -600
	_title.offset_right = 600
	_sub = _label(24, Color.WHITE)
	_sub.set_anchors_preset(Control.PRESET_CENTER)
	_sub.offset_top = -100
	_sub.offset_left = -600
	_sub.offset_right = 600
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective = _label(22, Color(1.0, 0.95, 0.75))
	_objective.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_objective.offset_top = 92
	_objective.offset_left = -420
	_objective.offset_right = 420
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_where = _label(18, Color(1.0, 0.85, 0.3))
	_where.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_where.offset_top = 124
	_where.offset_left = -420
	_where.offset_right = 420
	_clock = _label(34, Color(1.0, 1.0, 1.0))
	_clock.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_clock.offset_top = 48
	_clock.offset_left = -100
	_clock.offset_right = 100


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.modulate = col
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layer.add_child(l)
	return l


## Punto di vialetto o marciapiede più vicino a c (fuori dalle banchine del Tevere).
func spot(c: Vector2) -> Vector3:
	var best := c
	var best_d := INF
	for r: Dictionary in city.data["roads"]:
		if r["k"] != "foot" or int(r["b"]) == 1:
			continue
		for p in city._pts(r["p"]):
			if city.carve_at(p.x, p.y) < -0.3:
				continue
			var d := p.distance_to(c)
			if d < best_d:
				best_d = d
				best = p
	return Vector3(best.x, city.surface_at(best.x, best.y), best.y)


func _contact(at: Vector3, d: Dictionary) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	var h := Human.new().setup(String(d["look"]))
	n.add_child(h)
	h.play("talk")
	var l := Label3D.new()
	l.text = "%s\n[missioni]" % d["name"]
	l.position.y = 2.3
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 38
	l.outline_size = 10
	l.pixel_size = 0.006
	l.modulate = Color(1.0, 0.85, 0.25)
	l.visibility_range_end = 60.0
	n.add_child(l)
	n.add_child(_beam(Color(1.0, 0.8, 0.15)))
	return n


## Colonna di luce visibile da lontano (contatti e obiettivi).
func _beam(col: Color) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 60.0
	cyl.radial_segments = 12
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, 0.18)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	cyl.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.position.y = 30.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func map_pois() -> Array:
	var out := []
	for c: Array in _contacts:
		var p := (c[0] as Node3D).global_position
		out.append([p.x, p.z, "Missioni · " + String(CONTACTS[int(c[1])]["name"]), "mission"])
	return out


## Contatto vicino al giocatore: [indice contatto, prossima missione o ""] o [].
func contact_near(pos: Vector3) -> Array:
	for c: Array in _contacts:
		if (c[0] as Node3D).global_position.distance_to(pos) < 2.6:
			var i := int(c[1])
			for id: String in CONTACTS[i]["missions"]:
				if not done.has(id):
					return [i, id]
			return [i, ""]
	return []


func hint(pos: Vector3) -> String:
	var c := contact_near(pos)
	if c.is_empty():
		return ""
	if active != "":
		return "%s: «Prima finisci quello che stai facendo.»" % CONTACTS[int(c[0])]["name"]
	if String(c[1]) == "":
		return "%s: «Per ora non ho altro per te.»" % CONTACTS[int(c[0])]["name"]
	return "E / croce su: missione «%s» (%s)" % [INFO[c[1]]["title"], CONTACTS[int(c[0])]["name"]]


func try_start(pos: Vector3) -> bool:
	var c := contact_near(pos)
	if c.is_empty() or active != "" or String(c[1]) == "":
		return false
	start(String(c[1]))
	return true


# --- Svolgimento ------------------------------------------------------------------------------------


func start(id: String) -> void:
	active = id
	stage = 0
	timer = -1.0
	_data = {"money0": main.player.money}
	_banner(INFO[id]["title"].to_upper(), INFO[id]["intro"], 6.0)
	Sfx.play2d("win", -8.0)
	_enter(0)


func _banner(title: String, sub: String, t: float) -> void:
	_title.text = title
	_sub.text = sub
	_banner_t = t


func _objective_set(text: String, goal: Vector3 = Vector3.INF, label := "") -> void:
	_objective.text = text
	_goal = goal
	_where_street = city.street_name(goal, 120.0) if goal != Vector3.INF and city else ""
	if _marker:
		_marker.queue_free()
		_marker = null
	if goal != Vector3.INF:
		main._set_destination(Vector2(goal.x, goal.z), label if label != "" else INFO[active]["title"])
		_marker = Node3D.new()
		add_child(_marker)
		_marker.global_position = goal
		_marker.add_child(_beam(Color(1.0, 0.85, 0.2)))
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 2.2
		t.outer_radius = 2.5
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.85, 0.2, 0.7)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		t.material = m
		ring.mesh = t
		ring.scale = Vector3(1, 0.1, 1)
		ring.position.y = 0.1
		_marker.add_child(ring)
	else:
		main._set_destination(null, "")


func _near(r := 4.0) -> bool:
	return _goal != Vector3.INF and Vector2(main.player.global_position.x - _goal.x, main.player.global_position.z - _goal.z).length() < r


func _contact_pos(name_: String) -> Vector3:
	for c: Array in _contacts:
		if CONTACTS[int(c[1])]["name"] == name_:
			return (c[0] as Node3D).global_position
	return main.player.global_position


func _enemy(at: Vector3, look: String, weapon: String, hp: float, label := "", always := false) -> Gunman:
	var g := Gunman.new()
	g.combat = combat
	g.preset = look
	g.weapon = weapon
	g.health = hp
	g.skill = 0.5
	g.anchor = at
	g.label = label
	g.foe_fn = func(me: Gunman) -> Node3D:
		var p: Player = main.player
		if p.dead:
			return null
		var d := p.global_position.distance_to(me.global_position)
		if always or d < 30.0 or me.health < hp or me.get_meta("alert", false):
			me.set_meta("alert", true)
			return p if d < 90.0 else null
		return null
	g.on_dead = func(me: Gunman, from_peer: int) -> void:
		if from_peer > 0:
			main._on_local_crime("kill", me.global_position)
	add_child(g)
	g.global_position = at + Vector3(0, 0.3, 0)
	_things.append(g)
	return g


func _pickup(at: Vector3, text: String, value: int) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at + Vector3(0, 0.4, 0)
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.35, 0.18)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.15, 0.08)
	m.emission_enabled = true
	m.emission = Color(0.8, 0.6, 0.2)
	m.emission_energy_multiplier = 0.6
	box.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = box
	n.add_child(mi)
	var l := Label3D.new()
	l.text = text
	l.position.y = 0.6
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 32
	l.outline_size = 8
	l.pixel_size = 0.006
	n.add_child(l)
	n.set_meta("value", value)
	_things.append(n)
	return n


func _mission_car(at: Vector3, yaw: float, model: String, paint: Color) -> Car:
	var id := 3000000 + randi() % 100000
	var car := Car.new().setup(id, model, paint)
	car.combat = combat
	car.on_destroyed = main._on_car_destroyed
	main.get_node("Auto").add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, 0.6, 0))
	main.cars.append(car)
	main._extra_cars[id] = car
	_things.append(car)
	return car


## Ingresso in una fase: prepara nemici, oggetti, obiettivo.
func _enter(s: int) -> void:
	stage = s
	var p: Player = main.player
	match active:
		"crediti":
			match s:
				0:
					var at := spot(Vector2(-420, -340))
					_data["debtor"] = _enemy(at, "m8", "", 60.0, "Mario er Tirchio")
					(_data["debtor"] as Gunman).flee_on_hit = true
					_enemy(at + Vector3(2.0, 0, 1.0), "gang_black", "pistola", 110.0)
					_objective_set("Vai da Mario er Tirchio e fatti pagare (colpiscilo).", at, "Mario er Tirchio")
				1:
					var d: Gunman = _data["debtor"]
					_data["case"] = _pickup(d.global_position, "€ 2.000", 2000)
					_objective_set("Prendi i soldi che ha lasciato cadere.", (d.global_position))
				2:
					_objective_set("Riporta i soldi a Zio Franco.", _contact_pos("Zio Franco"))
		"auto":
			match s:
				0:
					var at := spot(Vector2(-120, -1380))
					_data["car"] = _mission_car(at + Vector3(3.0, 0, 0), 0.3, "sports_a", Color(0.85, 0.75, 0.1))
					_objective_set("Ruba l'auto sportiva gialla a Ponte Milvio.", at, "Auto da rubare")
				1:
					main._on_local_crime("theft", p.global_position)
					timer = 180.0
					_objective_set("Portala al Meccanico entro il tempo, senza rovinarla.", _contact_pos("Er Meccanico"), "Officina")
		"colpo":
			match s:
				0:
					var best := 0
					var bd := INF
					for i in main.banks.banks.size():
						var d := (main.banks.banks[i]["room"]["entrance"] as Vector3).distance_to(p.global_position)
						if d < bd and not main.banks.is_closed(i):
							bd = d
							best = i
					_data["bank"] = best
					_data["bags0"] = Banks._count_bits(int(main.banks.banks[best]["st"]["bags"]))
					_objective_set("Entra nella %s e apri il caveau (direttore in ostaggio, trapano o TNT)." % main.banks.banks[best]["room"]["brand"], main.banks.banks[best]["room"]["entrance"], "Banca")
				1:
					_objective_set("Prendi almeno due sacchi di contanti dal caveau.")
				2:
					_objective_set("Semina la polizia.")
				3:
					_objective_set("Torna da Zio Franco.", _contact_pos("Zio Franco"))
		"festa":
			match s:
				0:
					var at := spot(Vector2(520, -60))
					_data["target"] = _enemy(at, "boss", "pistola", 150.0, "Il Commendatore")
					for k in 4:
						var a := TAU * k / 4.0
						_enemy(at + Vector3(cos(a) * 4.0, 0, sin(a) * 4.0), "gang_black", "mitragliatrice" if k % 2 == 0 else "pistola", 130.0)
					_objective_set("Elimina il Commendatore. Ha quattro uomini di scorta.", at, "Il Commendatore")
				1:
					_objective_set("Semina la polizia.")
		"furgone":
			match s:
				0:
					var at := spot(Vector2(-700, 480))
					_data["van"] = _mission_car(at + Vector3(4.0, 0, 0), 1.2, "suv", Color(0.3, 0.32, 0.3))
					(_data["van"] as Car).health = 500.0
					for k in 3:
						_enemy(at + Vector3(2.0 + k * 1.5, 0, 2.5), "guard", "mitragliatrice" if k == 0 else "pistola", 140.0)
					_objective_set("Assalta il portavalori: fai fuori le guardie e fai saltare il furgone.", at, "Portavalori")
				1:
					var v: Car = _data["van"]
					_data["bags"] = []
					for k in 3:
						_data["bags"].append(_pickup(v.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), "€", randi_range(3500, 5500)))
					_objective_set("Prendi i sacchi di contanti.", v.global_position)
				2:
					_objective_set("Semina la polizia.")
		"corsa":
			match s:
				0:
					_objective_set("Sali su un'auto per partire.")
				1:
					var route := _race_route()
					_data["cps"] = route
					_data["cp"] = 0
					timer = 40.0 + route.size() * 16.0
					_objective_set("Checkpoint 1 / %d" % route.size(), route[0], "Checkpoint")
		"consegna":
			match s:
				0:
					var at := spot(Vector2(-100, 900))
					_data["pack"] = _pickup(at, "PACCO", 0)
					_objective_set("Prendi il pacco a Piazza della Marina.", at, "Pacco")
				1:
					main._on_local_crime("dealing", p.global_position)
					main._on_local_crime("robbery", p.global_position)
					timer = 150.0
					var dest := spot(Vector2(380, -950))
					_objective_set("Consegna il pacco al Villaggio Olimpico. La polizia ti cerca!", dest, "Consegna")


func _race_route() -> Array:
	var police: Police = main.police
	var a: Vector3 = main.player.global_position
	var pts := []
	var stops := [Vector3(-380, 0, -300), Vector3(80, 0, 450), Vector3(420, 0, -500), a]
	var from: Vector3 = a
	for s: Vector3 in stops:
		var ids := police.route_to(from, s)
		for k in range(8, ids.size(), 10):
			var q: Vector2 = police._astar.get_point_position(ids[k])
			pts.append(Vector3(q.x, city.surface_at(q.x, q.y), q.y))
		from = s
	if pts.size() < 3:
		for k in 6:
			var a2 := TAU * k / 6.0
			pts.append(spot(Vector2(a.x + cos(a2) * 200.0, a.z + sin(a2) * 200.0)))
	return pts.slice(0, 12)


func _process(delta: float) -> void:
	_banner_t -= delta
	if _banner_t <= 0.0 and _title.text != "":
		_title.text = ""
		_sub.text = ""
	_clock.text = ("%d:%02d" % [int(timer) / 60, int(timer) % 60]) if timer >= 0.0 and active != "" else ""
	_where.text = ""
	if active == "":
		return
	var p: Player = main.player
	if _goal != Vector3.INF and _objective.text != "":
		var dist := Vector2(p.global_position.x - _goal.x, p.global_position.z - _goal.z).length()
		var place := (" · %s" % _where_street) if _where_street != "" else ""
		_where.text = "◆ Punto giallo sul radar, segui la linea blu%s · %s" % [place, Navigator.fmt_dist(dist)] if dist > 25.0 else "◆ Ci sei: i bersagli hanno una freccia rossa sopra la testa"
	if p.dead:
		fail("Sei morto.")
		return
	if timer >= 0.0:
		timer -= delta
		if timer < 0.0:
			fail("Tempo scaduto.")
			return
	match active:
		"crediti":
			var d: Gunman = _data["debtor"]
			if stage == 0 and (d.dead or d.health < 60.0):
				main._system("Mario er Tirchio: «Basta! Basta! Ecco i soldi!» e scappa via.")
				_enter(1)
			elif stage == 1 and _take(_data["case"]):
				p.money += 2000
				_enter(2)
			elif stage == 2 and _near(3.5):
				complete()
		"auto":
			var car: Car = _data["car"]
			if car.destroyed:
				fail("L'auto è distrutta.")
			elif stage == 0 and p.vehicle == car:
				_enter(1)
			elif stage == 1:
				_objective.text = "Portala al Meccanico entro il tempo. Stato dell'auto: %d%%" % int(car.health / 220.0 * 100.0)
				if car.health < 110.0:
					fail("L'hai rovinata troppo: al boss non serve più.")
				elif _near(7.0) and p.vehicle == car:
					complete()
		"colpo":
			var bi := int(_data["bank"])
			var st: Dictionary = main.banks.banks[bi]["st"]
			if stage == 0 and st["open"]:
				_enter(1)
			elif stage == 1 and int(_data["bags0"]) - Banks._count_bits(int(st["bags"])) >= 2:
				_enter(2)
			elif stage == 2 and main.my_stars() == 0:
				_enter(3)
			elif stage == 3 and _near(3.5):
				complete()
		"festa":
			var t: Gunman = _data["target"]
			if stage == 0 and t.dead:
				_enter(1)
			elif stage == 1 and main.my_stars() == 0:
				complete()
		"furgone":
			var v: Car = _data["van"]
			if stage == 0 and v.destroyed:
				_enter(1)
			elif stage == 1:
				var left := 0
				for b: Node3D in _data["bags"]:
					if is_instance_valid(b) and b.visible:
						if _take(b):
							var val := int(b.get_meta("value"))
							p.money += val
							main._system("Sacco: € %d." % val)
						else:
							left += 1
				if left == 0:
					_enter(2)
			elif stage == 2 and main.my_stars() == 0:
				complete()
		"corsa":
			if stage == 0 and p.vehicle != null:
				_enter(1)
			elif stage == 1:
				if _near(9.0):
					var cps: Array = _data["cps"]
					_data["cp"] = int(_data["cp"]) + 1
					Sfx.play2d("beep", -2.0)
					if int(_data["cp"]) >= cps.size():
						complete()
					else:
						_objective_set("Checkpoint %d / %d" % [int(_data["cp"]) + 1, cps.size()], cps[int(_data["cp"])], "Checkpoint")
		"consegna":
			if stage == 0 and _take(_data["pack"]):
				_enter(1)
			elif stage == 1 and _near(5.0):
				complete()


## Raccoglie un oggetto della missione se ci sei sopra.
func _take(n: Node3D) -> bool:
	if n == null or not is_instance_valid(n) or not n.visible:
		return false
	if n.global_position.distance_to(main.player.global_position) < 1.8:
		n.visible = false
		Sfx.play2d("coin", -4.0)
		return true
	return false


func complete() -> void:
	var info: Dictionary = INFO[active]
	var reward := int(info["reward"])
	main.player.money += reward
	main.add_fame(int(info["fame"]))
	if not done.has(active):
		done.append(active)
	var gained: int = main.player.money - int(_data.get("money0", main.player.money))
	_banner("MISSIONE COMPIUTA", "%s · € %s · fama +%d" % [info["title"], SlotMachine._thousands(maxi(gained, reward)), int(info["fame"])], 6.0)
	Sfx.play2d("jackpot", -4.0)
	_finish()
	main.save_bank()


func fail(why: String) -> void:
	_banner("MISSIONE FALLITA", why + " Torna dal contatto per riprovare.", 5.0)
	Sfx.play2d("empty", 0.0)
	_finish()


func _finish() -> void:
	active = ""
	timer = -1.0
	_objective.text = ""
	_objective_set("")
	for n: Node in _things:
		if is_instance_valid(n):
			if n is Car:
				var c := n as Car
				if c.driven_locally:
					continue  # chi la guida se la tiene
				main.cars.erase(c)
				main._extra_cars.erase(c.car_id)
			n.queue_free()
	_things.clear()
