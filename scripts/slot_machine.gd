class_name SlotMachine
extends Control

## Slot machine dei bar: tre rulli veri (una striscia di simboli che scorre e si ferma con un piccolo rimbalzo,
## uno dopo l'altro), una linea di vincita, puntate da 5 a 500 €, tabella dei premi, luci che rincorrono il bordo
## e jackpot sul 7-7-7. Si gioca con i soldi del giocatore (in modalità creativa non finiscono mai).
## Comandi: Spazio / Invio / A gira · frecce ← → / croce del joypad cambia puntata · Esc / B esci.

signal closed

## Simboli: nome, peso sulla striscia (quanti ce ne sono), premio per tre uguali (volte la puntata).
const SYMBOLS := [
	{"id": "cherry", "name": "Ciliegie", "weight": 6, "pay": 8},
	{"id": "lemon", "name": "Limone", "weight": 5, "pay": 15},
	{"id": "orange", "name": "Arancia", "weight": 5, "pay": 20},
	{"id": "bell", "name": "Campana", "weight": 3, "pay": 40},
	{"id": "bar", "name": "BAR", "weight": 3, "pay": 75},
	{"id": "star", "name": "Stella", "weight": 2, "pay": 150},
	{"id": "seven", "name": "Sette", "weight": 1, "pay": 400},
]
const BETS := [5, 10, 25, 50, 100, 250, 500]
const REEL_SPEED := 22.0  # simboli al secondo a piena velocità
const PANEL := Vector2(860, 560)

var player: Player
var spinning := false
var _strips: Array = []  # per rullo: Array di indici dei simboli
var _pos: Array[float] = [0.0, 0.0, 0.0]  # posizione di ogni rullo (in simboli, la riga centrale è floorf(pos))
var _from: Array[float] = [0.0, 0.0, 0.0]
var _to: Array[float] = [0.0, 0.0, 0.0]
var _dur: Array[float] = [0.0, 0.0, 0.0]
var _stopped: Array[bool] = [true, true, true]
var _t := 0.0
var _bet_i := 1
var _last_win := 0
var _message := "Premi GIRA (Spazio) per giocare"
var _win_flash := 0.0
var _jackpot := false
var _spin_sound: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _font: Font
var _buttons := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_rng.randomize()
	_font = get_theme_default_font()
	for r in 3:
		var strip := []
		for i in SYMBOLS.size():
			for k in int(SYMBOLS[i]["weight"]):
				strip.append(i)
		# Ogni rullo ha un ordine diverso (mescolato con un seme fisso, uguale per tutti).
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234 + r * 77
		for i in range(strip.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: int = strip[i]
			strip[i] = strip[j]
			strip[j] = tmp
		_strips.append(strip)
		_pos[r] = float(rng.randi_range(0, strip.size() - 1))
	for b: Array in [["spin", "GIRA"], ["minus", "−"], ["plus", "+"], ["exit", "ESCI"]]:
		var btn := Button.new()
		btn.text = b[1]
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 28 if b[0] == "spin" else 24)
		btn.pressed.connect(_on_button.bind(b[0]))
		add_child(btn)
		_buttons[b[0]] = btn


func open(p: Player) -> void:
	player = p
	visible = true
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_message = "Premi GIRA (Spazio) per giocare"
	_last_win = 0
	_layout()


func close() -> void:
	if spinning:
		return  # prima finisce il giro
	visible = false
	_stop_spin_sound()
	closed.emit()


func bet() -> int:
	return BETS[_bet_i]


func _panel_rect() -> Rect2:
	return Rect2((get_viewport_rect().size - PANEL) * 0.5, PANEL)


func _layout() -> void:
	var r := _panel_rect()
	var y := r.end.y - 78
	_buttons["minus"].position = Vector2(r.position.x + 40, y)
	_buttons["minus"].size = Vector2(56, 52)
	_buttons["plus"].position = Vector2(r.position.x + 210, y)
	_buttons["plus"].size = Vector2(56, 52)
	_buttons["spin"].position = Vector2(r.position.x + 300, y)
	_buttons["spin"].size = Vector2(220, 52)
	_buttons["exit"].position = Vector2(r.end.x - 160, y)
	_buttons["exit"].size = Vector2(120, 52)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_layout()


