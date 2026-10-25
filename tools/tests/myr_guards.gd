extends Node
## Regression test: docs/MYR_GUARDS_PLAN.md - the stats a myr keeps, workers running from danger,
## the two guards, and the Graveyard.
##
## Run with:  godot --headless --path . res://tools/tests/myr_guards.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.
##
## Boots main.tscn, stops the waves, and drives everything through the real entry points
## (MainController.request_*), calling the server's per-tick checks (_update_danger, _guard_think)
## directly rather than waiting on their timers:
##   1. A delivery counts on the myr that made it.
##   2. A worker runs home from an enemy with no guard about, picks its harvest up again where it
##      left it once the lane is quiet, keeps going home when it is loaded, and ignores a stormer.
##   3. The Enforcer's price falls with the workers; one guard per lane; a worker in danger runs
##      behind its lane's guard; the guard takes on what attacks the worker, taunts it, hits it,
##      and is credited the kill; the Lodestone hits harder beside harvesting workers.
##   4. A dead myr goes to the Graveyard with its name, level and stats, and comes back for a
##      third of what went into it - level, name, lane and stats intact.

var _started: bool = false
var _failures: Array[String] = []
var _main: Node = null


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	GameSettings.intro_tour_pending = false
	GameSettings.wave_initial_warning_time = 3600.0
	var probe: Node = load("res://tools/tests/myr_guards.gd").new()
	probe.name = "MyrGuardsTest"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	var scene: Node = get_tree().current_scene
	if scene == null or scene.get_node_or_null("WaveManager") == null or not scene.has_method("myr_count"):
		return
	_started = true
	_main = scene
	scene.get_node("WaveManager").set_process(false)
	for _i: int in 30:
		await get_tree().physics_frame
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().physics_frame
	await _run()
	_report()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _run() -> void:
	for color: String in RunState.COLORS:
		RunState.mana_pool[color] = 60
	var well: Node3D = _main.mana_sources[0]
	var crystal: Vector3 = _main.crystal_anchor.global_position

	print("STATS")
	_main.request_build_myr()
	var worker: Myr = _newest(Myr.ROLE_WORKER)
	_check("a worker is built", worker != null and _main.myr_count() == 1, "")
	if worker == null:
		return
	await get_tree().physics_frame
	_check("...with what it cost and an id", worker.invested == GameSettings.myr_mana_cost and worker.record_id > 0,
		"invested %d id %d" % [worker.invested, worker.record_id])
	_main.request_myr_lane(worker, 0)
	_check("...and a lane", worker.lane_index == 0, "%d" % worker.lane_index)
	worker.global_position = well.global_position + Vector3(2.5, 0.5, 0.0)
	worker.start_depositing()
	_check("a delivery counts on the myr", worker.mana_delivered == worker.carry_amount() and worker.trips == 1,
		"%d mana, %d trips" % [worker.mana_delivered, worker.trips])

	print("FLEEING")
	worker.current_state = Myr.State.HARVESTING
	worker.state_timer = 4.0
	var enemy: EnemyBase = await _spawn_enemy(worker.global_position + Vector3(8.0, 0.0, 0.0))
	worker._update_danger(0.25)
	_check("a worker runs from an enemy", worker.current_state == Myr.State.FLEEING and worker.times_fled == 1,
		"state %d fled %d" % [worker.current_state, worker.times_fled])
	_check("...home, with no guard about", not worker.is_sheltering() and worker._flee_point.distance_to(crystal) < 0.5,
		"%s" % worker._flee_point)
	enemy.free()
	for _i: int in int(ceil(GameSettings.myr_return_delay / 0.25)) + 1:
		worker._update_danger(0.25)
	_check("...and goes back once it is quiet", worker.current_state == Myr.State.WALKING_TO_MANA, "state %d" % worker.current_state)
	# Within a tick or two of the 4 s it had: the harvest ran on while the enemy was spawned.
	var left: float = worker._harvest_left
	_check("...to pick its harvest up where it stopped", left > 3.8 and left <= 4.0, "%.2f" % left)
	worker.start_harvesting()
	_check("...and does", is_equal_approx(worker.state_timer, left), "%.2f" % worker.state_timer)

	worker.current_state = Myr.State.WALKING_TO_CRYSTAL
	worker._set_carrying(true)
	enemy = await _spawn_enemy(worker.global_position + Vector3(8.0, 0.0, 0.0))
	worker._update_danger(0.25)
	_check("a loaded worker keeps going home, faster", worker.current_state == Myr.State.WALKING_TO_CRYSTAL and worker._running_home,
		"state %d running %s" % [worker.current_state, worker._running_home])
	enemy.free()
	worker._update_danger(0.25)
	_check("...and walks again once it is quiet", not worker._running_home, "")

	worker.current_state = Myr.State.HARVESTING
	var fled_before: int = worker.times_fled
	enemy = await _spawn_enemy(worker.global_position + Vector3(8.0, 0.0, 0.0))
	enemy.begin_storm(30.0)
	worker._update_danger(0.25)
	_check("a storming enemy is no danger", worker.current_state == Myr.State.HARVESTING and worker.times_fled == fled_before,
		"state %d" % worker.current_state)
	enemy.free()

	print("GUARDS")
	var enforcer_cost: int = _main.guard_cost(Myr.ROLE_ENFORCER)
	_check("the Enforcer costs one less per worker", enforcer_cost == maxi(GameSettings.myr_enforcer_cost_min, GameSettings.myr_enforcer_cost - 1),
		"%d" % enforcer_cost)
	var mana_before: int = RunState.total_mana()
	_main.request_build_guard(Myr.ROLE_ENFORCER)
	var guard: Myr = _newest(Myr.ROLE_ENFORCER)
	_check("an Enforcer is built", guard != null and RunState.total_mana() == mana_before - enforcer_cost, "")
	if guard == null:
		return
	await get_tree().physics_frame
	_check("...as a guard, not a worker", guard.is_guard() and _main.myr_count() == 1 and _main.guard_count() == 1
		and is_equal_approx(guard.max_health, GameSettings.myr_enforcer_hp), "%.0f hp" % guard.max_health)
	_main.request_myr_lane(guard, 0)
	_check("...guards a lane", guard.lane_index == 0 and guard.current_state == Myr.State.GUARDING, "lane %d" % guard.lane_index)
	_check("...without taking a well slot", _main.well_slot_count(0) == 1, "%d" % _main.well_slot_count(0))
	_main.request_build_guard(Myr.ROLE_LODESTONE)
	var lodestone: Myr = _newest(Myr.ROLE_LODESTONE)
	await get_tree().physics_frame
	_main.request_myr_lane(lodestone, 0)
	_check("one guard per lane", lodestone.lane_index == -1, "%d" % lodestone.lane_index)
	_main.request_myr_lane(lodestone, 1)
	_check("...another lane is fine", lodestone.lane_index == 1, "%d" % lodestone.lane_index)

	var post: Vector3 = guard.guard_post()
	guard.global_position = post
	worker.global_position = well.global_position + Vector3(0.0, 0.5, 0.0)
	worker.current_state = Myr.State.HARVESTING
	enemy = await _spawn_enemy(post + (post - well.global_position).normalized() * 3.0)
	worker._update_danger(0.25)
	_check("a worker in danger runs behind its guard", worker.is_sheltering()
		and absf(worker._flee_point.distance_to(guard.global_position) - GameSettings.myr_guard_shelter_distance) < 0.6,
		"flee point %s, guard %s" % [worker._flee_point, guard.global_position])
	enemy.current_target = worker
	guard._guard_think()
	_check("the guard takes on what attacks its worker", guard.current_state == Myr.State.FIGHTING and guard._guard_target == enemy
		and guard.intercepts >= 1, "state %d intercepts %d" % [guard.current_state, guard.intercepts])
	_check("...and taunts it off the worker", enemy.taunt_source == guard, "%s" % enemy.taunt_source)
	var health_before: float = enemy.health
	guard._guard_strike()
	_check("...and hits it", enemy.health < health_before, "%.1f -> %.1f" % [health_before, enemy.health])
	enemy.take_damage(enemy.health + 10000.0, guard, true)
	_check("...and is credited the kill", guard.kills == 1, "%d" % guard.kills)
	await get_tree().physics_frame
	guard._guard_think()
	_check("...then goes back to its post", guard.current_state == Myr.State.GUARDING, "state %d" % guard.current_state)

	var base_damage: float = lodestone.guard_damage()
	for offset: Vector3 in [Vector3(2.0, 0.0, 0.0), Vector3(-2.0, 0.0, 0.0)]:
		_main.request_build_myr()
		var helper: Myr = _newest(Myr.ROLE_WORKER)
		await get_tree().physics_frame
		helper.global_position = lodestone.global_position + offset
		helper.current_state = Myr.State.HARVESTING
		helper.state_timer = 600.0
	_check("the Lodestone hits harder beside harvesting workers",
		is_equal_approx(lodestone.lodestone_bonus(), 2.0 * GameSettings.myr_lodestone_bonus_per_worker)
		and lodestone.guard_damage() > base_damage, "bonus %.2f" % lodestone.lodestone_bonus())

	print("GRAVEYARD")
	_main.request_myr_level(worker)
	_main.request_myr_level(worker)
	var invested: int = worker.invested
	_check("levels count as invested", worker.level == 3 and invested == GameSettings.myr_mana_cost
		+ GameSettings.myr_level_cost * 2 + GameSettings.myr_level_cost * 3, "level %d invested %d" % [worker.level, invested])
	worker.display_name = "Marvin"
	var delivered: int = worker.mana_delivered
	var record_id: int = worker.record_id
	worker.take_damage(100000.0)
	var record: Dictionary = RunState.graveyard_record(record_id)
	_check("a dead myr goes to the Graveyard", not record.is_empty() and String(record["name"]) == "Marvin"
		and int(record["level"]) == 3 and int(record["deaths"]) == 1 and int(record["mana_delivered"]) == delivered,
		"%s" % [record])
	var cost: int = RunState.return_cost(record)
	_check("returning it costs a third of what went in", cost == maxi(GameSettings.myr_mana_cost,
		roundi(float(invested) * GameSettings.myr_return_cost_fraction)), "%d of %d" % [cost, invested])
	_main.base_ui_instance.open(_main)
	await get_tree().process_frame
	_check("the base screen lists it with a Return button", _main.base_ui_instance._graveyard_box.find_child("ReturnButton", true, false) != null, "")
	_check("...and offers both guards", String(_main.base_ui_instance._enforcer_btn.text).contains("Myr Enforcer")
		and String(_main.base_ui_instance._lodestone_btn.text).contains("Lodestone Myr"), "")
	_main.base_ui_instance.close()
	await get_tree().create_timer(0.1).timeout
	mana_before = RunState.total_mana()
	_main.request_return_myr(record_id)
	var back: Myr = null
	for node: Node in get_tree().get_nodes_in_group("myrs"):
		if (node as Myr).record_id == record_id and not (node as Myr).is_dying:
			back = node as Myr
	_check("it comes back", back != null and RunState.graveyard_record(record_id).is_empty()
		and RunState.total_mana() == mana_before - cost, "mana %d -> %d" % [mana_before, RunState.total_mana()])
	if back != null:
		await get_tree().physics_frame
		_check("...as it was", back.display_name == "Marvin" and back.level == 3 and back.lane_index == 0
			and back.mana_delivered == delivered and back.deaths == 1 and back.invested == invested
			and is_equal_approx(back.max_health, GameSettings.myr_max_hp + 2.0 * GameSettings.myr_level_hp_bonus),
			"%s lv %d lane %d hp %.0f" % [back.display_name, back.level, back.lane_index, back.max_health])
	print("AUTO-ASSIGN")
	for mode: String in ["most", "fewest", "manual"]:
		_main.request_set_myr_auto_assign(mode)
		var counts: Array[int] = []
		for lane: int in _main.mana_sources.size():
			counts.append(_main.well_slot_count(lane))
		_main.request_build_myr()
		var fresh: Myr = _newest(Myr.ROLE_WORKER)
		var wanted: int = -1
		if mode == "most":
			wanted = counts.find(counts.max())
		elif mode == "fewest":
			wanted = counts.find(counts.min())
		_check("\"%s\": a new myr goes where it should" % mode, fresh != null and fresh.lane_index == wanted
			and (mode == "manual" or counts[wanted] == (counts.max() if mode == "most" else counts.min())),
			"lane %d, wanted %d, counts %s" % [fresh.lane_index if fresh != null else -2, wanted, counts])
	_main.base_ui_instance.open(_main)
	await get_tree().process_frame
	_check("the base screen shows the choice", _main.base_ui_instance._auto_assign_option.selected
		== RunState.MYR_AUTO_ASSIGN_MODES.find("manual"), "%d" % _main.base_ui_instance._auto_assign_option.selected)
	_main.base_ui_instance.close()

	var panel: Node = _main.get_node_or_null("UpkeepPanel")
	if panel != null:
		var totals: Dictionary = panel.myr_totals()
		_check("Upkeep's totals count the myrs' mana once", int(totals["mana"]) >= delivered, "%s" % [totals])


func _newest(role: String) -> Myr:
	var newest: Myr = null
	for node: Node in get_tree().get_nodes_in_group("myrs"):
		var myr: Myr = node as Myr
		if myr != null and myr.role == role and not myr.is_dying and (newest == null or myr.record_id > newest.record_id):
			newest = myr
	return newest


func _spawn_enemy(at: Vector3) -> EnemyBase:
	var enemy: EnemyBase = (load("res://scenes/misc/enemy.tscn") as PackedScene).instantiate()
	enemy.set_meta("enemy_color", "Red")
	enemy.set_meta("enemy_type", "Melee")
	_main.add_child(enemy)
	enemy.global_position = at
	await get_tree().physics_frame
	enemy.set_physics_process(false)
	return enemy


func _report() -> void:
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s %s (%s)" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s: %s" % [what, detail])
