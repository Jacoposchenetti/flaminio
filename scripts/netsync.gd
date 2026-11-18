class_name NetSync
extends Node3D

## Mondo condiviso in rete: pedoni, traffico, polizia e soldi a terra li calcola chi ospita; 10 volte al secondo
## manda a ogni altro giocatore lo stato di quelli che ha vicino (entro RADIUS metri). Sugli altri PC qui nascono
## delle "copie" che si muovono, si animano e muoiono uguali. I colpi sulle copie vengono girati a chi ospita.
##
## Le stelle viaggiano in un messaggio a parte (gli id dei giocatori sono troppo grandi per i float).
## Lo stato degli oggetti va in pezzi da PER_PART oggetti (sotto la dimensione massima di un pacchetto UDP),
## 9 numeri per oggetto: id, tipo, aspetto, x, y, z, direzione, animazione, segnali.

const RADIUS := 380.0
const FIELDS := 9
const PER_PART := 30
enum Kind { PERSON, COP, CAR, POLICE_CAR, CASH, AMMO }
const ANIMS := ["idle", "stroll", "walk", "sprint", "talk", "crouch", "aim", "shoot", "death", "hit", "crouch_walk", "jump", "fall"]

var world: Node  # main.gd
var police_active := true
var wanted := {}  # peer -> [stelle, calma] (sui PC che ricevono)
var _puppets := {}  # id -> nodo
var _last_seen := {}  # id -> numero del giro in cui è arrivato l'ultima volta
static var LOOKS: Array = []


static func looks() -> Array:
	if LOOKS.is_empty():
		LOOKS = Human.PRESETS.keys() + Human.UNIFORMS.keys()
	return LOOKS


# --- Chi ospita: costruzione del pacchetto --------------------------------------------------------


## Restituisce i pezzi (PackedFloat32Array) con gli oggetti vicini a center.
func build_for(center: Vector3, peds: Pedestrians, traffic: Traffic, police: Police) -> Array:
	var out := PackedFloat32Array()
	var add := func(n: Node3D, nid: int, kind: int, look: int, yaw: float, anim: String, flags: int) -> void:
		var p := n.global_position
		if p.distance_to(center) > RADIUS:
			return
		out.append_array([float(nid), float(kind), float(look), p.x, p.y, p.z, yaw, float(maxi(ANIMS.find(anim), 0)), float(flags)])
	for n: Node in peds.get_children():
		if n is Pedestrians.Pedestrian:
			var ped := n as Pedestrians.Pedestrian
			var pf := (1 if ped.dead else 0) | (4 if ped.has_meta("clerk") else 0) | (8 if ped.has_meta("dealer") else 0)  # 4 commesso, 8 fornitore
			add.call(ped, ped.nid, Kind.PERSON, looks().find(ped.preset), ped.rotation.y + ped.human().rotation.y, ped.net_anim, pf)
	for c: Array in peds.cash:
		if is_instance_valid(c[0]):
			var is_ammo: bool = c.size() > 3 and String(c[3]) != ""
			add.call(c[0], int(c[2]), Kind.AMMO if is_ammo else Kind.CASH, 0, 0.0, "idle", 0)
	for n: Node in traffic.get_children():
		if n is Traffic.TrafficCar:
			var tc := n as Traffic.TrafficCar
			add.call(tc, tc.nid, Kind.CAR, tc.look, tc.global_rotation.y, "idle", 1 if tc.destroyed else 0)
	for n: Node in police.get_children():
		if n is Police.Cop:
			var cop := n as Police.Cop
			var f := (1 if cop.dead else 0) | (2 if cop.weapon == "mitragliatrice" else 0)
			add.call(cop, cop.nid, Kind.COP, looks().find(cop.preset), cop.rotation.y + cop.human().rotation.y, cop.net_anim, f)
		elif n is Police.PoliceCar:
			var pc := n as Police.PoliceCar
			add.call(pc, pc.nid, Kind.POLICE_CAR, 1 if pc.carabinieri else 0, pc.global_rotation.y, "idle", 1 if pc.destroyed else 0)
	var parts := []
	var step := PER_PART * FIELDS
	for i in range(0, maxi(out.size(), 1), step):
		parts.append(out.slice(i, mini(i + step, out.size())))
	return parts


## Stelle e stato della polizia (dal messaggio a parte).
func apply_wanted(active: bool, w: Dictionary) -> void:
	police_active = active
	wanted = w


