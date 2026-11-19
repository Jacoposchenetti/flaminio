class_name Sfx
extends RefCounted

## Suoni del gioco (sintetizzati da tools/gen_sounds.py in assets/sounds). play3d() crea un suono nel mondo che si
## cancella da solo; loop3d() restituisce un suono continuo (motori, sirene) da attaccare a un nodo.

const GUN := {
	"pistola": "pistol", "mitragliatrice": "smg", "fucile": "rifle", "pompa": "shotgun", "cecchino": "sniper", "heli_mg": "rifle",
}
const LOOPS := ["engine", "siren", "ambience", "rotor", "jet", "spin"]

static var _cache := {}
static var root: Node  # dove aggiungere i suoni (la scena principale)


static func stream(sound_name: String) -> AudioStream:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var path := "res://assets/sounds/%s.wav" % sound_name
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStreamWAV = load(path)
	if sound_name in LOOPS:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / 2
	_cache[sound_name] = s
	return s


static func play3d(sound_name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, max_dist := 250.0) -> void:
	if root == null or not root.is_inside_tree():
		return
	var st := stream(sound_name)
	if st == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.max_distance = max_dist
	p.unit_size = 6.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	root.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


static func play2d(sound_name: String, volume_db := 0.0) -> void:
	if root == null:
		return
	var st := stream(sound_name)
	if st == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = volume_db
	root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


static func loop3d(parent: Node3D, sound_name: String, volume_db := 0.0, max_dist := 120.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound_name)
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 5.0
	p.autoplay = true  # parte appena entra nella scena (il genitore può non esserci ancora)
	parent.add_child(p)
	return p


static func gunshot(weapon_id: String, pos: Vector3) -> void:
	var sname: String = GUN.get(weapon_id, "pistol")
	play3d(sname, pos, 2.0 if weapon_id in ["cecchino", "pompa"] else 0.0, 1.0, 600.0)
