class_name Banks
extends Node3D

## Banche: nei punti dove OpenStreetMap ha una banca vera (con un'insegna inventata) c'è una filiale con atrio,
## tre sportelli dietro i vetri, l'ufficio del direttore, il caveau con la porta blindata e i sacchi di contanti,
## telecamere, bancomat in facciata e la vigilanza armata.
##
## - Conto corrente (allo sportello o al bancomat): i soldi in banca non si perdono quando muori. Vedi BankUI.
## - Rapina allo sportello: punti un'arma all'impiegato, ti passa il cassetto (1.500-4.000 €), scatta l'allarme
##   (4 stelle) e la vigilanza ti spara.
## - Il colpo grosso: aprire il caveau prendendo in ostaggio il direttore (puntagli l'arma), col trapano
##   (E tenuto alla porta per DRILL_TIME secondi) o con la TNT. Dentro sei sacchi da 6.000-12.000 €. 5 stelle.
## - La vigilanza: se entri con un'arma in pugno e la punti ti intima di metterla giù, poi spara. Spari in banca
##   o colpi ai dipendenti fanno scattare l'allarme (sirena, luci rosse).
## - Dopo un colpo la filiale resta chiusa per indagini CLOSED_TIME secondi, poi riapre col caveau pieno.
## Lo stato lo tiene chi ospita (sync a tutti); porta del caveau e sacchi si vedono uguali su tutti i PC.

const BRANDS := ["Banca del Tevere", "Credito Flaminio", "Cassa di Risparmio di Ponte Milvio", "Banca Popolare dei Parioli", "Banco di Piazza del Popolo"]
const CLOSED_TIME := 900.0
const ALARM_TIME := 90.0
const BAG_MIN := 6000
const BAG_MAX := 12000
const BAGS := 6
const DRILL_TIME := 18.0
const TELLER_LOOT := [1500, 4000]

var world: Node
var city: CityBuilder
var combat: Combat
var police: Police
var pedestrians: Pedestrians
var banks: Array = []  # {vi, room, shop, door, door_shape, bags[], sign, light, siren, st {open, bags, closed, alarm}, staff[], guards[], hostile {}, warned {}}
var _t := 0.0
var _rng := RandomNumberGenerator.new()


# --- Arredo (lo chiama Venues.build_room su tutti i PC) ---------------------------------------------


