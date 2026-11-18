class_name Police
extends Node3D

## Livello di ricercato (1-5 stelle) per ogni giocatore e forze dell'ordine, come in GTA.
## Reati: sparare vicino a qualcuno, uccidere un pedone, distruggere un'auto, colpire o uccidere un agente.
## Le volanti partono dai presidi veri del quartiere (OpenStreetMap: Questura - Prima Sezione Volanti,
## Commissariati Villa Glori e Prati, Comando Legione Carabinieri Lazio, stazione Carabinieri, Scuola Superiore
## di Polizia), arrivano con la sirena seguendo le strade e fanno scendere due agenti. Da 3 stelle si aggiungono
## pattuglie a piedi già in zona. Se nessun agente ti vede per un po', le stelle spariscono.
## La calcola solo chi ospita; insegue chiunque sia ricercato. Si può disattivare (active = false).

const MAX_STARS := 5
const CARS_PER_STAR := [0, 1, 2, 3, 4, 5]
## Secondi senza farsi vedere per perdere le stelle: 10 + 4 per stella (1 stella 14 s, 5 stelle 30 s).
const SHAKE_BASE := 10.0
const SHAKE_PER_STAR := 4.0

var active := true
var city: CityBuilder
var world: Node  # main.gd: players(), anchors(), simulate, new_nid(), register()
var combat: Combat
var traffic: Traffic
var pedestrians: Pedestrians
var wanted := {}  # peer -> stelle
var calm := {}  # peer -> secondi senza essere visto
var last_seen := {}  # peer -> Vector3: dove la polizia ha visto il ricercato l'ultima volta (lì lo cerca)
var stations: Array = []  # [Vector2, nome, carabinieri?]
var _astar := AStar2D.new()
var _rng := RandomNumberGenerator.new()
var _spawn_cd := 0.0
var _next_station := 0
var _sight_t := 0.0


func setup(c: CityBuilder, w: Node, cb: Combat, t: Traffic, peds: Pedestrians) -> void:
	city = c
	world = w
	combat = cb
	traffic = t
	pedestrians = peds
	_rng.randomize()
	# Grafo per le volanti: le stesse strade del traffico, ma la polizia ignora i sensi unici.
	for i in traffic._pos.size():
		_astar.add_point(i, traffic._pos[i])
	for i in traffic._adj.size():
		for e: Array in traffic._adj[i]:
			if not _astar.are_points_connected(i, int(e[0])):
				_astar.connect_points(i, int(e[0]), true)
	for p: Array in city.data.get("pois", []):
		if p[3] == "police":
			var n: String = p[2]
			stations.append([Vector2(p[0], p[1]), n, n.contains("arabinier")])


func level(peer: int) -> int:
	return int(wanted.get(peer, 0))


func calm_of(peer: int) -> float:
	return float(calm.get(peer, 0.0))


func calm_of_player(p: Player) -> float:
	return calm_of(_peer_of(p))


## Segnala un reato commesso dal giocatore peer.
func report(crime: String, pos: Vector3, peer: int) -> void:
	if not active or peer <= 0:
		return
	var w := level(peer)
	match crime:
		"shots":
			if w == 0 and _witnessed(pos):
				w = 1
		"kill":
			w = mini(maxi(w + 1, 2), 4)
		"car":
			if _witnessed(pos):
				w = mini(maxi(w, 1) + (1 if w > 0 else 0), 4)
		"assault":
			w = maxi(w, 2)
		"cop_kill":
			w = mini(w + 2, MAX_STARS)
		"rocket":
			w = maxi(w, 3)
		"dealing":
			# Spaccio: qualcuno ha chiamato la polizia, o un agente ti ha visto. 1 stella.
			w = maxi(w, 1)
		"robbery":
			w = maxi(w, 2)
		"theft":
			# Furto d'auto: 1 stella solo se c'è un agente lì vicino (come in GTA).
			for c: Node in get_tree().get_nodes_in_group("cop"):
				if not (c as Cop).dead and (c as Node3D).global_position.distance_to(pos) < 45.0:
					w = maxi(w, 1)
					break
	if w > level(peer):
		wanted[peer] = mini(w, MAX_STARS)
	if level(peer) > 0:
		calm[peer] = 0.0
		last_seen[peer] = pos  # il reato rivela dove sei


