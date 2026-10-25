"""Meshes a biome's props from references cut out of an asset sheet (tools/cut_sheet_references.py).

usage: python tools/mesh_biome_props.py <folder> [--go] [id ...]
       python tools/mesh_biome_props.py <folder> --approve id [id ...]

<folder> holds the references (<id>.png) and props.json - per prop its target triangles,
its height in game and the SHA-256 of the reference the user approved, e.g.
docs/screen_art/source/biome_black. Same request as the towers and the creatures
(meshy_request in tools/nature/nature_pipeline.py): image-to-3D on Smart Topology
(meshy-t2), 2k PBR, about 15 credits each, GLB only - props stand still. Writes
assets/generated/<prefix>-<id>/ with the .glb, a preview and the provenance .meshy.json.

PAID: without --go it only prints the requests. Refuses a reference that is not approved,
or that changed since. --approve records the current file's hash: only on the user's word,
naming the prop. Resumable: a submitted task is kept in <name>.task.json.

    $env:MESHY_API_KEY = [Environment]::GetEnvironmentVariable('Meshy API Key','User')
"""
import base64
import hashlib
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "nature"))
import nature_pipeline as pipeline  # noqa: E402


def _sha(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def mesh(manifest, folder, table, prop_id, go, key):
    spec = table["props"][prop_id]
    reference = os.path.join(folder, prop_id + ".png")
    if not spec.get("approved"):
        print(f"{prop_id}: not approved - skipped")
        return
    if _sha(reference) != spec["approved"]:
        print(f"{prop_id}: {prop_id}.png changed since it was approved - skipped")
        return
    name = f"{table['prefix']}-{prop_id}"
    out = os.path.join(ROOT, "assets", "generated", name)
    stem = os.path.join(out, name)
    if os.path.exists(stem + ".glb"):
        print(f"{prop_id}: glb exists, skipped")
        return
    with open(reference, "rb") as handle:
        image_b64 = base64.b64encode(handle.read()).decode("ascii")
    request = pipeline.meshy_request(manifest, {"id": name, "tris": spec["tris"], "model_type": "smart-topology"}, image_b64)
    if not go:
        print(prop_id, json.dumps({k: v for k, v in request.items() if k != "image_url"}))
        return
    os.makedirs(out, exist_ok=True)
    config = manifest["providers"]["meshy"]
    headers = {"Authorization": f"Bearer {key}"}
    task_file = stem + ".task.json"
    if os.path.exists(task_file):
        with open(task_file, encoding="utf-8") as handle:
            task_id = json.load(handle)["task_id"]
        print(f"{prop_id}: resuming {task_id}")
    else:
        try:
            task_id = pipeline.http_json("POST", config["endpoint"], headers, request)["result"]
        except RuntimeError as error:
            # A rejected request creates no task and costs nothing.
            print(f"{prop_id}: rejected - {error}")
            return
        with open(task_file, "w", encoding="utf-8") as handle:
            json.dump({"task_id": task_id}, handle)
        print(f"{prop_id}: submitted {task_id}")
    task = pipeline.wait_meshy(config, headers, task_id)
    if task is None:
        return
    pipeline.download(task["model_urls"]["glb"], stem + ".glb")
    if task.get("thumbnail_url"):
        pipeline.download(task["thumbnail_url"], stem + "_preview.png")
    with open(stem + ".meshy.json", "w", encoding="utf-8") as handle:
        json.dump({
            "generator": "Meshy Image to 3D API v1",
            "task_id": task_id,
            "status": task.get("status"),
            "consumed_credits": task.get("consumed_credits"),
            "request": {k: v for k, v in request.items() if k != "image_url"},
            "concept_image": os.path.relpath(reference, ROOT).replace("\\", "/"),
            "height_m": spec["height_m"],
            "license_review_required": True,
        }, handle, indent=2)
    os.remove(task_file)
    print(f"{prop_id}: saved {os.path.relpath(stem + '.glb', ROOT)}, {task.get('consumed_credits')} credits")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    folder = os.path.abspath(sys.argv[1])
    table_path = os.path.join(folder, "props.json")
    with open(table_path, encoding="utf-8") as handle:
        table = json.load(handle)
    args = sys.argv[2:]
    names = [a for a in args if a in table["props"]]
    unknown = [a for a in args if not a.startswith("--") and a not in table["props"]]
    if unknown:
        sys.exit("Unknown props: " + ", ".join(unknown) + "\nKnown: " + ", ".join(table["props"]))
    if "--approve" in args:
        if not names:
            sys.exit("Name the props the user approved.")
        for prop_id in names:
            table["props"][prop_id]["approved"] = _sha(os.path.join(folder, prop_id + ".png"))
            print(f"{prop_id}: approved {table['props'][prop_id]['approved']}")
        with open(table_path, "w", encoding="utf-8") as handle:
            json.dump(table, handle, indent=2)
            handle.write("\n")
        return
    go = "--go" in args
    if go and not names:
        sys.exit("Name what to mesh: " + ", ".join(table["props"]))
    manifest = pipeline.load_manifest()
    key = pipeline.require_key("MESHY_API_KEY") if go else ""
    for prop_id in names or list(table["props"]):
        mesh(manifest, folder, table, prop_id, go, key)


if __name__ == "__main__":
    main()