static func furnish(city: CityBuilder, v: Dictionary, to3: Callable, U: Vector3, N: Vector3, W: float, depth: float, H: float,
		walls: CityBuilder.Acc, floor_acc: CityBuilder.Acc, o: Vector2) -> Dictionary:
	var yaw := atan2(U.z, U.x) * -1.0
	var wood := CityBuilder.Acc.new()
	var glass := CityBuilder.Acc.new()
	var metal := CityBuilder.Acc.new()
	var red := CityBuilder.Acc.new()
	# Caveau: stanza blindata nell'angolo in fondo a destra, con il vano della porta tonda.
	var vx0 := W - 4.6
	var vz0 := depth - 2.9
	var dx0 := W - 3.3
	var dx1 := W - 1.3
	for seg: Array in [[vx0, dx0], [dx1, W]]:
		Venues._box(walls, to3.call((seg[0] + seg[1]) * 0.5, vz0, H * 0.5), Vector3(seg[1] - seg[0], H, 0.5), yaw)
	Venues._box(walls, to3.call((dx0 + dx1) * 0.5, vz0, (H + 2.3) * 0.5), Vector3(dx1 - dx0, H - 2.3, 0.5), yaw)
	Venues._box(walls, to3.call(vx0, (vz0 + depth) * 0.5, H * 0.5), Vector3(0.5, H, depth - vz0), yaw)
	# Bancone degli sportelli con i vetri, da 2 m a W - 2 m; ai lati i passaggi per il personale.
	var cz := depth - 4.0
	Venues._box(wood, to3.call(W * 0.5, cz, 0.55), Vector3(W - 4.0, 1.1, 0.75), yaw)
	Venues._box(glass, to3.call(W * 0.5, cz, 1.85), Vector3(W - 4.0, 1.5, 0.05), yaw)
	for k in 3:
		var x := W * 0.5 + (k - 1) * 3.0
		Venues._box(metal, to3.call(x, cz - 0.3, 1.15), Vector3(0.7, 0.06, 0.3), yaw)  # piano per i documenti
		Venues._box(metal, to3.call(x, cz + 0.2, 1.35), Vector3(0.45, 0.32, 0.05), yaw)  # schermo
	# Ufficio del direttore (dietro a sinistra), panche, colonnine con il cordone per la fila.
	Venues._box(wood, to3.call(2.0, depth - 1.6, 0.4), Vector3(1.8, 0.8, 0.9), yaw)
	Venues._box(metal, to3.call(2.0, depth - 1.4, 0.95), Vector3(0.5, 0.3, 0.05), yaw)
	for bx: float in [3.2, W - 3.2]:
		Venues._box(wood, to3.call(bx, 2.6, 0.25), Vector3(2.0, 0.5, 0.5), yaw)
	for k in 4:
		Venues._cyl(metal, to3.call(W * 0.5 - 1.5 + k, cz - 1.6, 0.0), 0.04, 1.0)
	Venues._box(red, to3.call(W * 0.5, cz - 1.6, 0.85), Vector3(3.0, 0.05, 0.05), yaw)
	# Telecamere negli angoli (con il led rosso).
	for c: Array in [[0.4, 0.5], [W - 0.4, 0.5], [0.4, cz - 0.6], [W - 0.4, cz - 0.6]]:
		Venues._box(metal, to3.call(c[0], c[1], H - 0.25), Vector3(0.18, 0.14, 0.3), yaw)
		Venues._box(red, to3.call(c[0], c[1] + 0.17, H - 0.27), Vector3(0.04, 0.04, 0.02), yaw)
	# Bancomat incassato nella facciata, a destra della porta.
	var atm_x := W - 1.5
	Venues._box(metal, to3.call(atm_x, -0.12, 1.3), Vector3(0.8, 1.2, 0.25), yaw)
	Venues._box(red, to3.call(atm_x, -0.26, 1.55), Vector3(0.45, 0.32, 0.02), yaw)
	var marble := StandardMaterial3D.new()
	marble.albedo_texture = TexLib.tex("PavingStones046", "color")
	marble.albedo_color = Color(0.62, 0.62, 0.64)
	marble.roughness = 0.25
	marble.uv1_triplanar = true
	marble.uv1_scale = Vector3(0.5, 0.5, 0.5)
	var plaster := StandardMaterial3D.new()
	plaster.albedo_color = Color(0.72, 0.73, 0.75)
	var wood_m := StandardMaterial3D.new()
	wood_m.albedo_color = Color(0.3, 0.17, 0.09)
	wood_m.roughness = 0.4
	var glass_m := StandardMaterial3D.new()
	glass_m.albedo_color = Color(0.7, 0.85, 0.9, 0.22)
	glass_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_m.roughness = 0.05
	glass_m.metallic = 0.3
	var metal_m := StandardMaterial3D.new()
	metal_m.albedo_color = Color(0.25, 0.27, 0.3)
	metal_m.metallic = 0.7
	metal_m.roughness = 0.3
	var red_m := StandardMaterial3D.new()
	red_m.albedo_color = Color(0.9, 0.08, 0.05)
	red_m.emission_enabled = true
	red_m.emission = Color(1.0, 0.1, 0.05)
	red_m.emission_energy_multiplier = 2.0
	var tag := "Banca_%d" % int(v["index"])
	city._add_mesh(walls.mesh(plaster), tag + "_pareti", false)
	city._add_mesh(floor_acc.mesh(marble), tag + "_pavimento", false)
	city._add_mesh(wood.mesh(wood_m), tag + "_arredi")
	city._add_mesh(glass.mesh(glass_m), tag + "_vetri", false)
	city._add_mesh(metal.mesh(metal_m), tag + "_metallo")
	city._add_mesh(red.mesh(red_m), tag + "_spie", false)
	var faces := walls.v.duplicate()
	faces.append_array(wood.v)
	faces.append_array(glass.v)
	city._add_trimesh_body(faces, tag + "_fisico")
	for k in 2:
		var light := OmniLight3D.new()
		light.light_color = Color(0.95, 0.97, 1.0)
		light.light_energy = 0.75
		light.omni_range = 10.0
		light.distance_fade_enabled = true
		light.distance_fade_begin = 80.0
		light.distance_fade_length = 20.0
		light.position = to3.call(W * (0.3 + 0.4 * k), depth * 0.45, H - 0.3)
		city.add_child(light)
	var sign := Label3D.new()
	sign.text = String(v.get("brand", "Banca")).to_upper()
	sign.font_size = 52
	sign.outline_size = 8
	sign.pixel_size = 0.01
	sign.modulate = Color(1.0, 0.85, 0.35)
	sign.shaded = false
	sign.position = to3.call(W * 0.5, -0.12, H - 0.25)
	sign.rotation.y = atan2(-N.x, -N.z)
	sign.visibility_range_end = 150.0
	city.add_child(sign)
	var atm_l := Label3D.new()
	atm_l.text = "BANCOMAT"
	atm_l.font_size = 28
	atm_l.pixel_size = 0.004
	atm_l.modulate = Color(0.4, 0.8, 1.0)
	atm_l.shaded = false
	atm_l.position = to3.call(atm_x, -0.27, 2.02)
	atm_l.rotation.y = atan2(-N.x, -N.z)
	city.add_child(atm_l)
	var face_lobby := atan2(-N.x, -N.z)
	var spots := []
	for k in BAGS:
		spots.append(to3.call(vx0 + 0.9 + (k % 3) * 1.15, vz0 + 1.0 + floori(k / 3) * 0.95, 0.0))
	var tellers := []
	for k in 3:
		tellers.append(to3.call(W * 0.5 + (k - 1) * 3.0, cz + 0.9, 0.0))
	return {
		"counter_front": to3.call(W * 0.5, cz - 1.0, 0.0),
		"clerk": tellers[1],
		"clerk_yaw": face_lobby,
		"entrance": to3.call(W * 0.5, -1.6, 0.0),
		"door2d": o + Vector2(U.x, U.z) * (W * 0.5),
		"slots": [],
		"tellers": tellers,
		"director": to3.call(2.0, depth - 0.7, 0.0),
		"guards": [to3.call(1.3, 1.4, 0.0), to3.call(W - 1.3, 1.4, 0.0), to3.call(W - 2.3, vz0 - 0.9, 0.0)],
		"vault_door": to3.call((dx0 + dx1) * 0.5, vz0, 0.0),
		"vault_spots": spots,
		"atm": to3.call(atm_x, -0.9, 0.0),
		"queue": [to3.call(W * 0.5, cz - 2.4, 0.0), to3.call(W * 0.5 - 0.8, cz - 3.2, 0.0)],
		"axes": [o, Vector2(U.x, U.z), Vector2(N.x, N.z), W, depth],
		"brand": v.get("brand", "Banca"),
		"face": face_lobby,
		"n": N,
		"u": U,
	}


