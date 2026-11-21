class_name CityBuilder
extends Node3D

## Costruisce il quartiere da data/city.json e data/heights.bin (generati da tools/convert_osm.py).
## X verso est, Z verso sud, metri. Collisioni: strato 1 = terreno ed edifici, strato 2 = alberi.

const CHUNK := 250.0
const NAME_CELL := 64.0
const Y_AREA := 0.025
const Y_PLAZA := 0.035
const Y_FOOT := 0.045
const Y_ROAD := 0.06
const Y_TRAM := 0.075
const FLOOR_H := 3.2
const BAY_W := 3.4
const NEAR_RANGE := 260.0
const TREE_NEAR := 120.0  # entro questa distanza gli alberi hanno tutti i rami e i ciuffi
const TERRAIN_CHUNK := 64  # celle per blocco di terreno (128 m)
const TERRAIN_NEAR := 380.0  # oltre questa distanza i blocchi di terreno passano alla maglia leggera  # oltre questa distanza alberi, balconi e lampioni passano alla versione semplice
const AREA_COLORS := {
	"green": Color(0.42, 0.55, 0.28),
	"wood": Color(0.33, 0.45, 0.22),
	"pitch": Color(0.36, 0.6, 0.3),
	"play": Color(0.5, 0.48, 0.3),
}

var data: Dictionary
var heights := PackedFloat32Array()
var relief := PackedFloat32Array()  # rilievo senza il Tevere scavato (strade livellate, palazzi in piano)
var hmap_w := 0
var hmap_h := 0
var cell := 2.0
var origin := Vector2.ZERO  # angolo nord-ovest (x, z)
var bbox := Rect2()
var spawn := Vector3.ZERO
var _names := {}  # Vector2i -> Array di [Vector2, Vector2, String]
var parking: Array[Transform3D] = []  # posti auto lungo i cordoli (davanti dell'auto = +Z locale)
var _stone_mat: StandardMaterial3D
var water_y := -10.5  # pelo dell'acqua del Tevere (da city.json)
var _bridge_polys: Array[PackedVector2Array] = []
var street_cells := {}
var civic_spots: Array = []  # [posizione della targa, normale, numero, via] (prova --civico=n)
var _facades := {}  # cella di 32 m -> [[lati del palazzo, quota del piano terra, centro], ...]  # Vector2i(cella di 4 m) -> 2 carreggiata, 1 marciapiede (vedi _build_roads)
var venues: Array = []  # locali (bar, farmacie, armerie) con l'interno: vedi venues.gd
var lamp_points := PackedVector3Array()  # dove sta la lampada di ogni lampione (per le luci di notte)
var lamp_glass: StandardMaterial3D  # vetro dei lampioni: si accende di notte
var venue_rooms: Array = []  # per ogni locale: posizioni di bancone, commesso, ingresso
var enterables: Array = []  # [x, z, nome, "enter"] davanti alla porta dei palazzi esplorabili
var _interior_picks: Array = []


class Acc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

	## Aggiunge un triangolo orientato in modo che la faccia visibile guardi verso nrm.
	func tri(
		a: Vector3, b: Vector3, d: Vector3, nrm: Vector3, col: Color,
		ua: Vector2, ub: Vector2, ud: Vector2, u2a: Vector2, u2b := Vector2.INF, u2d := Vector2.INF
	) -> void:
		if u2b == Vector2.INF:
			u2b = u2a
		if u2d == Vector2.INF:
			u2d = u2a
		if (d - a).cross(b - a).dot(nrm) < 0.0:
			var t := b
			b = d
			d = t
			var tu := ub
			ub = ud
			ud = tu
			var t2 := u2b
			u2b = u2d
			u2d = t2
		v.append_array([a, b, d])
		n.append_array([nrm, nrm, nrm])
		c.append_array([col, col, col])
		uv.append_array([ua, ub, ud])
		uv2.append_array([u2a, u2b, u2d])

	## Quadrilatero a-b-d-e (in giro). u2 opzionali per vertice.
	func quad(
		a: Vector3, b: Vector3, d: Vector3, e: Vector3, nrm: Vector3, col: Color,
		ua: Vector2, ub: Vector2, ud: Vector2, ue: Vector2, u2: Vector2,
		u2b := Vector2.INF, u2d := Vector2.INF, u2e := Vector2.INF
	) -> void:
		if u2b == Vector2.INF:
			u2b = u2
			u2d = u2
			u2e = u2
		tri(a, b, d, nrm, col, ua, ub, ud, u2, u2b, u2d)
		tri(a, d, e, nrm, col, ua, ud, ue, u2, u2d, u2e)

	func mesh(mat: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, mat)
		return m


func build() -> void:
	var t0 := Time.get_ticks_msec()
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/city.json"))
	cell = data["cell"]
	hmap_w = int(data["hmap_size"][0])
	hmap_h = int(data["hmap_size"][1])
	heights = FileAccess.get_file_as_bytes("res://data/heights.bin").to_float32_array()
	if FileAccess.file_exists("res://data/relief.bin"):
		relief = FileAccess.get_file_as_bytes("res://data/relief.bin").to_float32_array()
	else:  # dati vecchi, quartiere piatto: il rilievo è zero dove non c'è il fiume
		relief.resize(heights.size())
		relief.fill(0.0)
	var bb: Array = data["bbox_m"]
	origin = Vector2(bb[0], bb[1])
	bbox = Rect2(origin, Vector2(bb[2] - bb[0], bb[3] - bb[1]))
	water_y = data.get("water_y", -10.5)
	for b: Dictionary in data.get("bridges", []):
		_bridge_polys.append(_pts(b["p"]))
	var sp: Array = data["spawn"]
	spawn = Vector3(sp[0], 0.0, sp[1])
	spawn.y = surface_at(spawn.x, spawn.z) + 1.0
	_interior_picks = Interiors.pick(data, spawn)
	Venues.ground = surface_at
	venues = Venues.pick(data, spawn)
	_stone_mat = StandardMaterial3D.new()
	_stone_mat.albedo_texture = TexLib.tex("Concrete034", "color")
	_stone_mat.albedo_color = Color(0.95, 0.9, 0.8)
	_stone_mat.normal_enabled = true
	_stone_mat.normal_texture = TexLib.tex("Concrete034", "normal")
	_stone_mat.uv1_triplanar = true
	_stone_mat.uv1_scale = Vector3(0.4, 0.4, 0.4)
	_stone_mat.roughness = 0.8
	var steps := [_build_terrain, _build_areas, _build_roads, _build_buildings, _build_civici, _build_landmarks, _build_trees, _build_bounds]
	for step: Callable in steps:
		var ts := Time.get_ticks_msec()
		step.call()
		if OS.is_debug_build() and "--timing" in OS.get_cmdline_user_args():
			print("  %s: %d ms" % [step.get_method(), Time.get_ticks_msec() - ts])
	print("Flaminio costruito in %d ms" % (Time.get_ticks_msec() - t0))
	if "--timing" in OS.get_cmdline_user_args():
		print("esplorabili: ", enterables)
		var per := {}
		for vn: Dictionary in venues:
			per[vn["kind"]] = per.get(vn["kind"], 0) + 1
		print("locali: ", per, " ", venues.map(func(vn: Dictionary) -> String: return "%s@%d,%d" % [vn["name"], int((vn["a"] as Vector2).x), int((vn["a"] as Vector2).y)]))


func _build_landmarks() -> void:
	LandmarkBuilder.new(self).build()
	for vn: Dictionary in venues:
		venue_rooms.append(Venues.build_room(self, vn))
	var ib := Interiors.new(self)
	for b: Dictionary in _interior_picks:
		enterables.append(ib.build(b))


## Il punto è su un ponte con pianta (man_made=bridge)? Lì impalcato e parapetti li fa LandmarkBuilder.
func on_bridge(p: Vector2) -> bool:
	for poly in _bridge_polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


## Il punto è sopra l'acqua del fiume (fondale più basso del pelo dell'acqua)?
func over_river(x: float, z: float) -> bool:
	return height_at(x, z) < water_y - 0.5


