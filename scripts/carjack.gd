class_name CarJack
extends Node

## Salire in auto come in GTA: il giocatore va alla portiera, la apre, se c'è qualcuno al volante lo strattona fuori
## (cade, si rialza e scappa), sale e richiude. Per un paio di secondi il personaggio lo muove questa scena
## (Player.cutscene); alla fine il giocatore è al volante come con un normale enter_car.
## I modelli delle auto non hanno portiere separate: la portiera che si apre è un pannello del colore della
## carrozzeria, con dietro un riquadro scuro che copre quella disegnata (chiusa) finché è aperta.
## Autobus: si entra dalla porta anteriore (lato destro), il conducente esce da lì.

signal finished(car: Car)

const T_WALK := 0.45  # arriva alla portiera
const T_OPEN := 0.35  # la portiera si apre
const T_PULL := 0.55  # tira fuori il guidatore
const T_SIT := 0.5  # sale
const T_CLOSE := 0.3  # richiude

var player: Player
var car: Car
var driver: Pedestrians.Pedestrian  # chi sta al volante (null: auto vuota)
var _t := 0.0
var _phase := 0
var _ends: Array[float] = []
var _pivot: Node3D
var _hole: MeshInstance3D
var _side := 1.0  # +1 portiera a sinistra (+X dell'auto), -1 porta a destra (autobus)
var _hinge := Vector3.ZERO  # in coordinate dell'auto
var _stand := Vector3.ZERO  # dove sta il giocatore per aprire (coordinate dell'auto)
var _start_pos := Vector3.ZERO
var _out_pos := Vector3.ZERO  # dove finisce il guidatore tirato fuori (coordinate dell'auto)
var _seat_start := Vector3.ZERO


static func run(parent: Node, p: Player, c: Car, d: Pedestrians.Pedestrian) -> CarJack:
	var j := CarJack.new()
	j.player = p
	j.car = c
	j.driver = d
	parent.add_child(j)
	return j


func _ready() -> void:
	var bus := car.model.begins_with("bus")
	var box := car.body_box
	_side = -1.0 if bus else 1.0
	var edge := (box.position.x if bus else box.end.x)
	var door_len := 1.15 if bus else 1.05
	var front := (box.end.z - 0.35) if bus else (car.seat.origin.z + 0.6)
	_hinge = Vector3(edge, box.position.y + 0.2, front)
	var door_h := (2.3 if bus else box.size.y * 0.72 - 0.2)
	_stand = Vector3(edge + _side * 0.75, 0.0, front - door_len * 0.6)
	_out_pos = Vector3(edge + _side * 1.9, 0.0, front - door_len * 0.5)
	# Portiera: pannello del colore dell'auto (in basso) e vetro scuro (in alto), cerniera davanti.
	_pivot = Node3D.new()
	car.add_child(_pivot)
	_pivot.position = _hinge
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.35, 0.37, 0.39) if bus else car.paint_color
	paint.metallic = 0.5
	paint.roughness = 0.3
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.03, 0.04, 0.05)
	glass.roughness = 0.05
	var low := door_h * (0.6 if not bus else 0.35)
	for part: Array in [[low, 0.0, paint], [door_h - low, low, glass]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, part[0], door_len)
		bm.material = part[2]
		mi.mesh = bm
		mi.position = Vector3(_side * 0.02, float(part[1]) + float(part[0]) * 0.5, -door_len * 0.5)
		_pivot.add_child(mi)
	# Riquadro scuro sul fianco: l'interno che si vede a portiera aperta.
	_hole = MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.02, door_h - 0.05, door_len - 0.05)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.025)
	hm.material = dark
	_hole.mesh = hm
	_hole.position = _hinge + Vector3(_side * 0.012, door_h * 0.5, -door_len * 0.5)
	car.add_child(_hole)
	_hole.visible = false
	_pivot.visible = false
	# Il guidatore resta seduto al volante finché non lo si tira fuori.
	if driver:
		driver.collision_layer = 0
		driver.collision_mask = 0
		driver.set_physics_process(false)
		driver.global_transform = Transform3D(Basis(Vector3.UP, car.global_rotation.y), car.global_transform * car.seat.origin)
		driver.human().rotation.y = 0.0
		driver.human().play("drive")
	player.cutscene = true
	_start_pos = player.global_position
	var t := 0.0
	for d: float in [T_WALK, T_OPEN, T_PULL if driver else 0.0, T_SIT, T_CLOSE]:
		t += d
		_ends.append(t)


