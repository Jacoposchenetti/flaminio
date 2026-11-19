class_name ClanUI
extends Control

## Pannello dei clan (tasto U) e dialogo con un boss (E davanti a lui). Mostra la fama criminale, la zona in cui
## sei e di chi è, il tuo clan (rango, cassa, indagine, zone, rapporti, spacciatori, lavori) e i comandi:
## rinforzi, corruzione, assumere spacciatori, fondare un clan, chiedere di entrare, accettare chi chiede.
## Le azioni vanno a chi ospita (main.clan_request); il pannello si ridisegna quando arriva lo stato nuovo.

signal closed

var main: Node
var clans: Clans
var boss_clan := -1  # >= 0: dialogo con il boss di quel clan
var _panel: PanelContainer
var _box: VBoxContainer
var _status: Label
var _drug: OptionButton
var _doses: SpinBox
var _name_edit: LineEdit
var _fame_edit: SpinBox
var _fee_edit: SpinBox
var _withdraw: SpinBox


func setup(m: Node, c: Clans) -> void:
	main = m
	clans = c
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(760, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.07, 0.96)
	sb.border_color = Color(0.55, 0.42, 0.2)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_panel.add_child(margin)
	var outer := VBoxContainer.new()
	margin.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1.0, 0.9, 0.55)
	outer.add_child(_status)
	var close := Button.new()
	close.text = "Chiudi (Esc · joypad: B)"
	close.pressed.connect(close_ui)
	outer.add_child(close)
	clans.changed.connect(func() -> void:
		if visible:
			rebuild())


func _process(_delta: float) -> void:
	if not visible:
		return
	var vs := get_viewport_rect().size
	if size != vs:
		position = Vector2.ZERO
		size = vs
	_panel.position = ((vs - _panel.size) * 0.5).round()


func open_panel() -> void:
	boss_clan = -1
	_status.text = ""
	visible = true
	rebuild()


func open_boss(id: int) -> void:
	boss_clan = id
	_status.text = ""
	visible = true
	rebuild()


func close_ui() -> void:
	visible = false
	closed.emit()


func show_reply(text: String) -> void:
	_status.text = text
	if visible:
		rebuild()


func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)):
		close_ui()
		get_viewport().set_input_as_handled()


func _me() -> String:
	return main.my_name


func _player() -> Player:
	return main.player


# --- Costruzione ------------------------------------------------------------------------------------


func rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	if boss_clan >= 0:
		_build_boss()
	else:
		_build_panel()


func _title(text: String, col := Color(1.0, 0.85, 0.4), size := 26) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.modulate = col
	_box.add_child(l)


func _line(text: String, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = col
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(l)
	return l


func _button(text: String, cb: Callable, enabled := true, parent: Node = null) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.pressed.connect(cb)
	(parent if parent else _box).add_child(b)
	return b


func _bar(value: float, col: Color) -> void:
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.value = clampf(value, 0.0, 1.0)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 10)
	pb.modulate = col
	_box.add_child(pb)


func _fame_header() -> void:
	var f: int = main.fame
	var span := Crime.level_span(f)
	_title("Fama criminale: %d · %s" % [f, Crime.level_name(f)], Color(1.0, 0.85, 0.4), 22)
	_bar(float(f - int(span[0])) / maxf(1.0, float(int(span[1]) - int(span[0]))), Color(1.0, 0.7, 0.2))
	var i := Crime.level_index(f)
	if i + 1 < Crime.LEVELS.size():
		_line("Prossimo livello: %s a %d. Si sale con omicidi, rapine, furti, spaccio, uomini dei clan uccisi, fughe dalla polizia." % [Crime.LEVELS[i + 1][1], int(Crime.LEVELS[i + 1][0])], Color(0.8, 0.8, 0.8))


