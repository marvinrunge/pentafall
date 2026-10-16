extends "res://tools/tests/vfx_stage.gd"
## Regression test: a wild beast is an enemy that can be fought, keeps to its territory, and
## is NOT a wave enemy. Stages 1 and 2 of docs/BEASTS_PLAN.md.
##
## Run with:  godot --headless --path . res://tools/tests/beast_stage.tscn
## Windowed, with a folder after `--`, it also saves frames of each beast idling, using its
## special, biting and lying dead:  godot --path . res://tools/tests/beast_stage.tscn -- C:/some/folder
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.
##
## On the light stage (vfx_stage.gd) with a small navmesh baked over it and a training dummy
## standing in for a player. For the beast of each biome that has a model of its own (Green,
## Red, Blue), spawned the way MainController spawns anything (request_enemy):
##
##   1. Its model is a beast's: the GLB with all seven clips, at its size in metres - not the
##      100x a character scene is drawn at - standing on the ground and centred on the body.
##   2. Left alone it idles at home, then wanders about it on its walk - never out of its
##      roaming radius.
##   3. A player coming into reach meets its special: the ravagers pounce across the gap, the
##      Spineback spins its tail. The mark is drawn first and the hit lands on what is in it;
##      after that it bites.
##   4. Stepping out of the mark once it is drawn dodges the special.
##   5. With the player gone it walks back home and idles again.
##   6. A player who hurts it from beyond its aggro radius is chased and bitten.
##   7. Dragged past its leash it breaks off, runs home deaf to further hits, and arrives whole.
##   8. A solid hit plays its flinch.
##   9. It dies on its own death clip, on the spot (no throw), stays as a corpse - and is not
##      counted by the wave: SignalBus.enemy_died is the wave's countdown.
##  10. It never hits the crystal: nothing in this test may raise crystal_damaged, though a
##      beast's goal stands in the crystal's place in its targeting.

const Dummy := preload("res://tools/tests/beast_dummy.gd")
const EquipmentDatabase := preload("res://scripts/equipment_database.gd")
const COLORS: Array[String] = ["Green", "Red", "Blue"]
const CLIPS: Array[String] = ["idle", "walk", "run", "attack", "special", "hit", "death"]
const HOME := Vector3(0.0, 0.0, -10.0)
## How close to home counts as home: the agent ends a route a little short of its goal.
const HOME_TOLERANCE := 3.0

var _failures: Array[String] = []
var _crystal_hits: int = 0
var _wave_deaths: int = 0
var _shots_dir: String = ""


func _ready() -> void:
	build_stage()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		_shots_dir = args[0]
	SignalBus.crystal_damaged.connect(func(_amount: float) -> void: _crystal_hits += 1)
	SignalBus.enemy_died.connect(func() -> void: _wave_deaths += 1)
	_run.call_deferred()


func _run() -> void:
	for i: int in ready_frames():
		await get_tree().physics_frame
	await _bake_navigation()
	for color: String in COLORS:
		await _test_beast(color)
	_test_size_roll()
	await _test_giant("Green", 4.0, 16.0)
	await _test_giant("Red", 4.0, 9.0)
	await _test_rewards()
	await _test_equipment()
	_check("no beast ever hit the crystal", _crystal_hits == 0, "%d crystal hits" % _crystal_hits)
	_check("no beast death counted towards a wave", _wave_deaths == 0, "%d enemy_died" % _wave_deaths)
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()


## A navmesh over the middle of the stage, baked the way the map's is: from the static
## colliders, into a region the agents then find through the default map.
func _bake_navigation() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.filter_baking_aabb = AABB(Vector3(-50.0, -5.0, -50.0), Vector3(100.0, 20.0, 100.0))
	nav_mesh.agent_radius = 0.75  # a whole number of 0.25 m cells, or Recast rounds it up anyway
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, self)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nav_mesh
	add_child(region)
	for i: int in 10:
		await get_tree().physics_frame


