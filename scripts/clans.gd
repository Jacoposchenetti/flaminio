class_name Clans
extends Node3D

## Clan della malavita: territori, boss, picciotti, spacciatori al soldo, guerre e indagini.
##
## Chi ospita (o chi gioca da solo) tiene lo stato vero e lo salva in user://clans.json; agli altri arriva una copia
## (apply_state) ogni volta che cambia. I giocatori sono riconosciuti per nome (resta tra una partita e l'altra).
## Le richieste dei giocatori (entrare, fondare, assumere...) arrivano a chi ospita con request(); le risposte
## tornano con world.clan_reply().
##
## Dinamiche:
## - Ogni zona del quartiere ha un clan padrone. Spacciare nella zona di un clan di cui non fai parte lo fa
##   arrabbiare: prima ti avvisano, poi mandano i picciotti armati. Colpire i suoi uomini peggiora tutto.
## - Si entra in un clan parlando con il boss (condizioni: fama, quota, prova) o, per i clan dei giocatori,
##   chiedendo al loro capo. Da membro: rinforzi contro la polizia (da solo nel tuo territorio con 3 stelle, o
##   col tasto N), corruzione (−1 stella pagando), lavori dal boss, spacciatori al tuo soldo.
## - Con fama FOUND_FAME e FOUND_COST euro si fonda un clan: si conquistano zone uccidendo gli uomini di chi le
##   tiene e spacciando lì; le zone rendono ogni minuto (spaccio, estorsioni, prostituzione).
## - Rischi: gli spacciatori possono essere arrestati e fare il tuo nome (2 stelle); l'indagine della polizia sul
##   clan sale con arresti e omicidi e a 80 scatta il blitz della DDA (stelle a tutti, sequestro della cassa);
##   chi ti toglie una zona o con cui sei in guerra ti dà la caccia nel suo territorio.

signal changed

const SAVE_PATH := "user://clans.json"
const RAGE_WARN := 16.0
const RAGE_HUNT := 40.0
const WAR := -50
const PUSHER_TICK := 15.0
const PUSHER_CUT := 0.35  # quanto si tiene lo spacciatore
const PIZZO := 0.15  # quota al clan sulle vendite nel suo territorio
const RANKS := [[0, "Picciotto"], [350, "Soldato"], [700, "Capo"], [1200, "Braccio destro"]]
## Sicari: affiliati dei clan che si pagano per far fuori un giocatore. Il prezzo sale con la fama del bersaglio
## e con quella del sicario (più bravo: più vita, mira migliore, arma più pesante).
const HITMAN_NAMES := ["Er Freddo", "Lo Svizzero", "Mano Lesta", "Occhio de Falco", "Er Bisturi", "La Vedova", "Er Silenzio", "Er Tacchino", "Er Nebbia", "Lama"]
const HIT_TIME := 300.0
const PALETTE := [Color(0.1, 0.75, 0.6), Color(0.9, 0.85, 0.15), Color(0.95, 0.35, 0.6), Color(0.55, 0.85, 0.2), Color(0.3, 0.9, 1.0), Color(1.0, 1.0, 1.0)]

var world: Node  # main.gd
var city: CityBuilder
var combat: Combat
var police: Police
var pedestrians: Pedestrians

# Stato condiviso.
var clans: Array = []  # {id, name, color, npc, boss, hq, members {nome: true}, treasury, heat, rel {id: v}, fame, fee, task, n, look, requests [nomi]}
var zones: Array = []  # {owner, infl {id: v}}
var pushers: Array = []  # {id, owner, clan, zone, drug, stock, earned, pos}
var fame := {}  # nome -> fama (la manda ogni giocatore)
var rage := {}  # "clan|nome" -> rabbia
var tasks := {}  # "clan|nome" -> progresso della prova d'ingresso
var missions := {}  # nome -> {clan, kind, target, n, done, reward, fame, pos}
var bank := {}  # nome -> soldi guadagnati mentre non c'era (glieli si danno quando torna)

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _push_t := 0.0
var _income_t := 0.0
var _save_t := 0.0
var _npc_war_t := 0.0
var _dirty := true
var _send_t := 0.0
var _squad_cd := {}  # "clan|nome" -> secondi prima della prossima squadra
var _backup_cd := {}  # nome -> secondi
var _corrupt_cd := {}
var _next_id := 100
var contracts: Array = []  # {client, target, clan, hi, until, nid}
var _next_pusher := 1


func setup(w: Node, c: CityBuilder, cb: Combat, pol: Police, peds: Pedestrians) -> void:
	world = w
	city = c
	combat = cb
	police = pol
	pedestrians = peds
	_rng.randomize()
	_init_default()
	if world.simulate:
		_load()


## Stato iniziale: i clan storici del quartiere con le loro zone.
func _init_default() -> void:
	clans.clear()
	zones.clear()
	for i in Crime.ZONES.size():
		zones.append({"owner": -1, "infl": {}})
	for i in Crime.NPC_CLANS.size():
		var d: Dictionary = Crime.NPC_CLANS[i]
		var hq := _hq_for(int(d["zones"][0]))
		clans.append({"id": i, "name": d["name"], "color": (d["color"] as Color).to_html(false), "npc": true,
			"boss": d["boss"], "hq": [hq.x, hq.y, hq.z], "members": {}, "treasury": 50000, "heat": 0.0, "rel": {},
			"fame": d["fame"], "fee": d["fee"], "task": d["task"], "n": d["n"], "look": d["look"], "requests": [],
			"hitmen": _roster(i * 3, [380, 650, 950][i % 3], 3)})
		for z: int in d["zones"]:
			zones[z]["owner"] = i
			zones[z]["infl"] = {str(i): 100.0}
	for r: Array in Crime.NPC_RELATIONS:
		_set_rel(int(r[0]), int(r[1]), int(r[2]))


func _roster(seed_i: int, top: int, n: int) -> Array:
	var out := []
	for k in n:
		out.append({"name": HITMAN_NAMES[(seed_i + k * 3) % HITMAN_NAMES.size()], "fame": int(top * (1.0 - k * 0.3)), "kills": 0, "busy": false})
	return out


## Prezzo di un tentativo d'omicidio: cresce con la fama del bersaglio e con quella del sicario.
static func hit_price(hitman_fame: int, target_fame: int) -> int:
	return int(round((3000.0 + target_fame * 12.0) * (1.0 + hitman_fame / 400.0) / 100.0)) * 100


## Quartier generale: il punto di vialetto più vicino al centro della zona (fuori dalle banchine).
func _hq_for(zone: int) -> Vector3:
	var c: Vector2 = Crime.ZONES[zone]["c"]
	var best := c
	var best_d := INF
	for r: Dictionary in city.data["roads"]:
		if r["k"] != "foot" or int(r["b"]) == 1:
			continue
		var pts := city._pts(r["p"])
		for p in pts:
			if city.carve_at(p.x, p.y) < -0.3:
				continue
			var d := p.distance_to(c)
			if d < best_d:
				best_d = d
				best = p
	return Vector3(best.x, city.surface_at(best.x, best.y), best.y)


# --- Domande sullo stato (valgono su tutti i PC) ----------------------------------------------------


func clan(id: int) -> Dictionary:
	for c: Dictionary in clans:
		if int(c["id"]) == id:
			return c
	return {}


func clan_of(player_name: String) -> int:
	for c: Dictionary in clans:
		if (c["members"] as Dictionary).has(player_name):
			return int(c["id"])
	return -1


func color_of(id: int) -> Color:
	var c := clan(id)
	return Color.html(String(c["color"])) if not c.is_empty() else Color(0.6, 0.6, 0.6)


func zone_owner(z: int) -> int:
	return int(zones[z]["owner"]) if z >= 0 and z < zones.size() else -1


