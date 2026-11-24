extends Node3D

## Regia: luce e cielo, costruzione del quartiere, menu, giocatore, rete, interfaccia.
##
## Comandi: WASD muoversi, Shift correre, Spazio saltare, mouse guardarsi intorno, rotella zoom,
## C cambiare personaggio, R tornare al punto di partenza, M minimappa, T o Invio chat, Esc liberare il mouse.
##
## Rete: ENet, porta 7777. Chi ospita è il server e gioca anche lui; ogni giocatore comanda il proprio
## personaggio e manda agli altri posizione e animazione 20 volte al secondo.
##
## Argomenti (dopo "--"): --solo | --host | --join=indirizzo, --name=nome, --model=n, --bind=ip,
## --capture=percorso.png, --frames=n, --pos=x,z, --yaw=gradi, --pitch=gradi, --zoom=metri, --autoquit=secondi

const PORT := 7777
const MAX_PLAYERS := 8
const SEND_RATE := 20.0
const SETTINGS_PATH := "user://settings.cfg"
const MODELS := ["m1", "f1", "m2", "f2", "m3", "f3", "m4", "f4", "m5", "f5", "m6", "f6", "m7", "f7", "m8", "f8"]

var city: CityBuilder
var player: Player
var quality_high := true
var _sun: DirectionalLight3D
var _env: Environment
var my_name := "Giocatore"
var mode := ""  # "", "solo", "host", "join"

var _players_root: Node3D
var _remote := {}  # peer id -> Player
var _names := {}  # peer id -> nome
var _model_index := 0
var _address := ""
var _menu: StartMenu
var updater: Updater
var _overview: Camera3D
var _street: Label
var _online: Label
var _hint: Label
var _speed: Label
var cars: Array[Car] = []
var combat: Combat
var pedestrians: Pedestrians
var icone: Icone
var traffic: Traffic
var police: Police
var netsync: NetSync
var simulate := true  # questo PC calcola pedoni, traffico e polizia (chi ospita o chi gioca da solo)
var police_on := true
var _registry := {}  # id di rete -> pedone, agente, auto del traffico, volante (solo su chi li calcola)
var _next_nid := 1
var _world_timer := 0.0
var _world_frame := 0
var shops: Shops
var hud: Hud
var _wheel: WeaponWheel
var _wheel_down := -1  # quando è stato premuto Tab/RB (ms), -1 = non premuto
var nav: Navigator
var scooters: Scooters
var _dest: Variant = null  # Vector2 della destinazione scelta sulla mappa
var _dest_name := ""
var _route_t := 0.0
var _nav: Label
var _pause: PauseMenu
var _respawn_timer := -1.0
var _pending_release: Car  # auto appena lasciata: la sua posizione finale va comunicata agli altri
var _chat_box: VBoxContainer
var _chat_input: LineEdit
var _minimap: MapView
var _bigmap: MapView
var _layer: CanvasLayer
var _args := {}
var _capture_frames := 90
var _frame := 0
var _send_timer := 0.0
var _time := 0.0
var daynight: DayNight
## Server dedicato (--server): ospita la partita senza personaggio e senza schermo (sul telefono sempre acceso).
var server_mode := false
var _server_log_t := 0.0
var _server_upd_n := 0
var _profile_t := 0.0
const PROFILE_PATH := "user://profilo.json"
var clans: Clans
var banks: Banks
var missions: Missions
var homes: Homes
var _home_ui: HomeUI
var _missions_done: Array = []
var _jack_run: CarJack  # sequenza in corso del salire in auto
var _known_bosses: Array = []  # nomi dei boss incontrati di persona: solo questi (e il tuo) stanno sulla mappa
var _boss_scan := 0.0
var bank_balance := 0  # conto corrente di chi gioca su questo PC (salvato nelle impostazioni)
var _bank_ui: BankUI
var _drill_bank := -1
var _drill_t := 0.0
var _last_hour := 0.0
var fame := 0  # fama criminale di chi gioca su questo PC (salvata nelle impostazioni)
var _clan_ui: ClanUI
var _zone_label: Label
var _prev_stars := 0
var creative := false  # modalità creativa (solo da soli): armi, gadget, munizioni e soldi infiniti
var _slot: SlotMachine
var _clock_t := 0.0


func _ready() -> void:
	Sfx.root = self
	_setup_input()
	_setup_world()
	city = CityBuilder.new()
	city.name = "Citta"
	add_child(city)
	city.build()
	_players_root = Node3D.new()
	_players_root.name = "Giocatori"
	add_child(_players_root)
	combat = Combat.new()
	combat.name = "Combattimento"
	add_child(combat)
	combat.net_fx = _send_fx
	_spawn_cars()
	daynight = DayNight.new()
	daynight.name = "GiornoNotte"
	add_child(daynight)
	daynight.setup(_sun, _env, city)

	_overview = Camera3D.new()
	_overview.far = 3000
	add_child(_overview)
	_overview.current = true

	_load_settings()
	_setup_hud()
	_parse_args()
	if _args.has("hour"):  # prova: --hour=22 ferma l'orologio a quell'ora
		daynight.hour = float(_args["hour"])
		daynight.frozen = true

	var m := multiplayer
	m.peer_connected.connect(_on_peer_connected)
	m.peer_disconnected.connect(_on_peer_disconnected)
	m.connected_to_server.connect(_on_connected)
	m.connection_failed.connect(_on_connection_failed)
	m.server_disconnected.connect(_on_server_disconnected)

	if _args.has("padtest"):
		# La prova del joypad deve andare avanti anche col gioco in pausa (menu aperto).
		get_tree().process_frame.connect(func() -> void:
			if get_tree().paused and player:
				_pad_test())
	if _args.has("pauseshot"):
		# Prova: apre il menu di pausa (con i comandi) e ne salva la schermata in --pauseshot=file.png.
		var n := [0]
		get_tree().process_frame.connect(func() -> void:
			if player == null or _time < 2.0:
				return
			n[0] += 1
			if n[0] == 1:
				_open_pause()
				_pause._controls.get_parent().get_parent().visible = true
			elif n[0] == 30:
				get_viewport().get_texture().get_image().save_png(_args["pauseshot"])
				get_tree().quit())
	if _args.has("upnpcheck"):
		# Prova senza toccare il router: cerca solo il router e legge l'indirizzo pubblico.
		_upnp_thread = Thread.new()
		_upnp_thread.start(_upnp_work.bind(false))
	if _args.has("server"):
		server_mode = true
		Engine.max_fps = 60  # senza schermo girerebbe a vuoto e scalderebbe il telefono
		print("SERVER: preparo il quartiere, poi apro la porta %d" % PORT)
		_begin("host", "Server", 0, "")
	elif _args.has("join"):
		_begin("join", _args.get("name", my_name), _model_index, _args["join"])
	elif _args.has("host"):
		_begin("host", _args.get("name", my_name), _model_index, "")
	elif _args.has("solo") or _args.has("capture"):
		_begin("solo", _args.get("name", my_name), _model_index, "")
	else:
		_show_menu()


# --- Preparazione -----------------------------------------------------------------------------


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT],
		"jump": [KEY_SPACE],
		"respawn": [KEY_H],
		"next_model": [KEY_C],
		"crouch": [KEY_CTRL],
		"roll": [KEY_Q],
		"reload": [KEY_R],
		"interact": [KEY_E],
		"detonate": [KEY_B],
		"next_weapon": [KEY_TAB],
		"slot_1": [KEY_1],
		"slot_2": [KEY_2],
		"slot_3": [KEY_3],
		"slot_4": [KEY_4],
		"slot_5": [KEY_5],
		"slot_6": [KEY_6],
		"slot_7": [KEY_7],
		"toggle_map": [KEY_M],
		"chat": [KEY_T, KEY_ENTER],
		"quality": [KEY_F2],
		"toggle_police": [KEY_F3],
		"enter_car": [KEY_F],
		"horn": [KEY_G],
		"jetpack": [KEY_J],
		"clan": [KEY_U],
		"backup": [KEY_N],
		"arrange": [KEY_O],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)  # zona morta bassa: con le levette ci si muove anche piano
		for k: int in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for pair: Array in [["fire", MOUSE_BUTTON_LEFT], ["aim", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0], 0.2)
			var mb := InputEventMouseButton.new()
			mb.button_index = pair[1]
			InputMap.action_add_event(pair[0], mb)
	# Joypad (Xbox e PlayStation hanno la stessa disposizione: A = Croce, B = Cerchio, X = Quadrato, Y = Triangolo).
	var joy_buttons := {
		"jump": [JOY_BUTTON_A],
		"roll": [JOY_BUTTON_B],
		"reload": [JOY_BUTTON_X],
		"enter_car": [JOY_BUTTON_Y],
		"sprint_toggle": [JOY_BUTTON_LEFT_STICK],  # clic della levetta sinistra: corri (resta acceso finché ti muovi)
		"crouch": [JOY_BUTTON_LEFT_SHOULDER],
		"vehicle_fire": [JOY_BUTTON_LEFT_SHOULDER],  # in auto e in monopattino LB spara (RT accelera)
		"next_weapon": [JOY_BUTTON_RIGHT_SHOULDER],
		"horn": [JOY_BUTTON_RIGHT_STICK],
		"interact": [JOY_BUTTON_DPAD_UP],
		"detonate": [JOY_BUTTON_DPAD_DOWN],
		"respawn": [JOY_BUTTON_DPAD_LEFT],
		"toggle_map": [JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_BACK],
		"pause": [JOY_BUTTON_START],
	}
	for extra: String in ["sprint_toggle", "pause", "vehicle_fire"]:
		if not InputMap.has_action(extra):
			InputMap.add_action(extra)
	for k: int in [KEY_ESCAPE, KEY_P]:
		var pk := InputEventKey.new()
		pk.physical_keycode = k
		InputMap.action_add_event("pause", pk)
	# Nei menu e nei negozi: A / Croce conferma, B / Cerchio torna indietro (Godot di base non li assegna al joypad).
	joy_buttons["ui_accept"] = [JOY_BUTTON_A]
	joy_buttons["ui_cancel"] = [JOY_BUTTON_B]
	for action: String in joy_buttons:
		for b: int in joy_buttons[action]:
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)
	# Levette e grilletti: [azione, asse, verso]. L2/LT mira (in auto frena), R2/RT spara (in auto accelera).
	var joy_axes := [
		["move_left", JOY_AXIS_LEFT_X, -1.0], ["move_right", JOY_AXIS_LEFT_X, 1.0],
		["move_forward", JOY_AXIS_LEFT_Y, -1.0], ["move_back", JOY_AXIS_LEFT_Y, 1.0],
		["look_left", JOY_AXIS_RIGHT_X, -1.0], ["look_right", JOY_AXIS_RIGHT_X, 1.0],
		["look_up", JOY_AXIS_RIGHT_Y, -1.0], ["look_down", JOY_AXIS_RIGHT_Y, 1.0],
		["aim", JOY_AXIS_TRIGGER_LEFT, 1.0], ["fire", JOY_AXIS_TRIGGER_RIGHT, 1.0],
		["brake", JOY_AXIS_TRIGGER_LEFT, 1.0], ["accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0],
	]
	for a: Array in joy_axes:
		if not InputMap.has_action(a[0]):
			InputMap.add_action(a[0], 0.15)
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[1]
		jm.axis_value = a[2]
		InputMap.action_add_event(a[0], jm)


func _setup_world() -> void:
	# Pomeriggio romano: sole caldo e basso da sud-ovest, cielo fisico, foschia.
	_sun = DirectionalLight3D.new()
	_sun.name = "Sole"
	_sun.rotation_degrees = Vector3(-32, -140, 0)
	_sun.light_color = Color(1.0, 0.9, 0.76)
	_sun.light_energy = 1.6
	_sun.light_angular_distance = 0.6
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.2
	_sun.directional_shadow_max_distance = 300.0
	_sun.directional_shadow_split_1 = 0.05
	_sun.directional_shadow_split_2 = 0.18
	_sun.directional_shadow_split_3 = 0.45
	add_child(_sun)

	# Cielo disegnato da uno shader (shaders/sky.gdshader): nuvole, alone del sole, stelle. I colori li cambia DayNight.
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL  # la luce del cielo si aggiorna a rate, senza scatti
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.7
	_env.ambient_light_color = Color(0.66, 0.62, 0.56)  # luce rimbalzata da muri e strade, calda
	_env.ambient_light_sky_contribution = 0.45
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 0.95
	_env.tonemap_white = 6.0
	_env.ssao_enabled = true
	_env.ssao_radius = 1.2
	_env.ssao_intensity = 2.2
	_env.fog_enabled = true
	# Foschia: in lontananza i palazzi sbiadiscono nell'azzurro (prospettiva aerea) e verso il sole si accende
	# di luce calda; più densa in basso, come la caligine sopra Roma.
	_env.fog_light_color = Color(0.74, 0.78, 0.86)
	_env.fog_sun_scatter = 0.35
	_env.fog_density = 0.00065
	_env.fog_aerial_perspective = 0.7
	_env.fog_sky_affect = 0.25
	_env.fog_height = 25.0
	_env.fog_height_density = 0.0004
	_env.glow_enabled = true
	_env.glow_intensity = 0.45
	_env.glow_strength = 1.0
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.1
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.15
	_env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_apply_quality()


## Qualità alta: illuminazione globale (SDFGI), riflessi (SSR), luce indiretta (SSIL), foschia volumetrica.
## Qualità bassa: niente di tutto questo, per i PC meno potenti. Si cambia con F2.
func _apply_quality() -> void:
	var high := quality_high
	_env.sdfgi_enabled = false  # in questa scena sbianca tutto; resta spento
	_env.sdfgi_use_occlusion = true
	_env.sdfgi_cascades = 4
	_env.sdfgi_min_cell_size = 0.4
	_env.sdfgi_energy = 0.6
	_env.ssr_enabled = high
	_env.ssr_max_steps = 48
	_env.ssil_enabled = high
	_env.volumetric_fog_enabled = high
	_env.volumetric_fog_density = 0.0012
	_env.volumetric_fog_albedo = Color(0.85, 0.87, 0.9)
	_env.volumetric_fog_length = 160.0
	_env.volumetric_fog_anisotropy = 0.6
	_env.ssao_enabled = true
	# Per le prove: --off=sdfgi,ssr,ssil,vol spegne singoli effetti.
	var off: String = _args.get("off", "")
	if off != "":
		_env.sdfgi_enabled = _env.sdfgi_enabled and not off.contains("sdfgi")
		_env.ssr_enabled = _env.ssr_enabled and not off.contains("ssr")
		_env.ssil_enabled = _env.ssil_enabled and not off.contains("ssil")
		_env.volumetric_fog_enabled = _env.volumetric_fog_enabled and not off.contains("vol")
	_sun.directional_shadow_mode = (
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if high else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	)
	_sun.directional_shadow_max_distance = 300.0 if high else 150.0
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if high else Viewport.SCREEN_SPACE_AA_DISABLED


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_street = _outlined(28)
	_street.position = Vector2(24, 18)
	layer.add_child(_street)
	_zone_label = _outlined(19)
	_zone_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_zone_label.offset_left = -360
	_zone_label.offset_right = 360
	_zone_label.offset_top = 14
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_zone_label)
	_online = _outlined(16)
	_online.position = Vector2(24, 58)
	_online.modulate = Color(0.75, 1.0, 0.75)
	layer.add_child(_online)
	_nav = _outlined(18)
	_nav.position = Vector2(24, 84)
	_nav.modulate = Color(0.7, 0.85, 1.0)
	layer.add_child(_nav)
	_hint = _outlined(20)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -300
	_hint.offset_right = 300
	_hint.offset_top = -110
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_hint)
	_speed = _outlined(40)
	_speed.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_speed.offset_left = -260
	_speed.offset_top = -100
	_speed.offset_right = -30
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(_speed)

	_help = _outlined(15)
	_help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_help.offset_left = 24
	_help.offset_top = -36
	layer.add_child(_help)
	_update_help()
	Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void: _update_help())
	var credit := Label.new()
	credit.text = "Mappa © OpenStreetMap contributors"
	credit.add_theme_font_size_override("font_size", 12)
	credit.modulate = Color(1, 1, 1, 0.7)
	credit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	credit.offset_left = -230
	credit.offset_top = -24
	layer.add_child(credit)

	_chat_box = VBoxContainer.new()
	_chat_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_box.offset_left = 24
	_chat_box.offset_top = -260
	_chat_box.offset_right = 700
	_chat_box.offset_bottom = -80
	_chat_box.alignment = BoxContainer.ALIGNMENT_END
	_chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_chat_box)
	_chat_input = LineEdit.new()
	_chat_input.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_input.offset_left = 24
	_chat_input.offset_top = -74
	_chat_input.offset_right = 600
	_chat_input.offset_bottom = -44
	_chat_input.placeholder_text = "Scrivi agli altri e premi Invio (Esc per annullare)"
	_chat_input.max_length = 200
	_chat_input.visible = false
	_chat_input.text_submitted.connect(_on_chat_submitted)
	layer.add_child(_chat_input)

	_layer = layer
	_minimap = MapView.new()
	layer.add_child(_minimap)
	_minimap.visible = false
	_bigmap = MapView.new()
	layer.add_child(_bigmap)
	_bigmap.visible = false

	_pause = PauseMenu.new()
	layer.add_child(_pause)
	_pause.setup(my_name)
	_pause.action.connect(_on_pause_action)
	_pause.rename.connect(func(n: String) -> void: _on_chat_submitted("/nome " + n))

	_menu = StartMenu.new()
	layer.add_child(_menu)
	_menu.setup(MODELS, my_name, _model_index, _address)
	_menu.police_check.button_pressed = police_on
	_menu.start.connect(_begin)
	_menu.visible = false
	updater = Updater.new()
	add_child(updater)
	_menu.attach_updater(updater)
	updater.available.connect(func(v: int) -> void:
		if server_mode and _remote.is_empty():
			print("SERVER: è uscita la versione %d, mi chiudo per aggiornarmi" % v)
			if clans:
				clans.save()
			get_tree().quit())


var _help: Label

const HELP_KEYS := "WASD muoviti · Shift corri · Spazio salta · destro mira · sinistro spara · R ricarica · Tab armi · B TNT · E negozio · F auto · M mappa · U clan · N rinforzi · J jetpack · T chat · Esc menu"
const HELP_PAD := "Joypad: levette muoviti/guarda · clic levetta sinistra (L3) corri · LB/L1 accovacciati · B/Cerchio rotola · A/Croce salta · LT/L2 mira · RT/R2 spara · X/Quadrato ricarica\nRB/R1 (tieni) armi · Y/Triangolo auto (RT gas, LT freno, R3 clacson) · croce: su negozio, giù TNT, sinistra ritorno, destra mappa · Start menu"


## Riga dei comandi in basso: quella del joypad se ce n'è uno collegato.
func _update_help() -> void:
	var pad := not Input.get_connected_joypads().is_empty()
	_help.text = HELP_PAD if pad else HELP_KEYS
	_help.offset_top = -58.0 if pad else -36.0