func _test_beast(color: String) -> void:
	print("== %s" % color)
	var beast: EnemyBase = request_enemy({"color": color, "type": "Beast", "position": HOME}) as EnemyBase
	for i: int in 30:
		await get_tree().physics_frame
	_check_model(color, beast)
	var seen: Dictionary = {}

	# 2. alone: idle at home, then wandering about it
	await _watch(beast, 2.0, seen)
	_check("%s idles at home" % color, beast.visual_anim_player.current_animation == "idle" and seen.has("idle"),
		"playing %s" % beast.visual_anim_player.current_animation)
	_check("%s stays home at first" % color, _flat(beast.global_position, HOME) < 0.5,
		"%.2fm from home" % _flat(beast.global_position, HOME))
	await _shoot(beast, "%s_idle" % color.to_lower())
	var wait_min: float = GameSettings.beast_roam_wait_min
	var wait_max: float = GameSettings.beast_roam_wait_max
	GameSettings.beast_roam_wait_min = 0.5
	GameSettings.beast_roam_wait_max = 1.0
	beast._beast_wander_wait = 0.0
	seen.clear()
	var furthest: float = 0.0
	var elapsed: float = 0.0
	while elapsed < 14.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		furthest = maxf(furthest, _flat(beast.global_position, HOME))
		seen[beast.visual_anim_player.current_animation] = true
	GameSettings.beast_roam_wait_min = wait_min
	GameSettings.beast_roam_wait_max = wait_max
	_check("%s wanders off on its walk" % color, furthest > 1.5 and seen.has("walk") and not seen.has("run"),
		"got %.2fm out, clips %s" % [furthest, seen.keys()])
	_check("%s keeps to its roaming radius" % color,
		furthest <= GameSettings.beast_roam_radius + GameSettings.beast_home_arrive_distance + 0.5,
		"got %.2fm out" % furthest)

	# 3. a player in reach: the special first, then bites
	var pounce: bool = EnemyBase.BeastDatabase.special_kind(color) == "pounce"
	var dummy: Node3D = Dummy.new()
	add_child(dummy)
	var gap: float = 7.5 if pounce else 2.6
	dummy.global_position = beast.global_position + Vector3(0.0, 0.0, gap)
	var result: Dictionary = await _special(beast, dummy, false)
	_check("%s opens with its special" % color, result["started"], "")
	_check("%s marks where the special lands" % color, result["marked"], "")
	_check("%s's special hits what stands in the mark" % color, result["damage"] > 0.0, "%.1f damage" % result["damage"])
	if pounce:
		_check("%s pounces across the gap" % color, result["travel"] > 2.5, "carried %.2fm" % result["travel"])
	seen.clear()
	await _watch(beast, 5.0, seen, func() -> bool: return seen.has("attack"))
	_check("%s bites after its special" % color, seen.has("attack"), "clips %s" % [seen.keys()])
	await _shoot(beast, "%s_attack" % color.to_lower(), 0.25)

	# 4. stepping out of the mark dodges it
	beast._beast_special_cooldown = 0.0
	dummy.global_position = beast.global_position + beast.global_basis.z * (7.5 if pounce else 2.6)
	result = await _special(beast, dummy, true)
	_check("%s's special can be dodged" % color, result["started"] and result["damage"] == 0.0,
		"started %s, %.1f damage" % [result["started"], result["damage"]])

	# 5. the player leaves: back home
	# After a fight it walks home at its wandering pace, which from a chase can take a while.
	dummy.global_position = HOME + Vector3(-45.0, 0.0, 40.0)
	await _until_home(beast, 30.0)
	_check("%s walks back home when the player leaves" % color,
		_flat(beast.global_position, HOME) <= HOME_TOLERANCE,
		"%.2fm from home" % _flat(beast.global_position, HOME))
	# ...and counts as arrived there: it rests and wanders on, rather than standing a few steps
	# short of its goal forever.
	var rest_left: float = beast._beast_wander_wait
	await _watch(beast, 1.0, {})
	# Counting down, or already run out and drawn afresh for the next spot.
	_check("%s rests once it is home" % color, not is_equal_approx(beast._beast_wander_wait, rest_left),
		"wander wait %.2f -> %.2f" % [rest_left, beast._beast_wander_wait])

	# 6. hurt from beyond its aggro radius: it answers
	dummy.global_position = HOME + Vector3(18.0, 0.0, 0.0)
	var before: float = dummy.damage_taken
	beast._beast_special_cooldown = GameSettings.beast_special_cooldown
	beast.take_damage(1.0, dummy)
	await _watch(beast, 12.0, {}, func() -> bool: return dummy.damage_taken > before)
	_check("%s goes for whoever hurt it from afar" % color, dummy.damage_taken > before,
		"%.1f damage dealt" % (dummy.damage_taken - before))

	# 7. dragged past its leash: home at a run, deaf, and whole again
	beast.take_damage(beast.max_health * 0.3, dummy)
	dummy.global_position = HOME + Vector3(42.0, 0.0, 0.0)
	beast.take_damage(1.0, dummy)
	var broke_off: bool = false
	var deaf: bool = true
	elapsed = 0.0
	while elapsed < 25.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if beast._beast_returning and not broke_off:
			broke_off = true
			beast.take_damage(1.0, dummy)
			deaf = beast._beast_returning and beast.current_target == beast.target_crystal
		if broke_off and not beast._beast_returning:
			break
	_check("%s breaks off at the end of its leash" % color, broke_off, "")
	_check("%s ignores hits on the way home" % color, deaf, "")
	_check("%s gets home" % color, _flat(beast.global_position, HOME) <= HOME_TOLERANCE,
		"%.2fm from home" % _flat(beast.global_position, HOME))
	_check("%s arrives whole" % color, is_equal_approx(beast.health, beast.max_health),
		"%.0f of %.0f" % [beast.health, beast.max_health])
	dummy.queue_free()

	# 8. a solid hit: the flinch. Within the flinch window rather than on the next tick: with
	# nobody near, the beast thinks at its far level of detail, every few ticks.
	beast.take_damage(beast.max_health * 0.15)
	seen.clear()
	await _watch(beast, GameSettings.enemy_hit_react_duration, seen, func() -> bool: return seen.has("hit"))
	_check("%s flinches on a solid hit" % color, seen.has("hit"), "clips %s" % [seen.keys()])
	for i: int in 30:
		await get_tree().physics_frame

	# 9. death
	var deaths_before: int = _wave_deaths
	var at_death: Vector3 = beast.global_position
	var source := Node3D.new()
	add_child(source)
	source.global_position = at_death - Vector3(2.0, 0.0, 0.0)
	beast.take_damage(beast.max_health * 5.0, source)
	source.queue_free()
	_check("%s plays its death clip" % color, beast.is_dying and beast.visual_anim_player.current_animation == "death",
		"dying %s, playing %s" % [beast.is_dying, beast.visual_anim_player.current_animation])
	_check("%s is not thrown by the killing blow" % color, beast.death_launch == Vector3.ZERO, "launch %s" % beast.death_launch)
	_check("%s's death does not count down the wave" % color, _wave_deaths == deaths_before, "")
	for i: int in 150:
		await get_tree().physics_frame
	_check("%s lies where it fell" % color, _flat(beast.global_position, at_death) < 0.3 and absf(beast.global_position.y - at_death.y) < 0.3,
		"moved %.2fm" % beast.global_position.distance_to(at_death))
	_check("%s stays as a corpse" % color, EnemyBase.corpses().has(beast), "")
	await _shoot(beast, "%s_dead" % color.to_lower())
	beast.queue_free()
	await get_tree().physics_frame