func _zone_line() -> void:
	var p := _player()
	var z := Crime.zone_of(Vector2(p.global_position.x, p.global_position.z))
	var owner := clans.zone_owner(z)
	var c := clans.clan(owner)
	var t := "Sei a %s: " % Crime.ZONES[z]["name"]
	t += ("territorio di %s." % c["name"]) if not c.is_empty() else "nessuno la controlla."
	var r := float(clans.rage.get("%d|%s" % [owner, _me()], 0.0))
	if r >= Clans.RAGE_HUNT:
		t += "  Ti stanno dando la caccia!"
	elif r >= Clans.RAGE_WARN:
		t += "  Ti hanno avvisato: non spacciare qui."
	_line(t, clans.color_of(owner).lightened(0.35) if owner >= 0 else Color.WHITE)


func _rel_text(v: int) -> String:
	if v <= Clans.WAR:
		return "GUERRA"
	if v < -15:
		return "ostili"
	if v >= 50:
		return "alleati"
	return "neutrali"


func _build_panel() -> void:
	_fame_header()
	_zone_line()
	_box.add_child(HSeparator.new())
	var mine := clans.clan_of(_me())
	if mine < 0:
		_build_no_clan()
	else:
		_build_my_clan(mine)
	_box.add_child(HSeparator.new())
	_title("I clan del quartiere", Color(0.9, 0.9, 0.9), 20)
	for c: Dictionary in clans.clans:
		var zs := []
		for z in clans.zones.size():
			if clans.zone_owner(z) == int(c["id"]):
				zs.append(Crime.ZONES[z]["name"])
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s · capo %s · %d affiliati · zone: %s" % [c["name"], c["boss"], (c["members"] as Dictionary).size(), ", ".join(zs) if not zs.is_empty() else "nessuna"]
		l.modulate = clans.color_of(int(c["id"])).lightened(0.3)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if not c["npc"] and mine < 0:
			var b := Button.new()
			b.text = "Chiedi di entrare" + ((" (fama %d, € %d)" % [int(c["fame"]), int(c["fee"])]) if int(c["fee"]) > 0 or int(c["fame"]) > 0 else "")
			b.disabled = (c["requests"] as Array).has(_me()) or main.fame < int(c["fame"]) or _player().money < int(c["fee"])
			var cid := int(c["id"])
			b.pressed.connect(func() -> void: main.clan_request("apply", [cid]))
			row.add_child(b)
		_box.add_child(row)


func _build_no_clan() -> void:
	_title("Non sei in un clan", Color(0.9, 0.9, 0.9), 20)
	_line("Per entrare in un clan storico vai dal suo boss (simbolo ☠ sulla mappa) e premi E: ti dirà le sue condizioni. " +
		"Un clan ti copre con la polizia, ti dà lavori e ti fa tenere spacciatori al tuo soldo. Ma attira anche l'attenzione " +
		"della polizia e l'odio dei clan rivali.", Color(0.85, 0.85, 0.85))
	_box.add_child(HSeparator.new())
	_title("Fonda un clan", Color(1.0, 0.85, 0.4), 20)
	var ok: bool = main.fame >= Crime.FOUND_FAME and _player().money >= Crime.FOUND_COST
	_line("Serve fama %d (Criminale) e € %s. Sarai il capo: deciderai chi entra e a quali condizioni, prenderai una parte delle entrate delle zone che conquisti." % [Crime.FOUND_FAME, _thousands(Crime.FOUND_COST)])
	var row := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Nome del clan"
	_name_edit.max_length = 28
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name_edit)
	_button("Fonda", func() -> void: main.clan_request("found", [_name_edit.text]), ok, row)
	_box.add_child(row)
	if not main.online():
		_line("(Da soli puoi provarlo; in rete il clan lo vedono tutti e gli amici possono chiedere di entrare.)", Color(0.7, 0.7, 0.7))


