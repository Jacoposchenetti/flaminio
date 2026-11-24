"""Pubblica una nuova versione del gioco: gli amici la scaricano dal menu iniziale col pulsante "Aggiorna".

Uso (dalla cartella del progetto):
    python tools/pubblica_aggiornamento.py            pubblica su GitHub (versione +1)
    python tools/pubblica_aggiornamento.py --locale D prova: scrive in D come se fosse GitHub (senza git)
    pythonw tools/pubblica_aggiornamento.py --auto    da solo (attività pianificata di Windows, ogni ora):
        pubblica solo se il gioco è cambiato, se da 20 minuti nessuno tocca i file (lavoro finito, non a metà)
        e se il gioco parte senza errori negli script. Scrive cosa fa in tools/pubblica_auto.log.

Come funziona: i file del gioco vanno nel ramo "aggiornamenti" del repository GitHub (REPO qui sotto) con un
manifest.json (versione + MD5 di ogni file) e un tag vN. Il gioco legge il manifest dal ramo e scarica dal tag
solo i file cambiati. Il numero di versione è in tools/versione.txt (lo usa anche make_package.ps1 per lo zip).
"""
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stage import ROOT, stage  # noqa: E402

REPO = "Jacoposchenetti/flaminio"
BRANCH = "aggiornamenti"
SRC_BRANCH = "main"  # codice sorgente condiviso: chi pubblica parte sempre da qui (vedi CONTRIBUIRE.md)
VERSION_FILE = os.path.join(ROOT, "tools", "versione.txt")
CLONE = os.path.join(os.environ.get("LOCALAPPDATA", ROOT), "Flaminio_aggiornamenti")
# Godot: variabile FLAMINIO_GODOT, altrimenti lo shim di Jacopo, altrimenti "godot" nel PATH.
GODOT = os.environ.get("FLAMINIO_GODOT") or (
    os.path.expandvars(r"%USERPROFILE%\bin\godot.cmd")
    if os.path.exists(os.path.expandvars(r"%USERPROFILE%\bin\godot.cmd")) else shutil.which("godot") or "godot")
LOG = os.path.join(ROOT, "tools", "pubblica_auto.log")
QUIET_MIN = 20  # minuti senza modifiche prima di pubblicare da solo
SOURCES = ["project.godot", "scenes", "scripts", "shaders", "assets", "data", "locale", "README.md"]
SEEN = os.path.join(CLONE, "ultimo_controllo.txt")  # data dell'ultima modifica già controllata
NOWIN = getattr(subprocess, "CREATE_NO_WINDOW", 0)  # niente finestre nere quando gira da solo
AUTO = "--auto" in sys.argv


def say(text: str) -> None:
    if AUTO:
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(time.strftime("%Y-%m-%d %H:%M  ") + text + "\n")
    else:
        print(text)


def run(cmd, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, text=True, capture_output=True, creationflags=NOWIN, **kw)


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    return run(["git", "-C", CLONE, *args], check=check)