func _on_button(id: String) -> void:
	match id:
		"spin":
			spin()
		"minus":
			_change_bet(-1)
		"plus":
			_change_bet(1)
		"exit":
			close()


func _change_bet(step: int) -> void:
	if spinning:
		return
	_bet_i = clampi(_bet_i + step, 0, BETS.size() - 1)
	Sfx.play2d("beep", -10.0)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var handled := true
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		close()
	elif event.is_action_pressed("jump") or event.is_action_pressed("ui_accept"):
		spin()
	elif event.is_action_pressed("ui_left"):
		_change_bet(-1)
	elif event.is_action_pressed("ui_right"):
		_change_bet(1)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


## Un giro: si paga la puntata, ogni rullo sceglie dove fermarsi e gira per un tempo diverso.
func spin() -> void:
	if spinning or player == null:
		return
	if player.money < bet() and not player.creative:
		_message = "Non hai abbastanza soldi per puntare € %d" % bet()
		Sfx.play2d("empty", -4.0)
		return
	if not player.creative:
		player.money -= bet()
	spinning = true
	_jackpot = false
	_win_flash = 0.0
	_last_win = 0
	_message = "Gira…"
	_t = 0.0
	for r in 3:
		var n: int = _strips[r].size()
		var stop := _rng.randi_range(0, n - 1)
		_from[r] = _pos[r]
		# Almeno 3 giri interi, poi fino al simbolo scelto; i rulli dopo girano di più.
		var cur := fposmod(_pos[r], float(n))
		var dist := float(n) * (3 + r) + fposmod(float(stop) - cur, float(n))
		_to[r] = _pos[r] + dist
		_dur[r] = 1.2 + r * 0.55
		_stopped[r] = false
	_spin_sound = AudioStreamPlayer.new()
	_spin_sound.stream = Sfx.stream("spin")
	_spin_sound.volume_db = -6.0
	add_child(_spin_sound)
	_spin_sound.play()
	Sfx.play2d("coin", -12.0)


func _process(delta: float) -> void:
	if not visible:
		return
	if size != get_viewport_rect().size:
		position = Vector2.ZERO
		size = get_viewport_rect().size
		_layout()
	_win_flash = maxf(0.0, _win_flash - delta * 0.35)
	if spinning:
		_t += delta
		var all := true
		for r in 3:
			if _stopped[r]:
				continue
			var k := clampf(_t / _dur[r], 0.0, 1.0)
			# Rallenta e alla fine supera di poco il simbolo e torna indietro (rimbalzo del rullo).
			var c1 := 1.25
			var e := 1.0 + (c1 + 1.0) * pow(k - 1.0, 3) + c1 * pow(k - 1.0, 2)
			_pos[r] = lerpf(_from[r], _to[r], e)
			if k >= 1.0:
				_pos[r] = _to[r]
				_stopped[r] = true
				Sfx.play2d("reel_stop", -2.0)
			else:
				all = false
		if all:
			spinning = false
			_stop_spin_sound()
			_payout()
	queue_redraw()


func _stop_spin_sound() -> void:
	if _spin_sound:
		_spin_sound.queue_free()
		_spin_sound = null


## Simbolo sulla riga (−1 sopra, 0 linea di vincita, +1 sotto) del rullo r.
func _symbol_at(r: int, row: int) -> int:
	var strip: Array = _strips[r]
	var i := posmod(int(floorf(_pos[r] + 0.5)) + row, strip.size())
	return int(strip[i])


func _payout() -> void:
	var a := _symbol_at(0, 0)
	var b := _symbol_at(1, 0)
	var c := _symbol_at(2, 0)
	var mult := 0
	if a == b and b == c:
		mult = int(SYMBOLS[a]["pay"])
	elif a == 0 and b == 0:
		mult = 2
	elif a == 0:
		mult = 1
	_last_win = bet() * mult
	if _last_win > 0:
		player.money += _last_win if not player.creative else 0
		_win_flash = 1.0
		_jackpot = a == b and b == c and SYMBOLS[a]["id"] == "seven"
		if _jackpot:
			_message = "JACKPOT!  € %s" % _thousands(_last_win)
			Sfx.play2d("jackpot", 0.0)
		elif mult >= 8:
			_message = "Tris di %s!  Vinci € %s" % [SYMBOLS[a]["name"], _thousands(_last_win)]
			Sfx.play2d("win", -2.0)
		else:
			_message = "Vinci € %s" % _thousands(_last_win)
			Sfx.play2d("coin", -4.0)
	else:
		_message = "Niente questa volta. Ritenta!"