# --- Chi riceve: copie ----------------------------------------------------------------------------


## Un pezzo dello stato del giro "frame". Gli oggetti spariscono se non arrivano per qualche giro.
func apply(frame: int, data: PackedFloat32Array) -> void:
	var i := 0
	while i + FIELDS <= data.size():
		var nid := int(data[i])
		var kind := int(data[i + 1])
		var look := int(data[i + 2])
		var pos := Vector3(data[i + 3], data[i + 4], data[i + 5])
		var yaw := data[i + 6]
		var anim: String = ANIMS[clampi(int(data[i + 7]), 0, ANIMS.size() - 1)]
		var flags := int(data[i + 8])
		i += FIELDS
		_last_seen[nid] = frame
		var node: Node = _puppets.get(nid)
		if node == null or not is_instance_valid(node):
			node = _create(nid, kind, look, flags)
			node.global_position = pos
			_puppets[nid] = node
		node.call("net_update", pos, yaw, anim, flags)
	for nid: int in _puppets.keys():
		if frame - int(_last_seen.get(nid, frame)) > 4:
			var n: Node = _puppets[nid]
			if is_instance_valid(n):
				n.queue_free()
			_puppets.erase(nid)
			_last_seen.erase(nid)


func clear_puppets() -> void:
	for nid: int in _puppets:
		if is_instance_valid(_puppets[nid]):
			_puppets[nid].queue_free()
	_puppets.clear()
	wanted.clear()


func police_dots() -> Array:
	var out := []
	for nid: int in _puppets:
		var n: Node = _puppets[nid]
		if is_instance_valid(n) and n.get_meta("police", false) and not n.get_meta("dead", false):
			out.append((n as Node3D).global_position)
	return out


func _create(nid: int, kind: int, look: int, flags: int) -> Node:
	match kind:
		Kind.PERSON, Kind.COP:
			var p := PersonPuppet.new()
			p.sync = self
			p.nid = nid
			p.preset = looks()[clampi(look, 0, looks().size() - 1)]
			p.gun = ("mitragliatrice" if flags & 2 else "pistola") if kind == Kind.COP else ""
			p.set_meta("police", kind == Kind.COP)
			add_child(p)
			return p
		Kind.CAR, Kind.POLICE_CAR:
			var v := VehiclePuppet.new()
			v.sync = self
			v.nid = nid
			v.police = kind == Kind.POLICE_CAR
			v.look = look
			v.set_meta("police", kind == Kind.POLICE_CAR)
			add_child(v)
			return v
		_:
			var c := CashPuppet.new()
			c.ammo = kind == Kind.AMMO
			add_child(c)
			return c


func forward_hit(nid: int, amount: float, at: Vector3) -> void:
	world.forward_hit(nid, amount, at)


## Persona (pedone o agente) su un PC che non la calcola.
class PersonPuppet:
	extends CharacterBody3D

	var sync: NetSync
	var nid := 0
	var preset := "m1"
	var gun := ""
	var _human: Human
	var _gun_node: Node3D
	var _target := Vector3.ZERO
	var _yaw := 0.0
	var _dead := false

	func _ready() -> void:
		add_to_group("damageable")
		add_to_group("pedestrian")
		collision_layer = 32
		collision_mask = 0
		var shape := CapsuleShape3D.new()
		shape.radius = 0.3
		shape.height = 1.7
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 0.85
		add_child(cs)
		_human = Human.new().setup(preset)
		add_child(_human)
		if gun != "":
			_gun_node = Weapons.model(gun)
			if _gun_node:
				add_child(_gun_node)
				_gun_node.top_level = true

	## I danni delle esplosioni li calcola chi ospita: qui contano solo i colpi diretti (girati a lui).
	func is_mine() -> bool:
		return false

	func take_damage(amount: float, _from_peer: int, at: Vector3) -> void:
		if not _dead:
			sync.forward_hit(nid, amount, at)

	func net_update(pos: Vector3, yaw: float, anim: String, flags: int) -> void:
		_target = pos
		_yaw = yaw
		if flags & 4:
			set_meta("clerk", true)
		if flags & 8:
			set_meta("dealer", true)
		var dead := flags & 1 == 1
		if dead and not _dead:
			_dead = true
			set_meta("dead", true)
			collision_layer = 0
			_human.play_once("death")
			if _gun_node:
				_gun_node.queue_free()
				_gun_node = null
		elif not dead:
			if anim == "shoot" or anim == "hit":
				_human.play_once(anim, 0.02)
			else:
				_human.play(anim)

	func _process(delta: float) -> void:
		var k := 1.0 - exp(-10.0 * delta)
		global_position = _target if global_position.distance_to(_target) > 15.0 else global_position.lerp(_target, k)
		_human.rotation.y = lerp_angle(_human.rotation.y, _yaw, k)
		if _gun_node:
			_gun_node.global_transform = Transform3D(Basis(Vector3.UP, _human.rotation.y), _human.hand_position())