func rel(a: int, b: int) -> int:
	if a == b:
		return 100
	var c := clan(a)
	if c.is_empty():
		return 0
	return int((c["rel"] as Dictionary).get(str(b), 0))


func _set_rel(a: int, b: int, v: int) -> void:
	var ca := clan(a)
	var cb := clan(b)
	if ca.is_empty() or cb.is_empty():
		return
	v = clampi(v, -100, 100)
	ca["rel"][str(b)] = v
	cb["rel"][str(a)] = v


func rank_name(player_name: String) -> String:
	var f := int(fame.get(player_name, 0))
	var c := clan(clan_of(player_name))
	if not c.is_empty() and String(c["boss"]) == player_name:
		return "Boss"
	var out := "Picciotto"
	for r: Array in RANKS:
		if f >= int(r[0]):
			out = r[1]
	return out


func rank_index(player_name: String) -> int:
	var f := int(fame.get(player_name, 0))
	var i := 0
	for k in RANKS.size():
		if f >= int(RANKS[k][0]):
			i = k
	return i


func is_boss(player_name: String) -> bool:
	var c := clan(clan_of(player_name))
	return not c.is_empty() and not c["npc"] and String(c["boss"]) == player_name


## Gli uomini del clan id attaccano quel giocatore?
func hostile(id: int, player_name: String) -> bool:
	var mine := clan_of(player_name)
	if mine == id:
		return false
	if float(rage.get("%d|%s" % [id, player_name], 0.0)) >= RAGE_HUNT:
		return true
	return mine >= 0 and rel(id, mine) <= WAR


## Creativa: i clan dimenticano quello che hai fatto, le squadre mandate a cercarti se ne vanno e le
## guerre col tuo clan diventano tregue. Restituisce quanti clan ce l'avevano con te.
func make_peace(player_name: String) -> int:
	var n := 0
	var mine := clan_of(player_name)
	for c: Dictionary in clans:
		var id := int(c["id"])
		if id == mine:
			continue
		var key := "%d|%s" % [id, player_name]
		var angry := float(rage.get(key, 0.0)) >= RAGE_WARN
		rage.erase(key)
		if mine >= 0 and rel(id, mine) <= WAR:
			_set_rel(id, mine, -10)
			angry = true
		if angry:
			n += 1
	var p: Node = world.player
	for s: Node in get_children():
		if s is Soldier and (s as Soldier).role == "squad" and (s as Soldier).target == p:
			s.queue_free()
	_mark()
	return n


## Cosa pensano di te i clan: [testo, colore] per ognuno che ti cerca o ti tiene d'occhio.
func threats(player_name: String) -> Array:
	var out := []
	var mine := clan_of(player_name)
	for c: Dictionary in clans:
		var id := int(c["id"])
		if id == mine:
			continue
		var r := float(rage.get("%d|%s" % [id, player_name], 0.0))
		var col := color_of(id).lightened(0.25)
		if r >= RAGE_HUNT:
			var mins := ceili((r - RAGE_HUNT) * 6.0 / 60.0)
			var where := "ovunque" if r >= 150.0 else "nel suo territorio"
			out.append(["☠ %s ti dà la caccia %s · ancora ~%d min" % [c["name"], where, maxi(mins, 1)], col])
		elif mine >= 0 and rel(id, mine) <= WAR:
			out.append(["⚔ %s è in guerra col tuo clan" % c["name"], col])
		elif r >= RAGE_WARN:
			out.append(["⚠ %s ti tiene d'occhio" % c["name"], col.darkened(0.1)])
	return out


func task_progress(id: int, player_name: String) -> int:
	return int(tasks.get("%d|%s" % [id, player_name], 0))


func pushers_of(player_name: String) -> Array:
	return pushers.filter(func(p: Dictionary) -> bool: return String(p["owner"]) == player_name)


# --- Rete: copia dello stato ------------------------------------------------------------------------


func state_json() -> String:
	return JSON.stringify({"clans": clans, "zones": zones, "pushers": pushers, "fame": fame, "rage": rage,
		"tasks": tasks, "missions": missions})


func apply_state(text: String) -> void:
	var d: Variant = JSON.parse_string(text)
	if not d is Dictionary:
		return
	clans = d.get("clans", [])
	zones = d.get("zones", [])
	pushers = d.get("pushers", [])
	fame = d.get("fame", {})
	rage = d.get("rage", {})
	tasks = d.get("tasks", {})
	missions = d.get("missions", {})
	for c: Dictionary in clans:
		c["id"] = int(c["id"])
	for z: Dictionary in zones:
		z["owner"] = int(z["owner"])
	changed.emit()


func _mark() -> void:
	_dirty = true


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not d is Dictionary:
		return
	if (d.get("clans", []) as Array).size() >= Crime.NPC_CLANS.size():
		clans = d["clans"]
		zones = d.get("zones", zones)
		for c: Dictionary in clans:
			c["id"] = int(c["id"])
			_next_id = maxi(_next_id, int(c["id"]) + 1)
		for z: Dictionary in zones:
			z["owner"] = int(z["owner"])
	pushers = d.get("pushers", [])
	for p: Dictionary in pushers:
		_next_pusher = maxi(_next_pusher, int(p["id"]) + 1)
	fame = d.get("fame", {})
	rage = d.get("rage", {})
	tasks = d.get("tasks", {})
	bank = d.get("bank", {})
	missions = {}  # i lavori non sopravvivono a una partita
	for c: Dictionary in clans:
		if not c.has("hitmen"):
			c["hitmen"] = _roster(int(c["id"]), 380 if c["npc"] else 180, 3 if c["npc"] else 2)
		for h: Dictionary in c["hitmen"]:
			h["busy"] = false


func save() -> void:
	if world == null or not world.simulate or world.get("_args").has("autoquit"):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"clans": clans, "zones": zones, "pushers": pushers, "fame": fame, "rage": rage,
			"tasks": tasks, "bank": bank}))


# --- Chi ospita: eventi -----------------------------------------------------------------------------


## Un reato (dalla polizia di chi ospita): fama al giocatore, indagine sul suo clan.
func on_crime(kind: String, pos: Vector3, peer: int) -> void:
	if not world.simulate or peer <= 0:
		return
	var who: String = world.name_of(peer)
	if who == "":
		return
	var f: int = Crime.FAME.get(kind, 0)
	if f > 0:
		world.give_fame(peer, f)
	var mine := clan_of(who)
	if mine >= 0:
		var heat := {"kill": 2.0, "cop_kill": 8.0, "robbery": 3.0, "rocket": 2.0}.get(kind, 0.0) as float
		if heat > 0.0:
			_add_heat(mine, heat)
	# Rapina nella zona di un clan: è roba sua (estorsioni), si arrabbia.
	if kind == "robbery":
		var z := Crime.zone_of(Vector2(pos.x, pos.z))
		var owner := zone_owner(z)
		if owner >= 0 and owner != mine:
			_add_rage(owner, who, 12.0, peer)
		_mission_event(who, "racket", z)


## Una dose venduta da un giocatore in pos (il pizzo è già stato tolto dal suo incasso).
func on_sale(peer: int, drug: String, price: int, pos: Vector3) -> void:
	var who: String = world.name_of(peer)
	var z := Crime.zone_of(Vector2(pos.x, pos.z))
	var owner := zone_owner(z)
	var mine := clan_of(who)
	world.give_fame(peer, 1)
	if owner >= 0:
		if owner == mine:
			var c := clan(owner)
			c["treasury"] = int(c["treasury"]) + int(price * PIZZO)
		elif mine < 0 or rel(owner, mine) < 50:
			_add_rage(owner, who, 8.0, peer)
	if mine >= 0 and owner != mine:
		_influence(z, mine, 0.6)
	# Prova d'ingresso "vendi n dosi nel nostro territorio".
	if owner >= 0 and String(clan(owner).get("task", "")) == "sell" and owner != mine:
		_task_add(owner, who, 1)
	_mission_event(who, "deal", z)
	_mark()


