"""Planta do Dust II exportado (dust2.glb) vista de cima, com grelha em
coordenadas do Godot (marcas a cada 5 m, vermelhas a cada 10 m), ou vistas na
primeira pessoa a partir de posições do Godot.

Uso:
  blender -b --factory-startup --python render_dust2_plan.py -- <dust2.glb> <pasta texturas> <saída.png> plan <cx> <cz> <tamanho>
  blender -b --factory-startup --python render_dust2_plan.py -- <dust2.glb> <pasta texturas> <saída.png> eye <x> <y> <z> <yaw> <fov>
(yaw em graus: 0 = olhar para -Z do Godot, positivo = rodar para a esquerda)
"""
import bpy, sys, os, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
glb, tex_dir, out, mode = argv[:4]
nums = [float(v) for v in argv[4:]]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
cache = {}
for o in list(bpy.context.scene.objects):
    if o.type != 'MESH':
        continue
    part = "part10" if o.name.startswith("Prop_Crate") else o.name.split(".")[0]
    path = os.path.join(tex_dir, part + ".jpg")
    if not os.path.exists(path):
        continue
    if part not in cache:
        img = bpy.data.images.load(path)
        if img.size[0] > 2048:
            img.scale(2048, 2048)
        mat = bpy.data.materials.new(part)
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
        tn = nt.nodes.new('ShaderNodeTexImage')
        tn.image = img
        nt.links.new(tn.outputs['Color'], bsdf.inputs['Base Color'])
        cache[part] = mat
    o.data.materials.clear()
    o.data.materials.append(cache[part])

sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'FLAT'
sc.display.shading.color_type = 'TEXTURE'
world = bpy.data.worlds.new("w")
sc.world = world
world.color = (0.45, 0.62, 0.85)
cam_d = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam

if mode == "plan":
    cx, cz, size = nums
    red = bpy.data.materials.new("red"); red.diffuse_color = (1, 0, 0, 1)
    blue = bpy.data.materials.new("blue"); blue.diffuse_color = (0, 0.4, 1, 1)
    half = size / 2
    gx = math.floor((cx - half) / 5) * 5
    while gx <= cx + half:
        gz = math.floor((cz - half) / 5) * 5
        while gz <= cz + half:
            big = round(gx) % 10 == 0 and round(gz) % 10 == 0
            bpy.ops.mesh.primitive_cube_add(size=0.9 if big else 0.4, location=(gx, -gz, 20))
            c = bpy.context.active_object
            c.data.materials.append(red if big else blue)
            gz += 5
        gx += 5
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 1600
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = size
    cam.location = (cx, -cz, 60)
    cam.rotation_euler = (0, 0, 0)
else:
    x, y, z, yaw, fov = nums
    if mode == "eyefloor":
        # y = altura dos olhos acima do chão nesse ponto.
        from mathutils.bvhtree import BVHTree
        dg = bpy.context.evaluated_depsgraph_get()
        hit, loc, n, i, ob, m = sc.ray_cast(dg, Vector((x, -z, 30.0)), Vector((0, 0, -1)))
        floor = loc.z if hit else 0.0
        print("FLOOR", round(floor, 3))
        y = floor + y
    sc.render.resolution_x = 1280
    sc.render.resolution_y = 720
    cam_d.sensor_fit = 'HORIZONTAL'
    cam_d.angle = math.radians(fov)
    cam_d.clip_start = 0.05
    cam.location = (x, -z, y)
    cam.rotation_euler = (math.radians(90), 0, math.radians(yaw))
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("SAVED", out)
