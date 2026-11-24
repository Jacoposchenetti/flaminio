"""Converte i dati OSM grezzi in dati di gioco compatti, in metri.

Uso: python tools/convert_osm.py data/flaminio_raw.json data [--piano]
(quote vere dal LiDAR in data/dem, vedi tools/import_lidar.py; --piano: quartiere in piano con il solo Tevere scavato)

Produce:
  data/city.json       edifici, strade, aree verdi, acqua, alberi, punto di partenza
  data/heights.bin     quota del terreno in float32 (rilievo vero + Tevere scavato), 1 cella = CELL metri, righe da nord a sud
  data/relief.bin      solo il rilievo (strade livellate, palazzi in piano), senza il Tevere: serve per il colore del
                       terreno e per sapere dove sta la strada sopra il fiume
  data/cover_png.bin   coperture del suolo (PNG RGBA, 1 m per pixel): prati e parchi disegnati dallo shader del terreno
  data/minimap.png     minimappa sulla stessa griglia

Sistema di riferimento: X verso est, Z verso sud (come Godot), origine al centro del riquadro.
"""

import json
import math
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

CELL = 2.0  # metri per pixel del rilievo
BANK_Y = -9.5  # banchine del Tevere, sotto i muraglioni
WATER_Y = -10.5  # pelo dell'acqua
RIVER_BED = -13.5  # fondo del fiume
RIVER_DEPTH = -RIVER_BED
SPAWN_LATLON = (41.9286, 12.4700)  # Piazza Apollodoro, davanti al Palazzetto dello Sport

ROAD_WIDTH = {
    "motorway": 16, "trunk": 16, "primary": 14, "secondary": 12, "tertiary": 10,
    "unclassified": 8, "residential": 8, "living_street": 6, "service": 5,
    "primary_link": 7, "secondary_link": 7, "tertiary_link": 6, "trunk_link": 7,
    "pedestrian": 6, "footway": 2.5, "path": 2.5, "cycleway": 2.5, "steps": 2.5,
    "track": 3, "corridor": 0,
}
FOOT = {"pedestrian", "footway", "path", "cycleway", "steps", "track"}

# Palette romana: ocra, terracotta, giallo, rosa antico, travertino, mattone.
COLORS = [
    (0.83, 0.62, 0.37), (0.76, 0.45, 0.30), (0.90, 0.76, 0.48), (0.84, 0.63, 0.55),
    (0.88, 0.84, 0.74), (0.66, 0.38, 0.27), (0.93, 0.85, 0.66), (0.78, 0.55, 0.40),
]


# Colore reale della facciata da OSM (building:colour, altrimenti building:material); None se non è indicato.
CSS_COLOURS = {"white": "#ffffff", "lightyellow": "#ffffe0", "yellow": "#e8c860", "beige": "#f5f5dc",
               "orange": "#d98b48", "red": "#a8432e", "brown": "#8b5a3c", "pink": "#e0a8a0", "grey": "#9a9a9a",
               "gray": "#9a9a9a", "lightgrey": "#d3d3d3", "silver": "#c0c0c0", "cream": "#f3e5c8", "ochre": "#cc9a4e"}
MATERIAL_COLOURS = {"marble": (0.88, 0.87, 0.83), "brick": (0.64, 0.36, 0.26), "metal": (0.62, 0.64, 0.66),
                    "glass": (0.42, 0.52, 0.58), "concrete": (0.68, 0.67, 0.64), "stone": (0.80, 0.74, 0.62),
                    "plaster": (0.86, 0.76, 0.58), "plastic": (0.85, 0.85, 0.83)}


def real_colour(tags):
    c = (tags.get("building:colour") or tags.get("colour") or "").strip().lower()
    c = CSS_COLOURS.get(c, c)
    if len(c) == 7 and c.startswith("#"):
        try:
            rgb = [int(c[i:i + 2], 16) / 255.0 for i in (1, 3, 5)]
        except ValueError:
            rgb = None
        if rgb:
            # Il bianco pieno al sole "brucia": un intonaco bianco reale riflette circa l'85-90% (la tinta resta).
            return [round(v * 0.9, 3) for v in rgb]
    m = MATERIAL_COLOURS.get((tags.get("building:material") or "").strip().lower())
    return list(m) if m else None


class Projector:
    def __init__(self, bbox):
        s, w, n, e = bbox
        self.lat0 = (s + n) / 2
        self.lon0 = (w + e) / 2
        self.kx = 111320.0 * math.cos(math.radians(self.lat0))
        self.kz = 110540.0
        self.half_w = (e - w) / 2 * self.kx
        self.half_h = (n - s) / 2 * self.kz

    def xz(self, lat, lon):
        return ((lon - self.lon0) * self.kx, -(lat - self.lat0) * self.kz)


def ring_area(pts):
    a = 0.0
    for i in range(len(pts)):
        x1, z1 = pts[i]
        x2, z2 = pts[(i + 1) % len(pts)]
        a += x1 * z2 - x2 * z1
    return a / 2


def clean_ring(pts):
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    out = []
    for p in pts:
        if not out or abs(p[0] - out[-1][0]) > 0.05 or abs(p[1] - out[-1][1]) > 0.05:
            out.append(p)
    return out


def clip_ring(pts, xmin, zmin, xmax, zmax):
    """Sutherland-Hodgman su rettangolo."""
    def clip(points, inside, inter):
        res = []
        for i in range(len(points)):
            cur, prev = points[i], points[i - 1]
            if inside(cur):
                if not inside(prev):
                    res.append(inter(prev, cur))
                res.append(cur)
            elif inside(prev):
                res.append(inter(prev, cur))
        return res

    def ix(x0):
        return lambda a, b: (x0, a[1] + (b[1] - a[1]) * (x0 - a[0]) / (b[0] - a[0]))

    def iz(z0):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (z0 - a[1]) / (b[1] - a[1]), z0)

    pts = clip(pts, lambda p: p[0] >= xmin, ix(xmin)) if pts else pts
    pts = clip(pts, lambda p: p[0] <= xmax, ix(xmax)) if pts else pts
    pts = clip(pts, lambda p: p[1] >= zmin, iz(zmin)) if pts else pts
    pts = clip(pts, lambda p: p[1] <= zmax, iz(zmax)) if pts else pts
    return pts


def join_rings(ways):
    """Unisce i tratti 'outer' di una multipolygon in anelli chiusi."""
    segs = [list(w) for w in ways if len(w) >= 2]
    rings = []
    while segs:
        ring = segs.pop(0)
        changed = True
        while ring[0] != ring[-1] and changed:
            changed = False
            for i, s in enumerate(segs):
                if s[0] == ring[-1]:
                    ring += s[1:]
                elif s[-1] == ring[-1]:
                    ring += s[::-1][1:]
                elif s[-1] == ring[0]:
                    ring = s[:-1] + ring
                elif s[0] == ring[0]:
                    ring = s[::-1][:-1] + ring
                else:
                    continue
                segs.pop(i)
                changed = True
                break
        rings.append(ring)
    return rings


def parse_float(v):
    if v is None:
        return None
    try:
        return float(str(v).replace(",", ".").replace("m", "").strip().split(";")[0])
    except ValueError:
        return None


def building_height(tags, area):
    h = parse_float(tags.get("height"))
    if h:
        return max(2.5, min(h, 120.0))
    lv = parse_float(tags.get("building:levels"))
    if lv:
        return max(3.0, lv * 3.2 + 0.8)
    kind = tags.get("building", "yes")
    if kind in ("garage", "garages", "shed", "kiosk", "roof", "hut", "toilets", "carport"):
        return 3.5
    if area < 80:
        return 4.0
    if area < 250:
        return 9.0
    return 19.0  # tipica palazzina del Flaminio, sei piani


