extends "res://tools/tests/vfx_stage.gd"
## Screenshot: a worker myr beside the Myr Enforcer and the Lodestone Myr at the sizes the game
## draws them (Myr._apply_color_visual, Myr._apply_level_scale), and below them each guard's
## blow at the start, on its impact frame (`hit_ratio`) and after. For judging the guards'
## models and their attack clips.
##
## Run with (windowed - a headless run renders nothing):
##   godot --path . --resolution 1920x1080 res://tools/tests/myr_guards_shot.tscn -- C:/out.png

const WORKER_SCENE := "res://scenes/myrs/iron_myr.tscn"


func _ready() -> void:
	build_stage()
	_shoot.call_deferred()


func _shoot() -> void:
	for i: int in ready_frames():
		await get_tree().physics_frame
	# The line-up: drawn as Myr draws them - a worker's scene at a flat 100x, a guard's at the
	# size its builder gave it - then the node scale of its kind.
	_place(WORKER_SCENE, Vector3(-3.4, 0.0, 0.0), 1.0, true, "Myr", "idle", 0.0)
	_place(Myr.GUARD_SCENES[Myr.ROLE_ENFORCER], Vector3(0.0, 0.0, 0.0), GameSettings.myr_enforcer_scale, false,
		"Myr Enforcer", "idle", 0.0)
	_place(Myr.GUARD_SCENES[Myr.ROLE_LODESTONE], Vector3(3.6, 0.0, 0.0), GameSettings.myr_lodestone_scale, false,
		"Lodestone Myr", "idle", 0.0)
	# The blows, a row further back: start, impact, follow-through.
	var row: Array = [[Myr.ROLE_ENFORCER, GameSettings.myr_enforcer_scale, -9.0], [Myr.ROLE_LODESTONE, GameSettings.myr_lodestone_scale, 3.0]]
	for entry: Array in row:
		var path: String = Myr.GUARD_SCENES[entry[0]]
		var hit: float = _hit_ratio(path)
		var phases: Array[float] = [hit * 0.4, hit, minf(hit + 0.2, 0.95)]
		for i: int in phases.size():
			_place(path, Vector3(float(entry[2]) + float(i) * 3.0, 0.0, -6.0), entry[1], false,
				"%d%%" % roundi(phases[i] * 100.0), "attack", phases[i])
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 3.4, 8.0)
	cam.look_at(Vector3(0.0, 1.1, -2.5))
	cam.fov = 62.0
	cam.current = true
	for i: int in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://myr_guards_shot.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("SAVED %s" % out)
	get_tree().quit()


func _place(path: String, at: Vector3, node_scale: float, worker: bool, caption: String, clip: String, ratio: float) -> void:
	var holder := Node3D.new()
	holder.position = at
	holder.scale = Vector3.ONE * node_scale
	holder.rotation.y = deg_to_rad(-20.0)
	add_child(holder)
	var model: Node3D = (load(path) as PackedScene).instantiate()
	if worker:
		model.scale = Vector3(100, 100, 100)
	holder.add_child(model)
	# Myr._ground_visual: a worker's scene keeps its builder's lift under myr.gd's 100x, which
	# would sink it; it is stood on its mesh's lowest point instead. A guard's is already there.
	var mesh: MeshInstance3D = model.find_child("Skeleton3D", true, false).get_child(0) as MeshInstance3D
	var aabb: AABB = mesh.global_transform * mesh.get_aabb()
	model.position.y -= aabb.position.y - holder.global_position.y
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var shown: String = clip if player.has_animation(clip) else "walk"
	player.play(shown)
	player.seek(player.get_animation(shown).length * ratio, true)
	player.pause()
	var label := Label3D.new()
	label.text = caption
	label.font_size = 40
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at + Vector3(0.0, 2.2 * node_scale + 0.4, 0.0)
	add_child(label)


func _hit_ratio(path: String) -> float:
	var model: Node = (load(path) as PackedScene).instantiate()
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var ratio: float = float(player.get_animation("attack").get_meta("hit_ratio", 0.5))
	model.free()
	return ratio