## The size roll: small in the first wave, every size up to the largest later on, and the
## later the wave the bigger the same luck comes out.
func _test_size_roll() -> void:
	print("== size roll")
	var first_cap: float = EnemyBase.BeastDatabase.roll_size(1, 1.0)
	_check("wave 1 rolls no giants", is_equal_approx(first_cap, GameSettings.beast_size_cap_start), "largest %.2f" % first_cap)
	var late_cap: float = EnemyBase.BeastDatabase.roll_size(GameSettings.beast_size_cap_full_wave, 1.0)
	_check("a late wave can roll the largest size", is_equal_approx(late_cap, GameSettings.beast_size_max), "largest %.2f" % late_cap)
	_check("no roll is below 1x", is_equal_approx(EnemyBase.BeastDatabase.roll_size(30, 0.0), 1.0), "")
	var growing: bool = true
	var previous: float = 0.0
	for wave: int in [1, 5, 10, 15, 20, 25, 40]:
		var median: float = EnemyBase.BeastDatabase.roll_size(wave, 0.5)
		growing = growing and median >= previous
		previous = median
	_check("the same luck rolls bigger later", growing and previous > 1.5, "median %.2f at the cap" % previous)


## A giant: drawn at its size with its strength, marked as an alpha, and still a beast that
## bites, uses its special at its own longer reach, and dies.
func _test_giant(color: String, size: float, gap: float) -> void:
	print("== %s giant x%.1f" % [color, size])
	var small: EnemyBase = request_enemy({"color": color, "type": "Beast", "position": HOME + Vector3(-30.0, 0.0, 0.0)}) as EnemyBase
	var beast: EnemyBase = request_enemy({"color": color, "type": "Beast", "position": HOME, "beast_size": size}) as EnemyBase
	for i: int in 30:
		await get_tree().physics_frame
	var meshes: Array[Node] = beast.find_children("*", "MeshInstance3D", true, false)
	var box: AABB = (meshes[0] as MeshInstance3D).global_transform * (meshes[0] as MeshInstance3D).get_aabb()
	var small_meshes: Array[Node] = small.find_children("*", "MeshInstance3D", true, false)
	var small_box: AABB = (small_meshes[0] as MeshInstance3D).global_transform * (small_meshes[0] as MeshInstance3D).get_aabb()
	_check("%s giant is drawn %.0fx as big" % [color, size], absf(box.size.y / small_box.size.y - size) < 0.05,
		"%.2f vs %.2f high" % [box.size.y, small_box.size.y])
	_check("%s giant stands on the ground" % color, absf(box.position.y - beast.global_position.y) < 0.3,
		"underside %.2f above its feet" % (box.position.y - beast.global_position.y))
	var health_ratio: float = beast.max_health / small.max_health
	_check("%s giant is tougher" % color, is_equal_approx(health_ratio, pow(size, GameSettings.beast_size_health_exponent)),
		"%.2fx the health" % health_ratio)
	_check("%s giant hits harder" % color, beast.enemy_data.attack_damage > small.enemy_data.attack_damage * 2.0,
		"%.1f vs %.1f" % [beast.enemy_data.attack_damage, small.enemy_data.attack_damage])
	_check("%s giant is an alpha" % color, beast.health_bar.modifier_label.text == "ALPHA", "tag '%s'" % beast.health_bar.modifier_label.text)
	small.queue_free()

	var dummy: Node3D = Dummy.new()
	add_child(dummy)
	dummy.global_position = beast.global_position + Vector3(0.0, 0.0, gap)
	var result: Dictionary = await _special(beast, dummy, false)
	_check("%s giant uses its special at its reach" % color, result["started"] and result["damage"] > 0.0,
		"started %s, %.1f damage" % [result["started"], result["damage"]])
	var seen: Dictionary = {}
	await _watch(beast, 8.0, seen, func() -> bool: return seen.has("attack"))
	_check("%s giant bites" % color, seen.has("attack"), "clips %s" % [seen.keys()])
	await _shoot_wide(beast, "%s_giant" % color.to_lower(), dummy)
	dummy.queue_free()
	beast.take_damage(beast.max_health * 5.0)
	_check("%s giant dies" % color, beast.is_dying and beast.visual_anim_player.current_animation == "death", "")
	for i: int in 90:
		await get_tree().physics_frame
	beast.queue_free()
	await get_tree().physics_frame