func clear(peer: int) -> void:
	wanted.erase(peer)
	calm.erase(peer)
	last_seen.erase(peer)


func _peer_of(p: Player) -> int:
	var players: Dictionary = world.players()
	for peer: int in players:
		if players[peer] == p:
			return peer
	return 0


## Un agente vede il ricercato: la polizia sa di nuovo dov'è.
func spotted(p: Player) -> void:
	var peer := _peer_of(p)
	if peer != 0 and level(peer) > 0:
		calm[peer] = 0.0
		last_seen[peer] = p.global_position


## Dove andare a cercare il ricercato: dove si trova, se l'hanno visto da poco; altrimenti l'ultimo punto
## in cui l'hanno visto. Se sparisci dalla loro vista, perquisiscono quella zona invece di inseguirti.
func goal_for(p: Player) -> Vector3:
	var peer := _peer_of(p)
	if calm_of(peer) < 2.0 or not last_seen.has(peer):
		return p.global_position
	return last_seen[peer]


func set_active(on: bool) -> void:
	active = on
	if not on:
		wanted.clear()
		calm.clear()
		for n: Node in get_children():
			n.queue_free()


func _witnessed(pos: Vector3) -> bool:
	for n: Node in get_tree().get_nodes_in_group("pedestrian"):
		if (n as Node3D).global_position.distance_to(pos) < 45.0:
			return true
	return not get_tree().get_nodes_in_group("cop").is_empty()


## Il giocatore ricercato più vicino a pos (o null).
func target_near(pos: Vector3) -> Player:
	var best: Player = null
	var best_d := INF
	var players: Dictionary = world.players()
	for peer: int in players:
		var p: Player = players[peer]
		if level(peer) <= 0 or p.dead:
			continue
		var d := p.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = p
	return best


func _physics_process(delta: float) -> void:
	if world == null or not world.simulate or not active:
		return
	var players: Dictionary = world.players()
	var cops := get_tree().get_nodes_in_group("cop")
	var cars := get_children().filter(func(n: Node) -> bool: return n is PoliceCar)
	# Chi è ricercato e non è visto da nessun agente si calma; dopo un po' le stelle spariscono.
	# Il controllo della vista (un raggio per agente) si fa 5 volte al secondo, non a ogni passo.
	_sight_t += delta
	if _sight_t >= 0.2:
		var step := _sight_t
		_sight_t = 0.0
		for peer: int in wanted.keys():
			if not players.has(peer) or (players[peer] as Player).dead:
				clear(peer)
				continue
			var pl: Player = players[peer]
			var seen := false
			for c: Node in cops:
				if (c as Cop).sees(pl):
					seen = true
					break
			if not seen:
				# Le volanti in corsa vedono anche loro (a distanza minore, se non c'è un muro in mezzo).
				for n: Node in cars:
					if (n as PoliceCar).sees(pl):
						seen = true
						break
			calm[peer] = 0.0 if seen else calm_of(peer) + step
			if seen:
				last_seen[peer] = pl.global_position
			if calm_of(peer) > SHAKE_BASE + level(peer) * SHAKE_PER_STAR:
				clear(peer)  # seminati
	var top := 0
	for peer: int in wanted:
		top = maxi(top, level(peer))
	_spawn_cd -= delta
	if top > 0 and _spawn_cd <= 0.0:
		_spawn_cd = 3.0
		var want_cars := 0
		for peer: int in wanted:
			want_cars += CARS_PER_STAR[level(peer)]
		if cars.size() < mini(want_cars, 7):
			_dispatch_car()
		var alive := cops.filter(func(c: Node) -> bool: return not (c as Cop).dead).size()
		if top >= 3 and alive < top * 2 + 2:
			var t := _any_wanted()
			if t:
				_spawn_patrol(t)
	# Se ne vanno quando nessuno è più ricercato o sono lontanissimi da tutti.
	var anchors: Array = world.anchors()
	for c: Node in cops:
		var cop := c as Cop
		var d := Pedestrians.nearest(cop.global_position, anchors)
		if (top == 0 and d > 60.0) or d > 450.0 or (cop.dead and cop.dead_time > 30.0):
			cop.queue_free()
	for n: Node in cars:
		var pc := n as PoliceCar
		var d := Pedestrians.nearest(pc.global_position, anchors)
		if (top == 0 and d > 80.0 and pc.arrived) or (pc.arrived and d > 500.0):
			pc.queue_free()


