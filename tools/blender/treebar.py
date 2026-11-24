"""Tree Bar (Via Flaminia, Roma) costruito in Blender da script, sulla pianta reale di OpenStreetMap.

Uso:  blender --background --python tools/blender/treebar.py
Scrive assets/locali/treebar/treebar.glb (lo carica scripts/locali.gd) e tools/blender/treebar.blend.

Riferimenti: tour interno pubblicato dal locale su Google Maps (2014) e Street View 2024 (foto in
tools/cache_streetview/treebar/, non pubblicate). Texture CC0 di ambientCG in tools/blender/textures/.

Sistema locale: u lungo il lato corto dell'edificio OSM 1132263633 (verso est-nord-est), v lungo il lato lungo
(verso sud); origine nel suo spigolo nord-ovest. In Blender X = u, Y = -v, Z = alto: esportato in glTF diventa
x = u, y = alto, z = v, cioè lo stesso verso di Godot (x est, z sud) ruotato di ~16,5° (vedi locali.gd).

Pianta (metri):
  A  edificio 1132263633: u 0..6,95, v 0..12,8. Bar a nord (v 0..7), cucina col forno a sud.
  B  edificio 1132263632: u 6,95..11,7, v 1,2..9,2. Sala ristorante, soffitto in larice inclinato, vetrate sul parco.
  Dehors: pergolato in legno a nord-est (u 5..12, v -7..-0,6).
I nomi che finiscono in "-col" diventano anche collisioni in Godot.
"""
import math
import os
import random

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TEX = os.path.join(HERE, "textures")
OUT = os.path.join(ROOT, "assets", "locali", "treebar", "treebar.glb")

AU, AV = 6.95, 12.8          # edificio A
BU0, BU1, BV0, BV1 = 6.95, 11.7, 1.2, 9.2  # edificio B
FLOOR = 0.12                 # pavimento sopra il terreno
H_A = 3.3                    # soffitto piano del bar
ROOF0, ROOF1 = 3.45, 3.95    # lastra bianca del tetto (OSM: 4 m)
WALL = 0.2

random.seed(7)

# --- Scena pulita -------------------------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
col = bpy.context.collection

# --- Materiali --------------------------------------------------------------------------------------------------
MATS = {}
UVSCALE = {}


BAKED = os.path.join(HERE, "textures", "_pronte")  # texture già tinte e ridotte, quelle che finiscono nel .glb
TEXSIZE = 512


def _img(path, name, tint=None, color=True):
    """Carica una texture, la tinge (moltiplica) e la riduce a TEXSIZE; la salva in JPEG in BAKED."""
    import numpy as np
    os.makedirs(BAKED, exist_ok=True)
    out = os.path.join(BAKED, name + ".jpg")
    im = bpy.data.images.load(path)
    if not color:
        im.colorspace_settings.name = "Non-Color"
    im.scale(TEXSIZE, TEXSIZE)
    if tint:
        px = np.empty(TEXSIZE * TEXSIZE * 4, dtype=np.float32)
        im.pixels.foreach_get(px)
        px = px.reshape(-1, 4)
        # tint = colore medio voluto ('#rrggbb'): la texture viene scalata canale per canale fino ad averlo
        want = np.array([int(tint[i:i + 2], 16) / 255 for i in (1, 3, 5)], dtype=np.float32)
        px[:, :3] = np.clip(px[:, :3] * (want / np.maximum(px[:, :3].mean(axis=0), 1e-3)), 0.0, 1.0)
        im.pixels.foreach_set(px.ravel())
    im.filepath_raw = out
    im.file_format = "JPEG"
    scene.render.image_settings.quality = 85
    im.save(filepath=out, quality=85) if bpy.app.version >= (4, 0, 0) else im.save()
    bpy.data.images.remove(im)
    _strip_icc(out)
    im2 = bpy.data.images.load(out)
    if not color:
        im2.colorspace_settings.name = "Non-Color"
    return im2


def _strip_icc(path):
    """Toglie il profilo colore (segmento APP2) che Blender scrive nei JPEG: Godot non li legge."""
    d = open(path, "rb").read()
    out, k = bytearray(d[:2]), 2
    while k < len(d) - 4 and d[k] == 0xFF and d[k + 1] != 0xDA:
        n = int.from_bytes(d[k + 2:k + 4], "big")
        if d[k + 1] != 0xE2:
            out += d[k:k + 2 + n]
        k += 2 + n
    out += d[k:]
    open(path, "wb").write(bytes(out))


