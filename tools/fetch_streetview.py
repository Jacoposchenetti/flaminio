"""Colori delle facciate da Google Street View (Street View Static API). SOLO USO PERSONALE: le condizioni di Google
non permettono di distribuire dati ricavati dalle immagini, quindi il risultato va in locale/ (mai pubblicato).

Uso: python tools/fetch_streetview.py punta    per ogni palazzo cerca il panorama più adatto (metadata: gratis)
     python tools/fetch_streetview.py foto     scarica una foto puntata sulla facciata (a pagamento oltre la quota)
     python tools/fetch_streetview.py colori   misura i colori → locale/colori_streetview.json

Serve tools/google_key.txt. Cache in tools/cache_streetview/. Tetto di sicurezza: MAX_FOTO immagini in tutto.
"""

import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fetch_facciate as F  # noqa: E402

ROOT = F.ROOT
CACHE = os.path.join(ROOT, "tools", "cache_streetview")
META = os.path.join(CACHE, "meta.json")
SHOTS = os.path.join(CACHE, "shots.json")
COUNT = os.path.join(CACHE, "conteggio.txt")
OUT = os.path.join(ROOT, "locale", "colori_streetview.json")
MAX_FOTO = 6000
PRIVATE = "--private" in sys.argv  # usa anche i panorami caricati da privati dove Google non ha nulla
SIZE = 400
CAM_H = 2.5  # m: telecamera sul tetto dell'auto di Google


def key() -> str:
    return open(os.path.join(ROOT, "tools", "google_key.txt"), encoding="utf-8").read().strip()


def _get(url: str, params: dict, raw=False):
    full = url + "?" + urllib.parse.urlencode(dict(params, key=key()))
    for attempt in range(5):
        try:
            with urllib.request.urlopen(full, timeout=60) as r:
                return r.read() if raw else json.load(r)
        except Exception as ex:  # noqa: BLE001
            print("  ", ex, "riprovo")
            time.sleep(2 + attempt * 3)
    return None


def _latlon(proj, x, z):
    lat = proj.lat0 - z / proj.kz
    lon = proj.lon0 + x / proj.kx
    return lat, lon


