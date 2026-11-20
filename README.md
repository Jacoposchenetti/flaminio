# Flaminio

Il quartiere Flaminio di Roma (da Piazza del Popolo a Ponte Milvio, dal Tevere ai Parioli, circa 2 × 3,2 km),
esplorabile in terza persona in stile GTA. Godot 4.7, uso personale.

## Giocare

Doppio clic su `Gioca.bat`, oppure `godot --path .`

| Tasto | A piedi | In auto |
|---|---|---|
| WASD | muoversi | accelera, frena/retromarcia, sterza |
| Shift | correre | derapata alla Mario Kart (tieni Shift e sterza; lasciandola, scatto in avanti; joypad B) |
| Ctrl | accovacciarsi | |
| Q | rotolare (mentre ci si muove) | |
| Spazio | saltare (anche per uscire dal Tevere) | freno a mano |
| tasto destro | mirare (sopra la spalla; col cecchino nel cannocchiale) | |
| tasto sinistro | sparare / colpire / lanciare / piazzare | |
| R | ricaricare | |
| Tab (tieni premuto) | rotella delle armi: muovi il mouse verso l'arma e rilascia (tocco veloce = arma successiva); granate, mine e TNT hanno il loro spicchio; da soli il tempo rallenta | |
| 1–7 | scorciatoie: 1 corpo a corpo, 2 pistola, 3 mitragliatrice, 4 fucili, 5 cecchino, 6 lanciarazzi, 7 granate/mine/TNT | |
| B | far saltare le cariche di TNT | |
| E | comprare al bancone di un locale, o dal fornitore | |
| F | salire su un'auto (parcheggiata, o del traffico e dell'autobus: tiri fuori chi guida) | scendere |
| G | | clacson |
| M | mappa grande (rotella zoom, trascina, clic destro = segnalino) | |
| H | tornare al punto di partenza | |
| C | cambiare personaggio | |
| T / Invio | chat | |
| F2 | qualità grafica alta/bassa | |
| F3 | polizia attiva/disattivata (in rete la decide chi ospita) | |

**Joypad** (Xbox o PlayStation): levetta sinistra muoversi (clic L3 = corri), destra camera, LT/L2 mira, RT/R2
spara (in auto gas e freno), A/Croce salta, B/Cerchio capriola, X/Quadrato ricarica, Y/Triangolo auto o monopattino,
LB/L1 accovacciati, RB/R1 (tenuto) rotella delle armi con la levetta destra, R3 clacson, croce su negozio / giù TNT / sinistra ritorno / destra mappa,
Start menu, Back/Share mappa. Menu, negozi e mappa grande si usano col joypad.