# Monumenti ricostruiti a mano: id OSM -> (tipo, parametri). Le piante restano quelle reali.
LANDMARKS = {
    23950266: ("palazzetto", {}),  # Palazzetto dello Sport (Nervi, 1957)
    27536313: ("hall", {"h": 24.0}),  # Sala Santa Cecilia
    27536311: ("hall", {"h": 19.0}),  # Sala Sinopoli
    27536312: ("hall", {"h": 15.5}),  # Sala Petrassi
    1009564564: ("cavea", {}),  # Cavea dell'Auditorium
    63038: ("stadium", {}),  # Stadio Flaminio
    128448466: ("canopy", {"h": 24.0}),  # tribuna coperta dello Stadio Flaminio
    798054736: ("gate", {}),  # Porta del Popolo
}
POI_CATS = {
    "shop": "shop", "restaurant": "food", "cafe": "food", "bar": "food", "fast_food": "food",
    "pharmacy": "health", "bank": "bank", "police": "police", "theatre": "culture", "arts_centre": "culture",
    "cinema": "culture", "museum": "culture", "attraction": "monument", "place_of_worship": "worship",
    "hotel": "hotel",
}


def inside(px, pz, ring):
    res = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, zi = ring[i]
        xj, zj = ring[j]
        if (zi > pz) != (zj > pz) and px < (xj - xi) * (pz - zi) / (zj - zi + 1e-12) + xi:
            res = not res
        j = i
    return res


def extract_extras(raw, proj, buildings, flat, rd, geom_pts, box):
    """Monumenti, mura, ponti, punti d'interesse; segna chiese e MAXXI; gestisce le parti di edificio."""
    xmin, zmin, xmax, zmax = box
    landmarks, walls, bridges, pois = [], [], [], []

    def ring_of(b):
        return list(zip(b["p"][0::2], b["p"][1::2]))

    def centroid(r):
        return (sum(p[0] for p in r) / len(r), sum(p[1] for p in r) / len(r))

    # Monumenti con pianta: tolti dagli edifici normali.
    keep = []
    for b in buildings:
        if b["id"] in LANDMARKS:
            t, prm = LANDMARKS[b["id"]]
            lm = {"t": t, "p": b["p"], "n": b["n"], **prm}
            if "inner" in b:
                lm["inner"] = b["inner"]
            landmarks.append(lm)
        else:
            keep.append(b)
    buildings[:] = keep

    # Parti di edificio: dove ci sono, la sagoma esterna non si disegna.
    parts = [b for b in buildings if b.get("part")]
    part_c = [centroid(ring_of(p)) for p in parts]
    keep = []
    for b in buildings:
        if not b.get("part") and parts:
            r = ring_of(b)
            if any(inside(cx, cz, r) for cx, cz in part_c):
                continue
        keep.append(b)
    buildings[:] = keep

    maxxi = []
    for e in raw["elements"]:
        tags = e.get("tags", {})
        name = tags.get("name", "")
        if e["type"] == "relation" and "MAXXI" in name:
            for m in e.get("members", []):
                if m.get("role") == "outer" and m.get("geometry"):
                    maxxi.append(geom_pts(m["geometry"]))
        if e["type"] == "way" and tags.get("man_made") == "obelisk" and e.get("geometry"):
            r = clean_ring(geom_pts(e["geometry"]))
            cx, cz = centroid(r)
            ob = parse_float(tags.get("height")) or 12.0
            landmarks.append({"t": "obelisk", "x": round(cx, 2), "z": round(cz, 2), "h": ob, "n": name,
                              "base": round(max(3.0, max(abs(p[0] - cx) for p in r) * 1.6), 2)})
        if e["type"] == "node" and tags.get("man_made") == "obelisk":
            x, z = proj.xz(e["lat"], e["lon"])
            if not any(abs(l.get("x", 1e9) - x) < 5 for l in landmarks):
                landmarks.append({"t": "obelisk", "x": round(x, 2), "z": round(z, 2), "h": parse_float(tags.get("height")) or 12.0, "n": name})
        if e["type"] == "way" and tags.get("barrier") == "city_wall":
            pts = [p for p in geom_pts(e.get("geometry", [])) if xmin - 20 <= p[0] <= xmax + 20 and zmin - 20 <= p[1] <= zmax + 20]
            if len(pts) >= 2:
                walls.append(flat(pts))
        if tags.get("man_made") == "bridge":
            rings = []
            if e["type"] == "way":
                rings = [geom_pts(e.get("geometry", []))]
            elif e["type"] == "relation":
                rings = join_rings([geom_pts(m.get("geometry", [])) for m in e.get("members", []) if m.get("role") == "outer"])
            for r in rings:
                r = clean_ring(r)
                if len(r) >= 3:
                    bridges.append({"p": flat(r), "n": name})
        # Punti d'interesse per la mappa.
        cat = None
        for key in ("amenity", "tourism", "historic", "shop"):
            v = tags.get(key)
            if v:
                cat = "shop" if key == "shop" else POI_CATS.get(v, "monument" if key == "historic" else None)
                if cat:
                    break
        if cat and name:
            if e["type"] == "node":
                x, z = proj.xz(e["lat"], e["lon"])
            else:
                g = [p for p in (e.get("geometry") or []) if p]
                if not g and e["type"] == "relation":
                    g = [p for m in e.get("members", []) for p in (m.get("geometry") or []) if p]
                if not g:
                    continue
                x, z = centroid(geom_pts(g))
            if xmin <= x <= xmax and zmin <= z <= zmax:
                pois.append([round(x, 1), round(z, 1), name, cat, tags.get("shop", ""), tags.get("amenity") or tags.get("shop") or tags.get("tourism") or ""])

    for b in buildings:
        if b["k"] in ("church", "basilica", "chapel", "cathedral") and abs(ring_area(ring_of(b))) > 250:
            b["dome"] = 1
        if maxxi:
            cx, cz = centroid(ring_of(b))
            if any(inside(cx, cz, r) for r in maxxi):
                b["style"] = "modern"
                b["h"] = max(b["h"], 14.0)
    # Nomi dei monumenti anche sulla mappa.
    for lm in landmarks:
        if lm.get("n"):
            r = list(zip(lm["p"][0::2], lm["p"][1::2])) if "p" in lm else [(lm["x"], lm["z"])]
            cx, cz = centroid(r)
            pois.append([round(cx, 1), round(cz, 1), lm["n"], "monument", ""])
    for b in buildings:
        if b["n"] and abs(ring_area(ring_of(b))) > 600:
            cx, cz = centroid(ring_of(b))
            pois.append([round(cx, 1), round(cz, 1), b["n"], "worship" if b.get("dome") else "building", ""])
    if maxxi:
        cx, cz = centroid(maxxi[0])
        pois.append([round(cx, 1), round(cz, 1), "MAXXI", "culture", ""])
    return landmarks, walls, bridges, pois


