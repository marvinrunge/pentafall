"""Builds the barbarian's greatsword from its Meshy source (Blender 5.2, background).

    "G:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup \
        --python assets/player/barbarian/source/prepare_sword.py

Writes assets/weapons/player/barbarian_greatsword.glb: the Meshy "Scarred Sentinel"
(Meshy_AI_Scarred_Sentinel_1018120117, next to this script) with its PBR maps embedded,
scaled from Meshy's 0.95 m to a two-hander for a 1.9-tall orc, its blade drawn out longer,
and lying the way tools/player_character_builder.gd expects: the blade along +Y (the glTF
up), its edges along +X, its flats facing +Z, and the origin where the upper (right) fist
closes round the grip, just under the cross-guard.

Measured on the source (Blender units, the blade along +Z): the pommel at -0.476, the grip
up to the guard at -0.190, the guard to -0.120, the blade to the tip at +0.477. The grip is
30% of the sword - long enough for two fists at any size.
"""
import bpy, os

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
SOURCE = os.path.join(HERE, "Meshy_AI_Scarred_Sentinel_1018120117_texture.fbx")
OUT = os.path.join(PROJECT, "assets", "weapons", "player", "barbarian_greatsword.glb")

# Pommel to tip of the sword as Meshy shaped it, which sets the size of the grip and guard.
LENGTH = 1.45
GUARD_BOTTOM = -0.190
# Where the blade leaves the guard, in source units. Everything above is drawn out by
# BLADE_STRETCH; the grip and the guard keep their size.
BLADE_FROM = -0.120
BLADE_STRETCH = 1.5
# The fist's centre below the guard, in metres at the final size: half a fist and a finger.
FIST_BELOW_GUARD = 0.055

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SOURCE)
sword = next(o for o in bpy.context.scene.objects if o.type == "MESH")
bpy.context.view_layer.objects.active = sword
sword.select_set(True)
# Bake whatever the importer put on the object into the vertices first.
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mesh = sword.data

# The shading normals the export carries, read before the shape changes. A stretch along the
# blade turns a normal by the inverse of the stretch - (x, y, z / s), renormalized - so the
# lengthened blade lights exactly as the original did, smooth where it was smooth.
loop_normals = [l.normal.copy() for l in mesh.loops]

zs = [v.co.z for v in mesh.vertices]
factor = LENGTH / (max(zs) - min(zs))
grip_z = GUARD_BOTTOM * factor - FIST_BELOW_GUARD
on_blade = [v.co.z > BLADE_FROM for v in mesh.vertices]
for v in mesh.vertices:
    z = v.co.z
    if z > BLADE_FROM:
        z = BLADE_FROM + (z - BLADE_FROM) * BLADE_STRETCH
    v.co.x *= factor
    v.co.y *= factor
    v.co.z = z * factor - grip_z
for i, loop in enumerate(mesh.loops):
    if on_blade[loop.vertex_index]:
        n = loop_normals[i]
        n.z /= BLADE_STRETCH
        loop_normals[i] = n.normalized()
mesh.normals_split_custom_set(loop_normals)
mesh.update()

tip = (BLADE_FROM + (max(zs) - BLADE_FROM) * BLADE_STRETCH) * factor - grip_z
print("SWORD scaled %.3fx, blade drawn out %.1fx; grip at %.3f, pommel %.3f below it, tip %.3f above it"
      % (factor, BLADE_STRETCH, grip_z, -(min(zs) * factor - grip_z), tip))

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True)
print("WROTE", OUT)