## Quota del terreno (interpolazione bilineare del rilievo): fondo del Tevere e banchine compresi.
func height_at(x: float, z: float) -> float:
	return _sample(heights, x, z)


## Quota del rilievo senza il Tevere: dove sta la città (sopra il fiume: dove passano ponti e strade).
func relief_at(x: float, z: float) -> float:
	return _sample(relief, x, z)


## Quota su cui si cammina e si guida fuori dalle banchine: il terreno, ma mai sotto il livello dei ponti.
func surface_at(x: float, z: float) -> float:
	return maxf(height_at(x, z), relief_at(x, z))


## Quanto il Tevere scava sotto la città in quel punto (0 fuori dal fiume e dalle banchine, negativo dentro).
func carve_at(x: float, z: float) -> float:
	return height_at(x, z) - relief_at(x, z)


## Orientamento di un mezzo appoggiato al terreno (inclinato su salite e discese), con il muso verso yaw.
func ground_basis(x: float, z: float, yaw: float, half_len := 2.0, half_w := 0.9) -> Basis:
	var f := Vector3(sin(yaw), 0.0, cos(yaw))
	var r := Vector3(f.z, 0.0, -f.x)
	f.y = (surface_at(x + f.x * half_len, z + f.z * half_len) - surface_at(x - f.x * half_len, z - f.z * half_len)) / (2.0 * half_len)
	r.y = (surface_at(x + r.x * half_w, z + r.z * half_w) - surface_at(x - r.x * half_w, z - r.z * half_w)) / (2.0 * half_w)
	var up := r.cross(f).normalized()
	if up.y < 0.0:
		up = -up
	var fwd := (f - up * f.dot(up)).normalized()
	return Basis(up.cross(fwd), up, fwd).orthonormalized()


## Quota della maglia del terreno com'è disegnata da vicino (un vertice per cella, vedi _build_terrain): dentro
## una cella il triangolo può stare un filo sopra l'interpolazione bilineare. Strade e cordoli non scendono sotto.
func mesh_top_at(x: float, z: float) -> float:
	var nx := hmap_w - 1
	var nz := hmap_h - 1
	var sx := cell
	var sz := cell
	var fx := clampf((x - origin.x) / sx, 0.0, nx - 0.001)
	var fz := clampf((z - origin.y) / sz, 0.0, nz - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var x0 := origin.x + ix * sx
	var z0 := origin.y + iz * sz
	var h00 := height_at(x0, z0)
	var h10 := height_at(x0 + sx, z0)
	var h01 := height_at(x0, z0 + sz)
	var h11 := height_at(x0 + sx, z0 + sz)
	# Non so da che parte la PlaneMesh taglia il quadrato: prendo il più alto dei due modi.
	var d1 := h00 + (h10 - h00) * tx + (h11 - h10) * tz if tx > tz else h00 + (h01 - h00) * tz + (h11 - h01) * tx
	var d2 := h00 + (h10 - h00) * tx + (h01 - h00) * tz if tx + tz < 1.0 else h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)
	return maxf(d1, d2)


## Quota a cui appoggiare strade, vialetti e cordoli: il terreno, mai sotto la maglia disegnata.
func road_ground(x: float, z: float, keep_up: bool) -> float:
	return maxf(surface_at(x, z) if keep_up else height_at(x, z), mesh_top_at(x, z))


## Quota di una sezione di carreggiata (in piano in larghezza): nemmeno ai bordi la maglia del terreno la copre.
func _road_y(p: Vector2, off: Vector2, keep_up: bool) -> float:
	return maxf(road_ground(p.x, p.y, keep_up), maxf(mesh_top_at(p.x + off.x, p.y + off.y), mesh_top_at(p.x - off.x, p.y - off.y)))


func _sample(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x - origin.x) / cell, 0.0, hmap_w - 1.001)
	var fz := clampf((z - origin.y) / cell, 0.0, hmap_h - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * hmap_w + ix
	var a := lerpf(arr[i], arr[i + 1], tx)
	var b := lerpf(arr[i + hmap_w], arr[i + hmap_w + 1], tx)
	return lerpf(a, b, tz)


## Nome della via più vicina entro max_dist metri, o "".
func street_name(pos: Vector3, max_dist := 30.0) -> String:
	var p := Vector2(pos.x, pos.z)
	var key := Vector2i(floori(p.x / NAME_CELL), floori(p.y / NAME_CELL))
	var best := ""
	var best_d := max_dist
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for seg: Array in _names.get(key + Vector2i(dx, dz), []):
				var q := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])
				var d := p.distance_to(q)
				if d < best_d:
					best_d = d
					best = seg[2]
	return best


func _pts(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(flat.size() / 2)
	for i in out.size():
		out[i] = Vector2(flat[i * 2], flat[i * 2 + 1])
	return out


func _chunk_key(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))


