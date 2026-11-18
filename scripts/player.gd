class_name Player
extends CharacterBody3D

## Personaggio in terza persona: cammina, corre, si accovaccia, rotola, salta, nuota, guida, combatte.
## Modello: Human (corpo e animazioni Quaternius, CC0). Armi: Weapons; colpi ed esplosioni: Combat.
##
## is_local = true: lo controlla chi gioca su questo PC (camera, input, fisica, vita).
## is_local = false: è un altro giocatore in rete; segue lo stato ricevuto con apply_state().

signal died(by_peer: int)
signal respawned

const WALK := 4.5
const SPRINT := 9.0
const CROUCH := 2.0
const AIM_WALK := 2.6
const SWIM := 2.6
## Velocità di corsa secondo l'arma in mano: a mani nude o col coltello si corre di più, con le armi pesanti di meno.
const RUN_FACTOR := {
	"pugni": 1.2, "coltello": 1.2, "mazza": 1.08, "pistola": 0.95, "granata": 0.95, "mina": 0.95, "tnt": 0.92,
	"mitragliatrice": 0.88, "pompa": 0.82, "fucile": 0.82, "cecchino": 0.78, "bazooka": 0.7,
}
const JUMP := 5.5
const GRAVITY := 16.0
const MOUSE_SENS := 0.0025
const JOY_LOOK := 3.2  # radianti al secondo con la levetta destra tutta piegata
const LAYER_LOCAL := 4
const LAYER_REMOTE := 8
const CAR_LAYER := 16
const MAX_HEALTH := 100.0
## Come in GTA: dopo qualche secondo senza essere colpiti la vita risale da sola, ma solo fino a metà.
const REGEN_DELAY := 5.0
const REGEN_RATE := 2.0  # punti vita al secondo
const REGEN_CAP := 50.0
const MAX_ARMOR := 100.0

@export var model_name := "m1"

var is_local := true
var peer_id := 1  # per i giocatori remoti: il loro id di rete
var input_enabled := true  # falso con mappe, negozi o chat aperti
var display_name := ""
var swimming := false
var cam_yaw := 0.0
var cam_pitch := -0.25
var water_check: Callable  # func(x, z) -> bool: c'è il fiume qui sotto?
var water_y := -10.5  # pelo dell'acqua del Tevere
var car_lookup: Callable  # func(id) -> Car (per i giocatori remoti al volante)
var hurt_remote: Callable  # func(peer, quantità): danno a un giocatore di un altro PC
var combat: Combat
var camera: Camera3D
var vehicle: Car  # auto guidata da questo giocatore (solo locale)

# Stato di gioco.
var health := MAX_HEALTH
var armor := 0.0
var money := 500
var dead := false
var crouching := false
var aiming := false
var weapon := "pugni"
var ammo := {"pugni": -1}  # munizioni di riserva (-1 = infinite)
var clip := {}  # colpi nel caricatore
var last_hit_by := 0
var hurt_flash := 0.0
var penalty_paid := false  # la perdita di soldi per questa morte è già stata pagata
var stash := 0  # pacchetti da spacciare
const MAX_STASH := 30

var _model: Node3D
var _human: Human
var _current := ""
var _pivot: Node3D
var _arm: SpringArm3D
var _tag: Label3D
var _shape: CollisionShape3D
var _walk_zoom := 4.5
var _last_mouse := -10.0
var _cool := 0.0
var _busy := 0.0  # animazione breve in corso (colpo, ricarica, lancio)
var _since_hit := 0.0  # secondi dall'ultimo colpo subito
var _sprint_lock := false  # corsa accesa col clic della levetta sinistra
var scooter := -1  # id del monopattino su cui si sta (-1 = a piedi)
var _ride_speed := 0.0
var _ride_yaw := 0.0
var _ride_mesh: MeshInstance3D
var _roll := 0.0
var _roll_dir := Vector3.ZERO
var _fall_speed := 0.0
var _dead_time := 0.0
var _weapon_node: Node3D
var _weapon_shown := ""
var _net_pos := Vector3.ZERO
var _net_rot := 0.0
var _net_anim := "idle"
var _net_car := -1
var _net_weapon := "pugni"
var _net_seen := false
var _step := 0.0


