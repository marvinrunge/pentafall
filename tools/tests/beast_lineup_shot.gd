extends "res://tools/tests/vfx_stage.gd"
## Screenshot: the beast of every biome side by side, named, in its biome's skin
## (BeastDatabase.VARIANTS). For judging the recolours.
##
## Run with (windowed - a headless run renders nothing):
##   godot --path . --resolution 1920x900 res://tools/tests/beast_lineup_shot.tscn -- C:/out.png

const COLORS: Array[String] = ["White", "Blue", "Black", "Red", "Green"]
const SPACING := 3.4


func _ready() -> void:
	build_stage()
	_shoot.call_deferred()


func _shoot() -> void:
	for i: int in ready_frames():
		await get_tree().physics_frame
	var row_half: float = SPACING * float(COLORS.size() - 1) * 0.5
	for i: int in COLORS.size():
		var color: String = COLORS[i]
		var at := Vector3(float(i) * SPACING - row_half, 0.0, 0.0)
		var beast: Node3D = request_enemy({"color": color, "type": "Beast", "position": at})
		beast.rotation.y = deg_to_rad(-35.0)
		var label := Label3D.new()
		label.text = "%s\n%s" % [EnemyBase.BeastDatabase.display_name(color), color]
		label.font_size = 44
		label.outline_size = 10
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = at + Vector3(0.0, 1.9, 0.0)
		add_child(label)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 2.2, 8.2)
	cam.look_at(Vector3(0.0, 0.8, 0.0))
	cam.fov = 58.0
	cam.current = true
	for i: int in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://beast_lineup.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("SAVED %s" % out)
	get_tree().quit()
