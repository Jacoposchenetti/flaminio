class_name Car
extends VehicleBody3D

## Auto guidabile (modelli Quaternius, CC0, da Poly Pizza). Davanti = +Z.
## Ferma (congelata) finché nessuno su questo PC la guida; in rete la guida chi ci è salito,
## gli altri ne ricevono la posizione con apply_net_state().

const MODELS := ["car_a", "car_c", "suv", "taxi", "sports_a", "sports_b", "police"]
const PAINTS := [
	Color(0.75, 0.75, 0.76), Color(0.08, 0.08, 0.09), Color(0.92, 0.92, 0.9), Color(0.55, 0.06, 0.06),
	Color(0.12, 0.2, 0.4), Color(0.3, 0.32, 0.34), Color(0.45, 0.5, 0.55), Color(0.16, 0.3, 0.2),
	Color(0.85, 0.85, 0.82), Color(0.6, 0.45, 0.25),
]
## Materiali che non sono la vernice della carrozzeria.
const NOT_PAINT := ["Windows", "Black", "Grey", "Headlights", "TailLights", "WhiteLights", "BlueLights", "Material.007", "DarkOrange"]
const ENGINE := 5200.0
const BRAKE := 60.0
const MAX_STEER := 0.55
const LAYER := 16

var car_id := -1
var model := ""
var driven_locally := false
var driver_peer := 0  # 0 = libera
var steer_input := 0.0
var seat := Transform3D()  # posizione del guidatore, in coordinate dell'auto

var _engine: AudioStreamPlayer3D
var _net_xf := Transform3D()
var _net_seen := false
var _settle := 0.0
var health := 220.0
var destroyed := false
var combat: Combat
var on_destroyed: Callable  # func(id): per avvisare gli altri PC
var moved := false  # spostata rispetto al parcheggio iniziale (da comunicare a chi entra dopo)


