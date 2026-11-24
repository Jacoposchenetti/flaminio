"""Colori reali delle facciate dalle foto di strada di Mapillary (licenza CC BY-SA).

Uso: python tools/fetch_facciate.py elenco    scarica l'elenco delle foto del quartiere (posizione, direzione, ottica)
     python tools/fetch_facciate.py foto      sceglie per ogni palazzo le foto che lo inquadrano e le scarica
     python tools/fetch_facciate.py colori    misura il colore delle facciate → data/colori_facciate.json
     python tools/fetch_facciate.py applica   lo scrive in data/city.json (campo "col") senza rigenerare tutto

Serve tools/mapillary_token.txt (token "MLY|..." da mapillary.com/dashboard/developers). tools/ non viene pubblicato.
Le foto restano in tools/cache_mapillary/.
"""

import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from convert_osm import Projector  # noqa: E402
from fetch_osm import EAST, NORTH, SOUTH, WEST  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tools", "cache_mapillary")
IMAGES = os.path.join(CACHE, "images.json")
PICKS = os.path.join(CACHE, "picks.json")
OUT = os.path.join(ROOT, "data", "colori_facciate.json")
API = "https://graph.mapillary.com"
FIELDS = "id,computed_geometry,computed_compass_angle,is_pano,camera_type,camera_parameters,width,height,captured_at"


def token() -> str:
    return open(os.path.join(ROOT, "tools", "mapillary_token.txt"), encoding="utf-8").read().strip()


def get(url: str, params: dict) -> dict:
    params = dict(params, access_token=token())
    full = url + "?" + urllib.parse.urlencode(params)
    for attempt in range(6):
        try:
            with urllib.request.urlopen(full, timeout=60) as r:
                return json.load(r)
        except Exception as ex:  # noqa: BLE001
            print("  ", ex, "riprovo")
            time.sleep(3 + attempt * 4)
    raise SystemExit("Mapillary non risponde")


def elenco() -> None:
    """Tutte le foto dai tile vettoriali di copertura (livello 14): la ricerca per area ne restituisce solo una parte."""
    import mapbox_vector_tile  # pip install mapbox-vector-tile
    z = 14
    n = 2 ** z

    def tx(lon):
        return (lon + 180.0) / 360.0 * n

    def ty(lat):
        return (1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n

    found = {}
    for x in range(int(tx(WEST)), int(tx(EAST)) + 1):
        for y in range(int(ty(NORTH)), int(ty(SOUTH)) + 1):
            url = f"https://tiles.mapillary.com/maps/vtp/mly1_public/2/{z}/{x}/{y}?access_token={token()}"
            raw = urllib.request.urlopen(url, timeout=60).read()
            layer = mapbox_vector_tile.decode(raw).get("image", {})
            ext = layer.get("extent", 4096)
            for f in layer.get("features", []):
                gx, gy = f["geometry"]["coordinates"]
                lon = (x + gx / ext) / n * 360.0 - 180.0
                lat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * (y + 1.0 - gy / ext) / n))))
                if not (SOUTH <= lat <= NORTH and WEST <= lon <= EAST):
                    continue
                pr = f["properties"]
                found[str(pr["id"])] = {"id": str(pr["id"]), "lat": lat, "lon": lon, "pano": bool(pr.get("is_pano")),
                                        "compass": pr.get("compass_angle"), "t": pr.get("captured_at", 0),
                                        "seq": pr.get("sequence_id", "")}
            print(f"tile {x},{y}: {len(found)} foto")
    json.dump(list(found.values()), open(IMAGES, "w", encoding="utf-8"))
    print(len(found), "foto in", IMAGES)


