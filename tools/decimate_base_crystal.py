"""Builds assets/structures/base-cristal/base_crystal.glb, the base crystal's mesh, from
Meshy's FBX at a fifth of its triangles.

usage: "G:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup
           --python tools/decimate_base_crystal.py

Meshy's crystal is 5,694 triangles, most of them spent on facets that are flat anyway. A
collapse decimate to RATIO keeps the silhouette and the bevels along the facet edges (the
surface moves by about a tenth of a percent of its height) and the baked texture stays put
on it: half the surface within a texel of where it was, nearly all of it within ten of the
2048. The normals are then copied over from the original surface rather than recomputed,
so the decimated crystal shades as Meshy's did.

Exported without its textures: base_crystal.glb.import points the material at
base_crystal_material.tres, the material Godot imported from the FBX, so the look is the
same one and the textures are not duplicated. Godot generates the LODs on import.
"""
import os

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOLDER = os.path.join(ROOT, "assets", "structures", "base-cristal")
SOURCE = os.path.join(FOLDER, "Meshy_AI_Ein_riesiger_schweben_0523220202_texture.fbx")
TARGET = os.path.join(FOLDER, "base_crystal.glb")
RATIO = 0.18


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=SOURCE)
    original = next(o for o in bpy.data.objects if o.type == "MESH")
    crystal = original.copy()
    crystal.data = original.data.copy()
    crystal.name = crystal.data.name = "BaseCrystal"
    bpy.context.collection.objects.link(crystal)
    bpy.context.view_layer.objects.active = crystal

    decimate = crystal.modifiers.new("decimate", "DECIMATE")
    decimate.decimate_type = "COLLAPSE"
    decimate.ratio = RATIO
    decimate.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=decimate.name)

    normals = crystal.modifiers.new("normals", "DATA_TRANSFER")
    normals.object = original
    normals.use_loop_data = True
    normals.data_types_loops = {"CUSTOM_NORMAL"}
    normals.loop_mapping = "POLYINTERP_NEAREST"
    bpy.ops.object.modifier_apply(modifier=normals.name)

    bpy.data.objects.remove(original)
    crystal.data.calc_loop_triangles()
    print("BASE CRYSTAL %d triangles" % len(crystal.data.loop_triangles))

    bpy.ops.export_scene.gltf(
        filepath=TARGET,
        export_format="GLB",
        use_selection=False,
        export_image_format="NONE",
        export_normals=True,
        export_texcoords=True,
        export_tangents=False,
        export_animations=False,
        export_yup=True,
    )
    print("BASE CRYSTAL wrote %s" % TARGET)


main()
