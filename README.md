# Flaminio

Il quartiere Flaminio di Roma (da Piazza del Popolo a Ponte Milvio, dal Tevere ai Parioli, circa 2 × 3,2 km),
esplorabile in terza persona in stile GTA. Godot 4.7, uso personale.

## Giocare

Doppio clic su `Gioca.bat`, oppure `godot --path .`

| Tasto | A piedi | In auto |
|---|---|---|
| WASD | muoversi | accelera, frena/retromarcia, sterza |
| Shift | correre | |
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
| F | salire su un'auto parcheggiata | scendere |
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
- Personaggi e animazioni: Universal Base Characters e Universal Animation Library di Quaternius (CC0).
- Auto e armi: Quaternius e altri autori CC0, scaricati da Poly Pizza.
- Texture: ambientCG (CC0).

## Prossimi passi possibili

Vestiti veri al posto di quelli dipinti, giorno e notte,
rilievo reale di Parioli e Villa Glori, MAXXI modellato a mano.

## Aggiornamenti per gli amici

Il menu iniziale mostra la versione e un pulsante **Aggiorna**: il gioco legge `manifest.json` (versione + MD5 di
ogni file) dal ramo `aggiornamenti` del repository GitHub, scarica dal tag `vN` solo i file cambiati nella cartella
`aggiornamento` accanto al gioco, li controlla, poi si chiude e un piccolo `.bat` li mette al loro posto e riavvia.
La copia di sviluppo (senza `manifest.json`) non si aggiorna mai da sola.

- Pubblicare una versione nuova: `python tools/pubblica_aggiornamento.py` (versione +1 in `tools/versione.txt`).
- Prova in locale: `python tools/pubblica_aggiornamento.py --locale CARTELLA`, poi `python -m http.server` in quella
  cartella e il gioco con `-- --update-url=http://127.0.0.1:8000/` (`--autoupdate` aggiorna senza clic,
  `--menushot=file.png` salva la schermata del menu).
- Lo zip completo (`tools/make_package.ps1`) porta la versione di `tools/versione.txt`.