def mat_tex(name, tex, tint=None, scale=1.0, rough=None, metal=0.0, normal=True):
    m = bpy.data.materials.new(name)
    if hasattr(m, "use_nodes") and not m.node_tree:
        m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    base = os.path.join(TEX, tex)
    ci = nt.nodes.new("ShaderNodeTexImage")
    ci.image = _img(os.path.join(base, "color.jpg"), name + "_color", tint=tint)
    nt.links.new(ci.outputs["Color"], bsdf.inputs["Base Color"])
    rp = os.path.join(base, "rough.jpg")
    if rough is None and os.path.exists(rp):
        ri = nt.nodes.new("ShaderNodeTexImage")
        ri.image = _img(rp, name + "_rough", color=False)
        nt.links.new(ri.outputs["Color"], bsdf.inputs["Roughness"])
    else:
        bsdf.inputs["Roughness"].default_value = rough if rough is not None else 0.6
    np_ = os.path.join(base, "normal.jpg")
    if normal and os.path.exists(np_):
        ni = nt.nodes.new("ShaderNodeTexImage")
        ni.image = _img(np_, name + "_normal", color=False)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(ni.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Metallic"].default_value = metal
    MATS[name] = m
    UVSCALE[name] = scale
    return m


def mat_flat(name, color, rough=0.5, metal=0.0, emit=None, alpha=1.0):
    m = bpy.data.materials.new(name)
    if hasattr(m, "use_nodes") and not m.node_tree:
        m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit[0], 1)
        bsdf.inputs["Emission Strength"].default_value = emit[1]
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        m.blend_method = "BLEND" if hasattr(m, "blend_method") else None
        try:
            m.surface_render_method = "BLENDED"
        except AttributeError:
            pass
    MATS[name] = m
    UVSCALE[name] = 1.0
    return m


def srgb(h):
    """'#rrggbb' → colore lineare (Blender lavora in lineare)."""
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


mat_tex("larice", "Wood066", tint="#c88048", scale=1.2)            # soffitto e travi della sala
mat_tex("legno_chiaro", "Wood094", tint="#d4a068", scale=0.8)      # bancone a doghe, scaffali, infissi
mat_tex("legno_tavoli", "Wood049", tint="#b48858", scale=0.8)
mat_tex("legno_scuro", "Wood051", tint="#7a4c30", scale=1.0)       # rivestimento esterno (2024)
mat_tex("cemento", "Concrete034", tint="#9c9a96", scale=2.0, rough=0.6)  # pavimento in cemento lisciato
mat_tex("cemento_piano", "Concrete034", tint="#c4c2bc", scale=1.0, rough=0.4)  # piano del bancone
mat_tex("intonaco", "Plaster001", tint="#efede8", scale=2.0)       # muri bianchi
mat_tex("divano", "Fabric062", tint="#d6c6a4", scale=0.5)
mat_flat("vetro", srgb("#c8dde0"), rough=0.03, alpha=0.18)
mat_flat("acciaio", srgb("#c8c8c8"), rough=0.25, metal=1.0)
mat_flat("nero", srgb("#1a1a1a"), rough=0.6)
mat_flat("lavagna", srgb("#2a2c2c"), rough=0.9)
mat_flat("pelle_nera", srgb("#141414"), rough=0.35)
mat_flat("verde_poltrona", srgb("#3f5a40"), rough=0.8)
mat_flat("tovaglietta", srgb("#b0202a"), rough=0.8)
mat_flat("ceramica", srgb("#f2f0ea"), rough=0.2)
mat_flat("telo_nero", srgb("#202224"), rough=0.7)
mat_flat("alluminio", srgb("#a8a8a8"), rough=0.4, metal=0.8)
mat_flat("ombrellone", srgb("#ece6d8"), rough=0.9).use_backface_culling = False
mat_flat("lampada_arancio", srgb("#e07830"), rough=0.6, emit=(srgb("#ff9038"), 1.2))
mat_flat("lampada_rossa", srgb("#9a1810"), rough=0.7)
mat_flat("lampadina", srgb("#fff0d0"), rough=1.0, emit=(srgb("#ffd8a0"), 6.0))
mat_flat("fuoco", srgb("#ff6010"), rough=1.0, emit=(srgb("#ff7020"), 8.0))
mat_flat("faretto", srgb("#fff4e0"), rough=1.0, emit=(srgb("#fff0d8"), 6.0))
mat_flat("pianta", srgb("#3a6a2a"), rough=0.8)
mat_flat("vaso", srgb("#8a5a3a"), rough=0.8)
BOTTLE_MATS = []
for i, (hexc, a) in enumerate([("#203818", 0.9), ("#4a1e10", 0.9), ("#d8c890", 0.85), ("#2a2a30", 0.9),
                               ("#8a3018", 0.9), ("#e0b040", 0.85), ("#f0e8d8", 0.85)]):
    BOTTLE_MATS.append(mat_flat("bottiglia_%d" % i, srgb(hexc), rough=0.1, metal=0.0))

