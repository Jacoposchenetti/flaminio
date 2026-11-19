class_name Heli
extends Car

## Vita dell'elicottero: scende coi colpi ed esplode a zero; dopo qualche secondo senza danni si rigenera.
const MAX_HEALTH := 900.0
const REGEN_DELAY := 6.0
const REGEN_RATE := 18.0  # punti al secondo
var _since_hit := 99.0

## Elicottero pilotabile (modello costruito qui, a pezzi semplici). È un'auto per tutto il resto del gioco:
## ci si sale con F, in rete lo guida chi ci è salito e gli altri ne ricevono la posizione, si può distruggere.
##
## Comandi: W/S avanti e indietro (si inclina), A/D gira, Spazio sale, Ctrl scende, Shift più veloce.
## Joypad: levetta sinistra avanti/gira, RT sale, LT scende. Si mira con la camera: clic sinistro (LB) la
## mitragliatrice, clic destro (o R / X) i razzi. Il rotore deve prendere giri prima di staccarsi da terra.

const PADS: Array[Vector2] = [Vector2(117, -998), Vector2(-382, -378)]  # piazzole all aperto (prati e campi piani, alberi tolti)
const BASE_ID := 2000000  # id in rete degli elicotteri: BASE_ID + numero della piazzola
const MAX_SPEED := 38.0
const BOOST_SPEED := 58.0
const CLIMB := 9.0
const YAW_RATE := 1.5
const SPOOL := 0.35  # giri del rotore guadagnati al secondo (0 -> 1 in ~3 s)

var police_look := false
var pad := Vector3.ZERO
var rpm := 0.0  # 0 fermo, 1 a regime
var _rotor: Node3D
var _tail: Node3D
var _disc: MeshInstance3D
var _heading := 0.0
var _in_fwd := 0.0
var _in_yaw := 0.0
var _in_lift := 0.0
var _in_boost := false
var _gun_cd := 0.0
var _rocket_cd := 0.0
var _rocket_side := 1.0
var _prev_v := Vector3.ZERO
var _respawn_t := 0.0


func setup_heli(id: int, at: Vector3, yaw: float, police_style := false) -> Heli:
	car_id = id
	model = "heli"
	police_look = police_style
	pad = at
	health = MAX_HEALTH
	add_to_group("damageable")
	name = "Elicottero_%d" % id
	mass = 1800.0
	collision_layer = LAYER
	collision_mask = 1 | 2 | LAYER
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 1.0, 0.2)
	angular_damp = 2.0
	linear_damp = 0.3
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	can_sleep = true
	var parts := Heli.make_model(police_style)
	add_child(parts[0])
	_rotor = parts[1]
	_tail = parts[2]
	_disc = parts[3]
	for box: Array in [[Vector3(1.9, 1.5, 3.8), Vector3(0, 1.25, 0.3)], [Vector3(2.0, 0.3, 3.0), Vector3(0, 0.15, 0.2)],
			[Vector3(0.5, 0.6, 4.2), Vector3(0, 1.55, -2.9)]]:
		var shape := BoxShape3D.new()
		shape.size = box[0]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = box[1]
		add_child(cs)
	seat = Transform3D(Basis(), Vector3(0.38, 0.45, 0.85))
	_lamp_at = Vector3(0.0, 0.55, 1.9)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	_heading = yaw
	return self


