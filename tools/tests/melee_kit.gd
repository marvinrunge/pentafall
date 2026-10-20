extends Node
## Regression test for the warrior's basic attack and guard (MeleeKit, BlockGuard), driven
## through the real buttons on the real map.
##
## Run with (windowed - attacks only read the buttons with the mouse captured, and a
## headless run cannot capture it):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/melee_kit.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold, and a MEASURE line per
## move - clip length, rooting, hits and damage - so two builds can be compared line by line.
##
## A dummy enemy that does nothing stands in front of the player, and each move is checked
## for what it commits the player to and what it does to the dummy:
##   1. a tap is the light chain's opening stage, walked through or planted;
##   2. a second tap inside the combo window continues the chain rather than restarting it;
##   3. holding past player_heavy_hold_time commits the heavy spin while the button is still
##      down, roots the player, carries them forward, and hits harder than a tap;
##   4. the kick is its own move with its own cooldown and breaks the chain;
##   5. holding block raises the guard, which stops a hit from in front and not from behind;
##   6. Blade Dance's third stage lands harder than the first two;
##   7. the class skills: at level 14 Hurl Axe and Battle Frenzy are on the quick bar;
##   8. Bloodthirst: a kill by the axe heals, and the next cut comes faster;
##   9. Hurl Axe: the axe leaves the hand, hits a dummy on its way out and again on its way back,
##      and is back in the hand after;
##  10. Battle Frenzy: past the chain's last stage, a connecting chain plays the finisher again.

