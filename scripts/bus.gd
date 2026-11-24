class_name Bus
extends RefCounted

## Autobus ATAC da 12 metri, fatto di forme semplici come il resto del gioco: carrozzeria rossa, fascia dei
## finestrini scura, tetto chiaro, porte sul lato destro, scritta ATAC sui fianchi e numero di linea davanti e dietro.
## Locale: +Z avanti (muso), -X lato destro (porte), appoggiato a terra.

const LOOK := 1000  # aspetto in rete: LOOK + indice della linea
const SIZE := Vector3(2.55, 2.9, 12.0)
## Numeri di linea mostrati sul display (linee romane; il percorso nel gioco è libero).
const LINES := ["910", "53", "982", "168", "223", "226", "628", "911"]

static var _body: ArrayMesh


static func _mat(c: Color, metal := 0.2, rough := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


static func _merge(parts: Array, mat: Material, m: ArrayMesh) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Array in parts:
		var mesh: Mesh
		if p[0] is Vector3:
			var box := BoxMesh.new()
			box.size = p[0]
			mesh = box
		else:
			mesh = p[0]
		st.append_from(mesh, 0, p[1])
	st.set_material(mat)
	st.commit(m)


## Carrozzeria condivisa da tutti gli autobus.
static func body_mesh() -> ArrayMesh:
	if _body:
		return _body
	var m := ArrayMesh.new()
	var w := SIZE.x
	var l := SIZE.z
	var y0 := 0.3  # sotto c'è lo spazio delle ruote
	var h := SIZE.y
	var t := func(p: Vector3) -> Transform3D: return Transform3D(Basis(), p)
	# Rosso ATAC: fiancate basse e montanti.
	_merge([
		[Vector3(w, 1.05, l), t.call(Vector3(0, y0 + 0.525, 0))],
		[Vector3(w, 0.25, l), t.call(Vector3(0, y0 + h - 0.45, 0))],
		# Montanti: agli angoli (lasciano vedere parabrezza e lunotto) e due a metà fiancata.
		[Vector3(0.18, 1.5, 0.3), t.call(Vector3(w * 0.5 - 0.08, y0 + 1.8, l * 0.5 - 0.14))],
		[Vector3(0.18, 1.5, 0.3), t.call(Vector3(-w * 0.5 + 0.08, y0 + 1.8, l * 0.5 - 0.14))],
		[Vector3(0.18, 1.5, 0.3), t.call(Vector3(w * 0.5 - 0.08, y0 + 1.8, -l * 0.5 + 0.14))],
		[Vector3(0.18, 1.5, 0.3), t.call(Vector3(-w * 0.5 + 0.08, y0 + 1.8, -l * 0.5 + 0.14))],
		[Vector3(w + 0.01, 1.5, 0.25), t.call(Vector3(0, y0 + 1.8, 1.5))],
		[Vector3(w + 0.01, 1.5, 0.25), t.call(Vector3(0, y0 + 1.8, -2.0))],
	], _mat(Color(0.72, 0.08, 0.07), 0.35, 0.35), m)
	# Vetri: fascia dei finestrini, parabrezza e lunotto (la scatola arriva fino a muso e coda).
	_merge([
		[Vector3(w - 0.02, 1.5, l + 0.02), t.call(Vector3(0, y0 + 1.8, 0))],
	], _mat(Color(0.05, 0.07, 0.09), 0.4, 0.08), m)
	# Tetto chiaro con i condizionatori.
	_merge([
		[Vector3(w, 0.2, l), t.call(Vector3(0, y0 + h - 0.23, 0))],
		[Vector3(1.6, 0.25, 2.6), t.call(Vector3(0, y0 + h, -1.5))],
	], _mat(Color(0.88, 0.88, 0.86), 0.1, 0.6), m)
	# Porte (lato destro) e paraurti grigi.
	_merge([
		[Vector3(0.04, 2.3, 1.1), t.call(Vector3(-w * 0.5 - 0.01, y0 + 1.15, l * 0.5 - 1.1))],
		[Vector3(0.04, 2.3, 1.2), t.call(Vector3(-w * 0.5 - 0.01, y0 + 1.15, 0.2))],
		[Vector3(0.04, 2.3, 1.2), t.call(Vector3(-w * 0.5 - 0.01, y0 + 1.15, -3.6))],
		[Vector3(w + 0.04, 0.3, 0.12), t.call(Vector3(0, y0 + 0.15, l * 0.5))],
		[Vector3(w + 0.04, 0.3, 0.12), t.call(Vector3(0, y0 + 0.15, -l * 0.5))],
	], _mat(Color(0.35, 0.37, 0.39), 0.5, 0.4), m)
	# Ruote.
	var wheels := []
	for z: float in [l * 0.5 - 2.3, -l * 0.5 + 3.0]:
		for x: float in [w * 0.5 - 0.15, -w * 0.5 + 0.15]:
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 0.3
			c.radial_segments = 14
			wheels.append([c, Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(x, 0.5, z))])
	_merge(wheels, _mat(Color(0.05, 0.05, 0.05), 0.0, 0.9), m)
	# Fanali.
	_merge([
		[Vector3(0.35, 0.18, 0.05), t.call(Vector3(0.85, y0 + 0.75, l * 0.5 + 0.03))],
		[Vector3(0.35, 0.18, 0.05), t.call(Vector3(-0.85, y0 + 0.75, l * 0.5 + 0.03))],
	], _mat(Color(1, 0.97, 0.85), 0.0, 0.2), m)
	_body = m
	return m


## Autobus completo: carrozzeria più scritte (ATAC sui fianchi, linea e destinazione sul display).
static func make(line: int) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = body_mesh()
	mi.visibility_range_end = 400.0
	root.add_child(mi)
	var y0 := 0.3
	for side: float in [1.0, -1.0]:
		var atac := Label3D.new()
		atac.text = "ATAC"
		atac.font_size = 96
		atac.outline_size = 0
		atac.pixel_size = 0.006
		atac.modulate = Color(1, 1, 1)
		atac.position = Vector3(side * (SIZE.x * 0.5 + 0.02), y0 + 0.6, -1.0)
		atac.rotation.y = PI / 2 * side
		atac.visibility_range_end = 120.0
		root.add_child(atac)
	var num: String = LINES[line % LINES.size()]
	var front := Label3D.new()
	front.text = num
	front.font_size = 48
	front.pixel_size = 0.006
	front.outline_size = 0
	front.modulate = Color(1.0, 0.6, 0.1)
	front.position = Vector3(0, y0 + SIZE.y - 0.45, SIZE.z * 0.5 + 0.02)
	front.visibility_range_end = 120.0
	root.add_child(front)
	var back := front.duplicate() as Label3D
	back.text = num
	back.position = Vector3(0, y0 + SIZE.y - 0.45, -SIZE.z * 0.5 - 0.02)
	back.rotation.y = PI
	root.add_child(back)
	return root
