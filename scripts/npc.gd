class_name Pedestrians
extends Node3D

## Pedoni: passeggiano su marciapiedi e vialetti attorno a tutti i giocatori, scappano da spari ed esplosioni,
## possono essere feriti e uccisi (lasciano cadere dei soldi).
## Li calcola solo chi ospita (o chi gioca da solo); gli altri PC li ricevono da NetSync e li mostrano uguali.

const PER_PLAYER := 24
const MAX_TOTAL := 54
const SPAWN_MIN := 35.0
const SPAWN_MAX := 140.0
const DESPAWN := 210.0
const CELL := 60.0

var city: CityBuilder
var world: Node  # main.gd: anchors(), players(), award(), crime(), new_nid(), simulate
var combat: Combat
var _paths: Array = []  # PackedVector3Array: percorsi pedonali (marciapiedi lungo le strade e vialetti)
var _ends := {}  # cella -> Array di [indice percorso, 0 = inizio / 1 = fine]
var cash: Array = []  # [Node3D, soldi, id di rete]
var _rng := RandomNumberGenerator.new()


func setup(c: CityBuilder, w: Node, combat_node: Combat) -> void:
	city = c
	world = w
	combat = combat_node
	_rng.randomize()
	for r: Dictionary in city.data["roads"]:
		var pts := city._pts(r["p"])
		if pts.size() < 2 or int(r["b"]) == 1:
			continue
		var kind: String = r["k"]
		if kind == "tram":
			continue
		if kind == "foot":
			_add_path(pts, 0.0)
		elif float(r["w"]) >= 6.0:
			for side: float in [1.0, -1.0]:
				_add_path(pts, side * (float(r["w"]) * 0.5 + 1.7))
	combat_node.noise.connect(_on_noise)


func _add_path(pts: PackedVector2Array, offset: float) -> void:
	var out := PackedVector3Array()
	for i in pts.size():
		var p := pts[i]
		var d := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var q := p + Vector2(-d.y, d.x) * offset
		out.append(Vector3(q.x, maxf(city.height_at(q.x, q.y), city.height_at(p.x, p.y)), q.y))
	var idx := _paths.size()
	_paths.append(out)
	for e in [0, 1]:
		var p3: Vector3 = out[0] if e == 0 else out[out.size() - 1]
		var key := Vector2i(floori(p3.x / CELL), floori(p3.z / CELL))
		if not _ends.has(key):
			_ends[key] = []
		_ends[key].append([idx, e])


static func nearest(p: Vector3, anchors: Array) -> float:
	var best := INF
	for a: Vector3 in anchors:
		best = minf(best, a.distance_to(p))
	return best


var _clerk_t := 0.0


func _physics_process(delta: float) -> void:
	if world == null or not world.simulate:
		return
	var anchors: Array = world.anchors()
	if anchors.is_empty():
		return
	var alive := 0
	for n: Node in get_children():
		if n is Pedestrian:
			var ped := n as Pedestrian
			if nearest(ped.global_position, anchors) > DESPAWN:
				ped.queue_free()
			elif not ped.dead and not ped.has_meta("clerk") and not ped.has_meta("dealer"):
				alive += 1
	_clerk_t -= delta
	if _clerk_t <= 0.0:
		_clerk_t = 1.0
		_spawn_clerks(anchors)
	if alive < mini(PER_PLAYER * anchors.size(), MAX_TOTAL):
		_spawn_one(anchors[_rng.randi() % anchors.size()], anchors)
	# Soldi a terra: li prende il primo giocatore che ci passa sopra (su qualunque PC).
	var players: Dictionary = world.players()
	for c: Array in cash.duplicate():
		var node: Node3D = c[0]
		if not is_instance_valid(node):
			cash.erase(c)
			continue
		node.rotate_y(0.05)
		for peer: int in players:
			var pl: Player = players[peer]
			if node.global_position.distance_to(pl.global_position + Vector3(0, 0.5, 0)) < 1.4 and not pl.dead:
				if c.size() > 3 and String(c[3]) != "":
					world.award_ammo(peer, String(c[3]), int(c[1]))  # munizioni lasciate da un agente
				else:
					world.award(peer, int(c[1]))
				node.queue_free()
				cash.erase(c)
				break


