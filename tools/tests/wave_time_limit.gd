extends Node
## Regression test: a wave cannot outlast its time limit (GameSettings' Time limit block).
##
## Run with:  godot --headless --path . res://tools/tests/wave_time_limit.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.
##
## Boots main.tscn with the limit cut to seconds and nobody fighting the first wave, then:
##   1. The clock starts once the wave's last group has landed, and the HUD is told.
##   2. When it runs out every enemy of the wave storms the crystal - deaf to everything else,
##      and closing in on it - while the wild beasts carry on as they were.
##   3. When the storm ends Upkeep begins and the clock is cleared, but the wave's leftovers
##      stay as stragglers, still storming; killing one is not counted (SignalBus.enemy_died)
##      and leaves the wave count alone. The beasts remain.

var _started: bool = false
var _failures: Array[String] = []
var _deadlines: Array[float] = []
var _deaths: int = 0


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	GameSettings.wave_time_limit_base = 8.0
	GameSettings.wave_time_limit_per_wave = 0.0
	GameSettings.wave_storm_duration = 6.0
	GameSettings.beast_first_spawn_delay = 1.0
	GameSettings.beast_spawn_check_interval = 0.5
	GameSettings.intro_tour_pending = false
	var probe: Node = load("res://tools/tests/wave_time_limit.gd").new()
	probe.name = "WaveTimeLimitTest"
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
	SignalBus.wave_deadline_changed.connect(func(seconds: float) -> void: _deadlines.append(seconds))
	SignalBus.enemy_died.connect(func() -> void: _deaths += 1)
	await _run(scene, scene.get_node("WaveManager"))
	get_tree().quit()


func _run(main: Node, waves: Node) -> void:
	# 1. the clock
	var started: bool = await _wait(120.0, func() -> bool: return waves.deadline_left >= 0.0)
	_check("the clock starts once the wave is on the map", started and not waves.is_spawning, "deadline %.1f" % waves.deadline_left)
	_check("the HUD is told", not _deadlines.is_empty() and _deadlines[0] > 0.0, "signals %s" % [_deadlines])
	var panel: Control = main.find_child("WaveDeadlinePanel", true, false) as Control
	await _wait(0.5, Callable())
	_check("the countdown shows in its last seconds", panel != null and panel.visible, "panel %s" % panel)
	if not started:
		_report()
		return

	# 2. the storm
	var stormed: bool = await _wait(GameSettings.wave_time_limit_base + 2.0, func() -> bool: return waves.storm_left >= 0.0)
	_check("time's up starts the storm", stormed, "")
	await _wait(0.6, Callable())
	var wave_enemies: Array[EnemyBase] = _wave_enemies()
	var all_storming: bool = not wave_enemies.is_empty()
	for enemy: EnemyBase in wave_enemies:
		all_storming = all_storming and enemy.storm_timer > 0.0 and enemy.current_target == enemy.target_crystal
	_check("every enemy of the wave storms the crystal", all_storming, "%d enemies" % wave_enemies.size())
	var beasts: Array[EnemyBase] = _beasts()
	var calm: bool = true
	for beast: EnemyBase in beasts:
		calm = calm and beast.storm_timer <= 0.0
	_check("the wild beasts carry on", calm, "%d beasts" % beasts.size())
	var crystal: Vector3 = main.crystal_anchor.global_position
	var before: float = _mean_distance(wave_enemies, crystal)
	await _wait(3.0, Callable())
	var after: float = _mean_distance(_wave_enemies(), crystal)
	_check("the storm closes on the crystal", after < before, "mean distance %.1f -> %.1f" % [before, after])

	# 3. the end of it
	var deaths_before: int = _deaths
	var wave_before: int = waves.current_wave
	var ended: bool = await _wait(GameSettings.wave_storm_duration + 2.0, func() -> bool: return waves.in_upkeep)
	await get_tree().process_frame
	_check("Upkeep begins when the storm ends", ended and waves.current_wave == wave_before + 1, "upkeep %s, wave %d" % [waves.in_upkeep, waves.current_wave])
	var leftovers: Array[EnemyBase] = _wave_enemies()
	var stragglers: bool = not leftovers.is_empty()
	for enemy: EnemyBase in leftovers:
		stragglers = stragglers and enemy.straggler and enemy.storm_timer > 0.0
	_check("the wave's leftovers stay, still storming", stragglers, "%d left" % leftovers.size())
	_check("...without counting as kills", _deaths == deaths_before, "enemy_died %d -> %d" % [deaths_before, _deaths])
	await _wait(1.0, Callable())
	_check("...and keep storming after it", _wave_enemies().all(func(e: EnemyBase) -> bool: return e.storm_timer > 0.0),
		"%d left" % _wave_enemies().size())
	if not leftovers.is_empty():
		var victim: EnemyBase = leftovers[0]
		var active_before: int = waves.active_enemies
		victim.take_damage(victim.health * 10.0 + 1000.0)
		await get_tree().process_frame
		_check("killing a straggler is not one of the wave's deaths",
			(not is_instance_valid(victim) or victim.is_dying) and _deaths == deaths_before and waves.active_enemies == active_before,
			"enemy_died %d -> %d, active %d -> %d" % [deaths_before, _deaths, active_before, waves.active_enemies])
	_check("the clock is cleared", waves.deadline_left < 0.0 and not _deadlines.is_empty() and _deadlines[_deadlines.size() - 1] < 0.0,
		"signals %s" % [_deadlines])
	_check("the beasts are still there", _beasts().size() >= beasts.size(), "%d -> %d" % [beasts.size(), _beasts().size()])
	_report()


func _wave_enemies() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyBase and not (node as EnemyBase).is_beast() and not (node as EnemyBase).is_dying and not node.is_queued_for_deletion():
			out.append(node as EnemyBase)
	return out


func _beasts() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyBase and (node as EnemyBase).is_beast() and not node.is_queued_for_deletion():
			out.append(node as EnemyBase)
	return out


func _mean_distance(enemies: Array[EnemyBase], at: Vector3) -> float:
	if enemies.is_empty():
		return 0.0
	var total: float = 0.0
	for enemy: EnemyBase in enemies:
		total += Vector2(enemy.global_position.x - at.x, enemy.global_position.z - at.z).length()
	return total / float(enemies.size())


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