# --- Gestione (tutti i PC: porta e sacchi; chi ospita: personale, vigilanza, allarmi) ----------------


func setup(w: Node, c: CityBuilder, cb: Combat, pol: Police, peds: Pedestrians, shops: Shops) -> void:
	world = w
	city = c
	combat = cb
	police = pol
	pedestrians = peds
	_rng.randomize()
	combat.exploded.connect(_on_explosion)
	for i in city.venues.size():
		if city.venues[i]["kind"] != "bank":
			continue
		var room: Dictionary = city.venue_rooms[i]
		var shop: Dictionary = shops.shops[i]
		shop["loot"] = TELLER_LOOT
		var b := {"vi": i, "room": room, "shop": shop, "bags": [], "staff": [], "guards": [], "hostile": {}, "warned": {},
			"st": {"open": false, "bags": (1 << BAGS) - 1, "closed": 0.0, "alarm": 0.0}, "siren": null}
		_build_door(b)
		for k in BAGS:
			b["bags"].append(_bag_node(room["vault_spots"][k]))
		var sign := Label3D.new()
		sign.text = "CHIUSA PER INDAGINI"
		sign.font_size = 40
		sign.pixel_size = 0.008
		sign.modulate = Color(1.0, 0.3, 0.2)
		sign.shaded = false
		sign.visible = false
		add_child(sign)
		sign.global_position = (room["entrance"] as Vector3) + Vector3(0, 2.2, 0)
		sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		b["sign"] = sign
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.1, 0.05)
		light.omni_range = 14.0
		light.light_energy = 0.0
		add_child(light)
		light.global_position = (room["counter_front"] as Vector3) + Vector3(0, 2.6, 0)
		b["light"] = light
		banks.append(b)


