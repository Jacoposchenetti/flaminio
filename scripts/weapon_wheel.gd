class_name WeaponWheel
extends Control

## Menu a rotella delle armi (come in GTA): si apre tenendo premuto Tab o RB/R1, si sceglie muovendo il mouse
## o la levetta destra verso uno spicchio, si conferma rilasciando il tasto (o con un clic).
## Ogni arma posseduta ha il suo spicchio, granate, mine e TNT comprese, con i colpi rimasti.

signal chosen(weapon_id: String)

const R_OUT := 230.0
const R_IN := 85.0

var player: Player
var _items: Array = []  # id delle armi, in ordine
var _sel := -1
var _aim := Vector2.ZERO  # direzione accumulata dal mouse
var _font: Font


func setup(p: Player) -> void:
	player = p
	_font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open() -> void:
	_items = player.owned_weapons()
	_sel = _items.find(player.weapon)
	_aim = Vector2.ZERO
	visible = true


## Chiude e restituisce l'arma scelta ("" se nessuna).
func close() -> String:
	visible = false
	if _sel >= 0 and _sel < _items.size():
		return _items[_sel]
	return ""


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		_aim += event.relative
		if _aim.length() > 120.0:
			_aim = _aim.normalized() * 120.0
		if _aim.length() > 25.0:
			_sel = _slice_at(_aim.angle())
		get_viewport().set_input_as_handled()  # la camera non gira mentre si sceglie
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		chosen.emit(close())
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	# Levetta destra del joypad.
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.5:
		_sel = _slice_at(stick.angle())
	queue_redraw()


## Spicchio nella direzione data (0 = destra, in senso orario come lo schermo); il primo spicchio è in alto.
func _slice_at(angle: float) -> int:
	if _items.is_empty():
		return -1
	var n := _items.size()
	var a := fposmod(angle + PI / 2 + PI / n, TAU)
	return int(a / (TAU / n)) % n


func _draw() -> void:
	var c := size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	var n := _items.size()
	if n == 0:
		return
	var step := TAU / n
	for i in n:
		var a0 := -PI / 2 + (i - 0.5) * step
		var a1 := a0 + step
		var pts := PackedVector2Array()
		var segs := maxi(4, int(48 / n))
		for k in segs + 1:
			var a := lerpf(a0, a1, float(k) / segs)
			pts.append(c + Vector2(cos(a), sin(a)) * R_OUT)
		for k in range(segs, -1, -1):
			var a := lerpf(a0, a1, float(k) / segs)
			pts.append(c + Vector2(cos(a), sin(a)) * R_IN)
		var on := i == _sel
		draw_colored_polygon(pts, Color(0.95, 0.75, 0.25, 0.85) if on else Color(0.08, 0.08, 0.1, 0.75))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.5), 2.0)
		var id: String = _items[i]
		var w := Weapons.info(id)
		var mid := -PI / 2 + i * step
		var lp := c + Vector2(cos(mid), sin(mid)) * (R_IN + R_OUT) * 0.5
		var col := Color.BLACK if on else Color.WHITE
		_text(lp + Vector2(0, -4), _short(String(w["name"])), 15, col)
		var rounds := _rounds(id)
		if rounds != "":
			_text(lp + Vector2(0, 16), rounds, 13, col.darkened(0.2) if on else Color(1, 0.85, 0.5))
	# Al centro: l'arma scelta per esteso e come si usa.
	var cur: String = _items[_sel] if _sel >= 0 else player.weapon
	var cw := Weapons.info(cur)
	draw_circle(c, R_IN - 6.0, Color(0, 0, 0, 0.6))
	_text(c + Vector2(0, -8), String(cw["name"]), 17, Color.WHITE)
	_text(c + Vector2(0, 14), _hint(cur), 12, Color(0.85, 0.85, 0.85))


func _rounds(id: String) -> String:
	var kind: String = Weapons.info(id)["kind"]
	if kind == "melee":
		return ""
	if kind == "throw" or kind == "place":
		return "× %d" % int(player.ammo.get(id, 0))
	return "%d / %d" % [int(player.clip.get(id, 0)), int(player.ammo.get(id, 0))]


func _hint(id: String) -> String:
	match String(Weapons.info(id)["kind"]):
		"throw":
			return "clic: lancia"
		"place":
			return "clic: piazza · B: fai saltare" if id == "tnt" else "clic: piazza"
		"melee":
			return "clic: colpisci"
	return "destro mira · sinistro spara"


func _short(n: String) -> String:
	return n.replace("Fucile d'assalto", "Fucile").replace("Fucile da cecchino", "Cecchino").replace("Fucile a pompa", "Pompa") \
		.replace("Mazza da baseball", "Mazza")


func _text(pos: Vector2, s: String, fsize: int, col: Color) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(_font, Vector2(pos.x - w * 0.5, pos.y + fsize * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
