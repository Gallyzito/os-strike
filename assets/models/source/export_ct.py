"""Prepara o CT (models/counter-terrorist) para o jogo: esqueleto, pose de tiro
com a AK, animações e exportação para glb.

Uso:
  blender -b --factory-startup --python export_ct.py -- <sketchfab_obj.obj> <pasta texturas> <viewmodel_ak.glb> <saída.glb>

O OBJ traz duas versões do boneco; usa-se a de T-pose (uma só malha). Ele é:
- escalado para 1.83 m (72 unidades do CS), pés no chão, virado para +Y do
  Blender (= -Z do Godot) com a mão direita em +X;
- ligado a um esqueleto simples com pesos calculados pela distância aos ossos;
- posto em pose de tiro (tronco rodado, AK ao ombro) e essa pose passa a ser
  a pose de repouso. A AK fica presa à mão direita.
Animações: aim, strafe (ciclo), death e death_head.
"""
import bpy, sys, os, math
import numpy as np
from mathutils import Vector, Matrix, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:]
obj_path, tex_dir, ak_glb, out_path = argv[:4]

HEIGHT = 1.83
CX, CY, FEET = 11.93, -0.1, -0.549
S = HEIGHT / (10.498 - FEET)
FPS = 24


def T(dx, y, z):
    """Ponto do OBJ (dx = x - centro, + = lado esquerdo do boneco) -> final."""
    return Vector((-dx * S, -(y - CY) * S, (z - FEET) * S))


bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS

# --- Malha ------------------------------------------------------------------------
bpy.ops.wm.obj_import(filepath=obj_path)
objs = [o for o in scene.objects if o.type == 'MESH']
body = max(objs, key=lambda o: len(o.data.vertices))
for o in objs:
    if o is not body:
        bpy.data.objects.remove(o)
body.name = "CT"
mw = body.matrix_world.copy()
body.matrix_world = Matrix.Identity(4)
orig = [mw @ v.co for v in body.data.vertices]
for v, p in zip(body.data.vertices, orig):
    v.co = T(p.x - CX, p.y, p.z)
body.data.update()

# Material com as texturas (reduzidas; normal map convertido de DirectX para OpenGL).
def load_scaled(name, size, flip_green=False):
    img = bpy.data.images.load(os.path.join(tex_dir, name))
    if img.size[0] != size:
        img.scale(size, size)
    if flip_green:
        px = np.empty(size * size * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        px[1::4] = 1.0 - px[1::4]
        img.pixels.foreach_set(px)
    img.pack()
    return img

mat = bpy.data.materials.new("ct_body")
mat.use_nodes = True
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
def tex_node(img, non_color=False):
    n = nt.nodes.new('ShaderNodeTexImage')
    n.image = img
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    return n
base = tex_node(load_scaled("char_lp_Base_color.png", 2048))
nt.links.new(base.outputs['Color'], bsdf.inputs['Base Color'])
rough = tex_node(load_scaled("char_lp_Roughness.png", 1024), True)
nt.links.new(rough.outputs['Color'], bsdf.inputs['Roughness'])
metal = tex_node(load_scaled("char_lp_Metallic.png", 1024), True)
nt.links.new(metal.outputs['Color'], bsdf.inputs['Metallic'])
nrm_img = load_scaled("char_lp_Normal_DirectX.png", 2048, flip_green=True)
nrm = tex_node(nrm_img, True)
nmap = nt.nodes.new('ShaderNodeNormalMap')
nt.links.new(nrm.outputs['Color'], nmap.inputs['Color'])
nt.links.new(nmap.outputs['Normal'], bsdf.inputs['Normal'])
body.data.materials.clear()
body.data.materials.append(mat)

# --- Esqueleto ----------------------------------------------------------------------
BONES = [
    # nome, pai, cabeça (dx, y, z do OBJ), cauda
    ("hips", None, (0, -0.1, 5.1), (0, -0.1, 5.9)),
    ("spine", "hips", (0, -0.1, 5.9), (0, -0.1, 7.0)),
    ("chest", "spine", (0, -0.1, 7.0), (0, -0.1, 8.75)),
    ("neck", "chest", (0, -0.1, 8.75), (0, -0.15, 9.15)),
    ("head", "neck", (0, -0.15, 9.15), (0, -0.15, 10.5)),
]
for side, sx in (("L", 1), ("R", -1)):
    BONES += [
        (f"shoulder.{side}", "chest", (0.35 * sx, -0.05, 8.25), (1.2 * sx, 0.05, 8.36)),
        (f"upper_arm.{side}", f"shoulder.{side}", (1.2 * sx, 0.05, 8.36), (2.65 * sx, 0.05, 8.38)),
        (f"forearm.{side}", f"upper_arm.{side}", (2.65 * sx, 0.05, 8.38), (4.2 * sx, 0.05, 8.35)),
        (f"hand.{side}", f"forearm.{side}", (4.2 * sx, 0.05, 8.35), (5.3 * sx, 0.05, 8.35)),
        (f"thigh.{side}", "hips", (0.54 * sx, -0.1, 5.1), (0.6 * sx, -0.05, 2.7)),
        (f"shin.{side}", f"thigh.{side}", (0.6 * sx, -0.05, 2.7), (0.62 * sx, 0.05, 0.55)),
        (f"foot.{side}", f"shin.{side}", (0.62 * sx, 0.05, 0.55), (0.62 * sx, -0.85, -0.35)),
    ]

arm_data = bpy.data.armatures.new("Skeleton")
arm = bpy.data.objects.new("Skeleton", arm_data)
scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for name, parent, h, t in BONES:
    eb = arm_data.edit_bones.new(name)
    eb.head = T(*h)
    eb.tail = T(*t)
    if parent:
        eb.parent = arm_data.edit_bones[parent]
        eb.use_connect = (eb.parent.tail - eb.head).length < 1e-4
    # Rolo: eixo Z do osso aponta para a frente (+Y) ou para cima.
    eb.align_roll(Vector((0, 1, 0)) if abs((eb.tail - eb.head).normalized().y) < 0.9 else Vector((0, 0, 1)))
bpy.ops.object.mode_set(mode='OBJECT')
rest = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in arm_data.bones}

