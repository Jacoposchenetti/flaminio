class_name Locali
extends RefCounted

## Locali modellati a mano in Blender (tools/blender/*.py) al posto delle scatole OSM: il modello .glb sta in
## assets/locali/<nome>/ ed è costruito in coordinate locali (x lungo un lato della pianta, z lungo l'altro,
## origine in uno spigolo). Qui si tolgono gli edifici OSM che sostituisce, si mette il modello sulla pianta
## reale e si accendono le luci (nel modello: nodi vuoti "luce_<tipo>_NN").
## Le mesh con nome "...-col" diventano collisioni all'importazione (regola di Godot per i glTF).

const LOCALI := {
	"treebar": {
		"glb": "res://assets/locali/treebar/treebar.glb",
		"ids": [1132263633, 1132263632],  # Tree Bar, via Flaminia: padiglione (bar e cucina) e sala ristorante
		"origin": Vector2(-93.98, -68.9),  # spigolo nord-ovest dell'edificio 1132263633
		"axis": Vector2(-87.33, -70.87),   # spigolo nord-est: direzione dell'asse x del modello
	},
}

## Luci per tipo: colore, energia, raggio, ombre.
const LIGHTS := {
	"bar": [Color(1.0, 0.62, 0.3), 1.6, 4.5, true],
	"sala": [Color(1.0, 0.8, 0.58), 1.1, 3.5, false],
	"cucina": [Color(1.0, 0.92, 0.8), 1.2, 5.0, false],
	"forno": [Color(1.0, 0.45, 0.15), 2.0, 2.5, false],
	"dehors": [Color(1.0, 0.75, 0.45), 0.8, 4.0, false],
}


## Toglie dagli edifici OSM quelli sostituiti da un locale (prima che interni, case e bar li scelgano).
static func strip(data: Dictionary) -> void:
	var gone := {}
	for l: Dictionary in LOCALI.values():
		for id: int in l["ids"]:
			gone[id] = true
	data["buildings"] = (data["buildings"] as Array).filter(
		func(b: Dictionary) -> bool: return not gone.has(int(b["id"])))


static func build(city: CityBuilder) -> void:
	for name: String in LOCALI:
		var l: Dictionary = LOCALI[name]
		if not ResourceLoader.exists(l["glb"]):
			continue
		var scene: Node3D = (load(l["glb"]) as PackedScene).instantiate()
		scene.name = "Locale_" + name
		var o: Vector2 = l["origin"]
		var dir: Vector2 = ((l["axis"] as Vector2) - o).normalized()
		# Il pavimento del modello sta 12 cm sopra lo zero: lo zero va al punto più basso del terreno sotto la pianta.
		var y := INF
		var aabb := Rect2(o, Vector2.ZERO)
		for p in _corners(scene):
			var w := o + dir * p.x + Vector2(-dir.y, dir.x) * p.y
			aabb = aabb.expand(w)
		for i in 5:
			for j in 5:
				var q := aabb.position + aabb.size * Vector2(i / 4.0, j / 4.0)
				y = minf(y, city.surface_at(q.x, q.y))
		scene.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(o.x, y, o.y))
		city.add_child(scene)
		_lights(scene)
		var probe := ReflectionProbe.new()
		probe.size = Vector3(aabb.size.x + 2.0, 4.0, aabb.size.y + 2.0)
		probe.interior = true
		probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
		probe.ambient_color = Color(0.72, 0.66, 0.58)
		probe.ambient_color_energy = 0.9
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		city.add_child(probe)
		var c := aabb.get_center()
		probe.global_position = Vector3(c.x, y + 2.0, c.y)


## Pianta del modello (x, z locali) dai suoi AABB: per cercare la quota del terreno.
static func _corners(scene: Node3D) -> PackedVector2Array:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var bb := mi.transform * mi.mesh.get_aabb()
		lo = lo.min(Vector2(bb.position.x, bb.position.z))
		hi = hi.max(Vector2(bb.end.x, bb.end.z))
	return PackedVector2Array([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)])


static func _lights(scene: Node3D) -> void:
	for n: Node in scene.find_children("luce_*", "", true, false):
		var kind := String(n.name).get_slice("_", 1)
		var s: Array = LIGHTS.get(kind, LIGHTS["bar"])
		var l := OmniLight3D.new()
		l.light_color = s[0]
		l.light_energy = s[1]
		l.omni_range = s[2]
		l.shadow_enabled = s[3]
		l.distance_fade_enabled = true
		l.distance_fade_begin = 60.0
		l.distance_fade_length = 20.0
		n.add_child(l)
