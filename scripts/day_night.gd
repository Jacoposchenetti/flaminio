class_name DayNight
extends Node

## Giorno e notte: una giornata intera dura CYCLE secondi (45 minuti, 1 ora del gioco ≈ 1 minuto e 52 secondi).
## Muove il sole (da est a sud a ovest, alto come a Roma in primavera) e di notte la luna, cambia i colori del
## cielo, della foschia e della luce rimbalzata; al tramonto accende lampioni, finestre e vetrine (global uniform
## "night" negli shader). Le luci vere stanno solo sui LIGHTS lampioni più vicini alla camera: gli altri hanno il
## vetro luminoso. L'ora la decide chi ospita e la manda agli altri (main.gd, net_clock).

const CYCLE := 2700.0
const LIGHTS := 22
const SUN_MAX := 62.0  # gradi sull'orizzonte a mezzogiorno

static var current: DayNight  # per chi deve sapere se è notte (fari, faro dell'elicottero)

var hour := 15.5
var frozen := false  # prove: --hour=22 ferma l'orologio
var night := 0.0  # 0 giorno pieno, 1 notte fonda
var lights_on := 0.0  # lampioni accesi (dal tramonto all'alba)
var sun: DirectionalLight3D
var env: Environment
var sky: ShaderMaterial  # shaders/sky.gdshader
var _flare: ColorRect  # riflessi del sole sulla lente (shaders/lens_flare.gdshader)
var _flare_vis := 0.0  # 0 sole coperto, 1 sole libero (si sfuma)
var _flare_t := 0.0
var _clouds := Vector2(0.0, 0.0)
var _sky_t := 0.0
var _apply_sky := true
var city: CityBuilder
var _pool: Array[OmniLight3D] = []
var _lamp_t := 0.0


func setup(s: DirectionalLight3D, e: Environment, c: CityBuilder) -> void:
	sun = s
	env = e
	sky = e.sky.sky_material as ShaderMaterial
	if DisplayServer.get_name() != "headless":
		var layer := CanvasLayer.new()
		layer.layer = -1  # sopra la scena, sotto l'HUD
		add_child(layer)
		_flare = ColorRect.new()
		_flare.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flare.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fm := ShaderMaterial.new()
		fm.shader = load("res://shaders/lens_flare.gdshader")
		_flare.material = fm
		layer.add_child(_flare)
	city = c
	current = self
	for i in LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.76, 0.48)
		l.light_energy = 0.0
		l.omni_range = 19.0
		l.omni_attenuation = 1.3
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_pool.append(l)
	_apply()


## Ora del gioco come testo, per l'HUD.
func clock_text() -> String:
	var m := int(hour * 60.0) % (24 * 60)
	return "%02d:%02d" % [m / 60, m % 60]


func is_night() -> bool:
	return lights_on > 0.5


func _process(delta: float) -> void:
	if not frozen:
		hour = fposmod(hour + delta * 24.0 / CYCLE, 24.0)
	_clouds += Vector2(0.0011, 0.0004) * delta
	_sky_t -= delta
	if _sky_t <= 0.0:
		# Il cielo (e la luce che manda sulla scena) si ricalcola solo due volte al secondo: cambia piano.
		_sky_t = 0.5
		sky.set_shader_parameter("cloud_offset", _clouds)
		_apply_sky = true
	_apply()
	_apply_sky = false
	_update_flare(delta)
	_lamp_t -= delta
	if _lamp_t <= 0.0:
		_lamp_t = 0.4
		_place_lamps()