## Modello: [radice, rotore principale, rotore di coda, disco del rotore in movimento]. Davanti = +Z.
static func make_model(police_style: bool) -> Array:
	var root := Node3D.new()
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.1, 0.2, 0.48) if police_style else Color(0.72, 0.1, 0.08)
	paint.metallic = 0.45
	paint.roughness = 0.3
	paint.clearcoat_enabled = true
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.9)
	white.roughness = 0.35
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	dark.metallic = 0.6
	dark.roughness = 0.4
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.08, 0.1, 0.75)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.3
	glass.roughness = 0.05
	var add := func(mesh: Mesh, mat: Material, xf: Transform3D, parent: Node3D) -> MeshInstance3D:
		(mesh as PrimitiveMesh).material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = xf
		parent.add_child(mi)
		return mi
	var body := SphereMesh.new()
	body.radius = 1.0
	body.height = 2.0
	add.call(body, paint, Transform3D(Basis().scaled(Vector3(1.0, 0.82, 1.85)), Vector3(0, 1.3, 0.25)), root)
	var belly := SphereMesh.new()
	belly.radius = 1.0
	belly.height = 2.0
	add.call(belly, white, Transform3D(Basis().scaled(Vector3(0.96, 0.5, 1.7)), Vector3(0, 0.95, 0.25)), root)
	var canopy := SphereMesh.new()
	canopy.radius = 1.0
	canopy.height = 2.0
	add.call(canopy, glass, Transform3D(Basis().scaled(Vector3(0.88, 0.62, 0.9)), Vector3(0, 1.48, 1.15)), root)
	var boom := CylinderMesh.new()
	boom.top_radius = 0.13
	boom.bottom_radius = 0.32
	boom.height = 4.4
	add.call(boom, paint, Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 1.55, -2.7)), root)
	var fin := BoxMesh.new()
	fin.size = Vector3(0.08, 1.1, 0.7)
	add.call(fin, paint, Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 2.0, -4.75)), root)
	var stab := BoxMesh.new()
	stab.size = Vector3(1.4, 0.06, 0.4)
	add.call(stab, white, Transform3D(Basis(), Vector3(0, 1.6, -4.2)), root)
	for side: float in [1.0, -1.0]:
		var skid := CylinderMesh.new()
		skid.top_radius = 0.05
		skid.bottom_radius = 0.05
		skid.height = 3.4
		add.call(skid, dark, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0.9 * side, 0.07, 0.25)), root)
		for zs: float in [-0.6, 1.0]:
			var strut := BoxMesh.new()
			strut.size = Vector3(0.06, 0.7, 0.08)
			add.call(strut, dark, Transform3D(Basis(Vector3.FORWARD, -0.35 * side), Vector3(0.75 * side, 0.4, zs)), root)
	var mast := CylinderMesh.new()
	mast.top_radius = 0.08
	mast.bottom_radius = 0.16
	mast.height = 0.55
	add.call(mast, dark, Transform3D(Basis(), Vector3(0, 2.25, 0.1)), root)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 2.52, 0.1)
	root.add_child(rotor)
	for k in 4:
		var blade := BoxMesh.new()
		blade.size = Vector3(0.26, 0.04, 4.9)
		add.call(blade, dark, Transform3D(Basis(Vector3.UP, k * PI / 2), Basis(Vector3.UP, k * PI / 2) * Vector3(0, 0, 2.45)), rotor)
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 4.9
	disc_mesh.bottom_radius = 4.9
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 32
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.05, 0.05, 0.06, 0.16)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disc: MeshInstance3D = add.call(disc_mesh, disc_mat, Transform3D(Basis(), Vector3(0, 2.52, 0.1)), root)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.visible = false
	var tail := Node3D.new()
	tail.position = Vector3(0.14, 2.0, -4.75)
	root.add_child(tail)
	for k in 2:
		var tb := BoxMesh.new()
		tb.size = Vector3(0.03, 1.2, 0.12)
		add.call(tb, dark, Transform3D(Basis(Vector3.RIGHT, k * PI / 2), Vector3.ZERO), tail)
	# Luci di posizione e scritta.
	for l: Array in [[Color(1, 0.1, 0.1), Vector3(-0.75, 1.0, 0.6)], [Color(0.1, 1, 0.2), Vector3(0.75, 1.0, 0.6)]]:
		var bulb := SphereMesh.new()
		bulb.radius = 0.06
		bulb.height = 0.12
		var m := StandardMaterial3D.new()
		m.albedo_color = l[0]
		m.emission_enabled = true
		m.emission = l[0]
		m.emission_energy_multiplier = 3.0
		add.call(bulb, m, Transform3D(Basis(), l[1]), root)
	for side: float in [1.0, -1.0]:
		var tag := Label3D.new()
		tag.text = "POLIZIA" if police_style else "I-ROMA"
		tag.font_size = 64
		tag.pixel_size = 0.006
		tag.outline_size = 0
		tag.modulate = Color(1, 1, 1) if police_style else Color(0.95, 0.95, 0.9)
		tag.position = Vector3(0.97 * side, 1.35, -0.4)
		tag.rotation.y = PI / 2 * side
		root.add_child(tag)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi != disc:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.visibility_range_end = 900.0
	return [root, rotor, tail, disc]


