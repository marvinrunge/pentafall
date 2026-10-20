extends RefCounted
## Smooth shading for meshes that were exported faceted. Preloaded by path, never by
## class_name (a headless build run does not rescan for new global classes).
##
## Meshy hands out some models flat-shaded - every face with a normal of its own - and they
## light like low-poly however fine the mesh: the Scarred Warchief had split normals at 80% of
## its vertex positions, several enemy mages and archers at 30-70%, the enemy weapons at
## nearly all of them. This is Blender's "auto smooth": faces that meet along an edge at less
## than `max_angle` degrees are shaded as one smooth surface, and only the sharper edges stay
## hard - curved surfaces go smooth, a blade's edge or a box's corner stays a crease.
##
## Faces are weighted by area. Corners that come out identical are merged again, tangents are
## made fresh for the normal map, and the LODs are generated anew. Skin (bone indices and
## weights), UVs and colours ride along. Deterministic: the same mesh in gives the same mesh
## out, which tools/fix_player_chins.gd relies on to compare a saved mesh with its source.
##
## Used by the player builder (CONFIGS[<class>]["smooth_normals"]), by the import script
## tools/import/smooth_normals_post_import.gd on faceted source models, and by
## tools/smooth_scene_meshes.gd on the copies already saved inside character scenes.

## Without an angle of its own: a skinned mesh - a character - is smoothed all over, as Meshy's
## own "smooth" export would have it (the enemies are low-poly enough that a fifth of their
## edges meet at 60-90 degrees, and an angle limit left them half faceted); a rigid one - a
## weapon, a prop - keeps every edge sharper than RIGID_ANGLE, so a blade keeps its edge.
const SKINNED_ANGLE := 180.0
const RIGID_ANGLE := 60.0
## A position counts as split when its normals disagree by more than this.
const SPLIT_DEGREES := 5.0


## `mesh` with smoothed normals, as a new ArrayMesh. A mesh with blend shapes is returned as is.
## A negative `max_angle` picks SKINNED_ANGLE or RIGID_ANGLE per surface.
static func smooth(mesh: ArrayMesh, max_angle: float = -1.0) -> ArrayMesh:
	if mesh.get_blend_shape_count() > 0:
		push_warning("NormalSmoother: %s has blend shapes; left as it is" % mesh.resource_name)
		return mesh
	var importer := ImporterMesh.new()
	for surface in mesh.get_surface_count():
		var eight: bool = mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS != 0
		var arrays: Array = mesh.surface_get_arrays(surface)
		if mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
			var angle: float = max_angle
			if angle < 0.0:
				angle = SKINNED_ANGLE if arrays[Mesh.ARRAY_BONES] != null else RIGID_ANGLE
			arrays = _smooth_arrays(arrays, angle, eight)
		importer.add_surface(mesh.surface_get_primitive_type(surface), arrays, [], {},
			mesh.surface_get_material(surface), mesh.surface_get_name(surface),
			Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if eight else 0)
	importer.generate_lods(25.0, 60.0, [])
	var out: ArrayMesh = importer.get_mesh()
	out.resource_name = mesh.resource_name
	return out


## The share (0 to 1) of `mesh`'s vertex positions whose normals disagree - near 1 for a
## faceted mesh, a few percent for a smooth one with its UV seams and real creases.
static func split_share(mesh: ArrayMesh) -> float:
	var positions: int = 0
	var split: int = 0
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if arrays[Mesh.ARRAY_NORMAL] == null:
			continue
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var keys: Array = _position_keys(verts)
		var first: Dictionary = {}
		var disagree: Dictionary = {}
		for i in verts.size():
			var key: Vector3i = keys[i]
			if not first.has(key):
				first[key] = normals[i]
			elif (first[key] as Vector3).angle_to(normals[i]) > deg_to_rad(SPLIT_DEGREES):
				disagree[key] = true
		positions += first.size()
		split += disagree.size()
	return float(split) / float(maxi(positions, 1))


