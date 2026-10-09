# Gerador dos braços do viewmodel do os!strike (corre dentro do Blender).
#
# Mãos feitas por "box modeling" em código: a palma é uma grelha de quads, os
# dedos e o polegar saem da palma como anéis de 4 vértices (um por estação ao
# longo da falange) e o antebraço é uma sequência de anéis elípticos. No fim
# aplica-se Subdivision Surface, o que dá dedos redondos e articulações definidas
# com uma topologia limpa.
#
# Estilo "terrorista" do CS: luvas pretas sem dedos e antebraços nus.
# Coordenadas no espaço da AK: cano para +Y, cima +Z, direita +X (metros).
import bpy, bmesh, math
from mathutils import Vector, Quaternion

COLL = bpy.data.collections["Viewmodel"]
GLOVE, SKIN = 0, 1
# O Subdivision Surface encolhe as secções de 4 vértices; compensamos aqui.
SUBDIV_COMP = 1.25

# Colunas da palma ao longo de S (de mindinho para indicador): pares por dedo.
FINGER_COLS = [
    ("pinky", -0.040, -0.024),
    ("ring", -0.021, -0.003),
    ("middle", 0.000, 0.019),
    ("index", 0.022, 0.040),
]
FINGER_LENGTHS = {
    "pinky": (0.036, 0.022, 0.020),
    "ring": (0.046, 0.028, 0.023),
    "middle": (0.050, 0.030, 0.024),
    "index": (0.045, 0.026, 0.022),
}
# Linhas da palma ao longo de F: (distância ao pulso, escala da largura, espessura)
PALM_ROWS = [(0.000, 0.82, 0.027), (0.050, 1.00, 0.031), (0.090, 1.00, 0.020)]
PALM_LEN = PALM_ROWS[-1][0]
THUMB_LENGTHS = (0.042, 0.032, 0.027)
# Antebraço: (distância ao pulso, meia-largura, meia-espessura, material)
FOREARM = [
    (0.012, 0.0300, 0.0205, GLOVE),
    (0.034, 0.0305, 0.0225, GLOVE),
    (0.047, 0.0320, 0.0240, GLOVE),   # rebordo da luva
    (0.053, 0.0298, 0.0222, SKIN),
    (0.100, 0.0330, 0.0265, SKIN),
    (0.170, 0.0375, 0.0305, SKIN),
    (0.240, 0.0400, 0.0330, SKIN),
    (0.310, 0.0405, 0.0340, SKIN),
    (0.380, 0.0395, 0.0335, SKIN),
]


def frame(F, N, right):
    """F = direção dos dedos, N = normal da palma, S = lado do polegar, U = costas da mão."""
    F = Vector(F).normalized()
    N = Vector(N)
    N = (N - N.dot(F) * F).normalized()
    S = (F.cross(N) if right else N.cross(F)).normalized()
    return F, S, N, -N


def quad(bm, a, b, c, d, mat):
    f = bm.faces.new((a, b, c, d))
    f.material_index = mat
    return f


def ring4(bm, c, side, up, hw, hh):
    return [bm.verts.new(c - side * hw + up * hh), bm.verts.new(c + side * hw + up * hh),
            bm.verts.new(c + side * hw - up * hh), bm.verts.new(c - side * hw - up * hh)]


def bridge(bm, r0, r1, mat):
    n = len(r0)
    for e in range(n):
        quad(bm, r0[e], r0[(e + 1) % n], r1[(e + 1) % n], r1[e], mat)


def flex(d, s, u, deg):
    """Dobra a falange na direção da palma (-u)."""
    axis = d.cross(-u)
    if axis.length < 1e-6:
        return d, s, u
    q = Quaternion(axis.normalized(), math.radians(deg))
    return q @ d, q @ s, q @ u


def turn_to(d, s, u, new_d):
    q = d.rotation_difference(new_d.normalized())
    return q @ d, q @ s, q @ u