## What a kill pays: an elite's XP and mana of its biome's colour at 1x, more the bigger it was,
## and - with the chance forced to certain - its biome's piece of equipment.
func _test_rewards() -> void:
	print("== rewards")
	var chance: float = GameSettings.equipment_beast_drop_chance
	GameSettings.equipment_beast_drop_chance = 0.0
	for size: float in [1.0, 2.5]:
		var beast: EnemyBase = await _spawn_quiet("Blue", size)
		var xp_before: float = RunState.team_xp
		var mana_before: int = int(RunState.mana_pool["Blue"])
		var other_before: int = int(RunState.mana_pool["Red"])
		beast.take_damage(beast.max_health * 5.0)
		var xp: float = RunState.team_xp - xp_before
		var mana: int = int(RunState.mana_pool["Blue"]) - mana_before
		var scale: float = pow(size, GameSettings.beast_reward_size_exponent)
		_check("a %.1fx beast pays its XP" % size, is_equal_approx(xp, GameSettings.xp_per_beast * scale), "%.1f XP" % xp)
		_check("a %.1fx beast pays its biome's mana" % size, mana == int(round(GameSettings.mana_per_beast * scale))
			and int(RunState.mana_pool["Red"]) == other_before, "%d Blue mana" % mana)
		await _settle_and_free(beast)
	GameSettings.equipment_beast_drop_chance = 1.0
	RunState.equipment_unlocked.erase("explorers_scope")
	var carrier: EnemyBase = await _spawn_quiet("Blue", 1.0)
	carrier.take_damage(carrier.max_health * 5.0)
	_check("a beast can carry its biome's piece", RunState.is_equipment_unlocked("explorers_scope"),
		"unlocked %s" % [RunState.equipment_unlocked])
	await _settle_and_free(carrier)
	GameSettings.equipment_beast_drop_chance = chance


