extends Node
## Regression test for the mage class on the real map: the class choice reaching the spawned
## body, the bolts and the blast (MageKit, MageBolt), the blink (Blink) and the four class
## skills.
##
## Run with (windowed - the kit reads the real attack button, and a player only reads its
## buttons with the mouse captured, which a headless run cannot do):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/mage_kit.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold, plus MEASURE lines. With a
## folder after `--`, it also saves what the camera sees as a bolt flies and as the blast
## bursts (bolt.png, blast.png).
##
##   1. the solo player spawns as the mage: bolt kit, blink, the mage's visual and its clips,
##      the least health of any class and a little more speed than the warrior;
##   2. the orb floats over the palm and trails the hand on its spring; a tap throws it as a
##      bolt that lands on a dummy, for the bolt's damage, and a new one grows back; three taps
##      take MageKit.bolt_clips in turn (one throw, for now: the same one every time);
##   3. the bolt is drawn in the colour of the path: arcane with nothing invested, red once
##      red is the colour the mage has put the most into;
##   4. holding throws the Arcane Blast, which hits the dummy and a second one beside it;
##   5. the blink moves the mage away the way the stick points, nothing touches them as it
##      lands, and it has a cooldown;
##   6. Prowess (level 3): a colour spell cast empowers the next bolt;
##   7. Blink of an Eye (level 6) is put on the quick bar, blinks the mage to the aimed ground
##      and leaves a decoy the dummy is taunted onto;
##   8. Spell Mastery (level 10): a colour spell can be cast twice in a row, and only then
##      waits; the bar counts its charges;
##   9. Mana Surge (level 14) is put on the bar and makes the last spell ready again.

