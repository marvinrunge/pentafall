extends Node
## Regression test for the barbarian class on the real map: the class choice reaching the
## spawned body, the two-hander (GreatswordKit) and the four class skills.
##
## Run with (windowed - the kit reads the real attack button, and a player only reads its
## buttons with the mouse captured, which a headless run cannot do):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/barbarian_kit.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold, plus MEASURE lines.
## With a folder after `--`, it also saves what the camera sees mid-heavy,
## mid-Whirlwind and in Berserk (heavy.png, whirlwind.png, berserk.png).
##
##   1. the solo player spawns as the barbarian: the greatsword kit, no block, the barbarian's
##      visual with the sword in hand, more health and less speed than the warrior;
##   2. a tap is one wide cleave that lands, taking the whole body and walking it forwards as
##      far as the clip does; the next tap carries on from the playhead into the chain's next
##      cut; and the cleave reaches an enemy well off to the side;
##   3. holding sets the heavy off at once, as the warrior's spin is: both swings at the clip's
##      own pace, stepping in with it, the first for the heavy's damage and the second for its
##      share of it;
##   4. the heavy goes through a big hit that staggers a cleave; the block button does
##      nothing;
##   5. Brute Force (level 3) throws the struck enemy much harder;
##   6. Whirlwind (level 6) is put on the quick bar, spins the figure - with its wind, blade
##      smear and dust (WhirlwindFx) - and hits all around;
##   7. Indomitable (level 10) keeps a cleave going through a big hit;
##   8. Berserk (level 14) is put on the bar: faster, harder swings, and harder hits taken.

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
	var probe: Node = load("res://tools/tests/barbarian_kit.gd").new()
	probe.set_meta("player_class", UserSettings.character_class)
	UserSettings.character_class = "barbarian"
	probe.name = "BarbarianKitTest"
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
	_check("the solo player is the barbarian", player.character_class == "barbarian", player.character_class)
	_check("...with the greatsword kit", player.kit is GreatswordKit, str(player.kit))
	_check("...and no block", not (player.defence is BlockGuard) and not (player.defence is DodgeRoll), str(player.defence))
	_check("...in the barbarian's visual", player.animator.has_clip("cleave_chain") and player.animator.has_clip("heavy_combo") and player.animator.has_clip("whirlwind"), "")
	_check("...sword in hand", player.animator.find_child("Greatsword", true, false) != null, "")
	_check("...more health than the warrior", is_equal_approx(player.max_hp, GameSettings.player_max_hp * GameSettings.barbarian_health_mult), "%.1f" % player.max_hp)
	_check("...and less speed", is_equal_approx(player.speed, GameSettings.player_base_speed * GameSettings.barbarian_speed_mult), "%.2f" % player.speed)
	var kit: GreatswordKit = player.kit as GreatswordKit

	RunState.team_level = 1
	var dummy: EnemyBase = await _dummy(main, player, 2.6, 0.0)
	if dummy == null:
		_failures.append("no dummy enemy")
		_report()
		return

	# 2. the cleaves
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
	_check("a cleave takes the whole body", player._action_roots_player and kit._action_clip == "cleave_chain", "rooted %s, %s" % [player._action_roots_player, kit._action_clip])
	# The cut lands about 0.7 s in; its whoosh waits for it rather than playing on the click.
	var whoosh_at: float = kit._pending_whooshes[0] if kit._pending_whooshes.size() == 1 else -1.0
	_check("...its whoosh timed to the blade, not the click", whoosh_at > 0.3 and is_equal_approx(whoosh_at, kit._pending_hits[0] - MeleeKit.WHOOSH_PEAK[&"blade_swing"] - GameSettings.barbarian_whoosh_lead) if not kit._pending_hits.is_empty() else false,
		"whoosh at %.2f s, cut at %.2f s" % [whoosh_at, kit._pending_hits[0] if not kit._pending_hits.is_empty() else -1.0])
	var walked_window: Vector2 = kit._action_window
	await _until(func() -> bool: return player._action_timer <= 0.0, 3.0)
	var walked: float = (player.global_position - from).dot(forward)
	var strike: float = player.animator.strike_length("cleave_chain")
	var lead: float = player.animator.windup_length("cleave_chain")
	var clip_walk: float = player.animator.root_forward("cleave_chain", lead + walked_window.y * strike) - player.animator.root_forward("cleave_chain", lead + walked_window.x * strike)
	_check("...and walks it forwards as far as the clip does", clip_walk > 0.3 and absf(walked - clip_walk) < clip_walk * 0.2, "%.2f m, clip %.2f m" % [walked, clip_walk])
	print("MEASURE first cut walks %.2f m (clip %.2f m)" % [walked, clip_walk])
	await _seconds(GameSettings.player_combo_grace + 0.3)

	_place(player, dummy, 3.0, 0.0)
	var cleave_expected: float = GameSettings.spell_melee_damage * GameSettings.barbarian_cleave_damage_mult * player.get_spell_damage_multiplier()
	var first: float = await _tap(player, dummy)
	_check("a tap is a cleave that lands", absf(first - cleave_expected) < 1.0, "%.1f, expected %.1f" % [first, cleave_expected])
	_check("...the chain's first cut", kit._combo_stage == 1, "stage %d" % kit._combo_stage)
	var cut: float = player.animator.combo_windows("cleave_chain", 3)[1].x
	_place(player, dummy, 3.0, 0.0)
	var second: float = await _tap(player, dummy)
	_check("...the next tap carries on into the second", kit._combo_stage == 2 and second > 0.0, "stage %d, %.1f" % [kit._combo_stage, second])
	_check("...from where the first had got to, not from the cut", kit._action_window.x < cut - 0.01, "starts at %.3f, cut at %.3f" % [kit._action_window.x, cut])
	_check("...with no fade back towards idle in between", is_zero_approx(player.animator._shot.fadein_time), "fade-in %.2f s" % player.animator._shot.fadein_time)
	print("MEASURE cleaves %.1f %.1f" % [first, second])
	await _until(func() -> bool: return player._action_timer <= 0.0, 3.0)
	# A click after the cut has ended - inside the axe's grace, but with the body back at rest -
	# starts the chain over rather than playing the third cut out of the resting pose.
	await _seconds(0.15)
	await _capture()
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(3)
	_check("...and a click once the cut has ended starts over at the first", kit._combo_stage == 1 and is_zero_approx(kit._action_window.x),
		"stage %d from %.3f" % [kit._combo_stage, kit._action_window.x])
	await _until(func() -> bool: return player._action_timer <= 0.0, 3.0)
	await _seconds(GameSettings.player_combo_grace + 0.3)
	# Off to the side, a little ahead - the cut walks the barbarian up alongside it.
	dummy.global_position = player.global_position + _flat(player.global_basis.x) * 2.0 - _flat(player.global_basis.z) * 1.6
	await _frames(2)
	var wide: float = await _tap(player, dummy)
	_check("...and sweeps wide enough to catch an enemy off to the side", wide > 0.0, "%.1f" % wide)
	_place(player, dummy, 2.6, 0.0)
	await _seconds(1.0)

	# 3. the heavy
	# The walk with nothing in the way first: it steps in further than the dummy stands.
	_place(player, dummy, 12.0, 0.0)
	await _capture()
	forward = -_flat(player.global_basis.z)
	var from_heavy: Vector3 = player.global_position
	var furthest: float = 0.0
	Input.action_press("attack")
	await _seconds(GameSettings.player_heavy_hold_time + 0.1)
	_check("a hold sets the heavy off at once, still held", player.animator.action_clip() == "heavy_combo" and player._action_is_heavy and Input.is_action_pressed("attack"),
		"%s, heavy %s" % [player.animator.action_clip(), player._action_is_heavy])
	_check("...at the clip's own pace", absf(player.animator._shot_speed - GameSettings.barbarian_heavy_pace) < 0.05, "%.2fx" % player.animator._shot_speed)
	await _snapshot("heavy.png")
	Input.action_release("attack")
	while player._action_timer > 0.0:
		furthest = maxf(furthest, (player.global_position - from_heavy).dot(forward))
		await get_tree().physics_frame
	var clip_step: float = 0.0
	for i in 60:
		clip_step = maxf(clip_step, player.animator.root_forward("heavy_combo", i / 60.0 * player.animator.strike_length("heavy_combo")))
	var back_to: float = (player.global_position - from_heavy).dot(forward)
	var clip_end: float = player.animator.root_forward("heavy_combo", player.animator.strike_length("heavy_combo"))
	_check("...stepping in as far as the clip does", clip_step > 0.1 and absf(furthest - clip_step) < clip_step * 0.25, "%.2f m, clip %.2f m" % [furthest, clip_step])
	_check("...and ends where the clip does", absf(back_to - clip_end) < 0.15, "ends %.2f m on, clip %.2f m" % [back_to, clip_end])
	print("MEASURE heavy steps %.2f m in, ends %.2f m on" % [furthest, back_to])
	_place(player, dummy, 2.6, 0.0)
	await _capture()
	var hp: float = dummy.health
	Input.action_press("attack")
	await _seconds(GameSettings.player_heavy_hold_time + 0.1)
	Input.action_release("attack")
	await _until(func() -> bool: return player._action_timer <= 0.0, 4.0)
	var heavy: float = hp - dummy.health
	# Both swings land: the first for the heavy's damage, the second for its share of it.
	var heavy_expected: float = GameSettings.spell_melee_damage * GameSettings.barbarian_heavy_damage_mult * player.get_spell_damage_multiplier() \
		* (1.0 + GameSettings.barbarian_heavy_second_swing_share)
	_check("...and both swings land, the second lighter", absf(heavy - heavy_expected) < 1.0, "%.1f, expected %.1f" % [heavy, heavy_expected])
	print("MEASURE heavy %.1f" % heavy)
	_place(player, dummy, 2.6, 0.0)

	# 4. unstoppable heavy, staggered cleave, no block
	var big_hit: float = player.max_hp * GameSettings.player_hit_react_damage_pct * 1.5
	await _capture()
	Input.action_press("attack")
	await _seconds(GameSettings.player_heavy_hold_time + 0.3)
	player.take_damage(big_hit, dummy)
	await _frames(2)
	_check("a big hit does not stop the heavy", player.animator.action_clip() == "heavy_combo" and player._stagger_timer <= 0.0, "%s, stagger %.2f" % [player.animator.action_clip(), player._stagger_timer])
	Input.action_release("attack")
	await _until(func() -> bool: return player._action_timer <= 0.0, 4.0)
	player.hp = player.max_hp
	await _seconds(GameSettings.player_hit_react_cooldown)
	var staggered: bool = await _hit_mid_cleave(player, dummy, big_hit)
	_check("...where the same hit staggers a cleave", staggered, "stagger %.2f" % player._stagger_timer)
	player.hp = player.max_hp
	await _seconds(GameSettings.player_hit_react_duration + 0.2)
	await _capture()
	Input.action_press("block")
	await _frames(4)
	_check("the block button raises no guard", not player.is_blocking, "")
	Input.action_release("block")

	# 5. Brute Force
	await _seconds(GameSettings.player_hit_react_cooldown)
	var push_without: float = await _heavy_push(player, kit, dummy)
	RunState.team_level = GameSettings.class_skill_levels[0]
	var push_with: float = await _heavy_push(player, kit, dummy)
	_check("Brute Force throws the struck enemy much harder", push_with > push_without * 1.5, "%.1f vs %.1f" % [push_with, push_without])
	print("MEASURE heavy knockback %.1f, with Brute Force %.1f" % [push_without, push_with])

	# 6. Whirlwind
	RunState.team_level = GameSettings.class_skill_levels[1]
	SignalBus.team_level_changed.emit(RunState.team_level, 0)
	await _frames(2)
	var whirl_slot: int = player.quick_slots.find("barbarian_whirlwind")
	_check("Whirlwind is put on the quick bar", whirl_slot >= 0, str(player.quick_slots))
	if whirl_slot >= 0:
		var behind: EnemyBase = await _dummy(main, player, -2.0, 0.0)
		_place(player, dummy, 0.0, 2.0)
		var before_front: float = dummy.health
		var before_back: float = behind.health if behind != null else 0.0
		player._cast_slot(whirl_slot, {})
		await _seconds(0.7)
		_check("...it spins the figure", kit.is_spinning() and absf(player.animator.rotation.y) > 0.5, "spinning %s, turned %.2f rad" % [kit.is_spinning(), player.animator.rotation.y])
		var fx: WhirlwindFx = player.get_node_or_null("WhirlwindFx") as WhirlwindFx
		_check("...with wind, the blade's smear and dust round it (WhirlwindFx)",
			fx != null and fx.visible and fx._dust.emitting and fx._intensity > 0.5,
			"fx %s" % (fx != null))
		await _snapshot("whirlwind.png")
		await _seconds(2.0)
		_check("...hits what is beside the barbarian", dummy.health < before_front, "%.1f" % (before_front - dummy.health))
		_check("...and behind", behind != null and behind.health < before_back, "%.1f" % ((before_back - behind.health) if behind != null else 0.0))
		_check("...faces the body's way again after", not kit.is_spinning() and absf(player.animator.rotation.y) < 0.01, "%.2f" % player.animator.rotation.y)
		_check("...and stops stirring up dust", fx != null and not fx._dust.emitting, "")
		_check("...on cooldown after", float(player.spell_cooldown_timers.get("barbarian_whirlwind", 0.0)) > 0.0, "")
		print("MEASURE whirlwind side %.1f back %.1f" % [before_front - dummy.health, (before_back - behind.health) if behind != null else 0.0])
		if behind != null:
			behind.queue_free()
	_place(player, dummy, 2.6, 0.0)
	await _until(func() -> bool: return player._action_timer <= 0.0, 2.0)

	# 7. Indomitable
	RunState.team_level = GameSettings.class_skill_levels[2]
	await _seconds(GameSettings.player_hit_react_cooldown)
	var staggered_now: bool = await _hit_mid_cleave(player, dummy, big_hit)
	_check("with Indomitable the same hit no longer staggers a cleave", not staggered_now, "stagger %.2f" % player._stagger_timer)
	player.hp = player.max_hp
	await _until(func() -> bool: return player._action_timer <= 0.0, 2.0)

	# 8. Berserk
	RunState.team_level = GameSettings.class_skill_levels[3]
	SignalBus.team_level_changed.emit(RunState.team_level, 0)
	await _frames(2)
	var berserk_slot: int = player.quick_slots.find("barbarian_berserk")
	_check("Berserk is put on the quick bar", berserk_slot >= 0, str(player.quick_slots))
	if berserk_slot >= 0:
		var calm_swing: float = kit._swing_duration()
		player._cast_slot(berserk_slot, {})
		await _seconds(1.2)
		_check("...it sends the barbarian berserk", player.is_berserk(), "")
		_check("...swings come faster", kit._swing_duration() < calm_swing * 0.8, "%.2f vs %.2f" % [kit._swing_duration(), calm_swing])
		await _snapshot("berserk.png")
		var raged: float = await _tap(player, dummy)
		var raged_expected: float = GameSettings.spell_melee_damage * GameSettings.barbarian_cleave_damage_mult * GameSettings.barbarian_berserk_damage_mult * player.get_spell_damage_multiplier()
		_check("...and land harder", absf(raged - raged_expected) < 1.0, "%.1f, expected %.1f" % [raged, raged_expected])
		var hp_before: float = player.hp
		player.take_damage(10.0, dummy)
		_check("...while every hit taken lands harder too", is_equal_approx(hp_before - player.hp, 10.0 * GameSettings.barbarian_berserk_damage_taken_mult), "%.2f" % (hp_before - player.hp))
		await _seconds(GameSettings.barbarian_berserk_duration)
		_check("...until it wears off", not player.is_berserk(), "")
		player.hp = player.max_hp

	_report()