func _ready() -> void:
	add_to_group("damageable")
	collision_layer = LAYER_LOCAL if is_local else LAYER_REMOTE
	collision_mask = (1 | 2 | LAYER_REMOTE | CAR_LAYER | 32) if is_local else 0
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.4
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	_shape = CollisionShape3D.new()
	_shape.shape = shape
	_shape.position.y = 0.85
	add_child(_shape)
	_load_model()
	if not is_local:
		_tag = Label3D.new()
		_tag.position.y = 2.4
		_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tag.no_depth_test = true
		_tag.fixed_size = true
		_tag.pixel_size = 0.0012
		_tag.font_size = 32
		_tag.outline_size = 10
		_tag.modulate = Color(1.0, 0.95, 0.6)
		_tag.visibility_range_end = 400.0
		_tag.text = display_name
		add_child(_tag)
		return
	_pivot = Node3D.new()
	add_child(_pivot)
	_pivot.top_level = true
	_pivot.global_position = global_position + Vector3(0, 1.6, 0)
	_arm = SpringArm3D.new()
	_arm.spring_length = _walk_zoom
	_arm.collision_mask = 1
	_arm.margin = 0.2
	var arm_shape := SphereShape3D.new()
	arm_shape.radius = 0.25
	_arm.shape = arm_shape
	_arm.add_excluded_object(get_rid())
	_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 70
	camera.far = 3000
	_arm.add_child(camera)
	camera.current = true


func _load_model() -> void:
	if _model:
		_model.queue_free()
	_current = ""
	if not Human.PRESETS.has(model_name):
		model_name = "m1"  # nome sconosciuto (versioni vecchie del gioco)
	_human = Human.new().setup(model_name)
	_model = _human
	add_child(_model)
	_weapon_shown = ""


func set_model(name_: String) -> void:
	if name_ == model_name and _model != null:
		return
	model_name = name_
	if is_inside_tree():
		_load_model()


func set_display_name(n: String) -> void:
	display_name = n
	if _tag:
		_tag.text = n


## Stato da inviare agli altri: posizione, direzione del corpo, animazione, auto (-1 = a piedi), arma.
func net_state() -> Array:
	# Auto: il suo id; -1 a piedi; -2 - colore se in monopattino.
	var on := vehicle.car_id if vehicle else (-2 - _ride_color() if scooter >= 0 else -1)
	return [global_position, _model.rotation.y if _model else 0.0, _current, on, weapon]


func _ride_color() -> int:
	return int(_ride_mesh.get_meta("color", 0)) if _ride_mesh else 0


func apply_state(pos: Vector3, rot: float, anim: String, car := -1, weapon_id := "pugni") -> void:
	_net_pos = pos
	_net_rot = rot
	_net_anim = anim
	_net_car = car
	_net_weapon = weapon_id
	if not _net_seen:
		_net_seen = true
		global_position = pos


func is_mine() -> bool:
	return is_local


# --- Vita ---------------------------------------------------------------------------------------


func take_damage(amount: float, from_peer: int, _at: Vector3) -> void:
	if not is_local:
		if hurt_remote.is_valid():
			hurt_remote.call(peer_id, amount)
		return
	if dead or amount <= 0.0:
		return
	var absorbed := minf(armor, amount * 0.7)
	armor -= absorbed
	health -= amount - absorbed
	hurt_flash = 1.0
	_since_hit = 0.0
	last_hit_by = from_peer
	Sfx.play2d("hurt", -4.0)
	if health <= 0.0:
		_die(from_peer)
	elif amount > 10.0 and _busy <= 0.0 and vehicle == null:
		_human.play_once("hit")
		_busy = 0.35


