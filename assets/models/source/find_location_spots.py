"""Procura e escolhe os sítios dos bots de uma zona do Dust II (dust2.glb).

Uso:
  blender -b --factory-startup --python find_location_spots.py -- <dust2.glb> <locations.json> \
      <id> "<nome>" <x> <y> <z> <yaw graus> [ângulo máx.] [dist. mín.] [dist. máx.]

O jogador fica em (x, y, z) do Godot a olhar para `yaw` (0 = -Z, positivo = para
a esquerda). Um sítio é um par (escondido, exposto): no escondido nenhuma parte
do bot se vê; no exposto vê-se a cabeça e o peito. Só valem sítios dentro do
ângulo máximo (para o bot aparecer sempre no ecrã) e entre as distâncias dadas.
A escolha final espalha os sítios por ângulos e distâncias diferentes e alonga o
peek para o bot sair bem da cobertura. O resultado junta-se a locations.json.
"""
import bpy, sys, json, math, os
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
glb, out_path, loc_id, loc_name = argv[:4]
px, py, pz, yaw = map(float, argv[4:8])
MAX_ANGLE = float(argv[8]) if len(argv) > 8 else 38.0
MIN_DIST = float(argv[9]) if len(argv) > 9 else 4.5
MAX_DIST = float(argv[10]) if len(argv) > 10 else 22.0
MAX_SPOTS = 14
STEP = 0.3
EYE_H = 1.6256
CROUCH = 0.85
PEEK_MAX = 1.4

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
dg = bpy.context.evaluated_depsgraph_get()
verts, polys = [], []
for o in bpy.context.scene.objects:
    if o.type != 'MESH':
        continue
    me = o.evaluated_get(dg).to_mesh()
    base = len(verts)
    verts.extend(o.matrix_world @ v.co for v in me.vertices)
    polys.extend([base + i for i in p.vertices] for p in me.polygons)
bvh = BVHTree.FromPolygons(verts, polys)
UP = Vector((0, 0, 1))
# Caixas copiadas: um bot não pode ficar em cima delas.
CRATES = []
for o in bpy.context.scene.objects:
    if o.type == 'MESH' and o.name.startswith("Prop_Crate"):
        ws = [o.matrix_world @ Vector(c) for c in o.bound_box]
        CRATES.append((min(w.x for w in ws) - 0.3, min(w.y for w in ws) - 0.3, max(w.x for w in ws) + 0.3, max(w.y for w in ws) + 0.3))


def on_crate(p):
    return any(c[0] <= p.x <= c[2] and c[1] <= p.y <= c[3] for c in CRATES)


def b(gx, gy, gz):  # Godot -> Blender
    return Vector((gx, -gz, gy))


def g(v):  # Blender -> Godot
    return [round(v.x, 3), round(v.z, 3), round(-v.y, 3)]


FEET = b(px, py, pz)
EYE = FEET + Vector((0, 0, EYE_H))
# Direção para onde o jogador olha (no plano), em coordenadas do Blender.
FWD = Vector((-math.sin(math.radians(yaw)), math.cos(math.radians(yaw)), 0))


def rel_angle(p):
    d = Vector((p.x - EYE.x, p.y - EYE.y, 0))
    if d.length < 1e-6:
        return 0.0
    # Positivo = à direita do jogador (como no ecrã).
    return math.degrees(math.atan2(d.x * FWD.y - d.y * FWD.x, d.dot(FWD)))


def blocked(a, c):
    d = c - a
    hit = bvh.ray_cast(a, d.normalized(), d.length)
    return hit[0] is not None and hit[3] < d.length - 0.03


def floor_at(x, y, top):
    loc, n, i, d = bvh.ray_cast(Vector((x, y, top)), Vector((0, 0, -1)), 6.0)
    return loc.z if loc is not None and n.z > 0.75 else None


def standable(p):
    if bvh.ray_cast(p + Vector((0, 0, 0.05)), UP, 1.95)[0] is not None:
        return False
    for h in (0.4, 1.0, 1.6):
        for k in range(8):
            a = k * math.pi / 4
            if bvh.ray_cast(p + Vector((0, 0, h)), Vector((math.cos(a), math.sin(a), 0)), 0.3)[0] is not None:
                return False
    return True


def probes(p, drop=0.0):
    to_eye = EYE - p
    to_eye.z = 0
    to_eye.normalize()
    r = to_eye.cross(UP).normalized()
    z = lambda h: Vector((0, 0, h - drop))
    return {
        "head": p + z(1.68), "top": p + z(1.84), "chest": p + z(1.35),
        "sl": p + z(1.4) + r * 0.22, "sr": p + z(1.4) - r * 0.22,
        "hips": p + z(0.95), "kl": p + z(0.5) + r * 0.12, "kr": p + z(0.5) - r * 0.12,
    }


def visible(p, drop=0.0):
    return {k for k, q in probes(p, drop).items() if not blocked(EYE, q)}


