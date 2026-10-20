"""Builds the archer's two props from their sources (Blender 5.2, background).

    "G:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup \
        --python assets/player/archer/source/prepare_props.py -- <quiver fbx>

Writes, next to the player weapon (assets/weapons/player/):

  archer_longbow.glb  the elf ranged enemy's bow (assets/weapons/elf-bow.glb) with its string
                      cut away and scaled up to a longbow. The string is drawn at runtime
                      instead (scripts/bow_kit.gd), so it can follow the drawing hand - a
                      string baked into the mesh stays straight while the arrow is pulled back.
  archer_quiver.glb   the Meshy quiver (Meshy_AI_Elven_Archer_s_Quiver_1017104142), as is,
                      with its PBR maps embedded.

The bow mesh is a triangle soup - every triangle is its own loose part - so the string is
found by shape rather than by connectivity: it is the only geometry where a single triangle
spans more than a third of the bow's length.
"""
import bpy, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
OUT = os.path.join(PROJECT, "assets", "weapons", "player")
BOW_SOURCE = os.path.join(PROJECT, "assets", "weapons", "elf-bow.glb")

# Tip to tip. The elf bow is 1.0 long; a longbow for a 1.9-tall archer is about chin high.
LONGBOW_LENGTH = 1.55
STRING_MIN_SPAN = 0.3

argv = sys.argv[sys.argv.index("--") + 1:]
quiver_fbx = argv[0]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def export(path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
    print("WROTE", path)


reset()
bpy.ops.import_scene.gltf(filepath=BOW_SOURCE)
bow = next(o for o in bpy.context.scene.objects if o.type == "MESH")
mesh = bow.data
removed = 0
import bmesh
bm = bmesh.new()
bm.from_mesh(mesh)
doomed = []
for face in bm.faces:
    xs = [v.co.x for v in face.verts]
    if max(xs) - min(xs) > STRING_MIN_SPAN:
        doomed.append(face)
removed = len(doomed)
bmesh.ops.delete(bm, geom=doomed, context="FACES")
loose = [v for v in bm.verts if not v.link_faces]
bmesh.ops.delete(bm, geom=loose, context="VERTS")
bm.to_mesh(mesh)
bm.free()
print("BOW string faces removed:", removed)
xs = [v.co.x for v in mesh.vertices]
factor = LONGBOW_LENGTH / (max(xs) - min(xs))
bow.scale = (bow.scale[0] * factor, bow.scale[1] * factor, bow.scale[2] * factor)
bpy.context.view_layer.objects.active = bow
bow.select_set(True)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
export(os.path.join(OUT, "archer_longbow.glb"))

reset()
bpy.ops.import_scene.fbx(filepath=quiver_fbx)
export(os.path.join(OUT, "archer_quiver.glb"))