def _elenco_bbox() -> None:
    found = {}
    todo = []
    step = 0.0025
    lat = SOUTH
    while lat < NORTH:
        lon = WEST
        while lon < EAST:
            todo.append((lon, lat, min(lon + step, EAST), min(lat + step, NORTH)))
            lon += step
        lat += step
    while todo:
        w, s, e, n = todo.pop()
        d = get(API + "/images", {"fields": FIELDS, "bbox": f"{w},{s},{e},{n}", "limit": 2000})
        data = d.get("data", [])
        if len(data) >= 2000 and e - w > 0.0003:
            mx, my = (w + e) / 2, (s + n) / 2  # troppe: la cella si divide in quattro
            todo += [(w, s, mx, my), (mx, s, e, my), (w, my, mx, n), (mx, my, e, n)]
            continue
        for im in data:
            found[im["id"]] = im
        print(f"{len(todo)} celle restanti, {len(found)} foto")
    json.dump(list(found.values()), open(IMAGES, "w", encoding="utf-8"))
    print(len(found), "foto in", IMAGES)


# ---------------------------------------------------------------- scelta delle foto per ogni facciata

MAX_DIST = 70.0  # m: più lontano la facciata è troppo piccola nella foto
MIN_DIST = 5.0
MIN_EDGE = 6.0  # m: lati più corti non bastano per misurare
PER_BUILDING = 6  # foto per palazzo (da sequenze diverse quando si può)


def _proj():
    return Projector([SOUTH, WEST, NORTH, EAST])


def _cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def _seg_hit(p1, p2, q1, q2) -> bool:
    d1, d2 = _cross(q1, q2, p1), _cross(q1, q2, p2)
    d3, d4 = _cross(p1, p2, q1), _cross(p1, p2, q2)
    return (d1 > 0) != (d2 > 0) and (d3 > 0) != (d4 > 0)


def _buildings():
    city = json.load(open(os.path.join(ROOT, "data", "city.json"), encoding="utf-8"))
    out = []
    for b in city["buildings"]:
        pp = b["p"]
        pts = [(pp[i], pp[i + 1]) for i in range(0, len(pp), 2)]
        if len(pts) > 3 and pts[0] == pts[-1]:
            pts = pts[:-1]
        if len(pts) < 3:
            continue
        area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
                   for i in range(len(pts))) / 2.0
        if area < 0:
            pts.reverse()  # antiorario in (x, z): la normale esterna è a destra del lato... vedi _edges
        out.append({"id": b["id"], "pts": pts, "h": float(b["h"]), "m": float(b.get("m", 0.0)), "k": b.get("k", "")})
    return out


def _edges(b):
    pts = b["pts"]
    cx = sum(p[0] for p in pts) / len(pts)
    cz = sum(p[1] for p in pts) / len(pts)
    for i in range(len(pts)):
        a, c = pts[i], pts[(i + 1) % len(pts)]
        dx, dz = c[0] - a[0], c[1] - a[1]
        ln = math.hypot(dx, dz)
        if ln < MIN_EDGE:
            continue
        nx, nz = dz / ln, -dx / ln
        mx, mz = (a[0] + c[0]) / 2, (a[1] + c[1]) / 2
        if (mx - cx) * nx + (mz - cz) * nz < 0:
            nx, nz = -nx, -nz  # verso l'esterno
        yield i, a, c, (mx, mz), (nx, nz), ln


