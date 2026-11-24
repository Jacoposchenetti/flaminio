"""Copia i file del gioco per gli amici in una cartella e scrive manifest.json (versione + MD5 di ogni file).

Uso: python tools/stage.py CARTELLA_DESTINAZIONE VERSIONE
Lo usano make_package.ps1 (zip completo) e pubblica_aggiornamento.py (aggiornamenti scaricati dal gioco).
"""
import hashlib
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ITEMS = ["project.godot", "scenes", "scripts", "shaders", "assets", "locale", ".godot", "README.md"]
DATA = ["city.json", "heights.bin", "heights_phys.bin", "relief.bin", "cover_png.bin", "minimap.png", "minimap.png.import",
        "civici.json"]


def stage(dest: str, version: int) -> dict:
    os.makedirs(dest, exist_ok=True)
    for item in ITEMS:
        src = os.path.join(ROOT, item)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(dest, item), dirs_exist_ok=True,
                            ignore=shutil.ignore_patterns("editor") if item == ".godot" else None)
        elif os.path.exists(src):
            shutil.copy2(src, dest)
    os.makedirs(os.path.join(dest, "data"), exist_ok=True)
    for f in DATA:
        p = os.path.join(ROOT, "data", f)
        if os.path.exists(p):
            shutil.copy2(p, os.path.join(dest, "data"))
    files = {}
    for dirpath, _dirs, names in os.walk(dest):
        for n in names:
            full = os.path.join(dirpath, n)
            rel = os.path.relpath(full, dest).replace(os.sep, "/")
            if rel in ("manifest.json", ".git") or rel.startswith(".git/"):
                continue
            h = hashlib.md5()
            with open(full, "rb") as fh:
                for chunk in iter(lambda: fh.read(1 << 20), b""):
                    h.update(chunk)
            files[rel] = [h.hexdigest(), os.path.getsize(full)]
    manifest = {"version": version, "files": dict(sorted(files.items()))}
    with open(os.path.join(dest, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, separators=(",", ":"))
    return manifest


if __name__ == "__main__":
    m = stage(sys.argv[1], int(sys.argv[2]))
    print("%d file, versione %d" % (len(m["files"]), m["version"]))
