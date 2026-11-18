class_name Traffic
extends Node3D

## Traffico: auto che girano da sole sulla rete stradale vera (sensi unici rispettati), sulla corsia di destra,
## rallentano in curva e si fermano davanti a pedoni, giocatori e altri veicoli. Si possono distruggere.
## Lo calcola solo chi ospita (attorno a tutti i giocatori); gli altri PC lo ricevono da NetSync.

const PER_PLAYER := 30
const MAX_TOTAL := 64
const SPAWN_MIN := 70.0
const SPAWN_MAX := 260.0
const DESPAWN := 330.0

var city: CityBuilder
var world: Node  # main.gd
var combat: Combat
var _pos: Array[Vector2] = []  # nodi del grafo
var _adj: Array = []  # per nodo: Array di [nodo destinazione, larghezza, ponte, senso unico]
var _rng := RandomNumberGenerator.new()


func setup(c: CityBuilder, world_node: Node, cb: Combat) -> void:
	city = c
	world = world_node
	combat = cb
	_rng.randomize()
	var index := {}
	var node_of := func(q: Vector2) -> int:
		var key := Vector2i(roundi(q.x * 10.0), roundi(q.y * 10.0))
		if not index.has(key):
			index[key] = _pos.size()
			_pos.append(q)
			_adj.append([])
		return index[key]
	for r: Dictionary in city.data["roads"]:
		if r["k"] != "road" or float(r["w"]) < 6.0:
			continue
		var pts := city._pts(r["p"])
		var ow: int = int(r.get("o", 0))
		for i in pts.size() - 1:
			var a: int = node_of.call(pts[i])
			var b: int = node_of.call(pts[i + 1])
			if a == b:
				continue
			var w: float = r["w"]
			var br: bool = int(r["b"]) == 1
			if ow >= 0:
				_adj[a].append([b, w, br, ow != 0])
			if ow <= 0:
				_adj[b].append([a, w, br, ow != 0])


func _physics_process(delta: float) -> void:
	if world == null or not world.simulate:
		return
	var anchors: Array = world.anchors()
	if anchors.is_empty():
		return
	_obstacles = world.players().values().map(func(p: Player) -> Vector3: return p.global_position)
	var alive := 0
	for n: Node in get_children():
		var tc := n as TrafficCar
		if tc == null:
			continue
		if Pedestrians.nearest(tc.global_position, anchors) > DESPAWN:
			tc.queue_free()
		else:
			alive += 1
			tc.step(delta)
	if alive < mini(PER_PLAYER * anchors.size(), MAX_TOTAL):
		_spawn_one(anchors[_rng.randi() % anchors.size()], anchors)


var _obstacles: Array = []  # posizioni dei giocatori (aggiornate a ogni passo)


func _spawn_one(me: Vector3, anchors: Array) -> void:
	for attempt in 8:
		var a := _rng.randi() % _pos.size()
		if _adj[a].is_empty():
			continue
		var d := _pos[a].distance_to(Vector2(me.x, me.z))
		if d < SPAWN_MIN or d > SPAWN_MAX or Pedestrians.nearest(Vector3(_pos[a].x, 0, _pos[a].y), anchors) < SPAWN_MIN:
			continue
		var e: Array = _adj[a][_rng.randi() % _adj[a].size()]
		var tc := TrafficCar.new()
		tc.traffic = self
		tc.nid = world.new_nid()
		var buses := get_children().filter(func(n: Node) -> bool: return n is TrafficCar and (n as TrafficCar).is_bus).size()
		if float(e[1]) >= 8.0 and buses < 3 * anchors.size() and _rng.randf() < 0.2:
			# Autobus ATAC (solo sulle strade larghe): aspetto = BUS_LOOK + numero della linea.
			var line := _rng.randi() % Bus.LINES.size()
			tc.look = Bus.LOOK + line
			tc.build_bus(line)
		else:
			var mi := _rng.randi() % (Car.MODELS.size() - 1)  # niente polizia
			var pi := _rng.randi() % Car.PAINTS.size()
			tc.look = mi + pi * 16
			tc.build(Car.MODELS[mi], Car.PAINTS[pi])
		add_child(tc)
		tc.start(a, e)
		return


## Prossimo tratto da un nodo: niente inversioni a U se c'è altra scelta.
func next_edge(at: int, came_from: int) -> Array:
	var options: Array = _adj[at].filter(func(e: Array) -> bool: return int(e[0]) != came_from)
	if options.is_empty():
		options = _adj[at]
	if options.is_empty():
		return []
	return options[_rng.randi() % options.size()]


func node_pos(i: int) -> Vector2:
	return _pos[i]


