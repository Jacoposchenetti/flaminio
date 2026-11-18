class_name Updater
extends Node

## Aggiornamento automatico della copia per gli amici.
## Ogni versione pubblicata (tools/pubblica_aggiornamento.py) ha un manifest.json con l'elenco dei file e la loro
## impronta MD5. Il gioco confronta il manifest pubblicato con il suo (res://manifest.json), scarica solo i file
## cambiati in una cartella accanto al gioco ("aggiornamento"), li controlla, poi si chiude: un piccolo .bat li
## sposta al posto di quelli vecchi, cancella quelli tolti e riavvia il gioco.
## La copia di sviluppo non ha manifest.json, quindi non si aggiorna mai da sola.

signal status(text: String)
signal available(version: int)
signal finished_check(version: int)  # -1 se non si è potuto controllare

const BASE := "https://raw.githubusercontent.com/Jacoposchenetti/flaminio/"
const BRANCH := "aggiornamenti"

var base := BASE
var remote: Dictionary = {}
var _remote_text := ""
var busy := false
var _req: HTTPRequest
var _bytes_done := 0
var _bytes_total := 0
var _cur_size := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--update-url="):
			base = arg.get_slice("=", 1)
			if not base.ends_with("/"):
				base += "/"


static func local_manifest() -> Dictionary:
	if not FileAccess.file_exists("res://manifest.json"):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://manifest.json"))
	return d if d is Dictionary else {}


## Versione di questa copia (0 = copia di sviluppo, senza manifest).
static func local_version() -> int:
	return int(local_manifest().get("version", 0))


static func can_update() -> bool:
	return local_version() > 0


## Controlla se c'è una versione nuova; emette available(versione) se sì.
func check() -> void:
	if busy:
		return
	if not can_update():
		status.emit("Copia di sviluppo: gli aggiornamenti si pubblicano con tools/pubblica_aggiornamento.py")
		finished_check.emit(-1)
		return
	busy = true
	var res := await _fetch(base + BRANCH + "/manifest.json?t=%d" % Time.get_unix_time_from_system(), "")
	busy = false
	if res[0] != OK:
		status.emit("Non riesco a controllare gli aggiornamenti (sei collegato a Internet?)")
		finished_check.emit(-1)
		return
	var d: Variant = JSON.parse_string((res[1] as PackedByteArray).get_string_from_utf8())
	if not (d is Dictionary) or not d.has("files"):
		status.emit("Il file degli aggiornamenti non è valido.")
		finished_check.emit(-1)
		return
	remote = d
	_remote_text = (res[1] as PackedByteArray).get_string_from_utf8()
	var v := int(remote.get("version", 0))
	finished_check.emit(v)
	if v > local_version():
		available.emit(v)
		if "--autoupdate" in OS.get_cmdline_user_args():  # prova automatica
			install()


## Scarica la versione trovata da check() e riavvia il gioco aggiornato.
func install() -> void:
	if busy or remote.is_empty():
		return
	busy = true
	var mine: Dictionary = local_manifest().get("files", {})
	var theirs: Dictionary = remote["files"]
	var version := int(remote["version"])
	var todo: Array[String] = []
	_bytes_total = 0
	for path: String in theirs:
		var e: Array = theirs[path]
		var have: Variant = mine.get(path)
		if have == null or String(have[0]) != String(e[0]) or not FileAccess.file_exists("res://" + path):
			todo.append(path)
			_bytes_total += int(e[1])
	var gone: Array[String] = []
	for path: String in mine:
		if not theirs.has(path):
			gone.append(path)

	var game_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var stage := game_dir.get_base_dir().path_join("aggiornamento")
	if DirAccess.dir_exists_absolute(stage):
		_remove_tree(stage)
	DirAccess.make_dir_recursive_absolute(stage)

	_bytes_done = 0
	var i := 0
	for path in todo:
		i += 1
		var dest := stage.path_join(path)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		_cur_size = int(theirs[path][1])
		var url := base + "v%d/" % version + _encode_path(path)
		var ok := false
		for attempt in 3:
			var res := await _fetch(url, dest, i, todo.size())
			if res[0] == OK and FileAccess.get_md5(dest) == String(theirs[path][0]):
				ok = true
				break
		if not ok:
			busy = false
			status.emit("Download non riuscito (%s). Riprova più tardi." % path)
			return
		_bytes_done += _cur_size
	_cur_size = 0
	# Il manifest nuovo per ultimo: se qualcosa va storto la copia resta alla versione vecchia.
	var mf := FileAccess.open(stage.path_join("manifest.json"), FileAccess.WRITE)
	mf.store_string(_remote_text)  # così com'è: JSON.stringify scriverebbe i numeri come 2.0
	mf.close()

	status.emit("Versione %d scaricata: riavvio il gioco…" % version)
	_launch_swap(game_dir, stage, gone)