func heal(amount: float) -> void:
	health = minf(MAX_HEALTH, health + amount)


func _die(by_peer: int) -> void:
	health = 0.0
	dead = true
	_dead_time = 0.0
	aiming = false
	if vehicle:
		exit_car()
	_play("death")
	died.emit(by_peer)


## Rinasce all'ospedale (il punto di partenza): perde un po' di soldi, come in GTA.
func respawn_at(pos: Vector3) -> void:
	dead = false
	health = MAX_HEALTH
	armor = 0.0
	# Ucciso da un altro giocatore: ha già lasciato a terra metà dei soldi, quella è la perdita.
	if not penalty_paid:
		money = maxi(0, money - mini(500, money / 10))
	penalty_paid = false
	_current = ""
	teleport(pos)
	respawned.emit()


# --- Armi ---------------------------------------------------------------------------------------


## Dà l'arma (o solo i colpi, se già la si ha). select = false: raccolti da terra, non cambia l'arma in mano.
func give_weapon(id: String, rounds: int, select := true) -> void:
	var w := Weapons.info(id)
	if w["kind"] == "melee":
		ammo[id] = -1
		return
	if not ammo.has(id):
		ammo[id] = 0
		clip[id] = 0
	ammo[id] += rounds
	if w.has("mag") and clip.get(id, 0) == 0:
		_reload_now(id)
	if select or weapon == "pugni":
		weapon = id


func owned_weapons() -> Array:
	var out := []
	for id: String in Weapons.ORDER:
		# Le armi da fuoco restano anche scariche (basta comprare le munizioni); granate, mine e TNT finite spariscono.
		var kind: String = Weapons.info(id)["kind"]
		if ammo.has(id) and (ammo[id] != 0 or clip.get(id, 0) > 0 or kind in ["melee", "gun", "rocket"]):
			out.append(id)
	return out


## Seleziona l'arma di uno slot; premendo di nuovo passa alla successiva dello stesso slot.
func select_slot(slot: int) -> void:
	var options := []
	for id: String in owned_weapons():
		if int(Weapons.info(id)["slot"]) == slot:
			options.append(id)
	if options.is_empty():
		return
	var i := options.find(weapon)
	weapon = options[(i + 1) % options.size()] if i >= 0 else options[0]


func next_weapon(step := 1) -> void:
	var list := owned_weapons()
	if list.is_empty():
		return
	weapon = list[(list.find(weapon) + step + list.size()) % list.size()]


func rounds_text() -> String:
	var w := Weapons.info(weapon)
	match String(w["kind"]):
		"melee":
			return ""
		"throw", "place":
			return str(ammo.get(weapon, 0))
	return "%d / %d" % [clip.get(weapon, 0), ammo.get(weapon, 0)]


func _reload_now(id: String) -> void:
	var w := Weapons.info(id)
	if not w.has("mag"):
		return
	var need: int = int(w["mag"]) - int(clip.get(id, 0))
	var take: int = mini(need, int(ammo.get(id, 0)))
	clip[id] = int(clip.get(id, 0)) + take
	ammo[id] = int(ammo.get(id, 0)) - take


func reload() -> void:
	var w := Weapons.info(weapon)
	if not w.has("mag") or int(ammo.get(weapon, 0)) <= 0 or int(clip.get(weapon, 0)) >= int(w["mag"]):
		return
	_reload_now(weapon)
	Sfx.play3d("reload", global_position + Vector3(0, 1.2, 0), -2.0)
	if not mounted():
		_human.play_once("reload")
	_busy = 1.0
	_cool = 1.0