# --- Geometria ------------------------------------------------------------------------------------------------
PARTS = {}  # (materiale, collisione) -> lista di bmesh da unire


def _bm(key):
    if key not in PARTS:
        PARTS[key] = bmesh.new()
    return PARTS[key]


def P(u, v, z):
    return (u, -v, z)


def box(mat, u0, u1, v0, v1, z0, z1, collide=True):
    """Parallelepipedo allineato agli assi locali."""
    bm = _bm((mat, collide))
    u0, u1 = min(u0, u1), max(u0, u1)
    v0, v1 = min(v0, v1), max(v0, v1)
    vs = [bm.verts.new(P(u, v, z)) for z in (z0, z1) for v in (v0, v1) for u in (u0, u1)]
    # indici: z0: (u0v0 0, u1v0 1, u0v1 2, u1v1 3); z1: +4
    for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        try:
            bm.faces.new([vs[i] for i in f])
        except ValueError:
            pass


def quad(mat, pts, collide=True):
    bm = _bm((mat, collide))
    bm.faces.new([bm.verts.new(P(*p)) for p in pts])


def cyl(mat, u, v, z0, z1, r0, r1=None, seg=10, collide=False, cap=True):
    bm = _bm((mat, collide))
    r1 = r0 if r1 is None else r1
    lo, hi = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        lo.append(bm.verts.new(P(u + r0 * math.cos(a), v + r0 * math.sin(a), z0)))
        hi.append(bm.verts.new(P(u + r1 * math.cos(a), v + r1 * math.sin(a), z1)))
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new([lo[i], lo[j], hi[j], hi[i]])
    if cap:
        bm.faces.new(list(reversed(lo)))
        if r1 > 0.001:
            bm.faces.new(hi)


def bottle(u, v, z, kind=None):
    m = random.choice(BOTTLE_MATS).name if kind is None else kind
    h = random.uniform(0.26, 0.32)
    cyl(m, u, v, z, z + h * 0.62, 0.037, seg=8)
    cyl(m, u, v, z + h * 0.62, z + h * 0.78, 0.037, 0.014, seg=8, cap=False)
    cyl(m, u, v, z + h * 0.78, z + h, 0.014, seg=6)


# --- Pavimenti, muri, tetto -----------------------------------------------------------------------------------
box("cemento", 0, AU, 0, AV, -0.6, FLOOR)
box("cemento", BU0, BU1, BV0, BV1, -0.6, FLOOR)
# tetto: lastra bianca spessa con sbalzo
OV = 0.45
box("intonaco", -OV, AU + 0.01, -OV, AV + OV, ROOF0, ROOF1)
box("intonaco", AU - 0.01, BU1 + OV, BV0 - OV, BV1 + OV, ROOF0 - 0.25, ROOF1 - 0.25)
# soffitto piano del bar (A)
box("intonaco", 0, AU, 0, AV, H_A, ROOF0, collide=False)


def glazed(axis, fixed, a0, a1, z0=FLOOR, z1=H_A, sill=0.45, mull=1.5, frame="legno_chiaro", door=None, low="legno_scuro",
           ztop=None):
    """Parete vetrata con infissi in legno: lungo u (axis='u', a v=fixed) o lungo v (axis='v', a u=fixed).
    door=(a, b): tratto senza vetro né davanzale (ingresso). ztop: funzione a → altezza (soffitto inclinato)."""
    def B(m, s0, s1, zz0, zz1, th=0.08, c=True):
        if axis == "u":
            box(m, s0, s1, fixed - th / 2, fixed + th / 2, zz0, zz1, c)
        else:
            box(m, fixed - th / 2, fixed + th / 2, s0, s1, zz0, zz1, c)

    n = max(1, round((a1 - a0) / mull))
    step = (a1 - a0) / n
    for i in range(n + 1):
        s = a0 + i * step
        top = ztop(s) if ztop else z1
        B(frame, s - 0.05, s + 0.05, z0, top, th=0.12)  # montanti
    for i in range(n):
        s0, s1 = a0 + i * step + 0.05, a0 + (i + 1) * step - 0.05
        mid = (s0 + s1) / 2
        top = ztop(mid) if ztop else z1
        is_door = door and door[0] <= mid <= door[1]
        if is_door:
            B(frame, s0, s1, top - 0.08, top, th=0.12)
            continue
        if sill > 0:
            B(low, s0, s1, z0, z0 + sill, th=0.18)
            B(frame, s0 - 0.02, s1 + 0.02, z0 + sill, z0 + sill + 0.05, th=0.24)
        B("vetro", s0, s1, z0 + sill + 0.05, top - 0.06, th=0.02)
        B(frame, s0, s1, top - 0.08, top, th=0.12)


