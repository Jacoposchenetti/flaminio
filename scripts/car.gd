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
## Derapata: con Shift (drift_input) il posteriore perde aderenza e l'auto si gira in curva tenendo il gas;
## lasciato Shift l'aderenza torna piano. Senza Shift un "controllo di stabilità" toglie le sbandate.
const GRIP_FRONT := 3.6
const GRIP_REAR := 4.2
const GRIP_DRIFT := 0.8
const LAT_MAX := 13.0
var wheelbase := 2.5
var body_box := AABB()  # ingombro della carrozzeria (portiera per il furto)
var paint_color := Color(0.75, 0.75, 0.76)
var drift_input := false
var drifting := false
var power := 1.0  # motore e freni (l'autobus pesa nove volte un'auto)
var top_speed := 36.0  # m/s (~130 km/h)
var can_drift := true
var _rear_grip := GRIP_REAR
var _drift_dir := 0.0  # verso della derapata in corso (+1 sinistra, -1 destra, 0 nessuna)
var _drift_t := 0.0
var _drift_speed := 0.0
var _steer_hold := 0.0  # 0..1: da quanto si tiene lo sterzo a fondo
## Aderenza e ribaltamento (m/s² di traverso): oltre grip_lat si scivola, oltre tip_lat ci si cappotta.
## SUV alti e autobus si ribaltano prima, le sportive basse quasi mai (scivolano).
var grip_lat := 13.5
var tip_lat := 12.0
var roll_risk := 0.0  # 0 tranquillo, >0 ruote interne che si sollevano
var _front_wheels: Array[VehicleWheel3D] = []
var _rear_wheels: Array[VehicleWheel3D] = []
var _skid: AudioStreamPlayer3D
var _lamp_at := Vector3(0.6, 0.7, 2.0)  # faro destro, in coordinate dell'auto (il sinistro è speculare)
var _beams: Array[SpotLight3D] = []


func setup(id: int, model_name: String, paint: Color) -> Car:
	car_id = id
	model = model_name
	add_to_group("damageable")
	name = "Auto_%d" % id
	mass = 1250.0
	collision_layer = LAYER
	collision_mask = 1 | 2 | LAYER
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.1, 0.1)  # basso: in curva non si ribalta
	angular_damp = 0.5
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	can_sleep = true
	if model_name.begins_with("bus"):
		_setup_bus(int(model_name.substr(3)))
		return self

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
	wheelbase = maxf(absf(front_z - back_z), 1.5)
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
		wheel.wheel_friction_slip = GRIP_FRONT if sp[2] else GRIP_REAR
		wheel.wheel_roll_influence = 0.02
		wheel.use_as_steering = sp[2]
		wheel.use_as_traction = not sp[2]
		add_child(wheel)
		if sp[2]:
			_front_wheels.append(wheel)
		else:
			_rear_wheels.append(wheel)
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
	body_box = body_aabb
	tip_lat = {"suv": 9.5, "sports_a": 16.0, "sports_b": 16.0}.get(model_name, 12.0)
	paint_color = paint if model_name != "taxi" and model_name != "police" else (Color(0.95, 0.8, 0.1) if model_name == "taxi" else Color(0.92, 0.92, 0.92))
	_lamp_at = Vector3(body_aabb.size.x * 0.33, body_aabb.position.y + body_aabb.size.y * 0.4, body_aabb.end.z - 0.1)
	return self


