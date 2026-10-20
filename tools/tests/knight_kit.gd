extends Node
## Regression test for the knight class on the real map: the class choice reaching the
## spawned body, the sword (KnightKit), the shield (KnightGuard) and the four class skills.
##
## Run with (windowed - the kit reads the real buttons, and a player only reads them with the
## mouse captured, which a headless run cannot do):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/knight_kit.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold, plus MEASURE lines. With a
## folder after `--`, it also saves what the camera sees with the guard up (guard.png) and
## strafing under it (guard_walk.png).
##
##   1. the solo player spawns as the knight: the sword-and-shield kit, the shield guard, the
##      knight's visual with sword and shield in hand, more health and a little less speed;
##   2. a tap is the chain's first cut, taking the whole body and walking it forwards as far as
##      the clip does; the next taps while it plays carry on into the second and third cut, and
##      a tap once the chain has ended starts over at the first;
##   3. holding sets the heavy cut off at once, for the heavy's damage;
##   4. the guard takes nearly all of a hit from in front - a boss's too - and none from behind,
##      and walking under it plays the knight's own walk whole, no guard layer on the arms;
##   5. First Strike (level 3): the swing after a blocked hit plays faster and hits harder;
##   6. Shield Bash (level 6) is put on the quick bar and stuns and hurts what is in front;
##   7. Shield Wall (level 10): a hit taken just as the shield comes up stuns the attacker, one
##      taken later does not;
##   8. Phalanx (level 14): with the guard up, enemies around turn on the knight, and an ally
##      behind takes less damage while one in front does not.