**Soldi e crimini**: spaccio (pacchetti dal Fornitore, un personaggio che aspetta in un vialetto del verde: E accanto a
lui; se scappa o muore per 5 minuti non c'è; `Pedestrians.Dealer`; poi E vicino ai passanti), rapine nei locali
(mirare al commesso dietro al bancone: si arrende, scappa lasciando la refurtiva o reagisce; all'armeria reagisce
sempre armato; `Pedestrians.Clerk` in `npc.gd`),
agenti uccisi lasciano arma e colpi, chi viene ucciso da un altro giocatore lascia a terra metà dei soldi.
Si spara anche da auto e monopattini (clic sinistro / LB). Relitti e auto ribaltate spariscono quando non si
guardano. Sulla mappa i luoghi utili sono spilli grandi, il resto puntini sbiaditi. Prove: `--feattest`, `--pvptest`.

**Menu** (Esc, P, Start): riprendi, mappa, comandi, grafica, polizia, personaggio, nome, ritorno, esci
(`scripts/pause_menu.gd`). Da soli mette in pausa; in rete no.

**Indicazioni** (`scripts/navigator.gd`): clic su un luogo della mappa grande → percorso a piedi sulle strade
(grafo del traffico, senza sensi unici), disegnato in blu su entrambe le mappe, con passaggi "Gira a destra in…".

**Veicoli**: auto del traffico rubabili (F vicino a un'auto in movimento: il guidatore viene tirato fuori; in rete
l'auto nasce uguale su tutti i PC), monopattini in sharing sui marciapiedi (`scripts/scooters.gd`), autobus ATAC
nel traffico che si fermano alle fermate (`scripts/bus.gd`). La corsa a piedi è più veloce a mani nude, più lenta
con le armi pesanti.

**Armerie** (armi e munizioni): raggio rosso nel cielo e G rossa sulla mappa; a inizio partita c'è un segnalino
sulla più vicina. Prove automatiche: `--padtest` (joypad, menu, corsa), `--navtest` (indicazioni), `--jacktest`
(furto d'auto), `--scootertest`, `--bustest`, `--escape` (fuga dalla polizia), `--regentest`, `--netjack` (furto in
rete, su chi entra), `--pauseshot=file.png`; tempi di CPU e GPU: `--perf`. Le prove non salvano le impostazioni.

**Vita e soldi**: vita, armatura (giubbotto in armeria) e soldi in alto a destra. Dopo 5 s senza colpi la vita
risale da sola fino a 50; oltre servono bar e farmacie. Le armi da fuoco scariche restano (si ricomprano le munizioni). Si muore per colpi, esplosioni,
cadute da più di ~6 m; si rinasce dopo 5 secondi al punto di partenza perdendo un po' di soldi.
I pedoni colpiti lasciano cadere banconote (verdi a terra: basta passarci sopra).

**Polizia** (stelle in alto a destra, agenti sulla minimappa con puntini rossi e blu): sparare vicino a qualcuno dà
1 stella; uccidere un pedone, distruggere un'auto, colpire o uccidere un agente, usare il lanciarazzi ne danno di più
(fino a 5). Le volanti partono dai presidi veri del quartiere (dati OpenStreetMap): Questura di Roma – Prima Sezione
Volanti, Commissariati Villa Glori e Prati, Scuola Superiore di Polizia (volanti azzurre e bianche, agenti in camicia
azzurra) e Comando Legione Carabinieri Lazio e stazione Carabinieri (auto blu scuro, carabinieri in divisa scura).
Arrivano con sirena e lampeggianti blu seguendo le strade e fanno scendere due agenti; da 3 stelle si aggiungono
pattuglie a piedi già in zona, da 4 alcuni hanno la mitragliatrice. Se nessun agente ti vede, ti cercano dove ti hanno
visto l'ultima volta; restando nascosto le stelle lampeggiano e spariscono dopo 10 s + 4 s per stella; morendo si azzerano. La polizia si può disattivare dal menu o con F3 (meno calcoli).

**Suoni**: tutti sintetizzati da `tools/gen_sounds.py` (nessun file esterno): spari diversi per ogni arma,
esplosioni, razzi, colpi, ricarica, passi, motori che salgono di giri, sirena bitonale, clacson, soldi, città sullo sfondo.

**Locali veri** (`scripts/venues.gd`): bar e caffè, farmacie e supermercati/minimarket (che nel gioco fanno da armerie)
sono presi dai punti reali di OpenStreetMap e distribuiti su tutta la mappa: per ogni tipo si parte dal più vicino alla
partenza e si aggiunge ogni volta quello reale più lontano dagli altri (almeno 220 m tra due bar, 250 tra farmacie,
290 tra armerie), così ogni zona ha i suoi dove esistono davvero (oggi circa 21 bar, 6 farmacie, 12 armerie).
Ognuno è un vano al piano terra del palazzo vero: porta e vetrine aperte nella facciata, insegna col nome reale,
dentro bancone con la cassa, scaffali (bottiglie, scatole, armi appese), tavolini nei bar, luce, e il commesso alla
cassa. Si compra al bancone con E solo se il commesso c'è. Bar: cibo che cura; farmacie: kit medico; armerie: armi,
munizioni, giubbotto. Prove: `--venue=n[,dentro]`, `--dealer`, `--wheel`, `--tnttest`.

**Edifici esplorabili** (segno "E" sulla mappa): sette palazzi veri con porta, scale fino al tetto, finestre aperte
da cui affacciarsi e sparare.

**Città viva**: circa 26 pedoni che passeggiano e scappano quando sentono spari o esplosioni; circa 34 auto del
traffico che seguono le strade vere rispettando i sensi unici; circa 400 auto parcheggiate che si possono guidare.
Le auto si possono distruggere (prendono fuoco ed esplodono).

**Monumenti ricostruiti sulle piante reali**: Palazzetto dello Sport (cupola a costoloni e 36 cavalletti a Y),
Auditorium Parco della Musica (le tre sale "scarabeo" in piombo e la cavea), Stadio Flaminio con la tribuna coperta,
Porta del Popolo, Obelisco Flaminio con le fontane dei leoni, chiese gemelle con le cupole, Mura Aureliane,
Ponte Milvio e gli altri ponti ad arcate, Ponte della Musica con gli archi bianchi, il Tevere tra i muraglioni con le
banchine. Il MAXXI in OSM è mappato solo come tre blocchi: è reso come calcestruzzo con nastri vetrati, non è fedele.

## Giocare con gli amici

1. Tutti installano [Tailscale](https://tailscale.com/download) e stanno nella stessa rete Tailscale.
2. Agli amici si manda `Flaminio_per_amici.zip` (gioco + Godot), creato con
   `powershell -ExecutionPolicy Bypass -File tools\make_package.ps1`. Va ricreato dopo ogni modifica al gioco.
3. Chi ospita preme "Ospita una partita" (il menu mostra il suo indirizzo 100.x.y.z); gli altri lo scrivono e
   premono "Entra". La prima volta Windows chiede il permesso del firewall: consentire.

**Da Internet senza Tailscale**: chi ospita prova ad aprire la porta UDP 7777 sul router con UPnP (in un thread) e
scrive in chat l'indirizzo pubblico; alla chiusura la porta si richiude. Se il router non ha l'UPnP o l'operatore usa
il CGNAT, il gioco lo dice e resta Tailscale. `--upnpcheck` controlla il router senza aprire niente.
Prova grafica di tutte le armi: `--weapontest=cartella [--only=cecchino,bazooka]`.

**Il mondo è condiviso**: tutti vedono gli stessi pedoni, lo stesso traffico, la stessa polizia e gli stessi soldi a
terra. Li calcola il PC di chi ospita (attorno a tutti i giocatori) e li manda agli altri 10 volte al secondo, solo
quelli entro ~380 m da ciascuno; i colpi e gli investimenti sulle copie vengono girati a chi ospita. La polizia
insegue chiunque sia ricercato. Sono condivisi anche giocatori, armi in mano, spari, esplosioni, danni, morti,
auto guidate e distrutte, chat. Unica eccezione: le mine scattano sul PC di chi le vede.
ENet sulla porta UDP 7777, fino a 8 giocatori; non è protetto contro i trucchi. Se chi ospita ha un PC lento,
pedoni e traffico risentono per tutti: conviene che ospiti il PC più potente.

## Novità: elicotteri, jetpack, slot machine, giorno e notte, creativa

- `scripts/heli.gd` (`Heli`, sottoclasse di `Car`): elicotteri pilotabili sulle piazzole `Heli.PADS` (prati aperti,
  alberi tolti; id in rete `Heli.BASE_ID + n`). Volo "arcade" a forze (velocità voluta nella direzione del muso),
  rotore che prende giri, mitragliatrice (`heli_mg`) e razzi verso il centro della camera; distrutti tornano nuovi.
- `Police.PoliceHeli`: a 5 stelle, gira sopra il ricercato con il faro, lo vede da 150 m, raffiche del mitragliere;
  in rete è `NetSync.Kind.POLICE_HELI`.
- Jetpack in `player.gd` (`has_jetpack`, `jet_fuel`, flag in `net_state`), in vendita in armeria.
- `scripts/slot_machine.gd`: slot con rulli veri, premi, luci; i mobili li mette `Venues.build_room` nei bar
  (`room["slots"]`).
- `scripts/day_night.gd`: giornata di 45 minuti; sole/luna, cielo, foschia, global uniform `night` (finestre e
  vetrine in `building.gdshader`), vetro dei lampioni e luci vere sui 22 lampioni più vicini, fari delle auto.
  Ora condivisa da chi ospita (`net_clock`).
- Modalità creativa (solo da soli): menu iniziale o pausa; tutto infinito, K chiama un elicottero.
- Prove: `--hour=22`, `--heli=n`, `--press=azione@t0-t1,...`, `--helishot=t:file.png`, `--wanted=5`, `--god`,
  `--slot=n --slotspin=t`, `--creative`, `--jettest`. Suoni nuovi da `tools/gen_sounds.py` (rotore, jetpack, slot).

## Grafica: cielo, alberi, facciate, MAXXI

- `shaders/sky.gdshader`: cielo disegnato da shader (gradiente, foschia sull'orizzonte, alone del sole, nuvole che
  scorrono e si colorano al tramonto, stelle, luna). I colori li aggiorna `day_night.gd` due volte al secondo (la luce
  del cielo sulla scena si ricalcola a rate, `Sky.PROCESS_MODE_INCREMENTAL`).
- `shaders/lens_flare.gdshader`: riflessi del sole sulla lente; `DayNight._update_flare` lo nasconde se un palazzo o
  un albero copre il sole (raggio fisico ogni 0,1 s).
- `scripts/trees.gd` (`TreeKit`): pino domestico, platano e leccio con tronco, rami e chioma a ciuffi (piani con una
  texture di foglie disegnata all'avvio e salvata in `user://foglie_v1.png`); tre livelli di dettaglio (entro
  `TREE_NEAR`, fino a `NEAR_RANGE`, oltre). Le chiome non fanno ombra: la fa una sagoma piena invisibile
  (`shadow_mesh`), molto più leggera. `shaders/foliage_cards.gdshader`: normale "della chioma", controluce, vento.
- `shaders/building.gdshader`: intonaco invecchiato (macchie, rappezzi, umidità, sporco sotto il cornicione, colature
  sotto i davanzali) e stanze finte dietro i vetri (interior mapping: pareti, parquet, soffitto, mobili; di notte
  accese).
- `landmarks.gd` → `_maxxi()`: il MAXXI di Zaha Hadid fatto a mano (nastri curvi di cemento, galleria a sbalzo con
  vetrata nera, travi sul tetto); i palazzi generici del suo lotto non vengono costruiti (`in_maxxi`).

## Botte, guida, furti, viadotti

- **Passanti colpiti** (`npc.gd`, `Pedestrian._react`): barcollano (si girano verso il colpo, testa o petto), a una
  mazzata o al terzo pugno vanno a terra e si rialzano (caduta all'indietro, `Human.play_getup`); circa un uomo su
  tre (`fighter`) risponde a pugni finché non scappi o passano 20 s. I commessi hanno la loro reazione (rapina).
  In rete le copie ricevono `hit_head`, `knock`, `getup`, `punch` (una volta per cambio).
- **Guida** (`car.gd`, `_handling`): imbardata e scivolamento decisi dal gioco (impulsi), con fisica vera sotto.
  Un colpo di sterzo resta in una curva sicura (`LAT_MAX`); tenendo lo sterzo a fondo l'angolo cresce fino al
  massimo (sterzata brusca). Oltre l'aderenza delle gomme (`grip_lat`) il muso smette di girare e l'auto scivola
  fuori; oltre la soglia di ribaltamento (`tip_lat`, che cala con la velocità: SUV 9,5, auto 12, sportive 16,
  autobus 5,5 m/s²) le ruote interne si sollevano e, esagerando, ci si cappotta. In città a tutto sterzo ci si
  inclina e si scivola; a 100 km/h si rotola. **Derapata alla Mario Kart** con Shift (joypad B): si entra nel
  verso in cui si sterza, la velocità si conserva, il retro scivola fuori di ~20-30°, sterzo nello stesso verso =
  curva stretta, opposto = larga; lasciando Shift dopo più di 0,6 s spinta (mini-turbo). Anche in derapata, troppo
  stretta e troppo veloce, si rischia di ribaltarsi (soprattutto all'uscita, quando le gomme riprendono). Non
  assegnare `linear_velocity` a un VehicleBody: annulla la spinta del motore. Prove: `--drive=go --hilltest=x,z,gradi
  --press=move_left@t0-t1,sprint@t0-t1 [--v0=km/h]` (stampa velocità, traverso, rotazione, inclinazione, rischio).
  Suoni nuovi in `gen_sounds.py`: `skid`, `door_open`, `door_close`.
- **Autobus rubabili**: dal traffico come le auto; diventano `Car` con `_setup_bus` (11 t, ~72 km/h, niente
  derapata, camera più alta e lontana). Si entra dalla porta anteriore.
- **Salire in auto** (`carjack.gd`, `CarJack`): va alla portiera, la apre, tira fuori chi guida (cade, si rialza,
  scappa), sale e richiude (~1,6 s; `Player.cutscene`). Le portiere sono pannelli aggiunti per la scena.
- **Corso di Francia**: corsie e marciapiedi paralleli di uno stesso viadotto legati di traverso nel calcolo delle
  quote (`convert_osm.py`, le rampe strette restano libere); impalcati in calcestruzzo e piloni ogni 24 m dove
  sono alti da terra e non c'è una strada sotto (`city_builder.gd`).
- Prove: `--punchtest [--pshots=cartella]` (pugni, a terra, rialzo, risposta), `--furtotest[=bus] [--pshots=…]`
  (furto con le foto delle fasi, poi gas), `--pos=x,z,quota` (terzo numero facoltativo: quota assoluta).

## Case

- `scripts/homes.gd` (`Homes`): 16 case scelte nei palazzi veri (due per zona, portone sul lato verso la strada),
  tipi e prezzi (`TYPES`, `ZONE_PRICE`), interni costruiti al volo DEPTH metri sotto il portone (solo sul PC di chi
  entra), mobili procedurali (`FURNITURE`, `make_furniture`, livello di collisione `FURN_LAYER` per cliccarli),
  cassaforte, armadio, letto, salvataggio in `user://case.json`.
- `scripts/home_ui.gd`: portone (compra, visita, entra, vendi), cassaforte, arredamento con vista dall'alto.
- Prova: `--hometest=attico --shotdir=CARTELLA`.

## Banche, missioni, sicari

- `scripts/banks.gd` (`Banks`): filiali nei punti OSM delle banche (insegne inventate, `Banks.BRANDS`); arredo in
  `Banks.furnish` (chiamato da `Venues.build_room`, stanza 14 m); su chi ospita impiegati e direttore
  (`Pedestrians.Clerk`), vigilanti (`Gunman`, in rete `Kind.GANG`), allarme, caveau (ostaggio, trapano, TNT via
  `Combat.exploded`), sacchi, chiusura per indagini; stato a tutti con `net_bank`. Conto corrente: `BankUI`,
  `main.bank_balance` nelle impostazioni.
- `scripts/gunman.gd`: personaggio armato generico (vigilanti, nemici delle missioni).
- `scripts/missions.gd`: contatti e missioni a fasi (locali al PC di chi le fa), banner, obiettivo, timer.
- Sicari in `clans.gd` (`hitmen` di ogni clan, `hit_price`, `contracts`, `on_player_killed`) e nel pannello U.
- Prove: `--banktest=n`, `--drilltest`, `--mission=festa|crediti`, `--hittest=Nome` (su chi ospita).

## Malavita: spaccio, fama, clan

- `scripts/crime.gd` (`Crime`): droghe (prezzi, domanda, rischio), livelli di fama, zone del quartiere (Voronoi
  sui centri `ZONES`), clan iniziali (`NPC_CLANS`, nomi e boss inventati tranne la Banda della Magliana storica)
  e rapporti tra loro.
- `scripts/clans.gd` (`Clans`): stato dei clan su chi ospita (salvato in `user://clans.json`, copia agli altri con
  `net_clan_state`), richieste dei giocatori (`request`), rabbia, squadre, rinforzi, spacciatori al soldo, entrate
  delle zone, conquiste, guerre tra clan, blitz della DDA. `Clans.Soldier`: boss, guardie, squadre, rinforzi
  (in rete `NetSync.Kind.GANG`).
- `scripts/clan_ui.gd`: pannello (U) e dialogo col boss (E). La fama la tiene ogni PC nelle impostazioni.
- Prove: `--boss=n`, `--clantest`, `--clantest2`, `--threattest` (minacce dei clan, boss scoperti, vita dell'elicottero).

## Come è fatto

- `tools/fetch_osm.py` scarica i dati OpenStreetMap (Overpass, con più server di riserva); `tools/convert_osm.py`
  li converte: edifici e parti di edificio, strade (con sensi unici), aree, alberi, monumenti, mura, ponti, luoghi
  e nomi delle vie per la mappa, rilievo del Tevere con muraglioni e banchine, minimappa.
- `scripts/city_builder.gd`: terreno, strade, palazzi, cupole delle chiese, alberi, posti auto.
- `scripts/landmarks.gd`: monumenti su misura; `scripts/interiors.gd`: palazzi esplorabili.
- `scripts/player.gd` (movimento, vita, armi), `scripts/human.gd` (corpi, vestiti, animazioni),
  `scripts/weapons.gd` (catalogo armi), `scripts/combat.gd` (colpi, proiettili, esplosivi, effetti),
  `scripts/npc.gd` (pedoni), `scripts/traffic.gd` (traffico), `scripts/car.gd` (auto guidabili),
  `scripts/shops.gd` (negozi), `scripts/police.gd` (ricercato e polizia), `scripts/sfx.gd` (suoni),
  `scripts/netsync.gd` (mondo condiviso in rete), `scripts/hud.gd` (interfaccia), `scripts/map_view.gd` (minimappa e mappa grande).

Prove automatiche (aprono una finestra): `--capture=file.png --frames=n`, `--shots=elenco.txt` (giro di
inquadrature), `--fight`, `--cops`, `--stairs=n`, `--shop=n`, `--inside=edificio,piano`, `--lineup`, `--bigmap=zoom`.

## Crediti

- Mappa © OpenStreetMap contributors (ODbL).
- Rilievo: LiDAR DTM 1 m Regione Lazio, Piano Straordinario di Telerilevamento, Ministero dell'Ambiente e della
  Sicurezza Energetica (open data); dove manca, TINITALY/1.1, Tarquini S. et al., INGV,
  https://doi.org/10.13127/tinitaly/1.1 (CC BY 4.0).
- Coperture del suolo (prati e alberi che OSM non ha): ESA WorldCover 10 m 2021 v200, Zanaga D. et al.,
  https://doi.org/10.5281/zenodo.7254221 (CC BY 4.0).
- Personaggi e animazioni: Universal Base Characters e Universal Animation Library di Quaternius (CC0).
- Auto e armi: Quaternius e altri autori CC0, scaricati da Poly Pizza.
- Texture: ambientCG (CC0).

## Prossimi passi possibili

Vestiti veri al posto di quelli dipinti, giorno e notte, MAXXI modellato a mano.

## Aggiornamenti per gli amici

Il menu iniziale mostra la versione e un pulsante **Aggiorna**: il gioco legge `manifest.json` (versione + MD5 di
ogni file) dal ramo `aggiornamenti` del repository GitHub, scarica dal tag `vN` solo i file cambiati nella cartella
`aggiornamento` accanto al gioco, li controlla, poi si chiude e un piccolo `.bat` li mette al loro posto e riavvia.
La copia di sviluppo (senza `manifest.json`) non si aggiorna mai da sola.

- **In automatico**: l'attività pianificata di Windows "Flaminio - pubblica aggiornamenti" lancia ogni 30 minuti
  `pythonw tools/pubblica_aggiornamento.py --auto`, che pubblica da solo solo se il gioco è cambiato, se da 20 minuti
  nessuno tocca i file (così non esce un lavoro a metà) e se il gioco parte senza errori negli script. Cosa fa (e
  perché non pubblica) è in `tools/pubblica_auto.log`. Per spegnerla: `schtasks /Change /TN "Flaminio - pubblica aggiornamenti" /DISABLE`.
- A mano, subito: `python tools/pubblica_aggiornamento.py` (versione +1 in `tools/versione.txt`).
- Prova in locale: `python tools/pubblica_aggiornamento.py --locale CARTELLA`, poi `python -m http.server` in quella
  cartella e il gioco con `-- --update-url=http://127.0.0.1:8000/` (`--autoupdate` aggiorna senza clic,
  `--menushot=file.png` salva la schermata del menu).
- Lo zip completo (`tools/make_package.ps1`) porta la versione di `tools/versione.txt`.

## Rilievo vero (salite e discese)

Il quartiere ha le quote vere, prese dal **LiDAR della Regione Lazio** (DTM a 1 m, terreno nudo, volo 2014 del
Piano Straordinario di Telerilevamento del MASE, open data). Le tessere si scaricano dalla Banca Dati PST
(https://sim.mase.gov.it/pst/, LiDAR Lazio, dtm 1x1) e si importano con
`python tools/import_lidar.py CARTELLA_CON_I_TIFF` (→ `data/dem/lidar_dtm.npy`). Dove il volo non arriva (una
striscia a sud-est, verso Villa Borghese) si usa il TINITALY dell'INGV a 10 m (`tools/fetch_dem.py`), allineato al
LiDAR sul bordo. `convert_osm.py` lo porta sulla griglia del gioco (celle di 2 m, quota zero = il lungotevere) e lo
tratta come un progetto stradale:

1. **Profilo verticale di tutta la rete stradale insieme** (minimi quadrati sparsi, `_solve_profiles`): ogni 2 m
   la quota misurata, niente gobbe sotto i ~20-30 m, incroci in piano perché i nodi sono condivisi, pendenza delle
   carreggiate al massimo 16%. Seconda passata robusta (dossi isolati contano meno).
2. **Ponti e viadotti** dritti tra i loro attacchi a terra (i marciapiedi di un viadotto prendono la quota della
   carreggiata accanto); le quote ai vertici vanno in `city.json` (`"y"`) e le usano impalcati, parapetti e
   traffico. Sotto i ponti il terreno si ricostruisce dai lati (il LiDAR a volte tiene il viadotto come terrapieno).
3. Carreggiate e marciapiedi in piano in larghezza alla quota del profilo, raccordati al terreno; piazze e campi
   in piano; ogni palazzo su un piano alla quota della strada carrabile più vicina (se è allo stesso livello).
4. Entro 30 m dal Tevere quota zero (muraglioni e banchine del gioco), poi in 60 m il terreno vero.

In gioco `surface_at()` è la quota su cui si cammina e si guida, `carve_at()` quanto scava il fiume,
`ground_basis()` inclina auto e autobus, `mesh_top_at()` la quota della maglia del terreno com'è disegnata (vertici
ogni ~4 m): strade, vialetti e cordoli non scendono mai sotto, nemmeno ai bordi. Prati, boschi e campi non sono
più superfici a parte: li disegna lo shader del terreno da `data/cover_png.bin` (PNG a 1 m per pixel), così
seguono il rilievo senza buchi. Scarpate: prato oltre il ~30%, muri di contenimento in tufo quasi in verticale
(nei parchi solo oltre ~60°). I locali si aprono solo dove la porta è a livello del marciapiede.

Il terreno è disegnato a blocchi di 128 m: vicino (entro 380 m) un vertice ogni 2 m, la stessa maglia della
collisione, così i piedi non affondano; lontano uno ogni 8 m.

Prati e alberi che OpenStreetMap non ha (aiuole, cortili, scarpate, filari) vengono dalla carta satellitare
**ESA WorldCover** a 10 m: `python tools/fetch_worldcover.py` ne legge dal file pubblico su AWS solo i riquadri di
Flaminio (→ `data/dem/worldcover.npy`). `convert_osm.py` ne fa prato (strade con marciapiedi, piazze e palazzi
restano liberi, i ritagli piccoli spariscono) e mette un albero per cella "alberi" dove non ce n'è già uno vicino;
le aree di OSM vanno sopra, più precise. `--senza-worldcover` per spegnerla.

Per tornare in piano: `convert_osm.py ... --piano`. Prova in salita: `--hilltest=x,z,gradi --drive=go`.
Diagnostica: `RILIEVO_DEBUG=file.npz` salva terreno e profili stradali.