var _started: bool = false
var _failures: Array[String] = []


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	GameSettings.intro_tour_pending = false
	GameSettings.beast_first_spawn_delay = 9999.0
	# The solo seat plays the menu's class; the player's own pick is put back before quitting.
	var probe: Node = load("res://tools/tests/mage_kit.gd").new()
	probe.set_meta("player_class", UserSettings.character_class)
	UserSettings.character_class = "mage"
	probe.name = "MageKitTest"
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

	# 1. the class
	_check("the solo player is the mage", player.character_class == "mage", player.character_class)
	_check("...with the bolts", player.kit is MageKit, str(player.kit))
	_check("...and the blink", player.defence is Blink, str(player.defence))
	_check("...in the mage's visual", player.animator.has_clip("bolt_1") and player.animator.has_clip("arcane_blast") and player.animator.has_clip("cast_red"), "")
	_check("...the least health of any class", is_equal_approx(player.max_hp, GameSettings.player_max_hp * GameSettings.mage_health_mult), "%.1f" % player.max_hp)
	_check("...and a little more speed", is_equal_approx(player.speed, GameSettings.player_base_speed * GameSettings.mage_speed_mult), "%.2f" % player.speed)
	var kit: MageKit = player.kit as MageKit

	RunState.team_level = 1
	var dummy: EnemyBase = await _dummy(main, player, 9.0)
	if dummy == null:
		_failures.append("no dummy enemy")
		_report()
		return

	# 2. the orb over the palm, and a tap
	_aim_at(player, dummy, 1.0)
	var orb: MageHandOrb = player.animator.hand_orb()
	_check("the mage holds an orb over the palm", orb != null and orb.visible, "")
	if orb != null:
		await _until(func() -> bool: return player._action_timer <= 0.0, 2.0)
		await _seconds(0.5)
		var rest_gap: float = _orb_gap(orb)
		_check("...floating where the palm puts it at rest", rest_gap < 0.04, "%.3f m off" % rest_gap)
		await _capture()
		Input.action_press("attack")
		await _frames(2)
		Input.action_release("attack")
		var most_gap: float = 0.0
		var least_grown: float = 1.0
		for i in int(GameSettings.mage_bolt_duration * Engine.physics_ticks_per_second):
			await _frames(1)
			most_gap = maxf(most_gap, _orb_gap(orb))
			least_grown = minf(least_grown, orb._grown)
		_check("...trailing the hand as it throws", most_gap > 0.03, "%.3f m behind at most" % most_gap)
		_check("...thrown with the bolt, the palm emptying", least_grown < 0.3, "%.2f grown at least" % least_grown)
		await _seconds(MageHandOrb.REGROW_TIME + 0.2)
		_check("...and growing back", is_equal_approx(orb._grown, 1.0), "%.2f" % orb._grown)
		print("MEASURE orb rest %.3f m, trailing up to %.3f m" % [rest_gap, most_gap])
	var bolt_expected: float = GameSettings.spell_melee_damage * GameSettings.mage_bolt_damage_mult * player.get_spell_damage_multiplier()
	var first: float = await _tap(player, dummy)
	_check("a tap throws a bolt that lands", absf(first - bolt_expected) < 1.0, "%.1f, expected %.1f" % [first, bolt_expected])
	var clips: Array[String] = []
	for i in 3:
		await _until(func() -> bool: return player._action_timer <= 0.0, 2.0)
		await _capture()
		Input.action_press("attack")
		await _frames(2)
		Input.action_release("attack")
		await _frames(3)
		clips.append(player.animator.action_clip())
		await _seconds(GameSettings.mage_bolt_duration)
	var turns: Array[String] = (player.kit as MageKit).bolt_clips
	var in_turn: bool = clips.size() == 3 and turns.has(clips[0])
	for i in clips.size():
		in_turn = in_turn and clips[i] == turns[(turns.find(clips[0]) + i) % turns.size()]
	_check("...the throws in turn", in_turn, "%s of %s" % [str(clips), str(turns)])
	await _seconds(0.6)

	# 3. the colour of the path
	_check("with nothing invested the bolt is arcane", player.path_color() == "", player.path_color())
	player.invest_affinity("red")
	player.invest_affinity("red")
	player.invest_affinity("blue")
	_check("...and red once red has the most", player.path_color() == "red", player.path_color())
	await _until(func() -> bool: return player._action_timer <= 0.0, 2.0)
	await _capture()
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	var flying: MageBolt = null
	for i in 40:
		await _frames(1)
		flying = _bolt()
		if flying != null:
			break
	_check("...which the bolt is drawn in", flying != null and flying.color == "red", flying.color if flying != null else "no bolt")
	await _snapshot("bolt.png")
	await _seconds(0.8)

	# 4. the blast
	var beside: EnemyBase = await _dummy(main, player, 9.0)
	var right: Vector3 = player.global_basis.x
	right.y = 0.0
	if beside != null:
		beside.global_position = dummy.global_position + right.normalized() * (GameSettings.mage_blast_radius * 0.6)
	await _frames(2)
	_aim_at(player, dummy, 0.6)
	await _until(func() -> bool: return player._action_timer <= 0.0, 2.0)
	await _capture()
	var hp_a: float = dummy.health
	var hp_b: float = beside.health if beside != null else 0.0
	Input.action_press("attack")
	await _seconds(GameSettings.player_heavy_hold_time + 0.15)
	_check("holding throws the blast", player.animator.action_clip() == "arcane_blast", player.animator.action_clip())
	Input.action_release("attack")
	await _seconds(GameSettings.mage_blast_duration)
	await _snapshot("blast.png")
	await _seconds(0.4)
	var blast_a: float = hp_a - dummy.health
	var blast_b: float = (hp_b - beside.health) if beside != null else 0.0
	_check("...which hits the dummy hard", blast_a > first * 2.0, "%.1f vs a bolt's %.1f" % [blast_a, first])
	_check("...and the one beside it", blast_b > 0.0, "%.1f" % blast_b)
	print("MEASURE bolt %.1f blast %.1f + %.1f" % [first, blast_a, blast_b])
	if beside != null:
		beside.queue_free()
	await _frames(3)

	# 5. the blink
	await _until(func() -> bool: return player._action_timer <= 0.0, 2.0)
	var blink: Blink = player.defence as Blink
	var before: Vector3 = player.global_position
	var hp_before: float = player.hp
	_check("the blink is ready", blink.can_blink(), "")
	# Sideways, along the line of the seat: behind the player is the base.
	blink.blink(Vector2(1.0, 0.0))
	await _frames(1)
	player.take_damage(25.0, dummy)
	var untouched: bool = is_equal_approx(player.hp, hp_before)
	var moved: float = Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
	var aside: float = (player.global_position - before).dot(player.global_basis.x)
	_check("the blink moves the mage at once, the way the stick points", moved > GameSettings.mage_blink_distance * 0.6 and aside > 0.0, "%.2fm, %.2f to the right" % [moved, aside])
	_check("...and nothing touches them as they land", untouched, "hp %.1f -> %.1f" % [hp_before, player.hp])
	await _seconds(GameSettings.mage_blink_invulnerable_time + 0.1)
	player.take_damage(10.0, dummy)
	_check("...after which hits land again", player.hp < hp_before, "")
	_check("...and it has a cooldown", not blink.can_blink(), "")
	print("MEASURE blink %.2fm" % moved)
	player.hp = player.max_hp
	await _seconds(GameSettings.mage_blink_cooldown)
	var still: Vector3 = player.global_position
	blink.blink(Vector2.ZERO)
	await _frames(1)
	var back: float = (player.global_position - still).dot(player.global_basis.z)
	_check("...backwards with no direction held", back > 0.3, "%.2f" % back)
	player.teleport_to(still)
	await _frames(2)

	# 6. Prowess
	RunState.team_level = GameSettings.class_skill_levels[0]
	player.grant_spell_rank("green_5")
	_aim_at(player, dummy, 1.0)
	var plain: float = await _tap(player, dummy)
	player.execute_spell("green_5")
	_check("a colour spell gives a Prowess charge", kit.prowess_charges == 1, "%d" % kit.prowess_charges)
	var empowered: float = await _tap(player, dummy)
	_check("...which the next bolt spends, hitting harder", empowered > plain * 1.5 and kit.prowess_charges == 0, "%.1f vs %.1f, %d left" % [empowered, plain, kit.prowess_charges])
	print("MEASURE prowess plain %.1f empowered %.1f" % [plain, empowered])

	# 7. Blink of an Eye
	RunState.team_level = GameSettings.class_skill_levels[1]
	SignalBus.team_level_changed.emit(RunState.team_level, 0)
	await _frames(2)
	var eye_slot: int = player.quick_slots.find("mage_blink_of_an_eye")
	_check("Blink of an Eye is put on the quick bar", eye_slot >= 0, str(player.quick_slots))
	if eye_slot >= 0:
		dummy.global_position = player.global_position - player.global_basis.z * 4.0
		await _frames(2)
		var start: Vector3 = player.global_position
		var aim_to: Vector3 = player.global_position + player.global_basis.x * 10.0
		player._aim_override = [player.global_position + Vector3(0.0, 1.6, 0.0), ((aim_to + Vector3(0.0, 0.1, 0.0)) - (player.global_position + Vector3(0.0, 1.6, 0.0))).normalized()]
		player._cast_slot(eye_slot, {})
		await _frames(4)
		player._aim_override = []
		var went: float = Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
		_check("...it blinks the mage to the aimed ground", went > 6.0, "%.2fm" % went)
		var decoy: TemporaryAlly = _decoy()
		_check("...leaving a decoy where they stood", decoy != null and Vector2(decoy.global_position.x - start.x, decoy.global_position.z - start.z).length() < 1.0, "")
		_check("...in the mage's own shape", decoy != null and decoy.visual_player_class == "mage", "")
		_check("...which the dummy is taunted onto", decoy != null and dummy.taunt_source == decoy, str(dummy.taunt_source))
		_check("...on cooldown after", float(player.spell_cooldown_timers.get("mage_blink_of_an_eye", 0.0)) > 0.0, "")

	# 8. Spell Mastery
	player._clear_spell_cooldowns()
	RunState.team_level = GameSettings.class_skill_levels[2]
	SignalBus.team_level_changed.emit(RunState.team_level, 0)
	await _frames(2)
	_check("Spell Mastery gives a colour spell two charges", player.spell_charges("green_5") == 2, "%d" % player.spell_charges("green_5"))
	player.execute_spell("green_5")
	_check("...the first cast leaves it ready", float(player.spell_cooldown_timers.get("green_5", 0.0)) <= 0.0 and player.spell_charges("green_5") == 1, "%d" % player.spell_charges("green_5"))
	player.execute_spell("green_5")
	var waiting: float = float(player.spell_cooldown_timers.get("green_5", 0.0))
	_check("...the second makes it wait", waiting > 0.0 and player.spell_charges("green_5") == 0, "%.1fs, %d" % [waiting, player.spell_charges("green_5")])
	_check("...for no longer than one cooldown", waiting <= SpellDatabase.get_cooldown("green_5") / player._spell_cooldown_recovery_rate() + 0.01, "%.1fs" % waiting)
	# DRAWN frames: the bar updates in the HUD's _process, and when a frame takes longer to draw
	# than a physics tick, two physics frames pass within one drawn frame and the bar has not
	# looked yet - this check failed about every other run that way.
	await _drawn_frames(2)
	_check("...and the bar counts the charges", _bar_charges(main) == "x0", "%s, the player has %d, waits %.1fs, paused %s, HUD on %s" % [
		_bar_charges(main), player.spell_charges("green_5"), float(player.spell_cooldown_timers.get("green_5", 0.0)),
		get_tree().paused, str(main.find_child("HUD", true, false).get("_player"))])
	_check("...but a class skill has none", player.spell_charges("mage_blink_of_an_eye") == -1, "")

	# 9. Mana Surge
	RunState.team_level = GameSettings.class_skill_levels[3]
	SignalBus.team_level_changed.emit(RunState.team_level, 0)
	await _frames(2)
	var surge_slot: int = player.quick_slots.find("mage_mana_surge")
	_check("Mana Surge is put on the quick bar", surge_slot >= 0, str(player.quick_slots))
	if surge_slot >= 0:
		await _until(func() -> bool: return player._action_timer <= 0.0, 2.0)
		player._cast_slot(surge_slot, {})
		await _seconds(1.2)
		_check("...it makes the last spell ready again", float(player.spell_cooldown_timers.get("green_5", 0.0)) <= 0.0 and player.spell_charges("green_5") == 2, "%.1fs, %d" % [float(player.spell_cooldown_timers.get("green_5", 0.0)), player.spell_charges("green_5")])
		_check("...and goes on cooldown itself", float(player.spell_cooldown_timers.get("mage_mana_surge", 0.0)) > 0.0, "")

	_report()


