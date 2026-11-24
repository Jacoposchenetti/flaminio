#!/bin/bash
# Server di Flaminio sul telefono (dentro Debian di Termux). Lo lancia Termux:Boot all'accensione.
# Prima di ogni avvio scarica l'ultima versione pubblicata (ramo "aggiornamenti" del repository GitHub);
# se il gioco si chiude (crash, o perché è uscita una versione nuova e non c'era nessuno), riparte da solo.
GAME="$HOME/flaminio"
GODOT="$HOME/godot/godot"
REPO="https://github.com/Jacoposchenetti/flaminio.git"
LOG="$HOME/flaminio-server.log"
cd "$HOME"
while true; do
	if [ -d "$GAME/.git" ]; then
		git -C "$GAME" fetch --depth 1 origin aggiornamenti >>"$LOG" 2>&1 && git -C "$GAME" reset --hard FETCH_HEAD >>"$LOG" 2>&1
	else
		git clone --depth 1 --branch aggiornamenti "$REPO" "$GAME" >>"$LOG" 2>&1
	fi
	echo "$(date) avvio del server (versione $(grep -o '"version":[0-9]*' "$GAME/manifest.json"))" >>"$LOG"
	"$GODOT" --headless --path "$GAME" -- --server >>"$LOG" 2>&1
	echo "$(date) il server si è chiuso (codice $?), riparto tra 10 secondi" >>"$LOG"
	tail -c 2000000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"  # il registro non cresce all'infinito
	sleep 10
done
