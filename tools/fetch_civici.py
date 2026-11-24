"""Numeri civici del quartiere da OpenStreetMap (Overpass): punti e edifici con addr:housenumber.

Uso: python tools/fetch_civici.py            (scarica e converte → data/civici.json)
     python tools/fetch_civici.py --locale   (riconverte soltanto data/dem/civici_raw.json già scaricato)

data/civici.json: [[x, z, "numero", "via"], ...] nelle coordinate del gioco (stessa proiezione di convert_osm.py).
Il gioco (city_builder.gd) mette una targa di marmo col numero sulla facciata più vicina.
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from convert_osm import Projector  # noqa: E402
from fetch_osm import EAST, NORTH, SERVERS, SOUTH, WEST  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "data", "dem", "civici_raw.json")  # dem/ non viene distribuito né importato da Godot
OUT = os.path.join(ROOT, "data", "civici.json")

QUERY = f"""
[out:json][timeout:120];
(
  node["addr:housenumber"]({SOUTH},{WEST},{NORTH},{EAST});
  way["addr:housenumber"]({SOUTH},{WEST},{NORTH},{EAST});
  relation["addr:housenumber"]({SOUTH},{WEST},{NORTH},{EAST});
);
out center;
"""


def fetch() -> dict:
    body = urllib.parse.urlencode({"data": QUERY}).encode()
    for attempt in range(8):
        url = SERVERS[attempt % len(SERVERS)]
        try:
            req = urllib.request.Request(url, data=body, headers={"User-Agent": "flaminio-game-prototype/0.1"})
            with urllib.request.urlopen(req, timeout=180) as resp:
                return json.load(resp)
        except Exception as ex:  # noqa: BLE001
            print(f"{url}: {ex}, riprovo")
            time.sleep(5 + attempt * 5)
    sys.exit("Nessun server Overpass ha risposto")


def main() -> None:
    if "--locale" in sys.argv:
        data = json.load(open(RAW, encoding="utf-8"))
    else:
        data = fetch()
        with open(RAW, "w", encoding="utf-8") as f:
            json.dump(data, f)
    proj = Projector([SOUTH, WEST, NORTH, EAST])
    out = []
    seen = set()
    for e in data["elements"]:
        t = e.get("tags", {})
        num = t.get("addr:housenumber", "").strip()
        if not num:
            continue
        if e["type"] == "node":
            lat, lon = e["lat"], e["lon"]
        elif "center" in e:
            lat, lon = e["center"]["lat"], e["center"]["lon"]
        else:
            continue
        x, z = proj.xz(lat, lon)
        street = t.get("addr:street", "")
        key = (street, num)
        if key in seen:
            continue  # stesso civico come punto e come edificio: basta una targa
        seen.add(key)
        out.append([round(x, 2), round(z, 2), num[:8], street])
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"{len(out)} civici in {OUT}")


if __name__ == "__main__":
    main()
