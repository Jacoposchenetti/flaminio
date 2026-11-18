class_name Hud
extends Control

## Interfaccia di gioco: vita e armatura, soldi, arma e colpi, mirino, cannocchiale, schermata di morte,
## finestra del negozio.

signal shop_closed

var player: Player
var _font: Font
var _shop_panel: PanelContainer
var _shop_list: VBoxContainer
var _shop_title: Label
var _shop_money: Label
var _shop: Dictionary = {}
var _shop_items: Array = []
var _shops: Shops
var wanted_info: Callable  # func() -> [stelle, secondi senza essere visto]


func setup(p: Player, shops: Shops) -> void:
	player = p
	_shops = shops
	_font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shop_panel()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var w := size.x
	var h := size.y
	# Vignetta rossa quando si viene colpiti.
	if player.hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.0, 0.0, player.hurt_flash * 0.25))
	# Barre di vita e armatura sotto la minimappa (come in GTA, ma a destra).
	var x0 := w - 290.0
	var y0 := 300.0
	draw_rect(Rect2(x0, y0, 270, 10), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x0, y0, 270 * player.health / Player.MAX_HEALTH, 10), Color(0.3, 0.8, 0.35) if player.health > 30 else Color(0.9, 0.2, 0.15))
	draw_rect(Rect2(x0, y0 + 13, 270, 6), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x0, y0 + 13, 270 * player.armor / Player.MAX_ARMOR, 6), Color(0.3, 0.6, 1.0))
	_text(Vector2(w - 20, y0 + 52), "€ %s" % _thousands(player.money), 30, Color(0.55, 0.9, 0.5), HORIZONTAL_ALIGNMENT_RIGHT)
	var wi_star: Array = wanted_info.call() if wanted_info.is_valid() else [0, 0.0]
	if int(wi_star[0]) > 0:
		# Stelle del ricercato: lampeggiano quando gli agenti non ti vedono.
		var fade := float(wi_star[1]) > 0.5 and int(Time.get_ticks_msec() / 400) % 2 == 0
		for i in Police.MAX_STARS:
			var cx := w - 38.0 - (Police.MAX_STARS - 1 - i) * 30.0
			var filled := i < int(wi_star[0])
			_star(Vector2(cx, y0 + 150), 12.0, Color(1, 1, 1, 0.35 if fade else 1.0) if filled else Color(0, 0, 0, 0.35))
	var wi := Weapons.info(player.weapon)
	_text(Vector2(w - 20, y0 + 84), String(wi["name"]), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	var rt := player.rounds_text()
	if rt != "":
		_text(Vector2(w - 20, y0 + 110), rt, 20, Color(1, 0.9, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	if player.stash > 0:
		_text(Vector2(w - 20, y0 + 190), "Pacchetti: %d" % player.stash, 20, Color(0.8, 0.6, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
	# Mirino.
	var c := size * 0.5
	if player.aiming and player.weapon == "cecchino":
		_scope(c)
	elif player.aiming or (not player.dead and (
			(wi["kind"] != "melee" and player.vehicle == null) or String(wi["kind"]) in ["gun", "rocket"])):
		var r := 10.0 if player.aiming else 6.0
		var col := Color(1, 1, 1, 0.9 if player.aiming else 0.45)
		for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * r * 0.5, c + d * r * 1.4, col, 2.0)
		draw_circle(c, 1.5, col)
	if player.dead:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.0, 0.0, 0.45))
		_text(Vector2(w * 0.5, h * 0.45), "SEI MORTO", 72, Color(0.85, 0.1, 0.1), HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(w * 0.5, h * 0.45 + 50), "Ti risvegli all'ospedale tra poco…", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	elif not _shop.is_empty():
		pass
	elif _shops and not _shops.shop_here().is_empty() and player.vehicle == null:
		_text(Vector2(w * 0.5, h - 140), "E (joypad: croce su)  compra: %s" % _shops.shop_here()["name"], 22, Color(1, 0.95, 0.7), HORIZONTAL_ALIGNMENT_CENTER)


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2 + k * PI / 5
		var rr := r if k % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.8), 1.5)


func _scope(c: Vector2) -> void:
	var r := minf(size.x, size.y) * 0.42
	# Nero fuori dal cerchio del cannocchiale.
	var ring := PackedVector2Array()
	for i in 65:
		var a := TAU * i / 64.0
		ring.append(c + Vector2(cos(a), sin(a)) * r)
	draw_rect(Rect2(0, 0, c.x - r, size.y), Color.BLACK)
	draw_rect(Rect2(c.x + r, 0, size.x - c.x - r, size.y), Color.BLACK)
	for i in 64:
		var a0 := ring[i]
		var a1 := ring[i + 1]
		var e0 := Vector2(a0.x, 0.0 if a0.y < c.y else size.y)
		var e1 := Vector2(a1.x, 0.0 if a1.y < c.y else size.y)
		if (a0.y < c.y) == (a1.y < c.y):
			draw_colored_polygon(PackedVector2Array([a0, a1, e1, e0]), Color.BLACK)
	draw_arc(c, r, 0, TAU, 96, Color(0.05, 0.05, 0.05), 6.0)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0, 0, 0, 0.9), 1.5)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0, 0, 0, 0.9), 1.5)
	for k in range(1, 5):
		draw_line(c + Vector2(-6, k * r * 0.12), c + Vector2(6, k * r * 0.12), Color(0, 0, 0, 0.9), 1.5)