## Auto del traffico o volante su un PC che non la calcola.
class VehiclePuppet:
	extends AnimatableBody3D

	var sync: NetSync
	var nid := 0
	var police := false
	var look := 0
	var _target := Vector3.ZERO
	var _yaw := 0.0
	var _destroyed := false
	var _engine: AudioStreamPlayer3D
	var _siren: AudioStreamPlayer3D
	var _lights: Array[OmniLight3D] = []
	var _t := 0.0
	var _last := Vector3.ZERO

	func _ready() -> void:
		add_to_group("damageable")
		collision_layer = 16
		if look >= Bus.LOOK and not police:
			# Autobus ATAC.
			add_child(Bus.make(look - Bus.LOOK))
			_engine = Sfx.loop3d(self, "engine", -10.0, 60.0)
			var bshape := BoxShape3D.new()
			bshape.size = Bus.SIZE
			var bcs := CollisionShape3D.new()
			bcs.shape = bshape
			bcs.position.y = Bus.SIZE.y * 0.5 + 0.3
			add_child(bcs)
			return
		var model := "police" if police else String(Car.MODELS[(look % 16) % Car.MODELS.size()])
		var scene: Node3D = (load("res://assets/cars/%s.glb" % model) as PackedScene).instantiate()
		if police:
			Police.paint_car(scene, look == 1)
			_lights = Police.PoliceCar.make_lights(self)
			_siren = Sfx.loop3d(self, "siren", 2.0, 260.0)
		else:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Car.PAINTS[(look / 16) % Car.PAINTS.size()]
			mat.metallic = 0.55
			mat.roughness = 0.3
			for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
				for s in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(s)
					var nm := m.resource_name if m else ""
					if not nm in Car.NOT_PAINT and model != "taxi":
						mi.set_surface_override_material(s, mat)
		add_child(scene)
		_engine = Sfx.loop3d(self, "engine", -14.0, 50.0)
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.8, 1.2, 4.2)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 0.7
		add_child(cs)

	func is_mine() -> bool:
		return false

	func take_damage(amount: float, _from_peer: int, at: Vector3) -> void:
		if not _destroyed:
			sync.forward_hit(nid, amount, at)

	func net_update(pos: Vector3, yaw: float, _anim: String, flags: int) -> void:
		_target = pos
		_yaw = yaw
		if flags & 1 == 1 and not _destroyed:
			_destroyed = true
			for n: Node in [_engine, _siren]:
				if n:
					n.queue_free()
			for l in _lights:
				l.queue_free()
			_lights.clear()
			var burnt := StandardMaterial3D.new()
			burnt.albedo_color = Color(0.06, 0.055, 0.05)
			for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
				mi.material_override = burnt

	func _process(delta: float) -> void:
		_t += delta
		Police.PoliceCar.blink(_lights, _t)
		var k := 1.0 - exp(-10.0 * delta)
		var p := _target if global_position.distance_to(_target) > 20.0 else global_position.lerp(_target, k)
		var q := Basis(Vector3.UP, _yaw).get_rotation_quaternion()
		global_transform = Transform3D(Basis(global_basis.get_rotation_quaternion().slerp(q, k)), p)
		if _engine and delta > 0.0:
			_engine.pitch_scale = 0.5 + clampf(p.distance_to(_last) / delta / 18.0, 0.0, 1.5)
		_last = p


## Soldi a terra su un PC che non li calcola (li assegna chi ospita).
class CashPuppet:
	extends Node3D

	var _target := Vector3.ZERO
	var ammo := false  # scatola di munizioni invece di soldi

	func _ready() -> void:
		var n := Pedestrians.ammo_node(self) if ammo else Pedestrians.cash_node(self)
		n.position = Vector3.ZERO

	func net_update(pos: Vector3, _yaw: float, _anim: String, _flags: int) -> void:
		_target = pos
		global_position = pos

	func _process(_delta: float) -> void:
		rotate_y(0.05)