## Punto e direzione di mira: dal centro dello schermo (camera) verso quello che c'è nel mirino.
func aim_ray() -> Array:
	var origin := camera.global_position
	var dir := -camera.global_basis.z
	# Si parte dall'altezza del personaggio, così non si colpisce ciò che sta tra la camera e lui.
	var along := (global_position + Vector3(0, 1.4, 0) - origin).dot(dir)
	return [origin + dir * maxf(along, 0.0), dir]


func _attack() -> void:
	var w := Weapons.info(weapon)
	var kind: String = w["kind"]
	var r := aim_ray()
	var origin: Vector3 = r[0]
	var dir: Vector3 = r[1]
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var on_board := mounted()
	if not on_board:
		_model.rotation.y = atan2(flat.x, flat.z)
	var muzzle := _weapon_node.global_position + _weapon_node.global_basis.z * float(w.get("len", 0.3)) * 0.5 if _weapon_node else _human.hand_position()
	if vehicle:
		# Dal finestrino: la canna sporge di lato verso il bersaglio, sopra la portiera.
		muzzle = vehicle.global_position + Vector3(0, 1.35, 0) + flat * 1.3
	_cool = float(w["rate"])
	match kind:
		"melee":
			var chest := global_position + Vector3(0, 1.3, 0)
			combat.melee(self, weapon, chest, flat)
			_human.play_once("melee" if weapon != "pugni" else ("punch" if randf() < 0.5 else "punch2"))
			_busy = 0.45
		"gun":
			if int(clip.get(weapon, 0)) <= 0:
				if int(ammo.get(weapon, 0)) <= 0:
					Sfx.play3d("empty", muzzle, -4.0)
				reload()
				return
			clip[weapon] = int(clip[weapon]) - 1
			combat.shoot(self, weapon, origin, dir, muzzle)
			combat.crime.emit("shots", global_position)
			if not on_board:
				_human.play_once("shoot", 0.02)
			cam_pitch += 0.012 if weapon != "cecchino" else 0.05  # rinculo
			_busy = 0.12
		"rocket":
			if int(clip.get(weapon, 0)) <= 0:
				reload()
				return
			clip[weapon] = int(clip[weapon]) - 1
			combat.rocket(self, muzzle + dir * 0.6, dir, combat.my_peer)
			combat.crime.emit("rocket", global_position)
			if not on_board:
				_human.play_once("shoot", 0.02)
			_busy = 0.4
		"throw":
			if int(ammo.get(weapon, 0)) <= 0:
				return
			ammo[weapon] = int(ammo[weapon]) - 1
			combat.grenade(self, _human.hand_position() + flat * 0.5 + Vector3(0, 0.3, 0), (dir + Vector3(0, 0.15, 0)).normalized(), combat.my_peer)
			combat.crime.emit("shots", global_position)
			_human.play_once("throw")
			_busy = 0.5
		"place":
			if int(ammo.get(weapon, 0)) <= 0:
				return
			ammo[weapon] = int(ammo[weapon]) - 1
			combat.place(weapon, global_position + flat * 0.7 + Vector3(0, 0.02, 0), combat.my_peer)
			_human.play_once("interact")
			_busy = 0.6
	if owned_weapons().find(weapon) < 0:
		weapon = "pugni"


func _update_weapon_model() -> void:
	var want := weapon if not (is_local and vehicle) else ""
	if not is_local:
		want = _net_weapon if _net_car < 0 else ""
	if want != _weapon_shown:
		if _weapon_node:
			_weapon_node.queue_free()
			_weapon_node = null
		_weapon_shown = want
		if want != "":
			_weapon_node = Weapons.model(want)
			if _weapon_node:
				add_child(_weapon_node)
				_weapon_node.top_level = true
	if _weapon_node:
		var yaw := _model.rotation.y + global_rotation.y
		var pitch := 0.0
		if is_local and aiming:
			pitch = -cam_pitch * 0.9
		var at := _human.hand_position()
		if (_weapon_shown == "bazooka") and _current in ["aim", "aim_up", "aim_down", "armed"]:
			# Il lanciarazzi sta sulla spalla destra, accanto alla testa (non davanti alla faccia).
			var b := Basis(Vector3.UP, yaw)
			at = global_position + Vector3(0, (1.0 if crouching else 1.52), 0) + b * Vector3(-0.24, 0, 0.05)
		_weapon_node.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), at)
		_weapon_node.visible = not (is_local and aiming and weapon == "cecchino")
	# Nel cannocchiale la camera sta dentro la testa: il proprio corpo si nasconde, sennò copre la vista.
	if is_local and _model:
		_model.visible = not (aiming and weapon == "cecchino" and not dead)


