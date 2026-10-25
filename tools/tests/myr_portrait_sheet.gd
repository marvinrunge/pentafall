extends Node
## The reference sheet for the myrs' icons (docs/ICON_PROMPTS.md, "The myrs"): every myr the
## game has, rendered from its own scene in the 3 x 3 grid the prompt and
## `tools/slice_icon_sheet.py --set myrs` use - the five workers in lane order, the two guards,
## a fallen worker for the Graveyard and three workers together. Attached to the prompt as
## "draw exactly these creatures", since an image generator left to itself draws a generic
## robot (the first upkeep-myr.png was one).
##
## Run with (windowed - a headless run renders nothing):
##   godot --path . --resolution 1024x1024 res://tools/tests/myr_portrait_sheet.tscn -- C:/out.png

const CELL := 640
const GUTTER := 32
const BACKGROUND := Color(0.035, 0.045, 0.06)
const GUTTER_COLOR := Color(0.01, 0.01, 0.012)

## [scene, clip, moment as a share of the clip] per myr in the cell; workers are drawn at
## myr.gd's flat 100x, as in the game.
const CELLS: Array = [
	[["res://scenes/myrs/gold_myr.tscn", "walk", 0.3]],
	[["res://scenes/myrs/silver_myr.tscn", "walk", 0.3]],
	[["res://scenes/myrs/leaden_myr.tscn", "walk", 0.3]],
	[["res://scenes/myrs/iron_myr.tscn", "walk", 0.3]],
	[["res://scenes/myrs/copper_myr.tscn", "walk", 0.3]],
	[["res://scenes/myrs/myr_enforcer.tscn", "idle", 0.3]],
	[["res://scenes/myrs/lodestone_myr.tscn", "idle", 0.3]],
	[["res://scenes/myrs/silver_myr.tscn", "death", 1.0]],
	[["res://scenes/myrs/gold_myr.tscn", "walk", 0.1], ["res://scenes/myrs/iron_myr.tscn", "walk", 0.45],
		["res://scenes/myrs/copper_myr.tscn", "walk", 0.75]],
]

const Impact = preload("res://tools/animation_impact.gd")

var _viewports: Array[SubViewport] = []


func _ready() -> void:
	for cell: Array in CELLS:
		_viewports.append(_build_cell(cell))
	_shoot.call_deferred()


func _shoot() -> void:
	for i: int in 3:
		await get_tree().process_frame
	for i: int in CELLS.size():
		_frame(_viewports[i], CELLS[i].size() > 1, CELLS[i][0][1] == "death")
	for i: int in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var side: int = CELL * 3 + GUTTER * 4
	var sheet := Image.create(side, side, false, Image.FORMAT_RGBA8)
	sheet.fill(GUTTER_COLOR)
	for i: int in _viewports.size():
		var shot: Image = _viewports[i].get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		_vignette(shot)
		sheet.blit_rect(shot, Rect2i(0, 0, CELL, CELL), Vector2i(GUTTER + (i % 3) * (CELL + GUTTER), GUTTER + (i / 3) * (CELL + GUTTER)))
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://myr_portrait_sheet.png"
	sheet.save_png(out)
	print("SAVED %s" % out)
	get_tree().quit()


func _build_cell(myrs: Array) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(CELL, CELL)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.42, 0.55)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	# Key from the front left, warm; a cool rim from behind on the right, as the painted icons
	# light their subjects; a low fill so the shadow side keeps its detail.
	_light(viewport, Vector3(-35.0, -30.0, 0.0), Color(1.0, 0.9, 0.78), 1.6, true)
	_light(viewport, Vector3(-20.0, 145.0, 0.0), Color(0.55, 0.85, 1.0), 2.2, false)
	_light(viewport, Vector3(-10.0, 60.0, 0.0), Color(0.6, 0.65, 0.8), 0.35, false)

	# A group stands close, the middle one a step ahead.
	var spread: float = 0.95
	for i: int in myrs.size():
		var entry: Array = myrs[i]
		var model: Node3D = (load(entry[0]) as PackedScene).instantiate()
		if not String(entry[0]).ends_with("myr_enforcer.tscn") and not String(entry[0]).ends_with("lodestone_myr.tscn"):
			model.scale = Vector3(100, 100, 100)
		var offset: float = float(i) - float(myrs.size() - 1) * 0.5
		model.position = Vector3(offset * spread, 0.0, -absf(offset) * 0.35)
		model.rotation.y = deg_to_rad(-28.0)
		viewport.add_child(model)
		var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
		player.play(entry[1])
		player.seek(player.get_animation(entry[1]).length * float(entry[2]) - 0.001, true)
		player.pause()

	var cam := Camera3D.new()
	cam.fov = 28.0
	viewport.add_child(cam)
	cam.current = true
	return viewport


func _light(viewport: SubViewport, degrees: Vector3, color: Color, energy: float, shadow: bool) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = degrees
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadow
	viewport.add_child(light)


## Puts the camera where the posed bodies fill the cell: their bones' bounds, grown by how far
## the armour stands off the bones, seen a little from above and from the front left.
func _frame(viewport: SubViewport, group: bool, lying: bool) -> void:
	var bounds := AABB()
	var first := true
	for child: Node in viewport.get_children():
		var skeleton: Skeleton3D = child.find_child("Skeleton3D", true, false) as Skeleton3D if child is Node3D else null
		if skeleton == null:
			continue
		for bone: int in skeleton.get_bone_count():
			var point: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
			if first:
				bounds = AABB(point, Vector3.ZERO)
				first = false
			else:
				bounds = bounds.expand(point)
	var height: float = maxf(bounds.size.y, 0.5)
	bounds = bounds.grow(height * (0.06 if lying else 0.12))
	var cam: Camera3D = viewport.get_camera_3d()
	var centre: Vector3 = bounds.get_center() + Vector3(0.0, 0.0 if lying else height * 0.02, 0.0)
	# A body lying down or three side by side are wider than tall, and must fit across.
	var across: float = maxf(bounds.size.x, bounds.size.z) * (1.05 if group or lying else 0.8)
	var reach: float = maxf(bounds.size.y, across) * 0.5
	var distance: float = reach / tan(deg_to_rad(cam.fov) * 0.5) * 1.2
	var view_dir := Vector3(0.12, 0.28 if lying else 0.16, 1.0).normalized()
	cam.position = centre + view_dir * distance
	cam.look_at(centre)


## The dark falloff the painted icons put round their subject.
func _vignette(image: Image) -> void:
	var half: float = float(CELL) * 0.5
	for y: int in CELL:
		for x: int in CELL:
			var d: float = Vector2(float(x) - half, float(y) - half).length() / (half * 1.414)
			var fade: float = 1.0 - smoothstep(0.45, 1.0, d) * 0.7
			var c: Color = image.get_pixel(x, y)
			image.set_pixel(x, y, Color(c.r * fade, c.g * fade, c.b * fade, 1.0))
