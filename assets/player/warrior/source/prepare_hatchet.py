"""Builds the warrior's hatchet from its Meshy source (Blender 5.2, background).

    "G:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup \
        --python assets/player/warrior/source/prepare_hatchet.py

Writes assets/weapons/player/warrior_hatchet.glb, with its PBR maps embedded and lying the way
tools/player_character_builder.gd's one-handed fit expects (as knight_sword.glb does): the
Meshy "Battle Worn Hatchet" (Meshy_AI_Battle_Worn_Hatchet_1017104201), HATCHET_LENGTH long,
handle along +Y (the glTF up) with the head at the top, the cutting edge along +X, the flats
facing +Z, origin in the handle just above the knob - where the fist closes.

Measured on the source (Blender units, Meshy's 0.95 m, upright along +Z): knob -0.475..-0.43,
the handle a slightly bent shaft about 5 cm thick centred near x 0.12 at the bottom and 0.10
under the head, the head z 0.14..0.47 with its edge out at x -0.16 and the flats facing +-Y.
Already smooth-shaded (no split normals), so nothing else is done to it.
"""
import bpy, os, math
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
OUT = os.path.join(PROJECT, "assets", "weapons", "player", "warrior_hatchet.glb")

SOURCE = os.path.join(HERE, "Meshy_AI_Battle_Worn_Hatchet_1017104201_texture.fbx")
HATCHET_LENGTH = 0.85
GRIP = Vector((0.12, 0.0, -0.37))
# The edge faces -X in the source; half a turn about the handle puts it on +X.
TURN = Matrix.Rotation(math.pi, 3, "Z")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SOURCE)
obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mesh = obj.data
zs = [v.co.z for v in mesh.vertices]
factor = HATCHET_LENGTH / (max(zs) - min(zs))
# A uniform scale, a shift and a turn: the shading normals turn with the mesh (the turn is
# applied to them too, since setting positions leaves custom normals where they were).
normals = [TURN @ Vector(l.normal) for l in mesh.loops] if mesh.has_custom_normals else None
for v in mesh.vertices:
    v.co = TURN @ ((v.co - GRIP) * factor)
if normals is not None:
    mesh.normals_split_custom_set(normals)
mesh.update()
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True)
print("WROTE %s, scaled %.3fx; %.3f below the grip, %.3f above"
      % (OUT, factor, (GRIP.z - min(zs)) * factor, (max(zs) - GRIP.z) * factor))