# --- Disegno ------------------------------------------------------------------------------------


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	var r := _panel_rect()
	var now := Time.get_ticks_msec() / 1000.0
	# Mobile: rosso scuro con bordo dorato e lampadine che rincorrono.
	draw_rect(r.grow(10), Color(0.5, 0.36, 0.08))
	draw_rect(r.grow(6), Color(0.95, 0.75, 0.25))
	draw_rect(r, Color(0.32, 0.02, 0.04))
	var bulbs := 44
	var per := r.size * 2.0
	for i in bulbs:
		var t := float(i) / bulbs * (per.x + per.y)
		var p: Vector2
		if t < r.size.x:
			p = r.position + Vector2(t, 0)
		elif t < r.size.x + r.size.y:
			p = r.position + Vector2(r.size.x, t - r.size.x)
		elif t < r.size.x * 2.0 + r.size.y:
			p = r.end - Vector2(t - r.size.x - r.size.y, 0)
		else:
			p = r.position + Vector2(0, r.size.y - (t - r.size.x * 2.0 - r.size.y))
		var speed := 14.0 if (spinning or _win_flash > 0.0) else 4.0
		var on := (i + int(now * speed)) % 4 == 0
		var col := Color(1.0, 0.92, 0.5) if on else Color(0.55, 0.35, 0.12)
		if _win_flash > 0.0 and int(now * 8.0) % 2 == 0:
			col = Color(1.0, 0.3, 0.2) if on else col
		draw_circle(p, 6.0, col)
	# Finestra dei rulli.
	var reels := Rect2(r.position + Vector2(40, 84), Vector2(520, 300))
	draw_rect(reels.grow(6), Color(0.95, 0.75, 0.25))
	draw_rect(reels, Color(0.08, 0.06, 0.07))
	var rw := reels.size.x / 3.0
	var row_h := reels.size.y / 3.0
	for k in 3:
		var cell := Rect2(reels.position + Vector2(k * rw + 6, 0), Vector2(rw - 12, reels.size.y))
		draw_rect(cell, Color(0.97, 0.95, 0.9))
		var strip: Array = _strips[k]
		var frac := _pos[k] + 0.5 - floorf(_pos[k] + 0.5)  # 0..1 tra un simbolo e il successivo
		var base := int(floorf(_pos[k] + 0.5))
		var moving := not _stopped[k]
		for row in range(-2, 3):
			var idx := int(strip[posmod(base + row, strip.size())])
			var cy := cell.position.y + cell.size.y * 0.5 + (float(row) - frac + 0.5) * row_h
			if cy < cell.position.y - row_h * 0.5 or cy > cell.end.y + row_h * 0.5:
				continue
			_symbol(idx, Vector2(cell.position.x + cell.size.x * 0.5, cy), row_h * 0.36, moving)
		# Ombreggiatura sopra e sotto: il rullo è curvo.
		for g in 12:
			var a := 0.5 * (1.0 - g / 12.0)
			draw_rect(Rect2(cell.position.x, cell.position.y + g * 5, cell.size.x, 5), Color(0, 0, 0, a * 0.6))
			draw_rect(Rect2(cell.position.x, cell.end.y - (g + 1) * 5, cell.size.x, 5), Color(0, 0, 0, a * 0.6))
	# Coprire ciò che esce dalla finestra (simboli tagliati).
	var top_y := maxf(r.position.y, reels.position.y - row_h)
	draw_rect(Rect2(reels.position.x - 6, top_y, reels.size.x + 12, reels.position.y - 6 - top_y), Color(0.32, 0.02, 0.04))
	draw_rect(Rect2(reels.position.x - 6, reels.end.y + 6, reels.size.x + 12, row_h), Color(0.32, 0.02, 0.04))
	draw_rect(Rect2(reels.position.x - 6, reels.position.y - 6, reels.size.x + 12, 6), Color(0.95, 0.75, 0.25))
	draw_rect(Rect2(reels.position.x - 6, reels.end.y, reels.size.x + 12, 6), Color(0.95, 0.75, 0.25))
	# Titolo (dopo le coperture, che gli passerebbero sopra).
	_text(Vector2(r.position.x + r.size.x * 0.5, r.position.y + 58), "SLOT FLAMINIO", 40, Color(1.0, 0.84, 0.3), HORIZONTAL_ALIGNMENT_CENTER, Color(0.45, 0.05, 0.02))
	# Linea di vincita.
	var ly := reels.position.y + reels.size.y * 0.5
	var line_col := Color(1.0, 0.15, 0.1, 0.85)
	if _win_flash > 0.0 and int(now * 10.0) % 2 == 0:
		line_col = Color(1.0, 0.95, 0.3)
	draw_line(Vector2(reels.position.x - 16, ly), Vector2(reels.end.x + 16, ly), line_col, 3.0)
	draw_colored_polygon(PackedVector2Array([Vector2(reels.position.x - 26, ly - 10), Vector2(reels.position.x - 12, ly), Vector2(reels.position.x - 26, ly + 10)]), line_col)
	draw_colored_polygon(PackedVector2Array([Vector2(reels.end.x + 26, ly - 10), Vector2(reels.end.x + 12, ly), Vector2(reels.end.x + 26, ly + 10)]), line_col)
	# Tabella dei premi.
	var tx := r.position.x + 590
	var ty := r.position.y + 96
	_text(Vector2(tx, ty), "PREMI (× puntata)", 20, Color(1.0, 0.84, 0.3))
	ty += 14
	for i in range(SYMBOLS.size() - 1, -1, -1):
		ty += 34
		for k in 3:
			_symbol(i, Vector2(tx + 14 + k * 30, ty - 7), 12.0, false)
		_text(Vector2(tx + 110, ty), "× %d" % int(SYMBOLS[i]["pay"]), 20, Color.WHITE)
	ty += 34
	_symbol(0, Vector2(tx + 14, ty - 7), 12.0, false)
	_symbol(0, Vector2(tx + 44, ty - 7), 12.0, false)
	_text(Vector2(tx + 110, ty), "× 2", 20, Color.WHITE)
	ty += 30
	_symbol(0, Vector2(tx + 14, ty - 7), 12.0, false)
	_text(Vector2(tx + 110, ty), "× 1", 20, Color.WHITE)
	# Messaggio, credito, puntata.
	var msg_col := Color(1.0, 0.95, 0.6)
	if _jackpot:
		msg_col = Color.from_hsv(fmod(now * 0.8, 1.0), 0.8, 1.0)
	_text(Vector2(reels.position.x + reels.size.x * 0.5, reels.end.y + 44), _message, 30 if _jackpot else 24, msg_col, HORIZONTAL_ALIGNMENT_CENTER)
	var money := "∞" if player and player.creative else "€ %s" % _thousands(player.money if player else 0)
	_text(Vector2(r.end.x - 40, r.end.y - 96), "Credito  " + money, 22, Color(0.55, 0.95, 0.5), HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(r.position.x + 153, r.end.y - 42), "€ %d" % bet(), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(r.position.x + 153, r.end.y - 92), "PUNTATA", 16, Color(1.0, 0.84, 0.3), HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(r.position.x + r.size.x * 0.5, r.end.y + 40), "Spazio / Invio / A gira  ·  ← → puntata  ·  Esc / B esci", 18, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER)