func _spawn_one(me: Vector3, anchors: Array) -> void:
	for attempt in 6:
		var path_i := _rng.randi() % _paths.size()
		var path: PackedVector3Array = _paths[path_i]
		var k := _rng.randi() % path.size()
		var p := path[k]
		var d := p.distance_to(me)
		if d < SPAWN_MIN or d > SPAWN_MAX or nearest(p, anchors) < SPAWN_MIN:
			continue
		var ped := Pedestrian.new()
		ped.mgr = self
		ped.nid = world.new_nid()
		ped.preset = Human.PRESETS.keys()[_rng.randi() % Human.PRESETS.size()]
		add_child(ped)
		ped.global_position = p + Vector3(0, 0.2, 0)
		ped.follow(path_i, k, 1 if _rng.randf() < 0.5 else -1)
		return


## Commessi davanti a bar e farmacie vicini a un giocatore (uno per locale; dopo una rapina il locale resta
## chiuso 5 minuti).
func _spawn_clerks(anchors: Array) -> void:
	var sh: Shops = world.get("shops")
	if sh == null:
		return
	var now := Time.get_ticks_msec()
	for s: Dictionary in sh.shops:
		var c: Variant = s.get("clerk")
		if c != null and is_instance_valid(c):
			continue
		if int(s.get("robbed_until", 0)) > now:
			continue
		var p: Vector3 = s["pos"]
		if nearest(p, anchors) > 150.0:
			continue
		if s["kind"] == "dealer":
			var dl := Dealer.new()
			dl.mgr = self
			dl.nid = world.new_nid()
			dl.preset = ["m3", "m5", "m7", "f6"][_rng.randi() % 4]
			dl.shop = s
			dl.anchor = p
			add_child(dl)
			dl.global_position = p + Vector3(0, 0.2, 0)
			s["clerk"] = dl
			continue
		if not String(s["kind"]) in ["bar", "pharmacy", "gun"]:
			continue
		if s.has("clerk_pos"):
			# Locale vero: il commesso sta dietro il bancone, alla cassa, e guarda la porta.
			var ck := Clerk.new()
			ck.mgr = self
			ck.nid = world.new_nid()
			ck.preset = Human.PRESETS.keys()[_rng.randi() % Human.PRESETS.size()]
			ck.shop = s
			ck.anchor = s["clerk_pos"]
			ck.face_yaw = float(s["clerk_yaw"])
			add_child(ck)
			ck.global_position = ck.anchor + Vector3(0, 0.2, 0)
			s["clerk"] = ck
			continue
		var door: Vector2 = s.get("door", Vector2(p.x, p.z))
		var into := door - Vector2(p.x, p.z)
		into = into.normalized() if into.length() > 0.1 else Vector2(1, 0)
		var clerk := Clerk.new()
		clerk.mgr = self
		clerk.nid = world.new_nid()
		clerk.preset = Human.PRESETS.keys()[_rng.randi() % Human.PRESETS.size()]
		clerk.shop = s
		clerk.anchor = p + Vector3(into.x, 0, into.y) * 1.6
		clerk.face_yaw = atan2(-into.x, -into.y)  # guarda verso la strada
		add_child(clerk)
		clerk.global_position = clerk.anchor + Vector3(0, 0.2, 0)
		s["clerk"] = clerk


## Pedone fuori dai percorsi, in un punto preciso (il guidatore tirato fuori da un'auto rubata).
func spawn_at(pos: Vector3) -> Pedestrian:
	var ped := Pedestrian.new()
	ped.mgr = self
	ped.nid = world.new_nid()
	ped.preset = Human.PRESETS.keys()[_rng.randi() % Human.PRESETS.size()]
	add_child(ped)
	ped.global_position = pos
	return ped


## Percorso che parte vicino a pos (per continuare la passeggiata a fine marciapiede).
func next_path(pos: Vector3, not_idx: int) -> Array:
	var key := Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))
	var best := []
	var best_d := 8.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for e: Array in _ends.get(key + Vector2i(dx, dz), []):
				if int(e[0]) == not_idx:
					continue
				var path: PackedVector3Array = _paths[int(e[0])]
				var p: Vector3 = path[0] if int(e[1]) == 0 else path[path.size() - 1]
				var d := p.distance_to(pos) + _rng.randf() * 4.0
				if d < best_d:
					best_d = d
					best = [int(e[0]), 0 if int(e[1]) == 0 else path.size() - 1, 1 if int(e[1]) == 0 else -1]
	return best


func path(i: int) -> PackedVector3Array:
	return _paths[i]


static func cash_node(parent: Node) -> Node3D:
	var node := Node3D.new()
	parent.add_child(node)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.08, 0.2)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.75, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.6, 0.25)
	mi.material_override = mat
	node.add_child(mi)
	return node


