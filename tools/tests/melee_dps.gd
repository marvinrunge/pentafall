extends Node
## Measures a melee class's damage per second on one enemy, through the real buttons on the
## real map - for keeping the classes' basic attacks level with each other.
##
## Run with (windowed - the kits read the real attack button with the mouse captured):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/melee_dps.tscn -- barbarian
## Prints one MEASURE line per way of attacking, at team level 1 (no class skills):
##   spam      the attack button tapped as fast as it can be - every swing chained into the
##             next as early as the combo window allows
##   finished  one tap, then nothing until the swing is over, again and again
##   heavy     held just long enough for the heavy, again and again
## The dummy is kept a fixed distance in front, so a class that walks into its swings
## measures the same as one that stands.

const SECONDS := 10.0
const DISTANCE := 2.6

var _started: bool = false
## While set, the dummy is put back in front of the player every physics frame.
var _player: Player
var _dummy: EnemyBase


func _physics_process(_delta: float) -> void:
	if _player != null and is_instance_valid(_dummy):
		_keep_in_front(_player, _dummy)


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	GameSettings.intro_tour_pending = false
	GameSettings.beast_first_spawn_delay = 9999.0
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var probe: Node = load("res://tools/tests/melee_dps.gd").new()
	probe.set_meta("player_class", UserSettings.character_class)
	UserSettings.character_class = args[0] if not args.is_empty() else "warrior"
	probe.name = "MeleeDpsTest"
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
	await _run(scene, PlayerRegistry.get_local() as Player)
	UserSettings.set_value(&"character_class", String(get_meta("player_class", "warrior")))
	await get_tree().create_timer(0.6).timeout
	get_tree().quit()


func _run(main: Node, player: Player) -> void:
	await _frames(60)
	var waves: Node = main.get_node("WaveManager")
	waves.set_physics_process(false)
	waves.set_process(false)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await _frames(5)
	RunState.team_level = 1
	var at: Vector3 = player.global_position - _forward(player) * DISTANCE
	var dummy: EnemyBase = main.request_enemy({"color": "Red", "type": "Melee", "position": at}) as EnemyBase
	await _frames(3)
	dummy.set_physics_process(false)
	dummy.health = 1.0e7
	_player = player
	_dummy = dummy

	for mode: String in ["spam", "finished", "heavy"]:
		await _capture()
		await _until_idle(player)
		var hp: float = dummy.health
		var swings: int = 0
		var start_frame: int = Engine.get_physics_frames()
		var elapsed: float = 0.0
		while elapsed < SECONDS:
			match mode:
				"spam":
					Input.action_press("attack")
					await _frames(2)
					Input.action_release("attack")
					await _frames(2)
				"finished":
					Input.action_press("attack")
					await _frames(2)
					Input.action_release("attack")
					await _frames(3)
					await _until_idle(player)
					swings += 1
				"heavy":
					Input.action_press("attack")
					await _seconds(GameSettings.player_heavy_hold_time + 0.05)
					Input.action_release("attack")
					await _frames(3)
					await _until_idle(player)
					swings += 1
			elapsed = float(Engine.get_physics_frames() - start_frame) / Engine.physics_ticks_per_second
		# Whatever was still in the air when the clock ran out lands now, and so does its time.
		await _until_idle(player)
		elapsed = float(Engine.get_physics_frames() - start_frame) / Engine.physics_ticks_per_second
		var dealt: float = hp - dummy.health
		print("MEASURE %s %-8s %.1f damage in %.1f s = %.1f per second%s" % [
			player.character_class, mode, dealt, elapsed, dealt / elapsed, "" if swings == 0 else " (%d swings)" % swings])
	print("TEST RESULT: DONE")


func _keep_in_front(player: Player, dummy: EnemyBase) -> void:
	dummy.global_position = player.global_position - _forward(player) * DISTANCE
	dummy.velocity = Vector3.ZERO
	dummy.knockback_velocity = Vector3.ZERO


func _forward(player: Player) -> Vector3:
	var f: Vector3 = player.global_basis.z
	return Vector3(f.x, 0.0, f.z).normalized()


func _until_idle(player: Player) -> float:
	var waited: float = 0.0
	var step: float = 1.0 / Engine.physics_ticks_per_second
	while player._action_timer > 0.0 and waited < 6.0:
		await get_tree().physics_frame
		waited += step
	return waited


func _capture() -> void:
	get_window().grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _frames(3)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await _frames(int(ceil(s * Engine.physics_ticks_per_second)))
