class_name Icone
extends Node3D

## Personaggi famosi del mondo romano, fermi in un posto della mappa: si girano verso chi si avvicina, con E
## dicono una battuta (in romanesco), e qualcuno ha i suoi oggetti (Totti: il pallone, che si può calciare).
## Ognuno è un Human con un preset in Human.UNIFORMS (ed eventualmente una divisa in Human.KITS).
## Per ora ogni PC ha i suoi (non passano dalla rete): restano fermi, quindi tutti li vedono nello stesso posto.

const ICONE := {
	"totti": {
		"name": "Francesco Totti",
		"at": Vector2(-45.6, -587.7),  # davanti allo Stadio Flaminio, lato sud-ovest
		"ball": true,
		"lines": [
			"Ahò! Se famo du' tiri?",
			"Daje Roma, daje!",
			"Er cucchiaio? Basta avé coraggio, er resto viene da sé.",
			"Venticinque anni co' 'sta maglia. Una sola.",
			"Er derby nun se gioca: se vince.",
			"Passame 'a palla, va'!",
			"Qua ar Flaminio ce giocavamo prima de l'Olimpico, lo sai?",
			"Mica so' un monumento, eh. Però quasi.",
		],
		"kick_lines": ["Bel tiro!", "Mmh, se po' fa' mejo.", "Questa la tiravo io a occhi chiusi."],
	},
}
const TALK_DIST := 2.8
const LOOK_DIST := 9.0
const BALL_R := 0.11

var main: Node
var city: CityBuilder
var _still := "--iconetest" in OS.get_cmdline_user_args()  # prova: non si girano (per fotografarli di spalle)
var _people: Array = []  # [{id, root, human, bubble, bubble_t, line_i, ball, home, ball_away_t}]


func setup(c: CityBuilder, m: Node) -> void:
	city = c
	main = m
	for id: String in ICONE:
		_spawn(id, ICONE[id])


## Prova: --iconeview=fronte|spalle mette una telecamera a 2,2 m dal primo personaggio (con --iconetest).
func _test_camera(root: Node3D) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--iconeview="):
			var back := arg.get_slice("=", 1) == "spalle"
			var cam := Camera3D.new()
			cam.fov = 40.0
			add_child(cam)
			var at := root.global_position + Vector3(0.6, 1.25, -2.4 if back else 2.4)
			cam.look_at_from_position(at, root.global_position + Vector3(0, 1.0, 0))
			cam.current = true


func _spawn(id: String, d: Dictionary) -> void:
	var at: Vector2 = d["at"]
	var root := Node3D.new()
	root.name = "Icona_" + id
	add_child(root)
	root.global_position = Vector3(at.x, city.surface_at(at.x, at.y), at.y)
	var h := Human.new().setup(id)
	root.add_child(h)
	# Corpo per non passargli attraverso.
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	body.add_child(cs)
	root.add_child(body)
	var bubble := Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.fixed_size = true
	bubble.pixel_size = 0.0012
	bubble.font_size = 30
	bubble.outline_size = 10
	bubble.position.y = 2.15
	bubble.modulate = Color(1, 1, 1, 0)
	bubble.width = 900.0
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(bubble)
	var tag := Label3D.new()
	tag.text = String(d["name"])
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 26
	tag.outline_size = 8
	tag.pixel_size = 0.004
	tag.modulate = Color(1.0, 0.82, 0.3)
	tag.position.y = 2.0
	tag.visibility_range_end = 25.0
	root.add_child(tag)
	var p := {"id": id, "root": root, "human": h, "bubble": bubble, "bubble_t": 0.0, "line_i": -1, "ball": null,
		"home": root.global_position, "ball_away_t": 0.0, "anim_t": randf() * 10.0}
	if d.get("ball", false):
		p["ball"] = _make_ball(root.global_position + Vector3(0.35, BALL_R + 0.02, 0.45))
	_people.append(p)
	if _people.size() == 1:
		_test_camera.call_deferred(root)