func _outlined(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := arg.trim_prefix("--").get_slice("=", 0)
		_args[key] = arg.get_slice("=", 1) if arg.contains("=") else ""
	if _args.has("model"):
		_model_index = int(_args["model"]) % MODELS.size()
	if _args.has("frames"):
		_capture_frames = int(_args["frames"])
	if _args.has("quality"):
		quality_high = _args["quality"] != "low"
		_apply_quality()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		my_name = cfg.get_value("player", "name", my_name)
		_model_index = cfg.get_value("player", "model", 0)
		_address = cfg.get_value("net", "address", "")
		quality_high = cfg.get_value("video", "high", true)
		fame = cfg.get_value("crime", "fame", 0)
		bank_balance = cfg.get_value("bank", "balance", 0)
		_missions_done = cfg.get_value("missions", "done", [])
		_known_bosses = cfg.get_value("clans", "known_bosses", [])
		police_on = cfg.get_value("game", "police", true)
		_apply_quality()


func _save_settings() -> void:
	for test: String in ["capture", "autoquit", "padtest", "feattest", "weapontest", "navtest", "pauseshot", "escape", "regentest", "nopolice", "say", "perf"]:
		if _args.has(test):
			return  # le prove automatiche non toccano le impostazioni di chi gioca
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", my_name)
	cfg.set_value("player", "model", _model_index)
	cfg.set_value("net", "address", _address)
	cfg.set_value("video", "high", quality_high)
	cfg.set_value("game", "police", police_on)
	cfg.set_value("crime", "fame", fame)
	cfg.set_value("bank", "balance", bank_balance)
	cfg.set_value("missions", "done", missions.done if missions else _missions_done)
	cfg.set_value("clans", "known_bosses", _known_bosses)
	cfg.save(SETTINGS_PATH)


# --- Inizio partita ---------------------------------------------------------------------------


func _show_menu() -> void:
	_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _begin(mode_: String, name_: String, model_index: int, address: String) -> void:
	my_name = name_
	if _menu.police_check:
		police_on = _menu.police_check.button_pressed
	if _args.has("nopolice"):
		police_on = false
	_model_index = model_index
	creative = mode_ == "solo" and (_menu.creative_check.button_pressed or _args.has("creative"))
	if address != "":
		_address = address
	_save_settings()
	if mode_ == "host":
		var peer := ENetMultiplayerPeer.new()
		if _args.has("bind"):
			peer.set_bind_ip(_args["bind"])
		var err := peer.create_server(PORT, MAX_PLAYERS)
		if err != OK:
			_menu.set_status("Impossibile ospitare (porta %d occupata?). Errore %d" % [PORT, err])
			_show_menu()
			return
		multiplayer.multiplayer_peer = peer
		if not server_mode:
			_open_internet()
	elif mode_ == "join":
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_client(address, PORT)
		if err != OK:
			_menu.set_status("Indirizzo non valido. Errore %d" % err)
			_show_menu()
			return
		multiplayer.multiplayer_peer = peer
		mode = "join"
		_menu.set_status("Mi collego a %s…" % address)
		_menu.visible = true
		return  # il personaggio compare quando la connessione riesce (_on_connected)
	mode = mode_
	_start_playing()


# --- Partita su Internet (senza Tailscale) ------------------------------------------------------------
# Chi ospita chiede al proprio router, con UPnP, di aprire la porta UDP 7777 e legge l'indirizzo pubblico:
# gli amici lo scrivono nel menu e premono "Entra". Il router lo fa in un thread (ci mette 1-3 secondi).
# Se il router non lo permette (UPnP spento) o l'operatore usa un indirizzo condiviso (CGNAT), resta Tailscale.

var _upnp: UPNP
var _upnp_thread: Thread
var public_address := ""


func _open_internet() -> void:
	if _upnp_thread != null:
		return
	_system("Apro la partita anche su Internet (chiedo al router di aprire la porta %d)…" % PORT)
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work.bind(true))


