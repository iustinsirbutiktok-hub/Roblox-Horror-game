import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import bpy
OUT = os.path.join(os.path.dirname(__file__), "out")
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT, "TheMedic.blend"))
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "TheMedic.blend"))
for o in scene.objects:
    o.select_set(o.name in ("MedicRig", "TheMedic"))
bpy.context.view_layer.objects.active = bpy.data.objects["MedicRig"]
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, "TheMedic.fbx"), use_selection=True, object_types={"ARMATURE", "MESH"},
    apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", global_scale=1.0,
    axis_forward="-Z", axis_up="Y", add_leaf_bones=False, use_armature_deform_only=True,
    bake_anim=False, path_mode="COPY", embed_textures=True, mesh_smooth_type="FACE",
)
