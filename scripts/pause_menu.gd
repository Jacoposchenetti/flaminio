class_name PauseMenu
extends Control

## Menu di pausa (Esc, P o Start del joypad): riprendi, mappa, comandi, grafica, polizia, personaggio, nome,
## ritorno al punto di partenza, uscita. Da soli il gioco si ferma; in rete la partita continua.
## Si usa con mouse, frecce + Invio o joypad (croce + A, B per chiudere).

signal action(id: String)  # resume, map, quality, police, model, respawn, quit
signal rename(new_name: String)

const CONTROLS := """TASTIERA E MOUSE
WASD muoviti · Shift corri · Ctrl accovacciati · Q capriola · Spazio salta
Mouse camera · rotella zoom · tasto destro mira · sinistro spara · R ricarica
1-7 o Tab armi · B fa esplodere la TNT · E negozio · F sali/scendi dall'auto · G clacson
M mappa · H ritorno · C personaggio · T chat (/nome NuovoNome) · Esc o P questo menu
In auto: W gas · S freno/retromarcia · A/D sterza · Spazio freno a mano
Elicottero: Spazio sale · Ctrl scende · WASD vola · Shift veloce · sinistro mitra · destro o R razzi
Jetpack: in aria tieni Spazio · Ctrl scende · J lo togli/rimetti · E davanti alla slot machine: gioca
Clan: U pannello del clan (anche i sicari) · N chiama i rinforzi · E davanti a un boss: parlaci · K (creativa) elicottero
Case: E al portone (compra, entra, vendi) · O in casa: arreda · H torni a casa
Banche: E allo sportello o al bancomat · punta l'arma a impiegati o direttore · E al caveau: trapano · Missioni: E dal contatto

JOYPAD (Xbox / PlayStation)
Levetta sinistra muoviti · clic levetta sinistra (L3) corri · levetta destra camera
A/Croce salta · B/Cerchio capriola · X/Quadrato ricarica · Y/Triangolo auto
LT/L2 mira · RT/R2 spara · LB/L1 accovacciati · RB/R1 arma successiva · R3 clacson
Croce: su negozio · giù TNT · sinistra ritorno · destra mappa · Start menu · Back/Share mappa
In auto: RT gas · LT freno/retromarcia · A freno a mano
Elicottero: RT sale · LT scende · LB mitra · X razzi · Jetpack: in aria tieni A"""

var _box: VBoxContainer
var _quality: Button
var _police: Button
var _creative: Button
var _calm_stars: Button  # solo in creativa
var _calm_clans: Button  # solo in creativa
var _name: LineEdit
var _controls: Label
var _first: Button
var _note: Label


func setup(player_name: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # funziona anche a gioco fermo
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	center.add_child(row)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	row.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(m)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	m.add_child(_box)
	var title := Label.new()
	title.text = "Menu"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 13)
	_note.modulate = Color(1, 1, 1, 0.7)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_note)

	_first = _button("Riprendi", "resume")
	_button("Mappa", "map")
	var ctl := Button.new()
	ctl.text = "Comandi"
	ctl.pressed.connect(func() -> void: _controls.get_parent().get_parent().visible = not _controls.get_parent().get_parent().visible)
	_box.add_child(ctl)
	_quality = _button("Grafica", "quality")
	_police = _button("Polizia", "police")
	_creative = _button("Modalità creativa", "creative")
	_calm_stars = _button("   ↳ Azzera le stelle", "calm_stars")
	_calm_clans = _button("   ↳ Fai pace con i clan che ti cercano", "calm_clans")
	_button("Cambia personaggio", "model")
	var name_row := HBoxContainer.new()
	_name = LineEdit.new()
	_name.text = player_name
	_name.max_length = 20
	_name.placeholder_text = "Il tuo nome"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.select_all_on_focus = true
	_name.text_submitted.connect(func(_t: String) -> void: _do_rename())
	name_row.add_child(_name)
	var nb := Button.new()
	nb.text = "Cambia nome"
	nb.pressed.connect(_do_rename)
	name_row.add_child(nb)
	_box.add_child(name_row)
	_button("Torna al punto di partenza", "respawn")
	_box.add_child(HSeparator.new())
	_button("Esci dal gioco", "quit")

	# Pannello dei comandi accanto al menu (nascosto finché non si preme "Comandi").
	var cp := PanelContainer.new()
	cp.visible = false
	row.add_child(cp)
	var cm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		cm.add_theme_constant_override("margin_" + side, 18)
	cp.add_child(cm)
	_controls = Label.new()
	_controls.text = CONTROLS
	_controls.add_theme_font_size_override("font_size", 14)
	cm.add_child(_controls)
	visible = false


func _button(text: String, id: String) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func() -> void: action.emit(id))
	_box.add_child(b)
	return b


func _do_rename() -> void:
	var n := _name.text.strip_edges()
	if n != "":
		rename.emit(n)
	_first.grab_focus()


## Aggiorna le scritte che cambiano (grafica, polizia, nome) e il motivo per cui il gioco è o non è fermo.
func refresh(quality_high: bool, police_on: bool, can_police: bool, player_name: String, online: bool, creative := false) -> void:
	_quality.text = "Grafica: " + ("alta" if quality_high else "bassa (più veloce)")
	_creative.text = "Modalità creativa: " + ("attiva (tutto infinito)" if creative else "spenta") + (" · solo da soli" if online else "")
	_creative.disabled = online
	_calm_stars.visible = creative
	_calm_clans.visible = creative
	_police.text = "Polizia: " + ("attiva" if police_on else "disattivata")
	_police.disabled = not can_police
	if not _name.has_focus():
		_name.text = player_name
	_note.text = "In rete la partita continua" if online else "Gioco in pausa"


func open() -> void:
	visible = true
	_first.grab_focus.call_deferred()


func close() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f:
		f.release_focus()
	_controls.get_parent().get_parent().visible = false
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		action.emit("resume")