func _build_my_clan(id: int) -> void:
	var c := clans.clan(id)
	var col := clans.color_of(id)
	_title(String(c["name"]), col.lightened(0.3))
	_line("Rango: %s · capo: %s · cassa del clan: € %s" % [clans.rank_name(_me()), c["boss"], _thousands(int(c["treasury"]))])
	if not c["npc"]:
		_line("Indagine della polizia sul clan: %d%% (a 80%% scatta il blitz della DDA: stelle a tutti e sequestro della cassa)" % int(c["heat"]),
			Color(1.0, 0.55, 0.45) if float(c["heat"]) > 50.0 else Color(0.85, 0.85, 0.85))
		_bar(float(c["heat"]) / 100.0, Color(1.0, 0.3, 0.25))
	var zs := []
	for z in clans.zones.size():
		if clans.zone_owner(z) == id:
			zs.append(Crime.ZONES[z]["name"])
	var inc := 0
	for v: int in Crime.ZONE_INCOME.values():
		inc += v
	_line("Territorio: %s%s" % [", ".join(zs) if not zs.is_empty() else "nessuna zona (conquistale uccidendo gli uomini di chi le tiene e spacciando lì)",
		(" · ogni zona rende € %d al minuto (spaccio, estorsioni, prostituzione)" % inc) if not zs.is_empty() else ""])
	var rels := []
	for o: Dictionary in clans.clans:
		if int(o["id"]) != id:
			rels.append("%s: %s" % [o["name"], _rel_text(clans.rel(id, int(o["id"])))])
	_line("Rapporti: " + " · ".join(rels), Color(0.85, 0.85, 0.85))
	var members := (c["members"] as Dictionary).keys()
	if not members.is_empty():
		_line("Affiliati: " + ", ".join(members), Color(0.8, 0.8, 0.8))
	var mt: String = clans.mission_text(_me())
	if mt != "":
		_line("Lavoro in corso: " + mt, Color(0.6, 1.0, 0.6))
	_box.add_child(HSeparator.new())
	# Comandi.
	var row := HBoxContainer.new()
	_button("Chiama rinforzi (N)", func() -> void: main.clan_request("backup", []), true, row)
	var stars: int = int(main.my_stars())
	_button("Corrompi un funzionario: −1 stella (€ %d)" % (1500 * maxi(stars, 1)), func() -> void: main.clan_request("corrupt", []),
		stars > 0 and _player().money >= 1500 * stars, row)
	_box.add_child(row)
	_title("Spacciatori al tuo soldo", Color(0.8, 0.6, 1.0), 20)
	_line("Assumi un ragazzo qui dove sei: gli lasci delle dosi e le vende per te (si tiene il %d%%, il clan prende il %d%% nel suo territorio). Rischia l'arresto, e se lo beccano può fare il tuo nome; nelle zone dei rivali rischia la pelle." % [int(Clans.PUSHER_CUT * 100), int(Clans.PIZZO * 100)], Color(0.85, 0.85, 0.85))
	var hire := HBoxContainer.new()
	_drug = OptionButton.new()
	for d: String in Crime.DRUG_ORDER:
		_drug.add_item("%s (ne hai %d)" % [Crime.DRUGS[d]["name"], int(_player().drugs.get(d, 0))])
	hire.add_child(_drug)
	_doses = SpinBox.new()
	_doses.min_value = 1
	_doses.max_value = Crime.MAX_DOSES
	_doses.value = 5
	_doses.suffix = "dosi"
	hire.add_child(_doses)
	_button("Assumi qui", _hire, true, hire)
	_box.add_child(hire)
	for p: Dictionary in clans.pushers_of(_me()):
		var pr := HBoxContainer.new()
		var l := Label.new()
		l.text = "· %s a %s: restano %d dosi, vendute %d, da incassare € %d" % [Crime.DRUGS[String(p["drug"])]["name"], Crime.ZONES[int(p["zone"])]["name"], int(p["stock"]), int(p.get("sold", 0)), int(p["earned"])]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pr.add_child(l)
		var pid := int(p["id"])
		_button("Ritira", func() -> void: main.clan_request("fire", [pid]), true, pr)
		_box.add_child(pr)
	_build_hitmen(id)
	# Il capo di un clan di giocatori.
	if clans.is_boss(_me()):
		_box.add_child(HSeparator.new())
		_title("Sei il capo", Color(1.0, 0.85, 0.4), 20)
		for cand: String in c["requests"]:
			var rr := HBoxContainer.new()
			var l := Label.new()
			l.text = "%s chiede di entrare (fama %d)" % [cand, int(clans.fame.get(cand, 0))]
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rr.add_child(l)
			_button("Accetta", func() -> void: main.clan_request("accept", [cand]), true, rr)
			_button("Rifiuta", func() -> void: main.clan_request("reject", [cand]), true, rr)
			_box.add_child(rr)
		var er := HBoxContainer.new()
		var el := Label.new()
		el.text = "Per entrare:"
		er.add_child(el)
		_fame_edit = SpinBox.new()
		_fame_edit.max_value = 5000
		_fame_edit.step = 50
		_fame_edit.value = int(c["fame"])
		_fame_edit.prefix = "fama"
		er.add_child(_fame_edit)
		_fee_edit = SpinBox.new()
		_fee_edit.max_value = 1000000
		_fee_edit.step = 500
		_fee_edit.value = int(c["fee"])
		_fee_edit.prefix = "€"
		er.add_child(_fee_edit)
		_button("Salva", func() -> void: main.clan_request("entry", [int(_fame_edit.value), int(_fee_edit.value)]), true, er)
		_box.add_child(er)
		var wr := HBoxContainer.new()
		_withdraw = SpinBox.new()
		_withdraw.max_value = maxi(int(c["treasury"]), 1)
		_withdraw.step = 100
		_withdraw.prefix = "€"
		wr.add_child(_withdraw)
		_button("Preleva dalla cassa", func() -> void: main.clan_request("withdraw", [int(_withdraw.value)]), int(c["treasury"]) > 0, wr)
		_box.add_child(wr)
	_box.add_child(HSeparator.new())
	_button("Lascia il clan", func() -> void: main.clan_request("leave", []))