## Ostacoli divisi in celle da GRID metri, ricostruiti una volta per passo di fisica: ogni auto guarda solo
## le celle vicine invece di scorrere ogni volta tutte le auto parcheggiate e tutti i pedoni.
const GRID := 16.0
var _grid := {}  # Vector2i -> Array di [Vector3, Node]
var _grid_frame := -1


func _rebuild_grid() -> void:
	_grid_frame = Engine.get_physics_frames()
	_grid.clear()
	for p: Vector3 in _obstacles:
		_grid_add(p, null)
	# "damageable" comprende pedoni, agenti, auto parcheggiate, traffico, volanti e giocatori.
	for n: Node in get_tree().get_nodes_in_group("damageable"):
		if not (n is Node3D):
			continue
		if n is Pedestrians.Pedestrian and (n as Pedestrians.Pedestrian).dead:
			continue
		var n3 := n as Node3D
		_grid_add(n3.global_position, n)
		if n is TrafficCar and (n as TrafficCar).is_bus:
			# L'autobus è lungo 12 m: anche muso e coda contano come ostacoli.
			for z: float in [-5.0, -2.5, 2.5, 5.0]:
				_grid_add(n3.global_transform * Vector3(0, 0, z), n)


func _grid_add(p: Vector3, n: Node) -> void:
	var key := Vector2i(floori(p.x / GRID), floori(p.z / GRID))
	var cell: Array = _grid.get(key, [])
	if cell.is_empty():
		_grid[key] = cell
	cell.append([p, n])


## Qualcosa davanti (entro dist metri, nel corridoio della corsia)?
func blocked(pos: Vector3, fwd: Vector3, dist: float, me: Node) -> bool:
	if _grid_frame != Engine.get_physics_frames():
		_rebuild_grid()
	var x0 := floori((pos.x - dist) / GRID)
	var x1 := floori((pos.x + dist) / GRID)
	var z0 := floori((pos.z - dist) / GRID)
	var z1 := floori((pos.z + dist) / GRID)
	for gx in range(x0, x1 + 1):
		for gz in range(z0, z1 + 1):
			var cell: Array = _grid.get(Vector2i(gx, gz), [])
			for e: Array in cell:
				if e[1] == me:
					continue
				var d: Vector3 = e[0] - pos
				var along := d.dot(fwd)
				if along < 0.5 or along > dist:
					continue
				if (d - fwd * along).length() < 1.4 and absf(d.y) < 3.0:
					return true
	return false


