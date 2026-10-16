extends Node
## Regression test: every biome of the real map keeps its wild beasts, each living where a
## beast should. Stage 3 of docs/BEASTS_PLAN.md (the WildlifeManager).
##
## Run with:  godot --headless --path . res://tools/tests/beast_spawns.tscn
## Windowed, with a folder after `--`, it also saves a frame of one beast per biome:
##   godot --path . res://tools/tests/beast_spawns.tscn -- C:/some/folder
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.
##
## Boots main.tscn with the beasts' timers cut short, then checks:
##   1. Every biome fills up to beast_max_per_biome, with its own colour's beast, at a size
##      the wave allows (every size up to the largest, evenly, for this test).
##   2. Every home is inside its own biome's wedge, clear of every lane's enemy path, outside
##      the hub, dry, on the navmesh, free of trees and rocks for the beast's length, and apart
##      from the other homes - all by margins that grow with the beast's size.
##   3. Left a while, no beast strays past its leash or makes for the crystal.
##   4. Killing one is not a wave kill (no SignalBus.enemy_died, the wave's count unchanged),
##      and the biome replaces it once its respawn time is up.

const BeastDatabase := preload("res://scripts/beast_database.gd")

var _frames: int = 0
var _started: bool = false
var _failures: Array[String] = []
var _wave_deaths: int = 0


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	GameSettings.beast_first_spawn_delay = 1.0
	GameSettings.beast_spawn_stagger = 1.0
	GameSettings.beast_spawn_check_interval = 0.5
	GameSettings.beast_respawn_min = 3.0
	GameSettings.beast_respawn_max = 4.0
	# Every size from the first wave on, evenly: the map has to find room for giants too.
	GameSettings.beast_size_cap_start = GameSettings.beast_size_max
	GameSettings.beast_size_skew = 1.0
	GameSettings.intro_tour_pending = false
	var probe: Node = load("res://tools/tests/beast_spawns.gd").new()
	probe.name = "BeastSpawnsTest"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	var scene: Node = get_tree().current_scene
	if scene == null or scene.get_node_or_null("WildlifeManager") == null:
		return
	_started = true
	SignalBus.enemy_died.connect(func() -> void: _wave_deaths += 1)
	await _run(scene, scene.get_node("WildlifeManager"))
	get_tree().quit()


func _run(main: Node, wildlife: Node) -> void:
	var cap: int = GameSettings.beast_max_per_biome
	var filled: bool = await _wait(60.0, func() -> bool:
		for lane: String in MainController.LANE_NAMES:
			if wildlife.beasts_in(lane).size() < cap:
				return false
		return true)
	for lane: String in MainController.LANE_NAMES:
		var beasts: Array = wildlife.beasts_in(lane)
		_check("%s fills up to %d beasts" % [lane, cap], beasts.size() == cap, "%d living" % beasts.size())
		for beast: EnemyBase in beasts:
			_check_beast(wildlife, lane, beast)
	_check_spacing(wildlife)
	if not filled:
		_report()
		return

	# Left alone a while: nobody strays.
	await _wait(10.0, Callable())
	for lane: String in MainController.LANE_NAMES:
		for beast: EnemyBase in wildlife.beasts_in(lane):
			var out: float = _flat(beast.global_position, beast._home_position)
			_check("%s's beast keeps to its territory" % lane, out <= GameSettings.beast_leash_radius * sqrt(beast._beast_size),
				"%.1fm from home" % out)
			var to_crystal: float = _flat(beast.global_position, main.crystal_anchor.global_position)
			_check("%s's beast keeps away from the crystal" % lane, to_crystal >= GameSettings.beast_min_crystal_distance - GameSettings.beast_leash_radius,
				"%.1fm from it" % to_crystal)
	await _shoot(wildlife)

	# One dies: not the wave's, and replaced in time.
	var lane_name: String = "Green"
	var victim: EnemyBase = wildlife.beasts_in(lane_name)[0]
	var wave_manager: Node = main.get_node("WaveManager")
	var wave_count: int = int(wave_manager.active_enemies)
	var deaths: int = _wave_deaths
	victim.take_damage(victim.max_health * 5.0)
	await get_tree().physics_frame
	_check("a beast's death is no wave kill", _wave_deaths == deaths and int(wave_manager.active_enemies) == wave_count,
		"enemy_died %d -> %d, wave count %d -> %d" % [deaths, _wave_deaths, wave_count, int(wave_manager.active_enemies)])
	var replaced: bool = await _wait(GameSettings.beast_respawn_max + 6.0, func() -> bool:
		var living: Array = wildlife.beasts_in(lane_name).filter(func(b: EnemyBase) -> bool: return not b.is_dying)
		return living.size() == cap and not living.has(victim))
	_check("the biome replaces a dead beast", replaced, "")
	_report()