func _add_mesh(mesh: Mesh, node_name: String, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	add_child(mi)
	return mi


func _add_trimesh_body(faces: PackedVector3Array, node_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## MultiMesh divisi per riquadro, con distanza di visibilità (begin/end) per i livelli di dettaglio.
func _add_multimesh_chunks(mesh: Mesh, by_chunk: Dictionary, node_name: String, vis_begin: float, vis_end: float, shadows := true, shadow_only := false) -> void:
	for key: Vector2i in by_chunk:
		var list: Array = by_chunk[key]
		if list.is_empty():
			continue
		# Il nodo sta al centro del riquadro: la distanza di visibilità si misura da lì.
		var center := Vector3((key.x + 0.5) * CHUNK, 0, (key.y + 0.5) * CHUNK)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			var xf: Transform3D = list[i]
			xf.origin -= center
			mm.set_instance_transform(i, xf)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [node_name, key.x, key.y]
		mmi.multimesh = mm
		mmi.position = center
		mmi.visibility_range_begin = vis_begin
		mmi.visibility_range_end = vis_end
		mmi.visibility_range_begin_margin = 10.0 if vis_begin > 0.0 else 0.0
		mmi.visibility_range_end_margin = 10.0 if vis_end > 0.0 else 0.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if not shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif shadow_only:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(mmi)


func _push(by_chunk: Dictionary, xf: Transform3D) -> void:
	var key := _chunk_key(Vector2(xf.origin.x, xf.origin.z))
	if not by_chunk.has(key):
		by_chunk[key] = []
	by_chunk[key].append(xf)


# --- Terreno e Tevere -------------------------------------------------------------------------


func _build_terrain() -> void:
	var img := Image.create_from_data(hmap_w, hmap_h, false, Image.FORMAT_RF, heights.to_byte_array())
	var rimg := Image.create_from_data(hmap_w, hmap_h, false, Image.FORMAT_RF, relief.to_byte_array())
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("heights", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("relief_map", ImageTexture.create_from_image(rimg))
	mat.set_shader_parameter("origin", origin - Vector2(cell, cell) * 0.5)
	mat.set_shader_parameter("extent", Vector2(hmap_w, hmap_h) * cell)
	mat.set_shader_parameter("ground_albedo", TexLib.tex("Concrete034", "color"))
	mat.set_shader_parameter("ground_normal", TexLib.tex("Concrete034", "normal"))
	mat.set_shader_parameter("grass_albedo", TexLib.tex("Grass004", "color"))
	mat.set_shader_parameter("grass_normal", TexLib.tex("Grass004", "normal"))
	var cover := _load_cover()
	if cover:
		var cs: Array = data["cover_size"]
		mat.set_shader_parameter("cover", cover)
		mat.set_shader_parameter("cover_origin", bbox.position)
		mat.set_shader_parameter("cover_extent", Vector2(float(cs[0]), float(cs[1])))
		mat.set_shader_parameter("has_cover", true)
	var size := Vector2(hmap_w - 1, hmap_h - 1) * cell
	var center := origin + size * 0.5
	# Terreno a blocchi da TERRAIN_CHUNK celle: vicino un vertice per cella (la stessa maglia della collisione,
	# così i piedi non affondano e i bordi delle strade restano netti), lontano uno ogni 4 celle. La versione
	# lontana deborda di 8 m e sta 15 cm più in basso: copre le fessure tra blocchi vicini e lontani.
	var coarse_mat: ShaderMaterial = mat.duplicate()
	coarse_mat.set_shader_parameter("lower", 0.15)
	var holder := Node3D.new()
	holder.name = "Terreno"
	add_child(holder)
	var meshes := {}
	var near := TERRAIN_NEAR
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--terrain_near="):  # prova: distanza della maglia fine
			near = float(arg.split("=")[1])
	var cells_x := hmap_w - 1
	var cells_z := hmap_h - 1
	for cz in range(0, cells_z, TERRAIN_CHUNK):
		for cx in range(0, cells_x, TERRAIN_CHUNK):
			var nx := mini(TERRAIN_CHUNK, cells_x - cx)
			var nz := mini(TERRAIN_CHUNK, cells_z - cz)
			for lod in 2:
				var key := Vector3i(nx, nz, lod)
				if not meshes.has(key):
					var pm := PlaneMesh.new()
					if lod == 0:
						pm.size = Vector2(nx, nz) * cell
						pm.subdivide_width = nx - 1
						pm.subdivide_depth = nz - 1
						pm.material = mat
					else:
						pm.size = Vector2(nx, nz) * cell + Vector2(16, 16)
						pm.subdivide_width = maxi(0, ceili(pm.size.x / (cell * 4.0)) - 1)
						pm.subdivide_depth = maxi(0, ceili(pm.size.y / (cell * 4.0)) - 1)
						pm.material = coarse_mat
					meshes[key] = pm
				var mi := MeshInstance3D.new()
				mi.mesh = meshes[key]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.position = Vector3(origin.x + (cx + nx * 0.5) * cell, 0, origin.y + (cz + nz * 0.5) * cell)
				mi.extra_cull_margin = 64.0  # il terreno sale fino a +45 m (colline) e scende a -14 (Tevere)
				if lod == 0:
					mi.visibility_range_end = near
					mi.visibility_range_end_margin = 10.0
				else:
					mi.visibility_range_begin = near
					mi.visibility_range_begin_margin = 10.0
				holder.add_child(mi)

	# Cornice di terreno attorno alla mappa, per non vedere il vuoto all'orizzonte.
	var omat := StandardMaterial3D.new()
	omat.albedo_texture = TexLib.tex("Concrete034", "color")
	omat.albedo_color = Color(0.75, 0.72, 0.66)
	omat.uv1_triplanar = true
	omat.uv1_scale = Vector3(0.3, 0.3, 0.3)
	# Il bordo segue il rilievo (a est le colline) e si allunga piano verso l'orizzonte.
	var far := 4000.0
	var lo := origin
	var hi := origin + size
	var ring := PackedVector2Array()
	var step := 20.0
	var x := lo.x
	while x < hi.x:
		ring.append(Vector2(x, lo.y))
		x += step
	var zz := lo.y
	while zz < hi.y:
		ring.append(Vector2(hi.x, zz))
		zz += step
	x = hi.x
	while x > lo.x:
		ring.append(Vector2(x, hi.y))
		x -= step
	zz = hi.y
	while zz > lo.y:
		ring.append(Vector2(lo.x, zz))
		zz -= step
	var mid := (lo + hi) * 0.5
	var skirt := Acc.new()
	var zero := Vector2.ZERO
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var ya := relief_at(a.x, a.y) - 0.02
		var yb := relief_at(b.x, b.y) - 0.02
		var oa := a + (a - mid).normalized() * far
		var ob := b + (b - mid).normalized() * far
		skirt.quad(Vector3(a.x, ya, a.y), Vector3(oa.x, ya * 0.5, oa.y), Vector3(ob.x, yb * 0.5, ob.y), Vector3(b.x, yb, b.y),
			Vector3.UP, Color.WHITE, zero, zero, zero, zero, zero)
	_add_mesh(skirt.mesh(omat), "Dintorni", false)

	# Collisione: rilievo scalato in modo uniforme (le altezze vanno divise per la cella).
	var shape := HeightMapShape3D.new()
	shape.map_width = hmap_w
	shape.map_depth = hmap_h
	# Le altezze già divise per la cella le prepara tools/convert_osm.py (più veloce che farlo qui).
	shape.map_data = FileAccess.get_file_as_bytes("res://data/heights_phys.bin").to_float32_array()
	var body := StaticBody3D.new()
	body.name = "TerrenoFisico"
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(cell, cell, cell)
	body.add_child(cs)
	body.position = Vector3(center.x, 0, center.y)
	add_child(body)


func _road_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/road.gdshader")
	TexLib.bind(mat, "asphalt", "Asphalt031")
	mat.set_shader_parameter("cobble_albedo", TexLib.tex("PavingStones046", "color"))
	mat.set_shader_parameter("cobble_normal", TexLib.tex("PavingStones046", "normal"))
	mat.set_shader_parameter("path_albedo", TexLib.tex("Concrete034", "color"))
	mat.set_shader_parameter("path_normal", TexLib.tex("Concrete034", "normal"))
	return mat


## Coperture del suolo (data/cover_png.bin, PNG da convert_osm): prati e parchi disegnati nel terreno.
func _load_cover() -> ImageTexture:
	if not data.has("cover_size"):
		return null
	var bytes := FileAccess.get_file_as_bytes("res://data/cover_png.bin")
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _build_areas() -> void:
	var lawn_in_terrain := data.has("cover_size") and FileAccess.file_exists("res://data/cover_png.bin")
	var green := Acc.new()
	var plaza := Acc.new()
	var water := Acc.new()
	var far := Vector2(999, 999)
	for a: Dictionary in data["areas"]:
		var pts := _pts(a["p"])
		var idx := Geometry2D.triangulate_polygon(pts)
		if idx.is_empty():
			continue
		var kind: String = a["k"]
		if lawn_in_terrain and AREA_COLORS.has(kind):
			continue  # i prati li disegna il terreno (coperture)
		var y := Y_AREA
		var acc := green
		var col: Color = AREA_COLORS.get(kind, Color.WHITE)
		if kind == "plaza":
			acc = plaza
			y = Y_PLAZA
			col = Color(0.75, 2.0 / 32.0, 0)
		elif kind == "water":
			acc = water
			var c := pts[0]
			var river := carve_at(c.x, c.y) < -0.5 or (pts.size() > 60 and _mostly_river(pts))
			y = water_y if river else relief_at(c.x, c.y) + 0.25
		for i in range(0, idx.size(), 3):
			_area_tri(acc, pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]], y, kind == "water", col, far, 0)
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://shaders/grass.gdshader")
	gmat.set_shader_parameter("grass_albedo", TexLib.tex("Grass004", "color"))
	gmat.set_shader_parameter("grass_normal", TexLib.tex("Grass004", "normal"))
	if not green.v.is_empty():
		_add_mesh(green.mesh(gmat), "Verde", false)
		if "--timing" in OS.get_cmdline_user_args():
			print("  triangoli: verde %d, piazze %d" % [green.v.size() / 3, plaza.v.size() / 3])
	if not plaza.v.is_empty():
		_add_mesh(plaza.mesh(_road_material()), "Piazze", false)
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/water.gdshader")
	if not water.v.is_empty():
		_add_mesh(water.mesh(wmat), "Acqua", false)


## Triangolo di un'area (prato, piazza) adagiato sul terreno: si divide finché il rilievo è seguito bene.
func _area_tri(acc: Acc, a: Vector2, b: Vector2, c: Vector2, y: float, flat: bool, col: Color, far: Vector2, depth: int) -> void:
	if flat:
		acc.tri(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Vector3.UP, col, a, b, c, far)
		return
	var ha := height_at(a.x, a.y)
	var hb := height_at(b.x, b.y)
	var hc := height_at(c.x, c.y)
	var longest := maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a)))
	if depth < 6 and longest > 10.0:
		var m := (a + b + c) / 3.0
		var mab := (a + b) * 0.5
		var mbc := (b + c) * 0.5
		var mca := (c + a) * 0.5
		var ra := relief_at(a.x, a.y)
		var rb := relief_at(b.x, b.y)
		var rc := relief_at(c.x, c.y)
		var err := absf(relief_at(m.x, m.y) - (ra + rb + rc) / 3.0)
		err = maxf(err, absf(relief_at(mab.x, mab.y) - (ra + rb) * 0.5))
		err = maxf(err, absf(relief_at(mbc.x, mbc.y) - (rb + rc) * 0.5))
		err = maxf(err, absf(relief_at(mca.x, mca.y) - (rc + ra) * 0.5))
		if err > 0.3:
			_area_tri(acc, a, mab, mca, y, flat, col, far, depth + 1)
			_area_tri(acc, mab, b, mbc, y, flat, col, far, depth + 1)
			_area_tri(acc, mca, mbc, c, y, flat, col, far, depth + 1)
			_area_tri(acc, mab, mbc, mca, y, flat, col, far, depth + 1)
			return
	# In pendenza un filo più alto: il terreno (maglia di 4 m) non deve bucare il prato.
	var lift := y + (0.02 if maxf(ha, maxf(hb, hc)) - minf(ha, minf(hb, hc)) > 0.3 else 0.0)  # sempre sotto le strade
	var va := Vector3(a.x, ha + lift, a.y)
	var vb := Vector3(b.x, hb + lift, b.y)
	var vc := Vector3(c.x, hc + lift, c.y)
	var nrm := (vb - va).cross(vc - va).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	acc.tri(va, vb, vc, nrm if nrm.y > 0.2 else Vector3.UP, col, a, b, c, far)