## Simboli disegnati: niente immagini esterne.
func _symbol(idx: int, c: Vector2, s: float, blur: bool) -> void:
	var id: String = SYMBOLS[idx]["id"]
	var a := 0.55 if blur else 1.0
	match id:
		"cherry":
			draw_line(c + Vector2(-s * 0.45, s * 0.2), c + Vector2(s * 0.1, -s * 0.9), Color(0.2, 0.5, 0.15, a), maxf(2.0, s * 0.1))
			draw_line(c + Vector2(s * 0.45, s * 0.25), c + Vector2(s * 0.1, -s * 0.9), Color(0.2, 0.5, 0.15, a), maxf(2.0, s * 0.1))
			draw_colored_polygon(_ellipse(c + Vector2(s * 0.25, -s * 0.95), Vector2(s * 0.35, s * 0.15), 0.5), Color(0.25, 0.65, 0.2, a))
			draw_circle(c + Vector2(-s * 0.45, s * 0.45), s * 0.42, Color(0.8, 0.02, 0.08, a))
			draw_circle(c + Vector2(s * 0.45, s * 0.5), s * 0.42, Color(0.75, 0.0, 0.06, a))
			draw_circle(c + Vector2(-s * 0.58, s * 0.3), s * 0.1, Color(1, 1, 1, 0.6 * a))
			draw_circle(c + Vector2(s * 0.32, s * 0.35), s * 0.1, Color(1, 1, 1, 0.6 * a))
		"lemon":
			draw_colored_polygon(_ellipse(c, Vector2(s * 0.95, s * 0.65), 0.0), Color(0.95, 0.85, 0.1, a))
			draw_circle(c + Vector2(s * 0.92, 0), s * 0.14, Color(0.95, 0.85, 0.1, a))
			draw_circle(c + Vector2(-s * 0.92, 0), s * 0.14, Color(0.95, 0.85, 0.1, a))
			draw_colored_polygon(_ellipse(c + Vector2(-s * 0.25, -s * 0.25), Vector2(s * 0.3, s * 0.12), -0.3), Color(1, 1, 0.8, 0.7 * a))
		"orange":
			draw_circle(c, s * 0.85, Color(1.0, 0.55, 0.05, a))
			draw_circle(c + Vector2(-s * 0.3, -s * 0.3), s * 0.18, Color(1, 0.85, 0.6, 0.7 * a))
			draw_colored_polygon(_ellipse(c + Vector2(s * 0.2, -s * 0.9), Vector2(s * 0.32, s * 0.13), -0.4), Color(0.2, 0.6, 0.2, a))
		"bell":
			var pts := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				var y := lerpf(-s * 0.85, s * 0.55, t)
				var hw := lerpf(s * 0.28, s * 0.85, pow(t, 1.6))
				pts.append(c + Vector2(-hw, y))
			for i in range(12, -1, -1):
				var t := float(i) / 12.0
				var y := lerpf(-s * 0.85, s * 0.55, t)
				var hw := lerpf(s * 0.28, s * 0.85, pow(t, 1.6))
				pts.append(c + Vector2(hw, y))
			draw_colored_polygon(pts, Color(1.0, 0.8, 0.15, a))
			draw_rect(Rect2(c + Vector2(-s * 0.95, s * 0.5), Vector2(s * 1.9, s * 0.2)), Color(0.85, 0.62, 0.1, a))
			draw_circle(c + Vector2(0, s * 0.8), s * 0.17, Color(0.85, 0.62, 0.1, a))
			draw_circle(c + Vector2(0, -s * 0.9), s * 0.12, Color(0.85, 0.62, 0.1, a))
		"bar":
			draw_rect(Rect2(c - Vector2(s * 1.05, s * 0.5), Vector2(s * 2.1, s * 1.0)), Color(0.1, 0.1, 0.12, a))
			draw_rect(Rect2(c - Vector2(s * 0.95, s * 0.4), Vector2(s * 1.9, s * 0.8)), Color(0.97, 0.95, 0.9, a))
			_text(c + Vector2(0, s * 0.3), "BAR", int(s * 0.85), Color(0.1, 0.1, 0.12, a), HORIZONTAL_ALIGNMENT_CENTER)
		"star":
			var sp := PackedVector2Array()
			for i in 10:
				var ang := -PI / 2 + i * PI / 5.0
				var rr := s * (0.95 if i % 2 == 0 else 0.42)
				sp.append(c + Vector2(cos(ang), sin(ang)) * rr)
			draw_colored_polygon(sp, Color(0.98, 0.7, 0.05, a))
			draw_polyline(sp + PackedVector2Array([sp[0]]), Color(0.75, 0.4, 0.0, a), maxf(1.5, s * 0.06))
		"seven":
			_text(c + Vector2(s * 0.04, s * 0.66 + 2), "7", int(s * 2.1), Color(0.3, 0.0, 0.0, a), HORIZONTAL_ALIGNMENT_CENTER)
			_text(c + Vector2(0, s * 0.66), "7", int(s * 2.1), Color(0.9, 0.05, 0.05, a), HORIZONTAL_ALIGNMENT_CENTER)


func _ellipse(c: Vector2, r: Vector2, rot: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(rot))
	return out


func _text(pos: Vector2, s: String, fsize: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, outline := Color(0, 0, 0, 0.0)) -> void:
	var width := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= width
	if outline.a > 0.0:
		draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 6, outline)
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