def street_labels(roads):
    """Dove scrivere i nomi delle vie sulla mappa: [x, z, angolo, nome, importanza], uno ogni ~350 m di strada."""
    by_name = {}
    for r in roads:
        if r["n"] and r["k"] in ("road", "foot"):
            by_name.setdefault(r["n"], []).append(r)
    out = []
    for name, rs in by_name.items():
        segs = []
        for r in rs:
            pts = list(zip(r["p"][0::2], r["p"][1::2]))
            for a, b in zip(pts, pts[1:]):
                segs.append((math.dist(a, b), a, b, r["w"], r["k"]))
        total = sum(sg[0] for sg in segs)
        if total < 40:
            continue
        segs.sort(key=lambda sg: -sg[0])
        wanted = max(1, int(total / 350))
        chosen = []
        for length, a, b, w, k in segs:
            mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
            if length < 15 or any(math.dist(mid, c) < 200 for c in chosen):
                continue
            chosen.append(mid)
            ang = math.atan2(b[1] - a[1], b[0] - a[0])
            if ang > math.pi / 2:
                ang -= math.pi
            elif ang < -math.pi / 2:
                ang += math.pi
            imp = 3 if w >= 12 else 2 if w >= 8 and k == "road" else 1 if k == "road" else 0
            out.append([round(mid[0], 1), round(mid[1], 1), round(ang, 3), name, imp])
            if len(chosen) >= wanted:
                break
    return out


def _lidar_land(proj, X, Z, data_dir):
    """Quote vere (m sul mare) nei punti X, Z del gioco: DTM LiDAR 1 m della Regione Lazio (tools/import_lidar.py),
    con il TINITALY a 10 m (tools/fetch_dem.py) solo dove il volo LiDAR non arriva, allineato al LiDAR sul bordo."""
    import os
    from scipy import ndimage
    lon = proj.lon0 + X / proj.kx
    lat = proj.lat0 - Z / proj.kz
    path = os.path.join(data_dir, "dem", "lidar_dtm.npy")
    dem = np.load(path)
    meta = json.load(open(path.replace(".npy", ".json")))
    ok = ~np.isnan(dem)
    # Da celle di 1 m alla griglia di 2 m: media pesata su ~2 m (via il rumore, restano muri e scarpate).
    num = ndimage.gaussian_filter(np.where(ok, dem, 0.0).astype(np.float32), 0.9)
    den = ndimage.gaussian_filter(ok.astype(np.float32), 0.9)
    fr = (meta["lat0"] - lat) / meta["step"]
    fc = (lon - meta["lon0"]) / meta["step"]
    have = ndimage.map_coordinates(den, [fr, fc], order=1, mode="constant", cval=0.0)
    ratio = num / np.maximum(den, 1e-4)
    near = ndimage.distance_transform_edt(den < 0.5, return_distances=False, return_indices=True)
    ratio = ratio[near[0], near[1]]  # i vuoti prendono la quota valida più vicina: niente zeri mescolati sul bordo
    land = ndimage.map_coordinates(ratio, [fr, fc], order=1, mode="nearest").astype(np.float32)
    gap = have < 0.6
    gap_w = np.zeros_like(land)
    if gap.any():
        tin = os.path.join(data_dir, "dem", "flaminio_dem.npy")
        if os.path.exists(tin):
            from pyproj import Transformer
            tdem = np.load(tin).astype(np.float32)
            tmeta = json.load(open(tin.replace(".npy", ".json")))
            e, n = Transformer.from_crs(4326, tmeta["epsg"], always_xy=True).transform(lon, lat)
            coarse = ndimage.map_coordinates(tdem, [(tmeta["y0"] - n) / tmeta["cell"] - 0.5, (e - tmeta["x0"]) / tmeta["cell"] - 0.5],
                                             order=1, mode="nearest").astype(np.float32)
            edge = ~gap & (ndimage.distance_transform_edt(~gap) * CELL < 80)
            shift = float(np.median(land[edge] - coarse[edge])) if edge.any() else 0.0
            filled = coarse + shift
        else:
            filled = np.full_like(land, float(np.median(land[~gap])))
        # Raccordo di ~30 m: dentro il buco il TINITALY, fuori il LiDAR.
        t = np.clip(ndimage.distance_transform_edt(gap) * CELL / 30.0, 0.0, 1.0)
        wgt = np.where(gap, t * t * (3 - 2 * t), 0.0)
        land = (land * (1 - wgt) + filled * wgt).astype(np.float32)
        gap_w = wgt.astype(np.float32)
        print("rilievo: %.0f%% della mappa fuori dal volo LiDAR, riempito col TINITALY" % (100 * gap.mean()))
    return land, gap_w


def _solve_profiles(pos, edges, triples, data, weight, lam):
    """Profilo verticale delle strade: quote vicine al rilievo misurato ma senza gobbe sotto i ~20 m.
    Minimi quadrati sparsi su tutta la rete insieme (gli incroci sono nodi condivisi, quindi in piano e coerenti):
    sum w_i (h_i - d_i)^2 + lam_t * (h_a - 2 h_b + h_c)^2 su ogni terna di punti consecutivi."""
    from scipy import sparse
    from scipy.sparse.linalg import spsolve
    n = len(pos)
    a, b, c, lt = (np.array([t[i] for t in triples]) for i in range(4))
    rows = np.repeat(np.arange(len(triples)), 3)
    cols = np.stack([a, b, c], 1).ravel()
    vals = (np.array([1.0, -2.0, 1.0])[None, :] * np.sqrt(lt)[:, None]).ravel()
    D = sparse.csr_matrix((vals, (rows, cols)), shape=(len(triples), n))
    # Un filo di primo ordine tiene insieme i tratti senza dati (ponti).
    ea, eb = (np.array([e[i] for e in edges]) for i in range(2))
    G = sparse.csr_matrix((np.r_[np.ones(len(ea)), -np.ones(len(ea))] * 0.05,
                           (np.r_[np.arange(len(ea)), np.arange(len(ea))], np.r_[ea, eb])), shape=(len(ea), n))
    A = sparse.diags(weight) + D.T @ D + G.T @ G + sparse.identity(n) * 1e-6
    return spsolve(A.tocsc(), weight * data)