# --- Auto ---------------------------------------------------------------------------------------


func enter_car(car: Car) -> void:
	vehicle = car
	velocity = Vector3.ZERO
	aiming = false
	crouching = false
	_shape.disabled = true
	car.set_driven(true)
	_arm.add_excluded_object(car.get_rid())
	cam_yaw = car.global_rotation.y + PI
	_model.rotation.y = 0.0
	_play("drive")


func exit_car() -> void:
	var car := vehicle
	if car == null:
		return
	vehicle = null
	car.set_driven(false)
	_arm.remove_excluded_object(car.get_rid())
	var out := car.global_transform * (car.seat.origin + Vector3(1.4, 0, 0))
	global_position = Vector3(out.x, car.global_position.y + 0.3, out.z)
	global_rotation = Vector3.ZERO
	_model.rotation.y = car.global_rotation.y
	_shape.disabled = false


## In auto o in monopattino.
func mounted() -> bool:
	return vehicle != null or scooter >= 0


var _mount_trig_prev := false


## Sparare da auto e monopattino (stile GTA): si mira con la camera (mouse o levetta destra) e si spara con il
## tasto sinistro del mouse o LB / L1 del joypad (RT / R2 lì serve per accelerare). Solo armi da fuoco e lanciarazzi.
func _mounted_fire(blocked: bool) -> void:
	if blocked:
		_mount_trig_prev = false
		return
	var w := Weapons.info(weapon)
	if not String(w["kind"]) in ["gun", "rocket"]:
		return
	var trig := Input.is_action_pressed("vehicle_fire") or (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	var fire := trig if w.get("auto", false) else (trig and not _mount_trig_prev)
	_mount_trig_prev = trig
	if fire and _cool <= 0.0:
		_attack()
	if Input.is_action_just_pressed("reload"):
		reload()


# --- Monopattino --------------------------------------------------------------------------------


## Sale sul monopattino id (colore color_i), girato verso yaw.
func mount_scooter(id: int, color_i: int, yaw: float) -> void:
	scooter = id
	_ride_speed = 0.0
	_ride_yaw = yaw
	aiming = false
	crouching = false
	_sprint_lock = false
	_set_ride_mesh(true, color_i)
	_model.rotation.y = yaw
	cam_yaw = yaw + PI


## Scende: ritorna [posizione, direzione] dove lasciare il monopattino.
func dismount_scooter() -> Array:
	var yaw := _ride_yaw
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var at := global_position + Vector3(fwd.z, 0, -fwd.x) * 0.6  # di fianco a sé
	scooter = -1
	_set_ride_mesh(false)
	return [at + Vector3(0, 0.06, 0), yaw]


func _set_ride_mesh(on: bool, color_i := 0) -> void:
	if on and _ride_mesh == null:
		_ride_mesh = Scooters.make_node(color_i)
		_ride_mesh.set_meta("color", color_i)
		add_child(_ride_mesh)
	elif not on and _ride_mesh:
		_ride_mesh.queue_free()
		_ride_mesh = null
	if _model:
		_model.position.y = 0.15 if on else 0.0  # in piedi sulla pedana


## Guida del monopattino: W / RT accelera, S / LT frena, A-D / levetta sterza; la camera segue da dietro.
func _ride(delta: float, blocked: bool) -> void:
	var throttle := 0.0 if blocked else clampf(Input.get_axis("move_back", "move_forward")
		+ Input.get_action_strength("accelerate") - Input.get_action_strength("brake"), -1.0, 1.0)
	var steer := 0.0 if blocked else Input.get_axis("move_right", "move_left")
	if throttle > 0.0:
		_ride_speed = move_toward(_ride_speed, Scooters.RIDE_SPEED * throttle, delta * 3.0)
	elif throttle < 0.0:
		_ride_speed = move_toward(_ride_speed, 0.0, delta * 9.0)
	else:
		_ride_speed = move_toward(_ride_speed, 0.0, delta * 1.2)  # a ruota libera
	_ride_yaw += steer * delta * lerpf(2.4, 1.4, _ride_speed / Scooters.RIDE_SPEED)
	var fwd := Vector3(sin(_ride_yaw), 0, cos(_ride_yaw))
	velocity.x = fwd.x * _ride_speed
	velocity.z = fwd.z * _ride_speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	# Contro un muro si ferma.
	var real := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if _ride_speed > 1.0 and real < _ride_speed * 0.3:
		_ride_speed = real
	_model.rotation.y = _ride_yaw
	if _ride_mesh:
		_ride_mesh.rotation.y = _ride_yaw
	_play("idle")
	_update_weapon_model()


func _seat_transform(car: Car) -> Transform3D:
	return car.global_transform * car.seat


# --- Ciclo --------------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * (0.25 if aiming and weapon == "cecchino" else (0.6 if aiming else 1.0))
		cam_yaw -= event.relative.x * sens
		cam_pitch = clampf(cam_pitch - event.relative.y * sens, -1.3, 0.9)
		_last_mouse = Time.get_ticks_msec() / 1000.0
	elif event is InputEventMouseButton and event.pressed and not aiming:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_walk_zoom = maxf(1.5, _walk_zoom - 0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_walk_zoom = minf(18.0, _walk_zoom + 0.5)


func _physics_process(delta: float) -> void:
	if not is_local:
		_puppet_update(delta)
		_update_weapon_model()
		return
	hurt_flash = maxf(0.0, hurt_flash - delta * 1.5)
	_since_hit += delta
	if not dead and _since_hit > REGEN_DELAY and health < REGEN_CAP:
		health = minf(REGEN_CAP, health + REGEN_RATE * delta)
	_cool -= delta
	_busy -= delta
	var blocked := get_viewport().gui_get_focus_owner() is LineEdit or not input_enabled or dead
	if dead:
		_dead_time += delta
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	if vehicle:
		var throttle := 0.0 if blocked else clampf(
			Input.get_axis("move_back", "move_forward")
			+ Input.get_action_strength("accelerate") - Input.get_action_strength("brake"), -1.0, 1.0)
		var steer := 0.0 if blocked else Input.get_axis("move_right", "move_left")
		vehicle.drive(throttle, steer, not blocked and Input.is_action_pressed("jump"), delta)
		global_transform = _seat_transform(vehicle)
		_model.rotation.y = 0.0
		swimming = false
		_play("drive")
		_update_weapon_model()
		_mounted_fire(blocked)
		return
	if scooter >= 0:
		_ride(delta, blocked)
		_mounted_fire(blocked)
		return
	var input := Vector2.ZERO if blocked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (Basis(Vector3.UP, cam_yaw) * Vector3(input.x, 0, input.y))
	# Joypad: clic della levetta sinistra accende la corsa, che resta finché ci si muove.
	if not blocked and Input.is_action_just_pressed("sprint_toggle"):
		_sprint_lock = not _sprint_lock
		crouching = false
	if input.length() < 0.2:
		_sprint_lock = false
	var sprint := not blocked and (Input.is_action_pressed("sprint") or _sprint_lock) and not crouching
	var jump := not blocked and Input.is_action_just_pressed("jump")
	aiming = not blocked and Input.is_action_pressed("aim") and not swimming and _roll <= 0.0
	if not blocked and Input.is_action_just_pressed("crouch"):
		crouching = not crouching
	if not blocked and Input.is_action_just_pressed("roll") and is_on_floor() and _roll <= 0.0 and dir.length() > 0.1:
		_roll = 0.75
		_roll_dir = dir.normalized()
		crouching = false
		_human.play_once("roll")
	var over_river: bool = water_check.is_valid() and water_check.call(global_position.x, global_position.z)
	swimming = over_river and global_position.y < water_y - 0.9
	if swimming:
		crouching = false

	var run_k: float = RUN_FACTOR.get(weapon, 1.0)
	var speed := SWIM if swimming else (CROUCH if crouching else (AIM_WALK if aiming else (
		SPRINT * run_k if sprint else WALK * lerpf(1.0, run_k, 0.5))))
	var target := dir * speed
	if _roll > 0.0:
		_roll -= delta
		target = _roll_dir * 7.0
	var accel := 10.0 if is_on_floor() or swimming else 3.0
	velocity.x = lerpf(velocity.x, target.x, 1.0 - exp(-accel * delta))
	velocity.z = lerpf(velocity.z, target.z, 1.0 - exp(-accel * delta))

	if swimming:
		var float_y := water_y - 1.25
		velocity.y = lerpf(velocity.y, (float_y - global_position.y) * 4.0, 1.0 - exp(-6.0 * delta))
		if jump:
			velocity.y = JUMP * 1.15
	else:
		velocity.y -= GRAVITY * delta
		if is_on_floor() and jump:
			velocity.y = JUMP
			crouching = false
	var was_air := not is_on_floor()
	var vy := velocity.y
	move_and_slide()
	# Danno da caduta (oltre ~6 m).
	if was_air and is_on_floor() and vy < -11.0 and not swimming:
		take_damage((-vy - 11.0) * 9.0, 0, global_position)

	if aiming:
		_model.rotation.y = lerp_angle(_model.rotation.y, cam_yaw + PI, 1.0 - exp(-20.0 * delta))
	elif dir.length() > 0.1:
		var face := atan2(dir.x, dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, face, 1.0 - exp(-12.0 * delta))
	var fire := Input.is_action_pressed("fire") if Weapons.info(weapon).get("auto", false) else Input.is_action_just_pressed("fire")
	if not blocked and fire and _cool <= 0.0 and not swimming and _roll <= 0.0:
		_attack()
	if not blocked and Input.is_action_just_pressed("reload"):
		reload()
	_update_anim(dir.length() > 0.1, sprint)
	_update_weapon_model()
	# Passi.
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 1.0 and not swimming:
		_step -= delta
		if _step <= 0.0:
			_step = 0.5 if crouching else (0.27 if sprint else 0.36)
			Sfx.play3d("step%d" % randi_range(0, 3), global_position, -10.0 if crouching else -4.0, 1.0, 30.0)


func _puppet_update(delta: float) -> void:
	if not _net_seen:
		return
	if _net_car >= 0 and car_lookup.is_valid():
		var car: Car = car_lookup.call(_net_car)
		if car:
			global_transform = _seat_transform(car)
			_model.rotation.y = 0.0
			_play("drive")
			return
	global_rotation = Vector3.ZERO
	# In monopattino (stato -2 - colore): lo si vede sopra, girato come il corpo.
	if _net_car <= -2:
		_set_ride_mesh(true, -2 - _net_car)
		_ride_mesh.rotation.y = _model.rotation.y
	elif _ride_mesh:
		_set_ride_mesh(false)
	var k := 1.0 - exp(-12.0 * delta)
	if global_position.distance_to(_net_pos) > 20.0:
		global_position = _net_pos
	else:
		global_position = global_position.lerp(_net_pos, k)
	_model.rotation.y = lerp_angle(_model.rotation.y, _net_rot, k)
	_play(_net_anim)


func _process(delta: float) -> void:
	if not is_local:
		return
	# Levetta destra del joypad: camera (curva quadratica, così i piccoli movimenti sono precisi).
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO and input_enabled and get_viewport().gui_get_focus_owner() == null:
		look *= look.length()
		var rate := JOY_LOOK * (0.2 if aiming and weapon == "cecchino" else (0.5 if aiming else 1.0))
		cam_yaw -= look.x * rate * delta
		cam_pitch = clampf(cam_pitch - look.y * rate * 0.7 * delta, -1.3, 0.9)
		_last_mouse = Time.get_ticks_msec() / 1000.0
	var head := global_position + Vector3(0, 0.95 if crouching else 1.6, 0)
	var target_len := _walk_zoom
	var side := 0.0
	var fov := 70.0
	if vehicle:
		head = vehicle.global_position + Vector3(0, 1.9, 0)
		target_len = 7.5
		if Time.get_ticks_msec() / 1000.0 - _last_mouse > 1.2 and vehicle.linear_velocity.length() > 2.0:
			cam_yaw = lerp_angle(cam_yaw, vehicle.global_rotation.y + PI, 1.0 - exp(-2.5 * delta))
			cam_pitch = lerpf(cam_pitch, -0.22, 1.0 - exp(-2.0 * delta))
	elif scooter >= 0:
		# In monopattino la camera torna dietro le spalle quando non la si muove.
		if Time.get_ticks_msec() / 1000.0 - _last_mouse > 1.0 and _ride_speed > 1.0:
			cam_yaw = lerp_angle(cam_yaw, _ride_yaw + PI, 1.0 - exp(-3.0 * delta))
	elif aiming:
		# Mira sopra la spalla destra; col cecchino si guarda nel cannocchiale.
		target_len = 1.8
		side = 0.6
		if weapon == "cecchino":
			target_len = 0.0
			side = 0.0
			fov = 14.0
			head = global_position + Vector3(0, 1.62, 0)
	elif dead:
		target_len = 6.0
	_arm.spring_length = lerpf(_arm.spring_length, target_len, 1.0 - exp(-14.0 * delta))
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-12.0 * delta))
	var right := Basis(Vector3.UP, cam_yaw) * Vector3.RIGHT
	_pivot.global_position = _pivot.global_position.lerp(head + right * side, 1.0 - exp(-20.0 * delta))
	_pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)