## Un uomo di un clan è stato ucciso (from_peer: il giocatore che l'ha ucciso, -1 se nessuno).
func on_soldier_killed(s: Soldier, from_peer: int) -> void:
	if from_peer <= 0:
		return
	var who: String = world.name_of(from_peer)
	var mine := clan_of(who)
	var z := Crime.zone_of(Vector2(s.global_position.x, s.global_position.z))
	world.give_fame(from_peer, Crime.FAME["soldier_kill"])
	_add_rage(s.clan_id, who, 50.0, from_peer)
	if mine >= 0 and mine != s.clan_id:
		_set_rel(mine, s.clan_id, rel(mine, s.clan_id) - 12)
		if zone_owner(z) == s.clan_id:
			_influence(z, mine, 9.0)
		_add_heat(mine, 2.0)
	# Prove "uccidi n uomini di altri clan": valgono per tutti i clan con quella prova, tranne quello del morto.
	for c: Dictionary in clans:
		if c["npc"] and String(c["task"]) == "kill" and int(c["id"]) != s.clan_id and int(c["id"]) != mine:
			_task_add(int(c["id"]), who, 1)
	if s.role == "hitman":
		var k := _contract_of_soldier(s)
		if not k.is_empty():
			_end_contract(k, false, "il sicario è stato ucciso.")
	if s.role == "boss":
		world.clan_broadcast("Radio malavita: %s ha fatto fuori %s, il boss di %s!" % [who, s.display, clan(s.clan_id)["name"]])
		_add_rage(s.clan_id, who, 200.0, from_peer)
	_mission_event(who, "hit", s.clan_id)
	_mark()


func _task_add(id: int, who: String, n: int) -> void:
	var key := "%d|%s" % [id, who]
	tasks[key] = int(tasks.get(key, 0)) + n


func _add_rage(id: int, who: String, amount: float, peer: int) -> void:
	var key := "%d|%s" % [id, who]
	var before := float(rage.get(key, 0.0))
	var after := minf(before + amount, 250.0)
	rage[key] = after
	var c := clan(id)
	if before < RAGE_WARN and after >= RAGE_WARN and after < RAGE_HUNT:
		world.clan_msg(peer, "Un ragazzo ti si avvicina: «Questa è zona di %s. Qui non si lavora senza permesso. Ultimo avviso.»" % c["name"])
	elif before < RAGE_HUNT and after >= RAGE_HUNT:
		world.clan_msg(peer, "%s ti ha messo nel mirino: i suoi uomini ti cercano nel loro territorio." % c["name"])
	_mark()


func _add_heat(id: int, amount: float) -> void:
	var c := clan(id)
	if c.is_empty() or c["npc"]:
		return
	c["heat"] = minf(100.0, float(c["heat"]) + amount)
	if float(c["heat"]) >= 80.0:
		_blitz(id)
	_mark()


## Blitz della DDA contro un clan di giocatori: stelle a chi è in partita, cassa sequestrata, spacciatori arrestati.
func _blitz(id: int) -> void:
	var c := clan(id)
	c["heat"] = 30.0
	var seized := int(int(c["treasury"]) * 0.4)
	c["treasury"] = int(c["treasury"]) - seized
	pushers = pushers.filter(func(p: Dictionary) -> bool: return int(p["clan"]) != id)
	world.clan_broadcast("Blitz della DDA contro %s: sequestrati € %d, arrestati gli spacciatori. Tutti gli affiliati sono ricercati!" % [c["name"], seized])
	var ps: Dictionary = world.players()
	for peer: int in ps:
		if clan_of(world.name_of(peer)) == id:
			police.report("blitz", (ps[peer] as Node3D).global_position, peer)
	_mark()


func _influence(z: int, id: int, amount: float) -> void:
	var infl: Dictionary = zones[z]["infl"]
	var owner := zone_owner(z)
	infl[str(id)] = clampf(float(infl.get(str(id), 0.0)) + amount, 0.0, 100.0)
	if owner >= 0 and owner != id:
		infl[str(owner)] = clampf(float(infl.get(str(owner), 0.0)) - amount * 0.8, 0.0, 100.0)
		if float(infl[str(id)]) >= 50.0 and float(infl[str(id)]) > float(infl.get(str(owner), 0.0)):
			_take_zone(z, id)


func _take_zone(z: int, id: int) -> void:
	var old := zone_owner(z)
	zones[z]["owner"] = id
	var c := clan(id)
	world.clan_broadcast("Radio malavita: %s ha preso il controllo di %s%s!" % [c["name"], Crime.ZONES[z]["name"],
		(" togliendolo a " + String(clan(old)["name"])) if old >= 0 else ""])
	if old >= 0:
		_set_rel(id, old, rel(id, old) - 40)
	if not c["npc"]:
		var boss_peer: int = world.peer_of(String(c["boss"]))
		if boss_peer > 0:
			world.give_fame(boss_peer, Crime.FAME["capture"])
		_add_heat(id, 10.0)
	_mark()


# --- Chi ospita: richieste dei giocatori ------------------------------------------------------------


