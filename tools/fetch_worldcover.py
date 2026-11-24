"""Scarica la carta delle coperture ESA WorldCover 2021 (10 m, da Sentinel-1/2) per il riquadro di Flaminio.

Uso: python tools/fetch_worldcover.py
Legge dal file COG pubblico su AWS solo i riquadri che servono (richieste HTTP parziali) e scrive
data/dem/worldcover.npy (classi, righe da nord a sud) e worldcover.json. Lo usa tools/convert_osm.py per i prati e
gli alberi che OpenStreetMap non ha. Classi: 10 alberi, 20 arbusti, 30 prato, 40 coltivi, 50 edificato, 60 nudo,
80 acqua. Dati: ESA WorldCover 10 m 2021 v200, Zanaga D. et al., https://doi.org/10.5281/zenodo.7254221 (CC BY 4.0).
"""
import json
import os
import struct
import urllib.request
import zlib

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_N39E012_Map.tif"
TILE_LAT, TILE_LON = 42.0, 12.0  # angolo nord-ovest della tessera (3 x 3 gradi)
BBOX = (41.900, 12.450, 41.945, 12.495)  # sud, ovest, nord, est: Flaminio con un margine


def get(start, length):
    req = urllib.request.Request(URL, headers={"Range": "bytes=%d-%d" % (start, start + length - 1)})
    return urllib.request.urlopen(req, timeout=120).read()


def main() -> None:
    head = get(0, 65536)
    bo = "<" if head[:2] == b"II" else ">"
    assert struct.unpack(bo + "H", head[2:4])[0] == 42, "solo TIFF classico"
    ifd = struct.unpack(bo + "I", head[4:8])[0]
    n = struct.unpack(bo + "H", head[ifd:ifd + 2])[0]
    sizes = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 16: 8}
    tags = {}
    for i in range(n):
        e = head[ifd + 2 + 12 * i: ifd + 14 + 12 * i]
        tag, typ, cnt = struct.unpack(bo + "HHI", e[:8])
        size = sizes.get(typ, 1) * cnt
        fmt = {3: "H", 4: "I", 16: "Q"}.get(typ)
        if size <= 4:
            raw = e[8:8 + size]
        else:
            off = struct.unpack(bo + "I", e[8:12])[0]
            raw = head[off:off + size] if off + size <= len(head) else get(off, size)
        tags[tag] = struct.unpack(bo + fmt * cnt, raw[:struct.calcsize(fmt) * cnt]) if fmt else raw
    width, height = tags[256][0], tags[257][0]
    tw, th = tags[322][0], tags[323][0]
    offsets, counts = tags[324], tags[325]
    comp = tags[259][0]
    pred = tags.get(317, (1,))[0]
    step = 3.0 / width
    c0 = int((BBOX[1] - TILE_LON) / step)
    c1 = int((BBOX[3] - TILE_LON) / step) + 1
    r0 = int((TILE_LAT - BBOX[2]) / step)
    r1 = int((TILE_LAT - BBOX[0]) / step) + 1
    per_row = (width + tw - 1) // tw
    out = np.zeros((r1 - r0, c1 - c0), dtype=np.uint8)
    for ty in range(r0 // th, (r1 - 1) // th + 1):
        for tx in range(c0 // tw, (c1 - 1) // tw + 1):
            k = ty * per_row + tx
            data = get(offsets[k], counts[k])
            if comp in (8, 32946):
                data = zlib.decompress(data)
            elif comp != 1:
                raise SystemExit("compressione %d non gestita" % comp)
            t = np.frombuffer(data, dtype=np.uint8)[:tw * th].reshape(th, tw)
            if pred == 2:
                t = np.cumsum(t, axis=1, dtype=np.uint8)
            y0, x0 = ty * th, tx * tw
            ys, xs = max(r0, y0), max(c0, x0)
            ye, xe = min(r1, y0 + th), min(c1, x0 + tw)
            out[ys - r0:ye - r0, xs - c0:xe - c0] = t[ys - y0:ye - y0, xs - x0:xe - x0]
    dest = os.path.join(ROOT, "data", "dem")
    os.makedirs(dest, exist_ok=True)
    np.save(os.path.join(dest, "worldcover.npy"), out)
    json.dump({"lat0": TILE_LAT - r0 * step, "lon0": TILE_LON + c0 * step, "step": step,
               "source": "ESA WorldCover 10 m 2021 v200, doi:10.5281/zenodo.7254221, CC BY 4.0"},
              open(os.path.join(dest, "worldcover.json"), "w"))
    vals, cnt = np.unique(out, return_counts=True)
    print("WorldCover %dx%d:" % out.shape[::-1], {int(v): int(c) for v, c in zip(vals, cnt)})


if __name__ == "__main__":
    main()