def build_palm(bm, W, F, S, U):
    cols = [x for _, a, b in FINGER_COLS for x in (a, b)]
    rows = []
    for f, ws, t in PALM_ROWS:
        top, bot = [], []
        for j, sj in enumerate(cols):
            prof = 0.72 if j in (0, len(cols) - 1) else 1.0
            c = W + F * f + S * (sj * ws)
            top.append(bm.verts.new(c + U * (t * 0.5 * prof)))
            bot.append(bm.verts.new(c - U * (t * 0.5 * prof)))
        rows.append((top, bot))
    for r in range(len(rows) - 1):
        (at, ab), (bt, bb) = rows[r], rows[r + 1]
        for j in range(len(cols) - 1):
            quad(bm, at[j], at[j + 1], bt[j + 1], bt[j], GLOVE)
            quad(bm, ab[j + 1], ab[j], bb[j], bb[j + 1], GLOVE)
        quad(bm, at[0], bt[0], bb[0], ab[0], GLOVE)
        if r > 0:  # entre A e B o lado do indicador é a porta do polegar
            quad(bm, at[-1], bt[-1], bb[-1], ab[-1], GLOVE)
    ct, cb = rows[-1]
    for j in (1, 3, 5):  # pele entre os dedos
        quad(bm, ct[j], ct[j + 1], cb[j + 1], cb[j], GLOVE)
    finger_ports = {name: [ct[2 * i], ct[2 * i + 1], cb[2 * i + 1], cb[2 * i]]
                    for i, (name, _, _) in enumerate(FINGER_COLS)}
    (at, ab), (bt, bb) = rows[0], rows[1]
    thumb_port = [at[-1], bt[-1], bb[-1], ab[-1]]
    wrist_loop = list(rows[0][0]) + list(reversed(rows[0][1]))
    return finger_ports, thumb_port, wrist_loop


def build_finger(bm, port, F, S, U, lengths, curls, base_dir=None, fingerless=True):
    p0 = sum((v.co for v in port), Vector()) / 4
    hw = (port[1].co - port[0].co).length * 0.5 * SUBDIV_COMP
    hh = (port[0].co - port[3].co).length * 0.5 * SUBDIV_COMP
    d, s, u = F.copy(), S.copy(), U.copy()
    if base_dir is not None:
        d, s, u = turn_to(d, s, u, base_dir)
    L1, L2, L3 = lengths
    a1, a2, a3 = curls
    edge = SKIN if fingerless else GLOVE
    st = []
    d1, s1, u1 = flex(d, s, u, a1)
    st += [(p0 + d1 * 0.006, d1, s1, u1, 1.06, 1.02, GLOVE),
           (p0 + d1 * L1 * 0.45, d1, s1, u1, 0.93, 0.86, GLOVE),
           (p0 + d1 * L1 * 0.60, d1, s1, u1, 0.97, 0.92, GLOVE),   # rebordo da luva
           (p0 + d1 * L1 * 0.65, d1, s1, u1, 0.86, 0.80, edge)]
    p1 = p0 + d1 * L1
    dh, sh, uh = flex(d1, s1, u1, a2 * 0.5)
    d2, s2, u2 = flex(d1, s1, u1, a2)
    st += [(p1, dh, sh, uh, 0.90, 0.84, edge),
           (p1 + d2 * L2 * 0.5, d2, s2, u2, 0.80, 0.75, edge)]
    p2 = p1 + d2 * L2
    dh, sh, uh = flex(d2, s2, u2, a3 * 0.5)
    d3, s3, u3 = flex(d2, s2, u2, a3)
    st += [(p2, dh, sh, uh, 0.80, 0.75, edge),
           (p2 + d3 * L3 * 0.45, d3, s3, u3, 0.76, 0.68, edge),
           (p2 + d3 * L3 * 0.82, d3, s3, u3, 0.60, 0.52, edge),
           (p2 + d3 * L3, d3, s3, u3, 0.28, 0.24, edge)]
    prev = port
    for c, dd, ss, uu, ws, hs, mat in st:
        r = ring4(bm, c, ss, uu, hw * ws, hh * hs)
        bridge(bm, prev, r, mat)
        prev = r
    quad(bm, prev[0], prev[1], prev[2], prev[3], edge)
    return p2 + d3 * L3