func _mostly_river(pts: PackedVector2Array) -> bool:
	var n := 0
	for q in pts:
		if carve_at(q.x, q.y) < -0.5:
			n += 1
	return n * 2 > pts.size()


# --- Strade -----------------------------------------------------------------------------------


func _node_key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 100.0), roundi(p.y * 100.0))


func _build_roads() -> void:
	# Incroci: nodi da cui partono almeno tre tratti di strada carrabile.
	var degree := {}
	var half_w := {}
	for r: Dictionary in data["roads"]:
		if r["k"] != "road":
			continue
		var pts := _pts(r["p"])
		for i in pts.size():
			var k := _node_key(pts[i])
			degree[k] = degree.get(k, 0) + (1 if i == 0 or i == pts.size() - 1 else 2)
			half_w[k] = maxf(half_w.get(k, 0.0), float(r["w"]) * 0.5)

	var acc := Acc.new()
	var curbs := Acc.new()
	var lamps := {}
	var lamps_far := {}
	var bridge_body := StaticBody3D.new()
	bridge_body.name = "Ponti"
	bridge_body.collision_layer = 1
	add_child(bridge_body)
	var lamp_side := 1.0
	# Viadotti: calcestruzzo liscio grigio chiaro e piloni dove l'impalcato è alto da terra (non in mezzo alle
	# strade che passano sotto: per saperlo, una griglia a celle di 4 m delle carreggiate a terra).
	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_texture = TexLib.tex("Concrete034", "color")
	deck_mat.albedo_color = Color(0.78, 0.78, 0.76)
	deck_mat.normal_enabled = true
	deck_mat.normal_texture = TexLib.tex("Concrete034", "normal")
	deck_mat.normal_scale = 0.4
	deck_mat.uv1_triplanar = true
	deck_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
	deck_mat.roughness = 0.85
	# Celle di 4 m occupate da strade a terra: 2 carreggiata, 1 solo marciapiede/vialetto. Servono anche ai palazzi
	# (piano terra alla quota della via, _build_buildings).
	var road_cells := street_cells
	for r: Dictionary in data["roads"]:
		if int(r["b"]) == 1:
			continue
		var mark := 1 if r["k"] == "foot" else 2
		var rp := _pts(r["p"])
		var hw := float(r["w"]) * 0.5 + (1.0 if mark == 1 else 1.5)
		for i in range(1, rp.size()):
			var n := int(rp[i - 1].distance_to(rp[i]) / 2.0) + 1
			for k in n + 1:
				var q := rp[i - 1].lerp(rp[i], float(k) / n)
				for ox in range(floori((q.x - hw) / 4.0), floori((q.x + hw) / 4.0) + 1):
					for oz in range(floori((q.y - hw) / 4.0), floori((q.y + hw) / 4.0) + 1):
						road_cells[Vector2i(ox, oz)] = maxi(int(road_cells.get(Vector2i(ox, oz), 0)), mark)
	var pillars: Array[Transform3D] = []
	for r: Dictionary in data["roads"]:
		var pts := _pts(r["p"])
		var count := pts.size()
		if count < 2:
			continue
		var kind: String = r["k"]
		var w: float = r["w"]
		var code := 0.0
		var yoff := Y_ROAD
		if kind == "foot":
			code = 1.0
			yoff = Y_FOOT
		elif kind == "tram":
			code = 2.0
			yoff = Y_TRAM
		var is_bridge := int(r["b"]) == 1
		var deck: Array = r.get("y", []) if is_bridge else []  # quote dell'impalcato ai vertici (convert_osm)
		if deck.size() != count:
			deck = []
		var col := Color(code / 4.0, w / 32.0, 0)

		# Distanza (lungo la strada) dal bordo dell'incrocio precedente e da quello successivo.
		var seg_len := PackedFloat32Array()
		seg_len.resize(count)
		for i in range(1, count):
			seg_len[i] = pts[i].distance_to(pts[i - 1])
		var dp := PackedFloat32Array()
		var dn := PackedFloat32Array()
		dp.resize(count)
		dn.resize(count)
		var junction := func(i: int) -> bool:
			return kind == "road" and degree.get(_node_key(pts[i]), 0) >= 3
		var jr := func(i: int) -> float:
			return half_w.get(_node_key(pts[i]), w * 0.5) + 0.5
		for i in count:
			if junction.call(i):
				dp[i] = -jr.call(i)
			else:
				dp[i] = 999.0 if i == 0 else dp[i - 1] + seg_len[i]
		for i in range(count - 1, -1, -1):
			if junction.call(i):
				dn[i] = -jr.call(i)
			else:
				dn[i] = 999.0 if i == count - 1 else dn[i + 1] + seg_len[i + 1]

		var u := 0.0
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_u := 0.0
		var lamp_next := 14.0
		var pillar_next := 10.0
		for i in count:
			var p := pts[i]
			var d_in := (p - pts[i - 1]).normalized() if i > 0 else Vector2.ZERO
			var d_out := (pts[i + 1] - p).normalized() if i < count - 1 else Vector2.ZERO
			var n_in := Vector2(-d_in.y, d_in.x)
			var n_out := Vector2(-d_out.y, d_out.x)
			var m := (n_in + n_out).normalized()
			if m == Vector2.ZERO:
				m = n_out if n_out != Vector2.ZERO else n_in
			var ref := n_out if n_out != Vector2.ZERO else n_in
			var off := m * (w * 0.5) / maxf(m.dot(ref), 0.5)
			if i > 0:
				u += seg_len[i]
			# Carreggiate e ponti restano alla quota della città; i vialetti scendono in banchina.
			var keep_up := is_bridge or kind != "foot"
			var ground := _road_y(p, off, keep_up)
			if not deck.is_empty():
				ground = float(deck[i])
			var y := ground + yoff
			var l := Vector3(p.x + off.x, y, p.y + off.y)
			var rr := Vector3(p.x - off.x, y, p.y - off.y)
			if i > 0:
				var a := pts[i - 1]
				var length := seg_len[i]
				# UV2 per vertice: (dist. dall'incrocio precedente, dist. dal successivo).
				var s_a := Vector2(dp[i - 1], dn[i] + length)
				var s_b := Vector2(dp[i - 1] + length, dn[i])
				var pieces := 1 if is_bridge else _pieces_needed(a, p, keep_up, length)
				var pl := prev_l
				var pr := prev_r
				for k in range(1, pieces + 1):
					var t := float(k) / pieces
					var nl3 := prev_l.lerp(l, t)
					var nr3 := prev_r.lerp(rr, t)
					if k < pieces:
						var cq := a.lerp(p, t)
						nl3.y = _road_y(cq, off, keep_up) + yoff
						nr3.y = nl3.y
					var t0 := float(k - 1) / pieces
					acc.quad(
						pl, pr, nr3, nl3, Vector3.UP, col,
						Vector2(lerpf(prev_u, u, t0), 1), Vector2(lerpf(prev_u, u, t0), -1), Vector2(lerpf(prev_u, u, t), -1),
						Vector2(lerpf(prev_u, u, t), 1), s_a.lerp(s_b, t0), s_a.lerp(s_b, t0), s_a.lerp(s_b, t), s_a.lerp(s_b, t)
					)
					pl = nl3
					pr = nr3
				if is_bridge and not on_bridge((a + p) * 0.5):
					var ya := float(deck[i - 1]) if not deck.is_empty() else 0.0
					var yb := float(deck[i]) if not deck.is_empty() else 0.0
					_bridge_segment(bridge_body, Vector3(a.x, ya, a.y), Vector3(p.x, yb, p.y), w, deck_mat)
					while kind != "foot" and pillar_next < u:
						var s := pillar_next - (u - length)
						pillar_next += 24.0
						if s < 0.0:
							continue
						var t := s / length
						var q := a.lerp(p, t)
						var under := lerpf(ya, yb, t) - 1.15  # sotto l'impalcato
						var g := height_at(q.x, q.y)
						if under - g < 3.0 or over_river(q.x, q.y) or int(road_cells.get(Vector2i(floori(q.x / 4.0), floori(q.y / 4.0)), 0)) == 2:
							continue
						var side := Vector2(-(p - a).y, (p - a).x).normalized() * w * 0.28
						for sg: float in [1.0, -1.0]:
							var c2 := q + side * sg
							var hgt := under - g + 0.5
							pillars.append(Transform3D(Basis().scaled(Vector3(1, hgt, 1)), Vector3(c2.x, g - 0.5 + hgt * 0.5, c2.y)))
				elif kind == "road" and w >= 6.0 and length > 0.5:
					var s0 := maxf(0.0, 1.0 - dp[i - 1])
					var s1 := minf(length, length - maxf(0.0, 1.0 - dn[i]))
					if s1 - s0 > 0.3:
						var dir := (p - a) / length
						var nrm2 := Vector2(-dir.y, dir.x)
						for side in [1.0, -1.0]:
							_curb(curbs, a + dir * s0, a + dir * s1, nrm2 * side, w * 0.5)
					if w >= 7.0 and length > 12.0:
						_add_parking(a, p, length, dp[i - 1], dn[i], w, y - yoff)
					if w >= 8.0:
						# Lampioni ogni 30 m circa, alternati sui due lati.
						while lamp_next < u:
							var s := lamp_next - (u - length)
							if s >= 0.0 and minf(dp[i - 1] + s, dn[i] + length - s) > 3.0:
								var q := a + (p - a) * (s / length)
								var nrm3 := Vector2(-(p - a).y, (p - a).x).normalized() * lamp_side
								var pos2 := q + nrm3 * (w * 0.5 + 0.8)
								var face := -nrm3
								var basis := Basis(Vector3(face.x, 0, face.y), Vector3.UP, Vector3(-face.y, 0, face.x))
								var xf := Transform3D(basis.orthonormalized(), Vector3(pos2.x, surface_at(pos2.x, pos2.y), pos2.y))
								_push(lamps, xf)
								_push(lamps_far, xf)
								lamp_points.append(xf * Vector3(1.7, 7.9, 0.0))
								lamp_side = -lamp_side
							lamp_next += 30.0
			prev_l = l
			prev_r = rr
			prev_u = u
			# Raccordi rotondi alle estremità, per chiudere gli incroci.
			if kind != "tram" and (i == 0 or i == count - 1):
				var c := Vector3(p.x, y - 0.002, p.y)
				var far2 := Vector2(999, 999)
				for k in 8:
					var a0 := TAU * k / 8.0
					var a1 := TAU * (k + 1) / 8.0
					var e0 := c + Vector3(cos(a0), 0, sin(a0)) * w * 0.5
					var e1 := c + Vector3(cos(a1), 0, sin(a1)) * w * 0.5
					acc.tri(c, e0, e1, Vector3.UP, col, Vector2(u, 0.5), Vector2(u, 0.5), Vector2(u, 0.5), far2)
			if kind != "tram" and r["n"] != "" and i > 0:
				var key := Vector2i(floori((pts[i - 1].x + p.x) * 0.5 / NAME_CELL), floori((pts[i - 1].y + p.y) * 0.5 / NAME_CELL))
				if not _names.has(key):
					_names[key] = []
				_names[key].append([pts[i - 1], p, r["n"]])
	_add_mesh(acc.mesh(_road_material()), "Strade", false)
	if not pillars.is_empty():
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.6
		cyl.bottom_radius = 0.6
		cyl.height = 1.0
		cyl.radial_segments = 12
		cyl.rings = 1
		cyl.material = deck_mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cyl
		mm.instance_count = pillars.size()
		for i in pillars.size():
			mm.set_instance_transform(i, pillars[i])
			var cs := CollisionShape3D.new()
			var sh := CylinderShape3D.new()
			sh.radius = 0.6
			sh.height = pillars[i].basis.get_scale().y
			cs.shape = sh
			cs.position = pillars[i].origin
			bridge_body.add_child(cs)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "PiloniViadotti"
		mmi.multimesh = mm
		add_child(mmi)
	if "--timing" in OS.get_cmdline_user_args():
		print("  triangoli: strade %d, cordoli %d" % [acc.v.size() / 3, curbs.v.size() / 3])
	_add_mesh(curbs.mesh(_stone_mat), "Cordoli", false)
	var lamp_mesh := _lamp_mesh(true)
	_add_multimesh_chunks(lamp_mesh, lamps, "Lampioni", 0.0, NEAR_RANGE)
	_add_multimesh_chunks(_lamp_mesh(false), lamps_far, "LampioniLontani", NEAR_RANGE, 700.0)