static func _smooth_arrays(arrays: Array, max_angle: float, eight: bool) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(verts.size())
		for i in verts.size():
			indices[i] = i
	var old_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var keys: Array = _position_keys(verts)

	# Face normals, area-weighted, turned to agree with the normals the mesh came with so the
	# winding convention never matters; and every corner's position as a small integer.
	var tri_count: int = indices.size() / 3
	var face := PackedVector3Array()
	face.resize(tri_count)
	var unit := PackedVector3Array()
	unit.resize(tri_count)
	var position_ids: Dictionary = {}
	var corner_position := PackedInt32Array()
	corner_position.resize(indices.size())
	for t in tri_count:
		var a: int = indices[t * 3]
		var b: int = indices[t * 3 + 1]
		var c: int = indices[t * 3 + 2]
		var n: Vector3 = (verts[b] - verts[a]).cross(verts[c] - verts[a])
		if not old_normals.is_empty() and n.dot(old_normals[a] + old_normals[b] + old_normals[c]) < 0.0:
			n = -n
		face[t] = n
		unit[t] = n.normalized() if n.length_squared() > 0.0 else Vector3.ZERO
		for corner in 3:
			var key: Vector3i = keys[indices[t * 3 + corner]]
			if not position_ids.has(key):
				position_ids[key] = position_ids.size()
			corner_position[t * 3 + corner] = position_ids[key]

	# Blender's auto smooth: two faces that share an edge and meet at less than `max_angle`
	# join their corners at both ends of it into one smoothing fan. A fan is smooth inside and
	# stops at every sharper edge - a crease stays a crease, and every corner of one fan gets
	# the very same normal.
	var cos_limit: float = cos(deg_to_rad(max_angle))
	# An Array, not a PackedInt32Array: _find() and _join() write into it, and only an Array is
	# shared with the function it is passed to.
	var fan: Array = []
	fan.resize(indices.size())
	for c in indices.size():
		fan[c] = c
	var edges: Dictionary = {}
	for t in tri_count:
		for e in 3:
			var c0: int = t * 3 + e
			var c1: int = t * 3 + (e + 1) % 3
			var p0: int = corner_position[c0]
			var p1: int = corner_position[c1]
			if p0 == p1:
				continue
			var edge := Vector2i(mini(p0, p1), maxi(p0, p1))
			if not edges.has(edge):
				edges[edge] = PackedInt32Array()
			var list: PackedInt32Array = edges[edge]
			for other_t: int in list:
				if unit[t].dot(unit[other_t]) < cos_limit:
					continue
				for oc in 3:
					var other_corner: int = other_t * 3 + oc
					if corner_position[other_corner] == p0:
						_join(fan, c0, other_corner)
					elif corner_position[other_corner] == p1:
						_join(fan, c1, other_corner)
			list.append(t)
			edges[edge] = list
	var fan_sum: Dictionary = {}
	for c in indices.size():
		var root: int = _find(fan, c)
		fan_sum[root] = (fan_sum.get(root, Vector3.ZERO) as Vector3) + face[c / 3]

	# One vertex per corner, carrying its fan's normal; SurfaceTool merges them back.
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	var normals := PackedVector3Array()
	normals.resize(indices.size())
	for c in indices.size():
		var sum: Vector3 = fan_sum[_find(fan, c)]
		normals[c] = sum.normalized() if sum.length_squared() > 0.0 else unit[c / 3]
	out[Mesh.ARRAY_VERTEX] = _gather(arrays[Mesh.ARRAY_VERTEX], indices, 1)
	out[Mesh.ARRAY_NORMAL] = normals
	for slot in [Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arrays[slot] != null:
			out[slot] = _gather(arrays[slot], indices, 1)
	var per_vertex: int = 8 if eight else 4
	for slot in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		if arrays[slot] != null:
			out[slot] = _gather(arrays[slot], indices, per_vertex)

	var tool := SurfaceTool.new()
	tool.create_from_arrays(out, Mesh.PRIMITIVE_TRIANGLES)
	tool.set_skin_weight_count(SurfaceTool.SKIN_8_WEIGHTS if eight else SurfaceTool.SKIN_4_WEIGHTS)
	tool.index()
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		tool.generate_tangents()
	return tool.commit_to_arrays()


## The values of a per-vertex array for each corner in `indices`, `stride` values a vertex.
static func _gather(source: Variant, indices: PackedInt32Array, stride: int) -> Variant:
	var out: Variant = source.duplicate()
	out.resize(indices.size() * stride)
	for c in indices.size():
		for k in stride:
			out[c * stride + k] = source[indices[c] * stride + k]
	return out


## Union-find over corners, for the smoothing fans.
static func _find(parents: Array, c: int) -> int:
	var root: int = c
	while parents[root] != root:
		root = parents[root]
	while parents[c] != root:
		var next: int = parents[c]
		parents[c] = root
		c = next
	return root


static func _join(parents: Array, a: int, b: int) -> void:
	var ra: int = _find(parents, a)
	var rb: int = _find(parents, b)
	if ra != rb:
		parents[maxi(ra, rb)] = mini(ra, rb)


## A key per vertex that is the same for vertices at the same place, at a precision relative
## to the mesh's size - the rigs here run from centimetre to metre scale.
static func _position_keys(verts: PackedVector3Array) -> Array:
	var box := AABB()
	for i in verts.size():
		box = AABB(verts[i], Vector3.ZERO) if i == 0 else box.expand(verts[i])
	var step: float = maxf(box.size.length(), 0.000001) / 200000.0
	var keys: Array = []
	keys.resize(verts.size())
	for i in verts.size():
		keys[i] = Vector3i(((verts[i] - box.position) / step).round())
	return keys
