extends Node
## Regression test: the Last Stand (docs/LAST_STAND_PLAN.md, WaveManager._check_last_stand).
##
## Run with:  godot --headless --path . res://tools/tests/last_stand.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.
##
## Boots main.tscn with a time limit far too long to matter and kills the first wave by hand:
##   1. Nothing storms while more than the threshold is standing.
##   2. The kill that leaves the threshold starts the storm at once - clock cleared, its own
##      banner, every enemy left storming and revealed on the minimap.
##   3. A stormer held still away from the crystal is moved on along its way, not killed.
##   4. No arrival banners: nothing but the storm's line reaches the banner during the wave.

var _started: bool = false
var _failures: Array[String] = []
var _banners: Array[String] = []


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	GameSettings.wave_time_limit_base = 600.0
	GameSettings.wave_time_limit_per_wave = 0.0
	GameSettings.wave_storm_duration = 30.0
	GameSettings.intro_tour_pending = false
	var probe: Node = load("res://tools/tests/last_stand.gd").new()
	probe.name = "LastStandTest"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	var scene: Node = get_tree().current_scene
	if scene == null or scene.get_node_or_null("WaveManager") == null:
		return
	_started = true
	SignalBus.lane_warning_requested.connect(func(_lane: String, message: String, _tint: Color) -> void:
		_banners.append(message))
	await _run(scene, scene.get_node("WaveManager"))
	get_tree().quit()


func _run(main: Node, waves: Node) -> void:
	var on_map: bool = await _wait(120.0, func() -> bool: return waves.deadline_left >= 0.0)
	_check("the wave gets on the map", on_map, "deadline %.1f" % waves.deadline_left)
	if not on_map:
		_report()
		return
	var threshold: int = WaveManager.last_stand_threshold(waves.wave_total)
	_check("the threshold is a share of the wave", threshold >= 1 and threshold <= GameSettings.wave_last_stand_max_remaining,
		"%d of %d" % [threshold, waves.wave_total])

	# 1. down to one above the threshold: no storm yet
	while waves.active_enemies > threshold + 1 and not _wave_enemies().is_empty():
		_kill(_wave_enemies()[0])
		await get_tree().physics_frame
	_check("no storm while more than the threshold stands", waves.storm_left < 0.0 and waves.deadline_left >= 0.0,
		"%d standing, storm %.1f" % [waves.active_enemies, waves.storm_left])
	_check("nobody is revealed yet", _wave_enemies().all(func(e: EnemyBase) -> bool: return not e.revealed), "")

	# 2. the kill that leaves the threshold
	_kill(_wave_enemies()[0])
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("the Last Stand starts the storm", waves.storm_left >= 0.0, "%d standing" % waves.active_enemies)
	_check("the clock is cleared", waves.deadline_left < 0.0, "deadline %.1f" % waves.deadline_left)
	_check("it has its own banner", _banners.has("THE WAVE MAKES ITS LAST STAND"), "banners %s" % [_banners])
	var left: Array[EnemyBase] = _wave_enemies()
	_check("what is left storms and is revealed", not left.is_empty() and left.all(func(e: EnemyBase) -> bool:
		return e.storm_timer > 0.0 and e.revealed and e.current_target == e.target_crystal), "%d left" % left.size())

	# 3. a stormer caught on something
	var stuck: EnemyBase = null
	for enemy: EnemyBase in left:
		if not enemy._near_crystal_to_storm() and not enemy.is_boss():
			stuck = enemy
			break
	if stuck == null:
		_check("a stormer far from the crystal to pin", false, "")
	else:
		var map: RID = stuck.get_world_3d().navigation_map
		var crystal: Vector3 = main.crystal_anchor.global_position
		var at: Vector3 = stuck.global_position
		var before: float = Vector2(at.x - crystal.x, at.z - crystal.z).length()
		var moved: bool = false
		# Held still: the watch is asked again with the enemy exactly where it was.
		for i: int in range(int(ceil(GameSettings.enemy_storm_stuck_seconds)) + 2):
			stuck.global_position = at
			if stuck._check_storm_stuck(map, 1.0):
				moved = true
				break
		var after_pos: Vector3 = stuck.global_position
		var after: float = Vector2(after_pos.x - crystal.x, after_pos.z - crystal.z).length()
		_check("a stuck stormer is moved on", moved and after_pos.distance_to(at) > 1.0, "%s -> %s" % [at, after_pos])
		_check("...towards the crystal", after < before, "%.1f -> %.1f" % [before, after])
		_check("...and not killed", is_instance_valid(stuck) and not stuck.is_dying, "")

	# 4. the only banner of the wave is the storm's
	var others: Array[String] = []
	for message: String in _banners:
		if message != "THE WAVE MAKES ITS LAST STAND" and not message.begins_with("LEVEL"):
			others.append(message)
	_check("no arrival banners", others.is_empty(), "%s" % [others])
	_report()


func _kill(enemy: EnemyBase) -> void:
	enemy.take_damage(enemy.health * 10.0 + 10000.0)


func _wave_enemies() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyBase and not (node as EnemyBase).is_beast() and not (node as EnemyBase).is_dying and not node.is_queued_for_deletion():
			out.append(node as EnemyBase)
	return out


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


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s %s (%s)" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s: %s" % [what, detail])
