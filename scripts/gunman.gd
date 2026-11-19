class_name Gunman
extends CharacterBody3D

## Personaggio armato generico: vigilanti delle banche, nemici delle missioni, guardie del corpo, sicari.
## Sta al suo posto (anchor, girato verso face_yaw) o pattuglia; se foe_fn() gli dà un bersaglio lo insegue e gli
## spara quando lo vede (precisione da `skill`, 0 scarso - 1 ottimo). Alla morte chiama on_dead(self, chi l'ha ucciso).

var combat: Combat
var world: Node  # main.gd (per il registro dei colpi in rete), può mancare
var nid := 0
var preset := "guard"
var weapon := "pistola"
var health := 120.0
var skill := 0.5
var anchor := Vector3.ZERO
var face_yaw := 0.0
var foe_fn: Callable  # func(self) -> Node3D o null
var on_dead: Callable  # func(Gunman, from_peer)
var on_hurt: Callable  # func(Gunman, from_peer)
var flee_on_hit := false  # civili: scappano invece di combattere
var label := ""  # nome sopra la testa (vicino)
var dead := false
var dead_time := 0.0
var net_anim := "idle"
var foe: Node3D
var _human: Human
var _gun: Node3D
var _cool := 0.8
var _scan := 0.0
var _stuck := 0.0
var _side := 1.0


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("pedestrian")
	add_to_group("gang")
	set_meta("gang", true)
	if world and nid > 0:
		world.register(nid, self)
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
	_human.rotation.y = face_yaw
	if weapon != "":
		_gun = Weapons.model(weapon)
		if _gun:
			add_child(_gun)
			_gun.top_level = true
	if label != "":
		var t := Label3D.new()
		t.text = label
		t.position.y = 2.25
		t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		t.font_size = 36
		t.outline_size = 10
		t.pixel_size = 0.006
		t.modulate = Color(1.0, 0.85, 0.6)
		t.visibility_range_end = 45.0
		add_child(t)


func is_mine() -> bool:
	return true


func human() -> Human:
	return _human


func take_damage(amount: float, from_peer: int, at: Vector3) -> void:
	if dead:
		return
	health -= amount
	if on_hurt.is_valid():
		on_hurt.call(self, from_peer)
	if health <= 0.0:
		dead = true
		net_anim = "death"
		collision_layer = 0
		_human.play_once("death")
		if _gun:
			_gun.queue_free()
			_gun = null
		for c in get_children():
			if c is Label3D:
				c.queue_free()
		if on_dead.is_valid():
			on_dead.call(self, from_peer)
	else:
		_human.play_once("hit")


func _sees(n: Node3D) -> bool:
	var from := global_position + Vector3(0, 1.6, 0)
	var to := n.global_position + Vector3(0, 1.3, 0)
	if from.distance_to(to) > 70.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _physics_process(delta: float) -> void:
	if dead:
		dead_time += delta
		velocity = Vector3(0, velocity.y - 16.0 * delta, 0)
		move_and_slide()
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.5
		foe = foe_fn.call(self) if foe_fn.is_valid() else null
		if foe and (not is_instance_valid(foe) or foe.get("dead") == true or foe.get_meta("dead", false)):
			foe = null
	_cool -= delta
	var target_v := Vector3.ZERO
	var anim := "idle"
	var face := face_yaw
	var goal := anchor
	if foe:
		var to := foe.global_position - global_position
		to.y = 0.0
		face = atan2(to.x, to.z)
		if flee_on_hit:
			goal = global_position - to.normalized() * 10.0
		elif weapon != "" and to.length() < 24.0 and _sees(foe):
			anim = "aim"
			if _cool <= 0.0:
				_shoot(foe)
		else:
			goal = foe.global_position
	if anim != "aim":
		var to := goal - global_position
		to.y = 0.0
		if to.length() > (0.6 if foe == null else 3.0):
			var dir := to.normalized()
			if _stuck > 0.6:
				dir = (dir + Vector3(-dir.z, 0, dir.x) * _side * 1.5).normalized()
			var run := foe != null
			target_v = dir * (5.6 if run else 1.6)
			anim = "sprint" if run else "stroll"
			face = atan2(dir.x, dir.z)
	velocity.x = lerpf(velocity.x, target_v.x, 1.0 - exp(-8.0 * delta))
	velocity.z = lerpf(velocity.z, target_v.z, 1.0 - exp(-8.0 * delta))
	velocity.y = 0.0 if is_on_floor() else velocity.y - 16.0 * delta
	var before := global_position
	move_and_slide()
	if target_v.length() > 1.0 and global_position.distance_to(before) < target_v.length() * delta * 0.3:
		_stuck += delta
		if _stuck > 2.0:
			_stuck = 0.0
			_side = -_side
	else:
		_stuck = maxf(0.0, _stuck - delta)
	_human.rotation.y = lerp_angle(_human.rotation.y, face, 1.0 - exp(-10.0 * delta))
	net_anim = anim
	_human.play(anim)
	if _gun:
		_gun.global_transform = Transform3D(Basis(Vector3.UP, _human.rotation.y + rotation.y), _human.hand_position())


func _shoot(n: Node3D) -> void:
	var auto := weapon in ["mitragliatrice", "fucile"]
	_cool = randf_range(0.1, 0.18) if auto and randf() < 0.75 else randf_range(0.6, 1.3) * lerpf(1.4, 0.7, skill)
	var origin := global_position + Vector3(0, 1.45, 0)
	var aim := n.global_position + Vector3(0, 1.1, 0)
	var miss := (1.0 + aim.distance_to(origin) * 0.045) * lerpf(0.9, 0.25, skill)
	aim += Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * miss
	combat.shoot(self, weapon, origin, (aim - origin).normalized(), _gun.global_position if _gun else origin)
