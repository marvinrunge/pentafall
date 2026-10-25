"""Turns the goblins' red skin green in their baked Meshy textures.

usage: python tools/recolor_goblin_skin.py

Reads goblin_{melee,ranged,mage}_0.png as committed at HEAD (so a second run starts from
the red originals only while they are still the committed version) and writes the green
ones over the working copies.

The skin is found by colour: a salmon red (hue about 5 degrees, saturation 0.4-0.8) that
the brown leather (hue 25) and the melee goblin's loincloth (pure red, saturation 0.95)
both fall outside of. The mage's robe, boots and hood are the same red as its skin, so
there colour alone would dye the clothes too: its skin is also limited to the texels of
faces weighted to the head, neck or hands - read from the rig in Blender - and to a
narrower hue, which leaves the hood's rust red (hue about 12) as it is.

The hue turns by 80 degrees, and saturation and value come down so the green reads as an
olive skin rather than a lime one; the mage's red was darker, so it comes down less.
"""
import io
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parent.parent
BLENDER = r"G:\Program Files\Blender Foundation\Blender 5.2\blender.exe"

# Runs inside Blender: every face's UVs and how much of it the head and the hands carry.
BLENDER_FACES = r'''
import bpy, sys, json
fbx, out = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx)
obj = next(o for o in bpy.data.objects if o.type == "MESH")
me = obj.data
names = {g.index: g.name.split(":")[-1] for g in obj.vertex_groups}
def region(vi):
    head = hand = total = 0.0
    for g in me.vertices[vi].groups:
        n = names[g.group]
        total += g.weight
        if n in ("Head", "Neck"):
            head += g.weight
        elif "Hand" in n:
            hand += g.weight
    total = total or 1.0
    return head / total, hand / total
uv = me.uv_layers.active.data
faces = []
for p in me.polygons:
    rs = [region(v) for v in p.vertices]
    faces.append({"uv": [list(uv[li].uv) for li in p.loop_indices],
                  "head": sum(r[0] for r in rs) / len(rs), "hand": sum(r[1] for r in rs) / len(rs)})
json.dump(faces, open(out, "w"))
'''


def ramp(x, a0, a1, b1, b0):
    """0 below a0, rising to 1 at a1, 1 up to b1, falling to 0 at b0."""
    up = np.clip((x - a0) / (a1 - a0), 0, 1)
    down = np.clip((b0 - x) / (b0 - b1), 0, 1)
    return np.minimum(up, down)


def rgb_to_hsv(rgb):
    mx = rgb.max(-1)
    d = mx - rgb.min(-1)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rm = nz & (mx == r)
    gm = nz & (mx == g) & ~rm
    bm = nz & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h * 60, s, mx


def hsv_to_rgb(h, s, v):
    h = (h % 360) / 60
    i = np.floor(h).astype(int) % 6
    f = h - np.floor(h)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    out = np.zeros(h.shape + (3,))
    for k, (a, b, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        m = i == k
        out[m] = np.stack([a[m], b[m], c[m]], -1)
    return out


def skin_region(fbx, size):
    """The texels of faces on the head, neck or hands, softened at the island edges."""
    with tempfile.TemporaryDirectory() as tmp:
        script, faces_json = Path(tmp, "faces.py"), Path(tmp, "faces.json")
        script.write_text(BLENDER_FACES)
        subprocess.run([BLENDER, "-b", "--python", str(script), "--", str(fbx), str(faces_json)],
                       check=True, capture_output=True)
        faces = json.loads(faces_json.read_text())
    img = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(img)
    for f in faces:
        # A hand's weight reaches up into the sleeve cuff; only the hand proper counts.
        if f["head"] >= 0.5 or f["hand"] >= 0.8:
            draw.polygon([(u * size, (1 - v) * size) for u, v in f["uv"]], fill=255)
    img = img.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(3))
    return np.asarray(img, float) / 255


def main():
    for kind in ("melee", "ranged", "mage"):
        rel = f"assets/enemies/{kind}/goblin/goblin_{kind}_0.png"
        blob = subprocess.check_output(["git", "-C", str(REPO), "show", "HEAD:" + rel])
        im = Image.open(io.BytesIO(blob))
        rgba = np.asarray(im.convert("RGBA"), float) / 255
        rgb = rgba[..., :3]
        h, s, v = rgb_to_hsv(rgb)
        h = np.where(h > 180, h - 360, h)
        if kind == "mage":
            w = ramp(h, -16, -8, 6, 11) * ramp(s, 0.3, 0.42, 0.85, 0.92) * ramp(v, 0.08, 0.18, 2, 3)
            w *= skin_region(REPO / f"assets/enemies/{kind}/goblin/goblin_{kind}.fbx", rgb.shape[0])
            sat_k, val_k = 0.68, 0.72
        else:
            w = ramp(h, -16, -8, 14, 22) * ramp(s, 0.3, 0.42, 0.82, 0.9) * ramp(v, 0.12, 0.25, 2, 3)
            sat_k, val_k = 0.7, 0.6
        green = hsv_to_rgb(h + 80, s * sat_k, v * val_k)
        rgba[..., :3] = rgb * (1 - w[..., None]) + green * w[..., None]
        out = Image.fromarray(np.round(np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA")
        out.convert(im.mode).save(REPO / rel)
        print(f"{kind}: {w.mean():.1%} of the texture recoloured")


if __name__ == "__main__":
    sys.exit(main())