## Nel thread: cerca il router, (se map) apre la porta, legge l'indirizzo pubblico. Ritorna al thread principale.
func _upnp_work(map: bool) -> void:
	var u := UPNP.new()
	var res := {"found": false, "mapped": false, "ext": ""}
	if u.discover(2500, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS and u.get_device_count() > 0 \
			and u.get_gateway() and u.get_gateway().is_valid_gateway():
		res["found"] = true
		res["ext"] = u.query_external_address()
		if map:
			res["mapped"] = u.add_port_mapping(PORT, PORT, "Flaminio", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS
	_upnp_done.call_deferred(u, res)


func _upnp_done(u: UPNP, res: Dictionary) -> void:
	_upnp_thread.wait_to_finish()
	_upnp = u if res["mapped"] else null
	var ext: String = res["ext"]
	# Indirizzi non raggiungibili da Internet: condivisi dall'operatore (100.64-127) o privati.
	var o := ext.split(".")
	var b := int(o[1]) if o.size() == 4 else 0
	var shared := o.size() == 4 and ((o[0] == "100" and b >= 64 and b <= 127) or o[0] == "10"
		or (o[0] == "192" and b == 168) or (o[0] == "172" and b >= 16 and b <= 31))
	if _args.has("upnpcheck"):
		print("upnp: router trovato = %s, indirizzo pubblico = '%s', condiviso (CGNAT) = %s" % [res["found"], ext, shared])
		return
	if res["mapped"] and ext != "" and not shared:
		public_address = ext
		_system("Partita aperta su Internet! Manda all'amico questo indirizzo: %s  (lui lo scrive nel menu e preme Entra)" % ext)
	elif not res["found"]:
		_system("Il router non risponde (UPnP spento): da Internet non si entra da soli. Usate Tailscale, " +
			"oppure apri a mano sul router la porta UDP %d verso questo PC." % PORT)
	elif shared:
		_system("Il tuo operatore usa un indirizzo condiviso (CGNAT): da Internet non si entra. Usate Tailscale.")
	else:
		_system("Il router non ha aperto la porta %d da solo. Usate Tailscale, oppure aprila a mano (UDP)." % PORT)
	_update_online()


## Alla chiusura la porta sul router si richiude.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_profile()
		if clans and simulate:
			clans.save()
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _upnp:
			_upnp.delete_port_mapping(PORT, "UDP")
			_upnp = null


func _start_playing() -> void:
	_menu.visible = false
	_menu.set_status("")
	_minimap.visible = true
	if player == null:
		player = Player.new()
		player.name = "Io"
		player.model_name = MODELS[_model_index]
		player.water_check = city.over_river
		player.water_y = city.water_y
		player.car_lookup = _car_by_id
		player.combat = combat
		player.died.connect(_on_player_died)
		player.give_weapon("pistola", 36)
		player.weapon = "pugni"
		_players_root.add_child(player)
		if server_mode:
			# Il server non gioca: il suo personaggio sta fermo, invisibile e senza collisioni sotto la mappa.
			player.visible = false
			player.input_enabled = false
			player.collision_layer = 0
			player.collision_mask = 0
			player.set_physics_process(false)
		else:
			_load_profile()
		pedestrians = Pedestrians.new()
		pedestrians.name = "Pedoni"
		add_child(pedestrians)
		pedestrians.setup(city, self, combat)
		icone = Icone.new()
		icone.name = "Icone"
		add_child(icone)
		icone.setup(city, self)
		traffic = Traffic.new()
		traffic.name = "Traffico"
		add_child(traffic)
		traffic.setup(city, self, combat)
		police = Police.new()
		police.name = "Polizia"
		add_child(police)
		police.setup(city, self, combat, traffic, pedestrians)
		police.active = police_on
		combat.crime.connect(_on_local_crime)
		simulate = not _online_now() or multiplayer.is_server()
		clans = Clans.new()
		clans.name = "Clan"
		add_child(clans)
		clans.setup(self, city, combat, police, pedestrians)
		clans.changed.connect(_on_clans_changed)
		netsync = NetSync.new()
		netsync.name = "MondoCondiviso"
		netsync.world = self
		add_child(netsync)
		shops = Shops.new()
		shops.name = "Negozi"
		add_child(shops)
		shops.setup(city, player)
		shops.discount = _drug_discount
		banks = Banks.new()
		banks.name = "Banche"
		add_child(banks)
		banks.setup(self, city, combat, police, pedestrians, shops)
		missions = Missions.new()
		missions.name = "Missioni"
		add_child(missions)
		missions.setup(self, city, combat)
		missions.done = _missions_done.duplicate()
		homes = Homes.new()
		homes.name = "Case"
		add_child(homes)
		homes.setup(self, city)
		scooters = Scooters.new()
		scooters.name = "Monopattini"
		add_child(scooters)
		scooters.setup(city)
		hud = Hud.new()
		_layer.add_child(hud)
		_layer.move_child(hud, 0)
		hud.setup(player, shops)
		_wheel = WeaponWheel.new()
		_layer.add_child(_wheel)
		_wheel.setup(player)
		_wheel.chosen.connect(_wheel_pick)
		hud.wanted_info = _my_wanted
		hud.clock = daynight.clock_text
		hud.fame_info = func() -> int: return fame
		hud.clan_threats = func() -> Array: return clans.threats(my_name) if clans else []
		_minimap.police_dots = _police_dots
		_bigmap.police_dots = _police_dots
		var amb := AudioStreamPlayer.new()
		amb.stream = Sfx.stream("ambience")
		amb.volume_db = -16.0
		add_child(amb)
		amb.play()
		hud.shop_closed.connect(_on_shop_closed)
		_slot = SlotMachine.new()
		_layer.add_child(_slot)
		_slot.closed.connect(_on_slot_closed)
		_clan_ui = ClanUI.new()
		_layer.add_child(_clan_ui)
		_clan_ui.setup(self, clans)
		_clan_ui.closed.connect(_on_slot_closed)
		_bank_ui = BankUI.new()
		_layer.add_child(_bank_ui)
		_bank_ui.setup(self)
		_bank_ui.closed.connect(_on_slot_closed)
		_home_ui = HomeUI.new()
		_layer.add_child(_home_ui)
		_home_ui.setup(self, homes)
		_home_ui.closed.connect(_on_slot_closed)
		_minimap.setup(city, player, true)
		_bigmap.setup(city, player, false)
		_minimap.others = _other_players
		_bigmap.others = _other_players
		nav = Navigator.new()
		nav.setup(city, traffic)
		_bigmap.waypoint_changed.connect(_set_destination)
		for m: MapView in [_minimap, _bigmap]:
			for e: Array in city.enterables:
				m.extra_pois.append(e.slice(0, 4))
			m.extra_pois.append_array(shops.map_pois())
			for pad: Vector2 in Heli.PADS:
				m.extra_pois.append([pad.x, pad.y, "Elicottero", "heli"])
			m.dynamic_pois = _boss_pois
			m.zones_fn = _zones_for_map
			m.extra_pois.append_array(missions.map_pois())
			m.extra_pois.append_array(homes.map_entries)
	player.teleport(_spawn_point())
	if _args.has("pos"):
		var xz: PackedStringArray = _args["pos"].split(",")
		var x := float(xz[0])
		var z := float(xz[1])
		# Terzo numero (facoltativo): quota assoluta, per stare su un viadotto o guardare dall'alto.
		player.teleport(Vector3(x, float(xz[2]) if xz.size() > 2 else city.surface_at(x, z) + 1.0, z))
	if _args.has("civico") and not city.civic_spots.is_empty():
		# Prova: --civico=n davanti alla targa n (a 4 m, guardandola).
		var cs: Array = city.civic_spots[int(_args["civico"]) % city.civic_spots.size()]
		var stand: Vector3 = cs[0] + (cs[1] as Vector3) * 4.0
		player.teleport(Vector3(stand.x, city.surface_at(stand.x, stand.z) + 0.2, stand.z))
		var look: Vector3 = -(cs[1] as Vector3)
		player.cam_yaw = atan2(-look.x, -look.z) + 0.35
		player.cam_pitch = 0.05
		print("civico: %s %s" % [cs[3], cs[2]])
	if _args.has("yaw"):
		player.cam_yaw = deg_to_rad(float(_args["yaw"]))
	if _args.has("pitch"):
		player.cam_pitch = deg_to_rad(float(_args["pitch"]))
	if _args.has("zoom"):
		player.set_zoom(float(_args["zoom"]))
	if not _args.has("capture"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_online()
	_point_to_armory()
	_set_creative(creative)
	if not server_mode:
		clan_request("fame", [fame])
	if mode == "host":
		var ips := StartMenu.my_addresses()
		_system("Partita aperta. Gli amici entrano con: " + (", ".join(ips) if not ips.is_empty() else "il tuo indirizzo"))
	elif mode == "join":
		_system("Sei entrato nella partita.")


## Destinazione con indicazioni (dalla mappa, o null per toglierla): percorso blu su entrambe le mappe.
func _set_destination(pos: Variant, label: String) -> void:
	_dest = pos
	_dest_name = label
	for m: MapView in [_minimap, _bigmap]:
		m.waypoint = pos
		m.dest_name = label
		m.route = {}
	_route_t = 0.0  # ricalcolo subito
	_update_route()


func _update_route() -> void:
	if _dest == null or player == null or nav == null:
		_nav.text = ""
		return
	var me := Vector2(player.global_position.x, player.global_position.z)
	var d: Vector2 = _dest
	if me.distance_to(d) < 12.0:
		_system("Sei arrivato: %s." % _dest_name)
		_set_destination(null, "")
		return
	var r := nav.route(me, d)
	for m: MapView in [_minimap, _bigmap]:
		m.route = r
	# Sotto il nome della via: dove vai, quanto manca e la prossima svolta.
	var steps: Array = r["steps"]
	var next := "sempre dritto"
	if steps.size() > 1:
		var s1 := String(steps[1][0])
		next = "tra %s: %s" % [Navigator.fmt_dist(float(steps[0][1])), s1.left(1).to_lower() + s1.substr(1)]
	_nav.text = "→ %s · %s (%d min)\n%s" % [_dest_name, Navigator.fmt_dist(r["length"]), Navigator.walk_minutes(r["length"]), next]


## All'inizio: segnalino sulla mappa all'armeria più vicina e un messaggio che spiega dove si comprano le armi.
func _point_to_armory() -> void:
	var gun := shops.nearest("gun", player.global_position)
	if gun.is_empty():
		return
	var p: Vector3 = gun["pos"]
	_set_destination(Vector2(p.x, p.z), String(gun["name"]))
	_system("Armi, munizioni e TNT si comprano nelle armerie: raggio rosso nel cielo, G rossa sulla mappa (M). "
		+ "Segnalino giallo sulla più vicina: %s, %s. Sul cerchio a terra premi E." % [
			String(gun["name"]).trim_prefix("Armeria · "), city.street_name(p, 60.0)])
	_system("Hai già una pistola: tasto 2. Bar e farmacie (cerchi arancioni e verdi) curano.")


## Punto di partenza: Piazza Apollodoro, con un piccolo scarto per giocatore così non ci si sovrappone.
func _spawn_point() -> Vector3:
	var id := multiplayer.get_unique_id() if _online_now() else 1
	var a := float(id % 97) * 2.399
	var r := 0.0 if id == 1 else 2.5
	return city.spawn + Vector3(cos(a) * r, 0, sin(a) * r)


func _online_now() -> bool:
	var p := multiplayer.multiplayer_peer
	return (
		p != null and not (p is OfflineMultiplayerPeer)
		and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	)


# --- Rete -------------------------------------------------------------------------------------


func _on_connected() -> void:
	_start_playing()
	announce.rpc(my_name, MODELS[_model_index])


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	mode = ""
	_menu.set_status(
		"Connessione non riuscita. Controlla l'indirizzo, che chi ospita abbia avviato la partita "
		+ "e che Tailscale sia acceso su entrambi i PC."
	)
	_show_menu()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	netsync.clear_puppets()
	for id: int in _remote.keys():
		_remove_remote(id)
	for c in cars:
		if not c.driven_locally:
			c.driver_peer = 0
	mode = "solo"
	_system("Chi ospitava ha chiuso la partita. Continui da solo.")
	_update_online()


func _on_peer_connected(id: int) -> void:
	net_version.rpc_id(id, Updater.local_version())
	if multiplayer.is_server():
		net_clock.rpc_id(id, daynight.hour)
		if clans:
			net_clan_state.rpc_id(id, clans.state_json())
		if banks:
			for bi in banks.banks.size():
				net_bank.rpc_id(id, bi, banks.state_of(bi))
	if player != null and not server_mode:
		announce.rpc_id(id, my_name, MODELS[_model_index])
	if multiplayer.is_server():
		# Chi arriva dopo deve sapere dove sono finite le auto spostate e chi sta guidando (anche quelle rubate).
		if scooters:
			for sc: Node3D in scooters.list:
				if not sc.visible:
					net_scooter.rpc_id(id, int(sc.get_meta("id")), false, Vector3.ZERO, 0.0)
				elif sc.get_meta("moved", false):
					net_scooter.rpc_id(id, int(sc.get_meta("id")), true, sc.global_position, sc.rotation.y)
		for xid: int in _extra_cars:
			var xc: Car = _extra_cars[xid]
			net_car_spawn.rpc_id(id, xid, int(xc.get_meta("look", 0)), xc.global_transform)
		for c in cars:
			if c.moved:
				car_release.rpc_id(id, c.car_id, c.global_transform)
			if c.driver_peer != 0:
				car_claim.rpc_id(id, c.car_id, c.driver_peer)


func _on_peer_disconnected(id: int) -> void:
	if _names.has(id):
		_system("%s è uscito." % _names[id])
	for c in cars:
		if c.driver_peer == id:
			c.driver_peer = 0
			c.freeze = true
	_remove_remote(id)
	_update_online()


func _remove_remote(id: int) -> void:
	if _remote.has(id):
		_remote[id].queue_free()
		_remote.erase(id)
	_names.erase(id)


## Ora del gioco decisa da chi ospita (ogni 5 secondi e a chi entra): tutti vedono lo stesso cielo.
@rpc("authority", "call_remote", "unreliable")
func net_clock(h: float) -> void:
	if absf(daynight.hour - h) > 0.02 and not daynight.frozen:
		daynight.hour = h


## Versioni diverse tra giocatori: avvisa chi deve aggiornare (0 = copia di sviluppo, non si confronta).
@rpc("any_peer", "call_remote", "reliable")
func net_version(v: int) -> void:
	var mine := Updater.local_version()
	if v == 0 or mine == 0 or v == mine:
		return
	if v > mine:
		_system("Un altro giocatore ha la versione %d, tu la %d: esci al menu iniziale e premi \"Aggiorna\"." % [v, mine])
	else:
		_system("Un altro giocatore ha la versione %d, tu la %d: deve aggiornare dal menu iniziale." % [v, mine])


## Un giocatore si presenta (o cambia personaggio).
@rpc("any_peer", "call_remote", "reliable")
func announce(name_: String, model: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var safe_name := name_.left(20)
	if not _remote.has(id):
		var p := Player.new()
		p.is_local = false
		p.name = "Giocatore_%d" % id
		p.model_name = model
		p.display_name = safe_name
		p.car_lookup = _car_by_id
		p.peer_id = id
		# Chi ha colpito: il giocatore di questo PC, oppure 0 se è stato un personaggio del gioco (agenti, picciotti,
		# sicari calcolati qui): così chi muore per mano loro non perde i soldi come in un omicidio tra giocatori.
		p.hurt_remote = func(peer: int, amount: float, from_peer: int) -> void: net_hurt.rpc_id(peer, amount, _my_peer() if from_peer == _my_peer() else 0)
		_players_root.add_child(p)
		p.visible = false  # finché non arriva la prima posizione
		_remote[id] = p
		_system("%s è entrato." % safe_name)
	else:
		_remote[id].set_model(model)
		_remote[id].set_display_name(safe_name)
	if _names.has(id) and _names[id] != safe_name:
		_system("%s ora si chiama %s." % [_names[id], safe_name])
	_names[id] = safe_name
	_update_online()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func state(pos: Vector3, rot: float, anim: String, car: int, weapon_id: String, flags: int) -> void:
	var p: Player = _remote.get(multiplayer.get_remote_sender_id())
	if p != null:
		p.apply_state(pos, rot, anim, car, weapon_id, flags)
		p.visible = true


# --- Auto -------------------------------------------------------------------------------------


## Auto parcheggiate: stesse posizioni, modelli e colori su tutti i PC (servono gli stessi id in rete).
func _spawn_cars() -> void:
	var root := Node3D.new()
	root.name = "Auto"
	add_child(root)
	var spots := city.parking
	var step := maxi(1, spots.size() / 400)
	for i in range(0, spots.size(), step):
		var h := int(absf(sin(float(i) * 12.9898) * 43758.5453))
		var model: String = Car.MODELS[h % Car.MODELS.size()]
		var car := Car.new().setup(cars.size(), model, Car.PAINTS[(h / 7) % Car.PAINTS.size()])
		car.combat = combat
		car.on_destroyed = _on_car_destroyed
		root.add_child(car)
		car.global_transform = spots[i]
		cars.append(car)
	_parked_count = cars.size()
	# Elicotteri pilotabili, uno per piazzola (stessi id su tutti i PC).
	for i in Heli.PADS.size():
		var pad: Vector2 = Heli.PADS[i]
		var at := Vector3(pad.x, city.surface_at(pad.x, pad.y) + 0.05, pad.y)
		_helipad(at)
		var heli := Heli.new().setup_heli(Heli.BASE_ID + i, at, 0.4)
		heli.combat = combat
		heli.on_destroyed = _on_car_destroyed
		root.add_child(heli)
		heli.global_transform = Transform3D(Basis(Vector3.UP, 0.4), at)
		cars.append(heli)
		_extra_cars[heli.car_id] = heli


## Piazzola: cerchio giallo e grande H bianca sul prato.
func _helipad(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 6.2
	torus.outer_radius = 6.7
	torus.rings = 48
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.82, 0.1)
	m.roughness = 0.8
	torus.material = m
	ring.mesh = torus
	ring.scale = Vector3(1, 0.04, 1)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = at + Vector3(0, 0.02, 0)
	var h := Label3D.new()
	h.text = "H"
	h.font_size = 400
	h.pixel_size = 0.02
	h.outline_size = 0
	h.modulate = Color(0.95, 0.95, 0.95)
	h.rotation = Vector3(-PI / 2, 0, 0)
	add_child(h)
	h.global_position = at + Vector3(0, 0.05, 0)


func _car_by_id(id: int) -> Car:
	if id >= JACK_BASE:
		return _extra_cars.get(id)
	return cars[id] if id >= 0 and id < _parked_count else null


# --- Auto rubate al traffico (stile GTA: si tira fuori chi guida) -----------------------------------

const JACK_BASE := 1000000  # id delle auto rubate: JACK_BASE + numero (diversi da quelli delle parcheggiate)
var _extra_cars := {}  # id -> Car rubata
var _parked_count := 0
var _jack_n := 0


## Auto del traffico più vicina entro max_dist (vera su chi la calcola, copia sugli altri PC): [nodo, nid, aspetto].
func _nearest_traffic(max_dist: float) -> Array:
	var best := []
	var best_d := max_dist
	var cands: Array = traffic.get_children() if simulate else netsync.get_children()
	for n: Node in cands:
		var ok := false
		if n is Traffic.TrafficCar:
			ok = not (n as Traffic.TrafficCar).destroyed
		elif n is NetSync.VehiclePuppet:
			ok = not (n as NetSync.VehiclePuppet).police and not n.get("_destroyed")
		if not ok:
			continue
		var d := (n as Node3D).global_position.distance_to(player.global_position)
		if int(n.get("look")) >= Bus.LOOK:
			# Autobus: conta la distanza dal fianco, non dal centro (è lungo 12 m).
			var lp := (n as Node3D).global_transform.affine_inverse() * player.global_position
			var half := Bus.SIZE * 0.5
			d = Vector2(maxf(absf(lp.x) - half.x, 0.0), maxf(absf(lp.z) - half.z, 0.0)).length() + 1.2
		if d < best_d:
			best_d = d
			best = [n, int(n.get("nid")), int(n.get("look"))]
	return best


## Ruba l'auto del traffico t: al suo posto nasce un'auto guidabile uguale, il guidatore viene tirato fuori
## e scappa, il giocatore sale. In rete l'auto nasce uguale su tutti i PC.
func _jack(t: Array) -> void:
	var node: Node3D = t[0]
	var xf := node.global_transform
	_jack_n += 1
	var id := JACK_BASE + (_my_peer() % 1000) * 1000 + _jack_n % 1000
	var car := _make_jacked_car(id, int(t[2]), xf)
	var bus := int(t[2]) >= Bus.LOOK
	# Lato guidatore, un passo fuori dalla portiera (autobus: dalla porta anteriore, a destra).
	var door := xf * (Vector3(-2.3, 0.1, Bus.SIZE.z * 0.5 - 0.9) if bus else Vector3(2.4, 0.1, 0.2))
	var driver: Pedestrians.Pedestrian = null
	if simulate:
		# Il guidatore resta al volante: lo tira fuori la scena (CarJack).
		var n: Node = _registry.get(int(t[1]))
		if n and is_instance_valid(n):
			n.queue_free()
		driver = pedestrians.spawn_at(xf * car.seat.origin)
	elif _online_now():
		net_jacked.rpc_id(1, int(t[1]), door)
	if _online_now():
		net_car_spawn.rpc(id, int(t[2]), xf)
	_on_local_crime("theft", xf.origin)
	car.driver_peer = _my_peer()
	if _online_now():
		car_claim.rpc(car.car_id, car.driver_peer)
	_jack_run = CarJack.run(self, player, car, driver)


func _make_jacked_car(id: int, look: int, xf: Transform3D) -> Car:
	if _extra_cars.has(id):
		return _extra_cars[id]
	var model: String = Car.MODELS[(look % 16) % Car.MODELS.size()]
	if look >= Bus.LOOK:
		model = "bus%d" % (look - Bus.LOOK)  # autobus rubato
	var car := Car.new().setup(id, model, Car.PAINTS[(look / 16) % Car.PAINTS.size()])
	car.combat = combat
	car.on_destroyed = _on_car_destroyed
	car.set_meta("look", look)
	get_node("Auto").add_child(car)
	car.global_transform = xf
	car.moved = true
	cars.append(car)
	_extra_cars[id] = car
	return car


## Su chi calcola il traffico: toglie l'auto rubata e fa nascere il guidatore che scappa.
func _remove_traffic(nid: int, door: Vector3, from: Vector3) -> void:
	var n: Node = _registry.get(nid)
	if n and is_instance_valid(n):
		n.queue_free()
	var ped := pedestrians.spawn_at(door)
	if ped:
		ped.thrown_out(from)


@rpc("any_peer", "call_remote", "reliable")
func net_jacked(nid: int, door: Vector3) -> void:
	if simulate:
		var who: Player = _remote.get(multiplayer.get_remote_sender_id())
		_remove_traffic(nid, door, who.global_position if who else door)
		print("rete: auto del traffico %d rubata da un altro giocatore, tolta" % nid)


@rpc("any_peer", "call_remote", "reliable")
func net_car_spawn(id: int, look: int, xf: Transform3D) -> void:
	_make_jacked_car(id, look, xf)
	print("rete: auto rubata %d creata anche qui" % id)


func _my_peer() -> int:
	return multiplayer.get_unique_id() if _online_now() else 1


## Auto più vicina entro max_dist metri (solo libere se only_free).
func _nearest_car(max_dist: float, only_free: bool) -> Car:
	var best: Car = null
	var best_d := max_dist
	for c in cars:
		if c.destroyed or only_free and c.driver_peer != 0:
			continue
		var d := c.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best


func _toggle_car() -> void:
	if _jack_run and is_instance_valid(_jack_run):
		return  # sta già salendo
	if player.vehicle:
		_leave_car()
		return
	if player.scooter >= 0:
		_leave_scooter()
		return
	var sc := scooters.nearest(player.global_position, 2.2)
	if sc:
		var id: int = sc.get_meta("id")
		scooters.take(id)
		player.mount_scooter(id, int(sc.get_meta("color")), sc.rotation.y)
		if _online_now():
			net_scooter.rpc(id, false, Vector3.ZERO, 0.0)
		return
	var car := _nearest_car(4.0, true)
	var moving := _nearest_traffic(5.0) if traffic else []
	if not moving.is_empty() and (car == null or (moving[0] as Node3D).global_position.distance_to(player.global_position)
			< car.global_position.distance_to(player.global_position)):
		_jack(moving)
		return
	if car == null:
		var busy := _nearest_car(4.0, false)
		if busy:
			_system("Quest'auto la sta guidando %s." % _names.get(busy.driver_peer, "qualcun altro"))
		return
	car.driver_peer = _my_peer()
	if car is Heli:
		player.enter_car(car)
	else:
		_jack_run = CarJack.run(self, player, car, null)  # apre la portiera, sale, richiude
	if _online_now():
		car_claim.rpc(car.car_id, car.driver_peer)


func _leave_scooter() -> void:
	if player.scooter < 0:
		return
	var id := player.scooter
	var at: Array = player.dismount_scooter()
	scooters.drop(id, at[0], at[1])
	if _online_now():
		net_scooter.rpc(id, true, at[0], at[1])


## Un monopattino preso (dropped = false) o lasciato in pos (dropped = true) su un altro PC.
@rpc("any_peer", "call_remote", "reliable")
func net_scooter(id: int, dropped: bool, pos: Vector3, yaw: float) -> void:
	if dropped:
		scooters.drop(id, pos, yaw)
	else:
		scooters.take(id)


func _leave_car() -> void:
	_leave_scooter()
	var car := player.vehicle
	if car == null:
		return
	player.exit_car()
	car.driver_peer = 0
	_pending_release = car


## Qualcuno è salito su un'auto.
@rpc("any_peer", "call_remote", "reliable")
func car_claim(id: int, peer: int) -> void:
	var car := _car_by_id(id)
	if car == null:
		return
	if car.driven_locally and peer < _my_peer():
		# Saliti nello stesso istante: vince chi ha l'id più basso.
		_leave_car()
		_pending_release = null
	car.driver_peer = peer
	car.moved = true


## Un'auto è stata lasciata (o va sincronizzata per chi arriva dopo): posizione finale.
@rpc("any_peer", "call_remote", "reliable")
func car_release(id: int, xf: Transform3D) -> void:
	var car := _car_by_id(id)
	if car == null or car.driven_locally:
		return
	car.driver_peer = 0
	car.global_transform = xf
	car.freeze = true
	car.moved = true


@rpc("any_peer", "call_remote", "unreliable_ordered")
func car_state(id: int, xf: Transform3D, steer: float) -> void:
	var car := _car_by_id(id)
	if car == null or car.driven_locally:
		return
	if car.driver_peer == 0:
		car.driver_peer = multiplayer.get_remote_sender_id()
	car.apply_net_state(xf, steer)


@rpc("any_peer", "call_local", "reliable")
func chat(text: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var who: String = my_name if id == multiplayer.get_unique_id() else _names.get(id, "?")
	_add_chat_line("%s: %s" % [who, text.left(200)], Color.WHITE)
	print("chat ", who, ": ", text.left(200))


func _update_online() -> void:
	if not _online_now():
		_online.text = ""
		return
	var others := _names.values()
	var role := "Ospiti la partita" if multiplayer.is_server() else "In partita"
	if multiplayer.is_server() and public_address != "":
		role += " (da Internet: %s)" % public_address
	if others.is_empty():
		_online.text = "%s · nessun altro connesso" % role
	else:
		_online.text = "%s · con %s" % [role, ", ".join(others)]


# --- Chat -------------------------------------------------------------------------------------


func _system(text: String) -> void:
	_add_chat_line(text, Color(1.0, 0.9, 0.55))
	print("sistema: ", text)


func _add_chat_line(text: String, color: Color) -> void:
	var l := _outlined(18)
	l.text = text
	l.modulate = color
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.set_meta("born", _time)
	_chat_box.add_child(l)
	while _chat_box.get_child_count() > 8:
		_chat_box.get_child(0).free()


func _open_chat() -> void:
	_chat_input.visible = true
	_chat_input.text = ""
	_chat_input.grab_focus()


func _close_chat() -> void:
	_chat_input.release_focus()
	_chat_input.visible = false


func _on_chat_submitted(text: String) -> void:
	_close_chat()
	text = text.strip_edges()
	if text == "":
		return
	if text.begins_with("/nome"):
		# Cambio nome in partita: lo vedono subito tutti sopra la testa e in chat.
		var n := text.trim_prefix("/nome").strip_edges().left(20)
		if n == "":
			_system("Scrivi /nome seguito dal nuovo nome, per esempio: /nome Marco")
			return
		my_name = n
		_save_settings()
		if _online_now():
			announce.rpc(my_name, MODELS[_model_index])
		_system("Ora ti chiami %s." % my_name)
		_update_online()
		return
	if _online_now():
		chat.rpc(text)
	else:
		_add_chat_line("%s: %s" % [my_name, text], Color.WHITE)


# --- Ciclo ------------------------------------------------------------------------------------


func _input(event: InputEvent) -> void:
	# Esc mentre si scrive chiude la chat (il LineEdit altrimenti se lo terrebbe).
	if _chat_input.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_chat()
		get_viewport().set_input_as_handled()


func _open_pause() -> void:
	_pause.refresh(quality_high, police_on, simulate, my_name, _online_now(), creative)
	_pause.open()
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not _online_now():
		get_tree().paused = true  # da soli il mondo si ferma davvero


func _on_pause_action(id: String) -> void:
	match id:
		"resume", "map", "respawn":
			_pause.close()
			get_tree().paused = false
			player.input_enabled = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			if id == "map":
				_toggle_big_map()
			elif id == "respawn" and not player.dead:
				_leave_car()
				player.teleport(_spawn_point())
			return
		"quality":
			quality_high = not quality_high
			_apply_quality()
			_save_settings()
		"police":
			if simulate:
				_set_police(not police_on)
		"creative":
			if not _online_now():
				_set_creative(not creative)
		"calm_stars":
			if creative:
				police.clear(_my_peer())
				_system("Creativa: stelle azzerate, la polizia ti lascia in pace.")
		"calm_clans":
			if creative and clans:
				var n := clans.make_peace(my_name)
				_system("Creativa: pace fatta con %d clan. Nessuno ti cerca più." % n if n > 0 else "Creativa: nessun clan ce l'aveva con te.")
		"model":
			_model_index = (_model_index + 1) % MODELS.size()
			player.set_model(MODELS[_model_index])
			_save_settings()
			if _online_now():
				announce.rpc(my_name, MODELS[_model_index])
		"quit":
			_save_settings()
			save_profile()
			if clans:
				clans.save()
			get_tree().quit()
	_pause.refresh(quality_high, police_on, simulate, my_name, _online_now(), creative)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or _menu.visible or _pause.visible or (_slot and _slot.visible) or (_clan_ui and _clan_ui.visible) or (_bank_ui and _bank_ui.visible) or (_home_ui and _home_ui.visible):
		return
	if event.is_action_pressed("pause") and not _bigmap.visible and not (hud and hud.shop_open()):
		_open_pause()
		get_viewport().set_input_as_handled()
		return
	if _bigmap.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_map")):
		_toggle_big_map()
		return
	if hud and hud.shop_open():
		# Col joypad si esce con B/Cerchio (ui_cancel); la croce serve a scorrere la lista.
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.is_action_pressed("interact")):
			hud.close_shop()
		return
	if event is InputEventKey and event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # Esc libera il mouse (B del joypad invece fa la capriola)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _bigmap.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("chat"):
		_open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("enter_car"):
		_toggle_car()
	elif event.is_action_pressed("respawn") and not player.dead:
		_leave_car()
		if homes.inside != "":
			homes.leave()
		player.teleport(_respawn_point())
	elif event.is_action_pressed("interact") and not hud.shop_open() and not clans.boss_near(player.global_position, 2.6).is_empty() and not player.mounted() and not player.dead:
		_open_clan_ui(int(clans.boss_near(player.global_position, 2.6)[1]))
	elif event.is_action_pressed("interact") and not hud.shop_open() and not player.mounted() and not player.dead and _home_interact():
		pass
	elif event.is_action_pressed("arrange") and homes.inside != "" and not homes.visiting:
		_home_ui.open_edit()
	elif event.is_action_pressed("interact") and not hud.shop_open() and not player.mounted() and not player.dead and missions.try_start(player.global_position):
		pass
	elif event.is_action_pressed("interact") and not hud.shop_open() and not player.mounted() and not player.dead and _bank_interact():
		pass
	elif event.is_action_pressed("clan") and not player.dead:
		_open_clan_ui(-1)
	elif event.is_action_pressed("backup") and not player.dead:
		clan_request("backup", [])
	elif event.is_action_pressed("interact") and not hud.shop_open() and icone and not player.mounted() and not player.dead and icone.talk(player.global_position):
		pass
	elif event.is_action_pressed("interact") and not hud.shop_open() and not _slot_here().is_empty() and not player.mounted() and not player.dead:
		_open_slot()
	elif event.is_action_pressed("interact") and not hud.shop_open():
		var shop := shops.shop_here()
		if not shop.is_empty() and player.vehicle == null and not player.dead:
			hud.open_shop(shop)
			player.input_enabled = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif not player.dead and not player.mounted():
			_try_sell()
	elif creative and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_K:
		_call_heli()
	elif event.is_action_pressed("jetpack") and player.has_jetpack:
		player.jet_worn = not player.jet_worn
		_system("Jetpack " + ("indossato: in aria tieni premuto Spazio." if player.jet_worn else "tolto (J per rimetterlo)."))
	elif event.is_action_pressed("horn") and player.vehicle:
		player.vehicle.honk()
	elif event.is_action_pressed("detonate"):
		if combat.detonate(_my_peer()) == 0 and player.ammo.has("tnt"):
			_system("Nessuna carica di TNT piazzata.")
	elif event.is_action_pressed("next_weapon"):
		_wheel_down = Time.get_ticks_msec()  # tenuto premuto: rotella; tocco veloce: arma successiva
	elif event is InputEventKey and event.pressed and event.is_action("slot_1") or event.is_action_pressed("slot_2") or event.is_action_pressed("slot_3") or event.is_action_pressed("slot_4") or event.is_action_pressed("slot_5") or event.is_action_pressed("slot_6") or event.is_action_pressed("slot_7"):
		for i in range(1, 8):
			if event.is_action_pressed("slot_%d" % i):
				player.select_slot(i)
	elif event.is_action_pressed("next_model"):
		_model_index = (_model_index + 1) % MODELS.size()
		player.set_model(MODELS[_model_index])
		_save_settings()
		if _online_now():
			announce.rpc(my_name, MODELS[_model_index])
	elif event.is_action_pressed("toggle_map"):
		_toggle_big_map()
	elif event.is_action_pressed("toggle_police"):
		if simulate:
			_set_police(not police_on)
		else:
			_system("La polizia la decide chi ospita la partita.")
	elif event.is_action_pressed("quality"):
		quality_high = not quality_high
		_apply_quality()
		_save_settings()
		_system("Grafica: qualità " + ("alta" if quality_high else "bassa"))


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if _pending_release and _pending_release.freeze and not _pending_release.driven_locally:
		if _online_now():
			car_release.rpc(_pending_release.car_id, _pending_release.global_transform)
		_pending_release = null
	simulate = not _online_now() or multiplayer.is_server()
	if not _online_now():
		return
	if multiplayer.is_server():
		_clock_t -= delta
		if _clock_t <= 0.0:
			_clock_t = 5.0
			net_clock.rpc(daynight.hour)
		# Mondo condiviso: a ogni giocatore lo stato di pedoni, traffico e polizia che ha vicino.
		_world_timer += delta
		if _world_timer >= 0.1:
			_world_timer = 0.0
			_world_frame += 1
			var w := {}
			for peer: int in police.wanted:
				w[peer] = [police.level(peer), police.calm_of(peer)]
			for id: int in _remote:
				var rp: Player = _remote[id]
				net_wanted.rpc_id(id, police.active, w)
				for part: PackedFloat32Array in netsync.build_for(rp.global_position, pedestrians, traffic, police, clans, banks):
					net_world.rpc_id(id, _world_frame, part)
	_send_timer += delta
	if _send_timer >= 1.0 / SEND_RATE:
		_send_timer = 0.0
		if not server_mode:
			var s := player.net_state()
			state.rpc(s[0], s[1], s[2], s[3], s[4], s[5])
		for c: Car in [player.vehicle, _pending_release]:
			if c:
				car_state.rpc(c.car_id, c.global_transform, c.steering / Car.MAX_STEER)


func _process(delta: float) -> void:
	_update_wheel()
	_time += delta
	_boss_scan -= delta
	if _boss_scan <= 0.0 and player and clans:
		# Un boss visto da vicino finisce sulla mappa.
		_boss_scan = 1.0
		var bn: Array = clans.boss_near(player.global_position, 35.0)
		if not bn.is_empty():
			var bname := String(clans.clan(int(bn[1])).get("boss", ""))
			if bname != "" and not _known_bosses.has(bname):
				_known_bosses.append(bname)
				_system_clan("Ora sai dove trovare %s: è segnato sulla mappa." % bname)
				_save_settings()
	_frame += 1
	if _respawn_timer >= 0.0:
		_respawn_timer -= delta
		if _respawn_timer < 0.0 and player and player.dead:
			player.respawn_at(_respawn_point())
	if player == null:
		# Volo lento sopra il quartiere mentre si sceglie nel menu.
		var a := _time * 0.05
		var c := city.spawn
		_overview.global_position = c + Vector3(cos(a) * 260.0, 140.0, sin(a) * 260.0)
		_overview.look_at(c, Vector3.UP)
	elif _frame % 15 == 0:
		var s := city.street_name(player.global_position)
		if player.swimming:
			s = "Tevere (a nuoto)"
		combat.my_peer = _my_peer()
		_street.text = s
		_update_zone_label()
		var st: int = my_stars()
		if _prev_stars >= 1 and st == 0 and not player.dead:
			add_fame(Crime.FAME["escape"] * _prev_stars / 2)  # seminata la polizia
			_system("Hai seminato la polizia: fama +%d." % (Crime.FAME["escape"] * _prev_stars / 2))
		_prev_stars = st
		if player.vehicle is Heli:
			_hint.text = ("F scendi · Spazio/Ctrl su-giù · WASD vola · Shift veloce · clic sx mitra · dx o R razzi"
				if (player.vehicle as Heli).rpm > 0.9 else "Il rotore prende giri… (F scendi)")
		elif player.vehicle:
			_hint.text = ("F / Y scendi · Spazio / A freno a mano · clic sinistro / LB spara" if player.vehicle.model.begins_with("bus")
				else "F / Y scendi · Shift / B derapata · Spazio / A freno a mano · clic sinistro / LB spara")
		elif player.scooter >= 0:
			_hint.text = "W / RT avanti · S / LT frena · A-D sterza · clic sinistro / LB spara · F / Y scendi"
		elif scooters.nearest(player.global_position, 2.2):
			_hint.text = "F / Y / Triangolo sali sul monopattino"
		elif _nearest_car(4.0, true) is Heli:
			_hint.text = "F / Y / Triangolo sali sull'elicottero"
		elif _nearest_car(4.0, true):
			_hint.text = "F / Y / Triangolo sali in auto"
		elif traffic and not _nearest_traffic(5.0).is_empty():
			_hint.text = "F / Y / Triangolo ruba l'auto (tiri fuori chi guida)"
		elif (_slot and _slot.visible) or (_clan_ui and _clan_ui.visible) or (_bank_ui and _bank_ui.visible) or (_home_ui and _home_ui.visible):
			_hint.text = ""
		elif _home_hint() != "":
			_hint.text = _home_hint()
		elif _drill_bank >= 0:
			_hint.text = "Trapano sulla porta del caveau: %d%% (resta qui, F o E per smettere)" % int(_drill_t / Banks.DRILL_TIME * 100.0)
		elif missions.hint(player.global_position) != "" and not player.mounted():
			_hint.text = missions.hint(player.global_position)
		elif _bank_hint() != "":
			_hint.text = _bank_hint()
		elif not clans.boss_near(player.global_position, 2.6).is_empty() and not player.mounted():
			var bn: Array = clans.boss_near(player.global_position, 2.6)
			var bc: Dictionary = clans.clan(int(bn[1]))
			_hint.text = "E / croce su: parla con %s (%s)" % [bc.get("boss", "il boss"), bc.get("name", "")]
		elif icone and icone.hint(player.global_position) != "" and not player.mounted():
			_hint.text = icone.hint(player.global_position)
		elif not _slot_here().is_empty() and not player.mounted():
			_hint.text = "E / croce su: gioca alla slot machine"
		elif player.stash > 0 and _nearest_passerby(2.5) != null:
			_hint.text = "E / croce su: offri la roba"
		elif String(Weapons.info(player.weapon)["kind"]) in ["gun", "rocket"] and _near_clerk(8.0):
			_hint.text = "Mira al commesso (tasto destro / LT) per rapinare il locale"
		else:
			_hint.text = ""
	if player and not player.dead:
		_check_robbery(delta)
	if player and creative:
		_creative_refill()
	if player and server_mode:
		_server_log_t -= delta
		if _server_log_t <= 0.0:
			_server_log_t = 60.0
			# Ogni 10 minuti guarda se è uscita una versione nuova: se non c'è nessuno, si chiude e lo script
			# del telefono riparte con quella nuova.
			_server_upd_n += 1
			if _server_upd_n % 10 == 0 and _remote.is_empty() and updater:
				updater.check()
			print("SERVER %s: %d giocatori (%s), %d fps, ora del gioco %s" % [Time.get_time_string_from_system(), _remote.size(),
				", ".join(_names.values()), Engine.get_frames_per_second(), daynight.clock_text()])
	elif player:
		_profile_t -= delta
		if _profile_t <= 0.0:
			_profile_t = 20.0
			save_profile()
	if player:
		_fame_tick(delta)
		_drill_tick(delta)
		# Interessi del conto a mezzanotte.
		if _last_hour > 23.0 and daynight.hour < 1.0 and bank_balance > 0:
			var interest := mini(2000, bank_balance / 100)
			bank_balance += interest
			save_bank()
			_system("La banca ti ha accreditato € %d di interessi." % interest)
		_last_hour = daynight.hour
	if player and _args.has("jettest") and _frame % 30 == 0:
		print("jetpack: quota %.1f  jet %s  carburante %.2f  armi %d" % [player.global_position.y - city.surface_at(player.global_position.x, player.global_position.z), player.jet_on, player.jet_fuel, player.owned_weapons().size()])
	if player and _args.has("god"):
		player.health = Player.MAX_HEALTH  # prova: non si muore
	if player and _dest != null:
		_route_t -= delta
		if _route_t <= 0.0:
			_route_t = 1.0
			_update_route()
	if player and player.vehicle is Heli:
		var v := player.vehicle
		_speed.text = "%d km/h  %d m" % [roundi(v.speed_kmh()), roundi(v.global_position.y - city.surface_at(v.global_position.x, v.global_position.z))]
	elif player and player.vehicle:
		_speed.text = "%d km/h" % roundi(player.vehicle.speed_kmh())
	elif player and player.scooter >= 0:
		_speed.text = "%d km/h" % roundi(player._ride_speed * 3.6)
	elif _speed.text != "":
		_speed.text = ""
	for l: Node in _chat_box.get_children():
		var age: float = _time - float(l.get_meta("born", _time))
		(l as Label).modulate.a = clampf(12.0 - age, 0.0, 1.0)
	if player and _args.has("drive") and not _args.has("drove") and _time > float(_args.get("drive_at", "1")):
		_args["drove"] = true  # prova automatica: sale sull'auto più vicina (--drive=go: e accelera)
		var c := _nearest_car(200.0, true)
		if c:
			if _args.has("hilltest"):  # prova in salita: --hilltest=x,z,gradi (l'auto parte lì, muso verso gradi)
				var hv: PackedStringArray = String(_args["hilltest"]).split(",")
				var hx := float(hv[0])
				var hz := float(hv[1])
				c.global_transform = Transform3D(city.ground_basis(hx, hz, deg_to_rad(float(hv[2]))), Vector3(hx, city.surface_at(hx, hz) + 0.7, hz))
			player.teleport(c.global_position + Vector3(0, 0.5, 0))
			_toggle_car()
			if _args["drive"] == "go":
				Input.action_press("move_forward")
			if _args.has("v0"):  # prova: --v0=km/h, l'auto parte già lanciata (quando il guidatore è al volante)
				c.set_meta("v0", float(_args["v0"]) / 3.6)
	if player and police and _args.has("wanted") and not player.dead:
		# Prova: --wanted=n tiene il giocatore ricercato con n stelle.
		police.wanted[_my_peer()] = int(_args["wanted"])
		police.calm[_my_peer()] = 0.0
		police.last_seen[_my_peer()] = player.global_position
		if _frame % 120 == 0:
			for n: Node in police.get_children():
				if n is Police.PoliceHeli:
					print("elicottero polizia %s %d: a %d m, quota %d, vita %d, via %s · io vita %d" % [str(n.global_position.round()), n.nid, roundi(n.global_position.distance_to(player.global_position)), roundi(n.global_position.y - player.global_position.y), roundi(n.health), n.leaving, roundi(player.health)])
	if player and _args.has("slot") and not _args.has("slot_in") and _time > 2.0:
		_args["slot_in"] = true  # prova: --slot=n davanti alla prima slot del bar n (indice nei locali) e la apre
		var bars := []
		for i in city.venues.size():
			if city.venues[i]["kind"] == "bar":
				bars.append(i)
		var room: Dictionary = city.venue_rooms[bars[int(_args["slot"]) % bars.size()]]
		var sl: Array = room["slots"][0]
		player.teleport(sl[0] + Vector3(0, 0.2, 0))
		_open_slot()
	if _slot and _args.has("slotspin") and _slot.visible and not _args.has("slot_spun") and _time > float(_args["slotspin"]):
		_args["slot_spun"] = true
		_slot.spin()
	if player and _args.has("boss") and clans and not _args.has("boss_done"):
		# Prova: --boss=n davanti al boss del clan n; dopo 4 secondi apre il dialogo.
		var bc: Dictionary = clans.clan(int(_args["boss"]))
		var hq := Vector3(float(bc["hq"][0]), float(bc["hq"][1]), float(bc["hq"][2]))
		if not _args.has("boss_tp"):
			_args["boss_tp"] = true
			player.teleport(hq + Vector3(0, 0.5, 3.0))
			player.cam_yaw = 0.0
			player.cam_pitch = -0.15
		elif _time > 5.0 and not clans.boss_near(player.global_position, 4.0).is_empty():
			_args["boss_done"] = true
			_open_clan_ui(int(_args["boss"]))
	if player and _args.has("hittest"):
		# Prova (chi ospita): entra nel Clan di Prati e manda il primo sicario contro --hittest=Nome.
		if not _args.has("ht1") and _time > 3.0:
			_args["ht1"] = true
			fame = 400
			player.money = 200000
			clan_request("fame", [fame])
			clan_request("join", [3])
		elif not _args.has("ht2") and _time > 16.0:
			_args["ht2"] = true
			clan_request("contract", [String(_args["hittest"]), 0])
		elif _frame % 120 == 0 and _args.has("ht2"):
			for n: Node in clans.get_children():
				if n is Clans.Soldier and (n as Clans.Soldier).role == "hitman":
					var tgt: Node3D = (n as Clans.Soldier).target
					print("sicario %s: vita %d, a %d m dal bersaglio" % [(n as Clans.Soldier).display, roundi((n as Clans.Soldier).health), roundi(n.global_position.distance_to(tgt.global_position)) if tgt else -1])
	if player and _args.has("profiletest") and not _args.has("pt_done") and _time > 3.0:
		_args["pt_done"] = true
		print("profilo caricato: soldi %d, armi %s, droga %s, jetpack %s" % [player.money, player.owned_weapons(), player.drugs, player.has_jetpack])
		if String(_args["profiletest"]) == "scrivi":
			player.money = 12345
			player.give_weapon("fucile", 60, false)
			player.drugs = {"erba": 7}
			player.has_jetpack = true
			save_profile()
			print("profilo scritto")
	if player and _args.has("hometest"):
		_home_test()
	if player and _args.has("mission"):
		_mission_test()
	if player and _args.has("drilltest"):
		var db: Dictionary = banks.banks[0]
		if not _args.has("dt1") and _time > 3.0:
			_args["dt1"] = true
			var door: Vector3 = db["room"]["vault_door"]
			player.teleport(door - (db["room"]["n"] as Vector3) * 1.2 + Vector3(0, 0.3, 0))
		elif not _args.has("dt2") and _time > 4.0:
			_args["dt2"] = true
			print("trapano: inizio, vicino al caveau %d" % banks.vault_near(player.global_position))
			_bank_interact()
		elif _frame % 120 == 0 and _args.has("dt2"):
			print("trapano t=%d: %d%%, caveau aperto %s, stelle %d" % [int(_time), int(_drill_t / Banks.DRILL_TIME * 100), db["st"]["open"], my_stars()])
	if player and _args.has("banktest"):
		_bank_test()
	if player and _args.has("clantest"):
		_clan_test()
	if player and _args.has("punchtest"):
		_punch_test()
	if player and _args.has("furtotest"):
		_steal_test()
	if player and _args.has("threattest"):
		# Prova: rabbia dei clan sulla HUD, boss scoperti sulla mappa, vita dell'elicottero che torna.
		if _ct_step == 0 and _time > 3.0:
			_ct_step = 1
			clans.rage["0|%s" % my_name] = 170.0
			clans.rage["1|%s" % my_name] = 20.0
			var hq: Array = clans.clan(1)["hq"]
			player.teleport(Vector3(float(hq[0]) + 6.0, float(hq[1]) + 1.0, float(hq[2]) + 6.0))
			for n: Node in get_tree().get_nodes_in_group("damageable"):
				if n is Heli:
					(n as Heli).take_damage(500.0, 0, Vector3.ZERO)
			print("minacce: ", clans.threats(my_name), " · boss in mappa: ", _boss_pois().size())
		elif _ct_step == 1 and _time > 18.0:
			_ct_step = 2
			var hs := []
			for n: Node in get_tree().get_nodes_in_group("damageable"):
				if n is Heli:
					hs.append(roundi((n as Heli).health))
			print("minacce: ", clans.threats(my_name), " · boss in mappa: ", _boss_pois().size(), " · conosciuti ", _known_bosses, " · vita elicotteri ", hs)
			if creative:
				police.wanted[_my_peer()] = 3.0
				_on_pause_action("calm_stars")
				_on_pause_action("calm_clans")
				print("dopo la pace: minacce ", clans.threats(my_name), " · stelle ", my_stars())
	if player and _args.has("clantest2"):
		_clan_test2()
	if player and _args.has("press"):
		# Prova: --press=azione@inizio-fine,... tiene premute delle azioni in quegli intervalli (secondi).
		for item: String in String(_args["press"]).split(","):
			var parts := item.split("@")
			var span := parts[1].split("-")
			var on := _time >= float(span[0]) and _time < float(span[1])
			if on != Input.is_action_pressed(parts[0]):
				if on:
					Input.action_press(parts[0])
				else:
					Input.action_release(parts[0])
	if player and _args.has("heli") and not _args.has("heli_in") and _time > 2.0:
		_args["heli_in"] = true  # prova: sale sull'elicottero numero --heli=n
		var hc: Car = _extra_cars.get(Heli.BASE_ID + int(_args["heli"]))
		player.teleport(hc.global_position + Vector3(2.5, 0.5, 0))
		_toggle_car()
	if player and _args.has("heli") and player.vehicle and _frame % 60 == 0:
		var hv := player.vehicle
		print("volo: pos %s  giri %.2f  vel %.0f km/h  vita %d  lift %.1f fwd %.1f vy %.1f" % [hv.global_position.round(), (hv as Heli).rpm, hv.speed_kmh(), roundi(hv.health), (hv as Heli)._in_lift, (hv as Heli)._in_fwd, hv.linear_velocity.y])
	if player and _args.has("helishot") and _time > float(String(_args["helishot"]).split(":")[0]) and not _args.has("helishot_done"):
		_args["helishot_done"] = true
		var hs := String(_args["helishot"])
		get_viewport().get_texture().get_image().save_png(hs.substr(hs.find(":") + 1))
	if player and player.vehicle and player.vehicle.has_meta("v0"):
		player.vehicle.linear_velocity = player.vehicle.global_basis.z * float(player.vehicle.get_meta("v0"))
		player.vehicle.remove_meta("v0")
	if player and _args.has("drive") and player.vehicle and _frame % 30 == 0:
		var v := player.vehicle
		print("guida t=%.1f: pos %s  quota terreno %.1f  velocità %.0f km/h  traverso %.1f m/s  rotazione %.0f°/s  derapa %s" % [_time, v.global_position.round(), city.surface_at(v.global_position.x, v.global_position.z), v.linear_velocity.length() * 3.6,
			v.linear_velocity.dot(v.global_basis.x), rad_to_deg(v.angular_velocity.y), v.get("drifting")])
		print("  inclinazione %.0f°  rischio %.2f" % [rad_to_deg(acos(clampf(v.global_basis.y.dot(Vector3.UP), -1.0, 1.0))), float(v.get("roll_risk"))])
		if _args.has("drivedebug"):
			print("  motore %.0f freno %.1f gas %s sterzo %.2f a terra %s" % [v.engine_force, v.brake, Input.is_action_pressed("move_forward"), v.steering, (v.get_child(3) as VehicleWheel3D).is_in_contact() if v.get_child(3) is VehicleWheel3D else "?"])
	if _args.has("say") and _time > 8.0 and _online_now() and not _args.has("said"):
		_args["said"] = true  # prova automatica della chat
		_on_chat_submitted(_args["say"])
	if _args.has("perf") and _frame % 120 == 0:
		# Prova: --perf stampa i tempi per capire se pesa la CPU (script, fisica) o la GPU (disegno).
		print("perf fps %d · process %.1f ms · fisica %.1f ms · draw call %d · triangoli %dk · oggetti %d" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		])
	if _args.has("autoquit") and _time > float(_args["autoquit"]):
		if _args.has("netcount") and netsync:
			var kinds := {}
			for n: Node in netsync.get_children():
				var k: String = str(n.get_class()) + ("/polizia" if n.get_meta("police", false) else "")
				kinds[k] = kinds.get(k, 0) + 1
			print("copie dal mondo condiviso: ", kinds, " stelle mie: ", _my_wanted(), " fps ", Engine.get_frames_per_second())
		get_tree().quit()
	if _args.has("bigmap") and player and not _bigmap.visible and _time > 1.0:
		_toggle_big_map()
		_bigmap.scale_px = float(_args["bigmap"])
		_bigmap.waypoint = Vector2(318, 1303)
		_minimap.waypoint = _bigmap.waypoint
	if player and _args.has("lineup") and not _args.has("lined"):
		_args["lined"] = true  # prova: armi in fila, con la canna (+Z) verso destra
		var base := player.global_position + Vector3(0, 1.5, -3.0)
		var i := 0
		for id: String in Weapons.ORDER:
			var m := Weapons.model(id)
			if m:
				add_child(m)
				m.global_transform = Transform3D(Basis(Vector3.UP, PI / 2), base + Vector3(-2.2 + (i % 4) * 1.5, -floori(i / 4) * 0.6, 0))
				var l := Label3D.new()
				l.text = id
				l.pixel_size = 0.004
				l.position = Vector3(0, 0.25, 0)
				m.add_child(l)
				i += 1
		player.cam_yaw = 0.0
		player.cam_pitch = -0.1
		player.set_zoom(1.5)
	if player and _args.has("inside") and not _args.has("went_in") and _time > 1.0:
		_args["went_in"] = true  # prova: --inside=edificio,piano[,yaw] dentro un palazzo esplorabile
		var f: PackedStringArray = String(_args["inside"]).split(",")
		var e: Array = city.enterables[int(f[0])]
		var fl := int(f[1])
		player.teleport(Vector3(float(e[4]), float(e[6]) + fl * Interiors.FLOOR_H + 0.3, float(e[5])))
		player.cam_yaw = deg_to_rad(float(f[2]) if f.size() > 2 else 0.0)
		player.cam_pitch = -0.1
		player.set_zoom(2.5)
	if player and _args.has("stairs"):
		_stairs_test()
	if player and _args.has("shop") and not _args.has("shopped") and _time > 1.5:
		_args["shopped"] = true  # prova: --shop=n apre l'n-esimo negozio
		var sh: Dictionary = shops.shops[int(_args["shop"])]
		player.teleport(sh["pos"] + Vector3(0, 0.3, 0))
		hud.open_shop(sh)
	if player and _args.has("cops"):
		_cops_test()
	if player and _args.has("venue") and not _args.has("went_venue") and _time > 1.5:
		_args["went_venue"] = true  # prova: --venue=n[,dentro] davanti o dentro l'n-esimo locale
		var f: PackedStringArray = String(_args["venue"]).split(",")
		var room: Dictionary = city.venue_rooms[int(f[0])]
		var inside := f.size() > 1
		var at: Vector3 = room["counter_front"] if inside else room["entrance"] + ((room["entrance"] as Vector3) - (room["counter_front"] as Vector3)).normalized() * 6.0
		if not inside:
			at.y = city.surface_at(at.x, at.z)
		player.teleport(at + Vector3(0, 0.3, 0))
		var look: Vector3 = (room["clerk"] as Vector3) - at
		player.cam_yaw = atan2(-look.x, -look.z)
		player.cam_pitch = -0.12
		player.set_zoom(2.2 if inside else 5.0)
	if player and _args.has("dealer") and not _args.has("went_dealer") and _time > 2.5:
		_args["went_dealer"] = true  # prova: davanti al primo fornitore
		for sh: Dictionary in shops.shops:
			if sh["kind"] == "dealer":
				var dp: Vector3 = sh["pos"]
				player.teleport(dp + Vector3(0, 0.3, 4.0))
				player.cam_yaw = 0.0
				player.cam_pitch = -0.1
				player.set_zoom(3.0)
				break
	if player and _args.has("wheel") and _time > 3.0 and not _args.has("wheeled"):
		_args["wheeled"] = true  # prova: tutte le armi e la rotella aperta
		for id: String in Weapons.ORDER:
			player.give_weapon(id, 20, false)
		_wheel.open()
		_wheel._sel = Weapons.ORDER.find("tnt")
	if player and _args.has("tnttest"):
		if _time > 2.0 and not _args.has("tnt1"):
			_args["tnt1"] = true  # prova: TNT e mine scelte dalla rotella, piazzate e fatte saltare
			player.give_weapon("tnt", 3, false)
			player.give_weapon("mina", 3, false)
			_wheel_pick("tnt")
			player._cool = 0.0
			Input.action_press("fire")
		elif _time > 2.4 and not _args.has("tnt2"):
			_args["tnt2"] = true
			Input.action_release("fire")
			print("tnt: in mano ", player.weapon, ", piazzate ", combat._placed.size(), ", rimaste ", player.ammo.get("tnt", 0))
			_wheel_pick("mina")
			player._cool = 0.0
			Input.action_press("fire")
		elif _time > 2.8 and not _args.has("tnt3"):
			_args["tnt3"] = true
			Input.action_release("fire")
			print("mina: in mano ", player.weapon, ", piazzate ", combat._placed.size(), ", rimaste ", player.ammo.get("mina", 0))
			print("tnt fatte saltare: ", combat.detonate(_my_peer()), ", restano piazzate ", combat._placed.size())
	if player and _args.has("fight"):
		_fight_test()
	if player and _args.has("padtest"):
		_pad_test()
	if player and _args.has("escape"):
		_escape_test()
	if player and _args.has("navtest") and not _args.has("navved") and _time > 2.0:
		# Prova: mappa grande, clic sull'armeria più lontana tra quelle vicine; stampa percorso e indicazioni.
		_args["navved"] = true
		_toggle_big_map()
		_bigmap.scale_px = 0.9
		var target: Dictionary = {}
		for s: Dictionary in shops.shops:
			if s["kind"] == "gun" and String(s["name"]).contains("Lazio"):
				target = s
		var tp: Vector3 = target["pos"]
		_bigmap.center = (Vector2(tp.x, tp.z) + Vector2(player.global_position.x, player.global_position.z)) * 0.5
		await get_tree().process_frame
		var sp := _bigmap.to_screen(Vector2(tp.x, tp.z))
		_bigmap._hover = _bigmap._poi_at(sp)
		_bigmap._choose(sp, false)
		print("nav: destinazione ", _dest_name, " · ", _nav.text.replace("\n", " | "))
		for st: Array in _bigmap.route.get("steps", []):
			print("nav:   ", st[0], " — ", Navigator.fmt_dist(float(st[1])))
	if player and _args.has("jacktest"):
		_jack_test()
	if player and _args.has("feattest"):
		_feat_test()
	if player and _args.has("weapontest"):
		_weapon_test()
	if player and _args.has("pvptest") and _online_now() and _remote.has(1):
		# Prova in rete (su chi entra): uccide chi ospita, poi va a prendere i soldi che ha lasciato.
		if not _args.has("pvp1") and _time > 12.0:
			_args["pvp1"] = _time
			print("pvp: i miei soldi prima %d" % player.money)
			net_hurt.rpc_id(1, 300.0, _my_peer())
		elif _args.has("pvp1") and not _args.has("pvp2") and _time > float(_args["pvp1"]) + 1.5:
			_args["pvp2"] = _time
			player.teleport((_remote[1] as Player).global_position + Vector3(0, 0.3, 0))
		elif _args.has("pvp2") and not _args.has("pvp3") and _time > float(_args["pvp2"]) + 2.0:
			_args["pvp3"] = true
			print("pvp: i miei soldi dopo aver raccolto %d" % player.money)
	if player and _args.has("netjack") and _online_now():
		# Prova in rete (chi entra): conta autobus e monopattini, poi ruba l'auto copiata più vicina e accelera.
		var t0 := float(_args.get("netjack_t", "-1"))
		if t0 < 0.0 and _time > 12.0:
			var puppets := netsync.get_children().filter(func(n: Node) -> bool: return n is NetSync.VehiclePuppet)
			var buses := puppets.filter(func(n: Node) -> bool: return int(n.get("look")) >= Bus.LOOK)
			print("rete: qui si vedono %d veicoli del traffico, di cui %d autobus; monopattini %d" % [puppets.size(), buses.size(), scooters.list.size()])
			var best: Node3D = null
			for n: Node in puppets:
				if int(n.get("look")) < Bus.LOOK and (best == null or (n as Node3D).global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
					best = n
			if best:
				player.teleport(best.global_transform * Vector3(2.6, 0.5, 0))
				_args["netjack_t"] = str(_time)
		elif t0 >= 0.0 and not _args.has("netjacked") and _time > t0 + 0.2:
			_args["netjacked"] = true
			_toggle_car()
			print("rete: rubata dall'amico = %s" % (player.vehicle != null and player.vehicle.car_id >= JACK_BASE))
			Input.action_press("move_forward")
		elif _args.has("netjacked") and not _args.has("netjack_done") and _time > t0 + 3.0:
			_args["netjack_done"] = true
			Input.action_release("move_forward")
			print("rete: auto rubata dall'amico a %d km/h" % roundi(player.vehicle.speed_kmh() if player.vehicle else -1))
	if player and _args.has("scootertest"):
		_scooter_test()
	if player and _args.has("bustest"):
		# Prova: dopo 6 s si mette accanto all'autobus più vicino e lo guarda; stampa quanti ce ne sono e se si muovono.
		var buses := traffic.get_children().filter(func(n: Node) -> bool: return n is Traffic.TrafficCar and (n as Traffic.TrafficCar).is_bus)
		if not _args.has("bus_seen") and _time > 6.0 and not buses.is_empty():
			_args["bus_seen"] = true
			var b: Node3D = buses[0]
			_args["bus_ref"] = [b, b.global_position, _time]
			var side := b.global_transform * Vector3(-9.0, 0, 6.0)
			player.teleport(Vector3(side.x, city.surface_at(side.x, side.z) + 1.0, side.z))
			var to := b.global_position - side
			player.cam_yaw = atan2(-to.x, -to.z) + 0.25
			player.cam_pitch = -0.05
			player.set_zoom(4.0)
			print("bus: autobus in giro %d su %d veicoli del traffico" % [buses.size(), traffic.get_child_count()])
		elif _args.has("bus_ref") and not _args.has("bus_done") and _time > float(_args["bus_ref"][2]) + 8.0:
			_args["bus_done"] = true
			var r: Array = _args["bus_ref"]
			if is_instance_valid(r[0]):
				print("bus: in 8 s ha percorso %.0f m" % (r[0] as Node3D).global_position.distance_to(r[1]))
	if player and _args.has("regentest"):
		# Prova: colpito a 2 s (vita 10), poi stampa la vita ogni 5 s: deve risalire dopo 5 s e fermarsi a 50.
		if not _args.has("hit") and _time > 2.0:
			_args["hit"] = true
			player.take_damage(90.0, 0, player.global_position)
		elif _args.has("hit") and _frame % 300 == 0:
			print("vita: t=%d  %.1f" % [int(_time), player.health])
	if _args.has("shots") and player:
		_shot_tour()
	if _args.has("menushot") and not _args.has("menushot_done") and _time > 8.0:
		# Prova: schermata del menu iniziale (con la riga degli aggiornamenti).
		_args["menushot_done"] = true
		get_viewport().get_texture().get_image().save_png(_args["menushot"])
		get_tree().quit()
	if _args.has("capture") and _frame == _capture_frames:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_args["capture"])
		print("Schermata salvata: ", _args["capture"])
		get_tree().quit()


## Giro di schermate per le verifiche: --shots=file.txt con righe "nome x z yaw pitch zoom".
## Le immagini finiscono accanto al file. Ogni inquadratura aspetta 90 frame.
var _shots: Array = []
var _shot_i := -1
var _shot_wait := 0


func _shot_tour() -> void:
	if _shots.is_empty() and _shot_i < 0:
		var path: String = _args["shots"]
		for line in FileAccess.get_file_as_string(path).split(String.chr(10), false):
			var f := line.strip_edges().split(" ", false)
			if f.size() >= 6:
				_shots.append(f)
		_shot_i = 0
		_shot_wait = 0
	if _shot_i >= _shots.size():
		get_tree().quit()
		return
	var f: PackedStringArray = _shots[_shot_i]
	if _shot_wait == 0:
		var x := float(f[1])
		var z := float(f[2])
		player.teleport(Vector3(x, city.surface_at(x, z) + 1.0, z))
		player.cam_yaw = deg_to_rad(float(f[3]))
		player.cam_pitch = deg_to_rad(float(f[4]))
		player.set_zoom(float(f[5]))
	_shot_wait += 1
	if _shot_wait == 90:
		var dir := String(_args["shots"]).get_base_dir()
		get_viewport().get_texture().get_image().save_png(dir + "/" + f[0] + ".png")
		_shot_i += 1
		_shot_wait = 0


func _toggle_big_map() -> void:
	if _bigmap.visible:
		_bigmap.visible = false
		player.input_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_bigmap.open_at(Vector2(player.global_position.x, player.global_position.z))
		player.input_enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Posizione e nome degli altri giocatori, per le mappe.
func _other_players() -> Array:
	var out := []
	for id: int in _remote:
		var p: Player = _remote[id]
		if p.visible:
			out.append([p.global_position, _names.get(id, "?")])
	return out


# --- Combattimento in rete ---------------------------------------------------------------------


func _send_fx(kind: String, data: Array) -> void:
	if _online_now():
		net_fx.rpc(kind, data)


@rpc("any_peer", "call_remote", "unreliable")
func net_fx(kind: String, data: Array) -> void:
	combat.remote_fx(kind, data, multiplayer.get_remote_sender_id())


## Un altro giocatore mi ha colpito.
@rpc("any_peer", "call_remote", "reliable")
func net_hurt(amount: float, from_peer: int) -> void:
	if player:
		player.take_damage(clampf(amount, 0.0, 300.0), from_peer, player.global_position)


@rpc("any_peer", "call_local", "reliable")
func net_killed(victim: String, killer: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != multiplayer.get_unique_id() and _remote.has(sender):
		# Chi ospita smette di inseguirlo finché non rinasce.
		var rp: Player = _remote[sender]
		rp.dead = true
		get_tree().create_timer(6.0).timeout.connect(func() -> void: if is_instance_valid(rp): rp.dead = false)
		if police:
			police.clear(sender)
	var by: String = my_name if killer == multiplayer.get_unique_id() else _names.get(killer, "")
	_system("%s è stato ucciso%s." % [victim, (" da " + by) if by != "" else ""])
	if simulate and clans:
		clans.on_player_killed(victim)


@rpc("any_peer", "call_remote", "reliable")
func net_car_destroyed(id: int) -> void:
	var car := _car_by_id(id)
	if car:
		car.on_destroyed = Callable()
		car.destroy(multiplayer.get_remote_sender_id())
		car.on_destroyed = _on_car_destroyed


func _on_car_destroyed(id: int) -> void:
	if _online_now():
		net_car_destroyed.rpc(id)


func _on_player_died(by_peer: int) -> void:
	_leave_scooter()
	_respawn_timer = 5.0
	# Ucciso da un altro giocatore: metà dei soldi resta a terra (chiunque può raccoglierla) ed è la perdita.
	if by_peer > 0 and by_peer != _my_peer() and _names.has(by_peer) and player.money > 1:
		var half := player.money / 2
		player.money -= half
		player.penalty_paid = true
		drop_money(player.global_position, half)
		_system("Hai perso € %d: sono a terra dove sei morto." % half)
	if simulate and police:
		police.clear(_my_peer())
	if _online_now():
		net_killed.rpc(my_name, by_peer)
	elif clans:
		clans.on_player_killed(my_name)
	if missions and missions.active != "":
		missions.fail("Sei morto.")
	else:
		_system("Sei morto.")


## Slot machine davanti a cui si trova il giocatore ([posizione, direzione, schermo]) o [].
func _slot_here() -> Array:
	if player == null:
		return []
	var p := player.global_position
	for room: Dictionary in city.venue_rooms:
		for sl: Array in room.get("slots", []):
			var at: Vector3 = sl[0]
			if Vector2(at.x - p.x, at.z - p.z).length() < 1.2 and absf(at.y - p.y) < 1.5:
				return sl
	return []


func _open_slot() -> void:
	var sl := _slot_here()
	if sl.is_empty():
		return
	player.input_enabled = false
	player.cam_yaw = float(sl[1]) + PI  # la camera alle spalle, verso lo schermo
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_slot.open(player)


## Modalità creativa: tutte le armi, munizioni e soldi che non finiscono, jetpack, giubbotto; K fa arrivare
## un elicottero. Solo da soli (in rete sarebbe un vantaggio sugli altri).
func _set_creative(on: bool) -> void:
	var was := creative
	creative = on and not _online_now()
	player.creative = creative
	if creative:
		for id: String in Weapons.ORDER:
			if int(Weapons.info(id).get("price", 0)) >= 0:
				player.give_weapon(id, 999, false)
		player.has_jetpack = true
		player.armor = Player.MAX_ARMOR
		_system("Modalità creativa: armi, munizioni, jetpack e soldi infiniti. K: fai arrivare un elicottero. Dal menu (Esc) azzeri le stelle e fai pace coi clan.")
	elif was:
		player.money = mini(player.money, 50000)
		_system("Modalità creativa spenta.")


func _creative_refill() -> void:
	player.money = 9999999
	for id: String in player.ammo.keys():
		var w := Weapons.info(id)
		if String(w["kind"]) == "melee":
			continue
		player.ammo[id] = 999
		if w.has("mag"):
			player.clip[id] = int(w["mag"])


## Creativa: l'elicottero della prima piazzola arriva qui davanti (nuovo, se era distrutto).
func _call_heli() -> void:
	var h: Heli = _extra_cars.get(Heli.BASE_ID)
	if h == null or h.driven_locally:
		return
	if h.destroyed:
		h._restore()
	var yaw := player.cam_yaw + PI
	var at := player.global_position + Vector3(sin(yaw), 0, cos(yaw)) * 9.0
	at.y = city.surface_at(at.x, at.z) + 0.1
	h.driver_peer = 0
	h.freeze = true
	h.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	_system("Elicottero qui davanti: F per salire.")


func _on_slot_closed() -> void:
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_shop_closed() -> void:
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Prova automatica della fuga (--escape): 4 stelle, poi il giocatore sparisce lontano; stampa le stelle nel tempo.
var _esc_step := 0
var _esc_next := 0.0


func _escape_test() -> void:
	match _esc_step:
		0:
			if _time > 2.0:
				player.health = 100000.0
				for k: String in ["kill", "kill", "car"]:
					_on_local_crime(k, player.global_position)
				print("fuga: reati commessi, stelle %d" % int(_my_wanted()[0]))
				_esc_step = 1
		1:
			if _time > 14.0:
				var cops := get_tree().get_nodes_in_group("cop").size()
				print("fuga: t=%d stelle %d agenti %d, ora scappo a 600 m" % [int(_time), int(_my_wanted()[0]), cops])
				var p := player.global_position + Vector3(450, 0, 400)
				player.teleport(Vector3(p.x, city.surface_at(p.x, p.z) + 1.0, p.z))
				_esc_next = _time
				_esc_step = 2
		2:
			if _time >= _esc_next:
				_esc_next = _time + 4.0
				var w := _my_wanted()
				var near := 0
				for c: Node in get_tree().get_nodes_in_group("cop"):
					if (c as Node3D).global_position.distance_to(player.global_position) < 90.0:
						near += 1
				print("fuga: t=%d stelle %d, senza essere visto da %.1f s, agenti entro 90 m %d" % [int(_time), int(w[0]), float(w[1]), near])
				if int(w[0]) == 0:
					print("fuga: stelle perse!")
					_esc_step = 3


## Prova automatica del furto d'auto (--jacktest): accanto a un'auto del traffico, F, poi gas.
var _jack_step := 0
var _jack_ref := []


func _jack_test() -> void:
	match _jack_step:
		0:
			if _time > 4.0:
				var best: Traffic.TrafficCar = null
				for n: Node in traffic.get_children():
					if n is Traffic.TrafficCar and (best == null or (n as Node3D).global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
						best = n
				if best == null:
					return
				var side := best.global_transform * Vector3(2.6, 0.5, 0)
				player.teleport(side)
				var to := best.global_position - side
				player.cam_yaw = atan2(-to.x, -to.z)
				_jack_ref = [traffic.get_child_count(), pedestrians.get_child_count()]
				_jack_step = 1
		1:
			_toggle_car()
			_jack_ref.append(_time)
			_jack_step = 10
		10:
			# Salire (portiera, guidatore tirato fuori) dura un paio di secondi: CarJack.
			if player.vehicle == null and _time < float(_jack_ref[2]) + 4.0:
				return
			print("furto: alla guida = %s, auto rubata = %s, auto del traffico %d -> %d, pedoni %d -> %d" % [
				player.vehicle != null, player.vehicle != null and player.vehicle.car_id >= JACK_BASE,
				_jack_ref[0], traffic.get_child_count(), _jack_ref[1], pedestrians.get_child_count()])
			Input.action_press("move_forward")
			_jack_ref = [_time]
			_jack_step = 2
		2:
			if _time > float(_jack_ref[0]) + 2.5:
				print("furto: dopo 2,5 s di gas l'auto rubata va a %d km/h, stelle %d" % [roundi(player.vehicle.speed_kmh()) if player.vehicle else -1, int(_my_wanted()[0])])
				Input.action_release("move_forward")
				player.cam_yaw += PI
				_jack_step = 3


## Prova automatica del monopattino (--scootertest): sale sul più vicino, va avanti 3 s sterzando, scende.
var _sc_step := 0
var _sc_ref := []


func _scooter_test() -> void:
	match _sc_step:
		0:
			if _time > 3.0:
				var best: Node3D = null
				for n: Node3D in scooters.list:
					if best == null or n.global_position.distance_to(city.spawn) < best.global_position.distance_to(city.spawn):
						best = n
				player.teleport(best.global_position + Vector3(0.8, 0.3, 0))
				_sc_step = 1
		1:
			_toggle_car()
			print("monopattino: in sella = %s, monopattini liberi a terra %d / %d" % [player.scooter >= 0,
				scooters.list.filter(func(n: Node3D) -> bool: return n.visible).size(), scooters.list.size()])
			_sc_ref = [player.global_position, _time, player._ride_yaw]
			Input.action_press("move_forward")
			_sc_step = 2
		2:
			if _time > float(_sc_ref[1]) + 2.0:
				Input.action_press("move_left")
				_sc_step = 3
		3:
			if _time > float(_sc_ref[1]) + 3.0:
				Input.action_release("move_left")
				Input.action_release("move_forward")
				print("monopattino: %d km/h, percorsi %.1f m, girato di %.2f rad" % [roundi(player._ride_speed * 3.6),
					player.global_position.distance_to(_sc_ref[0]), absf(player._ride_yaw - float(_sc_ref[2]))])
				player.cam_yaw = player._ride_yaw + PI * 0.75
				player.set_zoom(3.5)
				_sc_step = 4
		4:
			if _time > float(_sc_ref[1]) + 5.0:
				_toggle_car()
				print("monopattino: sceso = %s, di nuovo a terra = %s" % [player.scooter < 0,
					scooters.list.filter(func(n: Node3D) -> bool: return n.visible).size() == scooters.list.size()])
				_sc_step = 5


## Prova grafica di tutte le armi (--weapontest=cartella): per ognuna mira (se serve), usa l'arma contro un'auto e
## salva una schermata nella cartella (nome dell'arma .png).
var _wt_i := -1
var _wt_step := 0
var _wt_t := 0.0
var _wt_car: Car


func _weapon_test() -> void:
	if _time < 3.0 or _time < _wt_t:
		return
	var ids: Array = Weapons.ORDER.filter(func(id: String) -> bool: return Weapons.info(id)["kind"] != "none")
	if _args.has("only"):  # --only=cecchino,bazooka: solo queste
		ids = ids.filter(func(id: String) -> bool: return id in String(_args["only"]).split(","))
	if _wt_i < 0:
		player.health = 1000000.0
		police.set_active(false)
		_wt_car = _nearest_car(300.0, true)
		_wt_i = 0
		_wt_step = 0
	if _wt_i >= ids.size():
		get_tree().quit()
		return
	var id: String = ids[_wt_i]
	var kind: String = Weapons.info(id)["kind"]
	var dir := "%s/%s.png" % [_args["weapontest"], id]
	match _wt_step:
		0:
			# Davanti all'auto, a 10 m (corpo a corpo: a 1,5 m), guardandola.
			var dist := 1.4 if kind == "melee" else (4.0 if kind in ["throw", "place"] else 10.0)
			var c := _wt_car.global_position
			var side := c + _wt_car.global_basis.x * dist
			player.teleport(Vector3(side.x, c.y + 0.4, side.z))
			player.give_weapon(id, 30)
			player.weapon = id
			var to := c + Vector3(0, 0.6, 0) - (player.global_position + Vector3(0, 1.6, 0))
			player.cam_yaw = atan2(-to.x, -to.z)
			player.cam_pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.6, 0.3)
			player.set_zoom(3.5)
			if kind in ["gun", "rocket"]:
				Input.action_press("aim")
			_wt_step = 1
			_wt_t = _time + 0.9
		1:
			# Col mirino: puntare la camera sull'auto (la spalla sposta la visuale).
			if kind in ["gun", "rocket"]:
				var to2 := _wt_car.global_position + Vector3(0, 0.6, 0) - player.camera.global_position
				player.cam_yaw = atan2(-to2.x, -to2.z)
				player.cam_pitch = atan2(to2.y, Vector2(to2.x, to2.z).length())
			Input.action_press("fire")
			_wt_step = 2
			_wt_t = _time + (0.35 if kind == "melee" else 0.12)
		2:
			Input.action_release("fire")
			if id == "tnt":
				player.teleport(player.global_position + player.global_basis.z * 0.0 + Vector3(0, 0.3, 0) - Vector3(sin(player.cam_yaw), 0, cos(player.cam_yaw)) * -8.0)
				_wt_step = 3
				_wt_t = _time + 0.8
				return
			if kind == "throw":
				_wt_step = 4
				_wt_t = _time + 3.1  # aspetta l'esplosione della granata
				return
			if kind == "place":
				_wt_step = 4
				_wt_t = _time + 0.5
				return
			_wt_step = 4
		3:
			combat.detonate(_my_peer())
			_wt_step = 4
			_wt_t = _time + 0.12
		4:
			get_viewport().get_texture().get_image().save_png(dir)
			print("armi: %s fatto (%s)" % [id, player.rounds_text()])
			Input.action_release("aim")
			_wt_i += 1
			_wt_step = 0
			_wt_t = _time + 0.6
			if _wt_car.destroyed:
				_wt_car = _nearest_car(400.0, true)


## Prova delle novità (--feattest): munizioni dagli agenti, sparo dall'auto, spaccio, rapina, relitti.
var _ft := 0
var _ft_t := 0.0
var _ft_ref: Variant


func _ft_next(wait: float) -> void:
	_ft += 1
	_ft_t = _time + wait


func _feat_test() -> void:
	if _time < _ft_t:
		return
	match _ft:
		0:
			if _time < 3.0:
				return
			player.health = 100000.0
			player.money = 0
			# 1) Agente ucciso: soldi e munizioni a terra.
			var cop := police.spawn_cop(player.global_position + Vector3(4, 0.3, 0), false)
			_ft_ref = cop
			_ft_next(0.5)
		1:
			(_ft_ref as Police.Cop).take_damage(500.0, _my_peer(), player.global_position)
			var ammo_drops := pedestrians.cash.filter(func(c: Array) -> bool: return c.size() > 3 and String(c[3]) != "")
			print("prova: agente ucciso, scatole di munizioni a terra %d" % ammo_drops.size())
			if not ammo_drops.is_empty():
				_ft_ref = [player.ammo.get("pistola", 0), player.money]
				player.teleport((ammo_drops[0][0] as Node3D).global_position + Vector3(0, -0.2, 0))
			_ft_next(1.0)
		2:
			print("prova: munizioni pistola %d -> %d" % [_ft_ref[0], player.ammo.get("pistola", 0)])
			# 2) Sparo dall'auto.
			var c := _nearest_car(300.0, true)
			player.teleport(c.global_position + Vector3(0, 0.5, 0))
			_toggle_car()
			player.select_slot(2)
			_ft_ref = player.rounds_text()
			Input.action_press("vehicle_fire")
			_ft_next(0.3)
		3:
			Input.action_release("vehicle_fire")
			print("prova: in auto = %s, colpi %s -> %s" % [player.vehicle != null, _ft_ref, player.rounds_text()])
			_leave_car()
			police.set_active(false)
			# 3) Spaccio: 20 pacchetti, poi provo con fino a 10 passanti.
			player.stash = 20
			_ft_ref = [0, player.money, 0]
			_ft_next(1.5)
		4:
			var tried: int = _ft_ref[2]
			var ped: Node3D = null
			for n: Node in pedestrians.get_children():
				if n is Pedestrians.Pedestrian and not n.has_meta("clerk") and not n.has_meta("asked") and not (n as Pedestrians.Pedestrian).dead:
					ped = n
					break
			if ped and tried < 10:
				player.teleport(ped.global_position + Vector3(1.2, 0.3, 0))
				_ft_ref[2] = tried + 1
				_ft = 40
				_ft_t = _time + 0.15
			else:
				print("prova: spaccio, %d passanti, pacchetti 20 -> %d, soldi %d -> %d" % [tried, player.stash, _ft_ref[1], player.money])
				_ft = 5
		40:
			_try_sell()
			_ft = 4
		5:
			# 4) Rapina: vado al bar più vicino e aspetto il commesso.
			var bar := shops.nearest("bar", player.global_position)
			player.teleport((bar["pos"] as Vector3) + Vector3(0, 0.3, 0))
			player.give_weapon("pistola", 24)
			_ft_ref = bar
			_ft_next(2.0)
		6:
			var clerk: Pedestrians.Clerk = _ft_ref.get("clerk")
			if clerk == null or not is_instance_valid(clerk):
				print("prova: nessun commesso al bar")
				_ft = 9
				return
			var away := clerk.global_position + (player.global_position - clerk.global_position).normalized() * 5.0
			player.teleport(Vector3(away.x, clerk.global_position.y + 0.3, away.z))
			var to := clerk.global_position + Vector3(0, 1.0, 0) - (player.global_position + Vector3(0, 1.6, 0))
			player.cam_yaw = atan2(-to.x, -to.z)
			player.cam_pitch = atan2(to.y, Vector2(to.x, to.z).length())
			_ft_ref = [clerk, pedestrians.cash.size()]
			Input.action_press("aim")
			_ft_next(0.8)
		7:
			var clerk: Pedestrians.Clerk = _ft_ref[0]
			# Il mirino deve cadere sul commesso: correggo la camera mentre si mira.
			if is_instance_valid(clerk):
				var to := clerk.global_position + Vector3(0, 1.0, 0) - player.camera.global_position
				player.cam_yaw = atan2(-to.x, -to.z)
				player.cam_pitch = atan2(to.y, Vector2(to.x, to.z).length())
			print("prova: rapina, reazione del commesso = %s, stelle %d" % [clerk.state if is_instance_valid(clerk) else "?", int(_my_wanted()[0])])
			_ft_next(4.0)
		8:
			Input.action_release("aim")
			var clerk: Pedestrians.Clerk = _ft_ref[0]
			print("prova: dopo 4 s il commesso è %s, soldi a terra %d -> %d, vita mia persa %d" % [
				clerk.state if is_instance_valid(clerk) else "?", _ft_ref[1], pedestrians.cash.size(), 100000 - int(player.health)])
			_ft = 9
		9:
			# 5) Relitti: un'auto esplosa e una ribaltata spariscono quando non si guardano.
			var cs: Array = cars.filter(func(c: Car) -> bool: return not c.destroyed).slice(0, 2)
			cs[0].destroy(0)
			cs[0]._wreck_t = Car.WRECK_TIME - 0.5
			cs[1].freeze = false
			cs[1].global_transform = Transform3D(Basis(Vector3.FORWARD, PI), cs[1].global_position + Vector3(0, 1.0, 0))
			cs[1]._flip_t = Car.FLIPPED_TIME - 0.5
			_ft_ref = cs
			player.teleport(city.spawn + Vector3(0, 0.5, 0))
			_ft_next(2.0)
		10:
			var cs: Array = _ft_ref
			print("prova: relitto sparito = %s, auto ribaltata sparita = %s" % [(cs[0] as Car).gone, (cs[1] as Car).gone])
			_ft = 11


## Prova automatica del joypad (--padtest): manda eventi veri di levette, grilletti e tasti e stampa l'esito.
var _pad_step := 0
var _pad_ref := []


func _pad(button: int, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	e.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(e)


func _stick(axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _pad_test() -> void:
	match _pad_step:
		0:
			if _time > 2.0:
				player.select_slot(2)
				_pad_ref = [player.global_position, player.cam_yaw, player.rounds_text()]
				_stick(JOY_AXIS_LEFT_Y, -1.0)
				_stick(JOY_AXIS_RIGHT_X, 0.7)
				_pad_step = 1
		1:
			if _time > 3.5:
				_stick(JOY_AXIS_LEFT_Y, 0.0)
				_stick(JOY_AXIS_RIGHT_X, 0.0)
				_stick(JOY_AXIS_TRIGGER_RIGHT, 1.0)
				_pad_step = 2
		2:
			if _time > 4.0:
				_stick(JOY_AXIS_TRIGGER_RIGHT, 0.0)
				print("pad: spostato %.1f m, camera girata %.2f rad, colpi %s -> %s" % [
					player.global_position.distance_to(_pad_ref[0]), absf(player.cam_yaw - float(_pad_ref[1])),
					_pad_ref[2], player.rounds_text()])
				_pad(JOY_BUTTON_DPAD_RIGHT, true)
				_pad_step = 3
		3:
			_pad(JOY_BUTTON_DPAD_RIGHT, false)
			print("pad: mappa aperta con croce destra = ", _bigmap.visible)
			_pad(JOY_BUTTON_A, true)
			_pad_step = 4
		4:
			_pad(JOY_BUTTON_A, false)
			print("pad: segnalino col tasto A = ", _bigmap.waypoint)
			_pad(JOY_BUTTON_B, true)
			_pad_step = 40
		40:
			_pad(JOY_BUTTON_B, false)
			_pad_step = 5
		5:
			print("pad: mappa chiusa con B = ", not _bigmap.visible, ", comandi attivi = ", player.input_enabled)
			var gun := shops.nearest("gun", player.global_position)
			player.money = 5000
			player.teleport(gun["pos"] + Vector3(0, 0.3, 0))
			_pad_step = 6
		6:
			if _time > 5.5:
				_pad(JOY_BUTTON_DPAD_UP, true)
				_pad_step = 7
		7:
			_pad(JOY_BUTTON_DPAD_UP, false)
			_pad_step = 70
		70:
			_pad_ref = [get_viewport().gui_get_focus_owner()]
			print("pad: negozio aperto con croce su = ", hud.shop_open(), ", voce selezionata = ", _pad_ref[0] != null)
			_pad(JOY_BUTTON_DPAD_DOWN, true)
			_pad_step = 9
		9:
			_pad(JOY_BUTTON_DPAD_DOWN, false)
			_pad_step = 90
		90:
			print("pad: croce giù sposta la selezione = ", get_viewport().gui_get_focus_owner() != _pad_ref[0], ", negozio aperto = ", hud.shop_open())
			_pad_ref = [player.money]
			_pad(JOY_BUTTON_A, true)
			_pad_step = 10
		10:
			_pad(JOY_BUTTON_A, false)
			_pad_step = 11
		11:
			print("pad: comprato con A, soldi %d -> %d" % [_pad_ref[0], player.money])
			_pad(JOY_BUTTON_B, true)
			_pad_step = 12
		12:
			_pad(JOY_BUTTON_B, false)
			_pad_step = 13
		13:
			print("pad: negozio chiuso con B = ", not hud.shop_open(), ", comandi attivi = ", player.input_enabled)
			_pad(JOY_BUTTON_START, true)
			_pad_step = 14
		14:
			_pad(JOY_BUTTON_START, false)
			_pad_step = 15
		15:
			print("pad: menu aperto con Start = ", _pause.visible, ", gioco in pausa = ", get_tree().paused,
				", voce selezionata = ", get_viewport().gui_get_focus_owner() != null)
			_pad(JOY_BUTTON_B, true)
			_pad_step = 16
		16:
			_pad(JOY_BUTTON_B, false)
			_pad_step = 17
		17:
			print("pad: menu chiuso con B = ", not _pause.visible, ", pausa tolta = ", not get_tree().paused)
			# Corsa: velocità con i pugni e col lanciarazzi (clic levetta sinistra).
			player.weapon = "pugni"
			player.teleport(city.spawn + Vector3(0, 0.5, 0))
			_stick(JOY_AXIS_LEFT_Y, -1.0)
			_pad(JOY_BUTTON_LEFT_STICK, true)
			_pad_ref = []
			_pad_step = 18
		18:
			_pad(JOY_BUTTON_LEFT_STICK, false)
			_pad_step = 200
		_:
			if _pad_step >= 200 and _pad_step < 400:
				_pad_step += 1
				# Velocità media su ~1 s di corsa (posizione e tempo), dopo l'accelerazione.
				if _pad_step in [260, 340]:
					_pad_ref.append([player.global_position, _time])
				elif _pad_step in [300, 380]:
					var a: Array = _pad_ref[-1]
					var dp: Vector3 = player.global_position - (a[0] as Vector3)
					_pad_ref[-1] = Vector2(dp.x, dp.z).length() / maxf(_time - float(a[1]), 0.001)
					if _pad_step == 300:
						print("pad: corsa accesa con L3 = ", player._sprint_lock)
						player.give_weapon("bazooka", 2)
					else:
						_stick(JOY_AXIS_LEFT_Y, 0.0)
						print("pad: corsa a mani nude %.1f m/s, col lanciarazzi %.1f m/s" % [_pad_ref[0], _pad_ref[1]])


## Prova automatica del combattimento (--fight): armi, mira, sparo a un'auto, granata, lanciarazzi.
var _fight_step := 0


func _fight_test() -> void:
	if _time < 2.0:
		return
	match _fight_step:
		0:
			player.money = 99999
			for id: String in ["coltello", "mitragliatrice", "fucile", "cecchino", "bazooka", "granata", "mina", "tnt"]:
				player.give_weapon(id, 50)
			player.weapon = "fucile"
			var c := _nearest_car(300.0, true)
			if c:
				var behind := c.global_position + c.global_basis.x * 9.0
				player.teleport(Vector3(behind.x, c.global_position.y + 0.5, behind.z))
				var to := c.global_position - player.global_position
				player.cam_yaw = atan2(-to.x, -to.z)
				player.cam_pitch = -0.08
			Input.action_press("aim")
			_fight_step = 1
		1:
			var c2 := _nearest_car(30.0, true)
			if c2:
				var to2 := c2.global_position + Vector3(0, 0.7, 0) - player.camera.global_position
				player.cam_yaw = atan2(-to2.x, -to2.z)
				player.cam_pitch = atan2(to2.y, Vector2(to2.x, to2.z).length())
			if _time > 3.5:
				Input.action_press("fire")
				_fight_step = 2
		2:
			var c3 := _nearest_car(30.0, false)
			if c3:
				var to3 := c3.global_position + Vector3(0, 0.7, 0) - player.camera.global_position
				player.cam_yaw = atan2(-to3.x, -to3.z)
				player.cam_pitch = atan2(to3.y, Vector2(to3.x, to3.z).length())
			if _time > 5.0:
				Input.action_release("fire")
				player.weapon = "bazooka"
				_fight_step = 3
		3:
			if _time > 6.0:
				Input.action_press("fire")
				_fight_step = 4
		4:
			if _time > 6.3:
				Input.action_release("fire")
				print("prova: vita %d, auto distrutte %d, pedoni %d" % [player.health, cars.filter(func(c: Car) -> bool: return c.destroyed).size(), pedestrians.get_child_count()])
				_fight_step = 5


## Prova automatica delle scale (--stairs=edificio): cammina sulla prima rampa e stampa la quota.
var _stairs_step := 0


func _stairs_test() -> void:
	if _time < 2.0:
		return
	var e: Array = city.enterables[int(_args["stairs"])]
	var a: Vector2 = e[8]
	var b: Vector2 = e[9]
	var d: Vector2 = e[10]
	var u := (b - a).normalized()
	var start := a + (d - a) * 0.5 - u * 1.2
	match _stairs_step:
		0:
			player.teleport(Vector3(start.x, float(e[6]) + 0.3, start.y))
			player.cam_yaw = atan2(-u.x, -u.y)
			player.cam_pitch = -0.2
			Input.action_press("move_forward")
			print("scale: parto da quota ", player.global_position.y)
			_stairs_step = 1
		1:
			if _time > 5.5:
				Input.action_release("move_forward")
				print("scale: arrivo a quota ", player.global_position.y, " (piano terra ", e[6], ", primo piano ", float(e[6]) + Interiors.FLOOR_H, ")")
				_stairs_step = 2


## Prova automatica della polizia (--cops): reati, stelle, agenti e volanti; stampa lo stato.
var _cops_step := 0


func _cops_test() -> void:
	match _cops_step:
		0:
			if _time > 2.0:
				player.give_weapon("fucile", 300)
				player.health = 100000.0  # per la prova: non muore
				for k: String in ["kill", "kill", "car"]:
					_on_local_crime(k, player.global_position)  # da solo va alla propria polizia, in rete a chi ospita
				print("polizia: reati commessi")
				player.cam_pitch = -0.35
				player.set_zoom(9.0)
				_cops_step = 1
		1:
			if _time > 22.0:
				var cops := get_tree().get_nodes_in_group("cop")
				var cars := police.get_children().filter(func(n: Node) -> bool: return n is Police.PoliceCar)
				var origins := police.get_children().filter(func(n: Node) -> bool: return n is Police.PoliceCar).map(func(n: Node) -> String: return (n as Police.PoliceCar).station)
				print("polizia: stelle %d, agenti %d, volanti %d %s, vita persa %d" % [int(_my_wanted()[0]), cops.size(), cars.size(), str(origins), 100000 - int(player.health)])
				_cops_step = 2


# --- Mondo condiviso (pedoni, traffico, polizia) --------------------------------------------------


## Giocatori in partita per id di rete (questo PC e gli altri), per pedoni, traffico e polizia.
func players() -> Dictionary:
	var out := {}
	if player and not server_mode:
		out[_my_peer()] = player
	for id: int in _remote:
		var rp: Player = _remote[id]
		if rp.visible:
			out[id] = rp
	return out


## Posizioni attorno a cui far vivere la città.
func anchors() -> Array:
	return players().values().map(func(p: Player) -> Vector3: return p.global_position)


func new_nid() -> int:
	_next_nid += 1
	return _next_nid


func register(nid: int, node: Node) -> void:
	_registry[nid] = node
	node.tree_exiting.connect(func() -> void: _registry.erase(nid))


## Soldi raccolti da un giocatore (su questo PC o su un altro).
func award(peer: int, amount: int) -> void:
	if peer == _my_peer():
		player.money += amount
		Sfx.play2d("coin", -6.0)
	elif _online_now():
		net_money.rpc_id(peer, amount)


# --- Spaccio e rapine -------------------------------------------------------------------------------


## Passante vivo più vicino entro max_dist (non agenti né commessi), vero o copia; null se nessuno.
func _nearest_passerby(max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for n: Node in get_tree().get_nodes_in_group("pedestrian"):
		if n is Police.Cop or n.get_meta("police", false) or n.has_meta("clerk") or n.has_meta("dealer") or n.get_meta("dead", false) or n.has_meta("gang"):
			continue
		if n is Pedestrians.Pedestrian and (n as Pedestrians.Pedestrian).dead:
			continue
		var d := (n as Node3D).global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


## Probabilità dello spaccio: 1 su 20 compra, 1 su 20 chiama la polizia, gli altri non sono interessati.
const SELL_BUY := 0.3  # di giorno 3 passanti su 10 comprano (se hai quello che cercano)
const SELL_BUY_NIGHT := 0.42
const SELL_SNITCH := 0.05


## Spaccio: E vicino a un passante con dei pacchetti. Ognuno si può provare una volta sola.
## Se un agente ti vede mentre lo fai (linea di vista libera, entro 60 m) diventi ricercato: 1 stella.
func _try_sell() -> void:
	if player.stash <= 0:
		return
	var ped := _nearest_passerby(2.5)
	if ped == null:
		return
	if ped.has_meta("asked"):
		_system("Gliel'hai già chiesto.")
		return
	ped.set_meta("asked", true)
	var night := daynight.is_night()
	# Cosa cerca: erba e fumo più spesso; di notte più MD, LSD e cocaina.
	var total := 0.0
	var weights := {}
	for id: String in Crime.DRUG_ORDER:
		var w := float(Crime.DRUGS[id]["demand"]) * (1.8 if night and id in ["md", "lsd", "cocaina"] else 1.0)
		weights[id] = w
		total += w
	var pick := randf() * total
	var want: String = Crime.DRUG_ORDER[0]
	for id: String in Crime.DRUG_ORDER:
		pick -= float(weights[id])
		if pick <= 0.0:
			want = id
			break
	var r := randf()
	if r < SELL_SNITCH:
		_system("Ha chiamato la polizia!")
		_on_local_crime("dealing", player.global_position)
		if ped is Pedestrians.Pedestrian:
			(ped as Pedestrians.Pedestrian).scare(player.global_position)
		return
	elif r < SELL_SNITCH + (SELL_BUY_NIGHT if night else SELL_BUY):
		var have := want if int(player.drugs.get(want, 0)) > 0 else ""
		var factor := 1.0
		if have == "" and randf() < 0.45:
			# Non hai quello che cerca: a volte si accontenta d'altro, pagandolo meno.
			for id: String in Crime.DRUG_ORDER:
				if int(player.drugs.get(id, 0)) > 0:
					have = id
					factor = 0.85
					break
		if have == "":
			_system("Cercava %s, e tu non ce l'hai." % Crime.DRUGS[want]["name"])
		else:
			var d: Dictionary = Crime.DRUGS[have]
			var price := int(randi_range(int(d["sell"][0]), int(d["sell"][1])) * factor * (1.2 if night and have in ["md", "lsd", "cocaina"] else 1.0))
			var z := Crime.zone_of(Vector2(player.global_position.x, player.global_position.z))
			var mine := clans.clan_of(my_name)
			var net := price
			if mine >= 0 and clans.zone_owner(z) == mine:
				net = int(price * (1.0 - Clans.PIZZO))  # la quota al clan
			player.drugs[have] = int(player.drugs[have]) - 1
			if int(player.drugs[have]) <= 0:
				player.drugs.erase(have)
			player.money += net
			Sfx.play2d("coin", -6.0)
			_system("Venduta una dose di %s: € %d%s (ti restano %d dosi)." % [d["name"], net, (" (€ %d al clan)" % (price - net)) if net < price else "", player.stash])
			clan_request("sale", [have, price, player.global_position])
			if ped is Pedestrians.Pedestrian:
				(ped as Pedestrians.Pedestrian).chat_pause()
	else:
		_system("Non gli interessa.")
	if _cop_sees_me():
		_system("Un agente ti ha visto!")
		_on_local_crime("dealing", player.global_position)


## C'è un agente (vero o copia) che vede il giocatore: entro 60 m e niente muri in mezzo.
func _cop_sees_me() -> bool:
	var space := get_world_3d().direct_space_state
	var me := player.global_position + Vector3(0, 1.3, 0)
	for c: Node in get_tree().get_nodes_in_group("pedestrian"):
		if not (c is Police.Cop or c.get_meta("police", false)):
			continue
		if (c is Police.Cop and (c as Police.Cop).dead) or c.get_meta("dead", false):
			continue
		var eye := (c as Node3D).global_position + Vector3(0, 1.6, 0)
		if eye.distance_to(me) > 60.0:
			continue
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, me, 1)).is_empty():
			return true
	return false


var _rob_cool := 0.0


func _near_clerk(max_dist: float) -> bool:
	for n: Node in get_tree().get_nodes_in_group("pedestrian"):
		if n.has_meta("clerk") and not n.get_meta("robbed", false) and n.get("dead") != true \
				and (n as Node3D).global_position.distance_to(player.global_position) < max_dist:
			return true
	return false


## Rapina: mirare con un'arma da fuoco al commesso di un bar o di una farmacia (entro 15 m).
func _check_robbery(delta: float) -> void:
	_rob_cool -= delta
	if _rob_cool > 0.0 or not player.aiming or player.mounted():
		return
	if not String(Weapons.info(player.weapon)["kind"]) in ["gun", "rocket"]:
		return
	var r := player.aim_ray()
	var q := PhysicsRayQueryParameters3D.create(r[0], r[0] + (r[1] as Vector3) * 15.0, 1 | 32)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var n: Node = hit["collider"]
	if not n.has_meta("clerk") or n.get_meta("dead", false) or n.get("dead") == true or n.get_meta("robbed", false):
		return
	n.set_meta("robbed", true)
	_rob_cool = 2.0
	_system("Rapina! Il commesso…")
	if simulate:
		(n as Pedestrians.Clerk).rob(_my_peer())
	elif _online_now():
		net_rob.rpc_id(1, int(n.get("nid")))


@rpc("any_peer", "call_remote", "reliable")
func net_rob(nid: int) -> void:
	var n: Node = _registry.get(nid)
	if n is Pedestrians.Clerk and is_instance_valid(n):
		(n as Pedestrians.Clerk).rob(multiplayer.get_remote_sender_id())


## Soldi lasciati a terra (li fa nascere chi calcola il mondo condiviso, così tutti li vedono e li possono prendere).
func drop_money(pos: Vector3, amount: int) -> void:
	if simulate:
		pedestrians.drop_cash(pos, amount)
	elif _online_now():
		net_drop_cash.rpc_id(1, pos, amount)


@rpc("any_peer", "call_remote", "reliable")
func net_drop_cash(pos: Vector3, amount: int) -> void:
	if simulate and pedestrians:
		pedestrians.drop_cash(pos, clampi(amount, 0, 10000000))


## Munizioni raccolte da terra (lasciate da un agente) da un giocatore, su questo PC o su un altro.
func award_ammo(peer: int, weapon_id: String, rounds: int) -> void:
	if peer == _my_peer():
		_got_ammo(weapon_id, rounds)
	elif _online_now():
		net_ammo.rpc_id(peer, weapon_id, rounds)


func _got_ammo(weapon_id: String, rounds: int) -> void:
	var had := player.ammo.has(weapon_id)
	player.give_weapon(weapon_id, rounds, false)
	Sfx.play2d("reload", -4.0)
	_system(("+%d colpi: %s" if had else "Raccolta: %s con %d colpi") % ([rounds, Weapons.info(weapon_id)["name"]] if had else [Weapons.info(weapon_id)["name"], rounds]))


@rpc("authority", "call_remote", "reliable")
func net_ammo(weapon_id: String, rounds: int) -> void:
	if player and Weapons.LIST.has(weapon_id):
		_got_ammo(weapon_id, clampi(rounds, 0, 500))


## Reato di un giocatore: lo valuta la polizia di chi ospita.
func crime(kind: String, pos: Vector3, peer: int) -> void:
	if simulate and police and peer > 0:
		police.report(kind, pos, peer)
		if clans:
			clans.on_crime(kind, pos, peer)
		if banks:
			banks.on_crime(kind, pos, peer)


func _on_local_crime(kind: String, pos: Vector3) -> void:
	if simulate:
		crime(kind, pos, _my_peer())
	elif _online_now():
		net_crime.rpc_id(1, kind, pos)


## Colpo su una copia: lo giro a chi ospita, che lo applica all'originale.
func forward_hit(nid: int, amount: float, at: Vector3) -> void:
	if _online_now():
		net_npc_hit.rpc_id(1, nid, amount, at)


func _my_wanted() -> Array:
	if simulate:
		return [police.level(_my_peer()), police.calm_of(_my_peer())] if police and police.active else [0, 0.0]
	var w: Array = netsync.wanted.get(_my_peer(), [0, 0.0])
	return w


func _police_dots() -> Array:
	return police.dots() if simulate else netsync.police_dots()


func _set_police(on: bool) -> void:
	police_on = on
	police.set_active(on)
	_save_settings()
	_system("Polizia " + ("attiva" if on else "disattivata (meno calcoli)"))


@rpc("authority", "call_remote", "unreliable_ordered")
func net_world(frame: int, data: PackedFloat32Array) -> void:
	if netsync:
		netsync.apply(frame, data)


@rpc("authority", "call_remote", "unreliable_ordered")
func net_wanted(active: bool, w: Dictionary) -> void:
	if netsync:
		netsync.apply_wanted(active, w)


@rpc("any_peer", "call_remote", "reliable")
func net_npc_hit(nid: int, amount: float, at: Vector3) -> void:
	var n: Node = _registry.get(nid)
	if n and is_instance_valid(n) and n.has_method("take_damage"):
		n.take_damage(clampf(amount, 0.0, 400.0), multiplayer.get_remote_sender_id(), at)


@rpc("any_peer", "call_remote", "reliable")
func net_crime(kind: String, pos: Vector3) -> void:
	crime(kind, pos, multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func net_money(amount: int) -> void:
	if player:
		player.money += clampi(amount, 0, 10000000)  # anche i soldi lasciati da un altro giocatore ucciso
		Sfx.play2d("coin", -6.0)


# --- Profilo del giocatore (resta tra una partita e l'altra) -----------------------------------------


## Soldi in tasca, armi e colpi, droga, jetpack, giubbotto: salvati sul PC di chi gioca ogni 20 secondi e all'uscita.
## In modalità creativa, sul server e nelle prove non si salva niente.
func save_profile() -> void:
	if player == null or server_mode or creative or ((_args.has("autoquit") or _args.has("capture")) and not _args.has("profiletest")):
		return
	var d := {"money": player.money, "ammo": player.ammo, "clip": player.clip, "weapon": player.weapon,
		"drugs": player.drugs, "jetpack": player.has_jetpack, "jet_worn": player.jet_worn, "armor": player.armor}
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func _load_profile() -> void:
	if ((_args.has("autoquit") or _args.has("capture")) and not _args.has("profiletest")) or not FileAccess.file_exists(PROFILE_PATH):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not d is Dictionary:
		return
	player.money = int(d.get("money", player.money))
	player.ammo = {}
	player.clip = {}
	for id: String in (d.get("ammo", {}) as Dictionary):
		player.ammo[id] = int(d["ammo"][id])
	for id: String in (d.get("clip", {}) as Dictionary):
		player.clip[id] = int(d["clip"][id])
	if not player.ammo.has("pugni"):
		player.ammo["pugni"] = -1
	player.weapon = String(d.get("weapon", "pugni")) if player.ammo.has(String(d.get("weapon", ""))) else "pugni"
	player.drugs = {}
	for id: String in (d.get("drugs", {}) as Dictionary):
		player.drugs[id] = int(d["drugs"][id])
	player.has_jetpack = bool(d.get("jetpack", false))
	player.jet_worn = bool(d.get("jet_worn", true))
	player.armor = float(d.get("armor", 0.0))


# --- Case -------------------------------------------------------------------------------------------


## Dove si rinasce (e dove porta H): davanti alla propria casa più vicina, se se ne ha una.
func _respawn_point() -> Vector3:
	if homes:
		var h := homes.nearest_owned(player.global_position)
		if not h.is_empty():
			var d: Vector3 = h["door"]
			return d + Vector3(0, 1.0, 0)
	return _spawn_point()


func _home_interact() -> bool:
	if homes == null:
		return false
	var p := player.global_position
	if homes.inside != "":
		if homes.exit_near(p):
			homes.leave()
			return true
		var u := homes.usable_near(p)
		if not u.is_empty() and not homes.visiting:
			match String(u[1]):
				"safe":
					_home_ui.open_safe()
				"wardrobe":
					_model_index = (_model_index + 1) % MODELS.size()
					player.set_model(MODELS[_model_index])
					_save_settings()
					if _online_now():
						announce.rpc(my_name, MODELS[_model_index])
					_system("Ti sei cambiato.")
				"sleep":
					player.heal(Player.MAX_HEALTH)
					if not _online_now():
						daynight.hour = 8.0
						_system("Hai dormito fino alle 8 di mattina. Vita piena.")
					else:
						_system("Ti sei riposato: vita piena (in rete l'ora non cambia).")
					save_bank()
			return true
		return false
	var d := homes.door_near(p)
	if not d.is_empty():
		_home_ui.open_door(String(d["id"]))
		return true
	return false


func _home_hint() -> String:
	if homes == null or player.mounted():
		return ""
	var p := player.global_position
	if homes.inside != "":
		if homes.exit_near(p):
			return "E / croce su: esci" + ("" if homes.visiting else " · O arreda")
		var u := homes.usable_near(p)
		if not u.is_empty() and not homes.visiting:
			return {"safe": "E: apri la cassaforte", "wardrobe": "E: cambiati (armadio)", "sleep": "E: dormi"}[u[1]]
		return "" if homes.visiting else "O: arreda la casa"
	var d := homes.door_near(p)
	if not d.is_empty():
		return "E / croce su: %s %s" % ["casa tua ·" if homes.owned.has(d["id"]) else "in vendita ·", d["name"]]
	return ""


# --- Banche -----------------------------------------------------------------------------------------


var _hm_step := 0


## Prova delle case (--hometest=tipo): elenca le case, compra la prima di quel tipo, entra, arreda, foto.
func _home_test() -> void:
	var dir := String(_args.get("shotdir", "."))
	if _hm_step == 0 and _time > 2.0:
		_hm_step = 1
		var counts := {}
		for pp: Dictionary in homes.properties:
			counts[pp["type"]] = int(counts.get(pp["type"], 0)) + 1
		print("case: %d %s" % [homes.properties.size(), counts])
		for pp: Dictionary in homes.properties:
			if pp["type"] == String(_args["hometest"]):
				player.money = 500000
				print(homes.buy(String(pp["id"])))
				player.teleport((pp["door"] as Vector3) + Vector3(0, 0.5, 0))
				_args["home_id"] = pp["id"]
				break
	elif _hm_step == 1 and _time > 3.5:
		_hm_step = 2
		get_viewport().get_texture().get_image().save_png(dir + "/door.png")
		homes.enter(String(_args["home_id"]))
	elif _hm_step == 2 and _time > 6.0:
		_hm_step = 3
		get_viewport().get_texture().get_image().save_png(dir + "/inside.png")
		_home_ui.open_edit()
		var s := homes.room_size()
		for e: Array in [["divano", s.x * 0.5, 3.2, PI], ["tv", s.x * 0.5, 1.0, 0.0], ["tappeto", s.x * 0.5, 2.2, 0.0], ["cassaforte", 0.6, s.y - 1.6, PI / 2],
				["armadio", s.x - 0.5, 2.2, -PI / 2], ["pianta", 0.6, 0.8, 0.0], ["biliardo", s.x * 0.3, s.y * 0.55, PI / 2], ["libreria", 0.3, 3.5, PI / 2]]:
			homes.place(e)
	elif _hm_step == 3 and _time > 8.0:
		_hm_step = 4
		get_viewport().get_texture().get_image().save_png(dir + "/edit.png")
		_home_ui.close_ui()
		print("mobili: %d, valore € %d, prezzo di vendita € %d" % [homes.items().size(), homes.furniture_value(String(_args["home_id"])), homes.sell_price(String(_args["home_id"]))])


var _mt_step := 0


## Prova di una missione (--mission=festa|crediti): la avvia e la porta avanti a forza, stampando le fasi.
func _mission_test() -> void:
	var id := String(_args["mission"])
	if _frame % 60 == 0 and missions.active != "":
		print("missione %s: fase %d, obiettivo «%s», soldi %d, stelle %d" % [missions.active, missions.stage, missions._objective.text, player.money, my_stars()])
	if _mt_step == 0 and _time > 2.0:
		_mt_step = 1
		missions.start(id)
	elif _mt_step == 1 and _args.has("mlook") and _time > 3.0:
		# --mlook: ci si ferma a guardare il bersaglio da 12 m (per controllare frecce e nomi).
		_mt_step = 9
		var tgt: Gunman = missions._data.get("target", missions._data.get("debtor"))
		player.teleport(tgt.global_position + Vector3(12, 0.5, 0))
		print("bersaglio: freccia ", tgt._arrow != null and tgt._arrow.visible, " · obiettivo «", missions._objective.text, "» · ", missions._where.text)
	elif _mt_step == 1 and _time > 5.0:
		_mt_step = 2
		var who: Gunman = missions._data.get("target", missions._data.get("debtor"))
		player.teleport(who.global_position + Vector3(3, 0.5, 0))
		who.take_damage(999.0 if id == "festa" else 30.0, _my_peer(), who.global_position)
	elif _mt_step == 2 and _time > 8.0:
		_mt_step = 3
		if id == "festa":
			police.clear(_my_peer())
		else:
			player.teleport((missions._data["case"] as Node3D).global_position + Vector3(0, 0.3, 0))
	elif _mt_step == 3 and _time > 10.0 and id == "crediti":
		_mt_step = 4
		player.teleport(missions._contact_pos("Zio Franco") + Vector3(1, 0.5, 0))
	if missions.active == "" and _mt_step >= 3 and not _args.has("mt_done"):
		_args["mt_done"] = true
		print("missione finita: completate %s, soldi %d, fama %d, titolo «%s»" % [missions.done, player.money, fame, missions._title.text])


var _bt_step := 0


## Prova della banca n (--banktest=n): atrio, direttore in ostaggio, caveau aperto, due sacchi presi.
func _bank_test() -> void:
	var b: Dictionary = banks.banks[int(_args["banktest"]) % banks.banks.size()]
	var room: Dictionary = b["room"]
	var n: Vector3 = room["n"]
	if _frame % 120 == 0:
		print("prova banca t=%d: soldi %d, stelle %d, caveau %s, sacchi %d, allarme %s, vigilanti %d" % [int(_time), player.money, my_stars(), b["st"]["open"],
			Banks._count_bits(int(b["st"]["bags"])), float(b["st"]["alarm"]) > Time.get_unix_time_from_system(), (b["guards"] as Array).size()])
	if _bt_step == 0 and _time > 2.0:
		_bt_step = 1
		var at: Vector3 = (room["counter_front"] as Vector3) - n * 2.5
		player.teleport(at + Vector3(0, 0.3, 0))
		player.cam_yaw = atan2(n.x, n.z) + PI
		player.cam_pitch = -0.12
		player.set_zoom(4.0)
	elif _bt_step == 1 and _time > 7.0:
		_bt_step = 2
		for ck: Node in b["staff"]:
			if is_instance_valid(ck) and ck.has_meta("director"):
				(ck as Pedestrians.Clerk).rob(_my_peer())
	elif _bt_step == 2 and _time > 15.0:
		_bt_step = 3
		var spot: Vector3 = room["vault_spots"][0]
		player.teleport(spot - n * 0.6 + Vector3(0, 0.3, 0))
		bank_request("bag", [banks.banks.find(b), 0])
		bank_request("bag", [banks.banks.find(b), 1])
		player.cam_yaw = atan2(n.x, n.z) + PI + 0.6


func save_bank() -> void:
	_save_settings()


## E in banca: bancomat, sportello (con l'impiegato al suo posto), sacco del caveau, trapano. true se ha fatto qualcosa.
func _bank_interact() -> bool:
	if banks == null:
		return false
	var p := player.global_position
	if _drill_bank >= 0:
		_drill_bank = -1
		_system("Hai smesso di trapanare.")
		return true
	var bag := banks.bag_near(p)
	if not bag.is_empty():
		bank_request("bag", bag)
		return true
	var atm := banks.atm_near(p)
	if atm >= 0:
		_open_bank_ui("Bancomat · " + String(banks.banks[atm]["room"]["brand"]))
		return true
	var shop := shops.shop_here()
	if not shop.is_empty() and shop["kind"] == "bank":
		_open_bank_ui("Sportello · " + String(shop["name"]).replace("Banca · ", ""))
		return true
	var v := banks.vault_near(p)
	if v >= 0:
		_drill_bank = v
		_drill_t = 0.0
		bank_request("drill_start", [v])
		_system("Trapano acceso sulla porta del caveau: servono %d secondi. È scattato l'allarme!" % int(Banks.DRILL_TIME))
		return true
	return false


func _bank_hint() -> String:
	if banks == null or player.mounted():
		return ""
	var p := player.global_position
	if not banks.bag_near(p).is_empty():
		return "E / croce su: prendi il sacco di contanti"
	if banks.atm_near(p) >= 0:
		return "E / croce su: bancomat (versa e preleva)"
	var shop := shops.shop_here()
	if not shop.is_empty() and shop["kind"] == "bank":
		return "E / croce su: sportello (conto corrente) · punta un'arma all'impiegato per rapinarlo"
	if banks.vault_near(p) >= 0:
		return "E / croce su: trapana la porta del caveau (%d s) · o fallala saltare con la TNT" % int(Banks.DRILL_TIME)
	return ""


func _drill_tick(delta: float) -> void:
	if _drill_bank < 0:
		return
	var door: Vector3 = banks.banks[_drill_bank]["room"]["vault_door"]
	if player.dead or player.mounted() or player.global_position.distance_to(door) > 2.8 or banks.banks[_drill_bank]["st"]["open"]:
		_drill_bank = -1
		return
	_drill_t += delta
	if int(_drill_t * 4.0) % 2 == 0 and _frame % 6 == 0:
		Sfx.play3d("impact", door + Vector3(0, 1.1, 0), -6.0, 0.6)
	if _drill_t >= Banks.DRILL_TIME:
		bank_request("drill_done", [_drill_bank])
		_drill_bank = -1


func _open_bank_ui(where: String) -> void:
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_bank_ui.open(where)


func bank_request(action: String, args: Array) -> void:
	if simulate:
		banks.request(_my_peer(), action, args)
	elif _online_now():
		net_bank_request.rpc_id(1, action, args)


func bank_sync(i: int, st: Array) -> void:
	if _online_now():
		net_bank.rpc(i, st)


@rpc("any_peer", "call_remote", "reliable")
func net_bank_request(action: String, args: Array) -> void:
	if simulate and banks:
		banks.request(multiplayer.get_remote_sender_id(), action, args)


@rpc("authority", "call_remote", "reliable")
func net_bank(i: int, st: Array) -> void:
	if banks:
		banks.set_state(i, st)


# --- Clan e fama criminale -------------------------------------------------------------------------


func online() -> bool:
	return _online_now()


func my_stars() -> int:
	return int(_my_wanted()[0])


func name_of(peer: int) -> String:
	if peer == _my_peer():
		return my_name
	return String(_names.get(peer, ""))


func peer_of(n: String) -> int:
	if n == my_name:
		return _my_peer()
	for id: int in _names:
		if String(_names[id]) == n:
			return id
	return 0


## Fama a un giocatore (su questo PC o su un altro): la tiene il suo PC, che la salva.
func give_fame(peer: int, n: int) -> void:
	if peer == _my_peer():
		add_fame(n)
	elif _online_now() and peer > 0:
		net_fame_add.rpc_id(peer, n)


var _fame_send_t := 0.0
var _fame_dirty := false


func add_fame(n: int) -> void:
	if n == 0:
		return
	var before := Crime.level_index(fame)
	fame = maxi(0, fame + n)
	_fame_dirty = true
	_fame_send_t = 2.0
	if Crime.level_index(fame) > before:
		_system_clan("Fama criminale: ora sei %s (%d)." % [Crime.level_name(fame), fame])
		Sfx.play2d("win", -6.0)
		if fame >= Crime.FOUND_FAME and before < Crime.level_index(Crime.FOUND_FAME):
			_system_clan("Ora puoi fondare un clan tuo (U).")


func _fame_tick(delta: float) -> void:
	if not _fame_dirty:
		return
	_fame_send_t -= delta
	if _fame_send_t <= 0.0:
		_fame_dirty = false
		clan_request("fame", [fame])
		_save_settings()


func _system_clan(text: String) -> void:
	_add_chat_line(text, Color(1.0, 0.62, 0.35))
	print("clan: ", text)


func clan_msg(peer: int, text: String) -> void:
	if peer == _my_peer():
		_system_clan(text)
	elif _online_now() and peer > 0:
		net_clan_msg.rpc_id(peer, text)


func clan_reply(peer: int, ok: bool, text: String, charge: int) -> void:
	if peer == _my_peer():
		_on_clan_reply(ok, text, charge)
	elif _online_now() and peer > 0:
		net_clan_reply.rpc_id(peer, ok, text, charge)


func clan_broadcast(text: String) -> void:
	_system_clan(text)
	if _online_now():
		net_clan_msg.rpc(text)


func clan_sync(json: String) -> void:
	if _online_now():
		net_clan_state.rpc(json)


## Azione di un giocatore sui clan: la decide chi ospita.
func clan_request(action: String, args: Array) -> void:
	if clans == null:
		return
	if simulate:
		clans.request(_my_peer(), action, args)
	elif _online_now():
		net_clan_request.rpc_id(1, action, args)


func _on_clan_reply(ok: bool, text: String, charge: int) -> void:
	if ok and charge > 0 and not creative:
		player.money = maxi(0, player.money - charge)
	if _clan_ui and _clan_ui.visible:
		_clan_ui.show_reply(text)
	else:
		_system_clan(text)
	if ok:
		Sfx.play2d("coin", -8.0)


@rpc("any_peer", "call_remote", "reliable")
func net_clan_request(action: String, args: Array) -> void:
	if simulate and clans:
		clans.request(multiplayer.get_remote_sender_id(), action, args)


@rpc("authority", "call_remote", "reliable")
func net_clan_state(json: String) -> void:
	if clans:
		clans.apply_state(json)


@rpc("any_peer", "call_remote", "reliable")
func net_clan_reply(ok: bool, text: String, charge: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_on_clan_reply(ok, text, charge)


@rpc("any_peer", "call_remote", "reliable")
func net_clan_msg(text: String) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_system_clan(text)


@rpc("any_peer", "call_remote", "reliable")
func net_fame_add(n: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		add_fame(clampi(n, -1000, 1000))


var _ct_step := 0


## Prova dei clan: spaccio nella zona di un clan (rabbia, avviso, squadra), fondazione di un clan, spacciatore
## assunto, rinforzi. Stampa cosa succede.
func _clan_test() -> void:
	var soldiers := clans.get_children().filter(func(n: Node) -> bool: return n is Clans.Soldier)
	if _frame % 120 == 0:
		var roles := {}
		for s: Clans.Soldier in soldiers:
			roles[s.role] = int(roles.get(s.role, 0)) + 1
		var mine := clans.clan_of(my_name)
		print("prova clan t=%d: uomini %s, rabbia %s, mio clan %d, fama %d, soldi %d, spacciatori %d, stelle %d" % [int(_time), roles, clans.rage, mine, fame, player.money, clans.pushers.size(), my_stars()])
	if _ct_step == 0 and _time > 3.0:
		_ct_step = 1
		fame = 800
		player.money = 60000
		player.drugs = {"erba": 20, "cocaina": 10}
		clan_request("fame", [fame])
		var p := player.global_position
		for k in 6:
			clans.on_sale(_my_peer(), "erba", 30, p)  # 6 vendite nella zona di un clan: rabbia 48
	elif _ct_step == 1 and _time > 14.0:
		_ct_step = 2
		clan_request("found", ["I Testardi"])
	elif _ct_step == 2 and _time > 16.0:
		_ct_step = 3
		player.drugs["cocaina"] = 0
		clan_request("hire", ["cocaina", 10])
		_args["wanted"] = "3"
	elif _ct_step == 3 and _time > 18.0:
		_ct_step = 4
		clan_request("backup", [])


var _ct2_step := 0


## Seconda prova dei clan: si entra nel Clan di Prati, lavoro dal boss, spacciatore nella propria zona, uomini
## di un clan rivale uccisi nella loro zona (presa sulla zona che cresce).
func _clan_test2() -> void:
	if _frame % 180 == 0:
		var m := clans.clan_of(my_name)
		var infl: Dictionary = clans.zones[4]["infl"] if clans.zones.size() > 4 else {}
		print("prova2 t=%d: clan %d (%s), soldi %d, fama %d, spacciatori %s, lavoro '%s', presa su Parioli %s, padrone %d" % [int(_time), m, clans.rank_name(my_name), player.money, fame,
			clans.pushers.map(func(p: Dictionary) -> String: return "%s:%d/%d" % [p["drug"], int(p["stock"]), int(p["earned"])]), clans.mission_text(my_name), infl, clans.zone_owner(4)])
	if _ct2_step == 0 and _time > 3.0:
		_ct2_step = 1
		fame = 400
		player.money = 50000
		player.drugs = {"erba": 20}
		clan_request("fame", [fame])
		clan_request("join", [3])
	elif _ct2_step == 1 and _time > 5.0:
		_ct2_step = 2
		clan_request("mission", [])
		var z6: Vector2 = Crime.ZONES[6]["c"]
		player.teleport(Vector3(z6.x, city.surface_at(z6.x, z6.y) + 1.0, z6.y))
	elif _ct2_step == 2 and _time > 7.0:
		_ct2_step = 3
		player.drugs["erba"] = 5
		clan_request("hire", ["erba", 15])
	elif _ct2_step == 3 and _time > 9.0:
		_ct2_step = 4
		# 6 uomini dei Pariolini uccisi a Parioli.
		var z4: Vector2 = Crime.ZONES[4]["c"]
		for k in 6:
			var s: Clans.Soldier = clans._spawn_soldier(2, Vector3(z4.x + k * 2.0, city.surface_at(z4.x, z4.y) + 0.3, z4.y), "squad", null)
			s.take_damage(999.0, _my_peer(), s.global_position)


func _open_clan_ui(boss_clan: int) -> void:
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if boss_clan >= 0:
		_clan_ui.open_boss(boss_clan)
	else:
		_clan_ui.open_panel()


## Sconto dallo spacciatore se è nella zona del tuo clan.
func _drug_discount(pos: Vector3) -> float:
	var mine := clans.clan_of(my_name)
	return 0.8 if mine >= 0 and clans.zone_owner(Crime.zone_of(Vector2(pos.x, pos.z))) == mine else 1.0


var _zone_polys := []


## Zone per la mappa: [poligono, colore del clan che la tiene, nome].
## I boss sulla mappa: quello del tuo clan e quelli che hai già incontrato. Gli altri vanno cercati
## nei loro territori (il pannello dei clan, U, dice in che zona si nascondono).
func _boss_pois() -> Array:
	var out := []
	if clans == null:
		return out
	var mine := clans.clan_of(my_name)
	for c: Dictionary in clans.clans:
		if not c["npc"] and int(c["id"]) != mine:
			continue
		if int(c["id"]) != mine and not _known_bosses.has(String(c["boss"])):
			continue
		out.append([float(c["hq"][0]), float(c["hq"][2]), "Boss · %s (%s)" % [c["boss"], c["name"]], "boss"])
	return out


func _zones_for_map() -> Array:
	if _zone_polys.is_empty():
		for i in Crime.ZONES.size():
			_zone_polys.append(Crime.zone_polygon(i, city.bbox))
	var out := []
	for i in Crime.ZONES.size():
		var owner := clans.zone_owner(i)
		out.append([_zone_polys[i], clans.color_of(owner) if owner >= 0 else Color(0.5, 0.5, 0.5), String(Crime.ZONES[i]["name"])])
	return out


func _update_zone_label() -> void:
	if clans == null or clans.zones.is_empty():
		return
	var z := Crime.zone_of(Vector2(player.global_position.x, player.global_position.z))
	var owner := clans.zone_owner(z)
	var c := clans.clan(owner)
	var t := String(Crime.ZONES[z]["name"]) + (" · territorio di " + String(c["name"]) if not c.is_empty() else " · terra di nessuno")
	if owner >= 0 and clans.clan_of(my_name) == owner:
		t += " (il tuo clan)"
	elif owner >= 0 and clans.hostile(owner, my_name):
		t += " · TI CERCANO"
	_zone_label.text = t
	_zone_label.modulate = clans.color_of(owner).lightened(0.45) if owner >= 0 else Color(0.85, 0.85, 0.85)


## Le etichette sopra gli altri giocatori dicono anche il loro clan.
func _on_clans_changed() -> void:
	for id: int in _remote:
		var n := String(_names.get(id, ""))
		var c := clans.clan(clans.clan_of(n))
		(_remote[id] as Player).set_display_name(n + ("  [%s]" % c["name"] if not c.is_empty() else ""))


# --- Rotella delle armi -----------------------------------------------------------------------


func _update_wheel() -> void:
	if _wheel == null or player == null or _wheel_down < 0:
		return
	var held := Time.get_ticks_msec() - _wheel_down
	if Input.is_action_pressed("next_weapon"):
		if held > 180 and not _wheel.visible and not player.dead:
			_wheel.open()
			player.input_enabled = false
			if not _online_now():
				Engine.time_scale = 0.25  # da soli il tempo rallenta mentre si sceglie
		return
	# Tasto rilasciato.
	_wheel_down = -1
	if _wheel.visible:
		_wheel_pick(_wheel.close())
	else:
		player.next_weapon()


func _wheel_pick(id: String) -> void:
	_wheel_down = -1
	Engine.time_scale = 1.0
	if not (hud and hud.shop_open()):
		player.input_enabled = true
	player._cool = 0.3  # il clic che conferma la scelta non deve anche sparare
	if id != "" and player.owned_weapons().has(id):
		player.weapon = id
		_system("In mano: " + String(Weapons.info(id)["name"]) + (" (B per farla saltare)" if id == "tnt" else ""))


## Prova: --punchtest. Un passante tosto davanti al giocatore: tre pugni (barcolla, poi a terra), si rialza e
## risponde; poi una mazzata. Stampa lo stato; con --capture si vede la scena.
var _pt_ped: Pedestrians.Pedestrian
var _pt_step := 0
func _punch_test() -> void:
	var t := _time
	if _pt_step == 0 and t > 2.0:
		_pt_step = 1
		var front := player.global_position + Vector3(1.6, 0, -2.2)
		_pt_ped = pedestrians.spawn_at(front)
		_pt_ped.fighter = true
		player.cam_yaw = 0.0
		print("pugni: passante creato ", _pt_ped != null, " t=", t)
	if _pt_ped == null or not is_instance_valid(_pt_ped):
		return
	var hit := func(dmg: float) -> void:
		_pt_ped.take_damage(dmg, _my_peer(), _pt_ped.global_position + Vector3(0, 1.4, 0))
	for k: Array in [[1, 2.6, 12.0], [2, 3.4, 12.0], [3, 4.2, 12.0], [4, 9.5, 30.0]]:
		if _pt_step == k[0] and t > k[1]:
			_pt_step += 1
			hit.call(k[2])
	# --pshots=cartella: fotografa i momenti salienti (barcolla, a terra, si rialza, risponde).
	if _args.has("pshots"):
		for m: Array in [["1_barcolla", 2.8], ["2_testa", 3.55], ["3_a_terra", 4.9], ["4_rialzo", 7.3], ["5_risponde", 9.3]]:
			if t > float(m[1]) and not _args.has("ps_" + String(m[0])):
				_args["ps_" + String(m[0])] = true
				get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_args["pshots"], m[0]])
	if _frame % 15 == 0 and _pt_step >= 2:
		print("pugni t=%.1f: vita %d, stun %.1f, a terra %.1f, rialzo %.1f, risponde %s, anim %s, vita giocatore %d" % [
			t, int(_pt_ped.health), _pt_ped._r_stun, _pt_ped._r_down, _pt_ped._r_getup, _pt_ped._r_foe > 0, _pt_ped.net_anim, int(player.health)])


## Prova: --furtotest (auto del traffico) o --furtotest=bus. Il giocatore accanto alla portiera preme F; con
## --pshots=cartella fotografa le fasi (va alla portiera, apre, tira fuori il guidatore, sale, richiude).
var _jt_t0 := -1.0
func _steal_test() -> void:
	if _jt_t0 < 0.0 and _time > 4.0:
		var want_bus := String(_args["furtotest"]) == "bus"
		var best: Traffic.TrafficCar = null
		for n: Node in traffic.get_children():
			var tc := n as Traffic.TrafficCar
			if tc and tc.is_bus == want_bus and not tc.destroyed and (best == null or
					tc.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
				best = tc
		if best == null:
			return
		var xf := best.global_transform
		var at := xf * (Vector3(-2.6, 0, Bus.SIZE.z * 0.5 - 1.6) if want_bus else Vector3(2.6, 0, -0.6))
		player.teleport(Vector3(at.x, city.surface_at(at.x, at.z) + 0.2, at.z))
		player.cam_yaw = best.global_rotation.y + (-PI * 0.5 if want_bus else PI * 0.5) + 0.5
		player.cam_pitch = -0.25
		_jt_t0 = _time
		_toggle_car()
		print("furto: avviato su %s, sequenza %s" % ["autobus" if want_bus else "auto", _jack_run != null])
	if _jt_t0 < 0.0:
		return
	var dt := _time - _jt_t0
	if _args.has("pshots"):
		for m: Array in [["1_va", 0.25], ["2_apre", 0.65], ["3_tira", 1.1], ["4_sale", 1.6], ["5_chiude", 1.95], ["6_dentro", 3.0]]:
			if dt > float(m[1]) and not _args.has("js_" + String(m[0])):
				_args["js_" + String(m[0])] = true
				get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_args["pshots"], m[0]])
	if dt > 3.2 and dt < 7.0 and player.vehicle:
		Input.action_press("move_forward")
	elif dt >= 7.0:
		Input.action_release("move_forward")
	if dt > 6.8 and not _args.has("jt_speed"):
		_args["jt_speed"] = true
		print("furto: dopo 3,5 s di gas %.0f km/h" % player.vehicle.speed_kmh())
		if _args.has("pshots"):
			get_viewport().get_texture().get_image().save_png("%s/7_guida.png" % _args["pshots"])
	if dt > 3.2 and not _args.has("jt_done"):
		_args["jt_done"] = true
		print("furto: al volante %s (%s), scena finita %s" % [player.vehicle != null, player.vehicle.model if player.vehicle else "-", not is_instance_valid(_jack_run)])
