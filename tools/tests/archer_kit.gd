extends Node
## Regression test for the archer class on the real map: the class choice reaching the
## spawned body, the bow (BowKit), the roll (DodgeRoll) and the four class skills.
##
## Run with (windowed - the bow reads the real attack button, and a player only reads its
## buttons with the mouse captured, which a headless run cannot do):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/archer_kit.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold, plus MEASURE lines.
## With a folder after `--`, it also saves what the camera sees at full draw and just after
## the release (full_draw.png, loosed.png).
##
##   1. the solo player spawns as the archer: bow kit, roll, archer visual with its bow rig,
##      less health and a little more speed than the warrior;
##   2. a tap shoots a quick arrow that lands on a dummy;
##   3. a held draw reaches a full draw, stops the animation on it, keeps the arrow nocked,
##      points the arrow at the crosshair (BowAim), zooms the camera in, and hits much harder than the quick shot - the zoom letting go
##      once the arrow is loosed;
##   4. Longshot (level 3): a full draw passes through a line of dummies; without it, not;
##   5. Deadeye (level 14): an arrow in the head deals more than one in the body;
##   6. the roll plays the dodge clip and moves the archer with its hop, and nothing touches
##      them in its window;
##   7. Disengage (level 6) is put on the quick bar, rolls the archer back and leaves a snare
##      that slows;
##   8. Arrow Volley Trap (level 10) is put on the bar and rains damage on the aimed ground.