func setup(id: int, model_name: String, paint: Color) -> Car:
	car_id = id
	model = model_name
	add_to_group("damageable")
	name = "Auto_%d" % id
	mass = 1250.0
	collision_layer = LAYER
	collision_mask = 1 | 2 | LAYER
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.35, 0.1)
	angular_damp = 0.5
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	can_sleep = true

	var scene: Node3D = (load("res://assets/cars/%s.glb" % model_name) as PackedScene).instantiate()
	var paint_mat := StandardMaterial3D.new()
	paint_mat.albedo_color = paint
	paint_mat.metallic = 0.55
	paint_mat.roughness = 0.28
	paint_mat.clearcoat_enabled = true
	paint_mat.clearcoat = 0.8
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.03, 0.04, 0.05)
	glass.metallic = 0.2
	glass.roughness = 0.05
	var body_aabb := AABB()
	var wheels := []  # [mesh, aabb, tipo]
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		var aabb := mi.get_aabb()
		if n.contains("Wheel"):
			var kind := "back" if n.contains("Back") else ("left" if n.contains("Left") else "right")
			wheels.append([mi, aabb, kind])
			continue
		body_aabb = aabb if body_aabb.size == Vector3.ZERO else body_aabb.merge(aabb)
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			var mname := m.resource_name if m else ""
			if mname == "Windows":
				mi.set_surface_override_material(s, glass)
			elif not mname in NOT_PAINT and model_name != "taxi" and model_name != "police":
				mi.set_surface_override_material(s, paint_mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = 450.0
	add_child(scene)

	# Collisione: scatola della carrozzeria, sollevata da terra (sotto lavorano le sospensioni).
	var shape := BoxShape3D.new()
	var bottom := body_aabb.position.y + 0.15
	shape.size = Vector3(body_aabb.size.x * 0.95, body_aabb.end.y - bottom, body_aabb.size.z * 0.97)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(body_aabb.get_center().x, (bottom + body_aabb.end.y) * 0.5, body_aabb.get_center().z)
	add_child(cs)

	# Ruote: le mesh hanno l'origine nel centro dell'auto; le sposto sotto le ruote fisiche.
	var radius := 0.32
	var back_z := -1.3
	var front_z := 1.2
	var half_track := 0.75
	for w: Array in wheels:
		var a: AABB = w[1]
		if w[2] == "back":
			radius = a.size.y * 0.5
			back_z = a.get_center().z
			half_track = a.size.x * 0.5 - 0.05
		else:
			front_z = a.get_center().z
	var axle_y := radius
	var specs := [
		["AntSx", Vector3(half_track, axle_y, front_z), true],
		["AntDx", Vector3(-half_track, axle_y, front_z), true],
		["PostSx", Vector3(half_track, axle_y, back_z), false],
		["PostDx", Vector3(-half_track, axle_y, back_z), false],
	]
	var made := {}
	for sp: Array in specs:
		var wheel := VehicleWheel3D.new()
		wheel.name = sp[0]
		wheel.position = sp[1] + Vector3(0, 0.15, 0)
		wheel.wheel_radius = radius
		wheel.wheel_rest_length = 0.15
		wheel.suspension_travel = 0.2
		wheel.suspension_stiffness = 45.0
		wheel.suspension_max_force = 9000.0
		wheel.damping_compression = 1.8
		wheel.damping_relaxation = 2.4
		wheel.wheel_friction_slip = 3.2
		wheel.wheel_roll_influence = 0.15
		wheel.use_as_steering = sp[2]
		wheel.use_as_traction = not sp[2]
		add_child(wheel)
		made[sp[0]] = wheel
	for w: Array in wheels:
		var mi: MeshInstance3D = w[0]
		var a: AABB = w[1]
		var target: VehicleWheel3D = made["PostSx"] if w[2] == "back" else (made["AntSx"] if w[2] == "left" else made["AntDx"])
		var c := a.get_center()
		mi.owner = null
		mi.get_parent().remove_child(mi)
		target.add_child(mi)
		# Il mozzo della mesh coincide con l'origine della ruota fisica (che gira e sterza).
		# Le due ruote posteriori sono una sola mesh: la appendo alla sinistra, centrata sull'asse.
		mi.transform = Transform3D(Basis(), Vector3(-target.position.x if w[2] == "back" else -c.x, -c.y, -c.z))

	# Seduto: la testa resta circa 20 cm sotto il tetto (la persona seduta è alta ~1,3 m dal punto d'appoggio).
	seat = Transform3D(Basis(), Vector3(0.36, body_aabb.end.y - 1.5, body_aabb.get_center().z - 0.15))
	return self


## Il giocatore locale prende o lascia il volante.
func set_driven(on: bool) -> void:
	driven_locally = on
	_engine_on(on)
	moved = true
	if on:
		freeze = false
		sleeping = false
		_settle = 0.0
	else:
		engine_force = 0.0
		brake = BRAKE
		steering = 0.0
		_settle = 3.0  # lascia che si fermi, poi la congela


func drive(throttle: float, steer: float, handbrake: bool, delta: float) -> void:
	var fwd_speed := linear_velocity.dot(global_basis.z)
	var limit := MAX_STEER * clampf(1.0 - absf(fwd_speed) / 45.0, 0.35, 1.0)
	steer_input = steer
	steering = move_toward(steering, steer * limit, delta * 2.2)
	if throttle > 0.0:
		engine_force = ENGINE * throttle if fwd_speed > -1.0 else 0.0
		brake = 0.0 if fwd_speed > -1.0 else BRAKE
	elif throttle < 0.0:
		if fwd_speed > 1.0:
			engine_force = 0.0
			brake = BRAKE * -throttle
		else:
			engine_force = ENGINE * 0.6 * throttle  # retromarcia
			brake = 0.0
	else:
		engine_force = 0.0
		brake = 4.0
	if handbrake:
		brake = BRAKE * 1.5
		engine_force = 0.0
	# Limite di velocità (~130 km/h).
	if fwd_speed > 36.0:
		engine_force = 0.0


## Motore acceso: suono continuo che sale di tono con la velocità.
func _engine_on(on: bool) -> void:
	if on and _engine == null and not destroyed:
		_engine = Sfx.loop3d(self, "engine", -2.0, 90.0)
	elif not on and _engine:
		_engine.queue_free()
		_engine = null


func honk() -> void:
	Sfx.play3d("horn", global_position + Vector3(0, 1, 0), 0.0, 1.0, 150.0)


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func apply_net_state(xf: Transform3D, steer: float) -> void:
	_net_xf = xf
	steering = steer * MAX_STEER
	if _engine == null:
		_engine_on(true)
	if not _net_seen or global_position.distance_to(xf.origin) > 15.0:
		global_transform = xf
	_net_seen = true
	moved = true


## Relitti: un'auto esplosa sparisce dopo un minuto, una ribaltata (e lasciata lì) dopo 20 secondi, ma solo quando
## nessuno la sta guardando da vicino (camera a più di 40 m).
const WRECK_TIME := 60.0
const FLIPPED_TIME := 20.0
var _wreck_t := 0.0
var _flip_t := 0.0
var gone := false


func _cleanup(delta: float) -> void:
	if gone or driven_locally:
		return
	if destroyed:
		_wreck_t += delta
	elif global_basis.y.dot(Vector3.UP) < 0.35 and driver_peer == 0:
		_flip_t += delta
	else:
		_flip_t = 0.0
	if _wreck_t < WRECK_TIME and _flip_t < FLIPPED_TIME:
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(global_position) < 40.0:
		return
	_vanish()


## Toglie l'auto dal mondo (resta nell'elenco perché gli id in rete non cambino).
func _vanish() -> void:
	gone = true
	destroyed = true
	_engine_on(false)
	visible = false
	freeze = true
	collision_layer = 0
	collision_mask = 0
	remove_from_group("damageable")
	for c in get_children():
		if c is OmniLight3D:
			c.queue_free()


func _physics_process(delta: float) -> void:
	_cleanup(delta)
	if gone:
		return
	if _engine:
		_engine.pitch_scale = 0.55 + clampf(linear_velocity.length() / 22.0, 0.0, 1.6)
	if driven_locally:
		# Investire i pedoni li ferisce (in proporzione alla velocità).
		var v := linear_velocity.length()
		if v > 4.0:
			for p: Node in get_tree().get_nodes_in_group("pedestrian"):
				var n3 := p as Node3D
				if int(p.get_meta("safe_until", 0)) > Time.get_ticks_msec():
					continue
				if n3.global_position.distance_to(global_position) < 2.6 and p.has_method("take_damage"):
					p.take_damage(v * 5.0, combat.my_peer if combat else 0, global_position)
		return
	if _settle > 0.0:
		_settle -= delta
		if _settle <= 0.0 or (linear_velocity.length() < 0.2 and _settle < 2.5):
			_settle = 0.0
			freeze = true
		return
	if _net_seen and driver_peer != 0:
		var k := 1.0 - exp(-12.0 * delta)
		var xf := global_transform
		xf.origin = xf.origin.lerp(_net_xf.origin, k)
		xf.basis = Basis(xf.basis.get_rotation_quaternion().slerp(_net_xf.basis.get_rotation_quaternion(), k))
		global_transform = xf


func is_mine() -> bool:
	return true


func take_damage(amount: float, from_peer: int, _at: Vector3) -> void:
	if destroyed:
		return
	health -= amount
	if health <= 0.0:
		destroy(from_peer)


## L'auto prende fuoco ed esplode: resta il relitto annerito.
func destroy(by_peer := 0) -> void:
	if destroyed:
		return
	destroyed = true
	engine_force = 0.0
	_engine_on(false)
	if combat and by_peer == combat.my_peer:
		combat.crime.emit("car", global_position)
	if on_destroyed.is_valid():
		on_destroyed.call(car_id)
	var burnt := StandardMaterial3D.new()
	burnt.albedo_color = Color(0.06, 0.055, 0.05)
	burnt.roughness = 1.0
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mi.material_override = burnt
	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.45, 0.15)
	fire.light_energy = 3.0
	fire.omni_range = 8.0
	fire.position = Vector3(0, 1.2, 0)
	add_child(fire)
	var tw := fire.create_tween().set_loops(40)
	tw.tween_property(fire, "light_energy", 1.5, 0.15)
	tw.tween_property(fire, "light_energy", 3.5, 0.2)
	if combat:
		combat.explode(global_position + Vector3(0, 0.8, 0), "auto", by_peer, false)


## Spinta di un'esplosione vicina.
func blast(pos: Vector3, radius: float) -> void:
	if driver_peer != 0 and not driven_locally:
		return  # la guida un altro: la simula il suo PC
	var d := global_position - pos
	var k := clampf(1.0 - d.length() / radius, 0.0, 1.0)
	if k <= 0.0:
		return
	freeze = false
	sleeping = false
	apply_impulse(d.normalized() * mass * 9.0 * k + Vector3.UP * mass * 7.0 * k, Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-1, 1)))
	if not driven_locally:
		_settle = 5.0
	moved = true