## One tap of the attack button, once the swing before has let go; the damage the dummy took.
func _tap(player: Player, dummy: EnemyBase) -> float:
	await _until(func() -> bool: return player._can_start_attack(), 3.0)
	await _capture()
	var hp: float = dummy.health
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(2)
	await _until(func() -> bool: return dummy.health < hp or player._action_timer <= 0.0, 3.0)
	await _frames(2)
	return hp - dummy.health


## How hard a heavy pushes the dummy, read off its knockback the frame its first swing lands.
func _heavy_push(player: Player, kit: GreatswordKit, dummy: EnemyBase) -> float:
	_place(player, dummy, 2.6, 0.0)
	dummy.knockback_velocity = Vector3.ZERO
	await _until(func() -> bool: return player._action_timer <= 0.0, 4.0)
	await _capture()
	var hp: float = dummy.health
	Input.action_press("attack")
	await _seconds(GameSettings.player_heavy_hold_time + 0.05)
	Input.action_release("attack")
	var push: float = 0.0
	for i: int in 90:
		await get_tree().physics_frame
		if dummy.health < hp:
			push = Vector2(dummy.knockback_velocity.x, dummy.knockback_velocity.z).length()
			break
	await _until(func() -> bool: return player._action_timer <= 0.0, 4.0)
	return push


## Starts a cleave and hits the barbarian hard in the middle of it; whether that staggered.
func _hit_mid_cleave(player: Player, dummy: EnemyBase, damage: float) -> bool:
	await _until(func() -> bool: return player._can_start_attack() and player._action_timer <= 0.0, 3.0)
	await _capture()
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(6)
	player.take_damage(damage, dummy)
	await _frames(1)
	return player._stagger_timer > 0.0


## Puts the dummy `ahead` metres in front of the player and `right` to their right.
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


## A dummy that does nothing, `ahead` metres in front of the player (behind for negative)
## and `right` to their right.
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