def build_thumb(bm, port, F, S, N, U, dirs, fingerless=True):
    p0 = sum((v.co for v in port), Vector()) / 4
    # Na porta, o "lado" do anel é F (do pulso para os dedos) e o "cima" é U.
    d, s, u = S.copy(), F.copy(), U.copy()
    edge = SKIN if fingerless else GLOVE
    seg = [(F * a + S * b + N * c).normalized() for a, b, c in dirs]
    k = SUBDIV_COMP
    st = []
    d, s, u = turn_to(d, s, u, seg[0])
    st.append((p0 + d * 0.010, d, s, u, 0.0175, 0.0135, GLOVE))
    st.append((p0 + d * THUMB_LENGTHS[0] * 0.55, d, s, u, 0.0140, 0.0118, GLOVE))
    p1 = p0 + d * THUMB_LENGTHS[0]
    mid = (d + seg[1]).normalized()
    dm, sm, um = turn_to(d, s, u, mid)
    st.append((p1, dm, sm, um, 0.0128, 0.0112, GLOVE))
    d, s, u = turn_to(d, s, u, seg[1])
    st.append((p1 + d * THUMB_LENGTHS[1] * 0.45, d, s, u, 0.0124, 0.0108, GLOVE))
    st.append((p1 + d * THUMB_LENGTHS[1] * 0.52, d, s, u, 0.0112, 0.0098, edge))
    p2 = p1 + d * THUMB_LENGTHS[1]
    mid = (d + seg[2]).normalized()
    dm, sm, um = turn_to(d, s, u, mid)
    st.append((p2, dm, sm, um, 0.0108, 0.0096, edge))
    d, s, u = turn_to(d, s, u, seg[2])
    st += [(p2 + d * THUMB_LENGTHS[2] * 0.45, d, s, u, 0.0102, 0.0088, edge),
           (p2 + d * THUMB_LENGTHS[2] * 0.82, d, s, u, 0.0078, 0.0066, edge),
           (p2 + d * THUMB_LENGTHS[2], d, s, u, 0.0036, 0.0030, edge)]
    prev = port
    for c, dd, ss, uu, hw, hh, mat in st:
        r = ring4(bm, c, ss, uu, hw * k, hh * k)
        bridge(bm, prev, r, mat)
        prev = r
    quad(bm, prev[0], prev[1], prev[2], prev[3], edge)
    return p2 + d * THUMB_LENGTHS[2]


WRIST_BLEND = 0.09  # distância ao longo da qual o pulso curva da mão para o braço


def build_forearm(bm, wrist_loop, W, F, D, S, U):
    center = sum((v.co for v in wrist_loop), Vector()) / len(wrist_loop)
    angles = []
    for v in wrist_loop:
        rel = v.co - center
        angles.append(math.atan2(rel.dot(U) / 0.0135, rel.dot(S) / 0.033))
    prev = wrist_loop
    c = W.copy()
    last_t = 0.0
    for t, rx, ry, mat in FOREARM:
        # A direção vai rodando de -F (continuação da mão) para D, para o pulso
        # dobrar em curva em vez de fazer um vinco.
        k = min(t / WRIST_BLEND, 1.0)
        k = k * k * (3.0 - 2.0 * k)
        d = (-F).slerp(D, k) if (-F).dot(D) > -0.99 else D
        c = c + d * (t - last_t)
        last_t = t
        X = (S - S.dot(d) * d).normalized()
        Y = (U - U.dot(d) * d - U.dot(X) * X).normalized()
        r = [bm.verts.new(c + X * (math.cos(a) * rx) + Y * (math.sin(a) * ry)) for a in angles]
        bridge(bm, prev, r, mat)
        prev = r


def get_mat(name, color, rough, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def clear_generated(prefixes=("VM_Arm", "VM_Glove", "VM_Gear")):
    for o in list(bpy.data.objects):
        if o.name.startswith(prefixes):
            bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)