## Fa girare i rotori: le pale ben visibili da ferme, sfocate in un disco a regime.
static func spin(rotor: Node3D, tail: Node3D, disc: MeshInstance3D, rpm_k: float, delta: float) -> void:
	if rotor:
		rotor.rotate_y(rpm_k * 42.0 * delta)
	if tail:
		tail.rotate_x(rpm_k * 70.0 * delta)
	if disc:
		disc.visible = rpm_k > 0.55


func _engine_on(on: bool) -> void:
	if on and _engine == null and not destroyed:
		_engine = Sfx.loop3d(self, "rotor", 4.0, 420.0)
	elif not on and _engine:
		_engine.queue_free()
		_engine = null


func set_driven(on: bool) -> void:
	super.set_driven(on)
	can_sleep = not on
	if on:
		_heading = global_rotation.y
		gravity_scale = 1.0
	else:
		_settle = 40.0 if global_position.y > city_ground() + 1.5 else 4.0  # in volo cade finché non tocca terra


func city_ground() -> float:
	return pad.y if pad != Vector3.ZERO else 0.0


## Per Player: legge i comandi di volo (Car.drive riceve solo acceleratore e sterzo).
func drive(throttle: float, steer: float, _handbrake: bool, _delta: float) -> void:
	_in_fwd = throttle
	_in_yaw = steer
	var blocked := get_viewport().gui_get_focus_owner() is LineEdit
	_in_lift = 0.0 if blocked else (
		(1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
		+ Input.get_action_strength("accelerate") - Input.get_action_strength("brake"))
	# Col joypad RT/LT servono per salire e scendere: l'acceleratore viene solo dalla levetta.
	_in_fwd = clampf(Input.get_axis("move_back", "move_forward"), -1.0, 1.0) if not blocked else 0.0
	_in_boost = not blocked and Input.is_action_pressed("sprint")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# La carcassa si ripara da sola se per un po' nessuno la colpisce.
	_since_hit += delta
	if not destroyed and _since_hit > REGEN_DELAY and health < MAX_HEALTH:
		health = minf(MAX_HEALTH, health + REGEN_RATE * delta)
	if gone:
		return
	var engine_running := (driven_locally or driver_peer != 0) and not destroyed
	rpm = move_toward(rpm, 1.0 if engine_running else 0.0, delta * (SPOOL if engine_running else 0.2))
	if _engine:
		_engine.pitch_scale = 0.6 + rpm * 0.55 + clampf(linear_velocity.length() / 60.0, 0.0, 0.3)
		_engine.volume_db = lerpf(-10.0, 4.0, rpm)
	if destroyed:
		_respawn_t += delta
		return
	if not driven_locally:
		return
	sleeping = false  # con le sole forze il corpo addormentato non ripartirebbe
	# Urti forti contro muri o terreno: danni.
	var dv := (linear_velocity - _prev_v).length()
	if dv > 14.0:
		take_damage((dv - 14.0) * 12.0, 0, global_position)
	_prev_v = linear_velocity
	if global_position.y < -9.5:
		destroy(0)  # nel Tevere
		return
	# Volo "arcade": velocità voluta nella direzione del muso, la fisica ci arriva con delle forze.
	var lift_k := smoothstep(0.55, 0.95, rpm)
	_heading += _in_yaw * YAW_RATE * delta * lift_k
	var fwd := Vector3(sin(_heading), 0.0, cos(_heading))
	var top := BOOST_SPEED if _in_boost else MAX_SPEED
	var want_h := fwd * _in_fwd * top
	var want_y := _in_lift * CLIMB
	var v := linear_velocity
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var acc := Vector3(want_h.x - v.x, 0.0, want_h.z - v.z) * 1.1
	acc.y = g + (want_y - v.y) * 2.6
	acc.x = clampf(acc.x, -14.0, 14.0)
	acc.z = clampf(acc.z, -14.0, 14.0)
	apply_central_force(acc * mass * lift_k)
	# Assetto: si inclina in avanti quando accelera, di lato in curva; girato verso _heading.
	var local_v := global_basis.inverse() * v
	var pitch := clampf(_in_fwd * 0.28 + (want_h - Vector3(v.x, 0, v.z)).dot(fwd) * 0.006, -0.35, 0.35) * lift_k
	var roll := -_in_yaw * clampf(local_v.z / 25.0, 0.0, 1.0) * 0.35 * lift_k
	var target := Basis(Vector3.UP, _heading) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, roll)
	var err := (target * global_basis.inverse()).get_rotation_quaternion()
	var ang := err.get_angle()
	if ang > PI:
		ang -= TAU
	var axis := err.get_axis() if absf(ang) > 0.0001 else Vector3.UP
	angular_velocity = angular_velocity.lerp(axis * ang * 6.0, 1.0 - exp(-8.0 * delta))