func _make_ball(at: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = "Pallone"
	b.mass = 0.43
	b.collision_layer = 1 << 9  # i giocatori non ci sbattono: il pallone si calcia avvicinandosi
	b.collision_mask = 1
	b.linear_damp = 0.25
	b.angular_damp = 0.6
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.55
	pm.friction = 0.7
	b.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = BALL_R
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/people/totti/pallone.png")
	mat.roughness = 0.35
	mi.material_override = mat
	b.add_child(mi)
	add_child(b)
	b.global_position = at
	return b


func _process(delta: float) -> void:
	var pl: Node3D = main.player
	if pl == null:
		return
	var pp := pl.global_position
	for p: Dictionary in _people:
		var root: Node3D = p["root"]
		var h: Human = p["human"]
		var to := pp - root.global_position
		to.y = 0.0
		var dist := to.length()
		if dist < LOOK_DIST and dist > 0.3 and not _still:
			h.rotation.y = lerp_angle(h.rotation.y, atan2(to.x, to.z), 1.0 - exp(-4.0 * delta))
		p["anim_t"] = float(p["anim_t"]) + delta
		if float(p["bubble_t"]) > 0.0:
			h.play("talk")
		else:
			h.play("idle")
		var bub: Label3D = p["bubble"]
		p["bubble_t"] = maxf(0.0, float(p["bubble_t"]) - delta)
		bub.modulate.a = clampf(float(p["bubble_t"]), 0.0, 1.0)
		if p["ball"]:
			_ball(p, pl, delta)


## Pallone: chi ci passa vicino lo calcia nella direzione in cui va; se finisce lontano, dopo un po' torna ai piedi.
func _ball(p: Dictionary, pl: Node3D, delta: float) -> void:
	var b: RigidBody3D = p["ball"]
	var d := b.global_position - pl.global_position
	d.y = 0.0
	var v: Vector3 = pl.get("velocity") if "velocity" in pl else Vector3.ZERO
	v.y = 0.0
	if d.length() < 0.55 and v.length() > 1.0 and absf(b.global_position.y - pl.global_position.y) < 1.0:
		var dir := (d.normalized() + v.normalized()).normalized()
		var power := clampf(v.length() * 1.6, 3.0, 14.0)
		b.linear_velocity = dir * power + Vector3.UP * power * 0.25
		if randf() < 0.5:
			_say(p, ICONE[p["id"]]["kick_lines"].pick_random())
	var home: Vector3 = p["home"]
	if b.global_position.distance_to(home) > 12.0 or b.global_position.y < home.y - 5.0:
		p["ball_away_t"] = float(p["ball_away_t"]) + delta
		if float(p["ball_away_t"]) > 15.0:
			p["ball_away_t"] = 0.0
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO
			b.global_position = home + Vector3(0.35, BALL_R + 0.3, 0.45)
	else:
		p["ball_away_t"] = 0.0


func _say(p: Dictionary, text: String) -> void:
	var bub: Label3D = p["bubble"]
	bub.text = text
	p["bubble_t"] = 4.5


func _near(pos: Vector3) -> Dictionary:
	for p: Dictionary in _people:
		if (p["root"] as Node3D).global_position.distance_to(pos) < TALK_DIST:
			return p
	return {}


func hint(pos: Vector3) -> String:
	var p := _near(pos)
	return "" if p.is_empty() else "E / croce su: parla con %s" % ICONE[p["id"]]["name"]


## Con E vicino a un personaggio: dice la battuta successiva. Restituisce true se ha parlato.
func talk(pos: Vector3) -> bool:
	var p := _near(pos)
	if p.is_empty():
		return false
	var lines: Array = ICONE[p["id"]]["lines"]
	p["line_i"] = (int(p["line_i"]) + 1) % lines.size()
	_say(p, lines[p["line_i"]])
	return true