func _any_wanted() -> Player:
	var players: Dictionary = world.players()
	var list := wanted.keys().filter(func(p: int) -> bool: return players.has(p))
	if list.is_empty():
		return null
	return players[list[_rng.randi() % list.size()]]


## Manda una volante dal presidio più vicino al ricercato (a turno, se ce ne sono più di uno vicini).
func _dispatch_car() -> void:
	var t := _any_wanted()
	if t == null or stations.is_empty():
		return
	var g := goal_for(t)
	var tp := Vector2(g.x, g.z)
	var order := stations.duplicate()
	order.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as Vector2).distance_to(tp) < (b[0] as Vector2).distance_to(tp))
	var st: Array = order[_next_station % mini(2, order.size())]
	_next_station += 1
	var start := _astar.get_closest_point(st[0])
	var goal := _astar.get_closest_point(tp)
	var route := _astar.get_id_path(start, goal)
	if route.size() < 2:
		return
	var pc := PoliceCar.new()
	pc.police = self
	pc.nid = world.new_nid()
	pc.carabinieri = st[2]
	pc.station = st[1]
	add_child(pc)
	pc.go(route)


## Pattuglia a piedi già in zona: compare all'aperto vicino a dove il ricercato è stato visto l'ultima volta,
## ma mai a meno di 100 m da lui (oltre la vista degli agenti: non deve "vederlo" appena compare).
func _spawn_patrol(target: Player) -> void:
	var me := target.global_position
	var around := goal_for(target)
	var space := get_world_3d().direct_space_state
	for attempt in 12:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(40.0, 110.0)
		var p := around + Vector3(cos(a), 0, sin(a)) * r
		if Vector2(p.x - me.x, p.z - me.z).length() < 100.0:
			continue
		var ground := city.surface_at(p.x, p.z)
		if city.carve_at(p.x, p.z) < -0.3:
			continue  # niente banchine del Tevere
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, ground + 90.0, p.z), Vector3(p.x, ground - 20.0, p.z), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or float(hit["position"].y) > ground + 0.6:
			continue
		spawn_cop(hit["position"] + Vector3(0, 0.2, 0), false)
		return


func spawn_cop(pos: Vector3, carabiniere: bool) -> Cop:
	var cop := Cop.new()
	cop.police = self
	cop.nid = world.new_nid()
	cop.preset = "cc_m" if carabiniere else ("cop_m" if _rng.randf() < 0.7 else "cop_f")
	var top := 0
	for peer: int in wanted:
		top = maxi(top, level(peer))
	cop.weapon = "mitragliatrice" if top >= 4 and _rng.randf() < 0.5 else "pistola"
	add_child(cop)
	cop.global_position = pos
	return cop


func route_to(from: Vector3, to: Vector3) -> PackedInt64Array:
	var a := _astar.get_closest_point(Vector2(from.x, from.z))
	var b := _astar.get_closest_point(Vector2(to.x, to.z))
	return _astar.get_id_path(a, b)


## Per la minimappa: posizioni degli agenti e delle volanti.
func dots() -> Array:
	var out := []
	for c: Node in get_tree().get_nodes_in_group("cop"):
		if not (c as Cop).dead:
			out.append((c as Node3D).global_position)
	for n: Node in get_children():
		if n is PoliceCar:
			out.append((n as Node3D).global_position)
	return out