var _started: bool = false
var _failures: Array[String] = []


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	GameSettings.intro_tour_pending = false
	GameSettings.beast_first_spawn_delay = 9999.0
	# The solo seat plays the menu's class - see archer_kit.gd for why it is set this way and
	# put back before the test quits.
	var probe: Node = load("res://tools/tests/knight_kit.gd").new()
	probe.set_meta("player_class", UserSettings.character_class)
	UserSettings.character_class = "knight"
	probe.name = "KnightKitTest"
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
	_check("the solo player is the knight", player.character_class == "knight", player.character_class)
	_check("...with the sword-and-shield kit", player.kit is KnightKit, str(player.kit))
	_check("...and the shield guard", player.defence is KnightGuard, str(player.defence))
	_check("...in the knight's visual", player.animator.has_clip("slash_chain") and player.animator.has_clip("heavy_slash") and player.animator.has_clip("block_idle"), "")
	_check("...sword and shield in hand", player.animator.find_child("Sword", true, false) != null and player.animator.find_child("Shield", true, false) != null, "")
	_check("...more health than the warrior", is_equal_approx(player.max_hp, GameSettings.player_max_hp * GameSettings.knight_health_mult), "%.1f" % player.max_hp)
	_check("...and a little less speed", is_equal_approx(player.speed, GameSettings.player_base_speed * GameSettings.knight_speed_mult), "%.2f" % player.speed)
	var kit: KnightKit = player.kit as KnightKit

	RunState.team_level = 1
	var dummy: EnemyBase = await _dummy(main, player, 2.4, 0.0)
	if dummy == null:
		_failures.append("no dummy enemy")
		_report()
		return

	# 2. the cuts
	# The walk first, with nothing in the way: one cut, how far it carried the body forwards
	# against how far the clip itself travels over the same slice.
	_place(player, dummy, 12.0, 0.0)
	await _capture()
	var forward: Vector3 = -_flat(player.global_basis.z)
	var from: Vector3 = player.global_position
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(2)
	_check("a cut takes the whole body", player._action_roots_player and kit._action_clip == "slash_chain", "rooted %s, %s" % [player._action_roots_player, kit._action_clip])
	var walked_window: Vector2 = kit._action_window
	await _until(func() -> bool: return player._action_timer <= 0.0, 3.0)
	var walked: float = (player.global_position - from).dot(forward)
	var strike: float = player.animator.strike_length("slash_chain")
	var lead: float = player.animator.windup_length("slash_chain")
	var clip_walk: float = player.animator.root_forward("slash_chain", lead + walked_window.y * strike) - player.animator.root_forward("slash_chain", lead + walked_window.x * strike)
	_check("...and walks it forwards as far as the clip does", absf(walked - clip_walk) < maxf(clip_walk * 0.2, 0.05), "%.2f m, clip %.2f m" % [walked, clip_walk])
	print("MEASURE first cut walks %.2f m (clip %.2f m)" % [walked, clip_walk])
	await _seconds(GameSettings.player_combo_grace + 0.3)

	# Each cut is paid for its share of the chain (KnightKit._stage_share).
	var cut_damage: float = GameSettings.spell_melee_damage * GameSettings.knight_cut_damage_mult * player.get_spell_damage_multiplier()
	var stages: Array[Vector2] = player.animator.combo_windows("slash_chain", 3)
	var cut_expected: float = cut_damage * kit._stage_share(stages[0])
	var first: float = await _tap(player, dummy)
	_check("a tap is the chain's first cut", kit._action_clip == "slash_chain" and kit._combo_stage == 1 and absf(first - cut_expected) < 1.0,
		"%s stage %d, %.1f (expected %.1f)" % [kit._action_clip, kit._combo_stage, first, cut_expected])
	var second: float = await _tap(player, dummy)
	var second_expected: float = cut_damage * kit._stage_share(stages[1])
	_check("...the next tap while it plays carries on into the second", kit._combo_stage == 2 and absf(second - second_expected) < 1.0,
		"stage %d, %.1f (expected %.1f)" % [kit._combo_stage, second, second_expected])
	var third: float = await _tap(player, dummy)
	var third_expected: float = cut_damage * kit._stage_share(stages[2])
	_check("...and the one after into the third, the hardest", kit._combo_stage == 3 and absf(third - third_expected) < 1.0 and third > first,
		"stage %d, %.1f (expected %.1f)" % [kit._combo_stage, third, third_expected])
	await _until(func() -> bool: return player._action_timer <= 0.0, 4.0)
	await _seconds(0.15)
	var again: float = await _tap(player, dummy)
	_check("...and a tap once the chain has ended starts over", kit._combo_stage == 1 and is_zero_approx(kit._action_window.x) and again > 0.0,
		"stage %d from %.3f" % [kit._combo_stage, kit._action_window.x])
	await _until(func() -> bool: return player._action_timer <= 0.0, 3.0)

	# 3. the heavy
	await _capture()
	_place(player, dummy, 2.4, 0.0)
	var hp: float = dummy.health
	Input.action_press("attack")
	await _seconds(GameSettings.player_heavy_hold_time + 0.1)
	_check("holding sets the heavy cut off at once", player.animator.action_clip() == "heavy_slash" and player._action_is_heavy, player.animator.action_clip())
	Input.action_release("attack")
	await _until(func() -> bool: return player._action_timer <= 0.0, 3.0)
	var heavy: float = hp - dummy.health
	var heavy_expected: float = GameSettings.spell_melee_damage * GameSettings.knight_heavy_damage_mult * player.get_spell_damage_multiplier()
	_check("...for the heavy's damage", absf(heavy - heavy_expected) < 1.0, "%.1f, expected %.1f" % [heavy, heavy_expected])
	print("MEASURE cuts %.1f %.1f %.1f heavy %.1f" % [first, second, third, heavy])

	# 4. the guard
	await _raise_guard(player)
	await _snapshot("guard.png")
	var before: float = player.hp
	player.take_damage(40.0, dummy)
	var front_taken: float = before - player.hp
	_check("the shield takes nearly all of a hit from in front", is_equal_approx(front_taken, 40.0 * (1.0 - GameSettings.knight_block_damage_reduction)), "%.2f taken" % front_taken)
	var boss_data: EnemyData = dummy.enemy_data
	dummy.enemy_data = boss_data.duplicate()
	dummy.enemy_data.enemy_class = "Boss"
	before = player.hp
	player.take_damage(40.0, dummy)
	_check("...a boss's too", is_equal_approx(before - player.hp, 40.0 * (1.0 - GameSettings.knight_block_damage_reduction)), "%.2f taken" % (before - player.hp))
	dummy.enemy_data = boss_data
	_place(player, dummy, -2.0, 0.0)
	before = player.hp
	player.take_damage(10.0, dummy)
	_check("...and none from behind", is_equal_approx(before - player.hp, 10.0), "%.2f taken" % (before - player.hp))
	# On the move the guard is the knight's own walks, which already hold the shield up - no
	# crouched block_idle laid over the arms of an upright walk.
	Input.action_press("move_left")
	await _seconds(0.6)
	await _snapshot("guard_walk.png")
	var strafe: float = Vector2(player.velocity.x, player.velocity.z).length()
	_check("walking under guard plays the walk whole", player.is_blocking and strafe > 0.3 and is_zero_approx(player.animator._guard_amount),
		"blocking %s, speed %.2f, guard layer %.2f" % [player.is_blocking, strafe, player.animator._guard_amount])
	Input.action_release("move_left")
	await _seconds(0.3)
	_place(player, dummy, 2.4, 0.0)
	Input.action_release("block")
	player.hp = player.max_hp
	await _seconds(0.3)

	# 5. First Strike
	RunState.team_level = GameSettings.class_skill_levels[0]
	var plain_duration: float = await _cut_duration(player, kit, dummy)
	await _raise_guard(player)
	player.take_damage(20.0, dummy)
	Input.action_release("block")
	await _frames(3)
	_place(player, dummy, 2.4, 0.0)
	hp = dummy.health
	var riposte_duration: float = await _cut_duration(player, kit, dummy)
	var riposte: float = hp - dummy.health
	_check("First Strike: the swing after a block hits harder", absf(riposte - cut_expected * GameSettings.knight_first_strike_damage_mult) < 1.0, "%.1f" % riposte)
	_check("...and comes out faster", riposte_duration < plain_duration * 0.8, "%.2f s vs %.2f s" % [riposte_duration, plain_duration])
	player.hp = player.max_hp

	# 6. Shield Bash
	RunState.team_level = GameSettings.class_skill_levels[1]
	SignalBus.team_level_changed.emit(RunState.team_level, 0)
	await _frames(2)
	var bash_slot: int = player.quick_slots.find("knight_shield_bash")
	_check("Shield Bash is put on the quick bar", bash_slot >= 0, str(player.quick_slots))
	if bash_slot >= 0:
		_place(player, dummy, 1.8, 0.0)
		dummy.stun_timer = 0.0
		hp = dummy.health
		player._cast_slot(bash_slot, {})
		await _seconds(0.5)
		_check("...it stuns what is in front", dummy.stun_timer > 0.0, "stun %.2f" % dummy.stun_timer)
		_check("...and hurts it", dummy.health < hp, "%.1f" % (hp - dummy.health))
		_check("...on cooldown after", float(player.spell_cooldown_timers.get("knight_shield_bash", 0.0)) > 0.0, "")
		dummy.stun_timer = 0.0
	await _until(func() -> bool: return player._action_timer <= 0.0, 2.0)
	_place(player, dummy, 2.4, 0.0)

	# 7. Shield Wall
	RunState.team_level = GameSettings.class_skill_levels[2]
	dummy.stun_timer = 0.0
	await _raise_guard(player)
	player.take_damage(10.0, dummy)
	_check("Shield Wall: a hit as the shield comes up stuns the attacker", dummy.stun_timer > 0.0, "stun %.2f" % dummy.stun_timer)
	dummy.stun_timer = 0.0
	await _seconds(GameSettings.knight_perfect_block_window + 0.3)
	player.take_damage(10.0, dummy)
	_check("...one taken later does not", is_zero_approx(dummy.stun_timer), "stun %.2f" % dummy.stun_timer)
	Input.action_release("block")
	player.hp = player.max_hp
	await _seconds(0.3)

	# 8. Phalanx
	RunState.team_level = GameSettings.class_skill_levels[3]
	_place(player, dummy, 5.0, 0.0)
	dummy.taunt_timer = 0.0
	dummy.taunt_source = null
	var behind := Node3D.new()
	var in_front := Node3D.new()
	main.add_child(behind)
	main.add_child(in_front)
	behind.global_position = player.global_position + _flat(player.global_basis.z) * 2.0
	in_front.global_position = player.global_position - _flat(player.global_basis.z) * 2.0
	_check("without the guard up nobody is sheltered", is_equal_approx(Player.phalanx_damage_taken_mult(behind), 1.0), "")
	await _raise_guard(player)
	await _seconds(0.3)
	_check("Phalanx: the enemies around turn on the knight", dummy.taunt_source == player and dummy.taunt_timer > 0.0, "taunt %.2f" % dummy.taunt_timer)
	_check("...an ally behind takes less damage", is_equal_approx(Player.phalanx_damage_taken_mult(behind), GameSettings.knight_phalanx_damage_taken_mult), "%.2f" % Player.phalanx_damage_taken_mult(behind))
	_check("...one in front does not", is_equal_approx(Player.phalanx_damage_taken_mult(in_front), 1.0), "%.2f" % Player.phalanx_damage_taken_mult(in_front))
	Input.action_release("block")
	behind.queue_free()
	in_front.queue_free()

	_report()


