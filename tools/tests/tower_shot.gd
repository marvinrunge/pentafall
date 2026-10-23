extends Node3D
## Screenshots the five round-two towers side by side under the game's own sky, at noon, at
## dusk and at night - the models, their size against an enemy, and whether their glow carries
## them through the dark.
##
## Run with (windowed - a headless run uses the dummy renderer and draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1600x700 res://tools/tests/tower_shot.tscn -- <folder> [--front] [--glow]

const Tower := preload("res://scripts/tower.gd")
const HOURS: Array[float] = [12.0, 19.5, 23.0]
const SPACING := 6.5

var _sky: Sky3D


func _ready() -> void:
	_sky = Sky3D.new()
	add_child(_sky)
	if _sky.tod:
		_sky.tod.game_time_enabled = false
	if OS.get_cmdline_user_args().has("--glow") and _sky.environment != null:
		GraphicsSettings.configure_glow(_sky.environment, true)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.22, 0.26, 0.20)
	ground.material_override = ground_material
	add_child(ground)

	for index: int in Tower.IDS.size():
		var tower: StaticBody3D = Tower.create(Tower.IDS[index], 1, null)
		tower.position = Vector3((index - 2) * SPACING, 0.0, 0.0)
		# As a caster where the camera is would put it up: front to the enemies beyond, back
		# (and its glow) to the caster - turned a little so the side shows too. `--front`
		# turns them round.
		tower.rotation.y = 0.5 + (PI if OS.get_cmdline_user_args().has("--front") else 0.0)
		add_child(tower)
		# The tower's own work wants a running match; here it only stands.
		tower.set_physics_process(false)
	# One enemy for scale.
	var enemy: EnemyBase = (load("res://scenes/misc/enemy.tscn") as PackedScene).instantiate()
	enemy.set_meta("enemy_color", "Red")
	enemy.set_meta("enemy_type", "Melee")
	add_child(enemy)
	enemy.position = Vector3(-2 * SPACING + 2.2, 0.0, 1.5)
	enemy.set_physics_process(false)

	var camera := Camera3D.new()
	camera.fov = 40.0
	camera.position = Vector3(0.0, 4.5, 21.0)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 2.2, 0.0), Vector3.UP)
	_shoot.call_deferred()


func _shoot() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = "user://tower_shot"
	if not args.is_empty() and not args[0].begins_with("--"):
		folder = args[0]
	DirAccess.make_dir_recursive_absolute(folder)
	for hour: float in HOURS:
		if _sky.tod:
			_sky.tod.current_time = hour
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var file: String = "towers_%05.2f.png" % hour
		get_viewport().get_texture().get_image().save_png(folder.path_join(file))
		print("TOWER saved %s" % file)
	get_tree().quit()
