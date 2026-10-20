extends Node
## Renders every page of the main menu at the window's size - for checking the layout fits a
## 720p or 1080p screen as well as a big one.
##
## Run with (windowed - a headless run renders nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/menu_shot.tscn -- <folder>
##
## Writes <folder>/menu_<width>x<height>_<page>.png. Nothing is pressed - the pages are shown
## directly - so no game is hosted, joined or started, and no setting is touched.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
## The boot splash fades for 1.8 s, and the class preview fades its figure in.
const SETTLE_SECONDS := 2.4
const PAGES := {"main": MainMenu.Page.MAIN, "host": MainMenu.Page.HOST, "browse": MainMenu.Page.BROWSE, "lobby": MainMenu.Page.LOBBY}


func _ready() -> void:
	if get_meta("armed", false):
		_run.call_deferred()
		return
	var probe: Node = load("res://tools/tests/menu_shot.gd").new()
	probe.set_meta("armed", true)
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func _run() -> void:
	var folder: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://menu_shot"
	DirAccess.make_dir_recursive_absolute(folder)
	while not get_tree().current_scene is MainMenu:
		await get_tree().process_frame
	var menu: MainMenu = get_tree().current_scene as MainMenu
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var size: Vector2i = get_viewport().get_visible_rect().size
	var tag: String = "%dx%d" % [size.x, size.y]
	for page: String in PAGES:
		menu._show_page(PAGES[page])
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/menu_%s_%s.png" % [folder, tag, page])
	menu._show_page(MainMenu.Page.MAIN)
	menu._set_settings_open(true)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/menu_%s_settings.png" % [folder, tag])
	get_tree().quit()
