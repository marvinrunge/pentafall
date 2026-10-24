extends Node
## Regression test: the first-steps objectives and the starting mana (docs/ONBOARDING_PLAN.md).
##
## Run with:  godot --headless --path . res://tools/tests/objectives.tscn
##
## The tracker on its own, without a match: which objectives it shows and in what order, that
## one done out of order is still done, that a finished one ticks and then gives its place to
## the next, that the multiplayer-only one waits for a multiplayer run, and that what is done is
## kept in UserSettings. The profile's own settings are put back afterwards.

var _failures: Array[String] = []
## A member rather than a local: a lambda captures a local's value, not the variable.
var _multiplayer_run: bool = false


func _ready() -> void:
	_run.call_deferred()


func _check(label: String, condition: bool, detail: String = "") -> void:
	print("  %s   %s%s" % ["ok " if condition else "FAIL", label, "" if detail == "" else "  (%s)" % detail])
	if not condition:
		_failures.append(label)


func _run() -> void:
	var saved_done: String = UserSettings.objectives_done
	var saved_show: bool = UserSettings.show_objectives
	UserSettings.objectives_done = ""
	UserSettings.show_objectives = true

	print("STARTING MANA")
	RunState.reset()
	var every_colour: bool = true
	for color: String in RunState.COLORS:
		every_colour = every_colour and int(RunState.mana_pool[color]) == GameSettings.run_starting_mana_per_color
	_check("the run starts with mana of every colour", every_colour, "%s" % [RunState.mana_pool])
	_check("...enough for two myrs", RunState.total_mana() >= GameSettings.myr_mana_cost * 2, "%d" % RunState.total_mana())

	print("TRACKER")
	var tracker := ObjectiveTracker.new()
	tracker.multiplayer_run = func() -> bool: return _multiplayer_run
	add_child(tracker)
	await get_tree().process_frame
	_check("the first two are shown, in order", tracker.shown_ids() == ["build_myr", "assign_myr"], "%s" % [tracker.shown_ids()])
	_check("it is visible", tracker.visible)

	SignalBus.objective_progress.emit("spend_skill_point")
	await get_tree().process_frame
	_check("one done out of order is done", tracker.is_done("spend_skill_point"))
	_check("...without disturbing what is shown", tracker.shown_ids() == ["build_myr", "assign_myr"], "%s" % [tracker.shown_ids()])

	SignalBus.objective_progress.emit("build_myr")
	await get_tree().process_frame
	_check("a finished one stays up with its tick", tracker.shown_ids().has("build_myr") and tracker.shown_ids().size() == 3,
		"%s" % [tracker.shown_ids()])
	await get_tree().create_timer(ObjectiveTracker.TICK_SECONDS + 0.3).timeout
	_check("...then the next takes its place", tracker.shown_ids() == ["assign_myr", "harvest_by_hand"], "%s" % [tracker.shown_ids()])
	_check("what is done is kept in the profile", "build_myr" in UserSettings.objectives_done.split(",")
		and "spend_skill_point" in UserSettings.objectives_done.split(","), UserSettings.objectives_done)

	SignalBus.objective_progress.emit("nonsense")
	_check("an unknown id is ignored", not tracker.is_done("nonsense"))

	for objective_id: String in ["assign_myr", "harvest_by_hand", "level_myr", "upkeep_purchase", "build_guard"]:
		SignalBus.objective_progress.emit(objective_id)
	await get_tree().create_timer(ObjectiveTracker.TICK_SECONDS + 0.3).timeout
	_check("solo, the multiplayer-only one never shows", tracker.shown_ids().is_empty() and not tracker.visible,
		"%s" % [tracker.shown_ids()])
	_multiplayer_run = true
	SignalBus.players_changed.emit(2)
	await get_tree().process_frame
	_check("...in a multiplayer run it does", tracker.shown_ids() == ["revive_teammate"], "%s" % [tracker.shown_ids()])
	UserSettings.set_value(&"show_objectives", false)
	await get_tree().process_frame
	_check("switched off, it hides", not tracker.visible)
	UserSettings.set_value(&"show_objectives", true)
	UserSettings.set_value(&"objectives_done", "")
	await get_tree().process_frame
	_check("a reset brings every one back", tracker.shown_ids() == ["build_myr", "assign_myr"] and tracker.visible,
		"%s" % [tracker.shown_ids()])

	UserSettings.set_value(&"objectives_done", saved_done)
	UserSettings.set_value(&"show_objectives", saved_show)
	await get_tree().create_timer(0.6).timeout
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL (%d)" % _failures.size())
	get_tree().quit(1 if not _failures.is_empty() else 0)
