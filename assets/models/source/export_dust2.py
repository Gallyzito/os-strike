"""Converte o Dust II (models/de-dust-2-with-real-light) para o jogo.

Uso (Blender sem interface):
  blender -b --factory-startup --python export_dust2.py -- <2.fbx> <pasta texturas> <pasta saída>

- O modelo vem em unidades do CS / 100 (uma caixa de 64 unidades mede 0.64):
  multiplica-se por 2.54 para ficar em metros (1 unidade = 1 polegada).
- O mapa é deslocado para o jogador (topo da rampa das portas do Long) ficar
  na origem, a olhar para o bombsite A.
- As texturas têm a luz "pintada" (canal UV 2). Fica só esse canal UV e as
  texturas são reduzidas para caberem na memória da gráfica.
"""
import bpy, sys, os

argv = sys.argv[sys.argv.index("--") + 1:]
fbx, tex_dir, out_dir = argv[:3]

UNITS_TO_METERS = 2.54
# Posição do jogador no modelo original (antes da escala).
PLAYER = (14.4, 8.4, 0.0)
# Resolução das texturas por peça: as do Long ficam com mais detalhe.
TEX_SIZE = {"part9": 8192, "part10": 8192}
DEFAULT_TEX_SIZE = 2048

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx)

meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

offset = [-c * UNITS_TO_METERS for c in PLAYER]
for o in meshes:
    me = o.data
    for v in me.vertices:
        v.co = v.co * UNITS_TO_METERS
        v.co.x += offset[0]
        v.co.y += offset[1]
        v.co.z += offset[2]
    # Só o canal com a luz pintada.
    for uv in list(me.uv_layers):
        if uv.name != "UVChannel_2":
            me.uv_layers.remove(uv)
    me.uv_layers[0].name = "UVMap"
    mat = me.materials[0]
    mat.name = o.name
    if mat.use_nodes:
        for n in list(mat.node_tree.nodes):
            if n.type == 'TEX_IMAGE':
                mat.node_tree.nodes.remove(n)
    me.update()

# Remove objetos que não são malhas (câmaras, luzes do FBX).
for o in list(bpy.context.scene.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o)

# --- Caixas extra no Long ---------------------------------------------------------
# O Long deste modelo não tem cobertura perto das portas. Copiamos a caixa da rua
# lateral (com a luz pintada) para dentro do Long. A caixa original só tem as
# faces da frente (+Z do Godot), da direita (+X) e de cima, por isso as cópias
# do lado direito são espelhadas para a face lateral ficar virada para o meio.
# Coordenadas do Blender aqui: x, y (= -z do Godot), z para cima.
CRATE = 1.6256
CRATE_MIN = (-13.83, 7.90, -0.02)
CRATE_MAX = (-12.17, 9.57, 1.65)
# (x, z do Godot, altura da pilha, espelhada)
CRATE_PLACES = [
    # Long (o jogador está na origem, a olhar para -Z). Pilhas de duas: uma
    # caixa sozinha (1.63 m) não esconde um bot de pé (1.83 m).
    (-3.45, -6.2, 2, False),
    (3.0, -8.8, 2, True),
    (-3.45, -11.8, 2, False),
    (3.0, -14.5, 2, True),
    (-3.45, -17.6, 2, False),
    (3.0, -19.6, 2, True),
    # Em cima do ressalto à direita das portas.
    (6.4, -2.8, 2, True),
    # Mid (o jogador está em x -46.5, z 10, a olhar para -Z).
    (-48.6, 5.0, 2, False),
    (-44.6, 1.0, 2, True),
    (-48.6, -4.5, 2, False),
    (-44.6, -8.5, 2, True),
]


def crate_mesh(mirror):
    src = bpy.data.objects["part10"]
    me = src.data
    uv = me.uv_layers[0]
    origin = ((CRATE_MIN[0] + CRATE_MAX[0]) / 2, (CRATE_MIN[1] + CRATE_MAX[1]) / 2, 0.0)
    verts, faces, uvs = [], [], []
    for p in me.polygons:
        co = [me.vertices[i].co for i in p.vertices]
        if all(CRATE_MIN[k] <= c[k] <= CRATE_MAX[k] for c in co for k in range(3)):
            base = len(verts)
            for li, vi in zip(p.loop_indices, p.vertices):
                c = me.vertices[vi].co
                x = c.x - origin[0]
                verts.append((-x if mirror else x, c.y - origin[1], c.z))
                uvs.append(tuple(uv.data[li].uv))
            idx = list(range(base, base + len(p.vertices)))
            if mirror:
                # Espelhar inverte a face: troca a ordem dos vértices (cada um mantém o seu UV).
                idx.reverse()
            faces.append(idx)
    new = bpy.data.meshes.new("crate_mirror" if mirror else "crate")
    new.from_pydata(verts, [], faces)
    new.uv_layers.new(name="UVMap")
    for i, l in enumerate(new.loops):
        new.uv_layers[0].data[i].uv = uvs[l.vertex_index]
    new.materials.append(me.materials[0])
    new.update()
    print("CRATE faces", len(faces), "mirror", mirror)
    return new


dg = bpy.context.evaluated_depsgraph_get()
crates = {False: crate_mesh(False), True: crate_mesh(True)}
for i, (gx, gz, stack, mirror) in enumerate(CRATE_PLACES):
    bx, by = gx, -gz
    hit, loc, n, idx, ob, m = bpy.context.scene.ray_cast(dg, (bx, by, 2.5), (0, 0, -1))
    floor = loc.z if hit else 0.0
    for level in range(stack):
        o = bpy.data.objects.new(f"Prop_Crate_{i}_{level}", crates[mirror])
        o.location = (bx, by, floor + level * CRATE)
        bpy.context.scene.collection.objects.link(o)
        print("CRATE at", gx, gz, "floor", round(floor, 3), "level", level)

os.makedirs(os.path.join(out_dir, "textures"), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=os.path.join(out_dir, "dust2.glb"),
    export_format='GLB',
    export_yup=True,
    export_image_format='NONE',
    export_normals=True,
    export_texcoords=True,
    export_materials='PLACEHOLDER',
)

# Texturas reduzidas.
files = {os.path.splitext(f)[0]: f for f in os.listdir(tex_dir)}
sc = bpy.context.scene
sc.view_settings.view_transform = 'Standard'
sc.render.image_settings.file_format = 'JPEG'
sc.render.image_settings.quality = 92
for o in meshes:
    key = o.name if o.name in files else o.name + "a"
    path = os.path.join(out_dir, "textures", o.name + ".jpg")
    if os.environ.get("SKIP_TEX") and os.path.exists(path):
        continue
    img = bpy.data.images.load(os.path.join(tex_dir, files[key]))
    size = TEX_SIZE.get(o.name, DEFAULT_TEX_SIZE)
    if img.size[0] != size:
        img.scale(size, size)
    img.save_render(path, scene=sc)
    print("TEXTURE", path, size)
    bpy.data.images.remove(img)
print("DONE")