## One tap of the attack button, once the swing before can be chained out of; the damage the
## dummy took.
func _tap(player: Player, dummy: EnemyBase) -> float:
	await _until(func() -> bool: return player._can_start_attack(), 3.0)
	await _capture()
	# Put back in front each time: a real mouse nudged while the window has it captured turns
	# the knight, and a cut swung past the dummy would read as one that did no damage.
	_place(player, dummy, 2.4, 0.0)
	var hp: float = dummy.health
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(2)
	await _until(func() -> bool: return dummy.health < hp or player._action_timer <= 0.0, 3.0)
	await _frames(2)
	return hp - dummy.health


## A fresh quick cut from rest: how long it commits the knight for.
func _cut_duration(player: Player, kit: KnightKit, dummy: EnemyBase) -> float:
	await _until(func() -> bool: return player._action_timer <= 0.0, 3.0)
	await _seconds(0.1)
	await _capture()
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(3)
	var duration: float = player._action_duration
	await _until(func() -> bool: return player._action_timer <= 0.0, 3.0)
	await _seconds(0.1)
	return duration


func _raise_guard(player: Player) -> void:
	await _until(func() -> bool: return player._action_timer <= 0.0, 3.0)
	await _capture()
	Input.action_press("block")
	await _until(func() -> bool: return player.is_blocking, 1.0)


## Puts the dummy `ahead` metres in front of the player (behind for negative) and `right` to
## their right.
func _place(player: Player, dummy: EnemyBase, ahead: float, right: float) -> void:
	dummy.global_position = player.global_position - _flat(player.global_basis.z) * ahead + _flat(player.global_basis.x) * right
	dummy.velocity = Vector3.ZERO
	dummy.knockback_velocity = Vector3.ZERO


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()


## The buttons are only read with the mouse captured - see archer_kit.gd.
func _capture() -> void:
	get_window().grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _frames(3)


func _snapshot(file_name: String) -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s" % [args[0], file_name])


## A dummy that does nothing, `ahead` metres in front of the player and `right` to their right.
func _dummy(main: Node, player: Player, ahead: float, right: float) -> EnemyBase:
	var at: Vector3 = player.global_position - _flat(player.global_basis.z) * ahead + _flat(player.global_basis.x) * right
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