var _started: bool = false
var _failures: Array[String] = []


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	GameSettings.intro_tour_pending = false
	GameSettings.beast_first_spawn_delay = 9999.0
	var probe: Node = load("res://tools/tests/melee_kit.gd").new()
	# The solo seat plays the menu's class, so the warrior is put there for the run and the
	# player's own pick put back before the test quits (see archer_kit.gd).
	probe.set_meta("player_class", UserSettings.character_class)
	UserSettings.character_class = "warrior"
	probe.name = "MeleeKitTest"
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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var waves: Node = main.get_node("WaveManager")
	waves.set_physics_process(false)
	waves.set_process(false)
	_clear_enemies()
	await _frames(5)

	var dummy: EnemyBase = await _dummy(main, player)
	if dummy == null:
		_failures.append("no dummy enemy")
		_report()
		return

	# 1. a tap, standing
	await _settle(player)
	var tap: Dictionary = await _measure(player, dummy, func() -> void: await _tap("attack"))
	_check("a tap is a melee action", tap["melee"], str(tap))
	_check("...planted when standing", tap["rooted"], str(tap))
	_check("...and it lands on the dummy", tap["damage"] > 0.0, str(tap))

	# 2. the chain continues
	await _settle(player)
	await _tap("attack")
	await _until(func() -> bool: return 1.0 - player._action_timer / maxf(player._action_duration, 0.001) >= 1.0 - GameSettings.player_combo_window, 2.0)
	var second: Dictionary = await _measure(player, dummy, func() -> void: await _tap("attack"))
	_check("a second tap inside the window plays the next stage", second["melee"] and second["started_fresh"], str(second))

	# 3. the heavy
	await _settle(player)
	var start_pos: Vector3 = player.global_position
	var heavy: Dictionary = await _measure(player, dummy, func() -> void:
		Input.action_press("attack")
		await _frames(int(ceil((GameSettings.player_heavy_hold_time + 0.1) * 60.0)))
		heavy_committed_while_held = player._action_timer > 0.0
		Input.action_release("attack"))
	_check("holding commits the heavy while still held", heavy_committed_while_held, "")
	_check("...it roots", heavy["rooted"], str(heavy))
	_check("...it runs the heavy's duration", absf(heavy["duration"] - GameSettings.player_heavy_duration) < 0.05, str(heavy))
	_check("...it hits harder than a tap", heavy["damage"] > tap["damage"] * 1.5, "%.1f vs %.1f" % [heavy["damage"], tap["damage"]])
	var lunge: float = Vector2(player.global_position.x - start_pos.x, player.global_position.z - start_pos.z).length()
	_check("...and carries the player forward", lunge > 0.3, "%.2fm" % lunge)
	print("MEASURE lunge %.2f" % lunge)

	# 4. the kick
	await _settle(player)
	player.spell_cooldown_timers["kick"] = 0.0
	var kick: Dictionary = await _measure(player, dummy, func() -> void: await _tap("kick"))
	_check("the kick is a rooted melee action", kick["melee"] and kick["rooted"], str(kick))
	_check("...with its own cooldown", float(player.spell_cooldown_timers.get("kick", 0.0)) > 0.0, "")
	_check("...and its own damage", absf(kick["damage"] - GameSettings.spell_melee_kick_damage * player.get_spell_damage_multiplier()) < 1.0,
		"%.1f" % kick["damage"])

	# 5. the guard
	await _settle(player)
	Input.action_press("block")
	await _frames(3)
	_check("holding block raises the guard", player.is_blocking, "")
	var front_hp: float = player.hp
	player.take_damage(10.0, dummy)
	var front_taken: float = front_hp - player.hp
	var behind: Node3D = Node3D.new()
	main.add_child(behind)
	behind.global_position = player.global_position + player.global_transform.basis.z * 3.0
	var back_hp: float = player.hp
	player.take_damage(10.0, behind)
	var back_taken: float = back_hp - player.hp
	behind.free()
	Input.action_release("block")
	await _frames(3)
	_check("the guard stops most of a hit from in front", front_taken < 10.0 * (1.0 - GameSettings.player_block_damage_reduction) + 0.01, "took %.2f" % front_taken)
	_check("...and none of one from behind", back_taken > front_taken, "took %.2f" % back_taken)
	_check("letting go lowers it", not player.is_blocking, "")
	print("MEASURE block front %.2f behind %.2f" % [front_taken, back_taken])

	# 6. Blade Dance
	await _settle(player)
	player.melee_combo_extended = true
	var stages: Array[float] = []
	for i: int in 3:
		var stage: Dictionary = await _measure(player, dummy, func() -> void: await _tap("attack"))
		stages.append(float(stage["damage"]))
	_check("Blade Dance's third stage lands harder", stages[2] > stages[0] * 1.2, str(stages))
	print("MEASURE blade dance %s" % [stages])

	# 7. the class skills on the bar
	await _settle(player)
	RunState.team_level = GameSettings.class_skill_levels[3]
	SignalBus.team_level_changed.emit(RunState.team_level, 0)
	await _frames(2)
	var axe_slot: int = player.quick_slots.find("warrior_hurl_axe")
	var frenzy_slot: int = player.quick_slots.find("warrior_battle_frenzy")
	_check("Hurl Axe and Battle Frenzy are put on the quick bar", axe_slot >= 0 and frenzy_slot >= 0, str(player.quick_slots))

	# 8. Bloodthirst
	var kit: MeleeKit = player.kit as MeleeKit
	player.melee_combo_extended = false
	await _settle(player)
	dummy.health = 5.0
	player.hp = player.max_hp * 0.5
	var hp_before: float = player.hp
	await _tap("attack")
	await _until(func() -> bool: return not is_instance_valid(dummy) or dummy.health <= 0.0, 2.0)
	await _frames(2)
	var healed: float = player.hp - hp_before
	_check("Bloodthirst: a kill by the axe heals", absf(healed - player.max_hp * GameSettings.warrior_bloodthirst_heal) < 0.5, "%.2f" % healed)
	_check("...and readies a quicker cut", kit._bloodthirst_ready, "")
	dummy = await _dummy(main, player)
	await _settle(player)
	var quick: Dictionary = await _measure(player, dummy, func() -> void: await _tap("attack"))
	_check("...which comes faster", absf(quick["duration"] - tap["duration"] / GameSettings.warrior_bloodthirst_haste) < 0.02 and not kit._bloodthirst_ready,
		"%.3f vs %.3f" % [quick["duration"], tap["duration"]])

	# 9. Hurl Axe
	await _settle(player)
	if axe_slot >= 0:
		dummy.global_position = player.global_position - player.global_transform.basis.z * 5.0
		var axe_hp: float = dummy.health
		player._cast_slot(axe_slot, {})
		var hand_empty: bool = false
		var flew: bool = false
		for i: int in 240:
			await get_tree().physics_frame
			var hatchet: Node3D = player.find_child("Hatchet", true, false) as Node3D
			if get_tree().current_scene.find_child("HurledAxe*", true, false) != null:
				flew = true
				hand_empty = hand_empty or (hatchet != null and not hatchet.visible)
			elif flew:
				break
		var thrown_damage: float = axe_hp - dummy.health
		var per_leg: float = GameSettings.spell_melee_damage * GameSettings.warrior_hurl_axe_damage_mult * player.get_spell_damage_multiplier()
		var back_in_hand: Node3D = player.find_child("Hatchet", true, false) as Node3D
		_check("Hurl Axe throws the axe out of the hand", flew and hand_empty, "flew %s, hand empty %s" % [flew, hand_empty])
		_check("...hits on the way out and back", is_equal_approx(thrown_damage, per_leg * 2.0), "%.1f, expected %.1f" % [thrown_damage, per_leg * 2.0])
		_check("...and comes back to the hand", back_in_hand != null and back_in_hand.visible, "")
		print("MEASURE hurl axe %.1f" % thrown_damage)

	# 10. Battle Frenzy
	await _settle(player)
	# Back in reach: the axe's dummy stood well out of it.
	dummy.global_position = player.global_position - player.global_transform.basis.z * 1.6
	player.melee_combo_extended = true
	kit.start_battle_frenzy(GameSettings.warrior_battle_frenzy_duration)
	var frenzied: Array[int] = []
	for i: int in 4:
		await _measure(player, dummy, func() -> void: await _tap("attack"))
		frenzied.append(kit._combo_stage)
	# Three stages, then the finisher again rather than the opener.
	_check("Battle Frenzy: past the last stage the finisher comes again", frenzied == [1, 2, 3, 3], str(frenzied))
	kit._frenzy_timer = 0.0

	_report()