var _hit_target: OptionButton
var _hit_names: Array = []


## Sicari del clan: si sceglie il bersaglio (un giocatore in partita, non del tuo clan) e chi mandare.
func _build_hitmen(id: int) -> void:
	var c := clans.clan(id)
	var roster: Array = c.get("hitmen", [])
	if roster.is_empty():
		return
	_box.add_child(HSeparator.new())
	_title("Sicari", Color(1.0, 0.45, 0.4), 20)
	_line("Paghi un sicario del clan per far fuori un giocatore. Più il bersaglio è famoso, più costa; più il sicario è bravo (fama), più costa e più è difficile fermarlo. Il bersaglio sa che c'è una taglia su di lui, e se il sicario fallisce a volte fa il tuo nome. Niente rimborsi.", Color(0.85, 0.85, 0.85))
	_hit_names.clear()
	for peer: int in main.players():
		var n: String = main.name_of(peer)
		if n != _me() and clans.clan_of(n) != id:
			_hit_names.append(n)
	if _hit_names.is_empty():
		_line("Nessun bersaglio in partita (servono altri giocatori, non del tuo clan).", Color(0.7, 0.7, 0.7))
		return
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "Bersaglio:"
	row.add_child(l)
	_hit_target = OptionButton.new()
	for n: String in _hit_names:
		_hit_target.add_item("%s (fama %d)" % [n, int(clans.fame.get(n, 0))])
	_hit_target.item_selected.connect(func(i: int) -> void:
		set_meta("hit_sel", i)
		rebuild())
	row.add_child(_hit_target)
	_box.add_child(row)
	var sel := 0
	if _hit_target.item_count > 0:
		sel = clampi(int(get_meta("hit_sel", 0)), 0, _hit_target.item_count - 1)
		_hit_target.select(sel)
	var target: String = _hit_names[sel]
	var tf := int(clans.fame.get(target, 0))
	for k in roster.size():
		var h: Dictionary = roster[k]
		var price := Clans.hit_price(int(h["fame"]), tf)
		var hr := HBoxContainer.new()
		var hl := Label.new()
		hl.text = "· %s — fama %d, %d colpi a segno%s" % [h["name"], int(h["fame"]), int(h["kills"]), " (impegnato)" if h["busy"] else ""]
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hr.add_child(hl)
		var hk := k
		_button("Ingaggia: € %s" % _thousands(price), func() -> void: main.clan_request("contract", [target, hk]),
			not h["busy"] and _player().money >= price, hr)
		_box.add_child(hr)


