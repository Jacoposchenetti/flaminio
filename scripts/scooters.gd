class_name Scooters
extends Node3D

## Monopattini elettrici in sharing, parcheggiati sui marciapiedi (stessi posti su tutti i PC: vengono dai
## posti auto lungo i cordoli, spostati sul marciapiede). F / Y per salire e scendere; ~25 km/h.
## In rete: chi sale lo "prende" (sparisce dagli altri PC) e dove scende lo lascia.

const RIDE_SPEED := 7.0  # m/s, circa 25 km/h
const COLORS := [Color(0.1, 0.75, 0.3), Color(0.95, 0.45, 0.1), Color(0.15, 0.15, 0.17), Color(0.9, 0.85, 0.1)]

static var _meshes := {}  # colore -> ArrayMesh

var list: Array[Node3D] = []


## Monopattino: pedana, ruote, piantone e manubrio. Locale: +Z avanti, appoggiato a terra.
static func mesh(color_i: int) -> ArrayMesh:
	if _meshes.has(color_i):
		return _meshes[color_i]
	var m := ArrayMesh.new()
	var body := StandardMaterial3D.new()
	body.albedo_color = COLORS[color_i % COLORS.size()]
	body.metallic = 0.3
	body.roughness = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.06, 0.06, 0.07)
	dark.roughness = 0.8
	var parts_body := []
	var deck := BoxMesh.new()
	deck.size = Vector3(0.18, 0.06, 0.62)
	parts_body.append([deck, Transform3D(Basis(), Vector3(0, 0.12, 0))])
	var stem := CylinderMesh.new()
	stem.top_radius = 0.022
	stem.bottom_radius = 0.028
	stem.height = 1.0
	stem.radial_segments = 8
	parts_body.append([stem, Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(0, 0.6, 0.38))])
	var lamp := BoxMesh.new()
	lamp.size = Vector3(0.08, 0.05, 0.04)
	parts_body.append([lamp, Transform3D(Basis(), Vector3(0, 0.95, 0.5))])
	_merge(parts_body, body, m)
	var parts_dark := []
	var bar := CylinderMesh.new()
	bar.top_radius = 0.016
	bar.bottom_radius = 0.016
	bar.height = 0.5
	bar.radial_segments = 6
	parts_dark.append([bar, Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0, 1.08, 0.49))])
	for z: float in [0.36, -0.3]:
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.1
		wheel.bottom_radius = 0.1
		wheel.height = 0.05
		wheel.radial_segments = 12
		parts_dark.append([wheel, Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0, 0.1, z))])
	_merge(parts_dark, dark, m)
	_meshes[color_i] = m
	return m


static func _merge(parts: Array, mat: Material, m: ArrayMesh) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Array in parts:
		st.append_from(p[0], 0, p[1])
	st.set_material(mat)
	st.commit(m)


static func make_node(color_i: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(color_i)
	mi.visibility_range_end = 150.0
	return mi


func setup(city: CityBuilder) -> void:
	# Un posto auto ogni tanto, spostato di 2,2 m verso il marciapiede (oltre il cordolo, prima del passeggio).
	var i := 0
	for k in range(3, city.parking.size(), 14):
		var xf: Transform3D = city.parking[k]
		var side := -xf.basis.x.normalized()  # -X dell'auto parcheggiata guarda il cordolo
		var p := xf.origin + side * 2.2
		p.y = maxf(city.height_at(p.x, p.z), 0.0) + 0.06
		var n := make_node(i % COLORS.size())
		n.set_meta("id", i)
		n.set_meta("color", i % COLORS.size())
		add_child(n)
		n.global_position = p
		n.rotation.y = xf.basis.get_euler().y + fposmod(float(k) * 0.37, 0.5) - 0.25  # lungo la strada, un po' storti
		list.append(n)
		i += 1


## Monopattino libero più vicino entro max_dist, o null.
func nearest(pos: Vector3, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for n in list:
		if not n.visible:
			continue
		var d := n.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = n
	return best


func by_id(id: int) -> Node3D:
	return list[id] if id >= 0 and id < list.size() else null


## Qualcuno (su questo o su un altro PC) ci è salito: sparisce da terra.
func take(id: int) -> void:
	var n := by_id(id)
	if n:
		n.visible = false


## Lasciato in pos con direzione yaw.
func drop(id: int, pos: Vector3, yaw: float) -> void:
	var n := by_id(id)
	if n:
		n.global_position = pos
		n.rotation.y = yaw
		n.visible = true
		n.set_meta("moved", true)