def land_relief(proj, xmin, zmin, w_px, h_px, water, buildings, roads, areas, data_dir):
    """Rilievo vero sulla griglia del gioco, in metri sopra il lungotevere, fatto come un progetto stradale:
    1) terreno dal LiDAR a 1 m;  2) profilo verticale di tutta la rete stradale risolto insieme (liscio, incroci in
    piano, pendenze vere);  3) carreggiate e marciapiedi in piano in larghezza a quella quota, raccordati al terreno;
    4) piazze e campi in piano, palazzi su un piano alla quota della loro strada;  5) vicino al Tevere quota zero
    (i muraglioni del gioco partono da lì).  Zero se manca il dato o con --piano.
    Scrive anche r["y"] (quota ai vertici) sui ponti, che CityBuilder usa per impalcati e parapetti."""
    import os
    from scipy import ndimage
    if "--piano" in sys.argv:
        print("rilievo: spento (--piano: quartiere in piano)")
        return np.zeros((h_px, w_px), dtype=np.float32)
    if not os.path.exists(os.path.join(data_dir, "dem", "lidar_dtm.npy")):
        print("rilievo: manca data/dem/lidar_dtm.npy (python tools/import_lidar.py CARTELLA): quartiere piatto")
        return np.zeros((h_px, w_px), dtype=np.float32)
    xs = xmin + np.arange(w_px) * CELL
    zs = zmin + np.arange(h_px) * CELL
    X, Z = np.meshgrid(xs, zs)
    land, gap_w = _lidar_land(proj, X, Z, data_dir)
    # Sotto ponti e viadotti il LiDAR a volte tiene l'impalcato come un terrapieno pieno (Corso di Francia):
    # lì il terreno si ricostruisce da quello ai lati, così le strade di sotto passano.
    under = Image.new("L", (w_px, h_px), 0)
    du = ImageDraw.Draw(under)
    for r in roads:
        if r.get("b") and r["w"] > 0:
            pts = [((x - xmin) / CELL, (z - zmin) / CELL) for x, z in zip(r["p"][0::2], r["p"][1::2])]
            du.line(pts, fill=255, width=max(2, int(round((r["w"] + 6.0) / CELL))))
    under = np.asarray(under) > 127
    if under.any():
        keep = (~under).astype(np.float32)
        filled = land.copy()
        for sigma in (2.0, 5.0, 12.0):  # dal bordo verso il centro della striscia
            num = ndimage.gaussian_filter(land * keep, sigma)
            den = ndimage.gaussian_filter(keep, sigma)
            ok = under & (den > 0.05) & (filled == land)
            filled = np.where(ok, num / np.maximum(den, 1e-4), filled)
        land = np.where(under, filled, land).astype(np.float32)

    # Quota zero = il lungotevere. Entro 30 m dal fiume tutto a zero (i muraglioni li scava il gioco), poi in 60 m
    # si raccorda al terreno vero: il lungotevere vero varia di poco, la rampa non si nota.
    dist = ndimage.distance_transform_edt(~water) * CELL
    band = (dist > 30) & (dist < 90)
    ref = float(np.median(land[band])) if band.any() else float(np.median(land))
    land -= ref
    t = np.clip((dist - 30.0) / 60.0, 0.0, 1.0)
    river_t = (t * t * (3 - 2 * t)).astype(np.float32)
    land *= river_t

    def px(pts):
        return [((x - xmin) / CELL, (z - zmin) / CELL) for x, z in pts]

    def sample(field, xs_, zs_):
        return ndimage.map_coordinates(field, [(np.asarray(zs_) - zmin) / CELL, (np.asarray(xs_) - xmin) / CELL],
                                       order=1, mode="nearest")

    def paint(items, base):
        """Disegna (poligoni o tratti) le quote volute; restituisce maschera e differenza dal terreno."""
        target = Image.new("F", (w_px, h_px), 0.0)
        mask = Image.new("L", (w_px, h_px), 0)
        dt, dm = ImageDraw.Draw(target), ImageDraw.Draw(mask)
        for kind, geom, h, width in items:
            if kind == "poly":
                dt.polygon(geom, fill=h)
                dm.polygon(geom, fill=255)
                dt.line(geom + [geom[0]], fill=h, width=2)
                dm.line(geom + [geom[0]], fill=255, width=2)
            else:
                dt.line(geom, fill=h, width=width)
                dm.line(geom, fill=255, width=width)
                for cx, cz in geom:
                    box = [cx - width / 2, cz - width / 2, cx + width / 2, cz + width / 2]
                    dt.ellipse(box, fill=h)
                    dm.ellipse(box, fill=255)
        m = np.asarray(mask) > 127
        return m, np.where(m, np.asarray(target, dtype=np.float32) - base, 0.0)

    def blend(base, m, diff, sigma, reach):
        wm = ndimage.gaussian_filter(m.astype(np.float32), sigma)
        spread = ndimage.gaussian_filter(diff, sigma) / np.maximum(wm, 1e-4)
        return base + np.where(m, diff, spread * np.clip(wm * reach, 0.0, 1.0))

    # 1) Rete stradale: un nodo ogni 2 m, condiviso tra le strade che si incrociano.
    keys, pos, edges, triples, on_bridge = {}, [], [], [], []
    road_pieces = []
    for r in roads:
        if r["w"] <= 0:
            continue
        pts = list(zip(r["p"][0::2], r["p"][1::2]))
        ids, vert = [], []
        for j, ((ax, az), (bx, bz)) in enumerate(zip(pts, pts[1:])):
            k = max(1, int(math.hypot(bx - ax, bz - az) / CELL))
            for i in range(0 if j == 0 else 1, k + 1):
                p = (ax + (bx - ax) * i / k, az + (bz - az) * i / k)
                key = (round(p[0], 2), round(p[1], 2))
                if key not in keys:
                    keys[key] = len(pos)
                    pos.append(p)
                    on_bridge.append(False)
                if r.get("b"):
                    on_bridge[keys[key]] = True
                if i == 0 or i == k:
                    vert.append(keys[key])
                ids.append(keys[key])
        if len(pts) == 1:
            continue
        lam = 30.0 if r["k"] != "foot" else 4.0
        if r.get("b"):
            lam = 300.0  # i ponti sono dritti
        for a, b in zip(ids, ids[1:]):
            if a != b:
                edges.append((a, b))
        for a, b, c in zip(ids, ids[1:], ids[2:]):
            if a != b and b != c:
                triples.append((a, b, c, lam))
        road_pieces.append((r, ids, vert))
    pos = np.array(pos, dtype=np.float64)
    on_bridge = np.array(on_bridge)
    pos_kind = np.ones(len(pos), dtype=bool)  # True = solo vialetti pedonali (niente limite di pendenza)
    for r, ids, _v in road_pieces:
        if r["k"] != "foot":
            pos_kind[ids] = False
    # Dato misurato: media di centro e quarti della carreggiata (le strade vere sono in piano in larghezza).
    meas = np.zeros(len(pos))
    cnt = np.zeros(len(pos))
    for r, ids, _v in road_pieces:
        idx = np.array(ids)
        p = pos[idx]
        d = np.gradient(p, axis=0) if len(p) > 1 else np.ones_like(p)
        ln = np.maximum(np.hypot(d[:, 0], d[:, 1]), 1e-6)
        q = r["w"] * 0.25
        nx, nz = -d[:, 1] / ln * q, d[:, 0] / ln * q
        v = (sample(land, p[:, 0], p[:, 1]) * 2 + sample(land, p[:, 0] + nx, p[:, 1] + nz)
             + sample(land, p[:, 0] - nx, p[:, 1] - nz)) / 4.0
        np.add.at(meas, idx, v)
        np.add.at(cnt, idx, 1)
    meas /= np.maximum(cnt, 1)
    weight = np.where(on_bridge, 0.0, 1.0)  # sotto i ponti il LiDAR vede il fiume o la strada di sotto
    hnode = _solve_profiles(pos, edges, triples, meas, weight, None)
    # Seconda passata robusta: dove il dato era una buca o un dosso isolato (auto, cantieri) conta meno.
    res = np.abs(hnode - meas)
    weight = np.where(on_bridge, 0.0, 1.0 / (1.0 + (res / 0.5) ** 2))
    hnode = _solve_profiles(pos, edges, triples, meas, weight, None)
    # Ponti e viadotti: dritti tra i loro attacchi. Per ogni gruppo di ponti collegati, le quote alle estremità
    # che toccano strade a terra restano fisse e in mezzo si interpola lungo il ponte (scale e rampe pedonali che
    # scendono dal viadotto non lo tirano giù); poi la rete a terra si ricalcola con i ponti fermi.
    from scipy import sparse
    from scipy.sparse.linalg import spsolve
    bridge_e = [(a, b) for (r, ids, _v) in road_pieces if r.get("b") for a, b in zip(ids, ids[1:]) if a != b]
    if bridge_e:
        ground_car = np.zeros(len(pos), dtype=bool)
        ground_any = np.zeros(len(pos), dtype=bool)
        for r, ids, _v in road_pieces:
            if not r.get("b"):
                ground_any[ids] = True
                if r["k"] != "foot":
                    ground_car[ids] = True
        bn = np.unique(np.array(bridge_e).ravel())
        loc = {int(n): i for i, n in enumerate(bn)}
        ba = np.array([loc[a] for a, _ in bridge_e])
        bb = np.array([loc[b] for _, b in bridge_e])
        nb_ = len(bn)
        adj = sparse.coo_matrix((np.ones(len(ba)), (ba, bb)), shape=(nb_, nb_)).tocsr()
        ncomp, comp = sparse.csgraph.connected_components(adj, directed=False)
        deg = np.bincount(np.r_[ba, bb], minlength=nb_)
        anchor = np.zeros(nb_, dtype=bool)
        for ci in range(ncomp):  # attacchi = estremità del ponte che toccano terra (meglio se una strada carrabile)
            members = (comp == ci) & (deg == 1)
            car_anchor = members & ground_car[bn]
            anchor |= car_anchor if car_anchor.any() else members & ground_any[bn]
        L = sparse.coo_matrix((np.r_[np.ones(len(ba)), np.ones(len(ba))], (np.r_[ba, bb], np.r_[bb, ba])), shape=(nb_, nb_)).tocsr()
        # Carreggiate e marciapiedi paralleli dello stesso viadotto (stesso nome, entro 22 m) legati di traverso:
        # ognuno da solo andava dritto tra i suoi attacchi e corsie accanto finivano a quote diverse, con "muri"
        # tra l'una e l'altra (Corso di Francia). Legati, il viadotto resta in piano in larghezza.
        # Le rampe (carreggiate strette) restano libere: scendono a fianco del viadotto, non sono in piano con lui.
        names = [""] * nb_
        for r, ids, _v in road_pieces:
            if r.get("b") and r.get("n") and (r["k"] == "foot" or float(r.get("w", 0)) >= 10.0):
                for i in ids:
                    names[loc[i]] = r["n"]
        from scipy.spatial import cKDTree as _KD
        la, lb = [], []
        for i, j in _KD(pos[bn]).query_pairs(22.0):
            if comp[i] != comp[j] and names[i] and names[i] == names[j]:
                la.append(i)
                lb.append(j)
        comp_all, ncomp_all = comp, ncomp
        if la:
            la, lb = np.array(la), np.array(lb)
            L = L + sparse.coo_matrix((np.full(2 * len(la), 4.0), (np.r_[la, lb], np.r_[lb, la])), shape=(nb_, nb_)).tocsr()
            ncomp_all, comp_all = sparse.csgraph.connected_components(L, directed=False)
            print(f"  viadotti: {len(la)} legami di traverso tra corsie parallele")
        Lap = sparse.diags(np.asarray(L.sum(1)).ravel()) - L
        fixed = anchor.copy()
        for ci in range(ncomp_all):  # gruppi senza attacchi: restano come li ha risolti la rete
            if not (anchor & (comp_all == ci)).any():
                fixed |= comp_all == ci
        hb = hnode[bn].copy()
        free = ~fixed

        def harmonic():
            if free.any():
                hb[free] = spsolve(Lap[free][:, free].tocsc(), -Lap[free][:, fixed] @ hb[fixed])

        harmonic()
        # I marciapiedi di un viadotto si attaccano alla quota della carreggiata accanto, non al terreno sotto.
        car_b = np.zeros(nb_, dtype=bool)
        for r, ids, _v in road_pieces:
            if r.get("b") and r["k"] != "foot":
                car_b[[loc[i] for i in ids]] = True
        foot_comp = [ci for ci in range(ncomp) if not (car_b & (comp == ci)).any()]
        if car_b.any() and foot_comp:
            from scipy.spatial import cKDTree as _T
            ct = _T(pos[bn[car_b]])
            car_list = np.nonzero(car_b)[0]
            for ci in foot_comp:
                for i in np.nonzero((comp == ci) & anchor)[0]:
                    dd, j = ct.query(pos[bn[i]])
                    if dd < 15.0:
                        hb[i] = hb[car_list[j]]
            harmonic()
        data2 = meas.copy()
        w2 = np.where(on_bridge, 0.0, weight)
        data2[bn] = hb
        w2[bn] = 1e4
        hnode = _solve_profiles(pos, edges, triples, data2, w2, None)

    # Pendenza massima delle carreggiate (le più ripide di Roma nord stanno sul 12-15%): dove il dato è grossolano
    # (fuori dal LiDAR la strada sotto una scarpata "vede" la scarpata) i nodi troppo ripidi si avvicinano di quota.
    car_e = np.array([not (pos_kind[a] or pos_kind[b]) for a, b in edges])
    ea, eb = np.array([e[0] for e in edges])[car_e], np.array([e[1] for e in edges])[car_e]
    lim = 0.16 * np.hypot(*(pos[ea] - pos[eb]).T)
    for _ in range(3000):
        d = hnode[ea] - hnode[eb]
        ex = np.sign(d) * np.maximum(np.abs(d) - lim, 0.0) * 0.5
        if np.abs(ex).max() < 0.01:
            break
        corr = np.zeros_like(hnode)
        cnt = np.zeros_like(hnode)
        np.add.at(corr, ea, -ex)
        np.add.at(corr, eb, ex)
        np.add.at(cnt, ea, 1)
        np.add.at(cnt, eb, 1)
        hnode += corr / np.maximum(cnt, 1) * 1.6

    # Ponti: quota ai vertici per impalcato e parapetti.
    for r, ids, vert in road_pieces:
        if r.get("b"):
            r["y"] = [round(float(hnode[i]), 2) for i in vert]

    items = []
    for r, ids, _v in sorted(road_pieces, key=lambda t: t[0]["w"]):  # prima le strette, sopra le grandi
        if r.get("b"):
            continue
        width = max(1, int(round((r["w"] + (3.0 if r["k"] == "road" else 1.0)) / CELL)))
        for a, b in zip(ids, ids[1:]):
            if a != b:
                items.append(("seg", px([pos[a], pos[b]]), float((hnode[a] + hnode[b]) * 0.5), width))
    road_items = items
    rm, rdiff = paint(road_items, land)
    # 2) Gli isolati seguono le loro strade per una decina di metri.
    guide = blend(land, rm, rdiff, 4.0, 3.0)
    if gap_w.any():
        # Fuori dal LiDAR il terreno a 10 m è troppo grossolano: lì comandano le strade, raccordate su ~40 m.
        wide = blend(land, rm, rdiff, 10.0, 8.0)
        guide = guide * (1 - gap_w) + wide * gap_w

    # 3) Piazze e campi sportivi in piano, palazzi su un piano alla quota della strada carrabile più vicina.
    from scipy.spatial import cKDTree
    car = np.zeros(len(pos), dtype=bool)
    for r, ids, _v in road_pieces:
        if r["k"] == "road" and not r.get("b"):
            car[ids] = True
    car_idx = np.nonzero(car)[0]
    tree = cKDTree(pos[car_idx]) if len(car_idx) else None
    items = []
    for a in sorted(areas, key=lambda a: -abs(ring_area(list(zip(a["p"][0::2], a["p"][1::2]))))):
        if a["k"] not in ("plaza", "pitch"):
            continue
        ring = list(zip(a["p"][0::2], a["p"][1::2]))
        items.append(("poly", px(ring), float(np.median(sample(guide, [p[0] for p in ring], [p[1] for p in ring]))), 0))
    for b in sorted(buildings, key=lambda b: -abs(ring_area(list(zip(b["p"][0::2], b["p"][1::2]))))):
        if b.get("m") or b.get("part"):
            continue
        if LANDMARKS.get(b["id"], ("",))[0] == "cavea":
            continue  # la cavea dell'Auditorium è una conca: niente piano, le gradinate seguono il terreno vero
        ring = list(zip(b["p"][0::2], b["p"][1::2]))
        hs = sample(guide, [p[0] for p in ring], [p[1] for p in ring])
        h = float(np.median(hs))
        if tree is not None:
            dist_r, which = tree.query(np.array(ring))
            k = int(np.argmin(dist_r))
            road_h = float(hnode[car_idx[which[k]]]) + 0.15  # marciapiede
            if dist_r[k] < 20.0 and hs.min() - 0.5 <= road_h <= hs.max() + 0.5:
                h = road_h  # l'ingresso è sulla strada; se la strada è su un altro livello resta il terreno
        items.append(("poly", px(ring), h, 0))
    bm, bdiff = paint(items, guide)
    out = blend(guide, bm, bdiff, 1.5, 2.5)
    # 4) Sopra tutto le carreggiate, raccordate in pochi metri.
    rm, rdiff = paint(road_items, out)
    out = blend(out, rm, rdiff, 1.0, 2.5)
    out *= river_t
    if os.environ.get('RILIEVO_DEBUG'):
        np.savez(os.environ['RILIEVO_DEBUG'], land=land, out=out, pos=pos, hnode=hnode, meas=meas, ea=np.array([e[0] for e in edges]), eb=np.array([e[1] for e in edges]), car=car, bridge=on_bridge, xmin=xmin, zmin=zmin)

    ea, eb = np.array([e[0] for e in edges]), np.array([e[1] for e in edges])
    gr = np.abs(hnode[ea] - hnode[eb]) / np.maximum(np.hypot(*(pos[ea] - pos[eb]).T), 1e-3)
    carry = car[ea] & car[eb]
    print("rilievo: LiDAR, %.1f m sul mare = quota zero (lungotevere), da %.1f a %.1f m; strade: %d nodi, "
          "pendenza max %.0f%% (99%%: %.0f%%)" % (ref, out.min(), out.max(), len(pos), gr[carry].max() * 100,
                                                  np.percentile(gr[carry], 99) * 100))
    return out.astype(np.float32)


