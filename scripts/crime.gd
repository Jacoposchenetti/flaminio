class_name Crime
extends RefCounted

## Dati della malavita: droghe dello spaccio, fama criminale (livelli) e clan che all'inizio si dividono il quartiere.
## La logica dei clan sta in clans.gd; qui solo tabelle e piccole funzioni senza stato.

## Droghe: prezzo dallo spacciatore, prezzo di strada (min-max), quanto la chiedono i passanti (peso), quanto
## rischi se ti beccano (stelle per lo spaccio e probabilità che un sottoposto arrestato parli).
const DRUGS := {
	"erba": {"name": "Erba", "buy": 10, "sell": [25, 40], "demand": 34, "risk": 0.6, "color": Color(0.35, 0.75, 0.3)},
	"fumo": {"name": "Fumo", "buy": 12, "sell": [30, 45], "demand": 26, "risk": 0.7, "color": Color(0.6, 0.42, 0.22)},
	"cocaina": {"name": "Cocaina", "buy": 60, "sell": [110, 160], "demand": 14, "risk": 1.6, "color": Color(0.95, 0.95, 0.98)},
	"md": {"name": "MD", "buy": 25, "sell": [50, 80], "demand": 15, "risk": 1.1, "color": Color(0.9, 0.45, 0.85)},
	"lsd": {"name": "LSD", "buy": 15, "sell": [40, 70], "demand": 11, "risk": 0.9, "color": Color(0.4, 0.7, 1.0)},
}
const DRUG_ORDER := ["erba", "fumo", "cocaina", "md", "lsd"]
const MAX_DOSES := 40  # dosi che si portano addosso, in tutto

## Fama criminale: si guadagna con i reati (e la tieni anche tra una partita e l'altra).
const LEVELS := [
	[0, "Nessuno"], [50, "Teppista"], [150, "Malvivente"], [350, "Delinquente"],
	[700, "Criminale"], [1200, "Boss"], [2000, "Padrino"],
]
const FOUND_FAME := 700  # fama per fondare un clan
const FOUND_COST := 25000
const FAME := {
	"kill": 4, "cop_kill": 12, "car": 3, "theft": 2, "robbery": 15, "assault": 1, "sale": 1,
	"soldier_kill": 8, "escape": 10, "capture": 50,
}


static func level_index(fame: int) -> int:
	var i := 0
	for k in LEVELS.size():
		if fame >= int(LEVELS[k][0]):
			i = k
	return i


static func level_name(fame: int) -> String:
	return String(LEVELS[level_index(fame)][1])


## [fama del livello attuale, fama del prossimo] (per la barra).
static func level_span(fame: int) -> Array:
	var i := level_index(fame)
	var next := int(LEVELS[i + 1][0]) if i + 1 < LEVELS.size() else int(LEVELS[i][0]) + 1000
	return [int(LEVELS[i][0]), next]


## Zone del quartiere (territori): nome e centro. Ogni punto della mappa sta nella zona col centro più vicino.
const ZONES := [
	{"name": "Ponte Milvio", "c": Vector2(-150, -1420)},
	{"name": "Tor di Quinto", "c": Vector2(520, -1250)},
	{"name": "Villaggio Olimpico", "c": Vector2(-60, -800)},
	{"name": "Flaminio", "c": Vector2(-420, -150)},
	{"name": "Parioli", "c": Vector2(380, -200)},
	{"name": "Valle Giulia", "c": Vector2(560, 650)},
	{"name": "Piazza del Popolo", "c": Vector2(-120, 1300)},
	{"name": "Della Vittoria", "c": Vector2(-800, 450)},
]

## Clan che all'inizio controllano il quartiere (personaggi e nomi inventati, la Banda della Magliana è quella
## storica dei romanzi e dei film). Condizioni per entrare: fama minima, quota in euro e una prova.
## Prove: "sell" (vendi n dosi nel loro territorio), "kill" (uccidi n uomini di altri clan), "" (nessuna).
const NPC_CLANS := [
	{"name": "Banda della Magliana", "boss": "Er Sorcio", "color": Color(0.8, 0.12, 0.1), "zones": [0, 1],
		"fame": 300, "fee": 10000, "task": "", "n": 0, "look": "gang_red"},
	{"name": "Clan del Flaminio", "boss": "Er Pantera", "color": Color(0.6, 0.2, 0.85), "zones": [2, 3],
		"fame": 100, "fee": 0, "task": "sell", "n": 10, "look": "gang_purple"},
	{"name": "I Pariolini", "boss": "Er Principe", "color": Color(0.15, 0.45, 0.95), "zones": [4, 5],
		"fame": 200, "fee": 0, "task": "kill", "n": 3, "look": "gang_blue"},
	{"name": "Clan di Prati", "boss": "Er Cravatta", "color": Color(0.95, 0.55, 0.1), "zones": [6, 7],
		"fame": 50, "fee": 3000, "task": "", "n": 0, "look": "gang_orange"},
]
## Rapporti iniziali tra i clan (da -100 guerra a +100 alleati): Magliana e Pariolini sono già in guerra.
const NPC_RELATIONS := [[0, 2, -70], [1, 3, 20], [0, 1, -20], [2, 3, -10]]

## Entrate di un territorio al minuto: spaccio, estorsioni ai negozi, giri di prostituzione.
const ZONE_INCOME := {"spaccio": 320, "estorsioni": 220, "prostituzione": 180}


static func zone_of(p: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in ZONES.size():
		var d := (ZONES[i]["c"] as Vector2).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


## Poligono della zona i (cella di Voronoi dentro il riquadro della mappa), per disegnarla sulla mappa.
static func zone_polygon(i: int, box: Rect2) -> PackedVector2Array:
	var poly := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
	var c: Vector2 = ZONES[i]["c"]
	for j in ZONES.size():
		if j == i:
			continue
		var o: Vector2 = ZONES[j]["c"]
		var mid := (c + o) * 0.5
		var n := (o - c).normalized()  # si tiene il lato di c: (p - mid)·n <= 0
		var out := PackedVector2Array()
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			var da := (a - mid).dot(n)
			var db := (b - mid).dot(n)
			if da <= 0.0:
				out.append(a)
			if (da <= 0.0) != (db <= 0.0):
				out.append(a + (b - a) * (da / (da - db)))
		poly = out
		if poly.size() < 3:
			break
	return poly