## Auto del traffico: segue i tratti del grafo sulla corsia di destra. Corpo cinematico: spinge ma non viene spinto.
class TrafficCar:
	extends AnimatableBody3D

	var traffic: Traffic
	var nid := 0
	var look := 0
	var health := 160.0
	var destroyed := false
	var _from := -1
	var _to := -1
	var _edge: Array = []
	var _t := 0.0
	var _len := 1.0
	var _speed := 0.0
	var _wait := 0.0
	var _visual: Node3D
	var _engine: AudioStreamPlayer3D
	var is_bus := false
	var _wreck_t := 0.0
	var _to_stop := 0.0  # metri alla prossima fermata (autobus)
	var _stop_wait := 0.0

	## Autobus ATAC della linea Bus.LINES[line].
	func build_bus(line: int) -> void:
		is_bus = true
		health = 400.0
		add_to_group("damageable")
		traffic.world.register(nid, self)
		collision_layer = 16
		collision_mask = 0
		sync_to_physics = false
		_visual = Bus.make(line)
		add_child(_visual)
		_engine = Sfx.loop3d(self, "engine", -10.0, 60.0)
		if _engine:
			_engine.pitch_scale = 0.6
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Bus.SIZE
		cs.shape = shape
		cs.position.y = Bus.SIZE.y * 0.5 + 0.3
		add_child(cs)
		_to_stop = traffic._rng.randf_range(120.0, 300.0)

	func build(model: String, paint: Color) -> void:
		add_to_group("damageable")
		traffic.world.register(nid, self)
		collision_layer = 16
		collision_mask = 0
		sync_to_physics = false
		var scene: Node3D = (load("res://assets/cars/%s.glb" % model) as PackedScene).instantiate()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = paint
		mat.metallic = 0.55
		mat.roughness = 0.3
		var aabb := AABB()
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			aabb = mi.get_aabb() if aabb.size == Vector3.ZERO else aabb.merge(mi.get_aabb())
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				var nm := m.resource_name if m else ""
				if not nm in Car.NOT_PAINT and model != "taxi":
					mi.set_surface_override_material(s, mat)
			mi.visibility_range_end = 350.0
		add_child(scene)
		_visual = scene
		_engine = Sfx.loop3d(self, "engine", -14.0, 50.0)
		var shape := BoxShape3D.new()
		shape.size = Vector3(aabb.size.x * 0.95, aabb.size.y * 0.85, aabb.size.z * 0.97)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = aabb.get_center()
		add_child(cs)

	func is_mine() -> bool:
		return true

	func start(a: int, e: Array) -> void:
		_from = a
		_edge = e
		_to = int(e[0])
		_len = maxf(traffic.node_pos(_from).distance_to(traffic.node_pos(_to)), 0.1)
		_t = traffic._rng.randf() * _len
		_place()

	func take_damage(amount: float, from_peer: int, _at: Vector3) -> void:
		if destroyed:
			return
		health -= amount
		if health <= 0.0:
			destroyed = true
			traffic.world.crime("car", global_position, from_peer)
			if _engine:
				_engine.queue_free()
				_engine = null
			var burnt := StandardMaterial3D.new()
			burnt.albedo_color = Color(0.06, 0.055, 0.05)
			for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
				mi.material_override = burnt
			var fire := OmniLight3D.new()
			fire.light_color = Color(1.0, 0.45, 0.15)
			fire.light_energy = 3.0
			fire.omni_range = 8.0
			fire.position.y = 1.2
			add_child(fire)
			traffic.combat.explode(global_position + Vector3(0, 0.8, 0), "auto", from_peer, false)

	func _lane_offset() -> float:
		var w: float = _edge[1]
		return 0.0 if bool(_edge[3]) else clampf(w * 0.25, 1.6, 3.2)

	func _place() -> void:
		var a := traffic.node_pos(_from)
		var b := traffic.node_pos(_to)
		var dir := (b - a) / _len
		var right := Vector2(-dir.y, dir.x)  # z verso sud: questo è il lato destro di chi va da a verso b
		var p := a + dir * _t + right * _lane_offset()
		var y := 0.0 if bool(_edge[2]) else traffic.city.surface_at(p.x, p.y)
		var yaw := atan2(dir.x, dir.y)
		var basis := Basis(Vector3.UP, yaw) if bool(_edge[2]) else traffic.city.ground_basis(p.x, p.y, yaw, 5.0 if is_bus else 2.0)
		global_transform = Transform3D(basis, Vector3(p.x, y + 0.06, p.y))

	func step(delta: float) -> void:
		if destroyed:
			# Il relitto sparisce dopo 45 s se nessuno guarda da vicino (sugli altri PC sparisce la copia).
			_wreck_t += delta
			var cam := get_viewport().get_camera_3d()
			if _wreck_t > 45.0 and (cam == null or cam.global_position.distance_to(global_position) > 40.0):
				queue_free()
			return
		var a := traffic.node_pos(_from)
		var b := traffic.node_pos(_to)
		var dir := (b - a) / _len
		var fwd := Vector3(dir.x, 0, dir.y)
		# Velocità: più lenta sulle strade strette e verso una curva stretta.
		var cruise: float = 13.0 if float(_edge[1]) >= 10.0 else 9.0
		if is_bus:
			cruise = 9.0 if float(_edge[1]) >= 10.0 else 7.0
		var remaining := _len - _t
		if remaining < 12.0:
			cruise = minf(cruise, (4.0 if is_bus else 6.0) + remaining * 0.4)
		# L'autobus guarda davanti dal muso, non dal centro.
		var from := global_position + Vector3(0, 0.5, 0) + (fwd * 5.5 if is_bus else Vector3.ZERO)
		var stop := traffic.blocked(from, fwd, 6.0 + _speed * 0.9, self)
		if is_bus:
			# Fermate: ogni 200-400 m si accosta e aspetta qualche secondo.
			if _stop_wait > 0.0:
				_stop_wait -= delta
				stop = true
				_wait = 0.0
			elif _to_stop <= 0.0:
				_stop_wait = traffic._rng.randf_range(5.0, 9.0)
				_to_stop = traffic._rng.randf_range(200.0, 400.0)
			_to_stop -= _speed * delta
		if stop:
			_wait += delta
		else:
			_wait = 0.0
		# Dopo 6 s di attesa si riparte comunque (incroci bloccati).
		var target := 0.0 if stop and _wait < 6.0 else cruise
		_speed = move_toward(_speed, target, delta * (9.0 if target < _speed else 3.0))
		if _engine:
			_engine.pitch_scale = 0.5 + _speed / 18.0
		_t += _speed * delta
		while _t >= _len:
			_t -= _len
			var nxt := traffic.next_edge(_to, _from)
			if nxt.is_empty():
				queue_free()
				return
			_from = _to
			_edge = nxt
			_to = int(nxt[0])
			_len = maxf(traffic.node_pos(_from).distance_to(traffic.node_pos(_to)), 0.1)
		var old := global_transform
		_place()
		# Sterzata morbida: interpolo la rotazione.
		var new_q := global_transform.basis.get_rotation_quaternion()
		global_transform.basis = Basis(old.basis.get_rotation_quaternion().slerp(new_q, 1.0 - exp(-8.0 * delta)))