var _started: bool = false
var _failures: Array[String] = []


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	GameSettings.intro_tour_pending = false
	GameSettings.beast_first_spawn_delay = 9999.0
	# The solo seat plays the menu's class. Set on the property rather than through
	# set_value - but any other setting saved during the run writes every value, so the
	# player's own pick is put back (and saved) before the test quits.
	var probe: Node = load("res://tools/tests/archer_kit.gd").new()
	probe.set_meta("player_class", UserSettings.character_class)
	UserSettings.character_class = "archer"
	probe.name = "ArcherKitTest"
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
	_check("the solo player is the archer", player.character_class == "archer", player.character_class)
	_check("...with the bow", player.kit is BowKit, str(player.kit))
	_check("...and the roll", player.defence is DodgeRoll, str(player.defence))
	_check("...in the archer's visual", player.animator.has_clip("draw") and player.animator.has_clip("aim") and player.animator.has_clip("shoot"), "")
	var rig: BowRig = player.animator.find_child("BowRig", true, false) as BowRig
	_check("...with a strung bow", rig != null, "")
	_check("...less health than the warrior", is_equal_approx(player.max_hp, GameSettings.player_max_hp * GameSettings.archer_health_mult), "%.1f" % player.max_hp)
	_check("...and a little more speed", is_equal_approx(player.speed, GameSettings.player_base_speed * GameSettings.archer_speed_mult), "%.2f" % player.speed)
	var kit: BowKit = player.kit as BowKit

	RunState.team_level = 1
	var dummy: EnemyBase = await _dummy(main, player, 7.0)
	if dummy == null:
		_failures.append("no dummy enemy")
		_report()
		return

	# 2. a tap
	_aim_at(player, dummy, 1.0)
	var quick: float = await _shot(player, kit, dummy, false)
	var quick_expected: float = GameSettings.spell_melee_damage * GameSettings.archer_quick_shot_damage_mult * player.get_spell_damage_multiplier()
	_check("a tap shoots a quick arrow that lands", absf(quick - quick_expected) < 1.0, "%.1f, expected %.1f" % [quick, quick_expected])

	# 3. a full draw
	_aim_at(player, dummy, 1.0)
	await _until(func() -> bool: return player._action_timer <= 0.0, 2.0)
	await _capture()
	var hp: float = dummy.health
	Input.action_press("attack")
	await _seconds(GameSettings.archer_draw_time + GameSettings.archer_full_draw_time + 0.2)
	_check("holding reaches a full draw", is_equal_approx(kit.charge(), 1.0), "%.2f" % kit.charge())
	_check("...the hold creeps to a stop on it", player.animator.action_clip() == "aim" and player.animator._shot_speed <= BowKit.HOLD_CREEP, "%s %.2f" % [player.animator.action_clip(), player.animator._shot_speed])
	_check("...and the pose stays on screen", bool(player.animator._tree.get("parameters/shot/active")) and _hands_apart(player) < 0.85, "%.2f m between the hands" % _hands_apart(player))
	_check("...with the arrow on the string", rig != null and rig.is_nocked(), "")
	var hand_gap: float = rig.nock_point().distance_to(rig._hand_position()) if rig != null else -1.0
	_check("...pulled back to the hand", hand_gap < 0.01, "%.3f" % hand_gap)
	var aim_off: float = _arrow_off_crosshair(player, rig)
	_check("...pointing at the crosshair", aim_off < 3.0, "%.1f deg off" % aim_off)
	print("MEASURE arrow %.2f deg off the crosshair" % aim_off)
	var zoomed_fov: float = player.camera.fov
	_check("...with the camera zoomed in", zoomed_fov < player._camera_base_fov * (GameSettings.archer_aim_zoom_fov_mult + 0.05),
		"fov %.1f of %.1f" % [zoomed_fov, player._camera_base_fov])
	await _snapshot("full_draw.png")
	Input.action_release("attack")
	await _frames(4)
	await _snapshot("loosed.png")
	await _seconds(0.6)
	var full: float = hp - dummy.health
	_check("...and hits much harder than a tap", full > quick * 2.5, "%.1f vs %.1f" % [full, quick])
	_check("...the zoom letting go on the shot", absf(player.camera.fov - player._camera_base_fov) < 0.5,
		"fov %.1f of %.1f" % [player.camera.fov, player._camera_base_fov])
	print("MEASURE quick %.1f full %.1f" % [quick, full])
	await _until(func() -> bool: return player._action_timer <= 0.0, 2.0)

	# 4. Longshot
	# Lined up behind the first along the shot itself, not along wherever the player happens
	# to face: a captured mouse turns the player if the real mouse is nudged mid-test.
	var line: Array[EnemyBase] = [dummy]
	var along: Vector3 = dummy.global_position - player.global_position
	along.y = 0.0
	along = along.normalized()
	for extra: float in [2.0, 4.0]:
		var behind: EnemyBase = await _dummy(main, player, 7.0)
		if behind != null:
			behind.global_position = dummy.global_position + along * extra
			line.append(behind)
	var pierced_without: int = await _full_draw_hits(player, kit, line)
	RunState.team_level = GameSettings.class_skill_levels[0]
	var pierced_with: int = await _full_draw_hits(player, kit, line)
	_check("without Longshot a full draw stops at the first", pierced_without == 1, "%d hit" % pierced_without)
	_check("with Longshot it passes through the line", pierced_with == line.size(), "%d of %d hit" % [pierced_with, line.size()])
	for extra_dummy: EnemyBase in line.slice(1):
		extra_dummy.queue_free()
	await _frames(3)

	# 5. Deadeye
	RunState.team_level = GameSettings.class_skill_levels[3]
	_aim_at(player, dummy, 0.35)
	var body: float = await _shot(player, kit, dummy, false)
	var top: float = PlayerArrow.body_top(dummy)
	# Into the middle of the head band: archer_head_fraction of the body from the top.
	_aim_at(player, dummy, (top - dummy.global_position.y) * (1.0 - GameSettings.archer_head_fraction * 0.4))
	var head: float = await _shot(player, kit, dummy, false)
	_check("with Deadeye a head shot deals more than a body shot", head > body * 1.5, "%.1f vs %.1f" % [head, body])
	print("MEASURE deadeye body %.1f head %.1f (top %.2f)" % [body, head, top - dummy.global_position.y])
	player._aim_override = []

	# 6. the roll
	await _seconds(0.3)
	var roll: DodgeRoll = player.defence as DodgeRoll
	var before: Vector3 = player.global_position
	var hp_before: float = player.hp
	_check("the roll is ready", roll.can_roll(), "")
	roll.roll(Vector2(0.0, 1.0))
	await _frames(2)
	_check("the roll plays the dodge clip", player.animator.action_clip() == "dodge_back", player.animator.action_clip())
	player.take_damage(25.0, dummy)
	var untouched: bool = is_equal_approx(player.hp, hp_before)
	# Fast where the clip's feet push off, slow as it lands - not one constant speed.
	var speeds: Array[float] = []
	while player._is_evading():
		speeds.append(Vector2(player.velocity.x, player.velocity.z).length())
		await get_tree().physics_frame
	await _seconds(0.1)
	var rolled: float = Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
	_check("the roll carries the archer", rolled > GameSettings.archer_dodge_distance * 0.7, "%.2fm" % rolled)
	var top_speed: float = speeds.max() if not speeds.is_empty() else 0.0
	_check("...with the clip's own hop", not speeds.is_empty() and top_speed > speeds[-1] * 1.5 and top_speed > speeds[0] * 1.5,
		"%.1f m/s at the start, %.1f at most, %.1f at the end" % [speeds[0] if not speeds.is_empty() else 0.0, top_speed, speeds[-1] if not speeds.is_empty() else 0.0])
	_check("...and nothing touches them in it", untouched, "hp %.1f -> %.1f" % [hp_before, player.hp])
	player.take_damage(10.0, dummy)
	_check("...after which hits land again", player.hp < hp_before, "")
	_check("...and it has a cooldown", not roll.can_roll(), "")
	print("MEASURE roll %.2fm" % rolled)
	player.hp = player.max_hp

	# 7. Disengage
	RunState.team_level = GameSettings.class_skill_levels[1]
	SignalBus.team_level_changed.emit(RunState.team_level, 0)
	await _frames(2)
	var disengage_slot: int = player.quick_slots.find("archer_disengage")
	_check("Disengage is put on the quick bar", disengage_slot >= 0, str(player.quick_slots))
	if disengage_slot >= 0:
		await _seconds(GameSettings.archer_dodge_cooldown)
		var start: Vector3 = player.global_position
		player._cast_slot(disengage_slot, {})
		await _seconds(0.9)
		var moved: float = Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
		_check("...it rolls the archer well back", moved > GameSettings.archer_disengage_distance * 0.7, "%.2fm" % moved)
		var snare: DoTZone = _zone("snare")
		_check("...and leaves a snare where they stood", snare != null and Vector2(snare.global_position.x - start.x, snare.global_position.z - start.z).length() < 1.5, "")
		_check("...on cooldown after", float(player.spell_cooldown_timers.get("archer_disengage", 0.0)) > 0.0, "")
		if snare != null:
			dummy.global_position = snare.global_position + Vector3(0.0, 0.2, 0.0)
			await _seconds(0.7)
			_check("...which slows what stands in it", dummy.slow_timer > 0.0 and dummy.slow_mult < 1.0, "%.2f x%.2f" % [dummy.slow_timer, dummy.slow_mult])

	# 8. Arrow Volley Trap
	RunState.team_level = GameSettings.class_skill_levels[2]
	SignalBus.team_level_changed.emit(RunState.team_level, 0)
	await _frames(2)
	var volley_slot: int = player.quick_slots.find("archer_volley")
	_check("Arrow Volley Trap is put on the quick bar", volley_slot >= 0, str(player.quick_slots))
	if volley_slot >= 0:
		dummy.global_position = player.global_position - player.global_basis.z * 8.0
		await _frames(2)
		_aim_at(player, dummy, 0.05)
		var volley_hp: float = dummy.health
		player._cast_slot(volley_slot, {})
		await _seconds(1.6)
		player._aim_override = []
		var volley: DoTZone = _zone("arrow_volley")
		_check("...it puts the volley on the aimed ground", volley != null and Vector2(volley.global_position.x - dummy.global_position.x, volley.global_position.z - dummy.global_position.z).length() < 1.5, "")
		_check("...and the volley hurts what is under it", volley_hp - dummy.health > 0.0, "%.1f" % (volley_hp - dummy.health))
		print("MEASURE volley %.1f in 1.6s" % (volley_hp - dummy.health))

	_report()