# A: facciata ovest (via Flaminia): pilastri bianchi, vetrate con zoccolo in legno scuro
for v0, v1 in ((0, 4.2), (4.4, 8.6)):
    glazed("v", 0.0, v0, v1, sill=0.9)
box("intonaco", -0.15, 0.15, -0.15, 0.15, FLOOR, ROOF0)
box("intonaco", -0.15, 0.15, 4.15, 4.45, FLOOR, ROOF0)
box("intonaco", -0.15, 0.15, 8.55, 8.85, FLOOR, ROOF0)
box("legno_scuro", -0.1, 0.1, 8.85, AV, FLOOR, H_A)          # cucina: tamponata, rivestita in legno
box("intonaco", 0.1, WALL + 0.1, 8.85, AV, FLOOR, H_A)
# A: lato nord, vetrato con l'ingresso
glazed("u", 0.0, 0.0, AU, sill=0.0, door=(2.6, 4.4), mull=1.75)
box("intonaco", AU - 0.15, AU + 0.15, -0.15, 0.15, FLOOR, ROOF0)
# A: lato sud (cucina) e lato est della cucina
box("intonaco", 0, AU, AV - WALL, AV, FLOOR, H_A)
box("legno_scuro", 0, AU, AV, AV + 0.06, FLOOR, H_A)
box("intonaco", AU - WALL, AU, BV1, AV, FLOOR, H_A)
box("legno_scuro", AU, AU + 0.06, BV1, AV, FLOOR, H_A)
glazed("v", AU, 0.0, BV0, sill=0.9)
# parete tra bar e cucina, con porta in legno
box("intonaco", 0.1, 4.7, 7.0, 7.0 + WALL, FLOOR, H_A)
box("intonaco", 5.6, AU, 7.0, 7.0 + WALL, FLOOR, H_A)
box("intonaco", 4.7, 5.6, 7.0, 7.0 + WALL, 2.2, H_A)
box("legno_chiaro", 4.72, 5.58, 7.04, 7.08, FLOOR, 2.18)     # porta (socchiusa, solo verso la cucina)
box("faretto", 5.0, 5.3, 7.0, 7.03, 1.5, 1.75, collide=False)  # oblò della porta
# parete tra bar (A) e sala (B): scaffali del vino dal lato sala, passaggio a v 5,6..6,9
box("intonaco", AU - WALL, AU, BV0, 5.6, FLOOR, H_A)
box("intonaco", AU - WALL, AU, 6.9, BV1, FLOOR, H_A)
box("intonaco", AU - WALL, AU, 5.6, 6.9, 2.4, H_A)

# B: sala con soffitto in larice inclinato (alto verso il bar, basso verso il parco)
ZB_HI, ZB_LO = 3.35, 2.75


def zb(u):
    return ZB_HI + (ZB_LO - ZB_HI) * (u - BU0) / (BU1 - BU0)


glazed("v", BU1, BV0, BV1, sill=0.5, z1=ZB_LO, mull=1.6, low="cemento")       # vetrata sul parco
glazed("u", BV0, BU0, BU1, sill=0.5, ztop=zb, mull=1.6, low="cemento", door=(BU0 + 2.2, BU0 + 3.6))  # verso il dehors
glazed("u", BV1, BU0, BU1, sill=0.5, ztop=zb, mull=1.6, low="cemento")
# soffitto: doghe di larice + travi
quad("larice", [(BU0, BV0, zb(BU0)), (BU1, BV0, zb(BU1)), (BU1, BV1, zb(BU1)), (BU0, BV1, zb(BU0))], collide=False)
quad("larice", [(BU0, BV1, zb(BU0) + 0.02), (BU1, BV1, zb(BU1) + 0.02), (BU1, BV0, zb(BU1) + 0.02),
                (BU0, BV0, zb(BU0) + 0.02)], collide=False)
box("intonaco", BU0, BU1 + 0.1, BV0, BV1, ZB_HI + 0.05, ROOF0 - 0.25, collide=False)
nb = 7
for i in range(nb):
    v = BV0 + 0.3 + i * (BV1 - BV0 - 0.6) / (nb - 1)
    bmk = _bm(("larice", False))
    w, d = 0.07, 0.2
    pts = [(BU0, v - w, zb(BU0)), (BU1, v - w, zb(BU1)), (BU1, v + w, zb(BU1)), (BU0, v + w, zb(BU0))]
    lo = [(u, vv, z - d) for u, vv, z in pts]
    vs = [bmk.verts.new(P(*p)) for p in pts + lo]
    for f in ((4, 5, 6, 7), (0, 1, 5, 4), (2, 3, 7, 6), (0, 4, 7, 3), (1, 2, 6, 5)):
        bmk.faces.new([vs[k] for k in f])
    # faretti in legno sulle travi
    for u in (BU0 + 1.2, BU0 + 3.3):
        box("larice", u - 0.06, u + 0.06, v - 0.06, v + 0.06, zb(u) - d - 0.16, zb(u) - d, collide=False)
        box("faretto", u - 0.04, u + 0.04, v - 0.04, v + 0.04, zb(u) - d - 0.17, zb(u) - d - 0.16, collide=False)