## Colori delle volanti: Polizia azzurra e bianca, Carabinieri blu scuro.
static func paint_car(scene: Node, carabinieri: bool) -> void:
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.05, 0.07, 0.17) if carabinieri else Color(0.16, 0.38, 0.75)
	blue.metallic = 0.5
	blue.roughness = 0.3
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.05, 0.07, 0.17) if carabinieri else Color(0.93, 0.94, 0.95)
	white.metallic = 0.3
	white.roughness = 0.3
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			var n := m.resource_name if m else ""
			if n == "Black":
				mi.set_surface_override_material(s, blue)
			elif n == "White":
				mi.set_surface_override_material(s, white)


## Agente a piedi: corre verso il ricercato più vicino, si ferma a distanza di tiro e spara (con imprecisione).
class Cop:
	extends CharacterBody3D

	var police: Police
	var nid := 0
	var preset := "cop_m"
	var weapon := "pistola"
	var health := 90.0
	var dead := false
	var dead_time := 0.0
	var net_anim := "idle"
	var _human: Human
	var _gun: Node3D
	var _cool := 1.0
	var _stuck := 0.0
	var _side := 1.0
	var _target: Player
	var _retarget := 0.0
	var _search_pt := Vector3.INF
	var _search_t := 0.0

	func _ready() -> void:
		add_to_group("damageable")
		add_to_group("cop")
		add_to_group("pedestrian")  # per il traffico e gli investimenti è un passante
		police.world.register(nid, self)
		collision_layer = 32
		collision_mask = 1 | 2 | 16
		var shape := CapsuleShape3D.new()
		shape.radius = 0.3
		shape.height = 1.7
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 0.85
		add_child(cs)
		_human = Human.new().setup(preset)
		add_child(_human)
		_gun = Weapons.model(weapon)
		if _gun:
			add_child(_gun)
			_gun.top_level = true

	func is_mine() -> bool:
		return true

	func human() -> Human:
		return _human

	func sees(p: Player) -> bool:
		if dead or p == null:
			return false
		var from := global_position + Vector3(0, 1.6, 0)
		var to := p.global_position + Vector3(0, 1.3, 0)
		if from.distance_to(to) > 90.0:
			return false
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

	func take_damage(amount: float, from_peer: int, at: Vector3) -> void:
		if dead:
			return
		health -= amount
		if health <= 0.0:
			dead = true
			net_anim = "death"
			collision_layer = 0
			_human.play_once("death")
			if _gun:
				_gun.queue_free()
				_gun = null
			police.report("cop_kill", at, from_peer)
			police.pedestrians.drop_cash(global_position, randi_range(40, 120))
			# Lascia anche la sua arma con un caricatore o due di colpi.
			var mag: int = int(Weapons.info(weapon).get("mag", 12))
			police.pedestrians.drop_ammo(global_position + global_basis.x * 0.8, weapon, mag * randi_range(1, 2))
		else:
			_human.play_once("hit")
			police.report("assault", at, from_peer)

	func _physics_process(delta: float) -> void:
		if dead:
			dead_time += delta
			velocity = Vector3(0, velocity.y - 16.0 * delta, 0)
			move_and_slide()
			return
		_retarget -= delta
		if _retarget <= 0.0:
			_retarget = 1.0
			_target = police.target_near(global_position)
		var target_v := Vector3.ZERO
		var anim := "idle"
		_cool -= delta
		if _target == null or not is_instance_valid(_target) or _target.dead:
			anim = "idle"
		else:
			var sees_it := sees(_target)
			if sees_it:
				police.spotted(_target)
			# Se non lo vede corre dove l'hanno visto l'ultima volta; arrivato lì, perlustra i dintorni.
			var goal := _target.global_position if sees_it else police.goal_for(_target)
			if not sees_it and Vector2(goal.x - global_position.x, goal.z - global_position.z).length() < 4.0:
				_search_t -= delta
				if _search_t <= 0.0 or _search_pt == Vector3.INF:
					_search_t = randf_range(3.0, 6.0)
					var a := randf() * TAU
					_search_pt = goal + Vector3(cos(a), 0, sin(a)) * randf_range(8.0, 25.0)
			if not sees_it and _search_pt != Vector3.INF and _search_t > 0.0 and police.calm_of_player(_target) > 2.0:
				goal = _search_pt
			if sees_it:
				_search_pt = Vector3.INF
				_search_t = 0.0
			var to := goal - global_position
			to.y = 0.0
			var dist := to.length()
			if not sees_it and dist < 1.5:
				pass  # fermo a guardarsi intorno
			elif dist > 16.0 or not sees_it:
				var dir := to.normalized()
				# Se è bloccato da un muro, prova a girarci attorno.
				if _stuck > 0.6:
					dir = (dir + Vector3(-dir.z, 0, dir.x) * _side * 1.5).normalized()
				target_v = dir * 6.5
				anim = "sprint"
			else:
				anim = "aim"
				_human.rotation.y = lerp_angle(_human.rotation.y, atan2(to.x, to.z), 1.0 - exp(-10.0 * delta))
				if _cool <= 0.0:
					_shoot(_target)
		velocity.x = lerpf(velocity.x, target_v.x, 1.0 - exp(-8.0 * delta))
		velocity.z = lerpf(velocity.z, target_v.z, 1.0 - exp(-8.0 * delta))
		velocity.y = 0.0 if is_on_floor() else velocity.y - 16.0 * delta
		var before := global_position
		move_and_slide()
		if target_v.length() > 1.0 and global_position.distance_to(before) < target_v.length() * delta * 0.3:
			_stuck += delta
			if _stuck > 2.5:
				_stuck = 0.0
				_side = -_side
		else:
			_stuck = maxf(0.0, _stuck - delta)
		if Vector2(velocity.x, velocity.z).length() > 0.5:
			_human.rotation.y = lerp_angle(_human.rotation.y, atan2(velocity.x, velocity.z), 1.0 - exp(-8.0 * delta))
		net_anim = anim
		_human.play(anim)
		if _gun:
			_gun.global_transform = Transform3D(Basis(Vector3.UP, _human.rotation.y + rotation.y), _human.hand_position())

	func _shoot(p: Player) -> void:
		var auto := weapon == "mitragliatrice"
		_cool = randf_range(0.12, 0.2) if auto and randf() < 0.8 else randf_range(0.7, 1.4)
		var origin := global_position + Vector3(0, 1.45, 0)
		var target := p.global_position + Vector3(0, 1.1, 0)
		# Imprecisione: più alta se il bersaglio corre o è lontano.
		var vel := p.velocity if p.is_local else Vector3.ZERO
		var miss := 0.95 + target.distance_to(origin) * 0.04 + Vector2(vel.x, vel.z).length() * 0.15
		target += Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * miss
		var dir := (target - origin).normalized()
		var muzzle := _gun.global_position if _gun else origin
		police.combat.shoot(self, weapon, origin, dir, muzzle)
		net_anim = "shoot"
		_human.play_once("shoot", 0.02)


