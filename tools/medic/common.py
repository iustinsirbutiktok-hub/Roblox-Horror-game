import bpy, bmesh, math
from mathutils import Vector as V, Matrix


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def apply_modifiers(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    mesh = bpy.data.meshes.new_from_object(ev)
    obj.modifiers.clear()
    old = obj.data
    obj.data = mesh
    bpy.data.meshes.remove(old)


def select_only(obj):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def decimate(obj, target_tris):
    t = tri_count(obj)
    if t <= target_tris:
        return
    m = obj.modifiers.new("Dec", "DECIMATE")
    m.ratio = target_tris / t
    m.use_collapse_triangulate = True
    apply_modifiers(obj)


def shade_smooth(obj, angle=60):
    for p in obj.data.polygons:
        p.use_smooth = True
    try:
        select_only(obj)
        bpy.ops.object.shade_auto_smooth(angle=math.radians(angle))
    except Exception:
        pass


def simple_material(name, color, rough=0.7, metal=0.0, emit=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return mat


def render(path, cams, size=(520, 760), samples=24, focus=None, lights=True, bg=(0.02, 0.02, 0.025)):
    """cams: list of (location, look_at, lens) -> renders side by side via several files"""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = False
    scene.cycles.device = "CPU"
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.film_transparent = False
    world = bpy.data.worlds.get("W") or bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (*bg, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scene.world = world
    if lights and not bpy.data.objects.get("KeyLight"):
        for name, loc, energy, size_ in (("KeyLight", (7, -3.5, 7), 900, 1.5), ("RimLight", (-4, 5, 8), 600, 2),
                                         ("FillLight", (-6, -5, 3), 90, 5)):
            ld = bpy.data.lights.new(name, "AREA")
            ld.energy = energy
            ld.size = size_
            lo = bpy.data.objects.new(name, ld)
            lo.location = loc
            direction = V((0, 0, 4.5)) - V(loc)
            lo.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
            link(lo)
    outs = []
    for i, (loc, at, lens) in enumerate(cams):
        cd = bpy.data.cameras.new("Cam%d" % i)
        cd.lens = lens
        co = bpy.data.objects.new("Cam%d" % i, cd)
        co.location = loc
        co.rotation_euler = (V(at) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        link(co)
        scene.camera = co
        out = path.replace(".png", "_%d.png" % i)
        scene.render.filepath = out
        bpy.ops.render.render(write_still=True)
        outs.append(out)
        bpy.data.objects.remove(co)
    return outs