# trave di colmo lungo il lato del bar e lungo la vetrata
box("larice", BU0, BU0 + 0.25, BV0, BV1, zb(BU0) - 0.3, zb(BU0), collide=False)
box("larice", BU1 - 0.25, BU1, BV0, BV1, ZB_LO - 0.3, ZB_LO, collide=False)

# --- Bar (A nord) ---------------------------------------------------------------------------------------------
# bancone: fronte a doghe orizzontali, piano in cemento, parallelo al lato est
CU0, CU1, CV0, CV1 = 4.35, 5.0, 0.9, 5.2
box("legno_chiaro", CU0, CU1, CV0, CV1, FLOOR, 1.02)
for k in range(9):  # doghe in rilievo
    z = FLOOR + 0.06 + k * 0.105
    box("legno_chiaro", CU0 - 0.025, CU0, CV0, CV1, z, z + 0.08, collide=False)
    box("legno_chiaro", CU0, CU1, CV0 - 0.025, CV0, z, z + 0.08, collide=False)
box("cemento_piano", CU0 - 0.25, CU1 + 0.02, CV0 - 0.25, CV1 + 0.02, 1.02, 1.08)
# macchina del caffè, spillatore, bicchieri sul bancone
box("acciaio", CU0 + 0.05, CU0 + 0.55, 1.4, 2.1, 1.08, 1.5)
box("nero", CU0 + 0.02, CU0 + 0.05, 1.45, 2.05, 1.2, 1.45)
cyl("acciaio", CU0 + 0.3, 3.2, 1.08, 1.55, 0.03, seg=8)
for k in range(6):
    cyl("vetro", CU0 + 0.35, 3.8 + k * 0.12, 1.08, 1.22, 0.035, 0.04, seg=8)
# retrobanco: mensole con bottiglie sul muro est (davanti alla parete del vino)
SU0 = AU - WALL - 0.32
box("legno_chiaro", SU0, AU - WALL, CV0, CV1, FLOOR, 0.95)       # mobile basso
box("cemento_piano", SU0 - 0.02, AU - WALL, CV0, CV1, 0.95, 0.99)
for z in (1.45, 1.85, 2.25):
    box("legno_chiaro", SU0 + 0.05, AU - WALL, CV0, CV1, z - 0.04, z, collide=False)
    v = CV0 + 0.08
    while v < CV1 - 0.06:
        if random.random() < 0.9:
            bottle(AU - WALL - 0.14, v, z)
        v += random.uniform(0.085, 0.11)
box("faretto", SU0 + 0.06, SU0 + 0.09, CV0, CV1, 1.39, 1.41, collide=False)  # led sotto la mensola
# sgabelli neri davanti al bancone
for v in (1.4, 2.2, 3.0, 3.8, 4.6):
    u = CU0 - 0.55
    cyl("pelle_nera", u, v, 0.74, 0.8, 0.2, 0.18, seg=14, collide=True)
    for du, dv in ((-0.13, -0.13), (0.13, -0.13), (-0.13, 0.13), (0.13, 0.13)):
        cyl("legno_tavoli", u + du, v + dv, FLOOR, 0.75, 0.02, 0.018, seg=6)
    box("legno_tavoli", u - 0.14, u + 0.14, v - 0.012, v + 0.012, 0.35, 0.38, collide=False)
# colonna lavagna nera
box("lavagna", 3.0, 3.5, 5.3, 5.8, FLOOR, H_A)
box("ceramica", 2.97, 2.99, 5.38, 5.72, 0.9, 1.6, collide=False)  # locandina
# lampade a nido d'ape arancioni sopra il bancone
LAMPS = []
for v in (1.6, 3.0, 4.4):
    u = CU0 - 0.1
    for k in range(5):
        r = 0.16 + 0.04 * math.sin(math.pi * (k + 0.5) / 5)
        cyl("lampada_arancio", u, v, 2.25 + k * 0.07, 2.31 + k * 0.07, r, r, seg=16, collide=False)
    cyl("nero", u, v, 2.6, H_A, 0.004, seg=4, collide=False)
    LAMPS.append(("bar", u, v, 2.3))