func drop_cash(pos: Vector3, amount: int) -> void:
	if not world.simulate:
		return
	var node := cash_node(self)
	node.global_position = pos + Vector3(0, 0.4, 0)
	cash.append([node, amount, world.new_nid(), ""])


## Scatola di munizioni a terra (l'arma di un agente ucciso): chi ci passa sopra prende i colpi (e l'arma).
func drop_ammo(pos: Vector3, weapon_id: String, rounds: int) -> void:
	if not world.simulate:
		return
	var node := ammo_node(self)
	node.global_position = pos + Vector3(0, 0.35, 0)
	cash.append([node, rounds, world.new_nid(), weapon_id])


static func ammo_node(parent: Node) -> Node3D:
	var node := Node3D.new()
	parent.add_child(node)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.36, 0.22, 0.22)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.36, 0.18)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.7, 0.1) * 0.35
	mi.material_override = mat
	node.add_child(mi)
	var band := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.37, 0.05, 0.23)
	band.mesh = bb
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.95, 0.75, 0.1)
	bm.emission_enabled = true
	bm.emission = Color(0.95, 0.75, 0.1)
	band.material_override = bm
	node.add_child(band)
	return node


func _on_noise(pos: Vector3, radius: float) -> void:
	for n: Node in get_children():
		if n is Pedestrian and (n as Pedestrian).global_position.distance_to(pos) < radius:
			(n as Pedestrian).scare(pos)


class Pedestrian:
	extends CharacterBody3D

	var mgr: Pedestrians
	var nid := 0
	var preset := "m1"
	var health := 60.0
	var dead := false
	var net_anim := "stroll"
	var _human: Human
	var _path_i := -1
	var _k := 0
	var _dir := 1
	var _fear := 0.0
	var _from := Vector3.ZERO
	var _pause := 0.0
	var _dead_t := 0.0
	var _cower := false

	func _ready() -> void:
		add_to_group("damageable")
		add_to_group("pedestrian")
		mgr.world.register(nid, self)
		collision_layer = 32
		collision_mask = 1 | 16
		var shape := CapsuleShape3D.new()
		shape.radius = 0.3
		shape.height = 1.7
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 0.85
		add_child(cs)
		_human = Human.new().setup(preset)
		add_child(_human)
		_human.play("stroll")

	func is_mine() -> bool:
		return true

	func human() -> Human:
		return _human

	func follow(path_i: int, k: int, dir: int) -> void:
		_path_i = path_i
		_k = k
		_dir = dir

	## Tirato fuori dall'auto: cade, poi si rialza e scappa (senza farsi rubare il posto da altri percorsi).
	func thrown_out(from: Vector3) -> void:
		_human.play_once("hit")
		_pause = 0.0
		_fear = 10.0
		_cower = false
		_from = from
		velocity = (global_position - from).normalized() * 3.0 + Vector3.UP * 2.0
		# Per due secondi l'auto appena rubata non lo investe mentre riparte.
		set_meta("safe_until", Time.get_ticks_msec() + 2500)

	func scare(from: Vector3) -> void:
		if dead:
			return
		_fear = 8.0
		_from = from
		_cower = randf() < 0.25

	func take_damage(amount: float, from_peer: int, at: Vector3) -> void:
		if dead:
			return
		mgr.world.crime("shots", at, from_peer)
		health -= amount
		scare(at)
		if health <= 0.0:
			dead = true
			net_anim = "death"
			_human.play_once("death")
			collision_layer = 0
			mgr.world.crime("kill", global_position, from_peer)
			if randf() < 0.8:
				mgr.drop_cash(global_position, randi_range(20, 150))
		else:
			_human.play_once("hit")

	func _physics_process(delta: float) -> void:
		if dead:
			_dead_t += delta
			velocity = Vector3(0, velocity.y - 16.0 * delta, 0)
			move_and_slide()
			if _dead_t > 40.0:
				queue_free()
			return
		var target_v := Vector3.ZERO
		var anim := "idle"
		if _fear > 0.0:
			_fear -= delta
			if _cower:
				anim = "crouch"
			else:
				var away := global_position - _from
				away.y = 0.0
				target_v = away.normalized() * 7.5
				anim = "sprint"
		elif _pause > 0.0:
			_pause -= delta
			anim = "talk" if _pause > 1.0 else "idle"
		elif _path_i >= 0:
			var path := mgr.path(_path_i)
			var goal := path[clampi(_k, 0, path.size() - 1)]
			var to := goal - global_position
			to.y = 0.0
			if to.length() < 0.8:
				_k += _dir
				if _k < 0 or _k >= path.size():
					var nxt := mgr.next_path(global_position, _path_i)
					if nxt.is_empty():
						_dir = -_dir
						_k = clampi(_k, 0, path.size() - 1)
					else:
						_path_i = nxt[0]
						_k = nxt[1]
						_dir = nxt[2]
					if randf() < 0.15:
						_pause = randf_range(2.0, 6.0)
			else:
				target_v = to.normalized() * 1.4
				anim = "stroll"
		velocity.x = lerpf(velocity.x, target_v.x, 1.0 - exp(-8.0 * delta))
		velocity.z = lerpf(velocity.z, target_v.z, 1.0 - exp(-8.0 * delta))
		velocity.y = 0.0 if is_on_floor() else velocity.y - 16.0 * delta
		move_and_slide()
		if Vector2(velocity.x, velocity.z).length() > 0.3:
			_human.rotation.y = lerp_angle(_human.rotation.y, atan2(velocity.x, velocity.z), 1.0 - exp(-8.0 * delta))
		net_anim = anim
		_human.play(anim)

	## Si ferma a parlare (ha comprato un pacchetto).
	func chat_pause() -> void:
		if not dead and _fear <= 0.0:
			_pause = 2.5
			velocity = Vector3.ZERO