# --- Pesos (distância aos ossos, com regiões para não misturar membros) -----------------
def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length

groups = {name: body.vertex_groups.new(name=name) for name, *_ in BONES}
for v, p in zip(body.data.vertices, orig):
    dx, z = p.x - CX, p.z
    side = "L" if dx > 0 else "R"
    if abs(dx) > 1.15 and z > 7.55:
        allowed = [f"shoulder.{side}", f"upper_arm.{side}", f"forearm.{side}", f"hand.{side}"]
        if abs(dx) < 1.7:
            allowed.append("chest")
    elif z < 5.0:
        allowed = [f"thigh.{side}", f"shin.{side}", f"foot.{side}"]
        if z > 4.2:
            allowed.append("hips")
    elif z > 8.8 and abs(dx) < 1.0:
        allowed = ["neck", "head"]
    else:
        allowed = ["hips", "spine", "chest", "neck", f"shoulder.{side}"]
    ws = []
    for name in allowed:
        a, b = rest[name]
        d = seg_dist(v.co, a, b)
        ws.append((1.0 / (d ** 4 + 1e-7), name))
    ws.sort(reverse=True)
    ws = ws[:2]
    total = sum(w for w, _ in ws)
    for w, name in ws:
        groups[name].add([v.index], w / total, 'REPLACE')

body.parent = arm
mod = body.modifiers.new("Armature", 'ARMATURE')
mod.object = arm

# --- Pose de tiro ---------------------------------------------------------------------
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
pbs = arm.pose.bones
for pb in pbs:
    pb.rotation_mode = 'QUATERNION'


def rot_arm_axis(pb, axis, deg):
    """Roda um osso em torno de um eixo do esqueleto (no repouso), em graus."""
    local = pb.bone.matrix_local.to_3x3().inverted() @ Vector(axis)
    pb.rotation_quaternion = Quaternion(local.normalized(), math.radians(deg)) @ pb.rotation_quaternion