# salotto verso la Flaminia: divano beige, tavolino, poltrona verde, stufa a pellet
box("divano", 0.35, 2.35, 0.35, 0.95, FLOOR + 0.1, 0.52)
box("divano", 0.35, 2.35, 0.25, 0.45, 0.52, 0.85)
box("divano", 0.3, 0.45, 0.3, 0.95, 0.52, 0.68)
box("divano", 2.25, 2.4, 0.3, 0.95, 0.52, 0.68)
for uu in (0.4, 2.3):
    for vv in (0.35, 0.9):
        cyl("legno_tavoli", uu, vv, FLOOR, FLOOR + 0.1, 0.02, seg=6)
box("legno_tavoli", 0.7, 2.0, 1.3, 1.9, 0.4, 0.45)
for uu, vv in ((0.75, 1.35), (1.95, 1.35), (0.75, 1.85), (1.95, 1.85)):
    cyl("legno_tavoli", uu, vv, FLOOR, 0.4, 0.02, seg=6)
box("verde_poltrona", 0.5, 1.15, 2.5, 3.15, 0.38, 0.5)
box("verde_poltrona", 0.45, 0.6, 2.5, 3.15, 0.5, 0.95)
box("legno_tavoli", 0.5, 1.15, 2.45, 2.52, 0.38, 0.62)
box("legno_tavoli", 0.5, 1.15, 3.13, 3.2, 0.38, 0.62)
box("nero", 0.35, 0.9, 3.9, 4.4, FLOOR, 1.05)                     # stufa
box("fuoco", 0.88, 0.91, 4.0, 4.3, 0.45, 0.8, collide=False)
cyl("nero", 0.55, 4.15, 1.05, H_A, 0.06, seg=8)
box("legno_chiaro", 0.25, 1.1, 3.8, 3.86, FLOOR, 1.1)
box("legno_chiaro", 0.25, 1.1, 4.44, 4.5, FLOOR, 1.1)
# pianta in vaso vicino all'ingresso
cyl("vaso", 2.2, 0.5, FLOOR, 0.55, 0.22, 0.26, seg=12, collide=True)
for k in range(9):
    a = k * 2.4
    cyl("pianta", 2.2 + 0.2 * math.cos(a), 0.5 + 0.2 * math.sin(a), 0.55, 1.2 + 0.3 * random.random(), 0.12, 0.0, seg=5)

# --- Cucina (A sud): forno a legna, piani in acciaio, scaffali -------------------------------------------------
box("intonaco", 2.0, 4.6, AV - 1.3, AV - WALL, FLOOR, 2.0)          # forno
box("acciaio", 2.1, 4.5, AV - 1.32, AV - 1.28, 0.95, 1.85)
box("nero", 2.8, 3.8, AV - 1.34, AV - 1.31, 1.05, 1.55, collide=False)
box("fuoco", 2.9, 3.7, AV - 1.33, AV - 1.32, 1.08, 1.4, collide=False)
box("acciaio", 2.0, 4.6, AV - 1.6, AV - 1.3, 0.95, 1.0)
box("acciaio", 1.7, 4.9, AV - 1.5, AV - WALL, 2.0, H_A)            # cappa
LAMPS.append(("forno", 3.3, AV - 1.6, 1.3))
box("acciaio", 0.3, 0.95, 7.6, AV - 0.4, FLOOR, 0.92)               # banco lungo la parete ovest
box("cemento_piano", 0.25, 1.0, 7.6, AV - 0.4, 0.92, 0.96)
box("acciaio", 5.9, AU - WALL, 7.5, AV - 0.4, FLOOR, 0.92)
for z in (1.3, 1.7, 2.1):
    box("legno_chiaro", 6.4, AU - WALL, 7.5, 9.8, z - 0.03, z, collide=False)
    for k in range(4):
        cyl("ceramica", 6.6, 7.8 + k * 0.5, z, z + 0.18, 0.14, seg=14)  # pile di piatti
for k in range(3):
    cyl("ceramica", 0.6, 8.2 + k * 0.9, 0.96, 1.15, 0.15, seg=14)
LAMPS.append(("cucina", 3.3, 9.5, 3.0))

# --- Sala ristorante (B) ----------------------------------------------------------------------------------------
# scaffalature del vino sulla parete verso il bar
for z in (0.5, 0.85, 1.2, 1.55, 1.9, 2.25):
    for (v0, v1) in ((BV0 + 0.2, 5.5), (7.0, BV1 - 0.2)):
        box("legno_chiaro", BU0, BU0 + 0.32, v0, v1, z - 0.03, z, collide=False)
        v = v0 + 0.06
        while v < v1 - 0.05:
            if random.random() < 0.85:
                bottle(BU0 + 0.16, v, z, kind=random.choice(BOTTLE_MATS[:2] + [BOTTLE_MATS[4]]).name)
            v += 0.088