var heavy_committed_while_held: bool = false


## What a move did: rooted, melee, its duration, and the damage its impact frames dealt. It
## waits the move out, which still leaves the next tap inside player_combo_grace, so a
## chain measured stage by stage carries on rather than starting over.
func _measure(player: Player, dummy: EnemyBase, act: Callable) -> Dictionary:
	var hp: float = dummy.health
	await act.call()
	await _until(func() -> bool: return player._action_timer > 0.0, 1.0)
	var out: Dictionary = {
		"melee": player._action_is_melee, "rooted": player._action_roots_player,
		"duration": snappedf(player._action_duration, 0.001),
		"started_fresh": player._action_elapsed < 0.1,
	}
	await _until(func() -> bool: return player._action_timer <= 0.0, 3.0)
	await _frames(2)
	out["damage"] = snappedf(hp - dummy.health, 0.01)
	print("MEASURE %s" % [out])
	return out


## Back to rest: no action, no chain, the dummy in front and the cooldowns clear.
func _settle(player: Player) -> void:
	await _until(func() -> bool: return player._action_timer <= 0.0, 3.0)
	await _frames(int(ceil((GameSettings.player_combo_grace + 0.6) * 60.0)))
	player.spell_cooldown_timers.clear()


func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(1)


func _dummy(main: Node, player: Player) -> EnemyBase:
	var at: Vector3 = player.global_position - player.global_transform.basis.z * 1.6
	var enemy: EnemyBase = main.request_enemy({"color": "Red", "type": "Melee", "position": at}) as EnemyBase
	if enemy == null:
		return null
	await _frames(3)
	enemy.set_physics_process(false)
	enemy.health = 1.0e6
	enemy.global_position = at
	enemy.velocity = Vector3.ZERO
	return enemy


func _clear_enemies() -> void:
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _until(done: Callable, seconds: float) -> bool:
	var elapsed: float = 0.0
	while elapsed < seconds:
		if done.call():
			return true
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
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
