"""Importa il DTM LiDAR 1x1 m della Regione Lazio (MASE, Piano Straordinario di Telerilevamento, volo 2014).

Uso: python tools/import_lidar.py CARTELLA_CON_I_TIFF
Le tessere (lazio_140_D4xxxxxx_0101_DTM.tiff) si scaricano da https://sim.mase.gov.it/pst/ (Banca Dati PST,
LiDAR Lazio, dtm 1x1). Sono in WGS84 gradi, celle da 1e-5 gradi (0,83 x 1,11 m), quota in metri, -9999 = vuoto.
Produce data/dem/lidar_dtm.npy (righe da nord a sud) e lidar_dtm.json; lo usa tools/convert_osm.py --rilievo.
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEP = 1e-5


def main(folder: str) -> None:
    tiles = []
    for f in sorted(glob.glob(os.path.join(folder, "*.tif*"))):
        im = Image.open(f)
        tie, scale = im.tag_v2[33922], im.tag_v2[33550]
        assert abs(scale[0] - STEP) < 1e-9 and abs(scale[1] - STEP) < 1e-9, f
        a = np.asarray(im, dtype=np.float32)
        tiles.append((float(tie[3]), float(tie[4]), a))  # centro del pixel in alto a sinistra (PixelIsPoint)
    lon0 = min(t[0] for t in tiles)
    lat0 = max(t[1] for t in tiles)
    cols = int(round((max(t[0] for t in tiles) - lon0) / STEP)) + 1000
    rows = int(round((lat0 - min(t[1] for t in tiles)) / STEP)) + 1000
    dem = np.full((rows, cols), np.nan, dtype=np.float32)
    for lon, lat, a in tiles:
        c, r = int(round((lon - lon0) / STEP)), int(round((lat0 - lat) / STEP))
        a = np.where(a < -1000, np.nan, a)
        dem[r:r + a.shape[0], c:c + a.shape[1]] = np.where(np.isnan(a), dem[r:r + a.shape[0], c:c + a.shape[1]], a)
    out = os.path.join(ROOT, "data", "dem")
    os.makedirs(out, exist_ok=True)
    np.save(os.path.join(out, "lidar_dtm.npy"), dem)
    meta = {"lon0": lon0, "lat0": lat0, "step": STEP, "source":
            "LiDAR DTM 1x1 m Regione Lazio, Piano Straordinario di Telerilevamento, MASE (open data)"}
    json.dump(meta, open(os.path.join(out, "lidar_dtm.json"), "w"))
    ok = ~np.isnan(dem)
    print("%d tessere, griglia %dx%d, piena al %.1f%%, quote %.1f-%.1f m" %
          (len(tiles), cols, rows, 100 * ok.mean(), np.nanmin(dem), np.nanmax(dem)))


if __name__ == "__main__":
    main(sys.argv[1])
