class_name Human
extends Node3D

## Persona realistica: corpo base Quaternius (CC0) con vestiti dipinti da shader, capelli agganciati alla
## testa, animazioni della Universal Animation Library (CC0, stesso scheletro). Guarda verso +Z.
##
## Uso: Human.new().setup("m3") e poi play("walk"). I nomi dei preset sono in PRESETS.

const BODY := {
	"m": "res://assets/people/Superhero_Male_FullBody.gltf",
	"f": "res://assets/people/Superhero_Female_FullBody.gltf",
}
const ANIMS := "res://assets/people/UAL1_Standard.glb"
const HAIR_DIR := "res://assets/people/hair/"
## Nomi delle animazioni del gioco -> animazioni della libreria.
const ANIM_MAP := {
	"idle": "Idle", "walk": "Jog_Fwd", "stroll": "Walk", "sprint": "Sprint", "jump": "Jump", "fall": "Jump",
	"swim": "Swim_Fwd", "swim_idle": "Swim_Idle", "drive": "Driving", "talk": "Idle_Talking", "dance": "Dance",
	"crouch": "Crouch_Idle", "crouch_walk": "Crouch_Fwd", "roll": "Roll", "punch": "Punch_Jab", "punch2": "Punch_Cross",
	"melee": "Sword_Attack", "aim": "Pistol_Aim_Neutral", "aim_up": "Pistol_Aim_Up", "aim_down": "Pistol_Aim_Down",
	"armed": "Pistol_Idle", "shoot": "Pistol_Shoot", "reload": "Pistol_Reload", "death": "Death01", "hit": "Hit_Chest", "hit_head": "Hit_Head",
	"throw": "Spell_Simple_Shoot", "interact": "Interact", "kick": "Punch_Cross", "push": "Push", "sit_enter": "Sitting_Enter",
}
const SKIN := {
	"chiara": Color(0.93, 0.76, 0.64), "olivastra": Color(0.8, 0.6, 0.45), "ambrata": Color(0.66, 0.46, 0.32),
	"scura": Color(0.42, 0.28, 0.2), "rosea": Color(0.96, 0.8, 0.72),
}
const HAIR_COLOR := {
	"nero": Color(0.12, 0.1, 0.09), "castano": Color(0.35, 0.22, 0.14), "castano chiaro": Color(0.55, 0.38, 0.24),
	"rosso": Color(0.6, 0.25, 0.12), "grigio": Color(0.6, 0.58, 0.55), "biondo": Color(0.85, 0.7, 0.45),
}
## sesso, pelle, capelli, colore capelli, barba, maglia, pantaloni, scarpe, manica lunga, bermuda, jeans, righe
const PRESETS := {
	"m1": ["m", "olivastra", "SimpleParted", "castano", false, Color(0.95, 0.95, 0.93), Color(0.2, 0.28, 0.45), Color(0.95, 0.95, 0.95), false, false, true, false],
	"m2": ["m", "chiara", "Buzzed", "castano chiaro", true, Color(0.25, 0.35, 0.55), Color(0.78, 0.72, 0.6), Color(0.35, 0.22, 0.12), true, false, false, false],
	"m3": ["m", "scura", "Buzzed", "nero", false, Color(0.85, 0.25, 0.2), Color(0.12, 0.12, 0.13), Color(0.95, 0.95, 0.95), false, false, false, false],
	"m4": ["m", "ambrata", "SimpleParted", "nero", true, Color(0.2, 0.22, 0.25), Color(0.3, 0.38, 0.55), Color(0.2, 0.2, 0.2), true, false, true, false],
	"m5": ["m", "rosea", "SimpleParted", "rosso", false, Color(0.3, 0.5, 0.35), Color(0.55, 0.5, 0.42), Color(0.5, 0.35, 0.2), false, true, false, false],
	"m6": ["m", "olivastra", "Buzzed", "grigio", true, Color(0.62, 0.75, 0.9), Color(0.25, 0.25, 0.3), Color(0.15, 0.1, 0.08), true, false, false, false],
	"m7": ["m", "chiara", "SimpleParted", "biondo", false, Color(0.15, 0.2, 0.45), Color(0.2, 0.28, 0.45), Color(0.95, 0.3, 0.2), false, false, true, true],
	"m8": ["m", "ambrata", "SimpleParted", "castano", true, Color(0.9, 0.8, 0.3), Color(0.35, 0.4, 0.3), Color(0.9, 0.9, 0.88), false, true, false, false],
	"f1": ["f", "olivastra", "Long", "castano", false, Color(0.95, 0.95, 0.93), Color(0.2, 0.28, 0.45), Color(0.95, 0.95, 0.95), false, false, true, false],
	"f2": ["f", "chiara", "Buns", "rosso", false, Color(0.2, 0.45, 0.4), Color(0.12, 0.12, 0.13), Color(0.15, 0.15, 0.15), true, false, false, false],
	"f3": ["f", "scura", "Long", "nero", false, Color(0.95, 0.75, 0.2), Color(0.3, 0.38, 0.55), Color(0.95, 0.95, 0.95), false, false, true, false],
	"f4": ["f", "ambrata", "Buns", "nero", false, Color(0.75, 0.2, 0.35), Color(0.85, 0.82, 0.75), Color(0.8, 0.65, 0.5), false, false, false, false],
	"f5": ["f", "rosea", "Long", "biondo", false, Color(0.55, 0.7, 0.9), Color(0.2, 0.28, 0.45), Color(0.95, 0.95, 0.95), true, false, true, true],
	"f6": ["f", "olivastra", "BuzzedFemale", "castano chiaro", false, Color(0.12, 0.12, 0.13), Color(0.12, 0.12, 0.13), Color(0.12, 0.12, 0.12), true, false, false, false],
	"f7": ["f", "chiara", "Long", "castano chiaro", false, Color(0.9, 0.55, 0.45), Color(0.6, 0.55, 0.45), Color(0.95, 0.95, 0.95), false, true, false, false],
	"f8": ["f", "scura", "Buns", "castano", false, Color(0.35, 0.3, 0.6), Color(0.2, 0.2, 0.22), Color(0.95, 0.95, 0.95), true, false, true, false],
}