## Posti auto in fila lungo il cordolo, lontano dagli incroci. Scelta deterministica (uguale per tutti in rete).
func _add_parking(a: Vector2, b: Vector2, length: float, d_prev: float, d_next: float, w: float, ground: float) -> void:
	var dir := (b - a) / length
	var nrm := Vector2(-dir.y, dir.x)
	var s := 8.0
	while s < length - 8.0:
		var h := fposmod(sin(a.x * 12.9898 + a.y * 78.233 + s * 3.17) * 43758.5453, 1.0)
		if h < 0.3 and d_prev + s > 10.0 and d_next + length - s > 10.0:
			var side := 1.0 if h < 0.15 else -1.0
			var q := a + dir * s + nrm * side * (w * 0.5 - 1.0)
			var fwd := dir * (1.0 if side > 0.0 else -1.0)  # nrm è il lato destro di dir: si parcheggia nel senso di marcia
			var basis := Basis(Vector3(fwd.y, 0, -fwd.x), Vector3.UP, Vector3(fwd.x, 0, fwd.y))
			var yaw := atan2(fwd.x, fwd.y)
			var c := a + dir * s
			var bs := ground_basis(q.x, q.y, yaw)
			# Niente posti sui tornanti in collina: l'auto finirebbe mezza dentro la scarpata.
			if bs.y.y > 0.985 and absf(surface_at(q.x, q.y) - surface_at(c.x, c.y)) < 0.2:
				parking.append(Transform3D(bs, Vector3(q.x, surface_at(q.x, q.y) + 0.05, q.y)))
		s += 6.5


## Pezzi (di ~3 m) in cui dividere un tratto perché segua il terreno: 1 se il profilo è già una retta.
func _pieces_needed(a: Vector2, b: Vector2, keep_up: bool, length: float) -> int:
	if length < 4.0:
		return 1
	var ha := road_ground(a.x, a.y, keep_up)
	var hb := road_ground(b.x, b.y, keep_up)
	var dev := 0.0
	for t: float in [0.25, 0.5, 0.75]:
		var q := a.lerp(b, t)
		var hq := road_ground(q.x, q.y, keep_up)
		dev = maxf(dev, absf(hq - lerpf(ha, hb, t)))
	# L'errore di un tratto dritto cala col quadrato dei pezzi: quanti ne servono per stare entro 4 cm.
	return 1 if dev < 0.04 else clampi(ceili(sqrt(dev / 0.04)), 1, maxi(1, ceili(length / 2.0)))