# Pontos onde um bot pode estar, no cone à frente do jogador.
points = []
R = MAX_DIST + 2.0
steps = int(R / STEP)
for i in range(-steps, steps + 1):
    for j in range(-steps, steps + 1):
        x = EYE.x + i * STEP
        y = EYE.y + j * STEP
        flat = math.hypot(x - EYE.x, y - EYE.y)
        if flat < MIN_DIST - 1.5 or flat > R:
            continue
        if abs(rel_angle(Vector((x, y, 0)))) > MAX_ANGLE + 6.0:
            continue
        z = floor_at(x, y, EYE.z + 3.0)
        if z is None or abs(z - FEET.z) > 4.5:
            continue
        p = Vector((x, y, z))
        if not on_crate(p) and standable(p):
            points.append((p, visible(p)))
print("POINTS", len(points))

hidden = [p for p, v in points if not v]
exposed = [(p, v) for p, v in points if {"head", "top", "chest"} <= v
           and abs(rel_angle(p)) <= MAX_ANGLE and MIN_DIST <= (p - EYE).length <= MAX_DIST]

pairs = []
for h in hidden:
    to_eye = EYE - h
    to_eye.z = 0
    to_eye.normalize()
    r = to_eye.cross(UP).normalized()
    best = None
    for x, v in exposed:
        d = x - h
        if abs(d.z) > 0.35:
            continue
        flat = Vector((d.x, d.y, 0))
        L = flat.length
        if L < 0.6 or L > 1.9:
            continue
        lateral = abs(flat.dot(r)) / L
        if lateral < 0.7:
            continue
        if blocked(h + Vector((0, 0, 0.5)), x + Vector((0, 0, 0.5))) or blocked(h + Vector((0, 0, 1.3)), x + Vector((0, 0, 1.3))):
            continue
        score = lateral * 2 - L * 0.5 + len(v) * 0.1 + (MAX_DIST - (x - EYE).length) * 0.06
        if best is None or score > best[0]:
            best = (score, x)
    if best:
        pairs.append({"hidden": h, "exposed": best[1], "kind": "strafe", "score": best[0]})
for p, v in exposed:
    if not visible(p, CROUCH):
        pairs.append({"hidden": p - Vector((0, 0, CROUCH)), "exposed": p, "kind": "crouch",
                      "score": 1.7 + (MAX_DIST - (p - EYE).length) * 0.06})
print("PAIRS", len(pairs))


def extend(pair):
    """Alonga o peek enquanto o caminho estiver livre."""
    if pair["kind"] != "strafe":
        return pair
    h, e = pair["hidden"], pair["exposed"]
    d = Vector((e.x - h.x, e.y - h.y, 0))
    dirv = d.normalized()
    L = d.length
    while L + 0.1 <= PEEK_MAX:
        cand = Vector((h.x, h.y, h.z)) + dirv * (L + 0.1)
        z = floor_at(cand.x, cand.y, h.z + 1.0)
        if z is None or abs(z - h.z) > 0.35:
            break
        cand.z = z
        if not standable(cand) or blocked(h + Vector((0, 0, 1.0)), cand + Vector((0, 0, 1.0))) \
                or abs(rel_angle(cand)) > MAX_ANGLE:
            break
        e = cand
        L += 0.1
    pair["exposed"] = e
    return pair


# Escolha: o melhor de cada "caixa" (ângulo × distância) primeiro, depois o resto.
def bucket(p):
    a = rel_angle(p["exposed"])
    dist = (p["exposed"] - EYE).length
    return (int((a + MAX_ANGLE) // 12), 0 if dist < 10 else (1 if dist < 16 else (2 if dist < 21 else 3)))


chosen = []


def far_enough(p):
    return all((p["exposed"].xy - c["exposed"].xy).length >= 2.2 and (p["hidden"].xy - c["hidden"].xy).length >= 1.2
               for c in chosen)


by_bucket = {}
for p in sorted(pairs, key=lambda q: -q["score"]):
    by_bucket.setdefault(bucket(p), []).append(p)
for key in sorted(by_bucket, key=lambda k: (k[1], k[0])):
    for p in by_bucket[key]:
        if far_enough(p):
            chosen.append(p)
            break
for p in sorted(pairs, key=lambda q: -q["score"]):
    if len(chosen) >= MAX_SPOTS:
        break
    if p not in chosen and far_enough(p):
        chosen.append(p)

spots = []
for p in chosen[:MAX_SPOTS]:
    p = extend(p)
    e = p["exposed"]
    spots.append({
        "kind": p["kind"], "hidden": g(p["hidden"]), "exposed": g(e),
        "dist": round((e - EYE).length, 2), "angle": round(rel_angle(e), 1),
    })
spots.sort(key=lambda s: s["angle"])
for s in spots:
    print("SPOT", s)

data = {}
if os.path.exists(out_path):
    data = json.load(open(out_path, encoding="utf-8"))
data[loc_id] = {"name": loc_name, "player": [px, py, pz], "yaw": yaw, "eye_height": EYE_H, "spots": spots}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=1, ensure_ascii=False)
print("WROTE", loc_id, len(spots))