## One tap at whatever the aim override points at; the damage the dummy took.
func _tap(player: Player, dummy: EnemyBase) -> float:
	await _until(func() -> bool: return player._action_timer <= 0.0, 2.0)
	await _capture()
	var hp: float = dummy.health
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _seconds(GameSettings.mage_bolt_duration + 0.6)
	return hp - dummy.health


## Points the crosshair at `enemy`, `height` metres up its body - set as the aim override,
## the same field a client's own aim arrives in.
func _aim_at(player: Player, enemy: Node3D, height: float) -> void:
	var eye: Vector3 = player.global_position + Vector3(0.0, 1.5, 0.0)
	var target: Vector3 = enemy.global_position + Vector3(0.0, height, 0.0)
	player._aim_override = [eye, (target - eye).normalized()]


## The buttons are only read with the mouse captured, and a window that lost focus to
## something else on the desktop has let it go - take both back before pressing anything.
func _capture() -> void:
	get_window().grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _frames(3)


## How far the orb is from the spot over the palm its spring pulls it to, metres - hover included.
func _orb_gap(orb: MageHandOrb) -> float:
	var frame: Transform3D = (orb.get_parent() as Node3D).global_transform
	return orb.global_position.distance_to(frame * orb._target_local)


func _bolt() -> MageBolt:
	for node: Node in get_tree().current_scene.find_children("*", "MageBolt", true, false):
		return node as MageBolt
	return null