def punta() -> None:
    """Per ogni palazzo: i lati verso la strada, il panorama più vicino davanti a ciascuno, e l'inquadratura."""
    proj = F._proj()
    blds = [b for b in F._buildings() if b["h"] >= 4.0 and b["m"] < 3.0]
    meta = json.load(open(META, encoding="utf-8")) if os.path.exists(META) else {}
    # Query: un punto 10 m davanti al centro di ogni lato lungo (la strada); cache per cella di 5 m.
    queries = {}
    for b in blds:
        for ei, a, c, mid, nrm, ln in F._edges(b):
            qx, qz = mid[0] + nrm[0] * 10.0, mid[1] + nrm[1] * 10.0
            k = f"{round(qx / 5) * 5},{round(qz / 5) * 5}"
            queries[k] = (qx, qz)
    # Con --private si richiedono i punti dove c'erano solo panorami di privati (meta vuoto).
    todo = [k for k in queries if k not in meta or (PRIVATE and meta[k] == {})]
    print(len(queries), "punti,", len(todo), "da chiedere")

    def ask(k):
        lat, lon = _latlon(proj, *queries[k])
        d = _get("https://maps.googleapis.com/maps/api/streetview/metadata",
                 {"location": f"{lat:.6f},{lon:.6f}", "radius": 25, "source": "outdoor"})
        if d and d.get("status") == "OK":
            priv = "Google" not in d.get("copyright", "")
            if priv and not PRIVATE:
                return k, {}  # panorami caricati da privati: spesso interni di negozi o foto storte
            return k, {"pano": d["pano_id"], "lat": d["location"]["lat"], "lon": d["location"]["lng"],
                       "date": d.get("date", ""), "priv": priv}
        return k, None if d is None else {}

    done = 0
    with ThreadPoolExecutor(8) as ex:
        for k, v in ex.map(ask, todo):
            if v is not None:
                meta[k] = v
            done += 1
            if done % 500 == 0:
                print(f"metadata {done}/{len(todo)}")
                json.dump(meta, open(META, "w"))
    json.dump(meta, open(META, "w"))
    # Inquadrature: per ogni palazzo i due lati migliori (più larghi, più di fronte al panorama, senza ostacoli).
    egrid = {}
    for bi, b in enumerate(blds):
        pts = b["pts"]
        for i in range(len(pts)):
            a, c = pts[i], pts[(i + 1) % len(pts)]
            for gx in range(int(min(a[0], c[0]) // 20), int(max(a[0], c[0]) // 20) + 1):
                for gz in range(int(min(a[1], c[1]) // 20), int(max(a[1], c[1]) // 20) + 1):
                    egrid.setdefault((gx, gz), []).append((bi, i, a, c))

    def blocked(p1, p2, bi, ei):
        n = int(math.hypot(p2[0] - p1[0], p2[1] - p1[1]) // 10) + 1
        for k in range(n + 1):
            x = p1[0] + (p2[0] - p1[0]) * k / n
            z = p1[1] + (p2[1] - p1[1]) * k / n
            for e in egrid.get((int(x // 20), int(z // 20)), []):
                if (e[0] == bi and e[1] == ei):
                    continue
                if F._seg_hit(p1, p2, e[2], e[3]):
                    return True
        return False

    shots = {}
    for bi, b in enumerate(blds):
        cands = []
        for ei, a, c, mid, nrm, ln in F._edges(b):
            qx, qz = mid[0] + nrm[0] * 10.0, mid[1] + nrm[1] * 10.0
            m = meta.get(f"{round(qx / 5) * 5},{round(qz / 5) * 5}")
            if not m:
                continue
            px, pz = F._proj().xz(m["lat"], m["lon"])
            dx, dz = mid[0] - px, mid[1] - pz
            d = math.hypot(dx, dz)
            if not 4.0 < d < 45.0:
                continue
            facing = -(dx * nrm[0] + dz * nrm[1]) / d
            if facing < 0.4:
                continue
            target = (mid[0] + nrm[0] * 0.3, mid[1] + nrm[1] * 0.3)
            if blocked((px, pz), target, bi, ei):
                continue
            heading = math.degrees(math.atan2(dx, -dz)) % 360.0
            hmid = min(b["h"] * 0.5, 3.5 + (b["h"] - 3.5) * 0.4, 11.0)  # sopra i negozi, sotto il cornicione
            pitch = math.degrees(math.atan2(hmid - CAM_H, d))
            w = min(ln * 0.6, b["h"] * 0.8)  # quanto si inquadra: una parte centrale della facciata
            fov = max(20.0, min(90.0, math.degrees(2 * math.atan2(w / 2, d))))
            sc = facing * min(ln, 30.0) / (1.0 + d / 30.0) * (0.3 if m.get("priv") else 1.0)  # Google prima
            cands.append((sc, m["pano"], round(heading, 1), round(pitch, 1), round(fov, 1), m["date"],
                          bool(m.get("priv"))))
        cands.sort(reverse=True)
        pick, seen = [], set()
        for cnd in cands:
            if cnd[1] in seen and len(cands) > 1:
                continue
            seen.add(cnd[1])
            pick.append(cnd[1:])
            if len(pick) >= 2:
                break
        if pick:
            shots[str(b["id"])] = pick
    json.dump(shots, open(SHOTS, "w"))
    print(len(shots), "palazzi su", len(blds), "inquadrabili;", sum(len(v) for v in shots.values()), "foto")


def foto() -> None:
    shots = json.load(open(SHOTS, encoding="utf-8"))
    os.makedirs(os.path.join(CACHE, "img"), exist_ok=True)
    count = int(open(COUNT).read()) if os.path.exists(COUNT) else 0
    jobs = []
    for bid, lst in shots.items():
        for i, (pano, heading, pitch, fov, _date, *_rest) in enumerate(lst):
            path = os.path.join(CACHE, "img", f"{bid}_{i}.jpg")
            if not os.path.exists(path):
                jobs.append((path, pano, heading, pitch, fov))
    if count + len(jobs) > MAX_FOTO:
        jobs = jobs[:max(0, MAX_FOTO - count)]
        print("tetto di sicurezza: ne scarico solo", len(jobs))

    def dl(job):
        path, pano, heading, pitch, fov = job
        data = _get("https://maps.googleapis.com/maps/api/streetview",
                    {"size": f"{SIZE}x{SIZE}", "pano": pano, "heading": heading, "pitch": pitch, "fov": fov,
                     "source": "outdoor", "return_error_code": "true"}, raw=True)
        if data:
            open(path, "wb").write(data)
        return 1

    done = 0
    with ThreadPoolExecutor(8) as ex:
        for _ in ex.map(dl, jobs):
            done += 1
            if done % 250 == 0:
                print(f"foto {done}/{len(jobs)}")
                open(COUNT, "w").write(str(count + done))
    open(COUNT, "w").write(str(count + done))
    print(done, "foto scaricate; in tutto", count + done)


def colori() -> None:
    import colorsys

    import numpy as np
    import torch
    from PIL import Image
    from transformers import SegformerForSemanticSegmentation
    name = "nvidia/segformer-b0-finetuned-ade-512-512"
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)

    def prep(img):  # come SegformerImageProcessor: 512 × 512, normalizzazione ImageNet
        x = (np.asarray(img.resize((512, 512), Image.BILINEAR), dtype=np.float32) / 255.0 - mean) / std
        return torch.from_numpy(x.transpose(2, 0, 1)[None])

    model = SegformerForSemanticSegmentation.from_pretrained(name).eval()
    labels = model.config.id2label
    wall_ids = [i for i, n in labels.items() if n in ("wall", "building", "house")]
    sky_id = next(i for i, n in labels.items() if n == "sky")
    shots = json.load(open(SHOTS, encoding="utf-8"))
    imgdir = os.path.join(CACHE, "img")
    result = {}
    for n, (bid, lst) in enumerate(shots.items()):
        samples = []
        for i in range(len(lst)):
            path = os.path.join(imgdir, f"{bid}_{i}.jpg")
            if not os.path.exists(path):
                continue
            img = Image.open(path).convert("RGB")
            arr = np.asarray(img, dtype=np.float32) / 255.0
            with torch.no_grad():
                logits = model(pixel_values=prep(img)).logits
            seg = torch.nn.functional.interpolate(logits, size=arr.shape[:2], mode="bilinear").argmax(1)[0].numpy()
            mask = np.isin(seg, wall_ids)
            if len(lst[i]) > 5 and lst[i][5] and (seg == sky_id).mean() < 0.02:
                continue  # panorama di un privato senza cielo: quasi sempre un interno
            # Zona centrale: la facciata puntata sta in mezzo (i bordi possono essere palazzi accanto).
            H, W = mask.shape
            cm = np.zeros_like(mask)
            cm[int(H * 0.12):int(H * 0.85), int(W * 0.2):int(W * 0.8)] = True
            ok = mask & cm & F._wall_pixels(arr)
            if ok.sum() < 800:
                continue
            px = arr[ok]
            lum = px @ np.array([0.2126, 0.7152, 0.0722])
            sel = px[(lum >= np.percentile(lum, 40)) & (lum <= np.percentile(lum, 90))]
            samples.append(np.median(sel, axis=0))
        if samples:
            result[bid] = np.median(np.array(samples), axis=0)
        if n % 200 == 0:
            print(f"{n}/{len(shots)} palazzi, {len(result)} misurati")
    # Misure fatte a mano su foto mirate (monumenti, edifici senza inquadratura automatica): valgono dove manca la
    # misura automatica.
    man = os.path.join(CACHE, "manuali.json")
    if os.path.exists(man):
        for k, v in json.load(open(man)).items():
            result.setdefault(k, np.array(v))
    json.dump({k: [float(x) for x in v] for k, v in result.items()}, open(os.path.join(CACHE, "grezzi.json"), "w"))
    _calibra(result)


def _calibra(result) -> None:
    import colorsys

    import numpy as np
    result = {k: np.array(v) for k, v in result.items()}
    # Stessa scala di colori delle misure Mapillary (vedi fetch_facciate.colori).
    lums = sorted(float(v @ np.array([0.2126, 0.7152, 0.0722])) for v in result.values())
    ref = lums[len(lums) // 2]
    sats = sorted(colorsys.rgb_to_hsv(*np.clip(v, 0, 1))[1] for v in result.values())
    boost = min(1.35, max(1.0, 0.3 / max(sats[len(sats) // 2], 1e-3)))
    out = {}
    for bid, rgb in result.items():
        lum = float(rgb @ np.array([0.2126, 0.7152, 0.0722]))
        target = float(np.clip(0.7 * (lum / ref) ** 0.8, 0.32, 0.88))
        rgb = rgb * (target / max(lum, 1e-3))
        h, s, v = colorsys.rgb_to_hsv(*np.clip(rgb, 0, 1))
        s = min(s * boost, 0.65)
        if 36.0 <= h * 360.0 <= 60.0:
            # Gialli e crema: dal vero sono chiari; scuriti dall'ombra della foto diventerebbero verde oliva.
            v = max(v, 0.8)
            s = min(s, 0.42)
        # Gli intonaci romani vanno dal rosso al giallo (0-50°): una tinta verdastra è la luce degli alberi o
        # dell'ombra, si riporta all'ocra; blu e viola (vetro, cielo riflesso) restano solo come grigi freddi.
        deg = h * 360.0
        if 50.0 < deg < 190.0:
            h, s = 44.0 / 360.0, s * 0.6
        elif deg >= 190.0 and deg < 330.0:
            s = min(s, 0.1)
        rgb = colorsys.hsv_to_rgb(h, s, v)
        out[bid] = [round(float(x), 3) for x in np.clip(rgb, 0.05, 0.92)]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(out, open(OUT, "w", encoding="utf-8"), indent=0)
    print(len(out), "facciate in", OUT, f"(saturazione x{boost:.2f})")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    {"punta": punta, "foto": foto, "colori": colori,
     "calibra": lambda: _calibra(json.load(open(os.path.join(CACHE, "grezzi.json"))))}.get(cmd, lambda: print(__doc__))()