def worldcover_fill(proj, xmin, zmin, cw, ch, roads, buildings, areas, data_dir):
    """Prati e alberi che OpenStreetMap non ha (aiuole, cortili, scarpate, filari), dalla carta ESA WorldCover a 10 m
    (tools/fetch_worldcover.py). Restituisce (rgba 1 m per pixel con il prato di base, punti dove mettere alberi).
    Strade con i loro marciapiedi, piazze e palazzi restano liberi. None se manca il dato."""
    import os
    from scipy import ndimage
    path = os.path.join(data_dir, "dem", "worldcover.npy")
    if not os.path.exists(path) or "--senza-worldcover" in sys.argv:
        return None, []
    wc = np.load(path)
    meta = json.load(open(path.replace(".npy", ".json")))
    xs = xmin + np.arange(cw) + 0.5
    zs = zmin + np.arange(ch) + 0.5
    lon = proj.lon0 + xs / proj.kx
    lat = proj.lat0 - zs / proj.kz
    fr = (meta["lat0"] - lat) / meta["step"] - 0.5
    fc = (lon - meta["lon0"]) / meta["step"] - 0.5
    FR, FC = np.meshgrid(fr, fc, indexing="ij")

    def soft(classes):  # maschera a 10 m portata a 1 m con bordi arrotondati
        m = np.isin(wc, classes).astype(np.float32)
        m = ndimage.gaussian_filter(m, 0.6)
        return ndimage.map_coordinates(m, [FR, FC], order=1, mode="nearest") > 0.5

    tree = soft([10])
    grass = soft([20, 30, 40]) & ~tree
    # Spazi che restano pavimentati: carreggiate con i marciapiedi, vialetti, piazze, palazzi.
    block = Image.new("L", (cw, ch), 0)
    db = ImageDraw.Draw(block)
    for r in roads:
        if r["w"] <= 0:
            continue
        pts = [(x - xmin, z - zmin) for x, z in zip(r["p"][0::2], r["p"][1::2])]
        width = r["w"] + (6.0 if r["k"] == "road" else 1.0)
        db.line(pts, fill=255, width=max(1, int(round(width))))
        for x, z in pts:
            db.ellipse([x - width / 2, z - width / 2, x + width / 2, z + width / 2], fill=255)
    for b in buildings:
        db.polygon([(x - xmin, z - zmin) for x, z in zip(b["p"][0::2], b["p"][1::2])], fill=255)
    for a in areas:
        if a["k"] in ("plaza", "water"):
            db.polygon([(x - xmin, z - zmin) for x, z in zip(a["p"][0::2], a["p"][1::2])], fill=255)
    blocked = np.asarray(block) > 127
    rgba = np.zeros((ch, cw, 4), dtype=np.uint8)
    rgba[..., :3] = (107, 140, 71)
    rgba[tree] = (84, 115, 56, 255)  # sotto gli alberi l'erba è più scura
    rgba[grass] = (107, 140, 71, 255)
    rgba[blocked, 3] = 0
    # Via i ritagli: strisce strette e pezzetti (resti tra due carreggiate, angoli di marciapiede).
    lawn = ndimage.binary_opening(rgba[..., 3] > 0, iterations=2)
    lab, n = ndimage.label(lawn)
    if n:
        size = ndimage.sum(lawn, lab, range(1, n + 1))
        lawn = np.isin(lab, 1 + np.nonzero(size >= 60)[0])
    rgba[..., 3] = np.where(lawn, 255, 0).astype(np.uint8)
    # Un albero per ogni cella "alberi" della carta (10 x 10 m), spostato a caso, fuori da strade e palazzi.
    free = ~ndimage.binary_dilation(blocked, iterations=2)
    rng = np.random.default_rng(7)
    cells = np.argwhere(wc == 10)
    spots = []
    for r_, c_ in cells:
        la = meta["lat0"] - (r_ + rng.uniform(0.15, 0.85)) * meta["step"]
        lo = meta["lon0"] + (c_ + rng.uniform(0.15, 0.85)) * meta["step"]
        x, z = proj.xz(la, lo)
        i, j = int(z - zmin), int(x - xmin)
        if 0 <= i < ch and 0 <= j < cw and free[i, j]:
            spots.append((x, z))
    print("WorldCover: prato aggiunto %.0f%% della mappa, %d posti per alberi" %
          (100 * (rgba[..., 3] > 0).mean(), len(spots)))
    return rgba, spots