TORSO_TURN = 40.0
rot_arm_axis(pbs["spine"], (0, 0, 1), TORSO_TURN * 0.4)
rot_arm_axis(pbs["chest"], (0, 0, 1), TORSO_TURN * 0.6)
rot_arm_axis(pbs["neck"], (0, 0, 1), -TORSO_TURN * 0.5)
rot_arm_axis(pbs["head"], (0, 0, 1), -TORSO_TURN * 0.5)
rot_arm_axis(pbs["head"], (1, 0, 0), -6)
# Ombro esquerdo para a frente, para a mão chegar ao guarda-mão.
rot_arm_axis(pbs["shoulder.L"], (0, 0, 1), -18)
bpy.context.view_layer.update()

# AK: coronha no ombro, mão direita no punho, esquerda no guarda-mão.
GRIP_ON_AK = Vector((0.0, -0.17, 0.10))
GUARD_ON_AK = Vector((0.0, 0.16, 0.16))
RIGHT_HAND = Vector((0.10, 0.14, 1.33))
AK_OFFSET = RIGHT_HAND - GRIP_ON_AK
LEFT_HAND = AK_OFFSET + GUARD_ON_AK

targets = {}
for side, pos, pole in (("R", RIGHT_HAND, Vector((0.6, -0.2, 0.6))), ("L", LEFT_HAND, Vector((-0.6, 0.1, 0.4)))):
    for nm, p in (("tgt", pos), ("pole", pole)):
        e = bpy.data.objects.new(f"{nm}.{side}", None)
        scene.collection.objects.link(e)
        e.location = p
        targets[f"{nm}.{side}"] = e
    c = pbs[f"forearm.{side}"].constraints.new('IK')
    c.target = targets[f"tgt.{side}"]
    c.pole_target = targets[f"pole.{side}"]
    c.pole_angle = math.radians(-90)
    c.chain_count = 2
bpy.context.view_layer.update()
for pb in pbs:
    if hasattr(pb, "select"):
        pb.select = True
    else:
        pb.bone.select = True
bpy.ops.pose.visual_transform_apply()
for side in ("L", "R"):
    pb = pbs[f"forearm.{side}"]
    for c in list(pb.constraints):
        pb.constraints.remove(c)
bpy.context.view_layer.update()
for side in ("L", "R"):
    tip = arm.matrix_world @ pbs[f"forearm.{side}"].tail
    want = targets[f"tgt.{side}"].location
    print(f"IK {side}: mão em {tuple(round(c, 3) for c in tip)} alvo {tuple(round(c, 3) for c in want)} erro {(tip - want).length:.3f}")
# As mãos continuam a direção do antebraço, ligeiramente fechadas para dentro.
rot_arm_axis(pbs["hand.R"], (0, 0, 1), 0)
bpy.ops.object.mode_set(mode='OBJECT')

# A pose de tiro passa a ser a pose de repouso.
bpy.context.view_layer.objects.active = body
bpy.ops.object.modifier_apply(modifier="Armature")
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')
mod = body.modifiers.new("Armature", 'ARMATURE')
mod.object = arm
for e in targets.values():
    bpy.data.objects.remove(e)

# --- AK na mão direita ------------------------------------------------------------------
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=ak_glb)
imported = [o for o in bpy.data.objects if o not in before]
ak_parts = [o for o in imported if o.type == 'MESH' and o.name.startswith("AK47")]
others = [o.name for o in imported if o not in ak_parts]
for o in ak_parts:
    m = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = m
for name in others:
    bpy.data.objects.remove(bpy.data.objects[name])