func _build_door(b: Dictionary) -> void:
	var room: Dictionary = b["room"]
	var hinge := Node3D.new()
	add_child(hinge)
	var n: Vector3 = room["n"]
	var u: Vector3 = room["u"]
	var center: Vector3 = room["vault_door"]
	hinge.global_position = center - u * 1.0 - n * 0.3  # cardine sul lato sinistro, sporgente verso l'atrio
	hinge.global_basis = Basis(u, Vector3.UP, n)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.57, 0.6)
	steel.metallic = 0.9
	steel.roughness = 0.25
	var disc := CylinderMesh.new()
	disc.top_radius = 1.05
	disc.bottom_radius = 1.05
	disc.height = 0.35
	disc.radial_segments = 32
	disc.material = steel
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.position = Vector3(1.0, 1.15, 0.0)
	mi.rotation = Vector3(PI / 2, 0, 0)
	hinge.add_child(mi)
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.28
	wheel.outer_radius = 0.36
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.15, 0.17)
	dark.metallic = 0.8
	wheel.material = dark
	var wi := MeshInstance3D.new()
	wi.mesh = wheel
	wi.position = Vector3(1.0, 1.15, -0.22)
	wi.rotation = Vector3(PI / 2, 0, 0)
	hinge.add_child(wi)
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.1, 2.3, 0.4)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(1.0, 1.15, 0.0)
	body.add_child(cs)
	hinge.add_child(body)
	b["door"] = hinge
	b["door_shape"] = cs
	b["door_rot"] = hinge.global_basis


func _bag_node(at: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	var sack := SphereMesh.new()
	sack.radius = 0.32
	sack.height = 0.6
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.47, 0.3)
	m.roughness = 0.9
	sack.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = sack
	mi.position.y = 0.3
	mi.scale = Vector3(1.0, 0.9, 0.85)
	n.add_child(mi)
	var l := Label3D.new()
	l.text = "€"
	l.font_size = 64
	l.pixel_size = 0.004
	l.modulate = Color(0.2, 0.6, 0.25)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 0.75
	n.add_child(l)
	return n


## Dove si trova chi è dentro la banca i (rettangolo della stanza).
func inside(i: int, p: Vector3, margin := 0.0) -> bool:
	var ax: Array = banks[i]["room"]["axes"]
	var d := Vector2(p.x, p.z) - (ax[0] as Vector2)
	var x := d.dot(ax[1])
	var z := d.dot(ax[2])
	return x > -margin and x < float(ax[3]) + margin and z > -margin and z < float(ax[4]) + margin


func bank_at(p: Vector3, margin := 0.0) -> int:
	for i in banks.size():
		if inside(i, p, margin):
			return i
	return -1


func is_closed(i: int) -> bool:
	return float(banks[i]["st"]["closed"]) > _now()


func _now() -> float:
	return Time.get_unix_time_from_system()


## Applica lo stato visibile (porta, sacchi, cartello, allarme) su questo PC.
func apply(i: int) -> void:
	var b: Dictionary = banks[i]
	var st: Dictionary = b["st"]
	var door: Node3D = b["door"]
	var closed_rot: Basis = b["door_rot"]
	door.global_basis = closed_rot.rotated(Vector3.UP, -1.9) if st["open"] else closed_rot
	(b["door_shape"] as CollisionShape3D).disabled = st["open"]
	for k in BAGS:
		(b["bags"][k] as Node3D).visible = (int(st["bags"]) >> k) & 1 == 1 and not is_closed(i)
	(b["sign"] as Label3D).visible = is_closed(i)
	var ringing := float(st["alarm"]) > _now()
	if ringing and b["siren"] == null:
		var s := Sfx.loop3d(b["light"], "siren", 6.0, 220.0)
		s.pitch_scale = 1.35
		b["siren"] = s
	elif not ringing and b["siren"] != null:
		(b["siren"] as Node).queue_free()
		b["siren"] = null