## Divise da calcio: stampa sulla schiena, colore dei bordi e dei calzettoni, fascia da capitano.
const KITS := {
	"totti": {"print": "res://assets/people/totti/maglia_retro.png", "trim": Color(0.95, 0.72, 0.16),
		"socks": Color(0.56, 0.1, 0.16), "armband": true},
}

## Divise (non scelte dai giocatori né dai pedoni): Polizia di Stato, camicia azzurra e pantaloni blu scuro.
const UNIFORMS := {
	"cop_m": ["m", "olivastra", "Buzzed", "nero", false, Color(0.55, 0.68, 0.86), Color(0.08, 0.1, 0.18), Color(0.05, 0.05, 0.05), true, false, false, false],
	"cop_f": ["f", "chiara", "Buns", "castano", false, Color(0.55, 0.68, 0.86), Color(0.08, 0.1, 0.18), Color(0.05, 0.05, 0.05), true, false, false, false],
	"cc_m": ["m", "olivastra", "Buzzed", "nero", false, Color(0.07, 0.07, 0.1), Color(0.05, 0.05, 0.07), Color(0.03, 0.03, 0.03), true, false, false, false],
	# Uomini dei clan: giubbotto col colore del clan, jeans scuri; i boss in completo.
	"gang_red": ["m", "olivastra", "Buzzed", "nero", true, Color(0.55, 0.06, 0.05), Color(0.1, 0.1, 0.12), Color(0.9, 0.9, 0.9), false, false, false, false],
	"gang_purple": ["m", "chiara", "SimpleParted", "castano", true, Color(0.38, 0.12, 0.5), Color(0.12, 0.12, 0.14), Color(0.1, 0.1, 0.1), false, false, false, false],
	"gang_blue": ["m", "rosea", "SimpleParted", "biondo", false, Color(0.1, 0.25, 0.6), Color(0.75, 0.7, 0.6), Color(0.35, 0.22, 0.12), true, false, true, false],
	"gang_orange": ["m", "ambrata", "Buzzed", "nero", true, Color(0.75, 0.38, 0.06), Color(0.15, 0.15, 0.18), Color(0.95, 0.95, 0.95), false, false, false, false],
	"gang_black": ["m", "scura", "Buzzed", "nero", true, Color(0.06, 0.06, 0.07), Color(0.08, 0.08, 0.1), Color(0.05, 0.05, 0.05), false, false, false, false],
	# Vigilanza privata delle banche (camicia grigia, pantaloni scuri) e direttore di filiale.
	"guard": ["m", "olivastra", "Buzzed", "nero", false, Color(0.32, 0.34, 0.38), Color(0.1, 0.11, 0.14), Color(0.04, 0.04, 0.04), true, false, false, false],
	"banker": ["m", "chiara", "SimpleParted", "grigio", false, Color(0.12, 0.16, 0.28), Color(0.12, 0.13, 0.18), Color(0.06, 0.05, 0.04), false, false, true, false],
	# Personaggi famosi (scripts/icone.gd). Francesco Totti con la maglia della Roma: rosso pompeiano e calzoncini bianchi.
	"totti": ["m", "chiara", "SimpleParted", "castano", false, Color(0.56, 0.1, 0.16), Color(0.95, 0.95, 0.93), Color(0.04, 0.04, 0.04), false, true, false, false],
	"boss": ["m", "olivastra", "SimpleParted", "grigio", true, Color(0.16, 0.16, 0.18), Color(0.14, 0.14, 0.16), Color(0.05, 0.04, 0.03), true, false, false, false],
}