bpy.ops.object.select_all(action='DESELECT')
for o in ak_parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = ak_parts[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.join()
ak = bpy.context.view_layer.objects.active
ak.name = "AK47"
for v in ak.data.vertices:
    v.co = v.co + AK_OFFSET
ak.data.update()
g = ak.vertex_groups.new(name="hand.R")
g.add(list(range(len(ak.data.vertices))), 1.0, 'REPLACE')
ak.parent = arm
m2 = ak.modifiers.new("Armature", 'ARMATURE')
m2.object = arm
muzzle = Vector((AK_OFFSET.x, AK_OFFSET.y + 0.49, AK_OFFSET.z + 0.205))
print("MUZZLE", tuple(round(c, 3) for c in muzzle))

# --- Animações ---------------------------------------------------------------------------
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
pbs = arm.pose.bones
arm.animation_data_create()


def clear_pose():
    for pb in pbs:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()


def key_all(frame):
    for pb in pbs:
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def set_loc(pb, delta):
    pb.location = pb.bone.matrix_local.to_3x3().inverted() @ Vector(delta)


def new_action(name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    return act


# aim: pose de repouso.
new_action("aim")
clear_pose()
key_all(0)
key_all(1)

# strafe: passos para o lado (ciclo de 12 frames).
new_action("strafe")
for f, k in ((0, 0.0), (3, 1.0), (6, 0.0), (9, -1.0), (12, 0.0)):
    clear_pose()
    rot_arm_axis(pbs["thigh.L"], (0, 1, 0), -14 * k)
    rot_arm_axis(pbs["thigh.R"], (0, 1, 0), -14 * k)
    rot_arm_axis(pbs["shin.L"], (1, 0, 0), 22 * max(k, 0))
    rot_arm_axis(pbs["shin.R"], (1, 0, 0), 22 * max(-k, 0))
    rot_arm_axis(pbs["thigh.L"], (1, 0, 0), -12 * max(k, 0))
    rot_arm_axis(pbs["thigh.R"], (1, 0, 0), -12 * max(-k, 0))
    set_loc(pbs["hips"], (0, 0, -0.035 * abs(k)))
    key_all(f)


def death(name, head_snap):
    new_action(name)
    keys = [
        # frame, queda (graus), recuo, descida, cabeça, joelhos, braços
        (0, 0, 0.0, 0.0, 0, 0, 0),
        (3, 6, -0.05, -0.02, head_snap, 8, 10),
        (8, 28, -0.25, -0.22, head_snap * 0.8, 35, 35),
        (13, 62, -0.6, -0.55, head_snap * 0.6, 45, 60),
        (17, 86, -0.88, -0.76, head_snap * 0.4, 30, 75),
        (20, 90, -0.92, -0.79, head_snap * 0.4, 25, 80),
        (26, 90, -0.92, -0.79, head_snap * 0.4, 25, 80),
    ]
    for f, fall, back, down, head, knees, arms in keys:
        clear_pose()
        rot_arm_axis(pbs["hips"], (1, 0, 0), fall)
        set_loc(pbs["hips"], (0, back, down))
        rot_arm_axis(pbs["chest"], (1, 0, 0), min(fall, 10) * 0.6)
        rot_arm_axis(pbs["head"], (1, 0, 0), head)
        for s in ("L", "R"):
            rot_arm_axis(pbs[f"thigh.{s}"], (1, 0, 0), -knees * 0.6)
            rot_arm_axis(pbs[f"shin.{s}"], (1, 0, 0), knees)
            rot_arm_axis(pbs[f"upper_arm.{s}"], (1, 0, 0), arms * 0.7)
            rot_arm_axis(pbs[f"forearm.{s}"], (1, 0, 0), -arms * 0.3)
        key_all(f)


death("death", 14)
death("death_head", 38)

arm.animation_data.action = bpy.data.actions["aim"]
bpy.ops.object.mode_set(mode='OBJECT')

# Os ossos ficam com os nomes; a malha com o material e as texturas embutidas.
bpy.ops.object.select_all(action='DESELECT')
for o in (arm, body, ak):
    o.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_yup=True,
    export_animations=True,
    export_animation_mode='ACTIONS',
    export_image_format='JPEG',
    export_skins=True,
)
print("EXPORTED", out_path)

# Imagens de verificação (frente e lado) da pose de tiro.
if len(argv) > 4:
    prev = argv[4]
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'TEXTURE'
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = 3.0
    cam = bpy.data.objects.new("cam", cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for nm, loc, rot in (("front", (0, 5, 0.95), (math.radians(90), 0, math.radians(180))),
                         ("side", (5, 0, 0.95), (math.radians(90), 0, math.radians(90))),
                         ("threeq", (3.5, 3.5, 1.6), (math.radians(80), 0, math.radians(135)))):
        cam.location = loc
        cam.rotation_euler = rot
        for act, fr in (("aim", 0), ("death", 26), ("strafe", 3)):
            arm.animation_data.action = bpy.data.actions[act]
            scene.frame_set(fr)
            scene.render.filepath = os.path.join(prev, f"ct_{nm}_{act}.png")
            bpy.ops.render.render(write_still=True)