## Commesso di un bar o di una farmacia, davanti all'ingresso. Se un giocatore gli punta contro un'arma è una
## rapina: alza le mani e consegna l'incasso, oppure scappa lasciando cadere la refurtiva, oppure reagisce
## (a pugni, o tirando fuori una pistola). Lo calcola chi ospita; gli altri lo vedono come un passante.
class Clerk:
	extends Pedestrian

	var shop: Dictionary
	var anchor := Vector3.ZERO
	var face_yaw := 0.0
	var state := "idle"  # idle, hands_up, flee, fight
	var robber := 0  # peer di chi rapina
	var armed := false
	var _t := 0.0
	var _cool := 0.0
	var _gun: Node3D

	func _ready() -> void:
		super._ready()
		set_meta("clerk", true)
		health = 80.0
		_human.play("idle")

	func _robber() -> Player:
		var players: Dictionary = mgr.world.players()
		return players.get(robber)

	## Un giocatore lo minaccia con un'arma.
	func rob(peer: int) -> void:
		if dead or state != "idle":
			return
		robber = peer
		shop["robbed_until"] = Time.get_ticks_msec() + 300000  # il locale si può rapinare di nuovo tra 5 minuti
		mgr.world.crime("robbery", global_position, peer)
		if shop.get("kind", "") == "gun":
			_fight(true)  # all'armeria il commesso è armato e reagisce
			return
		var r := randf()
		if r < 0.5:
			state = "hands_up"
			_t = 2.5
		elif r < 0.75:
			_flee(true)
		else:
			_fight(randf() < 0.5)

	func _flee(drop_loot: bool) -> void:
		if drop_loot:
			mgr.drop_cash(global_position + Vector3(0, 0.1, 0), randi_range(150, 500))  # scappa e la refurtiva cade
		state = "flee"
		var p := _robber()
		_from = p.global_position if p else global_position
		_fear = 12.0
		_cower = false

	func _fight(with_gun: bool) -> void:
		state = "fight"
		armed = with_gun
		_t = 25.0
		_cool = 0.8
		if armed and _gun == null:
			_gun = Weapons.model("pistola")
			if _gun:
				add_child(_gun)
				_gun.top_level = true

	func take_damage(amount: float, from_peer: int, at: Vector3) -> void:
		var was_dead := dead
		super.take_damage(amount, from_peer, at)
		if dead and not was_dead and _gun:
			_gun.queue_free()
			_gun = null
		if dead or state == "fight" or state == "flee":
			return
		# Colpito senza rapina o mentre aveva le mani alzate: reagisce o scappa.
		if from_peer > 0:
			robber = from_peer
		if randf() < 0.45 and from_peer > 0:
			_fight(randf() < 0.4)
		else:
			_flee(state == "hands_up")

	func _sees(p: Player) -> bool:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.5, 0), p.global_position + Vector3(0, 1.2, 0), 1)
		return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

	func _physics_process(delta: float) -> void:
		if dead or state == "flee":
			super._physics_process(delta)
			if _fear <= 0.0 and state == "flee":
				state = "done"  # resta in giro come un passante qualunque
			return
		if state == "done":
			super._physics_process(delta)
			return
		var target_v := Vector3.ZERO
		var anim := "idle"
		var face := face_yaw
		match state:
			"idle":
				var to := anchor - global_position
				to.y = 0.0
				if to.length() > 0.6:
					target_v = to.normalized() * 1.4
					anim = "stroll"
					face = atan2(to.x, to.z)
			"hands_up":
				anim = "crouch"  # si fa piccolo, mani avanti
				var p0 := _robber()
				if p0:
					var tp := p0.global_position - global_position
					face = atan2(tp.x, tp.z)
				_t -= delta
				if _t <= 0.0:
					mgr.drop_cash(global_position + Vector3(0, 0.1, 0) + global_basis.z * 0.0, randi_range(300, 900))
					_flee(false)
			"fight":
				var p := _robber()
				_t -= delta
				_cool -= delta
				if p == null or p.dead or _t <= 0.0 or p.global_position.distance_to(global_position) > 60.0:
					_flee(false)
				else:
					var to := p.global_position - global_position
					to.y = 0.0
					var dist := to.length()
					face = atan2(to.x, to.z)
					if armed:
						if dist > 22.0 or not _sees(p):
							target_v = to.normalized() * 5.0
							anim = "sprint"
						else:
							anim = "aim"
							if _cool <= 0.0:
								_cool = randf_range(0.8, 1.5)
								var origin := global_position + Vector3(0, 1.45, 0)
								var aim := p.global_position + Vector3(0, 1.1, 0)
								aim += Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * (0.8 + dist * 0.05)
								mgr.combat.shoot(self, "pistola", origin, (aim - origin).normalized(), _gun.global_position if _gun else origin)
								anim = "shoot"
								_human.play_once("shoot", 0.02)
					else:
						if dist > 1.3:
							target_v = to.normalized() * 5.5
							anim = "sprint"
						elif _cool <= 0.0:
							_cool = 0.9
							mgr.combat.melee(self, "pugni", global_position + Vector3(0, 1.3, 0), to.normalized())
							_human.play_once("punch" if randf() < 0.5 else "punch2")
							anim = "hit"
		velocity.x = lerpf(velocity.x, target_v.x, 1.0 - exp(-8.0 * delta))
		velocity.z = lerpf(velocity.z, target_v.z, 1.0 - exp(-8.0 * delta))
		velocity.y = 0.0 if is_on_floor() else velocity.y - 16.0 * delta
		move_and_slide()
		_human.rotation.y = lerp_angle(_human.rotation.y, face, 1.0 - exp(-10.0 * delta))
		net_anim = anim
		if anim != "shoot" and anim != "hit":
			_human.play(anim)
		if _gun:
			_gun.global_transform = Transform3D(Basis(Vector3.UP, _human.rotation.y + rotation.y), _human.hand_position())