## Richiesta di un giocatore (peer) a chi ospita. Restituisce il messaggio da mostrargli.
func request(peer: int, action: String, args: Array) -> void:
	var who: String = world.name_of(peer)
	var mine := clan_of(who)
	match action:
		"fame":
			fame[who] = maxi(int(fame.get(who, 0)), int(args[0]))
			_pay_bank(who, peer)
			_mark()
		"join":
			var id := int(args[0])
			var c := clan(id)
			if c.is_empty() or not c["npc"]:
				return
			if mine >= 0:
				_reply(peer, false, "Sei già di %s." % clan(mine)["name"])
				return
			if float(rage.get("%d|%s" % [id, who], 0.0)) >= RAGE_HUNT:
				_reply(peer, false, "%s: «Tu? Dopo quello che hai fatto ai miei? Sparisci finché sei in tempo.»" % c["boss"])
				return
			if int(fame.get(who, 0)) < int(c["fame"]):
				_reply(peer, false, "%s: «Non ti conosce nessuno. Torna quando avrai fama %d.»" % [c["boss"], int(c["fame"])])
				return
			if String(c["task"]) != "" and task_progress(id, who) < int(c["n"]):
				_reply(peer, false, "%s: «Prima la prova.»" % c["boss"])
				return
			c["members"][who] = true
			_reply(peer, true, "%s: «Benvenuto in %s. Da oggi la zona è anche tua. Non tradirci.»" % [c["boss"], c["name"]], int(c["fee"]))
			world.clan_broadcast("Radio malavita: %s è entrato in %s." % [who, c["name"]])
			_mark()
		"leave":
			if mine < 0:
				return
			var c := clan(mine)
			c["members"].erase(who)
			if c["npc"]:
				rage["%d|%s" % [mine, who]] = 120.0  # traditore: ti cercano
				_reply(peer, true, "Hai lasciato %s. Per loro sei un traditore: occhio nel loro territorio." % c["name"])
			else:
				if String(c["boss"]) == who:
					var rest := (c["members"] as Dictionary).keys()
					if rest.is_empty():
						_dissolve(mine)
					else:
						c["boss"] = rest[0]
						world.clan_broadcast("%s ha lasciato %s: ora il capo è %s." % [who, c["name"], rest[0]])
				_reply(peer, true, "Hai lasciato %s." % c["name"])
			_mark()
		"found":
			var name_: String = String(args[0]).strip_edges().left(28)
			if mine >= 0:
				_reply(peer, false, "Prima devi lasciare %s." % clan(mine)["name"])
				return
			if int(fame.get(who, 0)) < Crime.FOUND_FAME:
				_reply(peer, false, "Per fondare un clan serve fama %d (sei %s)." % [Crime.FOUND_FAME, Crime.level_name(int(fame.get(who, 0)))])
				return
			if name_.length() < 3:
				_reply(peer, false, "Il nome del clan è troppo corto.")
				return
			for c: Dictionary in clans:
				if String(c["name"]).to_lower() == name_.to_lower():
					_reply(peer, false, "Esiste già un clan con quel nome.")
					return
			var pos: Vector3 = (world.players().get(peer) as Node3D).global_position
			var id := _next_id
			_next_id += 1
			var col: Color = PALETTE[id % PALETTE.size()]
			clans.append({"id": id, "name": name_, "color": col.to_html(false), "npc": false, "boss": who,
				"hq": [pos.x, pos.y, pos.z], "members": {who: true}, "treasury": 10000, "heat": 10.0, "rel": {},
				"fame": 150, "fee": 0, "task": "", "n": 0, "look": "gang_black", "requests": [],
				"hitmen": _roster(id, 180, 2)})
			for c: Dictionary in clans:
				if int(c["id"]) != id:
					_set_rel(id, int(c["id"]), -15)
			_reply(peer, true, "Hai fondato %s. Conquista le zone uccidendo gli uomini di chi le tiene e spacciando lì." % name_, Crime.FOUND_COST)
			world.clan_broadcast("Radio malavita: %s ha fondato un nuovo clan, %s." % [who, name_])
			_mark()
		"apply":
			var c := clan(int(args[0]))
			if c.is_empty() or c["npc"] or mine >= 0:
				return
			if int(fame.get(who, 0)) < int(c["fame"]):
				_reply(peer, false, "%s chiede almeno fama %d." % [c["name"], int(c["fame"])])
				return
			if not (c["requests"] as Array).has(who):
				c["requests"].append(who)
			_reply(peer, true, "Richiesta mandata a %s, il capo di %s." % [c["boss"], c["name"]])
			world.clan_msg(world.peer_of(String(c["boss"])), "%s chiede di entrare in %s (pannello del clan, U)." % [who, c["name"]])
			_mark()
		"accept", "reject":
			if not is_boss(who):
				return
			var c := clan(mine)
			var cand := String(args[0])
			c["requests"].erase(cand)
			if action == "accept" and clan_of(cand) < 0:
				c["members"][cand] = true
				var cp: int = world.peer_of(cand)
				world.clan_reply(cp, true, "%s ti ha accettato in %s." % [who, c["name"]], int(c["fee"]))
				c["treasury"] = int(c["treasury"]) + int(c["fee"])
			_mark()
		"entry":
			if is_boss(who):
				var c := clan(mine)
				c["fame"] = clampi(int(args[0]), 0, 5000)
				c["fee"] = clampi(int(args[1]), 0, 1000000)
				_mark()
		"withdraw":
			if is_boss(who):
				var c := clan(mine)
				var amount := mini(int(args[0]), int(c["treasury"]))
				if amount > 0:
					c["treasury"] = int(c["treasury"]) - amount
					world.award(peer, amount)
					_reply(peer, true, "Prelevati € %d dalla cassa del clan." % amount)
					_mark()
		"backup":
			_backup(peer, who, false)
		"corrupt":
			if mine < 0:
				_reply(peer, false, "Senza un clan non hai agganci in Questura.")
				return
			var stars := police.level(peer)
			if stars <= 0:
				_reply(peer, false, "Non sei ricercato.")
				return
			if float(_corrupt_cd.get(who, 0.0)) > 0.0:
				_reply(peer, false, "Il tuo contatto in Questura non risponde: riprova fra %d secondi." % int(_corrupt_cd[who]))
				return
			var cost := 1500 * stars
			_corrupt_cd[who] = 180.0
			police.wanted[peer] = stars - 1
			if stars - 1 <= 0:
				police.clear(peer)
			_add_heat(mine, 5.0)
			_reply(peer, true, "Un funzionario guarda altrove: una stella in meno (€ %d)." % cost, cost)
		"hire":
			# args: droga, dosi (già tolte dall'inventario del giocatore)
			if mine < 0:
				_reply(peer, false, "Per avere spacciatori al tuo soldo devi stare in un clan.")
				return
			var pos: Vector3 = (world.players().get(peer) as Node3D).global_position
			var z := Crime.zone_of(Vector2(pos.x, pos.z))
			pushers.append({"id": _next_pusher, "owner": who, "clan": mine, "zone": z, "drug": String(args[0]),
				"stock": int(args[1]), "earned": 0, "sold": 0, "pos": [pos.x, pos.y, pos.z]})
			_next_pusher += 1
			var o := zone_owner(z)
			var warn := "" if o == mine or o < 0 else " Attento: è zona di %s." % clan(o)["name"]
			_reply(peer, true, "Un ragazzo spaccerà %d dosi di %s per te a %s (si tiene il %d%%).%s" % [int(args[1]),
				Crime.DRUGS[String(args[0])]["name"], Crime.ZONES[z]["name"], int(PUSHER_CUT * 100), warn])
			_mark()
		"fire":
			var pid := int(args[0])
			for p: Dictionary in pushers:
				if int(p["id"]) == pid and String(p["owner"]) == who:
					pushers.erase(p)
					_reply(peer, true, "Hai ritirato lo spacciatore (le dosi rimaste sono perse in giro).")
					_mark()
					break
		"mission":
			_give_mission(peer, who)
		"sale":
			on_sale(peer, String(args[0]), int(args[1]), args[2] as Vector3)
		"contract":
			_contract(peer, who, String(args[0]), int(args[1]))


## Ingaggio di un sicario del proprio clan contro un giocatore in partita.
func _contract(peer: int, who: String, target: String, hi: int) -> void:
	var mine := clan_of(who)
	if mine < 0:
		_reply(peer, false, "I sicari lavorano solo per chi sta in un clan.")
		return
	var c := clan(mine)
	var roster: Array = c.get("hitmen", [])
	if hi < 0 or hi >= roster.size():
		return
	var h: Dictionary = roster[hi]
	if h["busy"]:
		_reply(peer, false, "%s è già su un altro lavoro." % h["name"])
		return
	var tpeer: int = world.peer_of(target)
	if target == who or tpeer <= 0:
		_reply(peer, false, "Quel giocatore non è in partita.")
		return
	if clan_of(target) == mine:
		_reply(peer, false, "%s: «Uno dei nostri? Scordatelo.»" % h["name"])
		return
	for k: Dictionary in contracts:
		if String(k["target"]) == target:
			_reply(peer, false, "C'è già qualcuno su di lui.")
			return
	var price := hit_price(int(h["fame"]), int(fame.get(target, 0)))
	var tp: Player = world.players().get(tpeer)
	if tp == null or tp.dead:
		_reply(peer, false, "Il bersaglio è appena morto: aspetta che rinasca.")
		return
	# Il sicario arriva a piedi da fuori vista; più è famoso, più è duro da abbattere e più mira bene.
	var s: Soldier = null
	var space := get_world_3d().direct_space_state
	for attempt in 12:
		var a := _rng.randf() * TAU
		var at := tp.global_position + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(60.0, 90.0)
		if city.carve_at(at.x, at.z) < -0.3:
			continue
		var g := city.surface_at(at.x, at.z)
		var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, g + 90.0, at.z), Vector3(at.x, g - 20.0, at.z), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or float(hit["position"].y) > g + 0.6:
			continue
		s = _spawn_soldier(mine, hit["position"] + Vector3(0, 0.3, 0), "hitman", tp, "fucile" if int(h["fame"]) > 550 else "mitragliatrice")
		break
	if s == null:
		_reply(peer, false, "%s non trova un modo per avvicinarsi. Riprova fra poco." % h["name"])
		return
	var f := int(h["fame"])
	s.health = 140.0 + f * 0.25
	s.skill = clampf(f / 1000.0, 0.2, 0.95)
	s.display = String(h["name"])
	h["busy"] = true
	contracts.append({"client": who, "target": target, "clan": mine, "hi": hi, "until": Time.get_unix_time_from_system() + HIT_TIME, "nid": s.nid})
	_reply(peer, true, "%s accetta: € %s per %s. Ti farò sapere." % [h["name"], SlotMachine._thousands(price), target], price)
	world.clan_msg(tpeer, "Qualcuno ha messo una taglia sulla tua testa. Guardati le spalle...")
	_mark()