## Scrive e lancia il .bat che, a gioco chiuso, sostituisce i file e lo riavvia.
func _launch_swap(game_dir: String, stage: String, gone: Array[String]) -> void:
	var win := func(p: String) -> String: return p.replace("/", "\\")
	var pid := OS.get_process_id()
	var lines := PackedStringArray([
		"@echo off",
		"title Aggiornamento Flaminio",
		"echo Aggiorno Flaminio, un attimo...",
		":aspetta",
		"tasklist /FI \"PID eq %d\" 2>nul | find \"%d\" >nul && (timeout /t 1 /nobreak >nul & goto aspetta)" % [pid, pid],
	])
	for path in gone:
		lines.append("del /f /q \"%s\" 2>nul" % win.call(game_dir.path_join(path)))
	lines.append("robocopy \"%s\" \"%s\" /E /MOVE /R:5 /W:1 /NFL /NDL /NJH /NJS /NP >nul" % [win.call(stage), win.call(game_dir)])
	lines.append("rmdir /s /q \"%s\" 2>nul" % win.call(stage))
	lines.append("start \"\" \"%s\" --path \"%s\"" % [win.call(OS.get_executable_path()), win.call(game_dir)])
	lines.append("del \"%~f0\"")
	var bat := game_dir.get_base_dir().path_join("aggiorna_ora.bat")
	var f := FileAccess.open(bat, FileAccess.WRITE)
	f.store_string("\r\n".join(lines) + "\r\n")
	f.close()
	OS.create_process("cmd.exe", ["/c", win.call(bat)])
	get_tree().quit()


func _process(_delta: float) -> void:
	if busy and _req and _cur_size > 0 and _bytes_total > 0:
		var done := _bytes_done + _req.get_downloaded_bytes()
		status.emit("Scarico l'aggiornamento: %.1f / %.1f MB" % [done / 1048576.0, _bytes_total / 1048576.0])


## GET di un URL: in memoria (dest == "") o su file. Restituisce [errore, corpo].
func _fetch(url: String, dest: String, _n := 0, _of := 0) -> Array:
	_req = HTTPRequest.new()
	_req.accept_gzip = false
	_req.timeout = 20.0 if dest == "" else 0.0
	_req.download_file = dest
	add_child(_req)
	var err := _req.request(url)
	if err != OK:
		_req.queue_free()
		_req = null
		return [err, PackedByteArray()]
	var r: Array = await _req.request_completed
	_req.queue_free()
	_req = null
	if r[0] != HTTPRequest.RESULT_SUCCESS or int(r[1]) != 200:
		return [FAILED, PackedByteArray()]
	return [OK, r[3]]


func _encode_path(path: String) -> String:
	var parts := PackedStringArray()
	for p in path.split("/"):
		parts.append(p.uri_encode())
	return "/".join(parts)


func _remove_tree(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(d))
	DirAccess.remove_absolute(dir)