## Cordolo del marciapiede lungo un lato della carreggiata: alto 15 cm, largo 25; segue salite e discese.
func _curb(acc: Acc, a: Vector2, b: Vector2, side: Vector2, half: float) -> void:
	var nrm := Vector3(-side.x, 0, -side.y)
	var z := Vector2.ZERO
	var wc := Color.WHITE
	var pieces := _pieces_needed(a, b, true, a.distance_to(b))
	for k in pieces:
		var pa := a.lerp(b, float(k) / pieces)
		var pb := a.lerp(b, float(k + 1) / pieces)
		var ga := _road_y(pa, side * half, true)  # come la carreggiata accanto
		var gb := _road_y(pb, side * half, true)
		var inner_a := pa + side * half
		var inner_b := pb + side * half
		var outer_a := pa + side * (half + 0.25)
		var outer_b := pb + side * (half + 0.25)
		acc.quad(
			Vector3(inner_a.x, ga, inner_a.y), Vector3(inner_b.x, gb, inner_b.y),
			Vector3(inner_b.x, gb + 0.15, inner_b.y), Vector3(inner_a.x, ga + 0.15, inner_a.y), nrm, wc, z, z, z, z, z
		)
		acc.quad(
			Vector3(inner_a.x, ga + 0.15, inner_a.y), Vector3(inner_b.x, gb + 0.15, inner_b.y),
			Vector3(outer_b.x, gb + 0.15, outer_b.y), Vector3(outer_a.x, ga + 0.15, outer_a.y), Vector3.UP, wc, z, z, z, z, z
		)


## Lampione romano: palo alto con braccio verso la strada (+X locale).
func _lamp_mesh(detailed: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.12, 0.13, 0.12)
	metal.metallic = 0.6
	metal.roughness = 0.45
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.12
	pole.height = 8.5
	pole.radial_segments = 8 if detailed else 4
	pole.rings = 1
	_part(pole, Transform3D(Basis(), Vector3(0, 4.25, 0)), metal, mesh)
	var arm := BoxMesh.new()
	arm.size = Vector3(1.8, 0.08, 0.08)
	_part(arm, Transform3D(Basis(), Vector3(0.85, 8.35, 0)), metal, mesh)
	if detailed:
		var head := CylinderMesh.new()
		head.top_radius = 0.12
		head.bottom_radius = 0.38
		head.height = 0.3
		head.radial_segments = 10
		head.rings = 1
		_part(head, Transform3D(Basis(), Vector3(1.7, 8.2, 0)), metal, mesh)
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.95, 0.93, 0.85)
		glass.emission_enabled = true
		glass.emission = Color(1.0, 0.85, 0.6)
		glass.emission_energy_multiplier = 0.2
		lamp_glass = glass  # di notte lo accende DayNight
		var bulb := CylinderMesh.new()
		bulb.top_radius = 0.34
		bulb.bottom_radius = 0.3
		bulb.height = 0.08
		bulb.radial_segments = 10
		bulb.rings = 1
		_part(bulb, Transform3D(Basis(), Vector3(1.7, 8.02, 0)), glass, mesh)
	return mesh


## Impalcato e parapetti di un tratto di ponte, con collisione.
func _bridge_segment(body: StaticBody3D, a: Vector3, b: Vector3, w: float, mat: Material) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var mid := (a + b) * 0.5
	# Impalcato inclinato tra le due quote: asse x lungo il ponte, y la sua normale.
	var dx := (b - a).normalized()
	var dz := dx.cross(Vector3.UP).normalized()
	var dy := dz.cross(dx).normalized()
	var xf := Transform3D(Basis(dx, dy, dz), mid)
	var parts := [
		[Vector3(length + 0.4, 1.2, w + 0.6), Vector3(0, -0.55, 0)],
		[Vector3(length + 0.2, 1.1, 0.35), Vector3(0, 0.55, w * 0.5 + 0.12)],
		[Vector3(length + 0.2, 1.1, 0.35), Vector3(0, 0.55, -w * 0.5 - 0.12)],
	]
	for part: Array in parts:
		var size: Vector3 = part[0]
		var t := xf * Transform3D(Basis(), part[1])
		var box := BoxMesh.new()
		box.size = size
		box.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.transform = t
		add_child(mi)
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = t
		body.add_child(cs)


# --- Edifici ----------------------------------------------------------------------------------