func _text(pos: Vector2, s: String, fsize: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var tw := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var x := pos.x - (tw if align == HORIZONTAL_ALIGNMENT_RIGHT else (tw * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 0.0))
	draw_string_outline(_font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 7, Color(0, 0, 0, 0.85))
	draw_string(_font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# --- Negozio ------------------------------------------------------------------------------------


func _build_shop_panel() -> void:
	_shop_panel = PanelContainer.new()
	_shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	_shop_panel.custom_minimum_size = Vector2(520, 0)
	_shop_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_shop_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_shop_panel.visible = false
	add_child(_shop_panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	_shop_panel.add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	m.add_child(box)
	_shop_title = Label.new()
	_shop_title.add_theme_font_size_override("font_size", 26)
	box.add_child(_shop_title)
	_shop_money = Label.new()
	_shop_money.modulate = Color(0.55, 0.9, 0.5)
	box.add_child(_shop_money)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 380)
	scroll.follow_focus = true  # col joypad la lista scorre seguendo la voce selezionata
	box.add_child(scroll)
	_shop_list = VBoxContainer.new()
	_shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_shop_list)
	var close := Button.new()
	close.text = "Esci (Esc · joypad: B / Cerchio)"
	close.pressed.connect(close_shop)
	box.add_child(close)


func shop_open() -> bool:
	return not _shop.is_empty()


func open_shop(shop: Dictionary) -> void:
	_shop = shop
	_shop_items = _shops.items(shop)
	_shop_title.text = String(shop["name"])
	for ch in _shop_list.get_children():
		ch.queue_free()
	var first: Button = null
	for it: Array in _shop_items:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = String(it[0])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := Button.new()
		b.text = "€ %s" % _thousands(int(it[1]))
		b.custom_minimum_size = Vector2(110, 0)
		b.pressed.connect(func() -> void: _buy(it))
		row.add_child(b)
		_shop_list.add_child(row)
		if first == null:
			first = b
	_shop_panel.visible = true
	_refresh_money()
	if first:
		first.grab_focus.call_deferred()  # joypad e frecce: su/giù per scegliere, A / Croce / Invio per comprare


func close_shop() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f:
		f.release_focus()
	_shop = {}
	_shop_panel.visible = false
	shop_closed.emit()


func _buy(it: Array) -> void:
	if player.money < int(it[1]):
		_shop_money.text = "Non hai abbastanza soldi (€ %s)" % _thousands(player.money)
		return
	player.money -= int(it[1])
	(it[2] as Callable).call()
	Sfx.play2d("coin", -4.0)
	_refresh_money()


func _refresh_money() -> void:
	_shop_money.text = "Hai € %s · vita %d · armatura %d" % [_thousands(player.money), roundi(player.health), roundi(player.armor)]