def build_arm(side, p):
    F, S, N, U = frame(p["F"], p["N"], p["right"])
    W = Vector(p["W"])
    D = Vector(p["arm"]).normalized()
    bm = bmesh.new()
    finger_ports, thumb_port, wrist_loop = build_palm(bm, W, F, S, U)
    tips = {}
    for name, _, _ in FINGER_COLS:
        base = p.get("base_dirs", {}).get(name)
        base_v = (F * base[0] + S * base[1] + N * base[2]) if base else None
        tips[name] = build_finger(bm, finger_ports[name], F, S, U, FINGER_LENGTHS[name],
                                  p["curls"][name], base_v)
    tips["thumb"] = build_thumb(bm, thumb_port, F, S, N, U, p["thumb"])
    build_forearm(bm, wrist_loop, W, F, D, S, U)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    me = bpy.data.meshes.new(f"VM_Arm_{side}")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(f"VM_Arm_{side}", me)
    COLL.objects.link(ob)
    me.materials.append(get_mat("Glove", (0.022, 0.022, 0.025), 0.62))
    me.materials.append(get_mat("Skin", (0.38, 0.22, 0.14), 0.55))
    for poly in me.polygons:
        poly.use_smooth = True
    sub = ob.modifiers.new("Subdivision", "SUBSURF")
    sub.levels = 2
    sub.render_levels = 2
    return ob, tips


def build(params):
    clear_generated()
    out = {}
    for side, p in params.items():
        ob, tips = build_arm(side, p)
        parent = bpy.data.objects.get("Viewmodel")
        if parent:
            ob.parent = parent
        out[side] = {k: [round(c, 3) for c in v] for k, v in tips.items()}
    return out


def rotate_about_handguard(p, deg, axis_z=0.178):
    """Roda a pose de uma mão à volta do eixo do guarda-mão (eixo Y)."""
    from mathutils import Matrix
    R = Matrix.Rotation(math.radians(deg), 3, "Y")
    W = Vector(p["W"])
    pivot = Vector((0, W.y, axis_z))
    p["W"] = R @ (W - pivot) + pivot
    p["F"] = R @ Vector(p["F"])
    p["N"] = R @ Vector(p["N"])


# Pose de referência (usada pelo os!strike): mão direita no punho com o
# indicador no gatilho, mão esquerda debaixo do guarda-mão com o polegar
# deitado ao longo da lateral, rodada 25° para se ver do ponto de vista do jogador.
def default_params():
    F_r = Vector((0, 1, -0.42)).normalized()
    S_r = Vector((0, 0.42, 1)).normalized()
    W_r = Vector((0.034, -0.152, 0.113)) - F_r * PALM_LEN - S_r * 0.031
    params = {
        "R": {"W": W_r, "F": F_r, "N": (-1, 0, 0), "right": True,
              "curls": {"index": (38, 62, 28), "middle": (76, 82, 40), "ring": (78, 82, 40), "pinky": (80, 80, 40)},
              "base_dirs": {"index": (0.92, 0.39, 0.0)},
              "thumb": [(0.15, 0.25, 1.0), (0.85, 0.05, 0.55), (1.0, 0.0, 0.15)],
              "arm": (0.32, -1.0, -0.62)},
        "L": {"W": (-0.060, 0.092, 0.121), "F": (1.0, 0.15, 0.1), "N": (-0.3, 0.0, 1.0), "right": False,
              "curls": {"index": (50, 80, 42), "middle": (52, 82, 42), "ring": (54, 82, 42), "pinky": (56, 80, 40)},
              "thumb": [(0.45, 0.75, 0.45), (0.05, 1.0, 0.3), (-0.05, 1.0, 0.08)],
              "arm": (-0.4, -0.5, -0.8)},
    }
    rotate_about_handguard(params["L"], 25)
    # Encosta a palma ao canto inferior esquerdo do guarda-mão.
    params["L"]["W"] = Vector(params["L"]["W"]) + Vector((0.013, 0.0, 0.007))
    return params