## The beast pieces on a wearer's melee hits, as the server judges them.
func _test_equipment() -> void:
	print("== beast equipment")
	var wearer: Node3D = Dummy.new()
	add_child(wearer)
	wearer.global_position = HOME + Vector3(30.0, 0.0, 30.0)
	var hit: float = 10.0

	# Bonesplitter: double into an untouched enemy, plain after.
	wearer.equipment = {"bonesplitter": GameSettings.equipment_bonesplitter_bonus}
	var beast: EnemyBase = await _spawn_quiet("Green", 1.0)
	var before: float = beast.health
	beast.take_damage(hit, wearer, true)
	var first: float = before - beast.health
	before = beast.health
	beast.take_damage(hit, wearer, true)
	var second: float = before - beast.health
	_check("Bonesplitter doubles the first cut", is_equal_approx(first, hit * (1.0 + GameSettings.equipment_bonesplitter_bonus)) \
		and is_equal_approx(second, hit), "%.1f then %.1f" % [first, second])

	# Leonin Scimitar: more into an enemy busy with someone else.
	wearer.equipment = {"leonin_scimitar": GameSettings.equipment_leonin_scimitar_bonus}
	var ally: Node3D = Dummy.new()
	add_child(ally)
	ally.global_position = beast.global_position + Vector3(0.0, 0.0, 2.0)
	beast.current_target = ally
	before = beast.health
	beast.take_damage(hit, wearer, true)
	var busy: float = before - beast.health
	beast.current_target = wearer
	before = beast.health
	beast.take_damage(hit, wearer, true)
	var facing: float = before - beast.health
	_check("Leonin Scimitar cuts deeper into an enemy busy elsewhere",
		is_equal_approx(busy, hit * (1.0 + GameSettings.equipment_leonin_scimitar_bonus)) and is_equal_approx(facing, hit),
		"%.1f busy, %.1f facing the wearer" % [busy, facing])
	ally.queue_free()

	# Vorrac Battlehorns: a stagger, not a lock.
	wearer.equipment = {"vorrac_battlehorns": GameSettings.equipment_vorrac_battlehorns_stun}
	beast.stun_timer = 0.0
	beast.take_damage(hit, wearer, true)
	var stunned: float = beast.stun_timer
	beast.stun_timer = 0.0
	beast.take_damage(hit, wearer, true)
	_check("Vorrac Battlehorns stagger a beast", is_equal_approx(stunned, GameSettings.equipment_vorrac_battlehorns_stun), "stun %.2f" % stunned)
	_check("...and not again within their cooldown", beast.stun_timer == 0.0, "stun %.2f" % beast.stun_timer)

	# Nim Deathmantle: the beast it kills rises as the wearer's ghoul.
	wearer.equipment = {"nim_deathmantle": GameSettings.equipment_nim_deathmantle_duration}
	var effects: int = get_node("Effects").get_child_count()
	beast.take_damage(beast.max_health * 5.0, wearer, true)
	await get_tree().physics_frame
	var risen: Array = get_node("Effects").get_children().filter(func(n: Node) -> bool: return n is TemporaryAlly)
	_check("Nim Deathmantle raises the beast it kills", get_node("Effects").get_child_count() > effects and not risen.is_empty(),
		"%d allies standing" % risen.size())
	if not risen.is_empty():
		var ghoul: TemporaryAlly = risen[risen.size() - 1]
		var life: float = float(ghoul.get("_life_timer"))
		_check("...for its duration", absf(life - GameSettings.equipment_nim_deathmantle_duration) < 0.5,
			"%.2fs to live" % life)
	for node: Node in risen:
		node.queue_free()
	await _settle_and_free(beast)
	wearer.queue_free()

	# The pieces themselves.
	var pool: Array[String] = []
	for color: String in ["white", "blue", "black", "red", "green"]:
		pool.append_array(EquipmentDatabase.pool_for_beast(color))
	_check("every biome's beast carries one piece", pool.size() == 5 and EquipmentDatabase.pool_for("green").size() == 2,
		"beast pool %s" % [pool])
	_check("beast pieces say where they are found", EquipmentDatabase.source_text("bonesplitter").contains("Red biome"),
		EquipmentDatabase.source_text("bonesplitter"))


