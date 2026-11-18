class_name StartMenu
extends Control

## Schermata iniziale: nome, personaggio, gioco da solo, ospitare o entrare nella partita di un amico.

signal start(mode: String, player_name: String, model_index: int, address: String)

var _name: LineEdit
var _model: OptionButton
var _address: LineEdit
var _status: Label
var police_check: CheckBox


func setup(models: Array, player_name: String, model_index: int, address: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.custom_minimum_size = Vector2(460, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Flaminio"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_box = box

	box.add_child(_caption("Il tuo nome"))
	_name = LineEdit.new()
	_name.text = player_name
	_name.max_length = 20
	_name.select_all_on_focus = true
	box.add_child(_name)

	box.add_child(_caption("Personaggio (in gioco si cambia con C)"))
	_model = OptionButton.new()
	for m: String in models:
		_model.add_item(Human.label(m))
	_model.select(clampi(model_index, 0, models.size() - 1))
	box.add_child(_model)

	police_check = CheckBox.new()
	police_check.text = "Polizia attiva (in gioco: F3; in rete decide chi ospita)"
	police_check.button_pressed = true
	box.add_child(police_check)

	var solo := Button.new()
	solo.text = "Gioca da solo"
	solo.pressed.connect(func() -> void: _go("solo"))
	box.add_child(solo)

	box.add_child(HSeparator.new())
	var host := Button.new()
	host.text = "Ospita una partita"
	host.pressed.connect(func() -> void: _go("host"))
	box.add_child(host)
	var ips := my_addresses()
	var hint := _caption(
		"Gli amici si collegano a: " + (", ".join(ips) if not ips.is_empty() else "(nessun indirizzo trovato)")
		+ "\nDa Internet (reti diverse, senza Tailscale): ospitando, il gioco apre la porta sul router e "
		+ "scrive in chat l'indirizzo pubblico da mandare all'amico."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(hint)

	box.add_child(HSeparator.new())
	box.add_child(_caption("Indirizzo di chi ospita (Tailscale 100.x.y.z, o quello pubblico da Internet)"))
	var row := HBoxContainer.new()
	_address = LineEdit.new()
	_address.text = address
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text_submitted.connect(func(_t: String) -> void: _go("join"))
	row.add_child(_address)
	var join := Button.new()
	join.text = "Entra"
	join.pressed.connect(func() -> void: _go("join"))
	row.add_child(join)
	box.add_child(row)

	_status = Label.new()
	_status.modulate = Color(1, 0.85, 0.5)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_status)
	var pad := _caption("Senza mouse: frecce / croce del joypad per spostarti, Invio / A / Croce per scegliere")
	pad.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(pad)
	_solo_btn = solo
	_join_btn = join
	visibility_changed.connect(focus_default)
	focus_default.call_deferred()


var _solo_btn: Button
var _join_btn: Button
var _box: VBoxContainer
var _update_btn: Button
var _updater: Updater


## Riga "versione N" con il pulsante Aggiorna, subito sotto il titolo. Controlla da solo all'avvio.
func attach_updater(u: Updater) -> void:
	_updater = u
	var row := HBoxContainer.new()
	var ver := _caption("Versione %d" % Updater.local_version() if Updater.can_update() else "Versione di sviluppo")
	ver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ver)
	_update_btn = Button.new()
	_update_btn.text = "Cerca aggiornamenti"
	_update_btn.pressed.connect(_on_update_pressed)
	row.add_child(_update_btn)
	_box.add_child(row)
	_box.move_child(row, 1)
	u.status.connect(func(t: String) -> void: _status.text = t)
	u.available.connect(func(v: int) -> void:
		_update_btn.text = "Aggiorna alla versione %d" % v
		_update_btn.modulate = Color(0.6, 1, 0.6)
		_status.text = "È uscita la versione %d: premi \"Aggiorna\" (scarica solo i file cambiati e riavvia il gioco)." % v)
	u.finished_check.connect(func(v: int) -> void:
		_update_btn.disabled = false
		if v >= 0 and v <= Updater.local_version():
			_update_btn.text = "Cerca aggiornamenti"
			if _checked_by_hand:
				_status.text = "Hai già l'ultima versione (%d)." % Updater.local_version())
	if Updater.can_update():
		u.check.call_deferred()


var _checked_by_hand := false


func _on_update_pressed() -> void:
	if _updater.busy:
		return
	if _update_btn.text.begins_with("Aggiorna alla"):
		_update_btn.disabled = true
		_update_btn.text = "Aggiornamento…"
		_updater.install()
	else:
		_checked_by_hand = true
		_update_btn.disabled = true
		_status.text = "Controllo…"
		_updater.check()


## Fuoco iniziale, per usare il menu con tastiera o joypad: il nome la prima volta, poi "Entra" se c'è già
## un indirizzo, altrimenti "Gioca da solo".
func focus_default() -> void:
	if not is_visible_in_tree() or _name == null:
		return
	if _name.text == "Giocatore" or _name.text == "":
		_name.grab_focus()
	elif _address.text != "":
		_join_btn.grab_focus()
	else:
		_solo_btn.grab_focus()


func set_status(text: String) -> void:
	_status.text = text
	focus_default.call_deferred()


## Indirizzi di questo PC utili agli amici: prima Tailscale (100.64-127.x.x), poi la rete di casa.
static func my_addresses() -> PackedStringArray:
	var tailscale := PackedStringArray()
	var lan := PackedStringArray()
	for ip in IP.get_local_addresses():
		if ip.contains(":"):
			continue
		var parts := ip.split(".")
		if parts[0] == "100" and int(parts[1]) >= 64 and int(parts[1]) <= 127:
			tailscale.append(ip + " (Tailscale)")
		elif ip.begins_with("192.168.") or ip.begins_with("10."):
			lan.append(ip + " (stessa rete di casa)")
	tailscale.append_array(lan)
	return tailscale


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.modulate = Color(1, 1, 1, 0.75)
	return l


func _go(mode: String) -> void:
	var n := _name.text.strip_edges()
	if n == "":
		n = "Giocatore"
	if mode == "join" and _address.text.strip_edges() == "":
		set_status("Scrivi l'indirizzo di chi ospita.")
		return
	start.emit(mode, n, _model.selected, _address.text.strip_edges())
