extends Node
## Screenshot: the minimap under the fog of war on the real map, after the local player has
## walked out along two lanes and come part of the way back.
##
## Run with (windowed - a headless run renders nothing):
##   godot --path . --resolution 1600x900 res://tools/tests/fog_of_war_shot.tscn -- C:/out.png

var _started: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	GameSettings.intro_tour_pending = false
	var probe: Node = load("res://tools/tests/fog_of_war_shot.gd").new()
	probe.name = "FogOfWarShot"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	var scene: Node = get_tree().current_scene
	if scene == null or scene.get_node_or_null("WaveManager") == null or PlayerRegistry.get_local() == null:
		return
	_started = true
	await _walk(scene)
	get_tree().quit()


func _walk(main: Node) -> void:
	var player: Node3D = PlayerRegistry.get_local() as Node3D
	var crystal: Vector3 = main.crystal_anchor.global_position
	# Out along Green (index 4) and Blue (index 1), and part of the way home.
	var route: Array[Vector3] = []
	for lane: int in [4, 1]:
		var dir: Vector3 = main._lane_outward(lane)
		for distance: float in [40.0, 80.0, 120.0, 150.0]:
			route.append(crystal + dir * distance)
		route.append(crystal + dir * 70.0)
	for point: Vector3 in route:
		player.global_position = _ground(main, point) + Vector3.UP * 1.0
		for i: int in 40:
			await get_tree().physics_frame
	for i: int in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://fog_of_war.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("SAVED %s" % out)


func _ground(main: Node, at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 200.0, at + Vector3.DOWN * 200.0, EnemyBase.ENVIRONMENT_LAYER)
	var hit: Dictionary = (main as Node3D).get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else at
