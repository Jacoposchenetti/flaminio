class_name BankUI
extends Control

## Conto corrente (allo sportello o al bancomat): versare e prelevare. Il saldo lo tiene main.bank_balance (salvato
## nelle impostazioni di questo PC): i soldi in banca non si perdono quando si muore.

signal closed

var main: Node
var _panel: PanelContainer
var _title: Label
var _info: Label
var _note: Label
var _amount: SpinBox


func setup(m: Node) -> void:
	main = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(560, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.14, 0.97)
	sb.border_color = Color(0.85, 0.68, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.modulate = Color(1.0, 0.85, 0.4)
	box.add_child(_title)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 20)
	box.add_child(_info)
	for kind: String in ["deposit", "withdraw"]:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "Versa:" if kind == "deposit" else "Preleva:"
		l.custom_minimum_size = Vector2(90, 0)
		row.add_child(l)
		for v: int in [100, 1000, 10000, -1]:
			var b := Button.new()
			b.text = "tutto" if v < 0 else "€ %s" % SlotMachine._thousands(v)
			b.custom_minimum_size = Vector2(96, 0)
			b.pressed.connect(_move.bind(kind, v))
			row.add_child(b)
		box.add_child(row)
	var row2 := HBoxContainer.new()
	_amount = SpinBox.new()
	_amount.max_value = 10000000
	_amount.step = 50
	_amount.prefix = "€"
	_amount.custom_minimum_size = Vector2(180, 0)
	row2.add_child(_amount)
	var dep := Button.new()
	dep.text = "Versa"
	dep.pressed.connect(func() -> void: _move("deposit", int(_amount.value)))
	row2.add_child(dep)
	var wd := Button.new()
	wd.text = "Preleva"
	wd.pressed.connect(func() -> void: _move("withdraw", int(_amount.value)))
	row2.add_child(wd)
	box.add_child(row2)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.modulate = Color(0.75, 0.8, 0.85)
	_note.text = "I soldi sul conto non si perdono quando muori e a ogni mezzanotte fruttano l'1% (fino a € 2.000 al giorno)."
	box.add_child(_note)
	var close := Button.new()
	close.text = "Chiudi (Esc · joypad: B)"
	close.pressed.connect(close_ui)
	box.add_child(close)


func open(where: String) -> void:
	_title.text = where
	visible = true
	_refresh()


func close_ui() -> void:
	visible = false
	closed.emit()


func _process(_delta: float) -> void:
	if not visible:
		return
	var vs := get_viewport_rect().size
	if size != vs:
		position = Vector2.ZERO
		size = vs
	_panel.position = ((vs - _panel.size) * 0.5).round()


func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)):
		close_ui()
		get_viewport().set_input_as_handled()


func _move(kind: String, v: int) -> void:
	var p: Player = main.player
	if kind == "deposit":
		var n := p.money if v < 0 else mini(v, p.money)
		p.money -= n
		main.bank_balance += n
	else:
		var n: int = main.bank_balance if v < 0 else mini(v, main.bank_balance)
		main.bank_balance -= n
		p.money += n
	Sfx.play2d("coin", -6.0)
	main.save_bank()
	_refresh()


func _refresh() -> void:
	var p: Player = main.player
	_info.text = "Contanti: € %s      Sul conto: € %s" % [SlotMachine._thousands(p.money), SlotMachine._thousands(main.bank_balance)]
