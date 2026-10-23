"""Meshes the Curse of the Swine boar and the Awaken golem from their approved Gemini
references (docs/screen_art/source/creature_references.md).

usage: python tools/mesh_creatures.py [--go] [boar|stone_golem ...]

Same request as the nature set and the goblin caves (meshy_request in
tools/nature/nature_pipeline.py): image-to-3D on Smart Topology (meshy-t2), 2k PBR,
about 15 credits each. Writes <name>.glb/.fbx, a preview and the provenance .meshy.json
to assets/generated/<name>/.

PAID: without --go it only prints the requests. Refuses a reference whose SHA-256 is not
the one the user approved. Resumable: a submitted task is kept in <name>.task.json.

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

SOURCE = os.path.join(ROOT, "docs", "screen_art", "source")

## name: reference, approved SHA-256, target triangles, extra request fields.
CREATURES = {
    # Several can be on the field at once (the curse hits a group), so it stays lean.
    "boar": ("boar_reference.png", "c98b46337f05c6f9cc6e95f1c7a4b3f67f10511876443ef8287a4e2eb97c39a1",
             6000, {}),
    # One at a time and close to the player; Mixamo wants the arms away from the body.
    "stone_golem": ("stone_golem_reference.png", "5438fc00df1187e857f2269d791683acb8f771d6e55a80d8e6338bdc9e25e807",
                    10000, {"pose_mode": "a-pose"}),
}


def mesh(manifest, name, go, key):
    file, approved, tris, extra = CREATURES[name]
    reference = os.path.join(SOURCE, file)
    with open(reference, "rb") as handle:
        data = handle.read()
    if hashlib.sha256(data).hexdigest() != approved:
        print(f"{name}: {file} changed since it was approved - skipped")
        return
    folder = os.path.join(ROOT, "assets", "generated", name)
    stem = os.path.join(folder, name)
    if os.path.exists(stem + ".glb"):
        print(f"{name}: glb exists, skipped")
        return
    request = pipeline.meshy_request(manifest, {"id": name, "tris": tris, "model_type": "smart-topology"},
                                     base64.b64encode(data).decode("ascii"))
    request.update(extra)
    # The FBX is what Mixamo takes; the Blender beast rig imports it too.
    request["target_formats"] = ["glb", "fbx"]
    if not go:
        print(name, json.dumps({k: v for k, v in request.items() if k != "image_url"}))
        return
    os.makedirs(folder, exist_ok=True)
    config = manifest["providers"]["meshy"]
    headers = {"Authorization": f"Bearer {key}"}
    task_file = stem + ".task.json"
    if os.path.exists(task_file):
        with open(task_file, encoding="utf-8") as handle:
            task_id = json.load(handle)["task_id"]
        print(f"{name}: resuming {task_id}")
    else:
        try:
            task_id = pipeline.http_json("POST", config["endpoint"], headers, request)["result"]
        except RuntimeError as error:
            # A rejected request creates no task and costs nothing.
            print(f"{name}: rejected - {error}")
            return
        with open(task_file, "w", encoding="utf-8") as handle:
            json.dump({"task_id": task_id}, handle)
        print(f"{name}: submitted {task_id}")
    task = pipeline.wait_meshy(config, headers, task_id)
    if task is None:
        return
    for fmt in ("glb", "fbx"):
        if task["model_urls"].get(fmt):
            pipeline.download(task["model_urls"][fmt], f"{stem}.{fmt}")
    if task.get("thumbnail_url"):
        pipeline.download(task["thumbnail_url"], stem + "_preview.png")
    with open(stem + ".meshy.json", "w", encoding="utf-8") as handle:
        json.dump({
            "generator": "Meshy Image to 3D API v1",
            "task_id": task_id,
            "status": task.get("status"),
            "consumed_credits": task.get("consumed_credits"),
            "request": {k: v for k, v in request.items() if k != "image_url"},
            "concept_image": f"docs/screen_art/source/{file}",
            "concept_prompt": "docs/screen_art/source/creature_references.md (Gemini 3 Pro Image)",
            "license_review_required": True,
        }, handle, indent=2)
    os.remove(task_file)
    print(f"{name}: saved {os.path.relpath(stem + '.glb', ROOT)}, {task.get('consumed_credits')} credits")


def main():
    go = "--go" in sys.argv
    names = [a for a in sys.argv[1:] if a in CREATURES] or list(CREATURES)
    manifest = pipeline.load_manifest()
    key = pipeline.require_key("MESHY_API_KEY") if go else ""
    for name in names:
        mesh(manifest, name, go, key)


if __name__ == "__main__":
    main()