func _build_buildings() -> void:
	var colors: Array = data["colors"]
	var chunks := {}
	var balconies := {}
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/building.gdshader")
	TexLib.bind(mat, "plaster", "Plaster001")
	mat.set_shader_parameter("stone_albedo", TexLib.tex("Travertine005", "color"))
	mat.set_shader_parameter("stone_normal", TexLib.tex("Travertine005", "normal"))
	mat.set_shader_parameter("roof_albedo", TexLib.tex("Concrete034", "color"))
	mat.set_shader_parameter("roof_normal", TexLib.tex("Concrete034", "normal"))
	var modern_mat := mat.duplicate() as ShaderMaterial
	modern_mat.set_shader_parameter("modern", true)
	var modern_chunks := {}
	var domes := Acc.new()
	var dome_mat := StandardMaterial3D.new()
	dome_mat.albedo_color = Color(0.5, 0.52, 0.55)  # cupole rivestite di piombo
	dome_mat.metallic = 0.6
	dome_mat.roughness = 0.4
	var bi := 0
	for b: Dictionary in data["buildings"]:
		bi += 1
		var pts := _pts(b["p"])
		if pts.size() < 3 or b.has("enter"):
			continue
		if LandmarkBuilder.in_maxxi(pts):
			continue  # al loro posto c'è il MAXXI fatto a mano (landmarks.gd)
		if Geometry2D.triangulate_polygon(pts).is_empty():
			# Pianta che si autointerseca: meglio il suo inviluppo convesso che muri al rovescio.
			pts = Geometry2D.convex_hull(pts)
			pts.remove_at(pts.size() - 1)
			if pts.size() < 3:
				continue
		var h: float = b["h"]
		var cc: Array = colors[int(b["c"])]
		var col := Color(cc[0], cc[1], cc[2])
		var center := Vector2.ZERO
		var area := 0.0
		for i in pts.size():
			var p := pts[i]
			var q := pts[(i + 1) % pts.size()]
			area += p.x * q.y - q.x * p.y
			center += p
		center /= pts.size()
		var ground := height_at(center.x, center.y)
		if not b.has("m"):
			# Il piano terra sta alla quota della strada più alta che tocca il palazzo (ingresso e negozi sul
			# marciapiede): prima, appoggiato alla strada più vicina o al terreno, poteva finire sotto il livello della
			# via con le vetrine mezze interrate. Sul lato in discesa il muro scende fino a terra (foot).
			var street := -INF
			for i in pts.size():
				var e0 := pts[i]
				var e1 := pts[(i + 1) % pts.size()]
				var n := int(e0.distance_to(e1) / 4.0) + 1
				for k in n + 1:
					var q := e0.lerp(e1, float(k) / n)
					var o := q + (q - center).normalized() * 3.0
					if street_cells.has(Vector2i(floori(o.x / 4.0), floori(o.y / 4.0))):
						street = maxf(street, surface_at(o.x, o.y))
			if street > ground + 0.3:
				ground = minf(street, ground + 6.0)
		var modern := false  # il MAXXI ora è fatto a mano; la vecchia caserma accanto è un palazzo normale
		var y0 := ground - 0.4 + float(b.get("m", 0.0))
		var foot := y0  # piede del muro: in discesa scende sotto il piano del palazzo
		if not b.has("m"):
			for q in pts:
				var o := q + (q - center).normalized() * 1.5
				foot = minf(foot, minf(height_at(q.x, q.y), surface_at(o.x, o.y)) - 0.4)
		var y1 := ground + h
		if not b.has("m") and h > 4.0:
			# Facciate per i numeri civici (_build_civici): lati, piano terra, centro.
			var fk := Vector2i(floori(center.x / 32.0), floori(center.y / 32.0))
			if not _facades.has(fk):
				_facades[fk] = []
			_facades[fk].append([pts, ground, center])
		var tall := h > 6.5 and not modern and not b.has("m")
		var key := _chunk_key(center)
		var target := modern_chunks if modern else chunks
		if not target.has(key):
			target[key] = Acc.new()
		var acc: Acc = target[key]
		var wall_h := y1 - y0
		var u2 := Vector2(wall_h, 0)
		var trim := Vector2(wall_h, 2)
		var z := Vector2.ZERO
		var with_balconies := tall and h >= 9.0 and (bi % 5) != 0 and not b.has("dome")
		var u := 0.0
		for i in pts.size():
			var a := pts[i]
			var c := pts[(i + 1) % pts.size()]
			var d := c - a
			var length := d.length()
			if length < 0.01:
				continue
			var dir := d / length
			var nrm := Vector3(d.y, 0, -d.x).normalized()
			if area < 0.0:
				nrm = -nrm
			var n2 := Vector2(nrm.x, nrm.z)
			var top := y1 + (1.0 if tall else 0.0)  # il muro sale a fare da parapetto
			if b.has("venue") and int(venues[int(b["venue"])]["edge"]) == i:
				# Facciata del locale: porta e vetrine aperte al piano terra.
				var vn: Dictionary = venues[int(b["venue"])]
				var g_off := surface_at(center.x, center.y) - y0
				for r: Array in Venues.facade_rects(vn, length, g_off, top - y0):
					var p0 := a + dir * float(r[0])
					var p1 := a + dir * float(r[1])
					acc.quad(
						Vector3(p0.x, y0 + float(r[2]), p0.y), Vector3(p1.x, y0 + float(r[2]), p1.y),
						Vector3(p1.x, y0 + float(r[3]), p1.y), Vector3(p0.x, y0 + float(r[3]), p0.y), nrm, col,
						Vector2(u + float(r[0]), r[2]), Vector2(u + float(r[1]), r[2]), Vector2(u + float(r[1]), r[3]),
						Vector2(u + float(r[0]), r[3]), u2
					)
			else:
				acc.quad(
					Vector3(a.x, foot, a.y), Vector3(c.x, foot, c.y), Vector3(c.x, top, c.y), Vector3(a.x, top, a.y),
					nrm, col, Vector2(u, foot - y0), Vector2(u + length, foot - y0), Vector2(u + length, top - y0), Vector2(u, top - y0), u2
				)
			if tall:
				# Cornicione sporgente sotto il parapetto.
				var oa := a + n2 * 0.4
				var oc := c + n2 * 0.4
				var cy0 := y1 - 0.55
				var cy1 := y1 - 0.05
				acc.quad(
					Vector3(oa.x, cy0, oa.y), Vector3(oc.x, cy0, oc.y), Vector3(oc.x, cy1, oc.y), Vector3(oa.x, cy1, oa.y),
					nrm, col, Vector2(u, 0), Vector2(u + length, 0), Vector2(u + length, 0.5), Vector2(u, 0.5), trim
				)
				acc.quad(
					Vector3(a.x, cy0, a.y), Vector3(c.x, cy0, c.y), Vector3(oc.x, cy0, oc.y), Vector3(oa.x, cy0, oa.y),
					Vector3.DOWN, col, z, z, z, z, trim
				)
				acc.quad(
					Vector3(a.x, cy1, a.y), Vector3(c.x, cy1, c.y), Vector3(oc.x, cy1, oc.y), Vector3(oa.x, cy1, oa.y),
					Vector3.UP, col, z, z, z, z, trim
				)
				# Parapetto: faccia interna e copertina.
				var ia := a - n2 * 0.25
				var ic := c - n2 * 0.25
				acc.quad(
					Vector3(ia.x, y1, ia.y), Vector3(ic.x, y1, ic.y), Vector3(ic.x, top, ic.y), Vector3(ia.x, top, ia.y),
					-nrm, col, Vector2(u, 0), Vector2(u + length, 0), Vector2(u + length, 1), Vector2(u, 1), trim
				)
				acc.quad(
					Vector3(a.x, top, a.y), Vector3(c.x, top, c.y), Vector3(ic.x, top, ic.y), Vector3(ia.x, top, ia.y),
					Vector3.UP, col, z, z, z, z, trim
				)
			if with_balconies and length > BAY_W * 1.5:
				# Colonne di balconi allineate alle finestre disegnate dallo shader.
				var first := ceili(u / BAY_W)
				var last := floori((u + length) / BAY_W) - 1
				for bay in range(first, last + 1):
					var uc := (bay + 0.5) * BAY_W
					if uc - u < 1.4 or u + length - uc < 1.4:
						continue
					if fposmod(sin(float(bay) * 12.9898 + float(bi) * 78.233) * 43758.5453, 1.0) > 0.3:
						continue
					var base := a + dir * (uc - u)
					var basis := Basis(Vector3(dir.x, 0, dir.y), Vector3.UP, nrm)
					var lv := 1
					while 0.4 + lv * FLOOR_H + 0.81 * FLOOR_H < wall_h - 1.3:
						var by := y0 + 0.4 + lv * FLOOR_H + 0.78
						_push(balconies, Transform3D(basis, Vector3(base.x, by, base.y)))
						lv += 1
			u += length
		var idx := Geometry2D.triangulate_polygon(pts)
		for i in range(0, idx.size(), 3):
			var p0 := pts[idx[i]]
			var p1 := pts[idx[i + 1]]
			var p2 := pts[idx[i + 2]]
			acc.tri(
				Vector3(p0.x, y1, p0.y), Vector3(p1.x, y1, p1.y), Vector3(p2.x, y1, p2.y),
				Vector3.UP, col, p0, p1, p2, Vector2(h, 1)
			)
		if b.has("dome"):
			var r := INF
			for i in pts.size():
				var q := Geometry2D.get_closest_point_to_segment(center, pts[i], pts[(i + 1) % pts.size()])
				r = minf(r, center.distance_to(q))
			LandmarkBuilder.dome(domes, center, y1, clampf(r * 0.75, 3.0, 13.0))
		var bname: String = b["n"]
		if bname != "" and absf(area) > 400.0:
			var label := Label3D.new()
			label.text = bname
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 64
			label.outline_size = 12
			label.pixel_size = 0.02
			label.position = Vector3(center.x, y1 + 4.0, center.y)
			label.visibility_range_end = 320.0
			add_child(label)
	for key: Vector2i in chunks:
		var acc: Acc = chunks[key]
		_add_mesh(acc.mesh(mat), "Edifici_%d_%d" % [key.x, key.y])
		_add_trimesh_body(acc.v, "EdificiFisici_%d_%d" % [key.x, key.y])
	for key: Vector2i in modern_chunks:
		var acc: Acc = modern_chunks[key]
		_add_mesh(acc.mesh(modern_mat), "EdificiModerni_%d_%d" % [key.x, key.y])
		_add_trimesh_body(acc.v, "EdificiModerniFisici_%d_%d" % [key.x, key.y])
	if not domes.v.is_empty():
		_add_mesh(domes.mesh(dome_mat), "Cupole")
		_add_trimesh_body(domes.v, "CupoleFisiche")
	_add_multimesh_chunks(_balcony_mesh(), balconies, "Balconi", 0.0, NEAR_RANGE)


## Balcone: soletta in pietra e ringhiera in ferro. Locale: X lungo il muro, Z verso l'esterno.
func _balcony_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.08, 0.09, 0.08)
	iron.metallic = 0.5
	iron.roughness = 0.5
	var slab := BoxMesh.new()
	slab.size = Vector3(2.3, 0.16, 1.0)
	_part(slab, Transform3D(Basis(), Vector3(0, -0.08, 0.5)), _stone_mat, mesh)
	var rails := [
		[Vector3(2.3, 0.05, 0.05), Vector3(0, 1.0, 0.97)],
		[Vector3(0.05, 0.05, 1.0), Vector3(1.13, 1.0, 0.5)],
		[Vector3(0.05, 0.05, 1.0), Vector3(-1.13, 1.0, 0.5)],
		[Vector3(2.3, 0.04, 0.04), Vector3(0, 0.12, 0.97)],
	]
	for k in 12:
		var x := -1.1 + 2.2 * k / 11.0
		rails.append([Vector3(0.025, 0.9, 0.025), Vector3(x, 0.55, 0.97)])
	for k in 5:
		var zz := 0.15 + 0.8 * k / 4.0
		rails.append([Vector3(0.025, 0.9, 0.025), Vector3(1.13, 0.55, zz)])
		rails.append([Vector3(0.025, 0.9, 0.025), Vector3(-1.13, 0.55, zz)])
	var surf := SurfaceTool.new()
	surf.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r: Array in rails:
		var box := BoxMesh.new()
		box.size = r[0]
		surf.append_from(box, 0, Transform3D(Basis(), r[1]))
	surf.set_material(iron)
	surf.commit(mesh)
	return mesh