## Fornitore dello spaccio: aspetta nel suo vialetto (fermo, ogni tanto parla al telefono). Si compra da lui con E.
## Se sente spari scappa e poi torna; se viene ucciso lascia dei soldi e per 5 minuti non c'è nessuno.
class Dealer:
	extends Pedestrian

	var shop: Dictionary
	var anchor := Vector3.ZERO
	var _t := 0.0

	func _ready() -> void:
		super._ready()
		set_meta("dealer", true)
		health = 70.0

	func take_damage(amount: float, from_peer: int, at: Vector3) -> void:
		var was_dead := dead
		super.take_damage(amount, from_peer, at)
		if dead and not was_dead:
			shop["robbed_until"] = Time.get_ticks_msec() + 300000
			mgr.drop_cash(global_position, randi_range(200, 600))

	func _physics_process(delta: float) -> void:
		if dead or _fear > 0.0:
			super._physics_process(delta)
			return
		var to := anchor - global_position
		to.y = 0.0
		var target_v := Vector3.ZERO
		var anim := "idle"
		if to.length() > 0.8:
			target_v = to.normalized() * 2.5
			anim = "walk"
		else:
			_t += delta
			anim = "talk" if fmod(_t, 14.0) < 6.0 else "idle"
		velocity.x = lerpf(velocity.x, target_v.x, 1.0 - exp(-8.0 * delta))
		velocity.z = lerpf(velocity.z, target_v.z, 1.0 - exp(-8.0 * delta))
		velocity.y = 0.0 if is_on_floor() else velocity.y - 16.0 * delta
		move_and_slide()
		if target_v.length() > 0.1:
			_human.rotation.y = lerp_angle(_human.rotation.y, atan2(target_v.x, target_v.z), 1.0 - exp(-8.0 * delta))
		net_anim = anim
		_human.play(anim)