static var _anim_lib: AnimationLibrary
static var _body_mesh := {}  # sesso -> ArrayMesh con la posa a T in COLOR
static var _skin_ref := {}  # sesso -> colore medio (lineare) della texture della pelle

var anim: AnimationPlayer
var _skel: Skeleton3D
var _current := ""


## Nome da mostrare nel menu.
static func label(id: String) -> String:
	if not PRESETS.has(id):
		return id
	var p: Array = PRESETS[id]
	var who := "Uomo" if p[0] == "m" else "Donna"
	return "%s %s · capelli %s%s" % [who, id.substr(1), p[3], " e barba" if p[4] else ""]


func setup(id: String) -> Human:
	var p: Array = PRESETS.get(id, UNIFORMS.get(id, PRESETS["m1"]))
	var sex: String = p[0]
	var body := _new_body(sex)
	add_child(body)
	var skel := body.find_child("Skeleton3D", true, false) as Skeleton3D
	_skel = skel
	var bone := func(n: String) -> Vector3: return skel.get_bone_global_rest(skel.find_bone(n)).origin

	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if mat == null:
			continue
		if mat.resource_name.begins_with("MI_Superhero"):
			mi.mesh = _bind_pose_mesh(sex, mi.mesh)
			mi.material_override = _clothes_material(sex, mat, p, bone)
			if KITS.has(id):
				_kit(mi.material_override as ShaderMaterial, KITS[id], bone)
		elif mat.resource_name.begins_with("MI_Hair"):
			mi.material_override = _hair_material(mat, p[3])

	# Capelli e barba: mesh ferme rispetto all'osso della testa.
	var head := skel.find_bone("Head")
	var attach := BoneAttachment3D.new()
	attach.bone_name = "Head"
	skel.add_child(attach)
	var styles: Array[String] = ["Hair_" + String(p[2])]
	if p[4]:
		styles.append("Hair_Beard")
	for style in styles:
		var path := HAIR_DIR + style + ".gltf"
		if not ResourceLoader.exists(path):
			continue
		var hair: Node3D = (load(path) as PackedScene).instantiate()
		hair.transform = skel.get_bone_global_rest(head).affine_inverse()
		attach.add_child(hair)
		for mi: MeshInstance3D in hair.find_children("*", "MeshInstance3D", true, false):
			var hm := mi.mesh.surface_get_material(0) as StandardMaterial3D
			if hm:
				mi.material_override = _hair_material(hm, p[3])

	anim = AnimationPlayer.new()
	body.add_child(anim)
	anim.root_node = NodePath("..")
	anim.add_animation_library("", _library())
	play("idle")
	return self


static var _body_templates := {}  # sesso -> corpo istanziato una volta sola, da copiare


## Corpo nuovo. Istanziare il modello ricrea ogni volta le sue mesh sulla scheda video (~130 ms, uno scatto
## a ogni pedone che compare): lo istanzio una volta per sesso e poi copio i nodi condividendo le mesh.
static func _new_body(sex: String) -> Node3D:
	if not _body_templates.has(sex):
		_body_templates[sex] = (load(BODY[sex]) as PackedScene).instantiate()
	return (_body_templates[sex] as Node3D).duplicate(0) as Node3D


## Posizione della mano destra nel mondo (per tenere l'arma).
func hand_position() -> Vector3:
	if _skel == null:
		return global_position + Vector3(0, 1.2, 0)
	var i := _skel.find_bone("hand_r")
	return _skel.global_transform * _skel.get_bone_global_pose(i).origin


func play(want: String, blend := 0.2) -> void:
	var real: String = ANIM_MAP.get(want, want)
	if anim == null or not anim.has_animation(real):
		return
	if real == _current and (anim.get_animation(real).loop_mode != Animation.LOOP_NONE or anim.is_playing()):
		return
	anim.play(real, blend)
	_current = real


## Si rialza da terra: la caduta (Death01) all'indietro, un po' più veloce.
func play_getup() -> void:
	if anim == null or not anim.has_animation("Death01"):
		return
	anim.play("Death01", 0.1, -1.7, true)
	_current = "Death01_up"


## Rilancia da capo un'animazione breve (colpo, sparo, ricarica).
func play_once(want: String, blend := 0.08, speed := 1.0) -> void:
	var real: String = ANIM_MAP.get(want, want)
	if anim == null or not anim.has_animation(real):
		return
	anim.stop()
	anim.play(real, blend, speed)
	_current = real


