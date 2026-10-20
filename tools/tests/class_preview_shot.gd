extends Node
## Renders the main menu once per playable class, with that class standing in its
## ClassPreview - for checking the figure's framing, light and caption over the painting.
##
## Run with (windowed - a headless run renders nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1600x900 res://tools/tests/class_preview_shot.tscn -- <folder>
##
## Writes <folder>/menu_<class>.png. The class is put on the preview directly rather than
## through the picker, so the player's saved class is never touched.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
## The boot splash fades for 1.8 s, and a fresh model wants a moment to settle its idle.
const SETTLE_SECONDS := 2.6


func _ready() -> void:
	if get_meta("armed", false):
		_run.call_deferred()
		return
	var probe: Node = load("res://tools/tests/class_preview_shot.gd").new()
	probe.set_meta("armed", true)
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func _run() -> void:
	var folder: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://class_preview"
	DirAccess.make_dir_recursive_absolute(folder)
	while not get_tree().current_scene is MainMenu:
		await get_tree().process_frame
	var menu: MainMenu = get_tree().current_scene as MainMenu
	var preview: ClassPreview = menu._class_preview
	for class_id: String in ClassDatabase.ORDER:
		preview.show_class(class_id)
		await get_tree().create_timer(SETTLE_SECONDS).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/menu_%s.png" % [folder, class_id])
		# The figure at its widest: every idle variation at the moment its weapon is furthest
		# from the body, and turned side-on as a drag leaves it - nothing may be cut off.
		for look: String in ["idle_look_1", "idle_look_2"]:
			if preview._anim == null or not preview._anim.has_animation(look):
				continue
			var widest: float = await _widest_moment(preview, look)
			preview._anim.play(look)
			preview._anim.seek(widest, true)
			preview._anim.pause()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/menu_%s_%s.png" % [folder, class_id, look])
		preview._anim.play("idle")
		preview._since_drag = -INF
		preview._yaw = ClassPreview.REST_YAW + PI * 0.5
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/menu_%s_turned.png" % [folder, class_id])
		preview._since_drag = 0.0
	get_tree().quit()


## When in `clip` the figure's meshes reach furthest from its feet, sideways or up.
func _widest_moment(preview: ClassPreview, clip: String) -> float:
	var anim: Animation = preview._anim.get_animation(clip)
	var best: float = 0.0
	var best_t: float = 0.0
	var t: float = 0.0
	preview._anim.play(clip)
	while t < anim.length:
		preview._anim.seek(t, true)
		await get_tree().process_frame
		var reach: float = 0.0
		for node: Node in preview._visual.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			for corner in 8:
				var p: Vector3 = box.get_endpoint(corner) - preview._visual.global_position
				reach = maxf(reach, maxf(Vector2(p.x, p.z).length(), p.y * 0.5))
		if reach > best:
			best = reach
			best_t = t
		t += 0.1
	return best_t