## Volante: parte dal presidio, segue il percorso A* con la sirena, si ferma vicino al ricercato e fa
## scendere due agenti (carabinieri se viene da una caserma dei Carabinieri).
class PoliceCar:
	extends AnimatableBody3D

	var police: Police
	var nid := 0
	var carabinieri := false
	var station := ""
	var health := 260.0
	var destroyed := false
	var arrived := false
	var _route: PackedInt64Array
	var _k := 0
	var _speed := 0.0
	var _repath := 3.0
	var _lights: Array[OmniLight3D] = []
	var _siren: AudioStreamPlayer3D
	var _blink := 0.0

	func _ready() -> void:
		add_to_group("damageable")
		police.world.register(nid, self)
		collision_layer = 16
		var scene: Node3D = (load("res://assets/cars/police.glb") as PackedScene).instantiate()
		Police.paint_car(scene, carabinieri)
		add_child(scene)
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.8, 1.2, 4.2)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 0.7
		add_child(cs)
		_lights = PoliceCar.make_lights(self)
		_siren = Sfx.loop3d(self, "siren", 2.0, 260.0)

	static func make_lights(n: Node3D) -> Array[OmniLight3D]:
		var out: Array[OmniLight3D] = []
		for col: Color in [Color(0.15, 0.3, 1.0), Color(0.15, 0.3, 1.0)]:
			var l := OmniLight3D.new()
			l.light_color = col
			l.light_energy = 3.0
			l.omni_range = 9.0
			l.position = Vector3(0.4 if out.is_empty() else -0.4, 1.5, 0)
			n.add_child(l)
			out.append(l)
		return out

	static func blink(lights: Array[OmniLight3D], t: float) -> void:
		if lights.size() == 2:
			var on := int(t * 4.0) % 2 == 0
			lights[0].light_energy = 4.0 if on else 0.2
			lights[1].light_energy = 0.2 if on else 4.0

	func is_mine() -> bool:
		return true

	## Dalla volante si vede fino a 50 m, se non ci sono palazzi in mezzo.
	func sees(p: Player) -> bool:
		if destroyed or p == null or p.dead:
			return false
		var from := global_position + Vector3(0, 1.5, 0)
		var to := p.global_position + Vector3(0, 1.3, 0)
		if from.distance_to(to) > 50.0:
			return false
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

	func take_damage(amount: float, from_peer: int, at: Vector3) -> void:
		if destroyed or from_peer < 0:
			return  # i colpi degli agenti non danneggiano le loro volanti
		health -= amount
		police.report("assault", at, from_peer)
		if health <= 0.0:
			destroyed = true
			if _siren:
				_siren.queue_free()
			for l in _lights:
				l.queue_free()
			_lights.clear()
			var burnt := StandardMaterial3D.new()
			burnt.albedo_color = Color(0.06, 0.055, 0.05)
			for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
				mi.material_override = burnt
			_blink = 0.0  # da qui conta il tempo del relitto
			police.combat.explode(global_position + Vector3(0, 0.8, 0), "auto", -1, false)

	func go(route: PackedInt64Array) -> void:
		_route = route
		_k = 0
		var p := police._astar.get_point_position(route[0])
		global_position = Vector3(p.x, police.city.surface_at(p.x, p.y) + 0.06, p.y)

	func _physics_process(delta: float) -> void:
		if destroyed:
			# Relitto: sparisce dopo 45 s se nessuno guarda da vicino.
			_blink += delta
			var cam := get_viewport().get_camera_3d()
			if _blink > 45.0 and (cam == null or cam.global_position.distance_to(global_position) > 40.0):
				queue_free()
			return
		_blink += delta
		PoliceCar.blink(_lights, _blink)
		if arrived:
			return
		var target := police.target_near(global_position)
		if target == null:
			_arrive(false)
			return
		var me := police.goal_for(target)  # dove l'hanno visto l'ultima volta, non dove si trova davvero
		if global_position.distance_to(me) < 22.0 or _k >= _route.size():
			_arrive(true)
			return
		_repath -= delta
		if _repath <= 0.0:
			_repath = 3.0
			var r := police.route_to(global_position, me)
			if r.size() >= 2:
				_route = r
				_k = 1
		var t2 := police._astar.get_point_position(_route[_k])
		var to := Vector3(t2.x, global_position.y, t2.y) - global_position
		to.y = 0.0
		if to.length() < 2.0:
			_k += 1
			return
		var dir := to.normalized()
		var blocked := police.traffic.blocked(global_position + Vector3(0, 0.5, 0), dir, 7.0, self)
		_speed = move_toward(_speed, 5.0 if blocked else 22.0, delta * (10.0 if blocked else 5.0))
		var p := global_position + dir * _speed * delta
		p.y = police.city.surface_at(p.x, p.z) + 0.06
		var q := police.city.ground_basis(p.x, p.z, atan2(dir.x, dir.z)).get_rotation_quaternion()  # inclinata in salita
		global_transform = Transform3D(Basis(global_basis.get_rotation_quaternion().slerp(q, 1.0 - exp(-6.0 * delta))), p)

	func _arrive(with_cops: bool) -> void:
		arrived = true
		if with_cops:
			for side: float in [1.0, -1.0]:
				police.spawn_cop(global_transform * Vector3(1.8 * side, 0.2, 0.0), carabinieri)