## One shot at whatever the aim override points at, quick (`hold` false) or full. Returns
## the damage the dummy took.
func _shot(player: Player, kit: BowKit, dummy: EnemyBase, hold: bool) -> float:
	await _until(func() -> bool: return player._action_timer <= 0.0, 2.0)
	await _capture()
	var hp: float = dummy.health
	Input.action_press("attack")
	if hold:
		await _seconds(GameSettings.archer_draw_time + GameSettings.archer_full_draw_time + 0.1)
	else:
		await _frames(2)
	Input.action_release("attack")
	await _seconds(GameSettings.archer_draw_time + 0.7)
	return hp - dummy.health


## A full draw at the first of `line`; how many of them took damage.
func _full_draw_hits(player: Player, kit: BowKit, line: Array[EnemyBase]) -> int:
	_aim_at(player, line[0], 1.0)
	var before: Array[float] = []
	for enemy: EnemyBase in line:
		before.append(enemy.health)
	await _shot(player, kit, line[0], true)
	var hit: int = 0
	for i in line.size():
		if line[i].health < before[i]:
			hit += 1
	return hit


## Points the crosshair at `enemy`, `height` metres up its body - set as the aim override,
## the same field a client's own aim arrives in.
func _aim_at(player: Player, enemy: Node3D, height: float) -> void:
	var nock: Vector3 = player.global_position + Vector3(0.0, 1.5, 0.0)
	var target: Vector3 = enemy.global_position + Vector3(0.0, height, 0.0)
	player._aim_override = [nock, (target - nock).normalized()]


## The buttons are only read with the mouse captured, and a window that lost focus to
## something else on the desktop has let it go - take both back before pressing anything.
func _capture() -> void:
	get_window().grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _frames(3)


## The angle between the nocked arrow (string hand to grip, as BowRig draws it) and the line
## from the nock to what the crosshair is on - the arrow's flight path, so what BowAim has to
## make the bow point along.
func _arrow_off_crosshair(player: Player, rig: BowRig) -> float:
	if rig == null:
		return 180.0
	var nock: Vector3 = rig.nock_point()
	var arrow: Vector3 = rig._bow_world * rig.grip_point() - nock
	var wanted: Vector3 = player.aim_hit_point(GameSettings.archer_arrow_range) - nock
	return rad_to_deg(arrow.angle_to(wanted))


func _hands_apart(player: Player) -> float:
	var sk: Skeleton3D = player.animator._skeleton
	var left: Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftHand"))).origin
	var right: Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand"))).origin
	return left.distance_to(right)


func _snapshot(file_name: String) -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s" % [args[0], file_name])


func _zone(type: String) -> DoTZone:
	for node: Node in get_tree().current_scene.find_children("*", "DoTZone", true, false):
		if (node as DoTZone).zone_type == type:
			return node as DoTZone
	return null


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
