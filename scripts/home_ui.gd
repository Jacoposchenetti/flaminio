class_name HomeUI
extends Control

## Interfaccia delle case: pannello al portone (comprare, visitare, entrare, vendere), cassaforte (contanti e
## droga al sicuro), e arredamento: vista dall'alto senza soffitto, catalogo a sinistra, il mobile scelto segue il
## mouse; rotella o R per girarlo, clic sinistro per posarlo, clic destro o Esc per lasciar perdere. Cliccando un
## mobile già posato lo si sposta (o lo si rivende col pulsante).

signal closed

var main: Node
var homes: Homes
var mode := ""  # "door", "safe", "edit"
var _door_id := ""
var _panel: PanelContainer
var _box: VBoxContainer
var _status: Label
var _cam: Camera3D
var _ghost: Node3D
var _ghost_entry: Array = []  # [id, x, z, yaw]
var _ghost_old := false  # il fantasma è un mobile già posato (spostato)
var _old_entry: Array = []


func setup(m: Node, h: Homes) -> void:
	main = m
	homes = h
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.95)
	sb.border_color = Color(0.4, 0.75, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)
	var outer := VBoxContainer.new()
	margin.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(420, 420)
	outer.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1.0, 0.9, 0.55)
	_status.custom_minimum_size = Vector2(420, 0)
	outer.add_child(_status)


func open_door(id: String) -> void:
	mode = "door"
	_door_id = id
	_status.text = ""
	_show()


func open_safe() -> void:
	mode = "safe"
	_status.text = ""
	_show()


func open_edit() -> void:
	mode = "edit"
	_status.text = "Scegli un mobile dal catalogo, o clicca un mobile per spostarlo."
	_cam = Camera3D.new()
	var room := homes.room_node()
	var s := homes.room_size()
	room.add_child(_cam)
	_cam.position = Vector3(0, maxf(s.x, s.y) * 0.95 + 2.0, s.y * 0.5 + s.y * 0.35)
	_cam.rotation = Vector3(-1.2, 0, 0)
	_cam.fov = 60.0
	_cam.current = true
	homes.ceiling().visible = false
	_show()


func _show() -> void:
	visible = true
	main.player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rebuild()


func close_ui() -> void:
	if mode == "edit":
		_cancel_ghost()
		if _cam:
			_cam.queue_free()
			_cam = null
		main.player.camera.current = true
		if homes.ceiling():
			homes.ceiling().visible = true
	mode = ""
	visible = false
	closed.emit()


func _process(_delta: float) -> void:
	if not visible:
		return
	var vs := get_viewport_rect().size
	if size != vs:
		position = Vector2.ZERO
		size = vs
	if mode == "edit":
		_panel.position = Vector2(16, 16)
		_move_ghost(get_viewport().get_mouse_position())
	else:
		_panel.position = ((vs - _panel.size) * 0.5).round()


# --- Contenuto ------------------------------------------------------------------------------------


func rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	match mode:
		"door":
			_build_door()
		"safe":
			_build_safe()
		"edit":
			_build_edit()


func _line(text: String, col := Color.WHITE, size := 16) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = col
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(l)


func _btn(text: String, cb: Callable, ok := true) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = not ok
	b.pressed.connect(cb)
	_box.add_child(b)


func _build_door() -> void:
	var p := homes.prop(_door_id)
	var t: Dictionary = Homes.TYPES[p["type"]]
	var mine := homes.owned.has(_door_id)
	_line("%s · %s" % [t["name"], p["name"]], Color(0.6, 1.0, 0.7), 24)
	_line("Zona: %s · %d × %d m" % [Crime.ZONES[int(p["zone"])]["name"], int((t["size"] as Vector2).x), int((t["size"] as Vector2).y)], Color(0.85, 0.85, 0.85))
	if mine:
		_line("È casa tua. Dentro puoi arredarla (O), tenere soldi e droga in cassaforte, cambiarti all'armadio e dormire. Quando muori rinasci qui.")
		_btn("Entra", func() -> void: _enter(false))
		_btn("Vendi (ti danno € %s)" % SlotMachine._thousands(homes.sell_price(_door_id)), func() -> void:
			_status.text = homes.sell(_door_id)
			rebuild())
	else:
		_line("In vendita: € %s (hai € %s in tasca; i soldi in banca vanno prelevati)." % [SlotMachine._thousands(int(p["price"])), SlotMachine._thousands(main.player.money)])
		_line("Comprata, la arredi come vuoi e rinasci qui quando muori.", Color(0.8, 0.8, 0.8))
		_btn("Compra", func() -> void:
			_status.text = homes.buy(_door_id)
			rebuild(), main.player.money >= int(p["price"]) or main.player.creative)
		_btn("Visita", func() -> void: _enter(true))
	_btn("Chiudi (Esc)", close_ui)