for v0, v1 in ((BV0 + 0.2, 5.5), (7.0, BV1 - 0.2)):
    for vv in (v0, (v0 + v1) / 2, v1):
        box("legno_chiaro", BU0, BU0 + 0.34, vv - 0.03, vv + 0.03, FLOOR, 2.4)
box("legno_chiaro", BU0, BU0 + 0.34, BV0 + 0.2, BV1 - 0.2, FLOOR, 0.45)


def chair(u, v, face):
    """Sedia in legno; face: direzione (du, dv) verso cui guarda chi siede."""
    du, dv = face
    box("legno_tavoli", u - 0.21, u + 0.21, v - 0.21, v + 0.21, 0.44, 0.48)
    for a, b in ((-0.18, -0.18), (0.18, -0.18), (-0.18, 0.18), (0.18, 0.18)):
        cyl("legno_tavoli", u + a, v + b, FLOOR, 0.45, 0.018, seg=6)
    bu, bv = u - du * 0.2, v - dv * 0.2  # schienale dietro
    if du:
        box("legno_tavoli", bu - 0.02, bu + 0.02, v - 0.2, v + 0.2, 0.48, 0.9, collide=False)
        box("legno_tavoli", bu - 0.025, bu + 0.025, v - 0.21, v + 0.21, 0.72, 0.84, collide=False)
    else:
        box("legno_tavoli", u - 0.2, u + 0.2, bv - 0.02, bv + 0.02, 0.48, 0.9, collide=False)
        box("legno_tavoli", u - 0.21, u + 0.21, bv - 0.025, bv + 0.025, 0.72, 0.84, collide=False)


def table(u, v, w=0.75, d=0.75, cloth=True, seats=((1, 0), (-1, 0))):
    box("legno_tavoli", u - w / 2, u + w / 2, v - d / 2, v + d / 2, 0.72, 0.76)
    for a, b in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        box("legno_tavoli", u + a * (w / 2 - 0.06) - 0.025, u + a * (w / 2 - 0.06) + 0.025,
            v + b * (d / 2 - 0.06) - 0.025, v + b * (d / 2 - 0.06) + 0.025, FLOOR, 0.72)
    for su, sv in seats:
        if cloth:
            box("tovaglietta", u + su * w * 0.22 - 0.17, u + su * w * 0.22 + 0.17,
                v + sv * d * 0.22 - 0.13, v + sv * d * 0.22 + 0.13, 0.76, 0.765, collide=False)
            cyl("ceramica", u + su * w * 0.24, v + sv * d * 0.24, 0.765, 0.78, 0.12, seg=14)
            cyl("vetro", u + su * w * 0.1, v + sv * d * 0.1 + 0.15, 0.765, 0.88, 0.03, 0.035, seg=8)
        chair(u + su * (w / 2 + 0.25), v + sv * (d / 2 + 0.25), (-su, -sv))


for v in (2.2, 3.9, 5.6, 7.3, 8.6):
    table(10.4, v, seats=((1, 0), (-1, 0)) if v < 8 else ((-1, 0),))
for v in (2.6, 4.6, 7.8):
    table(8.2, v, w=0.8, d=1.1, seats=((0, 1), (0, -1)))
for v in (2.2, 4.6, 7.0):
    LAMPS.append(("sala", 9.3, v, 2.1))
    cyl("lampada_rossa", 9.3, v, 2.0, 2.28, 0.2, seg=18, collide=False)
    cyl("lampadina", 9.3, v, 1.99, 2.05, 0.18, seg=18, collide=False)
    cyl("nero", 9.3, v, 2.28, zb(9.3), 0.004, seg=4, collide=False)

# --- Dehors: pergolato in legno con tetto nero e paraventi a doghe ---------------------------------------------
GU0, GU1, GV0, GV1, GH = 5.2, 12.2, -7.2, -0.7, 2.75
box("cemento", GU0, GU1, GV0, GV1, -0.4, 0.04)
for u in (GU0 + 0.1, (GU0 + GU1) / 2, GU1 - 0.1):
    for v in (GV0 + 0.1, GV1 - 0.1):
        box("legno_chiaro", u - 0.08, u + 0.08, v - 0.08, v + 0.08, 0.04, GH)
box("legno_chiaro", GU0, GU1, GV0, GV0 + 0.18, GH - 0.25, GH)
box("legno_chiaro", GU0, GU1, GV1 - 0.18, GV1, GH - 0.25, GH)
for k in range(8):
    u = GU0 + 0.1 + k * (GU1 - GU0 - 0.2) / 7
    box("legno_chiaro", u - 0.04, u + 0.04, GV0, GV1, GH - 0.2, GH, collide=False)
