extends Node
## Measures how every tree TerraBrush placed on the map meets the ground: for each placed
## wrapper scene (assets/nature/scenes/*), the lowest ring of its bark is taken off the mesh,
## put where the tree stands, and each vertex compared with the ground straight under it.
##
##   min gap > 0   nothing of the trunk reaches the ground - the tree floats
##   max gap       how far the downhill side of the foot hangs in the air
##
## The ground is measured twice: TerraBrush's collision (a raycast), and the heightmap with
## the water's depression taken off (height - water * waterFactor), which is what the
## terrain shader draws. Where they disagree the tree stands in water.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . res://tools/tests/tree_grounding.tscn -- [out.json]

const FLOAT_LIMIT_M := 0.1
## How much of the bark, from its lowest vertex up, counts as the foot.
const FOOT_BAND_M := 0.35

var _frames: int = 0
var _done: bool = false
var _feet: Dictionary = {}  # mesh -> PackedVector3Array of local foot vertices


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/tree_grounding.gd").new()
	probe.name = "TreeGrounding"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _physics_process(_delta: float) -> void:
	if _done or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 240:
		return
	_done = true
	var scene: Node3D = get_tree().current_scene as Node3D
	var terra: Node = scene.get_node("TerraBrush")
	var terrain: StaticBody3D = scene.call("_find_collision_body", terra)
	var height := (load("res://scenes/misc/Main/Heightmap_0_0.res") as Image)
	var water := (load("res://scenes/misc/Main/Water_0_0.res") as Image)
	var water_factor: float = 3.0
	var water_resource: Variant = terra.get("waterDefinition")
	if water_resource is Resource:
		water_factor = float((water_resource as Resource).get("waterFactor"))

	var trees: Array = []
	_collect(terra, trees)
	var space := scene.get_world_3d().direct_space_state
	var per_asset: Dictionary = {}
	var rows: Array = []
	for tree: Node3D in trees:
		var mesh_node := tree.get_node_or_null("Mesh") as MeshInstance3D
		if mesh_node == null:
			continue
		var feet := _foot(mesh_node.mesh)
		if feet.is_empty():
			continue
		var min_ray := INF
		var max_ray := -INF
		var min_drawn := INF
		var max_drawn := -INF
		var wet := 0.0
		for local: Vector3 in feet:
			var world: Vector3 = mesh_node.global_transform * local
			var ground := _ray_ground(space, terrain, world)
			var drawn := _drawn_ground(height, water, water_factor, world)
			wet = maxf(wet, _sample(water, world))
			min_ray = minf(min_ray, world.y - ground)
			max_ray = maxf(max_ray, world.y - ground)
			min_drawn = minf(min_drawn, world.y - drawn)
			max_drawn = maxf(max_drawn, world.y - drawn)
		var id := tree.scene_file_path.get_file().get_basename()
		var base := id.split("_v")[0]
		var row := {
			"id": id, "pos": [snappedf(tree.global_position.x, 0.1), snappedf(tree.global_position.y, 0.01), snappedf(tree.global_position.z, 0.1)],
			"scale": snappedf(tree.global_transform.basis.get_scale().y, 0.01),
			"min_gap_ray": snappedf(min_ray, 0.01), "max_gap_ray": snappedf(max_ray, 0.01),
			"min_gap_drawn": snappedf(min_drawn, 0.01), "max_gap_drawn": snappedf(max_drawn, 0.01),
			"water": snappedf(wet, 0.01),
		}
		rows.append(row)
		if not per_asset.has(base):
			per_asset[base] = {"count": 0, "floating_ray": 0, "floating_drawn": 0, "worst_drawn": -INF, "wet": 0}
		var stats: Dictionary = per_asset[base]
		stats["count"] += 1
		if min_ray > FLOAT_LIMIT_M:
			stats["floating_ray"] += 1
		if min_drawn > FLOAT_LIMIT_M:
			stats["floating_drawn"] += 1
		if wet > 0.01:
			stats["wet"] += 1
		stats["worst_drawn"] = maxf(stats["worst_drawn"], min_drawn)

	for base: String in per_asset:
		var stats: Dictionary = per_asset[base]
		print("GROUNDING %-40s %4d placed, %3d float (ray), %3d float (drawn), %3d in water, worst %.2f m" % [
			base, stats["count"], stats["floating_ray"], stats["floating_drawn"], stats["wet"], stats["worst_drawn"]])
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		FileAccess.open(args[0], FileAccess.WRITE).store_string(JSON.stringify(rows, "  "))
		print("GROUNDING wrote %d trees to %s" % [rows.size(), args[0]])
	get_tree().quit()


func _collect(node: Node, out: Array) -> void:
	for child in node.get_children(true):
		if child is Node3D and (child as Node3D).scene_file_path.begins_with("res://assets/nature/scenes/"):
			out.append(child)
			continue
		_collect(child, out)


## The lowest band of the bark - the trunk's foot, or a mangrove's root tips.
func _foot(mesh: Mesh) -> PackedVector3Array:
	if _feet.has(mesh):
		return _feet[mesh]
	var bark := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if material == null or not material.resource_name.ends_with("_bark"):
			continue
		bark.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	var feet := PackedVector3Array()
	if not bark.is_empty():
		var lowest := INF
		for vertex in bark:
			lowest = minf(lowest, vertex.y)
		for vertex in bark:
			if vertex.y <= lowest + FOOT_BAND_M:
				feet.append(vertex)
	_feet[mesh] = feet
	return feet


func _ray_ground(space: PhysicsDirectSpaceState3D, terrain: StaticBody3D, at: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at + Vector3.DOWN * 60.0)
	var excluded: Array[RID] = []
	for attempt in 8:
		query.exclude = excluded
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return at.y
		if hit["collider"] == terrain:
			return (hit["position"] as Vector3).y
		excluded.append(hit["rid"])
	return at.y


func _sample(image: Image, at: Vector3) -> float:
	var px := at.x + 256.0
	var pz := at.z + 256.0
	var x0 := clampi(floori(px), 0, image.get_width() - 2)
	var z0 := clampi(floori(pz), 0, image.get_height() - 2)
	var fx := clampf(px - x0, 0.0, 1.0)
	var fz := clampf(pz - z0, 0.0, 1.0)
	var top := lerpf(image.get_pixel(x0, z0).r, image.get_pixel(x0 + 1, z0).r, fx)
	var bottom := lerpf(image.get_pixel(x0, z0 + 1).r, image.get_pixel(x0 + 1, z0 + 1).r, fx)
	return lerpf(top, bottom, fz)


func _drawn_ground(height: Image, water: Image, water_factor: float, at: Vector3) -> float:
	return _sample(height, at) - _sample(water, at) * water_factor