func _decoy() -> TemporaryAlly:
	for node: Node in get_tree().get_nodes_in_group("decoys"):
		if node is TemporaryAlly and (node as TemporaryAlly).kind == "decoy":
			return node as TemporaryAlly
	return null


## What the quick bar's charge count says on the slot holding green_5.
func _bar_charges(main: Node) -> String:
	var player: Player = PlayerRegistry.get_local() as Player
	var slot: int = player.quick_slots.find("green_5")
	var hud: Node = main.find_child("HUD", true, false)
	if slot < 0 or hud == null or not "_hotbar_charge_labels" in hud:
		return "no bar"
	var labels: Array = hud._hotbar_charge_labels
	if slot >= labels.size() or labels[slot] == null:
		return "no label"
	var label: Label = labels[slot]
	return label.text if label.visible else "hidden"


func _snapshot(file_name: String) -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s" % [args[0], file_name])


## A dummy that does nothing, `distance` metres straight ahead of the player.
func _dummy(main: Node, player: Player, distance: float) -> EnemyBase:
	var at: Vector3 = player.global_position - player.global_transform.basis.z * distance
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


## For what is updated in _process, like the HUD: physics frames can pass several to one drawn
## frame.
func _drawn_frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await _frames(int(ceil(s * Engine.physics_ticks_per_second)))


func _until(done: Callable, seconds: float) -> bool:
	var frames: int = int(ceil(seconds * Engine.physics_ticks_per_second))
	for i: int in frames:
		if done.call():
			return true
		await get_tree().physics_frame
	return done.call()


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s %s (%s)" % ["ok  " if ok else "FAIL", label, detail])
	if not ok:
		_failures.append("%s: %s" % [label, detail])


func _report() -> void:
	if _failures.is_empty():
		print("TEST RESULT: PASS")
		return
	print("TEST RESULT: FAIL")
	for failure: String in _failures:
		print("  " + failure)
