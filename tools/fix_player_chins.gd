extends SceneTree
## (Re-)applies the skin weight fixes (tools/skin_weight_fix.gd, apply_class_fixes: the chin,
## and a class's rigid_head, even_plates and mitten fingers) to a player class's saved visual,
## with that class's settings from PlayerCharacterBuilder.CONFIGS - the knob for tuning them by
## hand, without a rebuild.
##
## Run with (no class = every class):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/fix_player_chins.gd -- warrior
##
## Every run starts from the ORIGINAL weights: the class's source fbx (its config's "mesh")
## is loaded fresh, re-weighted, and its weights put into the saved scene in place of
## whatever is there now. So runs never stack, and "strength": 0.0 restores Mixamo's own
## weighting exactly. The fbx and the scene are checked to hold the same vertices in the same
## order first - the weights are written by position in the vertex list.
##
## The scene FILE is patched, not re-saved: only the skin weights of the body mesh (and its
## shadow mesh) are swapped, and the mesh is marked. Packing the instanced scene and saving
## it instead dropped the warrior's axe material, which the builder had written as an
## override on the axe instance.
##
## If the Godot editor has the scene open, reload it there afterwards (or close it first):
## an editor holding the old copy can save it back over the patch.

const Builder = preload("res://tools/player_character_builder.gd")
const SkinWeightFix = preload("res://tools/skin_weight_fix.gd")


func _init() -> void:
	var wanted: PackedStringArray = OS.get_cmdline_user_args()
	for class_id: String in Builder.CONFIGS:
		if not wanted.is_empty() and not wanted.has(class_id):
			continue
		var config: Dictionary = Builder.CONFIGS[class_id]
		if ResourceLoader.exists(config["scene"]):
			_patch(class_id, config)
	quit()


func _patch(class_id: String, config: Dictionary) -> void:
	var path: String = config["scene"]
	var visual: Node = (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene).instantiate()
	var source: Node = (ResourceLoader.load(String(config["mesh"]), "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene).instantiate()
	var saved_node: MeshInstance3D = _skinned_mesh(visual)
	var source_node: MeshInstance3D = _skinned_mesh(source)
	var skeleton: Skeleton3D = source.find_child("Skeleton3D", true, false)
	if saved_node == null or source_node == null or skeleton == null:
		push_error("%s: no skinned mesh in %s or %s" % [class_id, path, config["mesh"]])
		_free(visual, source)
		return

	# A class whose builder smooths the mesh (the barbarian) is compared with the fbx smoothed
	# the same way - the saved scene holds that mesh, not the fbx's own.
	if config.get("smooth_normals", false):
		Builder.smooth_normals(source_node)
	var saved: Array[ArrayMesh] = _with_shadow(saved_node.mesh as ArrayMesh)
	var original: Array[ArrayMesh] = _with_shadow(source_node.mesh as ArrayMesh)
	if saved.size() != original.size():
		push_error("%s: the scene and the fbx disagree on the shadow mesh" % class_id)
		_free(visual, source)
		return
	for i in saved.size():
		if not _same_vertices(saved[i], original[i]):
			push_error("%s: the saved mesh is not the fbx's vertex for vertex - rebuild the class instead" % class_id)
			_free(visual, source)
			return

	var current: Array[PackedStringArray] = []
	for mesh: ArrayMesh in saved:
		current.append(_skin_strings(mesh))
	# Every fix the builder applies, not just the chin, or this would undo the others.
	SkinWeightFix.apply_class_fixes(source_node, skeleton, config)

	var text: String = FileAccess.get_file_as_string(path)
	for i in saved.size():
		var fixed: PackedStringArray = _skin_strings(original[i])
		for s in fixed.size():
			if current[i][s] == fixed[s] or current[i][s] == "":
				continue
			var at: int = text.find(current[i][s])
			if at == -1:
				push_error("%s: could not find the skin data in %s" % [class_id, path])
				_free(visual, source)
				return
			text = text.substr(0, at) + fixed[s] + text.substr(at + current[i][s].length())
			# Marked where the mesh's own block ends - the first blank line after its data -
			# unless it already is.
			var block_end: int = text.find("\n\n", at)
			var mark: String = "metadata/%s = true" % SkinWeightFix.MARK
			if text.substr(at, block_end - at).find(mark) == -1:
				text = text.substr(0, block_end) + "\n" + mark + text.substr(block_end)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	print("%s: re-weighted from the original, with chin %s" % [class_id, config.get("chin", {})])
	_free(visual, source)


static func _skinned_mesh(root: Node) -> MeshInstance3D:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).skin != null and (node as MeshInstance3D).mesh is ArrayMesh:
			return node as MeshInstance3D
	return null


static func _with_shadow(mesh: ArrayMesh) -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = [mesh]
	if mesh.shadow_mesh is ArrayMesh:
		out.append(mesh.shadow_mesh as ArrayMesh)
	return out


static func _same_vertices(a: ArrayMesh, b: ArrayMesh) -> bool:
	var sa: Array = a.get("_surfaces")
	var sb: Array = b.get("_surfaces")
	if sa.size() != sb.size():
		return false
	for i in sa.size():
		if (sa[i] as Dictionary).get("vertex_data") != (sb[i] as Dictionary).get("vertex_data"):
			return false
		if (sa[i] as Dictionary).get("skin_data", PackedByteArray()).size() != (sb[i] as Dictionary).get("skin_data", PackedByteArray()).size():
			return false
	return true


## Each surface's skin data, base64 - how a format-4 scene file writes a PackedByteArray.
static func _skin_strings(mesh: ArrayMesh) -> PackedStringArray:
	var out := PackedStringArray()
	for surface: Dictionary in mesh.get("_surfaces"):
		var data: PackedByteArray = surface.get("skin_data", PackedByteArray())
		out.append(Marshalls.raw_to_base64(data) if not data.is_empty() else "")
	return out


static func _free(a: Node, b: Node) -> void:
	a.free()
	b.free()
