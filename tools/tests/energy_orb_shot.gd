extends "res://tools/tests/vfx_stage.gd"
## Photographs the energy orbs (SpellFx.energy_orb) side by side, by day and by night: the
## mage's bolt on no path, blue and green, a bolt Prowess empowered, the Arcane Blast, the
## Fireball in flight and the Fireball held at half and at full charge.
##
## Run with (windowed - a headless run draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1600x900 res://tools/tests/energy_orb_shot.tscn -- <folder> --glow
##
## Writes <folder>/orbs_day.png, orbs_night.png and a close-up of each (orbs_*_close.png),
## each twice a moment apart (_b) so the churn can be seen moving.

const ChargeOrb = preload("res://scripts/charge_orb.gd")
const ROW_HEIGHT := 1.5
const SPACING := 1.3
## The fireball drifts this fast towards the camera's left, put back on its spot before every
## shot, so the flames it sheds trail behind it the way they do in flight.
const FIREBALL_DRIFT := 2.5

var _fireball: Projectile = null
var _fireball_home: Vector3 = Vector3.ZERO


func _ready() -> void:
	build_stage()
	_run.call_deferred()


func _run() -> void:
	for i in ready_frames():
		await get_tree().physics_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = args[0] if not args.is_empty() and not args[0].begins_with("--") else "user://energy_orb_shot"
	DirAccess.make_dir_recursive_absolute(folder)

	var holder: Node3D = get_node("Effects")
	var x: float = -SPACING * 3.5
	for spec: Array in [["", 1.0], ["blue", 1.0], ["green", 1.0], ["red", 1.45], ["", 2.2]]:
		var bolt := MageBolt.new()
		bolt.color = spec[0]
		bolt.size = spec[1]
		holder.add_child(bolt)
		bolt.global_position = Vector3(x, ROW_HEIGHT, 0.0)
		x += SPACING
	var fireball: Projectile = (load("res://scenes/misc/projectile.tscn") as PackedScene).instantiate()
	holder.add_child(fireball)
	fireball.activate(Vector3(x, ROW_HEIGHT, 0.0), Vector3.RIGHT, 4, false, 1.0, -1.0,
		GameSettings.spell_red_fireball_base_radius * 1.3)
	fireball.direction = Vector3.LEFT
	fireball.speed = FIREBALL_DRIFT
	fireball.life_timer = 999.0
	fireball.collision_mask = 0
	_fireball = fireball
	_fireball_home = Vector3(x, ROW_HEIGHT, 0.0)
	x += SPACING
	for progress: float in [0.5, 1.0]:
		var orb: Node3D = ChargeOrb.new()
		orb.setup(1.0)
		holder.add_child(orb)
		orb.global_position = Vector3(x, ROW_HEIGHT, 0.0)
		orb.set_progress(progress)
		x += SPACING

	var camera := Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	camera.current = true
	for time: String in ["day", "night"]:
		if time == "night":
			# The game's nights are near black on purpose; whatever is seen is self-lit.
			environment.background_energy_multiplier = 0.04
			environment.ambient_light_energy = 0.04
			sun.light_energy = 0.02
		camera.global_position = Vector3(0.0, ROW_HEIGHT + 1.2, 8.5)
		camera.look_at(Vector3(0.0, ROW_HEIGHT, 0.0))
		await _shoot(folder, "orbs_%s" % time)
		# Close on the blast and the fireball, the two biggest balls.
		camera.global_position = Vector3(SPACING, ROW_HEIGHT + 0.2, 2.6)
		camera.look_at(Vector3(SPACING, ROW_HEIGHT, 0.0))
		await _shoot(folder, "orbs_%s_close" % time)
	get_tree().quit()


func _shoot(folder: String, file_name: String) -> void:
	if _fireball != null:
		_fireball.global_position = _fireball_home
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [folder, file_name])
	for i in 9:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_b.png" % [folder, file_name])
	print("wrote ", file_name)