func _contract_of_soldier(s: Soldier) -> Dictionary:
	for k: Dictionary in contracts:
		if int(k["nid"]) == s.nid:
			return k
	return {}


func _end_contract(k: Dictionary, success: bool, why: String) -> void:
	contracts.erase(k)
	var c := clan(int(k["clan"]))
	var cpeer: int = world.peer_of(String(k["client"]))
	var tpeer: int = world.peer_of(String(k["target"]))
	if not c.is_empty():
		var roster: Array = c.get("hitmen", [])
		if int(k["hi"]) < roster.size():
			var h: Dictionary = roster[int(k["hi"])]
			h["busy"] = false
			if success:
				h["fame"] = int(h["fame"]) + 80
				h["kills"] = int(h["kills"]) + 1
			else:
				h["fame"] = maxi(100, int(h["fame"]) - 40)
	if success:
		world.clan_msg(cpeer, "Lavoro fatto: %s è morto." % k["target"])
		world.give_fame(cpeer, 20)
		world.clan_msg(tpeer, "Ti ha fatto fuori un sicario. Qualcuno ti vuole morto.")
	else:
		world.clan_msg(cpeer, "Il contratto su %s è fallito: %s" % [k["target"], why])
		# A volte il sicario, prima di morire o di sparire, fa il nome di chi l'ha mandato.
		if _rng.randf() < 0.35 and tpeer > 0:
			world.clan_msg(tpeer, "Il sicario, prima di andarsene, ha fatto un nome: %s ti voleva morto." % k["client"])
	_mark()


## Un giocatore è morto (lo sa chi ospita): un sicario su di lui ha fatto il lavoro?
func on_player_killed(victim: String) -> void:
	for k: Dictionary in contracts.duplicate():
		if String(k["target"]) != victim:
			continue
		for n: Node in get_children():
			if n is Soldier and (n as Soldier).nid == int(k["nid"]) and not (n as Soldier).dead:
				var vp: Node3D = world.players().get(world.peer_of(victim))
				if vp == null or vp.global_position.distance_to((n as Soldier).global_position) < 60.0:
					_end_contract(k, true, "")
					(n as Soldier).life = 0.0
					(n as Soldier).role = "backup"  # se ne va
				break


func _reply(peer: int, ok: bool, text: String, charge := 0) -> void:
	world.clan_reply(peer, ok, text, charge)


func _dissolve(id: int) -> void:
	var c := clan(id)
	for z: Dictionary in zones:
		if int(z["owner"]) == id:
			z["owner"] = -1
		(z["infl"] as Dictionary).erase(str(id))
	pushers = pushers.filter(func(p: Dictionary) -> bool: return int(p["clan"]) != id)
	clans.erase(c)
	for o: Dictionary in clans:
		(o["rel"] as Dictionary).erase(str(id))
	world.clan_broadcast("Radio malavita: il clan %s non esiste più." % c["name"])


func _pay_bank(who: String, peer: int) -> void:
	var due := int(bank.get(who, 0))
	if due > 0 and peer > 0:
		bank.erase(who)
		world.award(peer, due)
		world.clan_msg(peer, "Mentre eri via i tuoi spacciatori ti hanno messo da parte € %d." % due)


# --- Lavori dal boss --------------------------------------------------------------------------------


func _give_mission(peer: int, who: String) -> void:
	var mine := clan_of(who)
	if mine < 0:
		return
	if missions.has(who):
		world.clan_reply(peer, false, "Hai già un lavoro in corso: %s" % _mission_text(missions[who]), 0)
		return
	var enemies := clans.filter(func(c: Dictionary) -> bool: return int(c["id"]) != mine)
	enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return rel(mine, int(a["id"])) < rel(mine, int(b["id"])))
	var kind: String = ["hit", "deal", "racket"][_rng.randi() % 3]
	var m := {"clan": mine, "kind": kind, "n": 0, "done": 0, "reward": 0, "fame": 0, "target": -1, "pos": []}
	match kind:
		"hit":
			var e: Dictionary = enemies[0] if not enemies.is_empty() else {}
			if e.is_empty():
				kind = "deal"
			else:
				m["target"] = int(e["id"])
				m["n"] = 3
				m["reward"] = 3500
				m["fame"] = 40
				var ez := _zones_of(int(e["id"]))
				var z: int = ez[_rng.randi() % ez.size()] if not ez.is_empty() else _rng.randi() % zones.size()
				var at := _hq_for(z) + Vector3(_rng.randf_range(-25, 25), 0, _rng.randf_range(-25, 25))
				m["pos"] = [at.x, at.y, at.z]
				for k in 3:
					_spawn_soldier(int(e["id"]), at + Vector3(k * 1.5, 0.3, 0), "squad", world.players().get(peer))
	if kind == "deal":
		m["kind"] = "deal"
		m["n"] = 8
		m["reward"] = 1500
		m["fame"] = 25
		var mz := _zones_of(mine)
		m["target"] = mz[0] if not mz.is_empty() else -1
	elif kind == "racket":
		var ez2: Array = []
		for e: Dictionary in enemies:
			ez2.append_array(_zones_of(int(e["id"])))
		if ez2.is_empty():
			ez2 = [0]
		m["target"] = ez2[_rng.randi() % ez2.size()]
		m["n"] = 1
		m["reward"] = 2500
		m["fame"] = 30
		var zc: Vector2 = Crime.ZONES[int(m["target"])]["c"]
		m["pos"] = [zc.x, 0.0, zc.y]
	missions[who] = m
	world.clan_reply(peer, true, "%s: «%s»" % [clan(mine)["boss"] if clan(mine)["npc"] else "Lavoro", _mission_text(m)], 0)
	_mark()


func _mission_text(m: Dictionary) -> String:
	match String(m["kind"]):
		"hit":
			return "Regolamento di conti: fai fuori %d uomini di %s (sono segnati sulla mappa). € %d" % [int(m["n"]), clan(int(m["target"])).get("name", "?"), int(m["reward"])]
		"deal":
			return "Spaccia %d dosi nel nostro territorio. € %d" % [int(m["n"]), int(m["reward"])]
		"racket":
			return "Rapina un locale a %s, zona nemica: è un messaggio. € %d" % [Crime.ZONES[int(m["target"])]["name"], int(m["reward"])]
	return ""


func mission_text(who: String) -> String:
	return _mission_text(missions[who]) + " (%d/%d)" % [int(missions[who]["done"]), int(missions[who]["n"])] if missions.has(who) else ""


func _mission_event(who: String, kind: String, arg: int) -> void:
	if not missions.has(who):
		return
	var m: Dictionary = missions[who]
	if String(m["kind"]) != kind:
		return
	if kind == "hit" and arg != int(m["target"]):
		return
	if kind == "deal" and zone_owner(arg) != int(m["clan"]):
		return
	if kind == "racket" and arg != int(m["target"]):
		return
	m["done"] = int(m["done"]) + 1
	var peer: int = world.peer_of(who)
	if int(m["done"]) >= int(m["n"]):
		missions.erase(who)
		world.award(peer, int(m["reward"]))
		world.give_fame(peer, int(m["fame"]))
		world.clan_msg(peer, "Lavoro fatto: € %d e fama +%d." % [int(m["reward"]), int(m["fame"])])
		var c := clan(int(m["clan"]))
		if not c.is_empty():
			c["treasury"] = int(c["treasury"]) + int(m["reward"]) / 5
	_mark()