func state_of(i: int) -> Array:
	var st: Dictionary = banks[i]["st"]
	return [st["open"], int(st["bags"]), float(st["closed"]) - _now(), float(st["alarm"]) - _now()]


func set_state(i: int, a: Array) -> void:
	if i < 0 or i >= banks.size():
		return
	var st: Dictionary = banks[i]["st"]
	st["open"] = bool(a[0])
	st["bags"] = int(a[1])
	st["closed"] = _now() + float(a[2])
	st["alarm"] = _now() + float(a[3])
	apply(i)


func _changed(i: int) -> void:
	apply(i)
	world.bank_sync(i, state_of(i))


func _process(_delta: float) -> void:
	var now := _now()
	for b: Dictionary in banks:
		var light: OmniLight3D = b["light"]
		var ringing := float(b["st"]["alarm"]) > now
		light.light_energy = (4.0 if int(now * 3.0) % 2 == 0 else 0.3) if ringing else 0.0
		if not ringing and b["siren"] != null:
			apply(banks.find(b))


# --- Chi ospita -------------------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if world == null or not world.simulate:
		return
	_t += delta
	if _t < 0.5:
		return
	var step := _t
	_t = 0.0
	var ps: Dictionary = world.players()
	var now := _now()
	for i in banks.size():
		var b: Dictionary = banks[i]
		var st: Dictionary = b["st"]
		var room: Dictionary = b["room"]
		var center: Vector3 = room["counter_front"]
		var near := false
		for peer: int in ps:
			if (ps[peer] as Node3D).global_position.distance_to(center) < 160.0:
				near = true
		# Riapertura dopo le indagini: caveau chiuso e pieno.
		if float(st["closed"]) > 0.0 and float(st["closed"]) <= now:
			st["closed"] = 0.0
			st["open"] = false
			st["bags"] = (1 << BAGS) - 1
			b["hostile"] = {}
			_changed(i)
		# Dopo un colpo, quando l'allarme finisce, si chiude per indagini.
		if st["open"] and float(st["alarm"]) <= now and float(st["closed"]) <= now:
			st["closed"] = now + CLOSED_TIME
			_changed(i)
		if near and not is_closed(i):
			_staff(b)
		elif not near:
			_dismiss(b)
		# Vigilanza: chi punta un'arma dentro la banca viene avvisato, poi diventa un bersaglio.
		for peer: int in ps:
			var p: Player = ps[peer]
			if p.dead or not inside(i, p.global_position):
				continue
			if _armed_and_aiming(p):
				var w := float(b["warned"].get(peer, 0.0)) + step
				b["warned"][peer] = w
				if w <= step + 0.01:
					world.clan_msg(peer, "Vigilanza: «Metta giù l'arma! Subito!»")
				elif w > 3.0:
					alarm(i, peer)
			else:
				b["warned"].erase(peer)


func _armed_and_aiming(p: Player) -> bool:
	var weapon: String = p.weapon if p.is_local else String(p.get("_net_weapon"))
	if not String(Weapons.info(weapon)["kind"]) in ["gun", "rocket"]:
		return false
	return p.aiming if p.is_local else String(p.get("_net_anim")) in ["aim", "aim_up", "aim_down", "shoot"]