func _apply() -> void:
	# Sole: sorge alle 6 a est, a mezzogiorno è a sud, tramonta alle 18 a ovest.
	var day_t := (hour - 6.0) / 12.0
	var elev := sin(PI * day_t) * SUN_MAX  # negativo di notte
	var az := 90.0 + 180.0 * clampf(day_t, 0.0, 1.0)
	var daylight := smoothstep(-6.0, 6.0, elev)  # crepuscolo civile
	night = 1.0 - daylight
	lights_on = 1.0 - smoothstep(-2.0, 5.0, elev)
	var low := 1.0 - clampf(absf(elev) / 14.0, 0.0, 1.0)  # vicino all'orizzonte: tramonto/alba
	if elev > -3.0:
		_point(sun, az, maxf(elev, 1.5))
		var warm := Color(1.0, 0.52, 0.28).lerp(Color(1.0, 0.9, 0.76), smoothstep(2.0, 24.0, elev))
		sun.light_color = warm
		sun.light_energy = 1.6 * smoothstep(-3.0, 8.0, elev)
		sun.light_angular_distance = 0.6
	else:
		# Luna: dalla parte opposta, più bassa, luce fredda e debole (fa ancora ombra).
		var moon_t := fposmod(hour - 18.0, 24.0) / 12.0
		_point(sun, 90.0 + 180.0 * clampf(moon_t, 0.0, 1.0), 18.0 + sin(PI * clampf(moon_t, 0.0, 1.0)) * 30.0)
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun.light_energy = 0.32 * smoothstep(-3.0, -10.0, elev)
		sun.light_angular_distance = 0.3
	# Cielo: azzurro di giorno, arancio e viola al tramonto, blu notte.
	var top_day := Color(0.22, 0.42, 0.75)
	var hor_day := Color(0.72, 0.76, 0.8)
	var top_night := Color(0.02, 0.03, 0.085)
	var hor_night := Color(0.1, 0.1, 0.16)  # bagliore della città
	var top := top_night.lerp(top_day, daylight)
	var hor := hor_night.lerp(hor_day, daylight)
	hor = hor.lerp(Color(0.96, 0.52, 0.3), low * 0.75 * smoothstep(-8.0, 0.0, elev))
	top = top.lerp(Color(0.24, 0.26, 0.5), low * 0.45 * smoothstep(-8.0, 0.0, elev))
	var dusk := low * smoothstep(-8.0, 1.0, elev)
	if not _apply_sky:
		RenderingServer.global_shader_parameter_set("night", lights_on)
		if city and city.lamp_glass:
			city.lamp_glass.emission_energy_multiplier = lerpf(0.2, 7.0, lights_on)
		return
	sky.set_shader_parameter("top_color", top)
	sky.set_shader_parameter("horizon_color", hor)
	sky.set_shader_parameter("ground_color", Color(0.32, 0.31, 0.3).lerp(Color(0.03, 0.035, 0.05), night))
	sky.set_shader_parameter("glow_color", Color(1.0, 0.88, 0.7).lerp(Color(1.0, 0.55, 0.3), dusk))
	sky.set_shader_parameter("daylight", daylight)
	sky.set_shader_parameter("sunset", dusk)
	sky.set_shader_parameter("energy", lerpf(0.45, 1.0, daylight))
	env.ambient_light_energy = lerpf(0.45, 0.7, daylight)
	env.ambient_light_color = Color(0.3, 0.36, 0.55).lerp(Color(0.66, 0.62, 0.56), daylight).lerp(Color(0.8, 0.55, 0.45), dusk * 0.5)
	env.fog_light_color = Color(0.06, 0.07, 0.12).lerp(Color(0.74, 0.78, 0.86), daylight).lerp(Color(0.98, 0.62, 0.42), dusk * 0.55)
	env.tonemap_exposure = lerpf(1.6, 0.95, daylight)
	env.volumetric_fog_albedo = Color(0.3, 0.32, 0.4).lerp(Color(0.85, 0.87, 0.9), daylight)
	RenderingServer.global_shader_parameter_set("night", lights_on)
	if city and city.lamp_glass:
		city.lamp_glass.emission_energy_multiplier = lerpf(0.2, 7.0, lights_on)


## Orienta la luce come se venisse dal punto del cielo ad azimut az (da nord, in senso orario) e altezza elev.
## Nel gioco il nord è verso -Z e l'est verso +X.
func _point(l: DirectionalLight3D, az: float, elev: float) -> void:
	var a := deg_to_rad(az)
	var e := deg_to_rad(elev)
	var from := Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e))
	l.global_basis = Basis.looking_at(-from, Vector3.UP if absf(from.y) < 0.99 else Vector3.FORWARD)


## Le luci vere vanno sui lampioni più vicini alla camera (gli altri hanno solo il vetro acceso).
func _place_lamps() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or city == null:
		return
	if lights_on <= 0.01:
		for l in _pool:
			l.visible = false
		return
	var at := cam.global_position
	var best: Array = []  # [distanza², indice], tenuti ordinati
	var pts := city.lamp_points
	for i in pts.size():
		var d := at.distance_squared_to(pts[i])
		if d > 160000.0:
			continue
		if best.size() < LIGHTS or d < float(best[-1][0]):
			best.append([d, i])
			best.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
			if best.size() > LIGHTS:
				best.pop_back()
	for k in _pool.size():
		var l := _pool[k]
		if k < best.size():
			l.visible = true
			l.global_position = pts[int(best[k][1])]
			l.light_energy = 2.4 * lights_on
		else:
			l.visible = false


## Riflessi sulla lente: dove sta il sole sullo schermo e se un palazzo o un albero lo copre.
func _update_flare(delta: float) -> void:
	if _flare == null:
		return
	var cam := get_viewport().get_camera_3d()
	var mat := _flare.material as ShaderMaterial
	var toward := sun.global_basis.z  # la luce va verso -Z: il sole sta da +Z
	var day := 1.0 - night
	if cam == null or day < 0.05 or toward.y < -0.02:
		mat.set_shader_parameter("strength", 0.0)
		return
	var far := cam.global_position + toward * 4000.0
	var vis := 0.0
	if not cam.is_position_behind(far):
		var sp := cam.unproject_position(far)
		var vs := get_viewport().get_visible_rect().size
		mat.set_shader_parameter("sun_pos", Vector2(sp.x, sp.y))
		mat.set_shader_parameter("screen", vs)
		# Fuori dallo schermo si spegne piano piano.
		var margin := maxf(maxf(-sp.x, sp.x - vs.x), maxf(-sp.y, sp.y - vs.y))
		vis = 1.0 - clampf(margin / (vs.x * 0.25), 0.0, 1.0)
		_flare_t -= delta
		if _flare_t <= 0.0:
			_flare_t = 0.1
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + toward * 1500.0)
			q.collision_mask = 1 | 2
			var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
			_flare.set_meta("blocked", not hit.is_empty())
		if _flare.get_meta("blocked", false):
			vis = 0.0
	_flare_vis = lerpf(_flare_vis, vis, 1.0 - exp(-delta * 8.0))
	mat.set_shader_parameter("strength", _flare_vis * day * 0.9)
	mat.set_shader_parameter("tint", sun.light_color)
