class_name Combat
extends Node3D

## Spari, proiettili, esplosivi, esplosioni ed effetti. Chi può subire danni sta nel gruppo "damageable" e ha
## take_damage(quantità: float, da_peer: int, punto: Vector3).
## In rete: effetti ed esplosioni vengono ripetuti su tutti i PC tramite i Callable net_fx; ogni PC applica i danni
## delle esplosioni a ciò che controlla (il proprio giocatore, i propri pedoni, le auto).

const RAY_MASK := 1 | 2 | 4 | 8 | 16 | 32  # mondo, alberi, giocatore locale, altri giocatori, auto, pedoni

signal noise(pos: Vector3, radius: float)  # rumore di spari ed esplosioni: i pedoni scappano
signal crime(kind: String, pos: Vector3)  # reato del giocatore di questo PC: lo ascolta la polizia

var net_fx: Callable  # func(tipo: String, dati: Array) -> manda l'effetto agli altri
var my_peer := 1
var _placed: Array = []  # mine e TNT: [Node3D, id arma, peer]
var _flash_mat: StandardMaterial3D
var _smoke_mat: StandardMaterial3D


func _ready() -> void:
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1.0, 0.85, 0.4)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.albedo_color = Color(0.25, 0.24, 0.23, 0.8)
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


# --- Armi ---------------------------------------------------------------------------------------


## Colpo con un'arma da fuoco: raggio dal centro dello schermo (origin, dir). Restituisce i punti colpiti.
func shoot(shooter: Node, weapon_id: String, origin: Vector3, dir: Vector3, muzzle: Vector3) -> void:
	var w := Weapons.info(weapon_id)
	var pellets: int = w.get("pellets", 1)
	var space := get_world_3d().direct_space_state
	for i in pellets:
		var spread: float = w.get("spread", 0.0)
		var d := (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + d * float(w.get("range", 150.0)), RAY_MASK)
		q.exclude = _exclude(shooter)
		var hit := space.intersect_ray(q)
		var end: Vector3 = hit["position"] if hit else origin + d * float(w.get("range", 150.0))
		if hit:
			_damage_collider(hit["collider"], float(w["damage"]), end, _attacker(shooter))
			impact(end, hit["normal"])
		tracer(muzzle, end)
		if net_fx.is_valid():
			net_fx.call("tracer", [muzzle, end, 1 if hit else 0, hit["normal"] if hit else Vector3.UP, weapon_id])
	muzzle_flash(muzzle)
	Sfx.gunshot(weapon_id, muzzle)
	noise.emit(muzzle, 45.0)


## Attacco corpo a corpo: colpisce il primo bersaglio davanti entro la portata.
func melee(shooter: Node, weapon_id: String, origin: Vector3, dir: Vector3) -> bool:
	var w := Weapons.info(weapon_id)
	var space := get_world_3d().direct_space_state
	for off in [Vector3.ZERO, Vector3(0, -0.4, 0), Vector3(0, 0.3, 0)]:
		var q := PhysicsRayQueryParameters3D.create(origin + off, origin + off + dir * float(w["range"]), RAY_MASK)
		q.exclude = _exclude(shooter)
		var hit := space.intersect_ray(q)
		if hit and _damage_collider(hit["collider"], float(w["damage"]), hit["position"], _attacker(shooter)):
			Sfx.play3d("punch", hit["position"], 2.0)
			return true
	Sfx.play3d("swing", origin, -4.0)
	return false


func rocket(shooter: Node, origin: Vector3, dir: Vector3, peer: int) -> void:
	var r := Projectile.new()
	r.combat = self
	r.kind = "rocket"
	r.velocity = dir * float(Weapons.info("bazooka")["speed"])
	r.peer = peer
	r.exclude = _exclude(shooter)
	add_child(r)
	r.global_position = origin
	Sfx.play3d("rocket", origin, 4.0, 1.0, 400.0)
	if net_fx.is_valid() and peer == my_peer:
		net_fx.call("rocket", [origin, dir])


func grenade(shooter: Node, origin: Vector3, dir: Vector3, peer: int) -> void:
	var g := Projectile.new()
	g.combat = self
	g.kind = "grenade"
	g.velocity = dir * 17.0 + Vector3(0, 5.0, 0)
	g.fuse = float(Weapons.info("granata")["fuse"])
	g.peer = peer
	g.exclude = _exclude(shooter)
	add_child(g)
	g.global_position = origin
	if net_fx.is_valid() and peer == my_peer:
		net_fx.call("grenade", [origin, dir])