## Impiegati agli sportelli, direttore e vigilanti (quando c'è qualcuno vicino).
func _staff(b: Dictionary) -> void:
	var room: Dictionary = b["room"]
	b["staff"] = (b["staff"] as Array).filter(func(n: Node) -> bool: return is_instance_valid(n))
	b["guards"] = (b["guards"] as Array).filter(func(n: Node) -> bool: return is_instance_valid(n))
	if (b["staff"] as Array).is_empty() and int(b["shop"].get("robbed_until", 0)) <= Time.get_ticks_msec():
		var face: float = room["face"]
		for k in 3:
			b["staff"].append(_clerk(b, room["tellers"][k], face, b["shop"], false))
		var dshop := {"kind": "bank_director", "pos": room["director"], "loot": [0, 0], "bank": banks.find(b)}
		b["staff"].append(_clerk(b, room["director"], face, dshop, true))
	if (b["guards"] as Array).is_empty():
		var face2: float = room["face"]
		for k in 3:
			var g := Gunman.new()
			g.combat = combat
			g.world = world
			g.nid = world.new_nid()
			g.preset = "guard"
			g.weapon = "mitragliatrice" if k == 2 else "pistola"
			g.health = 170.0
			g.skill = 0.65
			g.anchor = room["guards"][k]
			g.face_yaw = face2
			var bi := banks.find(b)
			g.foe_fn = func(me: Gunman) -> Node3D: return _guard_foe(bi, me)
			g.on_hurt = func(_me: Gunman, from_peer: int) -> void:
				if from_peer > 0:
					alarm(bi, from_peer)
			g.on_dead = func(me: Gunman, from_peer: int) -> void:
				pedestrians.drop_ammo(me.global_position, me.weapon, int(Weapons.info(me.weapon).get("mag", 12)))
				if from_peer > 0:
					police.report("kill", me.global_position, from_peer)
			add_child(g)
			g.global_position = g.anchor + Vector3(0, 0.3, 0)
			b["guards"].append(g)


func _clerk(b: Dictionary, at: Vector3, face: float, shop: Dictionary, director: bool) -> Pedestrians.Clerk:
	var ck := Pedestrians.Clerk.new()
	ck.mgr = pedestrians
	ck.nid = world.new_nid()
	ck.preset = "banker" if director else Human.PRESETS.keys()[_rng.randi() % Human.PRESETS.size()]
	ck.shop = shop
	ck.anchor = at
	ck.face_yaw = face
	if director:
		ck.set_meta("director", banks.find(b))
	pedestrians.add_child(ck)
	ck.global_position = at + Vector3(0, 0.2, 0)
	return ck


func _dismiss(b: Dictionary) -> void:
	for key: String in ["staff", "guards"]:
		for item: Variant in b[key]:  # Variant: un impiegato può essere già stato liberato
			if is_instance_valid(item):
				var n := item as Node
				if n.get("state") in [null, "idle"] or n.get("dead") == true:
					n.queue_free()
		b[key] = []


