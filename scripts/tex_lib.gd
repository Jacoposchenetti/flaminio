class_name TexLib
extends RefCounted

## Texture PBR (ambientCG, CC0) in assets/textures/<id>/{color,normal,rough}.jpg.
## Le carica come immagini con le mipmap, così non serve configurare l'importazione.

static var _cache := {}


static func tex(id: String, kind: String) -> Texture2D:
	var key := id + "/" + kind
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/textures/%s/%s.jpg" % [id, kind]
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		push_warning("Texture mancante: " + path)
		img = Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color(0.5, 0.5, 1.0) if kind == "normal" else Color(0.7, 0.7, 0.7))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


## Assegna a un ShaderMaterial i parametri <prefix>_albedo, <prefix>_normal, <prefix>_rough.
static func bind(mat: ShaderMaterial, prefix: String, id: String) -> void:
	mat.set_shader_parameter(prefix + "_albedo", tex(id, "color"))
	mat.set_shader_parameter(prefix + "_normal", tex(id, "normal"))
	mat.set_shader_parameter(prefix + "_rough", tex(id, "rough"))
