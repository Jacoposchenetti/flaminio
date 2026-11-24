"""Scarica da OpenStreetMap (Overpass API) i dati del quartiere Flaminio.

Uso: python tools/fetch_osm.py data/flaminio_raw.json
"""

import json
import sys
import urllib.parse
import urllib.request

# Riquadro: da Piazza del Popolo (sud) a Ponte Milvio (nord), dal Tevere ai Parioli.
SOUTH, WEST, NORTH, EAST = 41.9080, 12.4600, 41.9370, 12.4850

QUERY = f"""
[out:json][timeout:120];
(
  way["building"]({SOUTH},{WEST},{NORTH},{EAST});
  relation["building"]({SOUTH},{WEST},{NORTH},{EAST});
  way["highway"]({SOUTH},{WEST},{NORTH},{EAST});
  way["railway"="tram"]({SOUTH},{WEST},{NORTH},{EAST});
  way["leisure"~"park|garden|pitch|stadium|playground"]({SOUTH},{WEST},{NORTH},{EAST});
  relation["leisure"~"park|garden"]({SOUTH},{WEST},{NORTH},{EAST});
  way["landuse"~"grass|forest|recreation_ground|meadow"]({SOUTH},{WEST},{NORTH},{EAST});
  way["natural"~"water|wood|scrub"]({SOUTH},{WEST},{NORTH},{EAST});
  relation["natural"="water"]({SOUTH},{WEST},{NORTH},{EAST});
  way["waterway"="river"]({SOUTH},{WEST},{NORTH},{EAST});
  node["natural"="tree"]({SOUTH},{WEST},{NORTH},{EAST});
  way["building:part"]({SOUTH},{WEST},{NORTH},{EAST});
  relation["building:part"]({SOUTH},{WEST},{NORTH},{EAST});
  way["barrier"="city_wall"]({SOUTH},{WEST},{NORTH},{EAST});
  nwr["historic"~"city_gate|monument|memorial"]({SOUTH},{WEST},{NORTH},{EAST});
  nwr["man_made"~"obelisk|bridge"]({SOUTH},{WEST},{NORTH},{EAST});
  nwr["amenity"~"theatre|arts_centre|place_of_worship|cinema|pharmacy|bar|cafe|restaurant|fast_food|bank|police"]({SOUTH},{WEST},{NORTH},{EAST});
  nwr["shop"]({SOUTH},{WEST},{NORTH},{EAST});
  nwr["tourism"~"attraction|museum|hotel"]({SOUTH},{WEST},{NORTH},{EAST});
);
out geom;
"""


SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]


def main() -> None:
    import time

    out = sys.argv[1] if len(sys.argv) > 1 else "data/flaminio_raw.json"
    body = urllib.parse.urlencode({"data": QUERY}).encode()
    data = None
    for attempt in range(8):  # i server pubblici sono spesso sovraccarichi: si riprova a turno
        url = SERVERS[attempt % len(SERVERS)]
        try:
            req = urllib.request.Request(url, data=body, headers={"User-Agent": "flaminio-game-prototype/0.1"})
            with urllib.request.urlopen(req, timeout=180) as resp:
                data = json.load(resp)
            break
        except Exception as ex:  # noqa: BLE001
            print(f"{url}: {ex}, riprovo")
            time.sleep(5 + attempt * 5)
    if data is None:
        sys.exit("Nessun server Overpass ha risposto")
    data["bbox"] = [SOUTH, WEST, NORTH, EAST]
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f)
    print(f"{len(data['elements'])} elementi salvati in {out}")


if __name__ == "__main__":
    main()