func _guard_foe(i: int, me: Gunman) -> Node3D:
	var b: Dictionary = banks[i]
	var ps: Dictionary = world.players()
	var best: Node3D = null
	var best_d := 45.0
	var now := _now()
	for peer: int in ps:
		if float(b["hostile"].get(peer, 0.0)) < now:
			continue
		var p: Player = ps[peer]
		if p.dead:
			continue
		var d := p.global_position.distance_to(me.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


## Allarme: sirena, luci rosse, 4 stelle a chi l'ha fatto scattare, vigilanza contro di lui.
func alarm(i: int, peer: int) -> void:
	var b: Dictionary = banks[i]
	var st: Dictionary = b["st"]
	var now := _now()
	var was := float(st["alarm"]) > now
	b["hostile"][peer] = now + 150.0
	st["alarm"] = maxf(float(st["alarm"]), now + ALARM_TIME)
	if peer > 0:
		var p: Node3D = world.players().get(peer)
		police.report("bank", p.global_position if p else (b["room"]["counter_front"] as Vector3), peer)
	if not was:
		world.clan_msg(peer, "ALLARME! È scattato l'allarme della %s: la vigilanza spara e la polizia sta arrivando." % b["room"]["brand"])
		_changed(i)


## Un dipendente minacciato con un'arma (lo chiama Pedestrians.Clerk.rob, su chi ospita).
func on_rob(ck: Node, shop: Dictionary, peer: int) -> void:
	if String(shop.get("kind", "")) == "bank_director":
		var i := int(shop["bank"])
		alarm(i, peer)
		world.clan_msg(peer, "Il direttore, tremando: «Va bene, va bene! Apro il caveau... non sparate!»")
		get_tree().create_timer(6.0).timeout.connect(func() -> void:
			if is_instance_valid(ck) and ck.get("dead") != true:
				open_vault(i, peer, "Il direttore ha aperto il caveau."))
		return
	var bi := bank_at((ck as Node3D).global_position, 1.0)
	if bi >= 0:
		alarm(bi, peer)


func open_vault(i: int, peer: int, how: String) -> void:
	var st: Dictionary = banks[i]["st"]
	if st["open"] or is_closed(i):
		return
	st["open"] = true
	st["alarm"] = maxf(float(st["alarm"]), _now() + ALARM_TIME + 60.0)
	banks[i]["hostile"][peer] = _now() + 240.0
	var p: Node3D = world.players().get(peer)
	police.report("bank_vault", p.global_position if p else (banks[i]["room"]["vault_door"] as Vector3), peer)
	world.give_fame(peer, 30)
	world.clan_msg(peer, how + " Dentro ci sono %d sacchi di contanti: prendili (E) e scappa!" % BAGS)
	world.clan_broadcast("Radio: rapina in corso alla %s!" % banks[i]["room"]["brand"])
	_changed(i)


## Un reato dentro (o davanti) a una banca: allarme.
func on_crime(kind: String, pos: Vector3, peer: int) -> void:
	if not kind in ["shots", "kill", "rocket", "assault", "robbery"]:
		return
	var i := bank_at(pos, 3.0)
	if i >= 0 and not is_closed(i):
		alarm(i, peer)


func _on_explosion(pos: Vector3, _radius: float, peer: int) -> void:
	if not world.simulate:
		return
	for i in banks.size():
		var door: Vector3 = banks[i]["room"]["vault_door"]
		if not banks[i]["st"]["open"] and pos.distance_to(door + Vector3(0, 1.0, 0)) < 3.2 and peer > 0:
			open_vault(i, peer, "BOOM! La porta del caveau è saltata.")


## Richieste dei giocatori (su chi ospita).
func request(peer: int, action: String, args: Array) -> void:
	var i := int(args[0])
	if i < 0 or i >= banks.size():
		return
	var b: Dictionary = banks[i]
	var p: Node3D = world.players().get(peer)
	if p == null:
		return
	match action:
		"drill_start":
			if not b["st"]["open"] and not is_closed(i):
				alarm(i, peer)
		"drill_done":
			if p.global_position.distance_to(b["room"]["vault_door"]) < 4.0:
				open_vault(i, peer, "Il trapano ha bucato la serratura: il caveau è aperto.")
		"bag":
			var k := int(args[1])
			var st: Dictionary = b["st"]
			if not st["open"] or (int(st["bags"]) >> k) & 1 == 0:
				return
			if p.global_position.distance_to(b["room"]["vault_spots"][k]) > 3.0:
				return
			st["bags"] = int(st["bags"]) & ~(1 << k)
			var amount := _rng.randi_range(BAG_MIN, BAG_MAX)
			world.award(peer, amount)
			world.give_fame(peer, 8)
			world.clan_msg(peer, "Sacco preso: € %d. Ne restano %d." % [amount, _count_bits(int(st["bags"]))])
			police.report("bank_vault", p.global_position, peer)
			_changed(i)


static func _count_bits(m: int) -> int:
	var n := 0
	while m > 0:
		n += m & 1
		m >>= 1
	return n


# --- Domande per il giocatore di questo PC ------------------------------------------------------------


## [banca, sacco] davanti a cui si trova (caveau aperto), o [].
func bag_near(pos: Vector3) -> Array:
	for i in banks.size():
		var st: Dictionary = banks[i]["st"]
		if not st["open"] or is_closed(i):
			continue
		for k in BAGS:
			if (int(st["bags"]) >> k) & 1 == 1 and pos.distance_to(banks[i]["room"]["vault_spots"][k]) < 1.6:
				return [i, k]
	return []


## Banca col caveau chiuso davanti a cui si trova (per il trapano), o -1.
func vault_near(pos: Vector3) -> int:
	for i in banks.size():
		if not banks[i]["st"]["open"] and not is_closed(i) and pos.distance_to(banks[i]["room"]["vault_door"]) < 2.2:
			return i
	return -1


## Bancomat davanti a cui si trova, o -1.
func atm_near(pos: Vector3) -> int:
	for i in banks.size():
		if pos.distance_to(banks[i]["room"]["atm"]) < 1.6:
			return i
	return -1