func _zones_of(id: int) -> Array:
	var out := []
	for z in zones.size():
		if zone_owner(z) == id:
			out.append(z)
	return out


# --- Chi ospita: ciclo ------------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if world != null and not world.simulate:
		# Sui client la rabbia arriva solo quando cambia qualcosa: la si fa calare anche qui, come sull'host.
		for k: String in rage.keys():
			rage[k] = maxf(0.0, float(rage[k]) - delta / 6.0)
		return
	if world == null:
		return
	_t += delta
	for d: Dictionary in [_squad_cd, _backup_cd, _corrupt_cd]:
		for k: String in d.keys():
			d[k] = float(d[k]) - delta
	if _t >= 1.0:
		_t = 0.0
		_tick_second()
	_push_t += delta
	if _push_t >= PUSHER_TICK:
		_push_t = 0.0
		_tick_pushers()
	_income_t += delta
	if _income_t >= 60.0:
		_income_t = 0.0
		_tick_income()
	_npc_war_t += delta
	if _npc_war_t >= 240.0:
		_npc_war_t = 0.0
		_npc_war()
	_save_t += delta
	if _save_t >= 30.0:
		_save_t = 0.0
		save()
	_send_t -= delta
	if _dirty and _send_t <= 0.0:
		_dirty = false
		_send_t = 1.0
		world.clan_sync(state_json())
		changed.emit()


func _tick_second() -> void:
	var ps: Dictionary = world.players()
	# La rabbia passa piano (un punto ogni 6 secondi).
	for k: String in rage.keys():
		var was := float(rage[k])
		rage[k] = was - 1.0 / 6.0
		if was >= RAGE_HUNT and float(rage[k]) < RAGE_HUNT:
			var parts := k.split("|", true, 1)
			var gone := clan(int(parts[0]))
			if not gone.is_empty():
				world.clan_msg(world.peer_of(parts[1]), "%s ha smesso di cercarti. Per ora." % gone["name"])
			_mark()
		if float(rage[k]) <= 0.0:
			rage.erase(k)
	var soldiers := get_children().filter(func(n: Node) -> bool: return n is Soldier)
	# Boss e guardie del corpo davanti ai quartieri generali, quando c'è qualcuno vicino.
	for c: Dictionary in clans:
		var hq := Vector3(float(c["hq"][0]), float(c["hq"][1]), float(c["hq"][2]))
		var near := false
		for peer: int in ps:
			if (ps[peer] as Node3D).global_position.distance_to(hq) < 230.0:
				near = true
		var mine := soldiers.filter(func(s: Soldier) -> bool: return s.clan_id == int(c["id"]) and s.role in ["boss", "guard"])
		if near and mine.is_empty() and c["npc"] and float(c.get("boss_dead_until", 0.0)) < Time.get_unix_time_from_system():
			_spawn_soldier(int(c["id"]), hq + Vector3(0, 0.3, 0), "boss", null)
			for k in 2:
				_spawn_soldier(int(c["id"]), hq + Vector3(2.0 if k == 0 else -2.0, 0.3, 1.5), "guard", null)
		elif not near:
			for s: Soldier in mine:
				s.queue_free()
	# Squadre contro chi il clan vuole punire (nel suo territorio, o ovunque se la rabbia è altissima).
	for peer: int in ps:
		var p: Player = ps[peer]
		if p.dead:
			continue
		var who: String = world.name_of(peer)
		var z := Crime.zone_of(Vector2(p.global_position.x, p.global_position.z))
		for c: Dictionary in clans:
			var id := int(c["id"])
			if not hostile(id, who):
				continue
			var r := float(rage.get("%d|%s" % [id, who], 0.0))
			if zone_owner(z) != id and r < 150.0:
				continue
			var key := "%d|%s" % [id, who]
			if float(_squad_cd.get(key, 0.0)) > 0.0:
				continue
			var hunting := soldiers.filter(func(s: Soldier) -> bool: return s.clan_id == id and s.role == "squad" and s.target == p and not s.dead)
			if hunting.size() >= 2 + mini(int(r / 60.0), 3):
				continue
			_squad_cd[key] = 25.0
			_send_squad(id, p, 2 + mini(int(r / 80.0), 2))
		# Rinforzi automatici: 3 stelle o più nel territorio del proprio clan.
		var mine_id := clan_of(who)
		if mine_id >= 0 and police.level(peer) >= 3 and zone_owner(z) == mine_id:
			_backup(peer, who, true)
	# Indagini che si calmano, rabbia dei picciotti già in giro.
	for c: Dictionary in clans:
		if not c["npc"]:
			c["heat"] = maxf(0.0, float(c["heat"]) - 1.0 / 120.0)
	var now := Time.get_unix_time_from_system()
	for k: Dictionary in contracts.duplicate():
		var target_gone: bool = world.peer_of(String(k["target"])) <= 0
		if float(k["until"]) < now or target_gone:
			for s2: Soldier in soldiers:
				if s2.nid == int(k["nid"]):
					s2.queue_free()
			_end_contract(k, false, "il bersaglio è sparito." if target_gone else "il sicario non l'ha trovato in tempo.")
	for s: Soldier in soldiers:
		if not is_instance_valid(s.target) and s.role in ["squad", "hitman"]:
			s.target = null
		var far := Pedestrians.nearest(s.global_position, world.anchors()) > 320.0
		if (far and not s.role in ["boss", "hitman"]) or (s.dead and s.dead_time > 30.0) or (s.role == "backup" and s.life <= 0.0):
			s.queue_free()


## Squadra che arriva a piedi da fuori vista (60-90 m), armata, contro il giocatore p.
func _send_squad(id: int, p: Player, count: int) -> void:
	var space := get_world_3d().direct_space_state
	for attempt in 10:
		var a := _rng.randf() * TAU
		var at := p.global_position + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(55.0, 85.0)
		if city.carve_at(at.x, at.z) < -0.3:
			continue
		var g := city.surface_at(at.x, at.z)
		var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, g + 90.0, at.z), Vector3(at.x, g - 20.0, at.z), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or float(hit["position"].y) > g + 0.6:
			continue
		for k in count:
			_spawn_soldier(id, hit["position"] + Vector3(k * 1.2, 0.3, 0), "squad", p)
		return


## Rinforzi del clan contro la polizia (manuali col tasto N, o automatici col ricercato nel proprio territorio).
func _backup(peer: int, who: String, auto: bool) -> void:
	var mine := clan_of(who)
	if mine < 0:
		if not auto:
			world.clan_reply(peer, false, "Non hai un clan che ti copre.", 0)
		return
	if float(_backup_cd.get(who, 0.0)) > 0.0:
		if not auto:
			world.clan_reply(peer, false, "I tuoi sono già per strada: riprova fra %d secondi." % int(_backup_cd[who]), 0)
		return
	var c := clan(mine)
	var count := 2 + rank_index(who)
	if not c["npc"]:
		count = mini(count, int(c["treasury"]) / 500 + 1)
		c["treasury"] = maxi(0, int(c["treasury"]) - 500 * count)
	_backup_cd[who] = 120.0
	var p: Player = world.players().get(peer)
	if p == null:
		return
	for k in count:
		var a := TAU * k / count
		var at := p.global_position + Vector3(cos(a), 0, sin(a)) * 18.0
		at.y = city.surface_at(at.x, at.z) + 0.3
		var s := _spawn_soldier(mine, at, "backup", p)
		s.life = 100.0
	world.clan_reply(peer, true, "%s manda %d uomini a coprirti dalla polizia." % [c["name"], count], 0)
	_mark()