func _phase_t(i: int) -> float:
	var t0 := 0.0 if i == 0 else _ends[i - 1]
	var span := _ends[i] - t0
	return 1.0 if span <= 0.0 else clampf((_t - t0) / span, 0.0, 1.0)


func _process(delta: float) -> void:
	if not is_instance_valid(car) or car.destroyed or player.dead:
		_abort()
		return
	_t += delta
	var xf := car.global_transform
	var yaw_in := car.global_rotation.y + (PI * 0.5 if _side > 0.0 else -PI * 0.5)  # guarda verso la portiera
	var door_open := deg_to_rad(72.0)
	# 0: va alla portiera.
	if _phase == 0:
		var stand := xf * _stand
		stand.y = car.global_position.y + 0.05
		player.cutscene_pose(_start_pos.lerp(stand, _phase_t(0)), yaw_in + PI, "stroll")
		if _t >= _ends[0]:
			_phase = 1
			_pivot.visible = true
			_hole.visible = true
			Sfx.play3d("door_open", xf * _hinge, -2.0)
			player.cutscene_pose(stand, yaw_in + PI, "interact", true)
	# 1: apre la portiera.
	if _phase == 1:
		_pivot.rotation.y = -_side * door_open * ease(_phase_t(1), 0.5)
		if _t >= _ends[1]:
			_phase = 2
			if driver:
				player.cutscene_pose(player.global_position, yaw_in + PI, "push", true)
				driver.human().play_once("hit")
	# 2: tira fuori il guidatore (lo trascina fuori dalla portiera e lo butta a terra).
	if _phase == 2:
		if driver and is_instance_valid(driver):
			var k := _phase_t(2)
			var from := xf * car.seat.origin
			var to := xf * _out_pos
			to.y = car.global_position.y
			var p := from.lerp(to, ease(k, 0.6))
			p.y += sin(k * PI) * 0.25
			driver.global_position = p
			driver.human().rotation.y = car.global_rotation.y + (yaw_in - car.global_rotation.y) - driver.rotation.y
		if _t >= _ends[2]:
			_phase = 3
			_seat_start = player.global_position
			if driver and is_instance_valid(driver):
				driver.collision_layer = 32
				driver.collision_mask = 1 | 16
				driver.set_physics_process(true)
				driver.thrown_out(player.global_position)
			player.cutscene_pose(player.global_position, yaw_in, "sit_enter", true, 2.2)
	# 3: sale (dal punto davanti alla portiera al sedile).
	if _phase == 3:
		var seat := xf * car.seat.origin
		var k3 := _phase_t(3)
		player.cutscene_pose(_seat_start.lerp(seat, ease(k3, -1.6)), lerpf(yaw_in, car.global_rotation.y, k3), "")
		if _t >= _ends[3]:
			_phase = 4
			player.cutscene = false
			player.enter_car(car)
	# 4: richiude.
	if _phase == 4:
		_pivot.rotation.y = -_side * door_open * (1.0 - ease(_phase_t(4), 2.0))
		if _t >= _ends[4]:
			Sfx.play3d("door_close", xf * _hinge, 0.0)
			_cleanup()
			finished.emit(car)
			queue_free()


func _abort() -> void:
	player.cutscene = false
	if driver and is_instance_valid(driver) and not driver.is_physics_processing():
		driver.collision_layer = 32
		driver.collision_mask = 1 | 16
		driver.set_physics_process(true)
	_cleanup()
	queue_free()


func _cleanup() -> void:
	if is_instance_valid(_pivot):
		_pivot.queue_free()
	if is_instance_valid(_hole):
		_hole.queue_free()


## In corso: il giocatore non può fare altro (niente F di nuovo, niente armi).
func busy() -> bool:
	return _phase < 4
