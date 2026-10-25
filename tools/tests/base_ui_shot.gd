extends Node
## Screenshots the base screen with a run's worth of myrs in it - named workers on several
## lanes, both guards, and the Graveyard - so its layout can be judged rather than only asserted.
##
## Run with (windowed - a headless run draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . res://tools/tests/base_ui_shot.tscn -- <out.png>

var _started: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	GameSettings.intro_tour_pending = false
	GameSettings.wave_initial_warning_time = 3600.0
	var shooter: Node = load("res://tools/tests/base_ui_shot.gd").new()
	shooter.name = "BaseUiShooter"
	shooter.set_meta("armed", true)
	get_tree().root.add_child(shooter)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	var main: Node = get_tree().current_scene
	if main == null or not main.has_method("myr_count") or main.get_node_or_null("WaveManager") == null:
		return
	_started = true
	main.get_node("WaveManager").set_process(false)
	# The menu over a plain backdrop: a machine without a GPU renders the map at a frame every
	# few seconds, and the world behind the panel is not what is being judged.
	if OS.get_cmdline_user_args().has("--no-3d"):
		get_viewport().disable_3d = true
	for _i: int in 60:
		await get_tree().process_frame
	await _shoot(main)
	get_tree().quit()


func _shoot(main: Node) -> void:
	var out_path: String = "base_ui.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--"):
		out_path = args[0]
	for color: String in RunState.COLORS:
		RunState.mana_pool[color] = 12
	var names: Array[String] = ["Marvin", "Anna", "", "Bolt", "Rusty"]
	for index: int in names.size():
		main.request_build_myr()
	var workers: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group("myrs"):
		workers.append(node)
	for index: int in workers.size():
		var myr: Node = workers[index]
		myr.display_name = names[index % names.size()]
		myr.mana_delivered = [14, 3, 0, 27, 6][index % 5]
		myr.deaths = [0, 1, 0, 2, 0][index % 5]
	main.request_myr_level(workers[0])
	main.request_myr_level(workers[0])
	main.request_myr_level(workers[3])
	main.request_build_guard(Myr.ROLE_ENFORCER)
	main.request_build_guard(Myr.ROLE_LODESTONE)
	for node: Node in get_tree().get_nodes_in_group("myr_guards"):
		main.request_myr_lane(node, 0 if node.role == Myr.ROLE_ENFORCER else 3)
		node.kills = 4
		node.intercepts = 7
	# One for the Graveyard.
	workers[4].level = 3
	workers[4].invested = 12
	workers[4].take_damage(100000.0)
	for _i: int in 10:
		await get_tree().process_frame
	main.base_ui_instance.open(main)
	for _i: int in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(out_path)
	print("saved %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