## Autobus ATAC guidabile (rubato dal traffico): stessa carrozzeria di Bus, fisica da 11 tonnellate, motore e freni
## in proporzione, niente derapate. Le ruote disegnate sono quelle della carrozzeria; quelle fisiche stanno sotto.
func _setup_bus(line: int) -> void:
	mass = 11000.0
	power = 7.5
	grip_lat = 7.0
	tip_lat = 5.5
	top_speed = 20.0  # ~72 km/h
	can_drift = false
	center_of_mass = Vector3(0, 0.9, 0)
	angular_damp = 1.2
	var vis := Bus.make(line)
	add_child(vis)
	for mi: MeshInstance3D in vis.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var size := Bus.SIZE
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y - 0.15, size.z)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.45 + (size.y - 0.15) * 0.5, 0)
	add_child(cs)
	var front_z := size.z * 0.5 - 2.3
	var back_z := -size.z * 0.5 + 3.0
	var half_track := size.x * 0.5 - 0.15
	wheelbase = front_z - back_z
	for sp: Array in [["AntSx", Vector3(half_track, 0.5, front_z), true], ["AntDx", Vector3(-half_track, 0.5, front_z), true],
			["PostSx", Vector3(half_track, 0.5, back_z), false], ["PostDx", Vector3(-half_track, 0.5, back_z), false]]:
		var wheel := VehicleWheel3D.new()
		wheel.name = sp[0]
		wheel.position = sp[1] + Vector3(0, 0.15, 0)
		wheel.wheel_radius = 0.5
		wheel.wheel_rest_length = 0.15
		wheel.suspension_travel = 0.2
		wheel.suspension_stiffness = 60.0
		wheel.suspension_max_force = 90000.0
		wheel.damping_compression = 3.0
		wheel.damping_relaxation = 4.0
		wheel.wheel_friction_slip = GRIP_FRONT if sp[2] else GRIP_REAR
		wheel.wheel_roll_influence = 0.05
		wheel.use_as_steering = sp[2]
		wheel.use_as_traction = not sp[2]
		add_child(wheel)
		if sp[2]:
			_front_wheels.append(wheel)
		else:
			_rear_wheels.append(wheel)
	seat = Transform3D(Basis(), Vector3(0.75, 1.15, size.z * 0.5 - 1.5))
	_lamp_at = Vector3(0.85, 1.05, size.z * 0.5)
	body_box = AABB(Vector3(-size.x * 0.5, 0.3, -size.z * 0.5), Vector3(size.x, size.y, size.z))


## Fari: accesi di notte quando qualcuno guida (solo le auto guidate, per non avere centinaia di luci).
func _update_beams() -> void:
	var on := not destroyed and (driven_locally or driver_peer != 0) and DayNight.current != null and DayNight.current.is_night()
	if on and _beams.is_empty():
		for side: float in [1.0, -1.0]:
			var l := SpotLight3D.new()
			l.light_color = Color(1.0, 0.95, 0.85)
			l.light_energy = 6.0
			l.spot_range = 38.0
			l.spot_angle = 28.0
			l.spot_attenuation = 0.8
			l.shadow_enabled = side > 0.0
			l.position = Vector3(_lamp_at.x * side, _lamp_at.y, _lamp_at.z)
			l.rotation = Vector3(-0.08, PI, 0.0)  # le spot guardano verso -Z: le giro in avanti, un po' in basso
			add_child(l)
			_beams.append(l)
	for l in _beams:
		l.visible = on


## Il giocatore locale prende o lascia il volante.
func set_driven(on: bool) -> void:
	driven_locally = on
	if not on:
		drift_input = false
		if _skid:
			_skid.queue_free()
			_skid = null
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
	# Sterzo: un colpo veloce resta entro una curva "sicura" (LAT_MAX m/s² di traverso); tenendolo a fondo l'angolo
	# continua a crescere fino a tutto sterzo: la sterzata brusca, che in velocità fa scivolare o ribaltare.
	var v2 := maxf(fwd_speed * fwd_speed, 1.0)
	_steer_hold = move_toward(_steer_hold, 1.0 if absf(steer) > 0.7 else 0.0, delta * (1.1 if absf(steer) > 0.7 else 3.0))
	var limit := minf(MAX_STEER, atan(LAT_MAX * wheelbase / v2) * (1.0 + 2.5 * _steer_hold))
	steer_input = steer
	steering = move_toward(steering, steer * limit, delta * 2.2)
	if throttle > 0.0:
		engine_force = ENGINE * power * throttle if fwd_speed > -1.0 else 0.0
		brake = 0.0 if fwd_speed > -1.0 else BRAKE * power
	elif throttle < 0.0:
		if fwd_speed > 1.0:
			engine_force = 0.0
			brake = BRAKE * power * -throttle
		else:
			engine_force = ENGINE * power * 0.6 * throttle  # retromarcia
			brake = 0.0
	else:
		engine_force = 0.0
		brake = 4.0
	if handbrake:
		brake = BRAKE * power * 1.5
		engine_force = 0.0
	# Limite di velocità (~130 km/h; l'autobus meno).
	if fwd_speed > top_speed:
		engine_force = 0.0
	_handling(throttle, steer, fwd_speed, delta)


