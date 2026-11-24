# Flaminio

Il quartiere Flaminio di Roma (da Piazza del Popolo a Ponte Milvio, dal Tevere ai Parioli, circa
2 × 3,2 km) costruito a runtime da OpenStreetMap ed esplorabile in terza persona in stile GTA.
Multigiocatore con gli amici via Tailscale. Godot 4.7, GDScript. **Uso personale, non per Steam**
(il gioco per Steam è `../MioGioco`).

L'utente vuole una **ricostruzione fedele** dei luoghi reali e meccaniche alla GTA.
`README.md` è il manuale del giocatore: comandi, funzioni e tutte le opzioni di prova `--xxx`.

## Navigare il codice

C'è un grafo graphify (`graphify-out/`). Per domande sul codice usare prima
`graphify query "<domanda>"`, poi aprire solo i file indicati. Dopo modifiche al codice:
`graphify update .`

## Struttura

- `project.godot`, `scenes/`, `shaders/`
- `scripts/`: un modulo per sistema. Tra i principali:
  - `main.gd`: API `world` condivisa (`players()`, `anchors()`, `crime()`, `award()`, `register()`)
  - `city_builder.gd`: edifici, strade, ponti
  - `landmarks.gd`, `interiors.gd`, `venues.gd`: luoghi costruiti a mano, interni, bar, farmacie
    e armerie ricavati da POI OSM reali
  - `netsync.gd`: rete; l'host simula pedoni, traffico e polizia per tutti
  - `npc.gd`, `police.gd`, `car.gd`, `bus.gd`, `scooters.gd`, `heli.gd`, `combat.gd`
  - `crime.gd`, `clans.gd`, `banks.gd`, `missions.gd`, `homes.gd` (malavita, banche, missioni, case)
  - `navigator.gd`, `map_view.gd`, `hud.gd`, `pause_menu.gd`, `weapon_wheel.gd`, `day_night.gd`
  - `updater.gd`: aggiornamento automatico dal menu iniziale
- `data/`: `city.json` (dati OSM convertiti; i POI hanno il sottotipo all'indice [5]), `dem/`
  (rilievo: LiDAR 1 m MASE + TINITALY, WorldCover per prati e alberi; `lidar_dtm.npy` non viene
  distribuito)
- `locale/`: colori delle facciate da Google Street View (`colori_streetview.json`, da
  `tools/fetch_streetview.py`, chiave in `tools/google_key.txt`). Pubblicato anche questo per scelta dell'utente
  (gli "amici" sono suoi PC in altre case). Mapillary: `tools/fetch_facciate.py` → `data/colori_facciate.json`.
  Ogni file di `data/` che il gioco legge va aggiunto a `DATA` in `tools/stage.py`, altrimenti non viene pubblicato.
- `assets/`: modelli (Quaternius, Poly Pizza, ambientCG; tutti CC0), suoni sintetizzati
- `tools/`: script Python di conversione OSM (`convert_osm`), `import_lidar.py`,
  `fetch_worldcover.py`, `gen_sounds.py`, `make_package.ps1` (zip per gli amici, include
  `LEGGIMI.txt`), `pubblica_aggiornamento.py`, `server/` (server headless su telefono Android)

## Comandi

- Giocare: `Gioca.bat` oppure `godot --path .`
- Dopo aver aggiunto una nuova `class_name`: `godot --headless --path . --import`
- Nel Bash tool `godot` non è nel PATH: usare l'eseguibile console sotto i pacchetti WinGet.
- Prove automatiche: le opzioni `--xxxtest` e `--shots=` elencate in `README.md` (le prove non
  salvano le impostazioni). Rilievo piatto: `--piano`.

## Pubblicazione

- Repo pubblico `github.com/Jacoposchenetti/flaminio`. Il branch `aggiornamenti` e i tag `vN`
  contengono il gioco pronto e `manifest.json` (MD5 per file).
- Il sorgente è nel ramo `main` dello stesso repo (questa cartella è un clone git). Anche Sestiano (collaboratore
  con permesso di scrittura, voluto dall'utente) pubblica: guida in `CONTRIBUIRE.md`.
- `python tools/pubblica_aggiornamento.py` prima allinea il sorgente a `main` (commit delle modifiche locali,
  rebase su origin/main, push; se c'è conflitto non pubblica), poi aumenta `tools/versione.txt` e pubblica.
  Commit su `main` in inglese.
- Un'attività pianificata di Windows ("Flaminio - pubblica aggiornamenti") esegue `--auto` ogni
  30 minuti. Pubblica solo se ci sono modifiche ferme da 20 minuti e senza errori negli script;
  log in `tools/pubblica_auto.log`. **Ogni modifica salvata può quindi arrivare agli amici.**
- Server dedicato su un Galaxy A52s (Termux + proot Debian + Godot linux arm64). Dettagli in
  `tools/server/`.

## Insidie note

- Godot 4.7 ha un metodo virtuale `_enter_world` su Node3D: non chiamare così le funzioni.
- SDFGI sbianca la scena: tenerlo spento.
- Migliaia di shape su un solo corpo fisico sono lentissime: usare un corpo per chunk.
- Scritture Python su Windows: aprire con `newline=''` per non convertire LF in CRLF.
  PowerShell `Set-Content` aggiunge il BOM ai `.gd`: non usarlo.
- `Input.action_press` non genera InputEvent: i test di `_input` della UI vanno fatti con
  chiamate dirette.
- AnimatableBody: impostare `global_transform` in un colpo solo.
- Non usare `height_at < 0` per riconoscere il fiume.
- Le prestazioni su questo portatile (Intel Arc) variano tra 30 e 60 fps a seconda dello stato
  della macchina. Prima di dare la colpa a una modifica, confrontare con la copia pubblicata in
  `%LOCALAPPDATA%\Flaminio_aggiornamenti`.
- `tools/.gdignore` deve restare: senza, Godot importa le migliaia di foto in `tools/cache_*` dentro
  `.godot/imported` e la pubblicazione le spedisce (successo con la v11: 7600 file, 1 GB).
- Overpass risponde spesso 502: lo script di download prova più mirror.
- Clan reali: si usano nomi inventati (più la storica Banda della Magliana).

## Cartelle collegate

- `../Flaminio_copia_17nov`: backup del 17 novembre, da non modificare.
- `../Flaminio_per_amici.zip`: pacchetto v1 per gli amici.
