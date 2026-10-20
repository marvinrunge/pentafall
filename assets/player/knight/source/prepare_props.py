"""Builds the knight's sword and shield from their Meshy sources (Blender 5.2, background).

    "G:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup \
        --python assets/player/knight/source/prepare_props.py

Writes, next to the player weapons (assets/weapons/player/), each with its PBR maps embedded
and lying the way tools/player_character_builder.gd expects:

  knight_sword.glb   the Meshy "Shadowfang" blade (Meshy_AI_Shadowfang_Greatsword_1018195833),
                     a curved one-hander a metre long: blade along +Y (the glTF up), edges
                     along +X, flats facing +Z, origin in the middle of the grip - where the
                     fist closes.
  knight_shield.glb  the Meshy "Stone Warden" shield (Meshy_AI_Stone_Warden_of_the_S_1018195827),
                     a metre tall: up along +Y, its face outwards along +Z, origin in the middle
                     of the handle on its back - where the fist closes round it.

Measured on the sources (Blender units, Meshy's 0.95 m, upright along +Z):
  sword   pommel -0.475, grip -0.45..-0.30, guard -0.29..-0.14, blade up to +0.475
  shield  face towards -Y, a vertical handle bar on the back at x -0.105, y 0.055..0.092,
          z -0.093..0.069
"""
import bpy, os
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
OUT = os.path.join(PROJECT, "assets", "weapons", "player")

SWORD_SOURCE = os.path.join(HERE, "Meshy_AI_Shadowfang_Greatsword_1018195833_texture.fbx")
SWORD_LENGTH = 1.0
SWORD_GRIP = Vector((0.02, 0.0, -0.385))

SHIELD_SOURCE = os.path.join(HERE, "Meshy_AI_Stone_Warden_of_the_S_1018195827_texture.fbx")
SHIELD_HEIGHT = 1.0
SHIELD_HANDLE = Vector((-0.105, 0.075, -0.012))


def build(source, size, origin, out_name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=source)
    obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mesh = obj.data
    zs = [v.co.z for v in mesh.vertices]
    factor = size / (max(zs) - min(zs))
    # A uniform scale and a shift leave the shading normals as they are.
    for v in mesh.vertices:
        v.co = (v.co - origin) * factor
    mesh.update()
    out = os.path.join(OUT, out_name)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True)
    print("WROTE %s, scaled %.3fx; %.3f below the origin, %.3f above"
          % (out, factor, (origin.z - min(zs)) * factor, (max(zs) - origin.z) * factor))


build(SWORD_SOURCE, SWORD_LENGTH, SWORD_GRIP, "knight_sword.glb")
build(SHIELD_SOURCE, SHIELD_HEIGHT, SHIELD_HANDLE, "knight_shield.glb")