## Appoggia una mina o una carica di TNT ai piedi del giocatore.
func place(weapon_id: String, pos: Vector3, peer: int) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_position = pos
	var m := Weapons.model(weapon_id)
	if m:
		node.add_child(m)
		m.position.y = 0.08
		m.rotation.x = -PI / 2 if weapon_id == "tnt" else 0.0
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.1, 0.05)
	light.light_energy = 0.6
	light.omni_range = 1.5
	light.position.y = 0.3
	node.add_child(light)
	_placed.append([node, weapon_id, peer, Time.get_ticks_msec() / 1000.0])
	Sfx.play3d("beep", pos, -2.0)
	if net_fx.is_valid() and peer == my_peer:
		net_fx.call("place", [weapon_id, pos])


## Fa saltare tutte le cariche di TNT di questo giocatore.
func detonate(peer: int) -> int:
	var n := 0
	for p: Array in _placed.duplicate():
		if p[1] == "tnt" and p[2] == peer:
			_placed.erase(p)
			var pos: Vector3 = (p[0] as Node3D).global_position
			p[0].queue_free()
			explode(pos, "tnt", peer)
			n += 1
	if n > 0 and net_fx.is_valid() and peer == my_peer:
		net_fx.call("detonate", [])
	return n


func _physics_process(_delta: float) -> void:
	# Mine: scattano se qualcuno (diverso da chi le ha messe, dopo 2 s) si avvicina.
	var now := Time.get_ticks_msec() / 1000.0
	for p: Array in _placed.duplicate():
		if p[1] != "mina" or now - float(p[3]) < 2.0:
			continue
		var pos: Vector3 = (p[0] as Node3D).global_position
		for t: Node in get_tree().get_nodes_in_group("damageable"):
			if t is Node3D and (t as Node3D).global_position.distance_to(pos) < float(Weapons.info("mina")["trigger"]):
				_placed.erase(p)
				p[0].queue_free()
				explode(pos, "mina", p[2])
				break


# --- Danni --------------------------------------------------------------------------------------


func _exclude(shooter: Node) -> Array[RID]:
	var out: Array[RID] = []
	if shooter is CollisionObject3D:
		out.append((shooter as CollisionObject3D).get_rid())
	if shooter is Player and (shooter as Player).vehicle:
		out.append((shooter as Player).vehicle.get_rid())
	return out


## Chi spara: il giocatore di questo PC (my_peer) oppure -1 per poliziotti e altri personaggi del gioco.
func _attacker(shooter: Node) -> int:
	return my_peer if shooter is Player else -1


func _damage_collider(col: Object, amount: float, at: Vector3, attacker := -2) -> bool:
	var n := col as Node
	while n != null:
		if n.is_in_group("damageable") and n.has_method("take_damage"):
			n.take_damage(amount, my_peer if attacker == -2 else attacker, at)
			return true
		n = n.get_parent()
	return false


## Esplosione: danno che cala con la distanza, spinta alle auto, effetto. Ognuno applica il danno a ciò che controlla.
func explode(pos: Vector3, weapon_id: String, peer: int, replicate := true) -> void:
	var w := Weapons.info(weapon_id)
	var radius: float = w.get("radius", 6.0)
	var dmg: float = w.get("damage", 100.0)
	for t: Node in get_tree().get_nodes_in_group("damageable"):
		if not (t is Node3D):
			continue
		var d := (t as Node3D).global_position.distance_to(pos)
		if d < radius and t.has_method("take_damage"):
			if t.has_method("is_mine") and not t.is_mine():
				continue  # il giocatore di un altro PC: il danno lo calcola il suo PC
			t.take_damage(dmg * (1.0 - d / radius * 0.8), peer, pos)
			if t is Car:
				var car := t as Car
				car.blast(pos, radius)
	explosion_fx(pos, radius)
	Sfx.play3d("explosion", pos, 8.0, 1.0, 1200.0)
	noise.emit(pos, 80.0)
	if replicate and net_fx.is_valid() and peer == my_peer:
		net_fx.call("explode", [pos, weapon_id])


