extends SceneTree
## Smooths the faceted meshes saved INSIDE character scenes - the enemies', the bosses', the
## player's axe - which the character builders copied out of their models when they were
## built, so a smooth import (tools/import/smooth_normals_post_import.gd) no longer reaches
## them.
##
## Run with (no scenes = every .tscn under res://scenes):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/smooth_scene_meshes.gd -- res://scenes/mage/elf_mage.tscn
##
## Every mesh built into a scene whose normals are split at more than SPLIT_LIMIT of its
## positions is smoothed (tools/normal_smoother.gd) and marked; a marked mesh is skipped, so
## runs never stack. The scene FILE is patched rather than re-saved, for the reason
## tools/fix_player_chins.gd gives: only the mesh's `_surfaces` are swapped, and each surface
## keeps the material reference it had. Everything else in the file stays byte for byte.
##
## If the Godot editor has a scene open, reload it there afterwards - an editor holding the
## old copy can save it back over the patch.

const NormalSmoother = preload("res://tools/normal_smoother.gd")
const SPLIT_LIMIT := 0.15
const MARK := "metadata/normals_smoothed = true"
const TEMP := "user://smooth_scene_mesh.tres"


func _init() -> void:
	var scenes: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		scenes.append(arg)
	if scenes.is_empty():
		_collect("res://scenes", scenes)
	for path in scenes:
		_patch(path)
	quit()


func _patch(path: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if not text.begins_with("[gd_scene format=4"):
		return
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed == null:
		return
	var root: Node = packed.instantiate()
	var done: Dictionary = {}
	var changed: bool = false
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh as ArrayMesh
		if mesh == null or not mesh.resource_path.begins_with(path + "::"):
			continue
		var id: String = mesh.resource_path.get_slice("::", 1)
		if done.has(id):
			continue
		done[id] = true
		var block_at: int = text.find('[sub_resource type="ArrayMesh" id="%s"]' % id)
		if block_at == -1:
			continue
		var block_end: int = text.find("\n\n", block_at)
		if text.substr(block_at, block_end - block_at).contains(MARK):
			continue
		var share: float = NormalSmoother.split_share(mesh)
		if share <= SPLIT_LIMIT:
			continue
		var smoothed: ArrayMesh = NormalSmoother.smooth(mesh)
		var patched: String = _swap_surfaces(text, block_at, mesh, smoothed)
		if patched == "":
			push_error("%s: could not patch %s" % [path, id])
			continue
		text = patched
		changed = true
		print("%s: %s %s split %.0f%% -> %.0f%%" % [path, node.name, id, share * 100.0, NormalSmoother.split_share(smoothed) * 100.0])
	root.free()
	if changed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()


## `text` with the `_surfaces` of the ArrayMesh block at `block_at` replaced by `smoothed`'s,
## each surface keeping the material reference the old one had. "" if the block is not laid
## out as expected.
func _swap_surfaces(text: String, block_at: int, original: ArrayMesh, smoothed: ArrayMesh) -> String:
	var start: int = text.find("_surfaces = [", block_at)
	var end: int = text.find("\n}]", start)
	var next_block: int = text.find("\n[", block_at + 1)
	if start == -1 or end == -1 or (next_block != -1 and end > next_block):
		return ""
	end += 3
	var old_surfaces: String = text.substr(start, end - start)
	var materials: Array[String] = []
	var regex := RegEx.create_from_string('"material": [A-Za-z]+Resource\\("[^"]*"\\),')
	for found: RegExMatch in regex.search_all(old_surfaces):
		materials.append(found.get_string())
	# Saved without materials, so the new text holds no references of its own; the scene's
	# own references go back in, surface by surface, in front of each "name".
	var copy: ArrayMesh = smoothed.duplicate() as ArrayMesh
	for surface in copy.get_surface_count():
		copy.surface_set_material(surface, null)
	if ResourceSaver.save(copy, TEMP) != OK:
		return ""
	var saved: String = FileAccess.get_file_as_string(TEMP)
	var new_start: int = saved.find("_surfaces = [")
	var new_end: int = saved.find("\n}]", new_start)
	if new_start == -1 or new_end == -1:
		return ""
	var new_surfaces: String = saved.substr(new_start, new_end + 3 - new_start)
	if materials.size() == original.get_surface_count():
		var at: int = 0
		for material: String in materials:
			at = new_surfaces.find('\n"name": ', at)
			if at == -1:
				return ""
			new_surfaces = new_surfaces.insert(at + 1, material + "\n")
			at += material.length() + 2
	var patched: String = text.substr(0, start) + new_surfaces + text.substr(end)
	var block_end: int = patched.find("\n\n", block_at)
	return patched.insert(block_end, "\n" + MARK)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f in dir.get_files():
		if f.get_extension() == "tscn":
			out.append(dir_path.path_join(f))