## Spacciatori al soldo: ogni 15 secondi vendono una dose (di più di notte), con i loro rischi.
func _tick_pushers() -> void:
	var night := DayNight.current != null and DayNight.current.is_night()
	var cops := get_tree().get_nodes_in_group("cop")
	for p: Dictionary in pushers.duplicate():
		if int(p["stock"]) <= 0:
			_settle_pusher(p, "ha finito la roba")
			pushers.erase(p)
			continue
		if _rng.randf() > (0.85 if night else 0.65):
			continue
		var d: Dictionary = Crime.DRUGS[String(p["drug"])]
		var z := int(p["zone"])
		var owner := zone_owner(z)
		var at := Vector3(float(p["pos"][0]), float(p["pos"][1]), float(p["pos"][2]))
		# Clan rivali: chi tiene la zona può fargli la festa.
		if owner >= 0 and owner != int(p["clan"]) and rel(owner, int(p["clan"])) < 50 and _rng.randf() < 0.07:
			_settle_pusher(p, "")
			pushers.erase(p)
			_set_rel(owner, int(p["clan"]), rel(owner, int(p["clan"])) - 10)
			world.clan_msg(world.peer_of(String(p["owner"])), "Gli uomini di %s hanno pestato il tuo spacciatore a %s e si sono presi la roba." % [clan(owner)["name"], Crime.ZONES[z]["name"]])
			_mark()
			continue
		# Polizia: rischio per la droga, la zona sorvegliata, l'indagine sul clan.
		var risk := 0.02 * float(d["risk"])
		for c: Node in cops:
			if (c as Node3D).global_position.distance_to(at) < 70.0:
				risk += 0.08
				break
		var cl := clan(int(p["clan"]))
		if not cl.is_empty():
			risk += float(cl["heat"]) / 100.0 * 0.06
		if _rng.randf() < risk:
			_arrest_pusher(p)
			continue
		var price := _rng.randi_range(int(d["sell"][0]), int(d["sell"][1]))
		if night and String(p["drug"]) in ["md", "lsd", "cocaina"]:
			price = int(price * 1.2)
		p["stock"] = int(p["stock"]) - 1
		p["sold"] = int(p.get("sold", 0)) + 1
		var share := int(price * (1.0 - PUSHER_CUT))
		if owner == int(p["clan"]) or owner < 0:
			var c2 := clan(int(p["clan"]))
			if not c2.is_empty():
				var tax := int(price * PIZZO)
				share -= tax
				c2["treasury"] = int(c2["treasury"]) + tax
		else:
			_influence(z, int(p["clan"]), 0.5)
		p["earned"] = int(p["earned"]) + share
		if int(p["earned"]) >= 250:
			_settle_pusher(p, "")
		_mission_event(String(p["owner"]), "deal", z)
	_mark()


## Paga al padrone dello spacciatore quanto ha messo da parte (in banca se non c'è).
func _settle_pusher(p: Dictionary, why: String) -> void:
	var amount := int(p["earned"])
	p["earned"] = 0
	var who := String(p["owner"])
	var peer: int = world.peer_of(who)
	if amount > 0:
		if peer > 0:
			world.award(peer, amount)
		else:
			bank[who] = int(bank.get(who, 0)) + amount
	if peer > 0 and (amount > 0 or why != ""):
		world.clan_msg(peer, "Il tuo spacciatore a %s %s: € %d per te." % [Crime.ZONES[int(p["zone"])]["name"], why if why != "" else "ti passa l'incasso", amount])


## Arrestato: perdi la roba; a volte fa il tuo nome (2 stelle) e l'indagine sul clan sale.
func _arrest_pusher(p: Dictionary) -> void:
	pushers.erase(p)
	var who := String(p["owner"])
	var peer: int = world.peer_of(who)
	var talks := _rng.randf() < 0.3 * float(Crime.DRUGS[String(p["drug"])]["risk"])
	_add_heat(int(p["clan"]), 12.0)
	if peer > 0:
		var pl: Node3D = world.players().get(peer)
		if talks and pl:
			police.report("snitched", pl.global_position, peer)
			world.clan_msg(peer, "Il tuo spacciatore a %s è stato arrestato e HA FATTO IL TUO NOME: la polizia ti cerca!" % Crime.ZONES[int(p["zone"])]["name"])
		else:
			world.clan_msg(peer, "Il tuo spacciatore a %s è stato arrestato. Non ha parlato (per ora)." % Crime.ZONES[int(p["zone"])]["name"])
	_mark()


## Entrate dei territori: per i clan dei giocatori metà in cassa, un terzo al capo, il resto agli affiliati in partita.
func _tick_income() -> void:
	var total := 0
	for v: int in Crime.ZONE_INCOME.values():
		total += v
	for z in zones.size():
		var c := clan(zone_owner(z))
		if c.is_empty():
			continue
		# Il padrone recupera un po' di presa sulla zona.
		var infl: Dictionary = zones[z]["infl"]
		infl[str(c["id"])] = minf(100.0, float(infl.get(str(c["id"]), 0.0)) + 1.0)
		if c["npc"]:
			c["treasury"] = int(c["treasury"]) + total / 4
			continue
		c["treasury"] = int(c["treasury"]) + total / 2
		var boss_peer: int = world.peer_of(String(c["boss"]))
		if boss_peer > 0:
			world.award(boss_peer, total / 3)
		var online := []
		for m: String in (c["members"] as Dictionary).keys():
			if m != String(c["boss"]) and world.peer_of(m) > 0:
				online.append(world.peer_of(m))
		for peer: int in online:
			world.award(peer, (total - total / 2 - total / 3) / online.size())
	_mark()


## Guerre tra clan del gioco: chi è in guerra si ruba un po' di presa sulle zone di confine (e a volte una zona).
func _npc_war() -> void:
	for a: Dictionary in clans:
		for b: Dictionary in clans:
			if int(a["id"]) >= int(b["id"]) or not (a["npc"] and b["npc"]) or rel(int(a["id"]), int(b["id"])) > WAR:
				continue
			var bz := _zones_of(int(b["id"]))
			if bz.is_empty():
				continue
			var z: int = bz[_rng.randi() % bz.size()]
			_influence(z, int(a["id"]), _rng.randf_range(2.0, 7.0))
	# Pace e guerra cambiano piano: i rapporti tornano verso zero.
	for a: Dictionary in clans:
		for k: String in (a["rel"] as Dictionary).keys():
			var v := int(a["rel"][k])
			a["rel"][k] = v + (1 if v < 0 else (-1 if v > 0 else 0))
	_mark()


func _spawn_soldier(id: int, pos: Vector3, role: String, target: Node3D, weapon_override := "") -> Soldier:
	var c := clan(id)
	var s := Soldier.new()
	s.clans = self
	s.clan_id = id
	s.nid = world.new_nid()
	s.role = role
	s.preset = "boss" if role == "boss" else String(c.get("look", "gang_black"))
	s.weapon = "" if role == "boss" else ("mitragliatrice" if _rng.randf() < 0.35 else "pistola")
	if weapon_override != "":
		s.weapon = weapon_override
	s.target = target
	s.anchor = pos
	s.display = String(c.get("boss", "")) if role == "boss" else ""
	add_child(s)
	s.global_position = pos
	return s


## Il boss più vicino (vero o copia), se entro max_dist: [nodo, id del clan] o [].
func boss_near(pos: Vector3, max_dist: float) -> Array:
	for n: Node in get_tree().get_nodes_in_group("gang"):
		if n.get_meta("boss_clan", -1) < 0 or n.get_meta("dead", false):
			continue
		if (n as Node3D).global_position.distance_to(pos) < max_dist:
			return [n, int(n.get_meta("boss_clan"))]
	return []


