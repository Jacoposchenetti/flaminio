"""Scarica il rilievo reale (TINITALY 1.1 dell'INGV, terreno nudo, celle di 10 m) e ritaglia il quadrato di Flaminio.

Uso: python tools/fetch_dem.py
Produce data/dem/flaminio_dem.npy (quote in metri sul mare, righe da nord a sud) e flaminio_dem.json (riferimento
UTM 32N). Lo usa tools/convert_osm.py; non va nel pacchetto per gli amici (resta il rilievo già calcolato).

Dati: Tarquini S. et al., TINITALY/1.1, INGV, https://doi.org/10.13127/tinitaly/1.1 - licenza CC BY 4.0.
"""
import io
import json
import os
import urllib.request
import zipfile

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILE = "w46075_s10"  # 50 x 50 km: est 749950-800050, nord 4600050-4650050 (UTM 32N): contiene Roma nord
URL = f"https://tinitaly.pi.ingv.it/data_1.1/{TILE}/{TILE}.zip"
# Ritaglio in UTM 32N: Flaminio più un margine (Piazza del Popolo - Ponte Milvio, Monte Mario - Parioli).
CROP = (783000.0, 4641000.0, 792000.0, 4650000.0)  # est min, nord min, est max, nord max


def main() -> None:
    out_dir = os.path.join(ROOT, "data", "dem")
    os.makedirs(out_dir, exist_ok=True)
    print("Scarico", URL)
    raw = urllib.request.urlopen(URL, timeout=300).read()
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        name = next(n for n in z.namelist() if n.endswith(".tif"))
        Image.MAX_IMAGE_PIXELS = None
        im = Image.open(io.BytesIO(z.read(name)))
        tie = im.tag_v2[33922]
        scale = im.tag_v2[33550]
        dem = np.asarray(im, dtype=np.float32)
    x0, y0, step = float(tie[3]), float(tie[4]), float(scale[0])
    c0 = int((CROP[0] - x0) / step)
    c1 = int((CROP[2] - x0) / step) + 1
    r0 = int((y0 - CROP[3]) / step)
    r1 = int((y0 - CROP[1]) / step) + 1
    crop = dem[r0:r1, c0:c1]
    np.save(os.path.join(out_dir, "flaminio_dem.npy"), crop)
    meta = {"epsg": 32632, "x0": x0 + c0 * step, "y0": y0 - r0 * step, "cell": step,
            "source": "TINITALY/1.1 INGV, doi:10.13127/tinitaly/1.1, CC BY 4.0"}
    with open(os.path.join(out_dir, "flaminio_dem.json"), "w") as fh:
        json.dump(meta, fh)
    print("Ritaglio %dx%d, quote %.1f-%.1f m" % (crop.shape[1], crop.shape[0], crop.min(), crop.max()))


if __name__ == "__main__":
    main()
