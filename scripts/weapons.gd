class_name Weapons
extends RefCounted

## Catalogo delle armi (modelli Quaternius/Poly Pizza, CC0, in assets/weapons).
## kind: "melee" (corpo a corpo), "gun" (colpo istantaneo), "rocket" (proiettile che esplode),
## "throw" (granata lanciata), "place" (mina o TNT appoggiate a terra).

const LIST := {
	"pugni": {"name": "Pugni", "kind": "melee", "slot": 1, "damage": 12.0, "range": 1.6, "rate": 0.45, "price": 0},
	"coltello": {"name": "Coltello", "kind": "melee", "slot": 1, "damage": 40.0, "range": 1.8, "rate": 0.5, "model": "knife", "len": 0.3, "price": 150},
	"mazza": {"name": "Mazza da baseball", "kind": "melee", "slot": 1, "damage": 30.0, "range": 2.2, "rate": 0.7, "model": "bat", "len": 0.85, "price": 100},
	"pistola": {"name": "Pistola", "kind": "gun", "slot": 2, "damage": 26.0, "rate": 0.22, "mag": 12, "spread": 0.012, "range": 150.0, "model": "pistol", "len": 0.24, "price": 400, "ammo_price": 40},
	"mitragliatrice": {"name": "Mitragliatrice", "kind": "gun", "slot": 3, "damage": 16.0, "rate": 0.075, "mag": 40, "auto": true, "spread": 0.03, "range": 120.0, "model": "smg", "len": 0.5, "price": 1500, "ammo_price": 80},
	"fucile": {"name": "Fucile d'assalto", "kind": "gun", "slot": 4, "damage": 24.0, "rate": 0.11, "mag": 30, "auto": true, "spread": 0.015, "range": 250.0, "model": "rifle", "len": 0.9, "price": 2500, "ammo_price": 100},
	"pompa": {"name": "Fucile a pompa", "kind": "gun", "slot": 4, "damage": 16.0, "pellets": 8, "rate": 0.85, "mag": 8, "spread": 0.07, "range": 40.0, "model": "shotgun", "len": 0.95, "price": 1800, "ammo_price": 60},
	"cecchino": {"name": "Fucile da cecchino", "kind": "gun", "slot": 5, "damage": 140.0, "rate": 1.2, "mag": 5, "spread": 0.0, "range": 800.0, "scope": true, "model": "sniper", "len": 1.2, "price": 5000, "ammo_price": 150},
	"bazooka": {"name": "Lanciarazzi", "kind": "rocket", "slot": 6, "damage": 160.0, "radius": 8.0, "rate": 1.5, "mag": 1, "speed": 45.0, "model": "rocket", "len": 1.1, "flip": true, "price": 8000, "ammo_price": 400},
	"granata": {"name": "Granate", "kind": "throw", "slot": 7, "damage": 140.0, "radius": 7.0, "rate": 1.0, "fuse": 3.0, "model": "grenade", "len": 0.12, "price": 300},
	"mina": {"name": "Mine", "kind": "place", "slot": 7, "damage": 170.0, "radius": 6.0, "rate": 1.0, "trigger": 2.2, "model": "mine", "len": 0.35, "price": 500},
	"auto": {"name": "Esplosione", "kind": "none", "slot": 0, "damage": 110.0, "radius": 7.0, "rate": 1.0, "price": -1},
	"tnt": {"name": "TNT", "kind": "place", "slot": 7, "damage": 250.0, "radius": 10.0, "rate": 1.0, "remote": true, "model": "bomb", "len": 0.35, "price": 700},
}
const ORDER := ["pugni", "coltello", "mazza", "pistola", "mitragliatrice", "fucile", "pompa", "cecchino", "bazooka", "granata", "mina", "tnt"]

static var _cache := {}


static func info(id: String) -> Dictionary:
	return LIST.get(id, LIST["pugni"])


## Modello 3D dell'arma, scalato alla lunghezza reale e girato con la canna verso +Z.
static func model(id: String) -> Node3D:
	var w := info(id)
	if not w.has("model"):
		return null
	var path := "res://assets/weapons/%s.glb" % w["model"]
	if not ResourceLoader.exists(path):
		return null
	var scene: Node3D = (load(path) as PackedScene).instantiate()
	var aabb := AABB()
	var first := true
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var t := scene.global_transform.affine_inverse() * mi.global_transform if mi.is_inside_tree() else _rel(scene, mi)
		var a := t * mi.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var root := Node3D.new()
	var holder := Node3D.new()
	root.add_child(holder)
	holder.add_child(scene)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var s: float = w.get("len", 0.5) / maxf(longest, 0.001)
	# L'asse più lungo diventa +Z (la canna).
	var basis := Basis()
	if aabb.size.x >= aabb.size.y and aabb.size.x >= aabb.size.z:
		basis = Basis(Vector3.UP, -PI / 2)
	elif aabb.size.y > aabb.size.z:
		basis = Basis(Vector3.RIGHT, PI / 2)
	if w.get("flip", false):
		basis = Basis(Vector3.UP, PI) * basis
	holder.transform = Transform3D(basis.scaled(Vector3.ONE * s), Vector3.ZERO)
	scene.position = -aabb.get_center()
	return root


static func _rel(root: Node, n: Node3D) -> Transform3D:
	var t := Transform3D()
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