## Uomo di un clan: boss (fermo al quartier generale), guardia (vicino al boss), squadra (caccia un giocatore),
## rinforzo (spara agli agenti vicino al giocatore che copre).
class Soldier:
	extends CharacterBody3D

	var clans: Clans
	var clan_id := 0
	var nid := 0
	var role := "guard"
	var preset := "gang_black"
	var weapon := "pistola"
	var display := ""
	var target: Node3D
	var anchor := Vector3.ZERO
	var health := 110.0
	var dead := false
	var dead_time := 0.0
	var life := 0.0  # rinforzi: secondi prima di andarsene
	var skill := 0.4  # mira (i sicari migliori sbagliano meno)
	var net_anim := "idle"
	var _human: Human
	var _gun: Node3D
	var _cool := 1.0
	var _foe: Node3D  # bersaglio attuale (giocatore, agente, uomo di un altro clan)
	var _scan := 0.0
	var _stuck := 0.0
	var _side := 1.0
	var _tag: Label3D

	func _ready() -> void:
		add_to_group("damageable")
		add_to_group("pedestrian")
		add_to_group("gang")
		set_meta("gang", true)
		if role == "boss":
			set_meta("boss_clan", clan_id)
			health = 220.0
		clans.world.register(nid, self)
		collision_layer = 32
		collision_mask = 1 | 2 | 16
		var shape := CapsuleShape3D.new()
		shape.radius = 0.3
		shape.height = 1.7
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 0.85
		add_child(cs)
		_human = Human.new().setup(preset)
		add_child(_human)
		if weapon != "":
			_gun = Weapons.model(weapon)
			if _gun:
				add_child(_gun)
				_gun.top_level = true
		if role == "boss":
			_tag = make_tag(self, display, clans.color_of(clan_id))
		if role == "hitman":
			_human.scale = Vector3.ONE * 1.02

	static func make_tag(n: Node3D, text: String, col: Color) -> Label3D:
		var t := Label3D.new()
		t.text = text
		t.position.y = 2.25
		t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		t.font_size = 40
		t.outline_size = 10
		t.pixel_size = 0.006
		t.modulate = col.lightened(0.3)
		t.visibility_range_end = 40.0
		n.add_child(t)
		return t

	func is_mine() -> bool:
		return true

	func human() -> Human:
		return _human

	func take_damage(amount: float, from_peer: int, at: Vector3) -> void:
		if dead:
			return
		health -= amount
		if from_peer > 0:
			var who: String = clans.world.name_of(from_peer)
			if clans.clan_of(who) != clan_id:
				clans._add_rage(clan_id, who, 25.0, from_peer)
				var p: Node3D = clans.world.players().get(from_peer)
				if p:
					_foe = p
		if health <= 0.0:
			dead = true
			net_anim = "death"
			collision_layer = 0
			_human.play_once("death")
			if _gun:
				_gun.queue_free()
				_gun = null
			if _tag:
				_tag.queue_free()
			if role == "boss":
				var c := clans.clan(clan_id)
				c["boss_dead_until"] = Time.get_unix_time_from_system() + 600.0  # per 10 minuti niente boss
			clans.pedestrians.drop_cash(global_position, randi_range(80, 300) if role != "boss" else 3000)
			if weapon != "":
				clans.pedestrians.drop_ammo(global_position + global_basis.x * 0.8, weapon, int(Weapons.info(weapon).get("mag", 12)))
			if from_peer > 0:
				clans.police.report("kill", at, from_peer)
			clans.on_soldier_killed(self, from_peer)
		else:
			_human.play_once("hit")

	func _pick_foe() -> Node3D:
		var me := global_position
		match role:
			"squad", "hitman":
				if target and is_instance_valid(target) and not target.get("dead"):
					return target
			"backup":
				# Il primo agente vicino a chi stanno coprendo (o a loro).
				var best: Node3D = null
				var bd := 75.0
				for c: Node in get_tree().get_nodes_in_group("cop"):
					if c.get("dead") == true or c.get_meta("dead", false):
						continue
					var d := (c as Node3D).global_position.distance_to(target.global_position if target and is_instance_valid(target) else me)
					if d < bd:
						bd = d
						best = c
				return best
		# Guardie e boss: giocatori ostili vicini.
		var ps: Dictionary = clans.world.players()
		var best_p: Node3D = null
		var best_d := 45.0 if role == "guard" else 25.0
		for peer: int in ps:
			var p: Player = ps[peer]
			if p.dead or not clans.hostile(clan_id, clans.world.name_of(peer)):
				continue
			var d := p.global_position.distance_to(me)
			if d < best_d:
				best_d = d
				best_p = p
		return best_p

	func _sees(n: Node3D) -> bool:
		var from := global_position + Vector3(0, 1.6, 0)
		var to := n.global_position + Vector3(0, 1.3, 0)
		if from.distance_to(to) > 80.0:
			return false
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

	func _physics_process(delta: float) -> void:
		if dead:
			dead_time += delta
			velocity = Vector3(0, velocity.y - 16.0 * delta, 0)
			move_and_slide()
			return
		if role == "backup":
			life -= delta
		_scan -= delta
		if _scan <= 0.0:
			_scan = 0.8
			if _foe == null or not is_instance_valid(_foe) or _foe.get("dead") == true or _foe.get_meta("dead", false) or role != "guard":
				_foe = _pick_foe()
		_cool -= delta
		var target_v := Vector3.ZERO
		var anim := "idle"
		var goal := anchor
		if role == "backup" and target and is_instance_valid(target):
			goal = target.global_position
		if _foe and is_instance_valid(_foe):
			var sees_it := _sees(_foe)
			var to := _foe.global_position - global_position
			to.y = 0.0
			if sees_it and to.length() < 22.0 and weapon != "":
				anim = "aim"
				_human.rotation.y = lerp_angle(_human.rotation.y, atan2(to.x, to.z), 1.0 - exp(-10.0 * delta))
				if _cool <= 0.0:
					_shoot(_foe)
			else:
				goal = _foe.global_position
		if anim != "aim":
			var to := goal - global_position
			to.y = 0.0
			var stop := 1.2 if role in ["boss", "guard"] else 5.0
			if to.length() > stop:
				var dir := to.normalized()
				if _stuck > 0.6:
					dir = (dir + Vector3(-dir.z, 0, dir.x) * _side * 1.5).normalized()
				var run := _foe != null or to.length() > 12.0
				target_v = dir * (6.0 if run else 2.2)
				anim = "sprint" if run else "walk"
			elif role == "boss":
				anim = "talk" if fmod(Time.get_ticks_msec() / 1000.0 + nid, 12.0) < 5.0 else "idle"
		velocity.x = lerpf(velocity.x, target_v.x, 1.0 - exp(-8.0 * delta))
		velocity.z = lerpf(velocity.z, target_v.z, 1.0 - exp(-8.0 * delta))
		velocity.y = 0.0 if is_on_floor() else velocity.y - 16.0 * delta
		var before := global_position
		move_and_slide()
		if target_v.length() > 1.0 and global_position.distance_to(before) < target_v.length() * delta * 0.3:
			_stuck += delta
			if _stuck > 2.5:
				_stuck = 0.0
				_side = -_side
		else:
			_stuck = maxf(0.0, _stuck - delta)
		if Vector2(velocity.x, velocity.z).length() > 0.5:
			_human.rotation.y = lerp_angle(_human.rotation.y, atan2(velocity.x, velocity.z), 1.0 - exp(-8.0 * delta))
		net_anim = anim
		_human.play(anim)
		if _gun:
			_gun.global_transform = Transform3D(Basis(Vector3.UP, _human.rotation.y + rotation.y), _human.hand_position())

	func _shoot(n: Node3D) -> void:
		var auto := weapon == "mitragliatrice"
		_cool = randf_range(0.12, 0.2) if auto and randf() < 0.75 else randf_range(0.8, 1.5)
		var origin := global_position + Vector3(0, 1.45, 0)
		var aim := n.global_position + Vector3(0, 1.1, 0)
		var miss := (1.0 + aim.distance_to(origin) * 0.045) * lerpf(0.75, 0.2, skill)
		aim += Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * miss
		var muzzle := _gun.global_position if _gun else origin
		clans.combat.shoot(self, weapon, origin, (aim - origin).normalized(), muzzle)
