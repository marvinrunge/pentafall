"""Cuts single objects out of an asset sheet into Meshy image-to-3D references.

usage: python tools/cut_sheet_references.py <cuts.json> [id ...]

An asset sheet (a page of props drawn together on a dark backdrop, like the black biome's
graveyard set) has what Meshy wants - a three-quarter view of each object - but next to
its neighbours, labels and divider lines. Each cut takes one object's box and ISOLATES it:
the object keeps the sheet's own backdrop around it, and everything that is not it -
a neighbour reaching into the box, a label, a line - is painted over with that backdrop.
Then it is centred on a square of the same colour with a wide margin. Meshy removes a plain
background itself, and does it better than a cut-out here could: the shaded faces of
these props are as dark and as smooth as the backdrop, and every mask tried cut them off.

cuts.json, beside the sheet:

    {"sheet": "sheet.jpg", "out": ".", "size": 1024,
     "cuts": [{"id": "mausoleum", "box": [x0, y0, x1, y1], "seeds": [[x, y]],
               "erase": [[x0, y0, x1, y1]], "flame": [[x0, y0, x1, y1]], "keep_all": false}]}

    box       the object in sheet pixels; a margin is added
    seeds     points ON a lit, grained part of the object (sheet pixels): only what
              connects to one of them is kept. Default: the box centre.
    erase     boxes painted over with the backdrop first (a label, a divider line, smoke)
    flame     boxes in which fire - bright, orange - is painted over, so a brazier reaches
              Meshy as a bowl of embers (the flames are the game's, not the mesh's)
    keep_all  keep every separate part in the box (rubble, a scatter of pieces)

Finding the object: the backdrop is smooth, and stone, iron and wood are grained, so the
grained pixels the border flood fill cannot reach, connected to a seed, are the object.
That misses its smoothest darkest faces, which is why it is grown by REACH pixels before
anything is painted over - near the object, the sheet is left as it is.
Free; writes <out>/<id>.png and prints its SHA-256 for the approval record.
"""
import hashlib
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

MARGIN = 30
## The texture window, and the luminance spread below which a neighbourhood is smooth
## (the backdrop's JPEG noise sits around 1-2).
WINDOW = 5
SMOOTH = 3.5
## A smooth pixel this close to the backdrop's colour (largest channel difference) is
## backdrop - shadows and glow halos included; any pixel this close is.
SMOOTH_NEAR = 60
NEAR = 10
## How far past the found object the sheet is kept as it is, and how soft the seam is.
REACH = 18
FEATHER = 6.0