def src(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    return run(["git", "-C", ROOT, *args], check=check)


def sync_source() -> bool:
    """Allinea questa copia al codice condiviso su GitHub (ramo main) prima di pubblicare.

    Salva le modifiche locali in un commit, mette sopra quelle arrivate dagli altri e ricarica tutto su main.
    Così una versione pubblicata contiene il lavoro di tutti e nessuno cancella quello dell'altro.
    Restituisce False (e non si pubblica) se manca la rete o se le modifiche sono in conflitto."""
    if not os.path.exists(os.path.join(ROOT, ".git")):
        say("NON pubblico: questa copia non è collegata a GitHub (manca .git). Vedi CONTRIBUIRE.md.")
        return False
    src("add", "-A")
    if src("diff", "--cached", "--quiet", check=False).returncode != 0:
        src("commit", "-q", "-m", "Work in progress from %s" % platform.node())
    if src("fetch", "-q", "origin", SRC_BRANCH, check=False).returncode != 0:
        say("NON pubblico: non riesco a scaricare il codice da GitHub (sei collegato a Internet?)")
        return False
    if src("rebase", "-q", "origin/" + SRC_BRANCH, check=False).returncode != 0:
        src("rebase", "--abort", check=False)
        say("NON pubblico: le tue modifiche toccano le stesse righe di quelle arrivate su main. "
            "Risolvi con 'git pull --rebase' e riprova.")
        return False
    push = src("push", "-q", "origin", "HEAD:" + SRC_BRANCH, check=False)
    if push.returncode != 0:
        say("NON pubblico: non riesco a caricare il codice su main: " + push.stderr.strip()[-300:])
        return False
    return True


def newest_change() -> float:
    t = 0.0
    for item in SOURCES:
        p = os.path.join(ROOT, item)
        if os.path.isfile(p):
            t = max(t, os.path.getmtime(p))
        for dirpath, _d, names in os.walk(p):
            for n in names:
                t = max(t, os.path.getmtime(os.path.join(dirpath, n)))
    return t


def changed_since_last() -> bool:
    old = os.path.join(CLONE, "manifest.json")
    if not os.path.exists(old):
        return True
    with tempfile.TemporaryDirectory() as tmp:
        new = stage(os.path.join(tmp, "g"), 0)["files"]
    return new != json.load(open(old, encoding="utf-8"))["files"]


def script_errors() -> list:
    """Avvia il gioco senza finestra per qualche secondo e raccoglie gli errori degli script."""
    try:
        r = run([GODOT, "--headless", "--path", ROOT, "--quit-after", "300"], timeout=300)
        out = r.stdout + r.stderr
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode(errors="ignore") if isinstance(e.stdout, bytes) else (e.stdout or "")
    return [ln.strip() for ln in out.splitlines() if "SCRIPT ERROR" in ln or "Parse Error" in ln][:5]


def clear(folder: str) -> None:
    for n in os.listdir(folder):
        if n == ".git":
            continue
        p = os.path.join(folder, n)
        if os.path.isdir(p):
            shutil.rmtree(p)
        else:
            os.remove(p)


def main() -> None:
    version = int(open(VERSION_FILE).read().strip()) + 1
    if AUTO:
        # Giro normale: guarda solo le date dei file (una frazione di secondo) ed esce se niente è cambiato.
        newest = newest_change()
        seen = open(SEEN).read().strip() if os.path.exists(SEEN) else ""
        if seen == repr(newest):
            return
        if (time.time() - newest) / 60 < QUIET_MIN:
            return  # si sta ancora lavorando: riprovo al prossimo giro
        os.makedirs(CLONE, exist_ok=True)
        with open(SEEN, "w") as fh:
            fh.write(repr(newest))
    if "--locale" not in sys.argv and not sync_source():
        sys.exit(1)
    print("Reimporto le risorse (godot --import)...") if not AUTO else None
    run([GODOT, "--headless", "--path", ROOT, "--import"])
    if AUTO:
        if not changed_since_last():
            return
        errs = script_errors()
        if errs:
            say("NON pubblico: il gioco ha errori negli script -> " + " | ".join(errs))
            return

    if "--locale" in sys.argv:
        out = sys.argv[sys.argv.index("--locale") + 1]
        for sub in (BRANCH, "v%d" % version):
            d = os.path.join(out, sub)
            if os.path.exists(d):
                shutil.rmtree(d)
            m = stage(d, version)
        print("Prova locale: versione %d (%d file) in %s" % (version, len(m["files"]), out))
        print("Avvia il gioco con:  -- --update-url=http://127.0.0.1:8000/  (python -m http.server nella cartella)")
        return

    if not os.path.exists(os.path.join(CLONE, ".git")):
        os.makedirs(CLONE, exist_ok=True)
        run(["git", "init", "-q", "-b", BRANCH, CLONE], check=True)
        git("remote", "add", "origin", "https://github.com/%s.git" % REPO)
    # La versione porta il nome di chi la pubblica (lo stesso dei suoi commit su main).
    for key in ("user.name", "user.email"):
        value = src("config", key, check=False).stdout.strip()
        if value:
            git("config", key, value)
    # Sempre allineati a GitHub prima di aggiungere una versione (mai su una copia rimasta indietro).
    first = git("ls-remote", "--exit-code", "--heads", "origin", BRANCH, check=False).returncode != 0
    if not first:
        git("fetch", "-q", "--tags", "--force", "origin", BRANCH)
        git("checkout", "-q", "-B", BRANCH, "origin/" + BRANCH)
        git("reset", "-q", "--hard", "origin/" + BRANCH)
        # Numero di versione: dopo l'ultima pubblicata davvero (il manifest del ramo), saltando etichette rimaste.
        published = json.loads(git("show", "origin/%s:manifest.json" % BRANCH).stdout)["version"]
        version = max(version, int(published) + 1)
        tags = set(git("tag", "-l", "v*").stdout.split())
        while "v%d" % version in tags:
            version += 1
    else:
        version -= 1  # prima pubblicazione: è la stessa versione dello zip già mandato agli amici
    clear(CLONE)
    m = stage(CLONE, version)
    git("add", "-A")
    git("commit", "-q", "-m", "Versione %d" % version)
    git("tag", "v%d" % version)
    say("Carico la versione %d (%d file) su GitHub..." % (version, len(m["files"])))
    push = git("push", "--atomic", "origin", BRANCH, "v%d" % version, check=False)
    if push.returncode != 0:
        git("tag", "-d", "v%d" % version, check=False)
        if not first:
            git("reset", "-q", "--hard", "origin/" + BRANCH, check=False)
        say("Caricamento non riuscito, versione non pubblicata: " + push.stderr.strip()[-300:])
        sys.exit(1)
    with open(VERSION_FILE, "w") as fh:
        fh.write("%d\n" % version)
    say("Fatto: versione %d pubblicata. Gli amici la trovano nel menu iniziale (\"Aggiorna\")." % version)


if __name__ == "__main__":
    main()