func _update_anim(moving: bool, sprint: bool) -> void:
	if _busy > 0.0 or _roll > 0.0:
		return
	var armed: bool = weapon != "pugni"
	var want := "idle"
	if swimming:
		want = "swim" if moving else "swim_idle"
	elif not is_on_floor() and velocity.y > 0.5:
		want = "jump"
	elif not is_on_floor() and velocity.y < -3.0:
		want = "fall"
	elif crouching:
		want = "crouch_walk" if moving else "crouch"
	elif aiming:
		want = "stroll" if moving else ("aim_up" if cam_pitch > 0.35 else ("aim_down" if cam_pitch < -0.45 else "aim"))
	elif moving:
		want = "sprint" if sprint else "walk"
	elif armed and Weapons.info(weapon)["kind"] == "gun":
		want = "armed"
	_play(want)


func _play(want: String) -> void:
	if want == _current or _human == null:
		return
	_human.play(want)
	_current = want


func set_zoom(length: float) -> void:
	if _arm:
		_arm.spring_length = clampf(length, 1.5, 40.0)
		_walk_zoom = _arm.spring_length


func teleport(pos: Vector3) -> void:
	if vehicle:
		exit_car()
	global_position = pos
	velocity = Vector3.ZERO
	if _pivot:
		_pivot.global_position = pos + Vector3(0, 1.6, 0)
