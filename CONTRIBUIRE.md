# Lavorare su Flaminio e pubblicare aggiornamenti

Il codice sorgente sta nel ramo `main` di questo repository. Il ramo `aggiornamenti` e i tag `v1`, `v2`, …
contengono invece il gioco pronto: li scrive solo lo script di pubblicazione, **non vanno toccati a mano**.
Da lì i PC dove è installato il gioco (e il server sul telefono) scaricano gli aggiornamenti col pulsante "Aggiorna".

## Una volta sola

1. Installa:
   - [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) (versione standard, non .NET);
   - [Git](https://git-scm.com/download/win);
   - [Python 3](https://www.python.org/downloads/) (spunta "Add python.exe to PATH").
2. Di' a Git chi sei (comparirà sui tuoi commit e sulle versioni che pubblichi):
   ```
   git config --global user.name "IlTuoNomeGitHub"
   git config --global user.email "IlTuoNomeGitHub@users.noreply.github.com"
   ```
3. Scarica il progetto:
   ```
   git clone https://github.com/Jacoposchenetti/flaminio.git Flaminio
   ```
4. Indica allo script dove sta Godot (adatta il percorso):
   ```
   setx FLAMINIO_GODOT "C:\Programmi\Godot\Godot_v4.7.2-stable_win64_console.exe"
   ```
5. Apri il progetto una prima volta in Godot (oppure `godot --headless --path Flaminio --import`): rigenera
   la cartella `.godot`, che non sta su GitHub.

## Ogni volta

1. Prima di cominciare, prendi le ultime modifiche: `git pull --rebase`
2. Lavora, prova il gioco (`godot --path .`; le opzioni di prova sono nel `README.md`).
3. Pubblica:
   ```
   python tools/pubblica_aggiornamento.py
   ```
   Lo script fa tutto da solo, nell'ordine:
   - salva le tue modifiche in un commit, ci mette sotto quelle arrivate dagli altri e carica tutto su `main`;
   - prepara il gioco e lo pubblica come versione successiva (ramo `aggiornamenti` + tag `vN`).

   Se le tue modifiche toccano le stesse righe di quelle di qualcun altro si ferma senza pubblicare niente:
   risolvi con `git pull --rebase` (Git indica i file in conflitto), poi rilancia.

Se vuoi solo condividere il codice senza pubblicare una versione: `git add -A`, `git commit -m "..."`,
`git pull --rebase`, `git push`.

## Cose da sapere

- **Una versione pubblicata arriva subito su tutti i PC del gioco.** Prima di pubblicare, avvia il gioco e
  controlla che parta senza errori.
- Il PC di Jacopo pubblica anche da solo ogni mezz'ora se ci sono modifiche ferme da 20 minuti, sempre passando
  da `main`: il tuo lavoro non viene sovrascritto.
- Non si pubblicano chiavi o password: `tools/google_key.txt` e `tools/mapillary_token.txt` sono esclusi
  (`.gitignore`). Gli script che scaricano foto (`fetch_streetview.py`, `fetch_facciate.py`) senza chiave
  non servono: i colori sono già in `locale/` e `data/`.
- Godot 4.7: niente funzioni chiamate `_enter_world`. Altre insidie note nel `CLAUDE.md`.