func _process(delta: float) -> void:
	Heli.spin(_rotor, _tail, _disc, rpm, delta)
	# Distrutto: dopo un po' (e se nessuno guarda) torna nuovo sulla sua piazzola.
	if destroyed and _respawn_t > 75.0 and not driven_locally:
		var cam := get_viewport().get_camera_3d()
		if cam == null or cam.global_position.distance_to(global_position) > 60.0:
			_restore()


## Sul tasto sinistro la mitragliatrice, sul destro i razzi; si spara dove guarda la camera.
func fire(p: Player, blocked: bool) -> void:
	_gun_cd -= get_physics_process_delta_time()
	_rocket_cd -= get_physics_process_delta_time()
	if blocked or destroyed or p.camera == null:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var gun := Input.is_action_pressed("vehicle_fire") or (captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	# Razzi: tasto destro, oppure R / X (Quadrato) del joypad.
	var rockets := (captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) or Input.is_action_pressed("reload")
	var cam := p.camera
	var dir := -cam.global_basis.z
	var origin := cam.global_position + dir * (global_position - cam.global_position).dot(dir)
	origin += dir * 6.0  # davanti all'elicottero, così non colpisce sé stesso
	if gun and _gun_cd <= 0.0:
		_gun_cd = float(Weapons.info("heli_mg")["rate"])
		var muzzle := global_transform * Vector3(0.0, 0.55, 2.4)
		p.combat.shoot(p, "heli_mg", origin, dir, muzzle)
		p.combat.crime.emit("shots", global_position)
	if rockets and _rocket_cd <= 0.0:
		_rocket_cd = 0.9
		_rocket_side = -_rocket_side
		var pod := global_transform * Vector3(1.15 * _rocket_side, 0.75, 0.8)
		var aim_at := origin + dir * 200.0
		p.combat.rocket(p, pod, (aim_at - pod).normalized(), p.combat.my_peer)
		p.combat.crime.emit("rocket", global_position)


func destroy(by_peer := 0) -> void:
	super.destroy(by_peer)
	_respawn_t = 0.0
	if not driven_locally:
		freeze = false
		sleeping = false
		_settle = 20.0  # cade e si ferma


func take_damage(amount: float, from_peer: int, at: Vector3) -> void:
	_since_hit = 0.0
	super.take_damage(amount, from_peer, at)


func _vanish() -> void:
	pass  # gli elicotteri non spariscono: tornano sulla piazzola (_restore)


func _restore() -> void:
	destroyed = false
	gone = false
	health = MAX_HEALTH
	_respawn_t = 0.0
	driver_peer = 0
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mi.material_override = null
	for c in get_children():
		if c is OmniLight3D:
			c.queue_free()
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis(Vector3.UP, 0.4), pad)
	if not is_in_group("damageable"):
		add_to_group("damageable")