bmr = _bm(("telo_nero", False))
rv = [bmr.verts.new(P(u, v, z)) for u, v, z in ((GU0 - 0.2, GV0 - 0.2, GH + 0.05), (GU1 + 0.2, GV0 - 0.2, GH + 0.05),
                                                 ((GU0 + GU1) / 2, (GV0 + GV1) / 2, GH + 0.6),
                                                 (GU1 + 0.2, GV1 + 0.2, GH + 0.05), (GU0 - 0.2, GV1 + 0.2, GH + 0.05))]
for f in ((0, 1, 2), (1, 3, 2), (3, 4, 2), (4, 0, 2)):
    bmr.faces.new([rv[i] for i in f])
MATS["telo_nero"].use_backface_culling = False  # tetto del pergolato visibile dai due lati
for k in range(14):  # paravento a doghe sul lato nord e sul lato est
    z = 0.1 + k * 0.12
    box("legno_chiaro", GU0, GU1, GV0 + 0.02, GV0 + 0.06, z, z + 0.08)
    box("legno_chiaro", GU1 - 0.06, GU1 - 0.02, GV0, GV1, z, z + 0.08)


def alu_chair(u, v, face):
    du, dv = face
    box("alluminio", u - 0.22, u + 0.22, v - 0.22, v + 0.22, 0.44, 0.47)
    for a, b in ((-0.2, -0.2), (0.2, -0.2), (-0.2, 0.2), (0.2, 0.2)):
        cyl("alluminio", u + a, v + b, 0.04, 0.45, 0.012, seg=6)
    bu, bv = u - du * 0.21, v - dv * 0.21
    if du:
        box("alluminio", bu - 0.015, bu + 0.015, v - 0.22, v + 0.22, 0.47, 0.85, collide=False)
    else:
        box("alluminio", u - 0.22, u + 0.22, bv - 0.015, bv + 0.015, 0.47, 0.85, collide=False)


for u, v in ((6.6, -5.6), (8.6, -5.6), (10.6, -5.6), (6.6, -2.6), (8.6, -2.6), (10.6, -2.6)):
    box("legno_tavoli", u - 0.4, u + 0.4, v - 0.4, v + 0.4, 0.72, 0.76)
    cyl("alluminio", u, v, 0.04, 0.72, 0.04, seg=8)
    cyl("alluminio", u, v, 0.04, 0.06, 0.25, seg=10)
    alu_chair(u - 0.7, v, (1, 0))
    alu_chair(u + 0.7, v, (-1, 0))
for u, v in ((2.0, -2.0), (2.0, -5.0)):  # ombrelloni fuori dal pergolato
    cyl("alluminio", u, v, 0.0, 2.6, 0.03, seg=6)
    cyl("ombrellone", u, v, 2.1, 2.6, 1.4, 0.05, seg=8, collide=False, cap=False)
    box("legno_tavoli", u - 0.4, u + 0.4, v - 0.4, v + 0.4, 0.72, 0.76)
    cyl("alluminio", u, v, 0.0, 0.72, 0.04, seg=8)
    alu_chair(u, v - 0.7, (0, 1))
    alu_chair(u, v + 0.7, (0, -1))
for u in (GU0 + 1.0, GU0 + 3.5, GU0 + 6.0):
    LAMPS.append(("dehors", u, (GV0 + GV1) / 2, GH - 0.3))

# --- Oggetti Blender, UV, esportazione ------------------------------------------------------------------------


def box_uv(obj, scale):
    """UV a proiezione cubica in coordinate del mondo (texture alla scala giusta su ogni faccia)."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for lp in f.loops:
            co = lp.vert.co
            if ax == 0:
                lp[uv].uv = (co.y / scale, co.z / scale)
            elif ax == 1:
                lp[uv].uv = (co.x / scale, co.z / scale)
            else:
                lp[uv].uv = (co.x / scale, co.y / scale)
    bm.to_mesh(me)
    bm.free()


for (mname, collide), bm in PARTS.items():
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(mname)
    bm.to_mesh(me)
    bm.free()
    name = mname + ("-col" if collide else "")
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    me.materials.append(MATS[mname])
    box_uv(ob, UVSCALE[mname])
    for p in me.polygons:
        p.use_smooth = False

for i, (kind, u, v, z) in enumerate(LAMPS):
    e = bpy.data.objects.new("luce_%s_%02d" % (kind, i), None)
    e.location = P(u, v, z)
    col.objects.link(e)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "treebar.blend"))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_image_format="AUTO",
                          export_lights=False, export_cameras=False, export_apply=True)
print("SCRITTO", OUT, sum(len(o.data.polygons) for o in col.objects if o.type == "MESH"), "facce")
