extends Node
## Regression test for a second run in the same session: every way back into the map - Restart
## on the defeat screen, Main Menu then PLAY SOLO, and Restart once more after that - has to open
## on wave 1 with its enemies on the map, the way the first run does.
##
## Leaving to the menu used to set the multiplayer peer to null rather than back to offline, and
## with no peer the enemy spawner refuses every spawn: the next run planned and announced its
## waves, nothing arrived, and each wave "cleared" empty into the next.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . res://tools/tests/second_run.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

const MAP_SCENE := "res://scenes/misc/main.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
## Seconds a map gets to load and put its first battle group on the field.
const RUN_TIMEOUT := 60.0

var _failures: Array[String] = []
var _started: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/second_run.gd").new()
	probe.name = "SecondRunTest"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file(MENU_SCENE)


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	_started = true
	await _run()
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()


func _check(ok: bool, what: String, detail: String) -> void:
	print("%s   %s (%s)" % ["ok" if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s (%s)" % [what, detail])


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


## Polls `condition` every tenth of a second until it holds or `timeout` runs out.
func _wait_for(condition: Callable, timeout: float) -> bool:
	var waited: float = 0.0
	while not condition.call():
		if waited >= timeout:
			return false
		await _seconds(0.1)
		waited += 0.1
	return true


func _run() -> void:
	# The splash, into the menu.
	await _seconds(2.5)
	# Scenes are told apart by instance id: the lambdas waiting on the next scene outlive the
	# one it replaces, and a freed node captured in one is an engine error every call.
	var previous: int = get_tree().current_scene.get_instance_id()
	get_tree().current_scene.call("_on_solo_pressed")
	var map: Node = await _expect_wave_one("the first run", previous)
	if map == null:
		return

	previous = map.get_instance_id()
	if not await _lose(map):
		return
	(map.get_node("HUD").get("restart_btn") as Button).pressed.emit()
	map = await _expect_wave_one("a second run from Restart", previous)
	if map == null:
		return

	previous = map.get_instance_id()
	if not await _lose(map):
		return
	var to_menu: Button = _defeat_button(map, "Main Menu")
	_check(to_menu != null, "the defeat screen offers Main Menu", "")
	if to_menu == null:
		return
	to_menu.pressed.emit()
	var reached_menu: bool = await _wait_for(func() -> bool:
		var scene: Node = get_tree().current_scene
		return scene != null and scene.get_instance_id() != previous and scene.scene_file_path == MENU_SCENE, 10.0)
	_check(reached_menu, "Main Menu on the defeat screen lands on the menu", "")
	if not reached_menu:
		return
	await _seconds(0.5)
	previous = get_tree().current_scene.get_instance_id()
	get_tree().current_scene.call("_on_solo_pressed")
	map = await _expect_wave_one("a run from PLAY SOLO after leaving to the menu", previous)
	if map == null:
		return

	previous = map.get_instance_id()
	if not await _lose(map):
		return
	(map.get_node("HUD").get("restart_btn") as Button).pressed.emit()
	await _expect_wave_one("a Restart after that", previous)


## Waits for the map that replaces the scene with instance id `previous`, then for its first
## battle group, and checks that the run is in wave 1 with enemies of that wave standing on the
## map. Returns the map, or null when it never came up.
func _expect_wave_one(label: String, previous: int) -> Node:
	var loaded: bool = await _wait_for(func() -> bool:
		var scene: Node = get_tree().current_scene
		return scene != null and scene.get_instance_id() != previous and scene.scene_file_path == MAP_SCENE \
			and scene.get_node_or_null("WaveManager") != null, RUN_TIMEOUT)
	_check(loaded, "%s reaches the map and starts its waves" % label, "")
	if not loaded:
		return null
	var map: Node = get_tree().current_scene
	var waves: Node = map.get_node("WaveManager")
	# The first group lands, or the wave gives up empty - either ends the wait.
	await _wait_for(func() -> bool:
		return int(waves.get("active_enemies")) > 0 or bool(waves.get("in_upkeep")) or int(waves.get("current_wave")) > 0,
		RUN_TIMEOUT)
	var detail: String = "wave %d, %d active, %d wave enemies on the map, upkeep %s, peer %s" % [
		int(waves.get("current_wave")) + 1, int(waves.get("active_enemies")), _wave_enemies(),
		waves.get("in_upkeep"), multiplayer.multiplayer_peer]
	_check(int(waves.get("current_wave")) == 0 and not bool(waves.get("in_upkeep")), "%s is in wave 1" % label, detail)
	_check(int(waves.get("active_enemies")) > 0 and _wave_enemies() > 0, "%s puts wave 1's enemies on the map" % label, detail)
	return map


## The crystal falls and the defeat screen comes up. False if it never does.
func _lose(map: Node) -> bool:
	map.call("damage_crystal", 1.0e9)
	var panel: Control = map.get_node("HUD").get("game_over_panel")
	var shown: bool = await _wait_for(func() -> bool: return panel.visible, GameSettings.crystal_death_seconds + 5.0)
	_check(shown, "the defeat screen comes up", "")
	return shown


func _defeat_button(map: Node, text: String) -> Button:
	var panel: Control = map.get_node("HUD").get("game_over_panel")
	for node: Node in panel.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node as Button
	return null


## Enemies of the waves on the map, without the wild beasts that share their group.
func _wave_enemies() -> int:
	var count: int = 0
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if not (enemy.has_method("is_beast") and enemy.is_beast()):
			count += 1
	return count