# --- Effetti ------------------------------------------------------------------------------------


func tracer(a: Vector3, b: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _flash_mat)
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)


func muzzle_flash(at: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.45)
	l.light_energy = 3.0
	l.omni_range = 5.0
	add_child(l)
	l.global_position = at
	get_tree().create_timer(0.05).timeout.connect(l.queue_free)


func impact(at: Vector3, normal: Vector3) -> void:
	Sfx.play3d("impact", at, -6.0, 1.0, 60.0)
	var s := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	sphere.radial_segments = 6
	sphere.rings = 3
	s.mesh = sphere
	s.material_override = _smoke_mat
	add_child(s)
	s.global_position = at + normal * 0.05
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector3.ONE * 3.0, 0.4)
	tw.parallel().tween_property(s, "transparency", 1.0, 0.4)
	tw.tween_callback(s.queue_free)


func explosion_fx(pos: Vector3, radius: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 12.0
	l.omni_range = radius * 3.0
	add_child(l)
	l.global_position = pos + Vector3(0, 1, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.6)
	tw.tween_callback(l.queue_free)
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.albedo_color = Color(1.0, 0.55, 0.15)
	fire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 7:
		var s := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		s.mesh = sphere
		s.material_override = fire if i < 3 else _smoke_mat
		add_child(s)
		s.global_position = pos + Vector3(randf_range(-1, 1), randf_range(0, 1.5), randf_range(-1, 1)) * radius * 0.25
		var target := Vector3.ONE * radius * (0.6 if i < 3 else 0.9)
		var t := s.create_tween()
		t.tween_property(s, "scale", target, 0.35 if i < 3 else 1.2)
		t.parallel().tween_property(s, "position:y", s.position.y + (1.0 if i < 3 else 4.0), 1.2)
		t.parallel().tween_property(s, "transparency", 1.0, 0.5 if i < 3 else 1.6)
		t.tween_callback(s.queue_free)


## Ripete sul proprio PC un effetto arrivato dalla rete.
func remote_fx(kind: String, data: Array, peer: int) -> void:
	match kind:
		"tracer":
			tracer(data[0], data[1])
			muzzle_flash(data[0])
			Sfx.gunshot(String(data[4]) if data.size() > 4 else "pistola", data[0])
			noise.emit(data[0], 45.0)
			if int(data[2]) == 1:
				impact(data[1], data[3])
		"rocket":
			rocket(null, data[0], data[1], peer)
		"grenade":
			grenade(null, data[0], data[1], peer)
		"place":
			place(data[0], data[1], peer)
		"detonate":
			detonate(peer)
		"explode":
			explode(data[0], data[1], peer, false)


## Razzo o granata in volo.
class Projectile:
	extends Node3D

	var combat: Combat
	var kind := "rocket"
	var velocity := Vector3.ZERO
	var fuse := 3.0
	var peer := 1
	var exclude: Array[RID] = []
	var _life := 0.0

	func _ready() -> void:
		var m := Weapons.model("granata" if kind == "grenade" else "bazooka")
		if kind == "rocket":
			var body := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.05
			cyl.bottom_radius = 0.06
			cyl.height = 0.6
			body.mesh = cyl
			body.rotation.x = PI / 2
			add_child(body)
			var l := OmniLight3D.new()
			l.light_color = Color(1, 0.6, 0.2)
			l.light_energy = 2.0
			l.omni_range = 4.0
			add_child(l)
		elif m:
			add_child(m)

	func _physics_process(delta: float) -> void:
		_life += delta
		if kind == "grenade":
			velocity.y -= 16.0 * delta
		var from := global_position
		var to := from + velocity * delta
		var q := PhysicsRayQueryParameters3D.create(from, to, Combat.RAY_MASK)
		q.exclude = exclude
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			if kind == "rocket":
				combat.explode(hit["position"], "bazooka", peer, false)
				queue_free()
				return
			# La granata rimbalza e rotola.
			var n: Vector3 = hit["normal"]
			velocity = velocity.bounce(n) * 0.4
			global_position = hit["position"] + n * 0.05
		else:
			global_position = to
		if velocity.length() > 0.5:
			look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
		if kind == "grenade" and _life > fuse:
			combat.explode(global_position, "granata", peer, false)
			queue_free()
		elif _life > 8.0:
			queue_free()