## Guida "arcade": rotazione e scivolamento di traverso li decide il gioco, non l'attrito delle gomme, così l'auto
## resta incollata all'asfalto e non si ribalta in curva.
## - Normale: gira come una bicicletta (velocità / passo × tangente dello sterzo) e la velocità segue il muso.
## - Derapata (Shift, alla Mario Kart): si entra nel verso in cui si sterza e ci si resta finché si tiene Shift;
##   il muso punta dentro la curva, l'auto scivola di traverso senza perdere velocità, lo sterzo stringe o allarga.
##   Più dura, più forte la spinta quando si lascia Shift (mini-turbo).
func _handling(throttle: float, steer: float, fwd_speed: float, delta: float) -> void:
	var grounded := false
	for w: VehicleWheel3D in _front_wheels + _rear_wheels:
		if w.is_in_contact():
			grounded = true
	var up := global_basis.y
	var fwd := global_basis.z
	var side := global_basis.x
	var lat := linear_velocity.dot(side)
	if not grounded:
		_drift_dir = 0.0
		drifting = false
		_update_skid(0.0)
		return
	var speed := absf(fwd_speed)
	# Entrata e uscita dalla derapata.
	if can_drift and drift_input and fwd_speed > (2.5 if _drift_dir != 0.0 else 4.2):
		if _drift_dir == 0.0 and absf(steer) > 0.2:
			_drift_dir = signf(steer)
			_drift_t = 0.0
			_drift_speed = speed
	elif _drift_dir != 0.0:
		# Mini-turbo: spinta in avanti proporzionale alla durata della derapata (piena dopo ~2 s).
		var boost := clampf(_drift_t / 2.0, 0.0, 1.0) * 7.0 if _drift_t > 0.6 else 0.0
		apply_central_impulse(fwd * boost * mass)
		_drift_dir = 0.0
	drifting = _drift_dir != 0.0
	# In derapata le gomme mollano (soprattutto dietro); finita la derapata l'aderenza torna man mano che l'auto
	# smette di scivolare di traverso (se tornasse di colpo, le gomme "inciamperebbero" e l'auto si ribalterebbe).
	var slide := clampf((absf(lat) - 1.0) / 5.0, 0.0, 1.0)
	var grip_goal := GRIP_DRIFT if drifting else lerpf(GRIP_REAR, GRIP_DRIFT, slide)
	_rear_grip = move_toward(_rear_grip, grip_goal, delta * (14.0 if grip_goal < _rear_grip else 4.0))
	for w in _rear_wheels:
		w.wheel_friction_slip = _rear_grip
	for w in _front_wheels:
		w.wheel_friction_slip = lerpf(GRIP_FRONT, 2.0, (GRIP_REAR - _rear_grip) / (GRIP_REAR - GRIP_DRIFT))
	var yaw_rate: float
	var target_lat := 0.0
	var grip := 9.0  # quanto in fretta la velocità di traverso va dove deve
	if drifting:
		_drift_t += delta
		# Sterzo nello stesso verso: curva stretta; nel verso opposto: curva larga (mai controsterzo).
		var tight := 0.5 + 0.5 * clampf(steer * _drift_dir, -1.0, 1.0)  # 0 larga, 1 stretta
		yaw_rate = _drift_dir * lerpf(0.7, 1.6, tight) * clampf(_drift_speed / 9.0, 0.4, 1.0)
		# La velocità d'ingresso si conserva (cala piano solo senza gas o col freno): chi derapa esce dalla
		# curva veloce com'era entrato. La direzione gira con l'auto, il retro scivola fuori (~15-25°).
		_drift_speed = move_toward(_drift_speed, 0.0, delta * (6.0 if throttle < 0.0 else (1.5 if throttle == 0.0 else 0.3)))
		var s_lat := -_drift_dir * _drift_speed * lerpf(0.26, 0.42, tight)
		var s_fwd := sqrt(maxf(_drift_speed * _drift_speed - s_lat * s_lat, 0.0))
		var want_v := fwd * s_fwd + side * s_lat
		var have_v := linear_velocity - up * linear_velocity.dot(up)
		apply_central_impulse((want_v - have_v) * mass * (1.0 - exp(-7.0 * delta)))
		target_lat = s_lat
		grip = 0.0  # già fatto qui sopra
		engine_force = 0.0
		brake = 0.0
	else:
		yaw_rate = fwd_speed / wheelbase * tan(steering)
		# Le gomme tengono fino a grip_lat m/s² di traverso: oltre, la rotazione si ferma lì e il muso "scappa"
		# (l'auto scivola verso l'esterno, tanto più quanto più si chiede).
		var cap := grip_lat / maxf(speed, 1.0)
		var over := absf(yaw_rate) / cap if speed > 3.0 else 0.0
		yaw_rate = clampf(yaw_rate, -cap, cap)
		if over > 1.0:
			grip = 9.0 / (over * over)
		grip = minf(grip, lerpf(9.0, 2.5, slide))  # uscendo da una scivolata il retro rientra con gradualità
	# Velocità: in avanti quella che c'è, di traverso verso il bersaglio, in verticale libera (salti, buche).
	# (Impulsi, non linear_velocity = …: assegnare la velocità a un VehicleBody annulla la spinta del motore.)
	var vl := lerpf(lat, target_lat, 1.0 - exp(-grip * delta)) if grip > 0.0 else lat
	if grip > 0.0:
		apply_central_impulse(side * (vl - lat) * mass)
	# Cappottamento: la forza di traverso (velocità × rotazione; in derapata le gomme che scivolano ne trasmettono
	# meno) oltre la soglia del mezzo solleva le ruote interne; più si esagera, più spinge. Sopra i ~45° di
	# inclinazione il raddrizzamento si arrende e l'auto si ribalta davvero.
	# La soglia cala con la velocità: in città a tutto sterzo ci si inclina e si scivola, in velocità ci si ribalta.
	var a_lat := speed * absf(angular_velocity.y) * (0.45 if drifting else 1.0)
	var tip := tip_lat * clampf(1.2 - speed / 75.0, 0.72, 1.1)
	roll_risk = clampf((a_lat - tip) / (tip * 0.4), 0.0, 1.5)
	var lean := rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))
	var stab := (1.0 - clampf((roll_risk - 0.25) / 0.75, 0.0, 1.0)) * (0.0 if lean > 45.0 else 1.0)
	if roll_risk > 0.0:
		apply_torque(fwd * signf(angular_velocity.y) * mass * 60.0 * roll_risk * roll_risk)
	# Rotazione: imbardata decisa qui, rollio e beccheggio smorzati e un raddrizzamento che tiene le ruote giù.
	var av := global_basis.inverse() * angular_velocity
	av.y = lerpf(av.y, yaw_rate, 1.0 - exp(-10.0 * delta * (0.3 + 0.7 * stab)))
	av.z *= exp(-8.0 * delta * stab)  # rollio
	av.x *= exp(-3.0 * delta * stab)  # beccheggio (salite e dossi restano)
	angular_velocity = global_basis * av
	var tilt := up.cross(Vector3.UP)
	if tilt.length() > 0.02 and stab > 0.0:
		apply_torque(tilt * mass * 25.0 * stab)
	_update_skid(absf(vl) if drifting else absf(lat))


## Stridio delle gomme quando si scivola di traverso.
func _update_skid(lat: float) -> void:
	var on := lat > 3.0 and linear_velocity.length() > 5.0
	if on and _skid == null:
		_skid = Sfx.loop3d(self, "skid", -6.0, 70.0)
	elif not on and _skid:
		_skid.queue_free()
		_skid = null
	if _skid:
		_skid.volume_db = linear_to_db(clampf((lat - 3.0) / 6.0, 0.15, 1.0)) - 4.0


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
	if driven_locally or driver_peer != 0 or not _beams.is_empty():
		_update_beams()
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