def foto() -> None:
    proj = _proj()
    ims = json.load(open(IMAGES, encoding="utf-8"))
    for im in ims:
        im["x"], im["z"] = proj.xz(im["lat"], im["lon"])
    grid = {}
    for im in ims:
        grid.setdefault((int(im["x"] // 40), int(im["z"] // 40)), []).append(im)
    blds = [b for b in _buildings() if b["h"] >= 5.0 and b["m"] < 3.0]
    egrid = {}  # lati di tutti i palazzi, per gli ostacoli tra fotocamera e facciata
    for bi, b in enumerate(blds):
        pts = b["pts"]
        for i in range(len(pts)):
            a, c = pts[i], pts[(i + 1) % len(pts)]
            for gx in range(int(min(a[0], c[0]) // 20), int(max(a[0], c[0]) // 20) + 1):
                for gz in range(int(min(a[1], c[1]) // 20), int(max(a[1], c[1]) // 20) + 1):
                    egrid.setdefault((gx, gz), []).append((bi, i, a, c))

    def blocked(p1, p2, bi, ei):
        seen = set()
        n = int(math.hypot(p2[0] - p1[0], p2[1] - p1[1]) // 10) + 1
        for k in range(n + 1):
            x = p1[0] + (p2[0] - p1[0]) * k / n
            z = p1[1] + (p2[1] - p1[1]) * k / n
            for e in egrid.get((int(x // 20), int(z // 20)), []):
                if (e[0], e[1]) in seen or (e[0] == bi and e[1] == ei):
                    continue
                seen.add((e[0], e[1]))
                if _seg_hit(p1, p2, e[2], e[3]):
                    return True
        return False

    picks = {}
    for bi, b in enumerate(blds):
        cands = []
        for ei, a, c, mid, nrm, ln in _edges(b):
            for t in (0.3, 0.5, 0.7):  # tre punti lungo il lato
                px, pz = a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t
                gx, gz = int(px // 40), int(pz // 40)
                for ox in (-2, -1, 0, 1, 2):
                    for oz in (-2, -1, 0, 1, 2):
                        for im in grid.get((gx + ox, gz + oz), []):
                            dx, dz = im["x"] - px, im["z"] - pz
                            d = math.hypot(dx, dz)
                            if not MIN_DIST < d < MAX_DIST:
                                continue
                            facing = (dx * nrm[0] + dz * nrm[1]) / d  # 1: di fronte, 0: di striscio
                            if facing < 0.3:
                                continue
                            bearing = math.degrees(math.atan2(-dx, dz)) % 360.0  # dalla fotocamera al punto
                            if not im["pano"]:
                                if im.get("compass") is None:
                                    continue
                                off = (bearing - im["compass"] + 540.0) % 360.0 - 180.0
                                if abs(off) > 32.0:
                                    continue
                            target = (px + nrm[0] * 0.3, pz + nrm[1] * 0.3)
                            if blocked((im["x"], im["z"]), target, bi, ei):
                                continue
                            score = facing * (1.0 - d / MAX_DIST) + (im["t"] / 1000.0 - 1.4e9) / 4e8 * 0.3
                            cands.append((score, im["id"], im["seq"], ei, round(t, 2)))
        cands.sort(reverse=True)
        chosen, seqs, used = [], {}, set()
        for sc, iid, seq, ei, t in cands:
            if iid in used or seqs.get(seq, 0) >= 2:
                continue
            used.add(iid)
            seqs[seq] = seqs.get(seq, 0) + 1
            chosen.append([iid, ei, t])
            if len(chosen) >= PER_BUILDING:
                break
        if chosen:
            picks[str(b["id"])] = chosen
    need = sorted({c[0] for v in picks.values() for c in v})
    print(len(picks), "palazzi su", len(blds), "con foto;", len(need), "foto da scaricare")
    # Dettagli (ottica, posizione calcolata) e miniature.
    meta = {}
    if os.path.exists(PICKS):
        meta = json.load(open(PICKS, encoding="utf-8")).get("meta", {})
    todo = [i for i in need if i not in meta]
    for k in range(0, len(todo), 50):
        chunk = todo[k:k + 50]
        d = get(API, {"ids": ",".join(chunk), "fields": FIELDS + ",thumb_1024_url"})
        for iid, v in d.items():
            meta[iid] = v
        print(f"dettagli {min(k + 50, len(todo))}/{len(todo)}")
    json.dump({"picks": picks, "meta": meta}, open(PICKS, "w", encoding="utf-8"))
    os.makedirs(os.path.join(CACHE, "img"), exist_ok=True)
    from concurrent.futures import ThreadPoolExecutor

    def dl(iid):
        path = os.path.join(CACHE, "img", iid + ".jpg")
        if os.path.exists(path) or not meta.get(iid, {}).get("thumb_1024_url"):
            return
        for attempt in range(4):
            try:
                with urllib.request.urlopen(meta[iid]["thumb_1024_url"], timeout=60) as r:
                    open(path, "wb").write(r.read())
                return
            except Exception:  # noqa: BLE001
                time.sleep(2 + attempt * 3)

    with ThreadPoolExecutor(8) as ex:
        for k, _ in enumerate(ex.map(dl, need)):
            if k % 200 == 0:
                print(f"foto {k}/{len(need)}")
    # Segmentazione di Mapillary: solo le classi "edificio" (maschera dei pixel di facciata).
    os.makedirs(os.path.join(CACHE, "det"), exist_ok=True)

    def det(iid):
        path = os.path.join(CACHE, "det", iid + ".json")
        if os.path.exists(path):
            return
        d = get(f"{API}/{iid}/detections", {"fields": "value,geometry"})
        keep = [x["geometry"] for x in d.get("data", []) if x.get("value") == "construction--structure--building"]
        json.dump(keep, open(path, "w"))

    with ThreadPoolExecutor(6) as ex:
        list(ex.map(det, need))
    print("fatto")


# ---------------------------------------------------------------- misura del colore

CAM_H = 2.0  # m: altezza della fotocamera (auto, casco, mano)
SAT_BOOST = 1.6


def _project(meta, W, H, bearing, horiz, up):
    """Pixel (u, v) dove cade un punto a `horiz` m di distanza in orizzontale nella direzione `bearing`, `up` m sopra
    la fotocamera; None se fuori dall'inquadratura. Fotocamera a livello (Mapillary non dà il beccheggio)."""
    comp = meta.get("computed_compass_angle")
    if comp is None:
        return None
    a = math.radians((bearing - comp + 540.0) % 360.0 - 180.0)
    typ = meta.get("camera_type", "perspective")
    if typ in ("spherical", "equirectangular") or meta.get("is_pano"):
        u = (0.5 + math.degrees(a) / 360.0) * W
        v = (0.5 - math.degrees(math.atan2(up, horiz)) / 180.0) * H
        return u, v
    fwd = horiz * math.cos(a)
    if fwd <= 0.5:
        return None
    right = horiz * math.sin(a)
    cp = meta.get("camera_parameters") or [0.8]
    f = float(cp[0]) * max(W, H)
    if typ == "fisheye":
        r3 = math.sqrt(right * right + up * up)
        theta = math.atan2(r3, fwd)
        rr = f * theta
        u = W / 2 + (rr * right / r3 if r3 > 1e-6 else 0.0)
        v = H / 2 - (rr * up / r3 if r3 > 1e-6 else 0.0)
    else:
        u = W / 2 + f * right / fwd
        v = H / 2 - f * up / fwd
    if 0 <= u < W and 0 <= v < H:
        return u, v
    return None


def _wall_pixels(arr):
    """Pixel di muro: niente cielo, verde, ombre nere, vetri e riflessi bianchi."""
    import numpy as np
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    mx = arr.max(axis=-1)
    mn = arr.min(axis=-1)
    sat = (mx - mn) / np.maximum(mx, 1e-3)
    ok = (mx > 0.18) & (mx < 0.97)
    ok &= ~((b > r + 0.02) & (b >= g) & (mx > 0.45))  # cielo
    ok &= ~((g > r * 1.04) & (g > b * 1.08))  # alberi, prati
    ok &= ~((b > r + 0.06) & (sat > 0.15))  # vetri, auto blu
    return ok


def _building_mask(iid, W, H):
    """Maschera (H × W, bool) dei pixel che Mapillary riconosce come edificio; None se non c'è."""
    import base64

    import mapbox_vector_tile
    import numpy as np
    from PIL import Image, ImageDraw
    path = os.path.join(CACHE, "det", iid + ".json")
    if not os.path.exists(path):
        return None
    geoms = json.load(open(path))
    if not geoms:
        return None
    ov = Image.new("L", (W, H), 0)
    dr = ImageDraw.Draw(ov)
    for g64 in geoms:
        for lay in mapbox_vector_tile.decode(base64.b64decode(g64)).values():
            ext = lay.get("extent", 4096)
            for f in lay["features"]:
                g = f["geometry"]
                polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
                for poly in polys:
                    for ri, ring in enumerate(poly):  # il primo anello è il contorno, gli altri sono buchi
                        pts = [(x / ext * W, (1.0 - y / ext) * H) for x, y in ring]  # y dal basso
                        if len(pts) >= 3:
                            dr.polygon(pts, fill=0 if ri else 255)
    return np.asarray(ov) > 0


def colori() -> None:
    import numpy as np
    from PIL import Image
    proj = _proj()
    pk = json.load(open(PICKS, encoding="utf-8"))
    picks, meta = pk["picks"], pk["meta"]
    blds = {str(b["id"]): b for b in _buildings()}
    result = {}
    debug = []
    for bid, chosen in picks.items():
        b = blds.get(bid)
        if not b:
            continue
        edges = {e[0]: e for e in _edges(b)}
        samples = []
        for iid, ei, t in chosen:
            m = meta.get(iid)
            path = os.path.join(CACHE, "img", iid + ".jpg")
            if not m or ei not in edges or not os.path.exists(path):
                continue
            g = m.get("computed_geometry", {}).get("coordinates")
            if not g:
                continue
            cx, cz = proj.xz(g[1], g[0])
            img = Image.open(path).convert("RGB")
            W, H = img.size
            arr = np.asarray(img, dtype=np.float32) / 255.0
            _, a, c, _mid, _n, _ln = edges[ei]
            top = min(b["h"] - 1.0, 14.0)
            if top < 3.5:
                continue
            # Griglia di punti sulla facciata: dal primo piano (sopra negozi e auto) fino quasi in cima.
            uv = []
            for tt in (t - 0.15, t - 0.07, t, t + 0.07, t + 0.15):
                if not 0.05 < tt < 0.95:
                    continue
                px, pz = a[0] + (c[0] - a[0]) * tt, a[1] + (c[1] - a[1]) * tt
                dx, dz = px - cx, pz - cz
                horiz = math.hypot(dx, dz)
                bearing = math.degrees(math.atan2(dx, -dz)) % 360.0
                for hh in np.linspace(4.0, top, 5):
                    q = _project(m, W, H, bearing, horiz, hh - CAM_H)
                    if q:
                        uv.append(q)
            if len(uv) < 8:
                continue
            if float(np.median(arr)) < 0.22:
                continue  # foto di notte o controluce
            import datetime
            ora = datetime.datetime.fromtimestamp(m.get("captured_at", 0) / 1000.0, datetime.timezone.utc)
            ora = (ora.hour + ora.minute / 60.0 + (2.0 if 4 <= ora.month <= 10 else 1.0)) % 24.0  # ora di Roma
            if not 7.5 <= ora <= 18.5:
                continue  # di notte i lampioni gialli falsano tutto
            mask = _building_mask(iid, W, H)
            if mask is None:
                continue
            uvs = np.array(uv)
            u0, v0 = uvs.min(axis=0)
            u1, v1 = uvs.max(axis=0)
            if (u1 - u0) < 10:
                continue
            # In orizzontale la direzione della foto è affidabile, in verticale no (beccheggio ignoto): si prende
            # la striscia di colonne della facciata e, dentro, i pixel che Mapillary riconosce come edificio, tolto
            # il piano terra (negozi, saracinesche, auto davanti).
            du = (u1 - u0) * 0.15
            c0, c1 = int(u0 + du), int(u1 - du) + 1
            band = mask[:, c0:c1]
            rows = np.where(band.any(axis=1))[0]
            if len(rows) < 10:
                continue
            r0, r1 = rows.min(), rows.max()
            r1 = int(r1 - (r1 - r0) * 0.25)
            v0, v1 = r0, r1
            crop = arr[r0:r1 + 1, c0:c1]
            ok = band[r0:r1 + 1] & _wall_pixels(crop)
            if ok.sum() < 150:
                continue
            px = crop[ok]
            # Le parti più chiare sono il muro al sole o in luce diffusa; le più scure finestre e ombre.
            lum = px @ np.array([0.2126, 0.7152, 0.0722])
            sel = px[(lum >= np.percentile(lum, 40)) & (lum <= np.percentile(lum, 90))]
            if len(sel) < 30:
                continue
            col = np.median(sel, axis=0)
            samples.append((col, ok.mean() * len(sel) ** 0.5))
            debug.append([bid, iid, [c0, int(v0), c1, int(v1)], col.round(3).tolist()])
        if not samples:
            continue
        cols = np.array([s[0] for s in samples])
        # Colore tipico: mediana; con più foto scarta quelle lontane dalle altre (ombra, auto, impalcature).
        med = np.median(cols, axis=0)
        if len(cols) >= 3:
            dist = np.linalg.norm(cols - med, axis=1)
            cols = cols[dist <= np.percentile(dist, 70) + 1e-6]
            med = np.median(cols, axis=0)
        result[bid] = {"rgb": med.round(3).tolist(), "n": int(len(cols))}
    json.dump(debug, open(os.path.join(CACHE, "debug.json"), "w"))
    # Da foto a colore dell'intonaco: le foto hanno esposizione e luce diverse. Si tiene la tinta (rapporti tra i
    # canali) e si porta la luminosità nella fascia degli intonaci romani, con la stessa scala per tutti.
    lums = sorted(0.2126 * v["rgb"][0] + 0.7152 * v["rgb"][1] + 0.0722 * v["rgb"][2] for v in result.values())
    ref = lums[len(lums) // 2] if lums else 0.5
    out = {}
    for bid, v in result.items():
        rgb = np.array(v["rgb"])
        lum = float(rgb @ np.array([0.2126, 0.7152, 0.0722]))
        target = float(np.clip(0.68 * (lum / ref) ** 0.5, 0.38, 0.86))
        rgb = rgb * (target / max(lum, 1e-3))
        # Le foto spengono i colori (ombra, foschia, bilanciamento del bianco): la saturazione mediana delle misure
        # è circa 0,21 contro 0,3-0,4 degli intonaci romani visti dal vero. Si moltiplica per SAT_BOOST, tinta e
        # luminosità restano quelle misurate.
        import colorsys
        h, sat, val = colorsys.rgb_to_hsv(*np.clip(rgb, 0.0, 1.0))
        rgb = colorsys.hsv_to_rgb(h, min(sat * SAT_BOOST, 0.7), val)
        out[bid] = [round(float(x), 3) for x in np.clip(rgb, 0.05, 0.92)]
    json.dump(out, open(OUT, "w", encoding="utf-8"), indent=0)
    print(len(out), "facciate misurate in", OUT)


def applica() -> None:
    from convert_osm import real_colour
    raw = json.load(open(os.path.join(ROOT, "data", "flaminio_raw.json"), encoding="utf-8"))
    tags = {e["id"]: e.get("tags", {}) for e in raw["elements"]}
    photo = json.load(open(OUT, encoding="utf-8")) if os.path.exists(OUT) else {}
    cp = os.path.join(ROOT, "data", "city.json")
    city = json.load(open(cp, encoding="utf-8"))
    n_osm = n_foto = 0
    for b in city["buildings"]:
        col = real_colour(tags.get(b.get("id"), {}))
        if col:
            n_osm += 1
        elif str(b.get("id")) in photo:
            col = photo[str(b["id"])]
            n_foto += 1
        if col:
            b["col"] = col
        else:
            b.pop("col", None)
    json.dump(city, open(cp, "w", encoding="utf-8", newline=""), ensure_ascii=False)
    print(f"colori reali: {n_osm} da OSM, {n_foto} dalle foto")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    {"elenco": elenco, "foto": foto, "colori": colori, "applica": applica}.get(cmd, lambda: print(__doc__))()