func _hire() -> void:
	var d: String = Crime.DRUG_ORDER[_drug.selected]
	var n := mini(int(_doses.value), int(_player().drugs.get(d, 0)))
	if n <= 0:
		_status.text = "Non hai %s da lasciargli: comprala da uno spacciatore." % Crime.DRUGS[d]["name"]
		return
	_player().drugs[d] = int(_player().drugs[d]) - n
	if int(_player().drugs[d]) <= 0:
		_player().drugs.erase(d)
	main.clan_request("hire", [d, n])


func _build_boss() -> void:
	var c := clans.clan(boss_clan)
	if c.is_empty():
		close_ui()
		return
	var col := clans.color_of(boss_clan)
	_title("%s, boss di %s" % [c["boss"], c["name"]], col.lightened(0.3))
	var zs := []
	for z in clans.zones.size():
		if clans.zone_owner(z) == boss_clan:
			zs.append(Crime.ZONES[z]["name"])
	_line("Comanda su: %s. Spaccio, estorsioni ai negozi e giri di prostituzione passano tutti da lui." % (", ".join(zs) if not zs.is_empty() else "più niente: gli hanno preso tutto"), Color(0.85, 0.85, 0.85))
	_fame_header()
	var mine := clans.clan_of(_me())
	if mine == boss_clan:
		_line("«Allora, che mi porti? Hai fatto il tuo dovere?»", Color(1.0, 0.95, 0.8))
		_line("Rango: %s. Sulle vendite nel nostro territorio ci dai il %d%%; in cambio i nostri ti coprono." % [clans.rank_name(_me()), int(Clans.PIZZO * 100)])
		var mt: String = clans.mission_text(_me())
		if mt != "":
			_line("Lavoro in corso: " + mt, Color(0.6, 1.0, 0.6))
		else:
			_button("Chiedi un lavoro", func() -> void: main.clan_request("mission", []))
		_button("Apri il pannello del clan (U)", open_panel)
		_button("Lascia il clan (ti considereranno un traditore)", func() -> void: main.clan_request("leave", []))
		return
	if clans.hostile(boss_clan, _me()):
		_line("«Hai un bel coraggio a farti vedere qui. Ancora un passo e i miei ti fanno la festa.»", Color(1.0, 0.5, 0.45))
		return
	if mine >= 0:
		_line("«Sei di %s. Qui non hai niente da cercare.»" % clans.clan(mine)["name"], Color(1.0, 0.95, 0.8))
		return
	_line("«Chi ti manda? Vuoi lavorare per noi? Bene. Ma da me non entra chiunque.»", Color(1.0, 0.95, 0.8))
	var f: int = main.fame
	var need_f := int(c["fame"])
	var fee := int(c["fee"])
	var ok_f := f >= need_f
	var ok_m: bool = _player().money >= fee
	_line(("✔" if ok_f else "✘") + " Fama almeno %d (tu: %d, %s)" % [need_f, f, Crime.level_name(f)], Color(0.6, 1.0, 0.6) if ok_f else Color(1.0, 0.6, 0.55))
	if fee > 0:
		_line(("✔" if ok_m else "✘") + " Quota d'ingresso: € %s" % _thousands(fee), Color(0.6, 1.0, 0.6) if ok_m else Color(1.0, 0.6, 0.55))
	var ok_t := true
	if String(c["task"]) != "":
		var prog := clans.task_progress(boss_clan, _me())
		ok_t = prog >= int(c["n"])
		var what := "Vendi %d dosi nel nostro territorio" % int(c["n"]) if String(c["task"]) == "sell" else "Fai fuori %d uomini di un altro clan" % int(c["n"])
		_line(("✔" if ok_t else "✘") + " Prova: %s (%d/%d)" % [what, mini(prog, int(c["n"])), int(c["n"])], Color(0.6, 1.0, 0.6) if ok_t else Color(1.0, 0.6, 0.55))
	_button("Voglio entrare" + ((" (pago € %s)" % _thousands(fee)) if fee > 0 else ""), func() -> void: main.clan_request("join", [boss_clan]), ok_f and ok_m and ok_t)


static func _thousands(n: int) -> String:
	return SlotMachine._thousands(n)