static func _library() -> AnimationLibrary:
	if _anim_lib == null:
		var scene: Node = (load(ANIMS) as PackedScene).instantiate()
		var ap := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_anim_lib = ap.get_animation_library("").duplicate(true)
		for n in ["Idle", "Jog_Fwd", "Walk", "Sprint", "Jump", "Swim_Fwd", "Swim_Idle", "Driving", "Idle_Talking", "Dance",
				"Crouch_Idle", "Crouch_Fwd", "Pistol_Idle", "Pistol_Aim_Neutral", "Pistol_Aim_Up", "Pistol_Aim_Down", "Push"]:
			if _anim_lib.has_animation(n):
				_anim_lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		scene.free()
	return _anim_lib


## Copia della mesh del corpo con la posizione nella posa a T salvata nel colore dei vertici.
static func _bind_pose_mesh(sex: String, src: Mesh) -> Mesh:
	if _body_mesh.has(sex):
		return _body_mesh[sex]
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		cols[i] = Color((v.x + 1.0) * 0.5, v.y * 0.5, v.z + 0.5, 1.0)
	arrays[Mesh.ARRAY_COLOR] = cols
	# I canali extra del glTF non servono e richiederebbero di ripeterne il formato.
	for k in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arrays[k] = null
	var flags: int = src.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	_body_mesh[sex] = m
	return m


static func _skin_reference(sex: String, tex: Texture2D) -> Color:
	if _skin_ref.has(sex):
		return _skin_ref[sex]
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var sum := Vector3.ZERO
	var n := 0
	for yy in range(0, img.get_height(), img.get_height() / 48):
		for xx in range(0, img.get_width(), img.get_width() / 48):
			var c := img.get_pixel(xx, yy).srgb_to_linear()
			if c.r > c.b * 1.1 and c.r > 0.03:  # solo pixel color pelle
				sum += Vector3(c.r, c.g, c.b)
				n += 1
	var avg := sum / maxf(n, 1)
	_skin_ref[sex] = Color(avg.x, avg.y, avg.z)
	return _skin_ref[sex]


func _clothes_material(sex: String, src: StandardMaterial3D, p: Array, bone: Callable) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/clothes.gdshader")
	m.set_shader_parameter("body_albedo", src.albedo_texture)
	m.set_shader_parameter("body_normal", src.normal_texture)
	m.set_shader_parameter("body_rough", src.roughness_texture)
	var ref := _skin_reference(sex, src.albedo_texture)
	var tone: Color = SKIN.get(p[1], SKIN["olivastra"]).srgb_to_linear()
	m.set_shader_parameter("skin_ratio", Vector3(tone.r / ref.r, tone.g / ref.g, tone.b / ref.b))
	m.set_shader_parameter("shirt_color", p[5])
	m.set_shader_parameter("pants_color", p[6])
	m.set_shader_parameter("shoe_color", p[7])
	var pelvis: Vector3 = bone.call("pelvis")
	var neck: Vector3 = bone.call("neck_01")
	var knee: Vector3 = bone.call("calf_l")
	var foot: Vector3 = bone.call("foot_l")
	var shoulder: Vector3 = bone.call("upperarm_l")
	var elbow: Vector3 = bone.call("lowerarm_l")
	var hand: Vector3 = bone.call("hand_l")
	m.set_shader_parameter("waist_y", pelvis.y + 0.05)
	m.set_shader_parameter("neck_y", neck.y - 0.03)
	m.set_shader_parameter("shoe_y", foot.y + 0.04)
	m.set_shader_parameter("pants_end_y", knee.y + 0.04 if p[9] else foot.y + 0.04)
	m.set_shader_parameter("torso_x", shoulder.x - 0.02)
	m.set_shader_parameter("sleeve_x", hand.x - 0.04 if p[8] else lerpf(shoulder.x, elbow.x, 0.45))
	m.set_shader_parameter("denim", 1.0 if p[10] else 0.0)
	m.set_shader_parameter("stripes", 1.0 if p[11] else 0.0)
	return m


func _kit(m: ShaderMaterial, k: Dictionary, bone: Callable) -> void:
	var knee: Vector3 = bone.call("calf_l")
	m.set_shader_parameter("kit", 1.0)
	m.set_shader_parameter("kit_print", load(k["print"]))
	m.set_shader_parameter("trim_color", k["trim"])
	m.set_shader_parameter("sock_color", k["socks"])
	m.set_shader_parameter("sock_top_y", knee.y - 0.03)
	m.set_shader_parameter("pants_end_y", knee.y + 0.13)  # calzoncini corti
	m.set_shader_parameter("armband", 1.0 if k.get("armband", false) else 0.0)


func _hair_material(src: StandardMaterial3D, color_name: String) -> StandardMaterial3D:
	var m := src.duplicate() as StandardMaterial3D
	var c: Color = HAIR_COLOR.get(color_name, HAIR_COLOR["castano"])
	# La texture dei capelli è castana: la schiarisco o scurisco moltiplicando.
	m.albedo_color = Color(c.r * 2.2, c.g * 2.2, c.b * 2.2)
	return m