def hillshade(relief):
    """Ombreggiatura del rilievo per la minimappa (luce da nord-ovest), 1 = piano."""
    gz, gx = np.gradient(relief, CELL)
    nx, nz, ny = -gx, -gz, np.ones_like(relief)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    lx, ly, lz = -0.5, 0.7, -0.5
    lit = (nx * lx + ny * ly + nz * lz) / (ln * math.sqrt(lx * lx + ly * ly + lz * lz))
    flat = ly / math.sqrt(lx * lx + ly * ly + lz * lz)
    return np.clip(1.0 + (lit - flat) * 2.2, 0.55, 1.25)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "data/flaminio_raw.json"
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "data"
    raw = json.load(open(src, encoding="utf-8"))
    proj = Projector(raw["bbox"])
    xmin, xmax = -proj.half_w, proj.half_w
    zmin, zmax = -proj.half_h, proj.half_h
    rnd = random.Random(42)
    # Colori misurati sulle foto di strada (tools/fetch_facciate.py), dove OSM non dice nulla.
    import os.path as osp
    photo_path = osp.join(out_dir, "colori_facciate.json")
    photo_cols = json.load(open(photo_path, encoding="utf-8")) if osp.exists(photo_path) else {}

    def geom_pts(geom):
        return [proj.xz(g["lat"], g["lon"]) for g in geom if g]

    def rd(p):
        return [round(p[0], 2), round(p[1], 2)]

    def flat(pts):
        return [c for p in pts for c in rd(p)]

    buildings, roads, areas, trees, water_rings = [], [], [], [], []

    def make_building(osm_id, tags, ring, a):
        part = "building:part" in tags and "building" not in tags
        b = {"p": flat(ring), "h": round(building_height(tags, a), 1),
             "c": rnd.randrange(len(COLORS)), "n": tags.get("name", ""), "id": osm_id,
             "k": tags.get("building") or tags.get("building:part") or "yes"}
        mh = parse_float(tags.get("min_height"))
        if mh:
            b["m"] = round(mh, 1)
        if part:
            b["part"] = 1
        if tags.get("roof:shape"):
            b["roof"] = tags["roof:shape"]
        col = real_colour(tags) or photo_cols.get(str(osm_id))
        if col:
            b["col"] = col
        return b

    def add_area(pts, kind):
        pts = clean_ring(pts)
        pts = clip_ring(pts, xmin, zmin, xmax, zmax)
        pts = clean_ring(pts)
        if len(pts) < 3 or abs(ring_area(pts)) < 4:
            return
        areas.append({"k": kind, "p": flat(pts)})
        if kind == "water":
            water_rings.append(pts)

    def area_kind(tags):
        if tags.get("natural") == "water" or tags.get("waterway") == "riverbank":
            return "water"
        if tags.get("leisure") in ("pitch", "stadium"):
            return "pitch"
        if tags.get("leisure") == "playground":
            return "play"
        if tags.get("natural") in ("wood", "scrub") or tags.get("landuse") == "forest":
            return "wood"
        if tags.get("leisure") or tags.get("landuse"):
            return "green"
        return None

    for e in raw["elements"]:
        tags = e.get("tags", {})
        t = e["type"]
        if t == "node":
            if tags.get("natural") == "tree":
                x, z = proj.xz(e["lat"], e["lon"])
                trees.append(rd((x, z)))
            continue

        if t == "way":
            pts = geom_pts(e.get("geometry", []))
            closed = len(pts) > 3 and e["geometry"][0] == e["geometry"][-1]
            if ("building" in tags or "building:part" in tags) and closed:
                ring = clean_ring(pts)
                if len(ring) >= 3 and all(xmin <= p[0] <= xmax and zmin <= p[1] <= zmax for p in ring):
                    a = abs(ring_area(ring))
                    if a > 1.5:
                        buildings.append(make_building(e["id"], tags, ring, a))
                continue
            if "highway" in tags or tags.get("railway") == "tram":
                hw = tags.get("highway", "")
                if tags.get("railway") == "tram":
                    kind, width = "tram", 2.0
                else:
                    if hw not in ROAD_WIDTH or ROAD_WIDTH[hw] == 0:
                        continue
                    if tags.get("area") == "yes":
                        if closed and hw == "pedestrian":
                            add_area(pts, "plaza")
                        continue
                    kind = "foot" if hw in FOOT else "road"
                    width = parse_float(tags.get("width")) or ROAD_WIDTH[hw]
                    if kind == "road" and tags.get("lanes"):
                        width = max(width, (parse_float(tags.get("lanes")) or 2) * 3.3)
                if tags.get("tunnel") in ("yes", "building_passage") or (parse_float(tags.get("layer")) or 0) < 0:
                    continue
                if not any(xmin - 50 <= p[0] <= xmax + 50 and zmin - 50 <= p[1] <= zmax + 50 for p in pts):
                    continue
                roads.append({"k": kind, "w": round(width, 1), "p": flat(pts),
                              "b": 1 if tags.get("bridge") in ("yes", "viaduct") else 0,
                              # senso unico: 1 nel verso del disegno, -1 al contrario, 0 doppio senso
                              "o": (1 if tags.get("oneway") in ("yes", "true", "1")
                                    or tags.get("junction") in ("roundabout", "circular")
                                    or hw in ("motorway", "motorway_link")
                                    else -1 if tags.get("oneway") == "-1" else 0),
                              "n": tags.get("name", "")})
                continue
            kind = area_kind(tags)
            if kind and closed:
                add_area(pts, kind)
            continue

        if t == "relation":
            outers = [geom_pts(m.get("geometry", [])) for m in e.get("members", [])
                      if m.get("role") in ("outer", "") and m["type"] == "way"]
            if "building" in tags:
                if tags.get("type") != "multipolygon":
                    continue
                for ring in join_rings(outers):
                    ring = clean_ring(ring)
                    if len(ring) >= 3 and all(xmin <= p[0] <= xmax and zmin <= p[1] <= zmax for p in ring):
                        a = abs(ring_area(ring))
                        if a > 6:
                            b = make_building(e["id"], tags, ring, a)
                            if e["id"] == 63038:  # Stadio Flaminio: serve anche il buco del campo
                                inner = [geom_pts(m.get("geometry", [])) for m in e.get("members", [])
                                         if m.get("role") == "inner" and m["type"] == "way"]
                                b["inner"] = [flat(clean_ring(r)) for r in join_rings(inner)]
                            buildings.append(b)
                continue
            kind = area_kind(tags)
            if kind:
                for ring in join_rings(outers):
                    if len(ring) > 3 and ring[0] == ring[-1]:
                        add_area(ring, kind)

    # Rilievo: Tevere scavato (sotto quota 0); il rilievo vero si aggiunge dopo (land_relief).
    w_px = int(math.ceil((xmax - xmin) / CELL)) + 1
    h_px = int(math.ceil((zmax - zmin) / CELL)) + 1
    mask = Image.new("L", (w_px, h_px), 0)
    draw = ImageDraw.Draw(mask)
    for ring in water_rings:
        if abs(ring_area(ring)) < 5000:  # fontane e vasche restano piatte
            continue
        draw.polygon([((x - xmin) / CELL, (z - zmin) / CELL) for x, z in ring], fill=255)
    water = np.asarray(mask) > 127
    # Solo il Tevere va scavato tra i muraglioni: laghetti e vasche dei parchi restano alla quota del terreno.
    from scipy import ndimage
    lab, nlab = ndimage.label(water)
    sizes = ndimage.sum(water, lab, range(1, nlab + 1))
    water = np.isin(lab, [i + 1 for i, sz in enumerate(sizes) if sz * CELL * CELL > 80000])

    def grow(a, steps):
        """Dilatazione di un pixel per passo (8 vicini); restituisce la lista delle maschere."""
        out = [a]
        for _ in range(steps):
            b = out[-1].copy()
            b[1:, :] |= out[-1][:-1, :]
            b[:-1, :] |= out[-1][1:, :]
            b[:, 1:] |= out[-1][:, :-1]
            b[:, :-1] |= out[-1][:, 1:]
            out.append(b)
        return out

    # Tevere tra i muraglioni: strada a quota 0, muro di ~10 m, banchina larga ~8 m a -9,5, acqua a -10,5.
    heights = np.zeros(water.shape, dtype=np.float32)
    outer = grow(water, 6)
    heights[outer[6]] = -2.0
    heights[outer[5]] = -6.0
    heights[outer[4]] = BANK_Y
    inner = grow(~water, 6)  # inner[k] = acqua a meno di k pixel dalla riva
    heights[water] = RIVER_BED
    for k in range(5, 0, -1):
        heights[water & inner[k]] = -11.5 - (k - 1) * 0.5  # fondale che scende dalla riva verso il centro
    import os
    relief = land_relief(proj, xmin, zmin, w_px, h_px, water, buildings, roads, areas, os.path.dirname(os.path.abspath(out_dir + "/x")))
    heights = heights + relief
    relief.astype("<f4").tofile(f"{out_dir}/relief.bin")
    heights.astype("<f4").tofile(f"{out_dir}/heights.bin")
    (heights / CELL).astype("<f4").tofile(f"{out_dir}/heights_phys.bin")  # per la collisione scalata

    # Minimappa: 1 pixel = CELL metri, stessa griglia del rilievo.
    def to_px(pts):
        return [((x - xmin) / CELL, (z - zmin) / CELL) for x, z in pts]

    cw, ch = int(math.ceil(xmax - xmin)), int(math.ceil(zmax - zmin))
    import os
    wc_rgba, wc_trees = worldcover_fill(proj, xmin, zmin, cw, ch, roads, buildings, areas,
                                        os.path.dirname(os.path.abspath(out_dir + "/x")))
    mm = Image.new("RGB", (w_px, h_px), (214, 208, 196))
    if wc_rgba is not None:  # prati e alberi della carta WorldCover anche sulla minimappa (sotto le aree di OSM)
        lawn = Image.fromarray(wc_rgba[..., 3]).resize((w_px, h_px), Image.BILINEAR)
        mm.paste((182, 204, 156), mask=lawn.point(lambda v: 255 if v > 127 else 0))
    md = ImageDraw.Draw(mm)
    area_col = {"green": (178, 206, 150), "wood": (150, 188, 128), "pitch": (160, 200, 140),
                "play": (190, 210, 160), "plaza": (226, 220, 206), "water": (140, 182, 222)}
    for kind in ("green", "wood", "pitch", "play", "plaza", "water"):
        for a in areas:
            if a["k"] == kind:
                md.polygon(to_px(list(zip(a["p"][0::2], a["p"][1::2]))), fill=area_col[kind])
    for r in roads:
        pts = to_px(list(zip(r["p"][0::2], r["p"][1::2])))
        if r["k"] == "foot":
            md.line(pts, fill=(236, 232, 222), width=1)
    for r in roads:
        pts = to_px(list(zip(r["p"][0::2], r["p"][1::2])))
        if r["k"] == "road":
            md.line(pts, fill=(255, 255, 255), width=max(2, int(r["w"] / CELL)), joint="curve")
    for b in buildings:
        md.polygon(to_px(list(zip(b["p"][0::2], b["p"][1::2]))), fill=(186, 160, 140), outline=(160, 136, 118))
    shade = hillshade(relief)[:, :, None]
    mm = Image.fromarray(np.clip(np.asarray(mm, dtype=np.float32) * shade, 0, 255).astype(np.uint8))
    mm.save(f"{out_dir}/minimap.png")

    # Coperture del suolo per lo shader del terreno (1 m per pixel): RGB = tinta dell'erba (come AREA_COLORS di
    # CityBuilder), A = 255 dove c'è prato. Il prato fa parte del terreno stesso: segue il rilievo senza buchi.
    # PNG salvato come .bin perché Godot non provi a importarlo; lo legge CityBuilder.
    cover_tint = {"green": (107, 140, 71), "wood": (84, 115, 56), "pitch": (92, 153, 77), "play": (128, 122, 77)}
    cover = Image.fromarray(wc_rgba, "RGBA") if wc_rgba is not None else Image.new("RGBA", (cw, ch), (107, 140, 71, 0))
    dc = ImageDraw.Draw(cover)
    for a in sorted(areas, key=lambda a: -abs(ring_area(list(zip(a["p"][0::2], a["p"][1::2]))))):
        if a["k"] not in cover_tint and a["k"] != "plaza":
            continue
        ring = [(x - xmin, z - zmin) for x, z in zip(a["p"][0::2], a["p"][1::2])]
        dc.polygon(ring, fill=cover_tint[a["k"]] + (255,) if a["k"] in cover_tint else (107, 140, 71, 0))
    # Bordi morbidi (lo shader taglia a metà): niente scalini da un metro.
    from scipy import ndimage as _nd
    arr = np.asarray(cover).copy()
    arr[..., 3] = np.clip(_nd.gaussian_filter(arr[..., 3].astype(np.float32), 0.8), 0, 255).astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(f"{out_dir}/cover_png.bin", format="PNG", optimize=True)

    # Alberi nei parchi: distribuzione casuale nei poligoni verdi.
    def inside(px, pz, ring):
        res = False
        j = len(ring) - 1
        for i in range(len(ring)):
            xi, zi = ring[i]
            xj, zj = ring[j]
            if (zi > pz) != (zj > pz) and px < (xj - xi) * (pz - zi) / (zj - zi + 1e-12) + xi:
                res = not res
            j = i
        return res

    for a in areas:
        if a["k"] not in ("green", "wood"):
            continue
        ring = list(zip(a["p"][0::2], a["p"][1::2]))
        area = abs(ring_area(ring))
        density = 1 / 260 if a["k"] == "green" else 1 / 90
        n = min(int(area * density), 600)
        xs = [p[0] for p in ring]
        zs = [p[1] for p in ring]
        tries = 0
        while n > 0 and tries < n * 20:
            tries += 1
            px, pz = rnd.uniform(min(xs), max(xs)), rnd.uniform(min(zs), max(zs))
            if inside(px, pz, ring):
                trees.append(rd((px, pz)))
                n -= 1

    # Alberi della carta WorldCover dove non ce n'è già uno vicino (filari, cortili, scarpate).
    if wc_trees:
        from scipy.spatial import cKDTree
        have = cKDTree(np.array(trees, dtype=np.float64)) if trees else None
        added = []
        for x, z in wc_trees:
            if have is not None and have.query((x, z))[0] < 7.0:
                continue
            if added and min(abs(x - ax) + abs(z - az) for ax, az in added[-40:]) < 6.0:
                continue
            added.append((x, z))
            trees.append(rd((x, z)))
        print("WorldCover: %d alberi in più" % len(added))

    # Punto di partenza: il punto di strada più vicino a Piazza Apollodoro.
    sx, sz = proj.xz(*SPAWN_LATLON)
    best, best_d = (sx, sz), 1e18
    for r in roads:
        if r["k"] != "road":
            continue
        for i in range(0, len(r["p"]), 2):
            d = (r["p"][i] - sx) ** 2 + (r["p"][i + 1] - sz) ** 2
            if d < best_d:
                best_d, best = d, (r["p"][i], r["p"][i + 1])

    landmarks, walls, bridges, pois = extract_extras(raw, proj, buildings, flat, rd, geom_pts, (xmin, zmin, xmax, zmax))
    labels = street_labels(roads)

    city = {
        "bbox_m": [round(xmin, 1), round(zmin, 1), round(xmax, 1), round(zmax, 1)],
        "origin_latlon": [proj.lat0, proj.lon0],
        "cell": CELL, "hmap_size": [w_px, h_px], "cover_size": [cw, ch], "river_depth": RIVER_DEPTH, "water_y": WATER_Y, "bank_y": BANK_Y,
        "colors": COLORS, "spawn": rd(best),
        "buildings": buildings, "roads": roads, "areas": areas, "trees": trees,
        "landmarks": landmarks, "walls": walls, "bridges": bridges, "pois": pois, "labels": labels,
    }
    with open(f"{out_dir}/city.json", "w", encoding="utf-8") as f:
        json.dump(city, f, separators=(",", ":"), ensure_ascii=False)
    print(f"edifici {len(buildings)}, strade {len(roads)}, aree {len(areas)}, alberi {len(trees)}, "
          f"rilievo {w_px}x{h_px}, area {xmax - xmin:.0f}x{zmax - zmin:.0f} m, partenza {best}")


if __name__ == "__main__":
    main()