# --- Alberi -----------------------------------------------------------------------------------


func _part(prim: PrimitiveMesh, xf: Transform3D, mat: Material, mesh: ArrayMesh) -> void:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var nb := xf.basis.inverse().transposed()
	for i in verts.size():
		verts[i] = xf * verts[i]
		norms[i] = (nb * norms[i]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = null
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


## Unisce più forme in una sola superficie (meno chiamate di disegno).
func _merged(parts: Array, mat: Material, mesh: ArrayMesh) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Array in parts:
		st.append_from(p[0], 0, p[1])
	st.set_material(mat)
	st.commit(mesh)


func _build_trees() -> void:
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = TexLib.tex("Bark014", "color")
	bark.normal_enabled = true
	bark.normal_texture = TexLib.tex("Bark014", "normal")
	bark.uv1_triplanar = true
	bark.uv1_scale = Vector3(0.8, 0.8, 0.8)
	bark.albedo_color = Color(0.78, 0.72, 0.68)  # corteccia meno arancione, più grigio-bruna
	# Alberi con rami e chiome di foglie vere (scripts/trees.gd): tre specie, tre livelli di dettaglio.
	var meshes := {}
	var lists := {}
	for kind: String in TreeKit.KINDS:
		var lm := TreeKit.leaves_material(kind)
		meshes[kind] = []
		for lod in TreeKit.LODS:
			meshes[kind].append(TreeKit.mesh(kind, lod, bark, lm))
		lists[kind] = {}
	var bodies := {}  # un corpo per riquadro: aggiungere migliaia di forme a un solo corpo è lentissimo
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.3
	trunk_shape.height = 4.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for t: Array in data["trees"]:
		var x: float = t[0]
		var zz: float = t[1]
		var on_pad := false
		for pad: Vector2 in Heli.PADS:
			if pad.distance_to(Vector2(x, zz)) < 13.0:
				on_pad = true  # piazzola degli elicotteri libera dagli alberi
		if on_pad:
			continue
		var g := height_at(x, zz)
		if g < water_y + 0.5 or g < -0.3 and g > -9.0:
			continue  # niente alberi in acqua o sul muraglione
		var s := rng.randf_range(0.8, 1.2)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), Vector3(x, g, zz))
		var pick := rng.randf()
		_push(lists["pino" if pick < 0.35 else ("platano" if pick < 0.75 else "leccio")], xf)
		var key := _chunk_key(Vector2(x, zz))
		if not bodies.has(key):
			var b := StaticBody3D.new()
			b.name = "AlberiFisici_%d_%d" % [key.x, key.y]
			b.collision_layer = 2
			add_child(b)
			bodies[key] = b
		var cs := CollisionShape3D.new()
		cs.shape = trunk_shape
		cs.position = Vector3(x, g + 2.0, zz)
		bodies[key].add_child(cs)
	for kind: String in lists:
		# Le chiome trasparenti non fanno ombra (costerebbe troppo): la fa una sagoma piena e semplice, invisibile.
		_add_multimesh_chunks(meshes[kind][0], lists[kind], "Alberi_" + kind, 0.0, TREE_NEAR, false)
		_add_multimesh_chunks(meshes[kind][1], lists[kind], "Alberi_%s_medi" % kind, TREE_NEAR, NEAR_RANGE, false)
		_add_multimesh_chunks(TreeKit.shadow_mesh(kind), lists[kind], "Alberi_%s_ombre" % kind, 0.0, NEAR_RANGE, true, true)
		_add_multimesh_chunks(meshes[kind][2], lists[kind], "Alberi_%s_lontani" % kind, NEAR_RANGE, 0.0, false)


## Numeri civici (data/civici.json, da tools/fetch_civici.py): targa di marmo bianco col numero nero, come a
## Roma, sulla facciata più vicina al punto dell'indirizzo, accanto al portone a circa 2,3 m da terra.
## Si vedono entro 30 m (sono quasi duemila).
func _build_civici() -> void:
	if not FileAccess.file_exists("res://data/civici.json"):
		return
	var list: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/civici.json"))
	var plates: Array[Transform3D] = []
	var font_col := Color(0.08, 0.08, 0.09)
	for cv: Array in list:
		var at := Vector2(float(cv[0]), float(cv[1]))
		var best_d := 14.0
		var best: Array = []
		var key := Vector2i(floori(at.x / 32.0), floori(at.y / 32.0))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for f: Array in _facades.get(key + Vector2i(dx, dz), []):
					var pts: PackedVector2Array = f[0]
					for i in pts.size():
						var a := pts[i]
						var b := pts[(i + 1) % pts.size()]
						if a.distance_to(b) < 2.5:
							continue
						var q := Geometry2D.get_closest_point_to_segment(at, a, b)
						var d := q.distance_to(at)
						if d < best_d:
							best_d = d
							best = [a, b, q, float(f[1]), f[2]]
		if best.is_empty():
			continue
		var a2: Vector2 = best[0]
		var b2: Vector2 = best[1]
		var dir := (b2 - a2).normalized()
		var n := Vector2(-dir.y, dir.x)
		if n.dot((best[2] as Vector2) - (best[4] as Vector2)) < 0.0:
			n = -n  # normale verso fuori
		# Un po' di lato rispetto al punto (dove di solito c'è il portone), mai oltre lo spigolo.
		var t := clampf((best[2] as Vector2).distance_to(a2) + 0.9, 0.5, a2.distance_to(b2) - 0.5)
		var q2 := a2 + dir * t + n * 0.045
		var pos := Vector3(q2.x, float(best[3]) + 2.3, q2.y)
		var basis := Basis(Vector3(dir.x, 0, dir.y), Vector3.UP, Vector3(n.x, 0, n.y))  # testo leggibile da fuori
		plates.append(Transform3D(basis, pos))
		civic_spots.append([pos, Vector3(n.x, 0, n.y), String(cv[2]), String(cv[3])])
		var num := Label3D.new()
		num.text = String(cv[2])
		num.font_size = 72
		num.outline_size = 0
		num.pixel_size = 0.0022
		num.modulate = font_col
		num.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		num.shaded = true
		num.double_sided = false
		num.transform = Transform3D(basis, pos + Vector3(n.x, 0, n.y) * 0.022)
		num.visibility_range_end = 30.0
		add_child(num)
	if plates.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.24, 0.035)
	var marble := StandardMaterial3D.new()
	marble.albedo_color = Color(0.9, 0.89, 0.86)
	marble.roughness = 0.35
	box.material = marble
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = plates.size()
	for i in plates.size():
		mm.set_instance_transform(i, plates[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Civici"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	print("civici: %d targhe" % plates.size())


## Muri invisibili sul bordo della mappa.
func _build_bounds() -> void:
	var body := StaticBody3D.new()
	body.name = "Bordi"
	body.collision_layer = 1
	add_child(body)
	var c := bbox.get_center()
	var s := bbox.size
	for e: Array in [
		[Vector3(s.x, 200, 2), Vector3(c.x, 70, bbox.position.y)],
		[Vector3(s.x, 200, 2), Vector3(c.x, 70, bbox.end.y)],
		[Vector3(2, 200, s.y), Vector3(bbox.position.x, 70, c.y)],
		[Vector3(2, 200, s.y), Vector3(bbox.end.x, 70, c.y)],
	]:
		var shape := BoxShape3D.new()
		shape.size = e[0]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = e[1]
		body.add_child(cs)