func _enter(visit: bool) -> void:
	var msg := homes.enter(_door_id, visit)
	close_ui()
	if msg != "":
		main._system(msg)


func _build_safe() -> void:
	var st: Dictionary = homes.owned[homes.inside]
	var pl: Player = main.player
	_line("Cassaforte", Color(1.0, 0.85, 0.4), 24)
	_line("Dentro: € %s. In tasca: € %s. Quello che è qui non lo perdi quando muori." % [SlotMachine._thousands(int(st.get("cash", 0))), SlotMachine._thousands(pl.money)])
	for v: int in [1000, 10000, -1]:
		var vv := v
		_btn("Metti € %s" % ("tutto" if v < 0 else SlotMachine._thousands(v)), func() -> void:
			var n := pl.money if vv < 0 else mini(vv, pl.money)
			pl.money -= n
			st["cash"] = int(st.get("cash", 0)) + n
			homes.save()
			rebuild())
		_btn("Prendi € %s" % ("tutto" if v < 0 else SlotMachine._thousands(v)), func() -> void:
			var n := int(st.get("cash", 0)) if vv < 0 else mini(vv, int(st.get("cash", 0)))
			st["cash"] = int(st.get("cash", 0)) - n
			pl.money += n
			homes.save()
			rebuild())
	var drugs: Dictionary = st.get("drugs", {})
	st["drugs"] = drugs
	var dl := []
	for d: String in drugs:
		if int(drugs[d]) > 0:
			dl.append("%s %d" % [Crime.DRUGS[d]["name"], int(drugs[d])])
	_line("Droga nascosta: " + (", ".join(dl) if not dl.is_empty() else "niente"), Color(0.8, 0.6, 1.0))
	_btn("Nascondi tutta la droga che hai addosso", func() -> void:
		for d: String in pl.drugs.keys():
			drugs[d] = int(drugs.get(d, 0)) + int(pl.drugs[d])
		pl.drugs = {}
		homes.save()
		rebuild())
	_btn("Riprendi la droga (fino a %d dosi addosso)" % Crime.MAX_DOSES, func() -> void:
		for d: String in drugs.keys():
			var room := Crime.MAX_DOSES - pl.stash
			var n := mini(room, int(drugs[d]))
			if n > 0:
				pl.drugs[d] = int(pl.drugs.get(d, 0)) + n
				drugs[d] = int(drugs[d]) - n
		homes.save()
		rebuild())
	_btn("Chiudi (Esc)", close_ui)


func _build_edit() -> void:
	_line("Arreda", Color(0.6, 1.0, 0.7), 24)
	_line("Rotella o R: gira · clic sinistro: posa · clic destro: lascia · clic su un mobile: spostalo", Color(0.8, 0.8, 0.8), 13)
	if _ghost and _ghost_old:
		var id: String = _ghost_entry[0]
		_btn("Rivendi %s (€ %s)" % [Homes.FURNITURE[id]["name"], SlotMachine._thousands(int(int(Homes.FURNITURE[id]["price"]) * Homes.FURN_BACK))], func() -> void:
			var refund := int(int(Homes.FURNITURE[id]["price"]) * Homes.FURN_BACK)
			main.player.money += refund
			(homes.owned[homes.inside]["furniture"] as Array).erase(_old_entry)
			homes.save()
			_ghost.queue_free()
			_ghost = null
			_status.text = "Rivenduto per € %d." % refund
			rebuild())
	for id: String in Homes.FURN_ORDER:
		var d: Dictionary = Homes.FURNITURE[id]
		var iid := id
		_btn("%s · € %s" % [d["name"], SlotMachine._thousands(int(d["price"]))], func() -> void: _new_ghost(iid),
			main.player.money >= int(d["price"]) or main.player.creative)
	_btn("Fatto (Esc)", close_ui)