## A beast with nobody about, for poking at directly.
func _spawn_quiet(color: String, size: float) -> EnemyBase:
	var beast: EnemyBase = request_enemy({"color": color, "type": "Beast", "position": HOME, "beast_size": size}) as EnemyBase
	for i: int in 10:
		await get_tree().physics_frame
	return beast


func _settle_and_free(beast: EnemyBase) -> void:
	for i: int in 10:
		await get_tree().physics_frame
	beast.queue_free()
	await get_tree().physics_frame


## A wider frame than _shoot, with the dummy in it for scale.
func _shoot_wide(beast: EnemyBase, label: String, dummy: Node3D) -> void:
	if _shots_dir == "":
		return
	var cam := Camera3D.new()
	add_child(cam)
	var mid: Vector3 = (beast.global_position + dummy.global_position) * 0.5
	cam.global_position = mid + beast.global_basis.x * 14.0 * beast._beast_size * 0.5 + Vector3.UP * 4.0 * beast._beast_size * 0.5
	cam.look_at(mid + Vector3.UP * 1.5)
	cam.current = true
	for i: int in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots_dir.path_join(label + ".png"))
	cam.queue_free()


## Waits for the beast's special to start at the dummy and plays it out. With `dodge`, the
## dummy steps well clear the moment the mark is down. Returns whether it started, whether a
## mark was drawn, the damage the dummy took during it, and how far the beast was carried.
func _special(beast: EnemyBase, dummy: Node3D, dodge: bool) -> Dictionary:
	var result: Dictionary = {"started": false, "marked": false, "damage": 0.0, "travel": 0.0}
	var started: float = await _watch(beast, 4.0, {}, func() -> bool: return not beast._beast_special.is_empty())
	if started < 0.0:
		return result
	result["started"] = true
	result["marked"] = not beast._cast_indicators.is_empty()
	var start: Vector3 = beast.global_position
	var before: float = dummy.damage_taken
	if dodge:
		var away: Vector3 = beast.global_basis.x * 7.0
		dummy.global_position += away
	var shot_taken: bool = false
	while not beast._beast_special.is_empty() and not beast.is_dying:
		await get_tree().physics_frame
		if not shot_taken and not dodge and bool(beast._beast_special.get("hit", false)):
			shot_taken = true
			await _shoot(beast, "%s_special" % beast.enemy_data.color_identity.to_lower())
	result["damage"] = dummy.damage_taken - before
	result["travel"] = _flat(beast.global_position, start)
	return result