func _check_beast(wildlife: Node, lane: String, beast: EnemyBase) -> void:
	var home: Vector3 = beast._home_position
	_check("%s's beast is its own" % lane, beast.is_beast() and beast.enemy_data.color_identity == lane \
		and beast.enemy_data.display_name == BeastDatabase.display_name(lane),
		"%s %s" % [beast.enemy_data.color_identity, beast.enemy_data.display_name])
	_check("%s's beast lives in its own biome" % lane, wildlife.in_wedge(home, wildlife.lane_dir(lane)), "home %s" % home)
	var size: float = beast._beast_size
	var cap: float = BeastDatabase.roll_size(maxi(int(get_tree().current_scene.get_node("WaveManager").current_wave), 1), 1.0)
	_check("%s's beast has a size for this wave" % lane, size >= 1.0 and size <= cap + 0.001 and is_equal_approx(beast.scale.y, size),
		"size %.2f, cap %.2f, scale %.2f" % [size, cap, beast.scale.y])
	var road: float = INF
	for other: Dictionary in wildlife._lanes:
		road = minf(road, wildlife.distance_to_path(home, other["road"]))
	_check("%s's beast lives off the road" % lane, road >= wildlife.lane_clearance(size) - 0.5,
		"%.1fm from a lane, needs %.1f" % [road, wildlife.lane_clearance(size)])
	var crystal: float = _flat(home, wildlife._crystal)
	_check("%s's beast lives outside the hub" % lane, crystal >= wildlife.min_crystal_distance(size) - 0.5, "%.1fm from the crystal" % crystal)
	_check("%s's beast has room" % lane, wildlife._open_ground(home, size), "")
	_check("%s's beast lives on dry land" % lane, not wildlife._in_water(home), "")
	var map: RID = beast.get_world_3d().navigation_map
	var on_mesh: float = _flat(NavigationServer3D.map_get_closest_point(map, home), home)
	_check("%s's beast lives on the navmesh" % lane, on_mesh < 1.0, "%.2fm off it" % on_mesh)


func _check_spacing(wildlife: Node) -> void:
	var beasts: Array[EnemyBase] = []
	for lane: String in MainController.LANE_NAMES:
		for beast: EnemyBase in wildlife.beasts_in(lane):
			beasts.append(beast)
	var worst: float = INF
	for i: int in beasts.size():
		for j: int in range(i + 1, beasts.size()):
			var apart: float = _flat(beasts[i]._home_position, beasts[j]._home_position)
			worst = minf(worst, apart - wildlife.home_spacing(beasts[i]._beast_size, beasts[j]._beast_size))
	_check("territories do not overlap", worst >= -0.5, "closest pair %.1fm inside its spacing" % -worst)


## A frame of the first beast of each biome, from the side and a little above.
func _shoot(wildlife: Node) -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		return
	# Midday, so the shots show the beasts rather than the dark.
	var sky: Node = get_tree().current_scene.get_node_or_null("Sky3D")
	if sky != null:
		sky.set("current_time", 13.0)
	var cam := Camera3D.new()
	cam.far = 2000.0
	get_tree().current_scene.add_child(cam)
	cam.make_current()
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
	for lane: String in MainController.LANE_NAMES:
		var beasts: Array = wildlife.beasts_in(lane)
		if beasts.is_empty():
			continue
		var beast: EnemyBase = beasts[0]
		var at: Vector3 = beast.global_position
		var eye: Vector3 = at + beast.global_basis.z * 6.0 + beast.global_basis.x * 4.0
		# Kept above the ground there, which on a slope can be higher than the beast.
		var probe := PhysicsRayQueryParameters3D.create(eye + Vector3.UP * 60.0, eye + Vector3.DOWN * 60.0, EnemyBase.ENVIRONMENT_LAYER)
		var hit: Dictionary = space.intersect_ray(probe)
		var ground: float = (hit["position"] as Vector3).y if not hit.is_empty() else at.y
		eye.y = maxf(at.y, ground) + 3.5
		cam.global_position = eye
		cam.look_at(at + Vector3.UP * 0.6)
		for i: int in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0].path_join("biome_%s.png" % lane.to_lower()))
	cam.queue_free()


## Runs until `until` holds or `seconds` pass. Returns whether it held.
func _wait(seconds: float, until: Callable) -> bool:
	var elapsed: float = 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if until.is_valid() and until.call():
			return true
	return false


func _report() -> void:
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s %s (%s)" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s: %s" % [what, detail])