# --- Arredamento ----------------------------------------------------------------------------------


func _new_ghost(id: String) -> void:
	_cancel_ghost()
	_ghost = Homes.make_furniture(id)
	homes.room_node().add_child(_ghost)
	_ghost_entry = [id, 1.0, 1.0, 0.0]
	_ghost_old = false
	_ghost_body(false)
	_status.text = "%s: posalo dove vuoi (clic sinistro)." % Homes.FURNITURE[id]["name"]


func _ghost_body(on: bool) -> void:
	for c in _ghost.get_children():
		if c is StaticBody3D:
			for s in c.get_children():
				if s is CollisionShape3D:
					s.disabled = not on


func _cancel_ghost() -> void:
	if _ghost == null:
		return
	_ghost.queue_free()
	_ghost = null
	if _ghost_old:
		homes.place(_old_entry)  # rimesso dov'era
	_ghost_old = false


func _floor_point(mouse: Vector2) -> Variant:
	if _cam == null:
		return null
	var o := _cam.project_ray_origin(mouse)
	var n := _cam.project_ray_normal(mouse)
	var y := homes.room_node().global_position.y
	if absf(n.y) < 0.001:
		return null
	var t := (y - o.y) / n.y
	if t < 0.0:
		return null
	return o + n * t


func _move_ghost(mouse: Vector2) -> void:
	if _ghost == null:
		return
	var hit: Variant = _floor_point(mouse)
	if hit == null:
		return
	var local := homes.room_node().to_local(hit)
	var s := homes.room_size()
	var x := clampf(snappedf(local.x + s.x * 0.5, 0.25), 0.3, s.x - 0.3)
	var z := clampf(snappedf(local.z, 0.25), 0.6, s.y - 0.3)
	_ghost_entry[1] = x
	_ghost_entry[2] = z
	_ghost.position = Vector3(x - s.x * 0.5, 0.02, z)
	_ghost.rotation.y = float(_ghost_entry[3])


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if mode == "edit" and _ghost:
			_cancel_ghost()
			rebuild()
		else:
			close_ui()
		get_viewport().set_input_as_handled()
		return
	if mode != "edit":
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_R and _ghost:
		_ghost_entry[3] = float(_ghost_entry[3]) + PI / 2
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed:
		if _panel.get_global_rect().has_point(event.position):
			return  # clic sul catalogo
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _ghost:
			_ghost_entry[3] = float(_ghost_entry[3]) + (PI / 12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -PI / 12)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_ghost()
			rebuild()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if _ghost:
				_drop()
			else:
				_pick(event.position)
		get_viewport().set_input_as_handled()


func _drop() -> void:
	var id: String = _ghost_entry[0]
	var price := int(Homes.FURNITURE[id]["price"])
	if not _ghost_old:
		if main.player.money < price and not main.player.creative:
			_status.text = "Non hai abbastanza soldi."
			return
		if not main.player.creative:
			main.player.money -= price
	var entry := _ghost_entry.duplicate()
	_ghost.queue_free()
	_ghost = null
	_ghost_old = false
	homes.place(entry)
	Sfx.play2d("coin", -8.0)
	_status.text = "%s posato." % Homes.FURNITURE[id]["name"]
	rebuild()


func _pick(mouse: Vector2) -> void:
	var o := _cam.project_ray_origin(mouse)
	var n := _cam.project_ray_normal(mouse)
	var q := PhysicsRayQueryParameters3D.create(o, o + n * 60.0, Homes.FURN_LAYER)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var node: Node = hit["collider"]
	while node and not node.has_meta("entry"):
		node = node.get_parent()
	if node == null:
		return
	var entry: Array = node.get_meta("entry")
	_old_entry = entry
	homes.remove_item(node as Node3D, false)
	_ghost = Homes.make_furniture(String(entry[0]))
	homes.room_node().add_child(_ghost)
	_ghost_entry = entry.duplicate()
	_ghost_old = true
	_ghost_body(false)
	_status.text = "Spostalo e clicca per posarlo, o rivendilo."
	rebuild()