func _until_home(beast: EnemyBase, seconds: float) -> void:
	await _watch(beast, seconds, {}, func() -> bool:
		return _flat(beast.global_position, HOME) <= HOME_TOLERANCE \
			and beast.current_target == beast.target_crystal \
			and Vector2(beast.velocity.x, beast.velocity.z).length() < 0.05)


func _check_model(color: String, beast: EnemyBase) -> void:
	_check("%s is a beast" % color, beast.is_beast() and beast.enemy_data.display_name == EnemyBase.BeastDatabase.display_name(color),
		"class %s, name %s" % [beast.enemy_data.enemy_class, beast.enemy_data.display_name])
	var missing: Array[String] = []
	for clip: String in CLIPS:
		if beast.visual_anim_player == null or not beast.visual_anim_player.has_animation(clip):
			missing.append(clip)
	_check("%s has all seven clips" % color, missing.is_empty(), "missing %s" % [missing])
	var meshes: Array[Node] = beast.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		_check("%s has a model" % color, false, "no mesh")
		return
	var mesh: MeshInstance3D = meshes[0] as MeshInstance3D
	var box: AABB = mesh.global_transform * mesh.get_aabb()
	var length: float = maxf(box.size.x, box.size.z)
	_check("%s is drawn at its own size" % color, box.size.y > 0.8 and box.size.y < 1.5 and length > 2.3 and length < 3.3,
		"%.2f high, %.2f long" % [box.size.y, length])
	_check("%s stands on the ground" % color, absf(box.position.y - beast.global_position.y) < 0.12,
		"underside %.2f above its feet" % (box.position.y - beast.global_position.y))
	var centre: Vector3 = box.get_center()
	_check("%s's model is on its body" % color, _flat(centre, beast.global_position) < 0.6,
		"model centre %.2fm off the body" % _flat(centre, beast.global_position))


## Runs physics for up to `seconds`, noting every clip the beast plays, and stops early when
## `until` says so. Returns when it stopped, or -1 if it never did.
func _watch(beast: EnemyBase, seconds: float, seen: Dictionary, until: Callable = Callable()) -> float:
	var elapsed: float = 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if beast.visual_anim_player != null and beast.visual_anim_player.current_animation != "":
			seen[beast.visual_anim_player.current_animation] = true
		if until.is_valid() and until.call():
			return elapsed
	return -1.0


## A frame of the beast from the front-left, saved to the shots folder when there is one.
func _shoot(beast: EnemyBase, label: String, wait: float = 0.0) -> void:
	if _shots_dir == "":
		return
	var cam := Camera3D.new()
	add_child(cam)
	var at: Vector3 = beast.global_position
	cam.global_position = at + beast.global_basis.z * 3.4 + beast.global_basis.x * 2.6 + Vector3.UP * 1.6
	cam.look_at(at + Vector3.UP * 0.6)
	cam.current = true
	var elapsed: float = 0.0
	while elapsed < maxf(wait, 0.05):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots_dir.path_join(label + ".png"))
	cam.queue_free()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s %s (%s)" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s: %s" % [what, detail])