def _box(a: np.ndarray, k: int) -> np.ndarray:
    """The mean over a k x k neighbourhood, by summed-area table."""
    pad = k // 2
    c = np.pad(np.pad(a, pad, mode="edge").cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def _backdrop_like(px: np.ndarray, bg: np.ndarray) -> np.ndarray:
    diff = np.abs(px - bg).max(axis=2)
    lum = px.mean(axis=2)
    spread = np.sqrt(np.maximum(_box(lum * lum, WINDOW) - _box(lum, WINDOW) ** 2, 0.0))
    return ((spread < SMOOTH) & (diff < SMOOTH_NEAR)) | (diff < NEAR)


def _flood_from_border(region: Image.Image, value: int, fill: int) -> None:
    w, h = region.size
    edge = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    for xy in edge:
        if region.getpixel(xy) == value:
            ImageDraw.floodfill(region, xy, fill)


def cut(sheet: Image.Image, spec: dict, size: int) -> Image.Image:
    bx0, by0, bx1, by1 = spec["box"]
    x0, y0 = max(bx0 - MARGIN, 0), max(by0 - MARGIN, 0)
    x1, y1 = min(bx1 + MARGIN, sheet.width), min(by1 + MARGIN, sheet.height)
    px = np.asarray(sheet.crop((x0, y0, x1, y1)).convert("RGB")).astype(float)
    border = np.concatenate([px[0], px[-1], px[:, 0], px[:, -1]])
    bg = np.median(border, axis=0)

    def local(box: list) -> tuple:
        ex0, ey0, ex1, ey1 = box
        return slice(max(ey0 - y0, 0), max(ey1 - y0, 0)), slice(max(ex0 - x0, 0), max(ex1 - x0, 0))

    for box in spec.get("erase", []):
        px[local(box)] = bg
    for box in spec.get("flame", []):
        area = px[local(box)]
        # Orange flame, and its white-hot core.
        fire = ((area[..., 0] > 200) & (area[..., 0] - area[..., 2] > 100)) | (area.min(axis=2) > 170)
        area[fire] = bg

    # The object: grained pixels the backdrop's flood from the border does not reach.
    # .copy(): an image made from an array shares its read-only memory, and Pillow's flood
    # fill then silently changes nothing.
    region = Image.fromarray(np.where(_backdrop_like(px, bg), 255, 0).astype(np.uint8)).copy()
    _flood_from_border(region, 255, 128)
    solid = np.asarray(region) != 128
    everything = solid
    h, w = solid.shape
    if not spec.get("keep_all", False):
        parts = Image.fromarray(np.where(solid, 0, 128).astype(np.uint8)).copy()
        seeds = spec.get("seeds") or [[(bx0 + bx1) // 2, (by0 + by1) // 2]]
        for sx, sy in seeds:
            sx, sy = sx - x0, sy - y0
            inside = 0 <= sx < w and 0 <= sy < h
            if inside and parts.getpixel((sx, sy)) == 0:
                ImageDraw.floodfill(parts, (sx, sy), 255)
            elif not inside or parts.getpixel((sx, sy)) == 128:
                print(f"  {spec['id']}: seed {sx + x0},{sy + y0} is on the backdrop")
        solid = np.asarray(parts) == 255

    # Grown by REACH and feathered: the sheet itself near the object, its backdrop beyond -
    # but never over a neighbour, which the growth would otherwise reach into.
    grown = np.asarray(Image.fromarray(np.where(solid, 255, 0).astype(np.uint8)).filter(
        ImageFilter.MaxFilter(2 * REACH + 1))) > 0
    others = np.asarray(Image.fromarray(np.where(everything & ~solid, 255, 0).astype(np.uint8)).filter(
        ImageFilter.MaxFilter(2 * WINDOW + 1))) > 0
    keep = Image.fromarray(np.where(grown & ~others, 255, 0).astype(np.uint8))
    keep = keep.filter(ImageFilter.GaussianBlur(FEATHER))
    alpha = np.asarray(keep).astype(float)[..., None] / 255.0
    out = Image.fromarray((px * alpha + bg * (1.0 - alpha)).clip(0, 255).astype(np.uint8))
    bbox = Image.fromarray(np.where(solid, 255, 0).astype(np.uint8)).getbbox()
    if bbox is None:
        raise SystemExit(f"{spec['id']}: nothing found in the box - check its seeds")
    obj = out.crop(bbox)

    # Square, centred, the object at most 78% of the side - the margin the reference prompts
    # ask for - on the backdrop's own colour, scaled to `size`. The pasted crop carries a
    # little more of the sheet round it, faded into that colour by the feather above.
    side = int(max(obj.width, obj.height) / 0.78)
    grow = int(REACH + 2 * FEATHER)
    wide = out.crop((max(bbox[0] - grow, 0), max(bbox[1] - grow, 0),
                     min(bbox[2] + grow, w), min(bbox[3] + grow, h)))
    canvas = Image.new("RGB", (side, side), tuple(int(c) for c in bg))
    canvas.paste(wide, ((side - obj.width) // 2 - (bbox[0] - max(bbox[0] - grow, 0)),
                        (side - obj.height) // 2 - (bbox[1] - max(bbox[1] - grow, 0))))
    return canvas.resize((size, size), Image.LANCZOS)


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cuts_path = os.path.abspath(sys.argv[1])
    folder = os.path.dirname(cuts_path)
    with open(cuts_path, encoding="utf-8") as handle:
        config = json.load(handle)
    sheet = Image.open(os.path.join(folder, config["sheet"]))
    out = os.path.join(folder, config.get("out", "."))
    os.makedirs(out, exist_ok=True)
    wanted = set(sys.argv[2:])
    for spec in config["cuts"]:
        if wanted and spec["id"] not in wanted:
            continue
        image = cut(sheet, spec, int(config.get("size", 1024)))
        path = os.path.join(out, spec["id"] + ".png")
        image.save(path)
        with open(path, "rb") as handle:
            digest = hashlib.sha256(handle.read()).hexdigest()
        print(f"{spec['id']}: {os.path.relpath(path)} {digest}")


if __name__ == "__main__":
    main()
